-- =====================================================================
-- GG Vitrine — 0037: Indique e ganhe
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança.
--
-- Regras:
--   * Cada dono tem um link: ggvitrine.online/?indique=<slug da vitrine>.
--   * Quem se cadastra por ele (o indicado) ganha +10 dias no teste grátis.
--   * Quando o indicado paga a 1ª mensalidade, quem indicou ganha 30% de
--     desconto em UMA mensalidade. Várias indicações = vários meses com 30%
--     (um desconto por fatura, usados em ordem).
--   * O desconto entra na próxima fatura gerada. Se a fatura for apagada,
--     o desconto volta pra fila.
-- =====================================================================

create table if not exists referrals (
  id            uuid primary key default gen_random_uuid(),
  referrer_id   uuid not null references auth.users (id) on delete cascade,  -- quem indicou
  referred_id   uuid not null unique references auth.users (id) on delete cascade, -- quem foi indicado
  referrer_slug text,
  created_at    timestamptz not null default now(),
  bonus_at      timestamptz,   -- quando o indicado ganhou os +10 dias
  paid_at       timestamptz,   -- 1ª mensalidade paga pelo indicado (libera o desconto)
  used_at       timestamptz,   -- quando o desconto foi usado numa fatura de quem indicou
  used_payment  text,          -- fatura que usou o desconto (id do Asaas ou "manual:<id>")
  check (referrer_id <> referred_id)
);
create index if not exists referrals_referrer_idx on referrals (referrer_id);
alter table referrals enable row level security;   -- só acessado pelas funções abaixo

