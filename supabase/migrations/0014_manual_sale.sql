-- =====================================================================
-- GG Vitrine — 0014: registrar venda avulsa (feita fora do link)
--
-- Como aplicar: Supabase > SQL Editor > cole e Run. Idempotente.
--
-- O dono pode registrar vendas que aconteceram fora do agendamento online —
-- ex: cliente passou na loja sem marcar, ou pagou um pacote. A venda vira
-- um agendamento com status 'completed' pra entrar no financeiro.
-- =====================================================================

drop function if exists register_manual_sale(uuid, uuid, uuid, timestamptz, text, text, numeric, text);

create function register_manual_sale(
  p_business       uuid,
  p_service        uuid,
  p_professional   uuid,
  p_at             timestamptz,
  p_customer_name  text,
  p_customer_phone text default null,
  p_price          numeric default null,
  p_notes          text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_duration int;
  v_price    numeric;
  v_phone    text := nullif(regexp_replace(coalesce(p_customer_phone, ''), '\D', '', 'g'), '');
  v_customer uuid;
  v_id       uuid;
begin
  if not can_manage(p_business) then
    raise exception 'Sem permissão.';
  end if;
  if coalesce(trim(p_customer_name), '') = '' then
    raise exception 'Informe o nome do cliente.';
  end if;

  select duration_min, price into v_duration, v_price
    from services where id = p_service and business_id = p_business;
  if not found then
    raise exception 'Serviço não encontrado.';
  end if;
  if p_price is not null then v_price := p_price; end if;

  -- Garante que o profissional é desse estabelecimento.
  if not exists (select 1 from professionals where id = p_professional and business_id = p_business) then
    raise exception 'Profissional não encontrado.';
  end if;

  -- Acha ou cria o cliente pelo telefone. Se não informado, só cria um novo
  -- registro (sem auth_user_id, pra não conflitar com clientes logados).
  if v_phone is not null then
    select id into v_customer from customers
     where business_id = p_business and phone = v_phone
     limit 1;
  end if;

  if v_customer is null then
    insert into customers (business_id, name, phone)
    values (p_business, trim(p_customer_name), v_phone)
    returning id into v_customer;
  end if;

  insert into appointments (business_id, professional_id, service_id, customer_id,
                            starts_at, ends_at, status, price, notes, created_by)
  values (p_business, p_professional, p_service, v_customer,
          p_at, p_at + make_interval(mins => coalesce(v_duration, 30)),
          'completed', v_price, p_notes, auth.uid())
  returning id into v_id;

  return v_id;
exception
  when exclusion_violation then
    -- Já tem outro agendamento nesse horário pro mesmo profissional. Dá 1 min
    -- de diferença pra evitar conflito e tenta de novo.
    insert into appointments (business_id, professional_id, service_id, customer_id,
                              starts_at, ends_at, status, price, notes, created_by)
    values (p_business, p_professional, p_service, v_customer,
            p_at + interval '1 minute',
            p_at + interval '1 minute' + make_interval(mins => coalesce(v_duration, 30)),
            'completed', v_price, p_notes, auth.uid())
    returning id into v_id;
    return v_id;
end $$;
