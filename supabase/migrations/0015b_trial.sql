-- =====================================================================
-- GG Vitrine — 0015: 7 dias de teste grátis
--
-- Como aplicar: Supabase > SQL Editor > cole e Run. Idempotente.
--
-- Fluxo:
--   * No cadastro, o dono informa CPF.
--   * Edge Function `start-trial` lê o IP e chama a RPC start_trial.
--   * CPF é validado (algoritmo oficial) e guardado com hash único — não dá
--     pra fazer outro trial com o mesmo CPF.
--   * IP pode ter até 3 trials em 24h (bloqueia o 4º, mas deixa cadastrar).
--   * Vitrine fica no ar normal durante o trial (business_is_live aceita).
--   * No dia 8 vira past_due e segue o fluxo normal de bloqueio.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Campos (enum e extensão já vieram na 0015a)
-- ---------------------------------------------------------------------
alter table subscriptions
  add column if not exists trial_until timestamptz,
  add column if not exists trial_cpf   text,
  add column if not exists trial_ip    inet;

-- Unique no CPF (um por conta) — permite null (quem assinou sem trial).
create unique index if not exists subscriptions_trial_cpf_key
  on subscriptions (trial_cpf) where trial_cpf is not null;

-- ---------------------------------------------------------------------
-- Valida CPF pelo algoritmo oficial (dígitos verificadores)
-- ---------------------------------------------------------------------
create or replace function valid_cpf(p_cpf text) returns boolean
language plpgsql immutable set search_path = public as $$
declare
  v text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  v_sum1 int := 0;
  v_sum2 int := 0;
  v_d1 int;
  v_d2 int;
  i int;
begin
  if length(v) <> 11 then return false; end if;
  -- Rejeita 00000000000, 11111111111, etc.
  if v ~ ('^(.)\1{10}$') then return false; end if;
  for i in 1..9 loop
    v_sum1 := v_sum1 + (substr(v, i, 1))::int * (11 - i);
  end loop;
  v_d1 := (v_sum1 * 10) % 11;
  if v_d1 = 10 then v_d1 := 0; end if;
  if v_d1 <> (substr(v, 10, 1))::int then return false; end if;
  for i in 1..10 loop
    v_sum2 := v_sum2 + (substr(v, i, 1))::int * (12 - i);
  end loop;
  v_d2 := (v_sum2 * 10) % 11;
  if v_d2 = 10 then v_d2 := 0; end if;
  return v_d2 = (substr(v, 11, 1))::int;
end $$;

-- ---------------------------------------------------------------------
-- start_trial: cria a subscription do trial (ou falha com motivo claro)
-- ---------------------------------------------------------------------
create or replace function start_trial(p_cpf text, p_ip text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid    uuid := auth.uid();
  v_cpf    text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  v_hash   text;
  v_ip     inet;
  v_recent int;
  v_sub    subscriptions;
  v_plan   text := 'solo';   -- plano default do trial; dá pra trocar depois
begin
  if v_uid is null then
    raise exception 'Faça login primeiro.';
  end if;
  if not valid_cpf(v_cpf) then
    raise exception 'CPF inválido.';
  end if;

  -- CPF: guardamos hash hex (sha256) pra não armazenar o número cru.
  v_hash := encode(digest(v_cpf, 'sha256'), 'hex');

  -- IP: rate-limit por IP (máx 3 trials nas últimas 24h).
  if p_ip is not null and length(trim(p_ip)) > 0 then
    begin
      v_ip := p_ip::inet;
    exception when others then
      v_ip := null;
    end;
  end if;

  if v_ip is not null then
    select count(*) into v_recent from subscriptions
     where trial_ip = v_ip and created_at > now() - interval '24 hours';
    if v_recent >= 3 then
      raise exception 'Muitas tentativas de teste a partir deste local. Tente mais tarde ou assine direto.';
    end if;
  end if;

  -- CPF já usado em outro trial?
  if exists (select 1 from subscriptions where trial_cpf = v_hash) then
    raise exception 'Este CPF já foi usado em um teste grátis. Para continuar, assine um plano.';
  end if;

  -- Verifica se o usuário já tem assinatura.
  select * into v_sub from subscriptions where owner_id = v_uid;
  if found then
    -- Se já tem subscription (pending_payment / canceled), permite virar trial.
    if v_sub.status in ('active', 'past_due', 'trialing') then
      raise exception 'Você já tem uma assinatura ativa.';
    end if;
    update subscriptions set
      status      = 'trialing',
      trial_until = now() + interval '7 days',
      trial_cpf   = v_hash,
      trial_ip    = v_ip,
      plan_id     = coalesce(plan_id, v_plan)
     where id = v_sub.id;
  else
    insert into subscriptions (owner_id, plan_id, status, trial_until, trial_cpf, trial_ip)
    values (v_uid, v_plan, 'trialing', now() + interval '7 days', v_hash, v_ip);
  end if;

  return jsonb_build_object('ok', true, 'trial_until', now() + interval '7 days');
end $$;

-- ---------------------------------------------------------------------
-- business_is_live: aceita trialing como vitrine ao vivo
-- ---------------------------------------------------------------------
create or replace function business_is_live(bid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from businesses b
    join subscriptions s on s.owner_id = b.created_by
    where b.id = bid and b.status = 'approved'
      and (s.status in ('active', 'past_due', 'trialing')
           or (s.status = 'canceled' and s.current_period_end > now())))
$$;

-- ---------------------------------------------------------------------
-- billing_daily: expira trials vencidos (vira past_due, segue bloqueio normal)
-- ---------------------------------------------------------------------
create or replace function billing_daily() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_late    int;
  v_blocked int;
  v_expired int;
begin
  -- Trials que estouraram viram past_due (assinante precisa pagar pra manter).
  update subscriptions
     set status = 'past_due'
   where status = 'trialing' and trial_until < now();
  get diagnostics v_expired = row_count;

  -- Assinaturas pagas por fora (PIX manual) vencidas sem pagamento novo.
  update subscriptions set status = 'past_due'
   where gateway is null and status = 'active' and current_period_end < now();
  get diagnostics v_late = row_count;

  -- 5 dias de tolerância pós-vencimento, depois bloqueia.
  update businesses b
     set status = 'blocked', billing_blocked = true,
         status_reason = 'Pagamento em atraso. Pague a fatura em aberto para reativar sua vitrine.'
    from subscriptions s
   where s.owner_id = b.created_by and b.status = 'approved' and s.status = 'past_due'
     and (
       (s.gateway is null and (coalesce(s.trial_until, s.current_period_end) < now() - interval '5 days'))
       or exists (select 1 from payments p
                   where p.subscription_id = s.id and p.status = 'overdue'
                     and p.due_date < current_date - 5));
  get diagnostics v_blocked = row_count;

  return jsonb_build_object('trials_expirados', v_expired, 'em_atraso', v_late, 'bloqueadas', v_blocked);
end $$;
revoke execute on function billing_daily() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Grant pra RPC
-- ---------------------------------------------------------------------
grant execute on function start_trial(text, text) to authenticated;