-- Desconto disponível (o mais antigo ainda não usado).
create or replace function referral_credit(p_owner uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select id from referrals
   where referrer_id = p_owner and paid_at is not null and used_payment is null
   order by paid_at limit 1
$$;

-- Preço do plano sem o desconto de indicação (preço negociado e desconto do admin continuam valendo).
create or replace function base_effective_price(s subscriptions) returns numeric
language sql stable as $$
  select greatest(0,
           coalesce(s.custom_price, p.base_price)
           - case when s.discount_until is null or s.discount_until >= current_date
                  then s.discount_amount else 0 end)
  from plans p where p.id = s.plan_id
$$;

-- Preço do mês: com 30% a menos quando há desconto de indicação na fila.
create or replace function effective_price(s subscriptions) returns numeric
language sql stable as $$
  select case when referral_credit(s.owner_id) is not null
              then round(base_effective_price(s) * 0.7, 2)
              else base_effective_price(s) end
$$;

-- ---------------------------------------------------------------------
-- Cadastro: grava quem indicou (metadado referred_by = slug da vitrine)
-- ---------------------------------------------------------------------
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_meta jsonb := new.raw_user_meta_data;
  v_kind text  := case when new.raw_user_meta_data->>'business_kind' = 'cardapio' then 'cardapio' else 'agenda' end;
  v_id   uuid;
  v_ref  text  := lower(trim(coalesce(new.raw_user_meta_data->>'referred_by', '')));
  v_tel  text  := nullif(regexp_replace(coalesce(new.raw_user_meta_data->>'business_phone', ''), '\D', '', 'g'), '');
begin
  if v_meta ? 'business_name' and v_meta ? 'business_slug' then
    begin
      insert into businesses (name, slug, category, phone, kind, created_by)
      values (trim(v_meta->>'business_name'), lower(trim(v_meta->>'business_slug')),
              v_meta->>'business_category', v_meta->>'business_phone', v_kind, new.id)
      returning id into v_id;
      insert into business_members (business_id, user_id, role) values (v_id, new.id, 'owner');
    exception when others then
      null;
    end;
  end if;

  -- Indicação: não vale indicar a si mesmo (mesma conta ou mesmo telefone).
  if v_ref <> '' then
    begin
      insert into referrals (referrer_id, referred_id, referrer_slug)
      select b.created_by, new.id, b.slug from businesses b
       where b.slug = v_ref and b.created_by <> new.id
         and (v_tel is null or regexp_replace(coalesce(b.phone, ''), '\D', '', 'g') <> v_tel)
       limit 1
      on conflict (referred_id) do nothing;
    exception when others then
      null;
    end;
  end if;
  return new;
end $$;
revoke execute on function handle_new_user() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- +10 dias de teste pro indicado (vale pra qualquer jeito de liberar o teste)
-- ---------------------------------------------------------------------
create or replace function referral_trial_bonus() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_ref uuid;
begin
  if new.status = 'trialing' and new.trial_until is not null
     and (tg_op = 'INSERT' or new.trial_until is distinct from old.trial_until) then
    update referrals set bonus_at = now()
     where referred_id = new.owner_id and bonus_at is null
     returning id into v_ref;
    if v_ref is not null then
      new.trial_until := new.trial_until + interval '10 days';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists referral_trial_bonus on subscriptions;
create trigger referral_trial_bonus before insert or update of trial_until, status on subscriptions
  for each row execute function referral_trial_bonus();

-- ---------------------------------------------------------------------
-- Webhook do Asaas: libera o desconto de quem indicou e aplica nas faturas
-- (também volta a comparar com o valor final, plano + taxa, como na 0006)
-- ---------------------------------------------------------------------
create or replace function billing_webhook(p_event text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s        subscriptions;
  v_status text;
  v_method text;
  v_due    date := (p->>'dueDate')::date;
  v_want   numeric;
  v_base   numeric;
  v_credit uuid;
  v_linked boolean;
begin
  select * into s from subscriptions where gateway_subscription_id = p->>'subscription';
  if not found then
    return jsonb_build_object('ignored', 'assinatura não encontrada');
  end if;

  v_status := case
    when p_event in ('PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED', 'PAYMENT_RECEIVED_IN_CASH') then 'paid'
    when p_event = 'PAYMENT_OVERDUE' then 'overdue'
    when p_event in ('PAYMENT_REFUNDED', 'PAYMENT_PARTIALLY_REFUNDED', 'PAYMENT_CHARGEBACK_REQUESTED') then 'refunded'
    when p_event = 'PAYMENT_DELETED' then 'canceled'
    when p->>'status' in ('CONFIRMED', 'RECEIVED', 'RECEIVED_IN_CASH') then 'paid'
    when p->>'status' = 'OVERDUE' then 'overdue'
    else 'pending' end;
  v_method := case p->>'billingType'
    when 'PIX' then 'pix' when 'BOLETO' then 'boleto' when 'CREDIT_CARD' then 'cartao' else 'a definir' end;

  insert into payments (subscription_id, amount, status, method, due_date, paid_at, gateway_payment_id, invoice_url)
  values (s.id, (p->>'value')::numeric, v_status::payment_status, v_method, v_due,
          case when v_status = 'paid' then now() end, p->>'id', p->>'invoiceUrl')
  on conflict (gateway_payment_id) do update set
    amount      = excluded.amount,
    status      = case when payments.status = 'paid' and excluded.status in ('pending', 'overdue')
                       then payments.status else excluded.status end,
    method      = excluded.method,
    due_date    = excluded.due_date,
    paid_at     = coalesce(payments.paid_at, excluded.paid_at),
    invoice_url = coalesce(excluded.invoice_url, payments.invoice_url);

  if v_status = 'paid' then
    update subscriptions
       set status = 'active',
           current_period_end = greatest(coalesce(current_period_end, now()), (v_due + interval '1 month')::timestamptz)
     where id = s.id;
    update businesses set status = 'approved', status_reason = null, billing_blocked = false
     where created_by = s.owner_id and billing_blocked;
    -- 1ª mensalidade do indicado: libera o desconto de quem indicou.
    update referrals set paid_at = now() where referred_id = s.owner_id and paid_at is null;
  elsif v_status = 'overdue' then
    update subscriptions set status = 'past_due' where id = s.id and status = 'active';
  elsif p_event = 'PAYMENT_DELETED' then
    -- Fatura apagada: o desconto volta pra fila.
    update referrals set used_payment = null, used_at = null where used_payment = p->>'id';
  end if;

  if p_event = 'PAYMENT_CREATED' then
    -- Fatura nova: usa um desconto de indicação, se tiver (uma vez por fatura).
    v_linked := exists (select 1 from referrals where used_payment = p->>'id');
    if not v_linked then
      v_credit := referral_credit(s.owner_id);
      if v_credit is not null then
        update referrals set used_payment = p->>'id', used_at = now() where id = v_credit;
        v_linked := true;
      end if;
    end if;
    v_base := base_effective_price(s);
    if v_linked then v_base := round(v_base * 0.7, 2); end if;
    v_want := v_base + billing_fee(v_base, coalesce(s.billing_method, 'pix'));
    if v_want is not null and v_want <> (p->>'value')::numeric then
      return jsonb_build_object('ok', true, 'adjust_value', v_want);
    end if;
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function billing_webhook(text, jsonb) from public, anon, authenticated;
grant execute on function billing_webhook(text, jsonb) to service_role;

-- ---------------------------------------------------------------------
-- Pagamento lançado à mão pelo admin: mesmas regras
-- ---------------------------------------------------------------------
create or replace function admin_register_payment(p_owner uuid, p_amount numeric, p_months int default 1,
                                                  p_method text default 'manual', p_note text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_sub    subscriptions;
  v_pay    uuid;
  v_credit uuid;
begin
  perform assert_platform_admin();
  select * into v_sub from subscriptions where owner_id = p_owner;
  if not found then
    raise exception 'Essa conta ainda não escolheu um plano.';
  end if;
  insert into payments (subscription_id, amount, status, method, paid_at, note)
  values (v_sub.id, p_amount, 'paid', p_method, now(), p_note)
  returning id into v_pay;
  update subscriptions
     set status = 'active',
         current_period_end = greatest(coalesce(current_period_end, now()), now())
                              + make_interval(months => greatest(p_months, 1))
   where id = v_sub.id;
  update businesses set status = 'approved', status_reason = null, billing_blocked = false
   where created_by = p_owner and billing_blocked;
  -- Desconto de indicação deste dono: conta como usado neste pagamento.
  v_credit := referral_credit(p_owner);
  if v_credit is not null then
    update referrals set used_payment = 'manual:' || v_pay, used_at = now() where id = v_credit;
  end if;
  -- 1ª mensalidade do indicado: libera o desconto de quem indicou.
  update referrals set paid_at = now() where referred_id = p_owner and paid_at is null;
end $$;

-- ---------------------------------------------------------------------
-- Aba "Indique e ganhe" do painel
-- ---------------------------------------------------------------------
create or replace function my_referrals() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'slug', (select slug from businesses where created_by = auth.uid() order by created_at limit 1),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', coalesce(b.name, 'Cadastro em andamento'),
               'created_at', r.created_at,
               'trial', r.bonus_at is not null,
               'paid', r.paid_at is not null,
               'used', r.used_payment is not null) order by r.created_at desc)
        from referrals r
        left join lateral (select name from businesses where created_by = r.referred_id
                            order by created_at limit 1) b on true
       where r.referrer_id = auth.uid()), '[]'::jsonb))
$$;
revoke execute on function my_referrals() from public, anon;
grant execute on function my_referrals() to authenticated;
-- effective_price (lido pelo painel) usa referral_credit, então o painel precisa poder chamar.
revoke execute on function referral_credit(uuid) from public, anon;
grant execute on function referral_credit(uuid) to authenticated, service_role;
