-- =====================================================================
-- GG Vitrine — 0023: modo fila (ordem de chegada)
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança. Precisa da 0016 antes.
--
-- Para negócios que não trabalham com horário marcado (lava-jato, por
-- exemplo): o cliente escolhe o serviço e entra na fila do dia. A vitrine
-- mostra quantos estão na frente e a previsão de atendimento. O dono
-- encerra a entrada de novos clientes quando quiser (vale só pro dia) e
-- pode definir horário e dias em que a fila abre sozinha.
--
-- businesses.kind ganha o valor 'fila'. Os serviços (preço e tempo) são os
-- mesmos da agenda.
-- =====================================================================

alter table businesses drop constraint if exists businesses_kind_check;
alter table businesses add constraint businesses_kind_check check (kind in ('agenda', 'cardapio', 'fila'));

alter table businesses
  add column if not exists queue_slots      int      not null default 1,   -- quantos atendidos ao mesmo tempo
  add column if not exists queue_open_time  time,                          -- fila abre sozinha a partir de
  add column if not exists queue_close_time time,                          -- e para de aceitar às
  add column if not exists queue_weekdays   smallint[] not null default '{1,2,3,4,5,6}',  -- 0 = domingo
  add column if not exists queue_closed_on  date;                          -- "encerrar por hoje"
alter table businesses drop constraint if exists businesses_queue_slots_check;
alter table businesses add constraint businesses_queue_slots_check check (queue_slots between 1 and 20);

grant update (queue_slots, queue_open_time, queue_close_time, queue_weekdays, queue_closed_on)
  on businesses to authenticated;

create table if not exists queue_entries (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references businesses (id) on delete cascade,
  service_day   date not null,
  number        int  not null,
  service_id    uuid references services (id) on delete set null,
  service_name  text not null check (char_length(service_name) between 1 and 80),
  price         numeric(10,2) not null default 0 check (price >= 0),
  duration_min  int  not null default 30 check (duration_min between 5 and 720),
  customer_name text not null check (char_length(customer_name) between 1 and 80),
  phone         text not null default '',
  vehicle       text check (char_length(vehicle) <= 80),
  notes         text check (char_length(notes) <= 500),
  source        text not null default 'site' check (source in ('site', 'balcao')),
  status        text not null default 'aguardando'
                check (status in ('aguardando', 'atendendo', 'pronto', 'cancelado')),
  canceled_by   text check (canceled_by in ('cliente', 'loja')),
  created_at    timestamptz not null default now(),
  started_at    timestamptz,
  finished_at   timestamptz,
  unique (business_id, service_day, number)
);
create index if not exists queue_entries_business_day_idx on queue_entries (business_id, service_day, number);
create index if not exists queue_entries_business_created_idx on queue_entries (business_id, created_at desc);

alter table queue_entries enable row level security;
drop policy if exists queue_entries_read   on queue_entries;
drop policy if exists queue_entries_insert on queue_entries;
drop policy if exists queue_entries_update on queue_entries;
drop policy if exists queue_entries_delete on queue_entries;
create policy queue_entries_read   on queue_entries for select using (is_member(business_id) or is_platform_admin());
create policy queue_entries_insert on queue_entries for insert with check (can_manage(business_id));
create policy queue_entries_update on queue_entries for update using (can_manage(business_id)) with check (can_manage(business_id));
create policy queue_entries_delete on queue_entries for delete using (can_manage(business_id));

-- Dia de hoje no fuso do negócio.
create or replace function _queue_today(p_business uuid) returns date
language sql stable security definer set search_path = public as $$
  select (now() at time zone coalesce(b.timezone, 'America/Sao_Paulo'))::date from businesses b where b.id = p_business
$$;

-- Senha do dia e horários de início/fim preenchidos sozinhos.
create or replace function queue_entries_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.service_day := _queue_today(new.business_id);
    perform pg_advisory_xact_lock(hashtext('fila' || new.business_id::text));
    select coalesce(max(number), 0) + 1 into new.number
      from queue_entries where business_id = new.business_id and service_day = new.service_day;
    if new.status = 'atendendo' then new.started_at := now(); end if;
    if new.status = 'pronto' then new.started_at := now(); new.finished_at := now(); end if;
  else
    new.business_id := old.business_id;
    new.service_day := old.service_day;
    new.number := old.number;
    if new.status = 'atendendo' and old.status <> 'atendendo' then new.started_at := now(); new.finished_at := null; end if;
    if new.status = 'pronto' and old.status <> 'pronto' then
      new.started_at := coalesce(new.started_at, now());
      new.finished_at := now();
    end if;
    if new.status = 'aguardando' then new.started_at := null; new.finished_at := null; end if;
  end if;
  return new;
end $$;
revoke execute on function queue_entries_stamp() from public, anon, authenticated;
drop trigger if exists queue_entries_stamp on queue_entries;
create trigger queue_entries_stamp before insert or update on queue_entries
  for each row execute function queue_entries_stamp();

-- A fila está aceitando gente agora? (dia da semana, horário e "encerrar por hoje")
create or replace function queue_is_open(p_business uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select b.kind = 'fila'
     and business_is_live(b.id)
     and b.queue_closed_on is distinct from l.day
     and extract(dow from l.day)::smallint = any (b.queue_weekdays)
     and (b.queue_open_time  is null or l.t >= b.queue_open_time)
     and (b.queue_close_time is null or l.t <  b.queue_close_time)
    from businesses b,
         lateral (select (now() at time zone coalesce(b.timezone, 'America/Sao_Paulo'))::date as day,
                         (now() at time zone coalesce(b.timezone, 'America/Sao_Paulo'))::time as t) l
   where b.id = p_business
$$;

-- Espera estimada (minutos) de quem está atrás da senha p_before (null =
-- quem entrar agora). Simula os boxes: cada carro vai pro que libera primeiro.
create or replace function _queue_wait(p_business uuid, p_before int default null) returns int
language plpgsql stable security definer set search_path = public as $$
declare
  v_slots numeric[];
  v_day   date := _queue_today(p_business);
  r       record;
  m       int;
  k       int;
begin
  select array_fill(0::numeric, array[greatest(queue_slots, 1)]) into v_slots from businesses where id = p_business;
  for r in
    select e.duration_min, e.status, e.started_at
      from queue_entries e
     where e.business_id = p_business and e.service_day = v_day
       and (e.status = 'atendendo' or (e.status = 'aguardando' and (p_before is null or e.number < p_before)))
     order by (e.status = 'atendendo') desc, e.number
  loop
    m := 1;
    for k in 2 .. array_length(v_slots, 1) loop
      if v_slots[k] < v_slots[m] then m := k; end if;
    end loop;
    v_slots[m] := v_slots[m] + case when r.status = 'atendendo'
      then greatest(r.duration_min - extract(epoch from now() - coalesce(r.started_at, now())) / 60, 0)
      else r.duration_min end;
  end loop;
  m := 1;
  for k in 2 .. array_length(v_slots, 1) loop
    if v_slots[k] < v_slots[m] then m := k; end if;
  end loop;
  return ceil(v_slots[m])::int;
end $$;
revoke execute on function _queue_wait(uuid, int) from public, anon, authenticated;

-- Situação da fila pra vitrine.
create or replace function queue_public(p_business uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'open',       queue_is_open(b.id),
    'closed_today', b.queue_closed_on = _queue_today(b.id),
    'waiting',    (select count(*) from queue_entries e
                    where e.business_id = b.id and e.service_day = _queue_today(b.id) and e.status = 'aguardando'),
    'in_service', (select count(*) from queue_entries e
                    where e.business_id = b.id and e.service_day = _queue_today(b.id) and e.status = 'atendendo'),
    'wait_min',   _queue_wait(b.id, null),
    'open_time',  b.queue_open_time,
    'close_time', b.queue_close_time,
    'weekdays',   b.queue_weekdays)
  from businesses b where b.id = p_business and b.kind = 'fila'
$$;
grant execute on function queue_public(uuid) to anon, authenticated;

-- Entrar na fila pela vitrine.
create or replace function join_queue(p_business uuid, p_service uuid, p_name text, p_phone text,
                                      p_vehicle text default null, p_notes text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s       services;
  v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_old   queue_entries;
  v_new   queue_entries;
begin
  if not queue_is_open(p_business) then
    raise exception 'Novos serviços encerrados por hoje.';
  end if;
  if coalesce(trim(p_name), '') = '' or length(v_phone) < 8 then
    raise exception 'Informe seu nome e WhatsApp.';
  end if;
  select * into s from services where id = p_service and business_id = p_business and active;
  if not found then raise exception 'Escolha um serviço.'; end if;

  -- Mesmo WhatsApp já na fila hoje: devolve a senha que ele já tem.
  select * into v_old from queue_entries
   where business_id = p_business and service_day = _queue_today(p_business)
     and status in ('aguardando', 'atendendo')
     and regexp_replace(phone, '\D', '', 'g') = v_phone
   order by number limit 1;
  if found then
    return jsonb_build_object('id', v_old.id, 'number', v_old.number, 'existing', true);
  end if;

  insert into queue_entries (business_id, service_id, service_name, price, duration_min,
                             customer_name, phone, vehicle, notes, source)
  values (p_business, s.id, s.name, s.price, s.duration_min, left(trim(p_name), 80), left(trim(p_phone), 30),
          nullif(left(trim(coalesce(p_vehicle, '')), 80), ''), nullif(left(trim(coalesce(p_notes, '')), 500), ''), 'site')
  returning * into v_new;
  return jsonb_build_object('id', v_new.id, 'number', v_new.number, 'existing', false);
end $$;
grant execute on function join_queue(uuid, uuid, text, text, text, text) to anon, authenticated;

-- Acompanhar a senha (o id é um uuid que só quem entrou na fila conhece).
create or replace function queue_ticket(p_entry uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'number', e.number, 'status', e.status, 'service_name', e.service_name,
    'price', e.price, 'customer_name', e.customer_name, 'vehicle', e.vehicle,
    'service_day', e.service_day, 'created_at', e.created_at, 'canceled_by', e.canceled_by,
    'ahead', case when e.status = 'aguardando' then
               (select count(*) from queue_entries x
                 where x.business_id = e.business_id and x.service_day = e.service_day
                   and (x.status = 'atendendo' or (x.status = 'aguardando' and x.number < e.number))) end,
    'wait_min', case when e.status = 'aguardando' then _queue_wait(e.business_id, e.number) end)
  from queue_entries e
  where e.id = p_entry and e.created_at > now() - interval '2 days'
$$;
grant execute on function queue_ticket(uuid) to anon, authenticated;

-- O cliente desiste (só enquanto ainda está esperando).
create or replace function leave_queue(p_entry uuid) returns void
language sql security definer set search_path = public as $$
  update queue_entries set status = 'cancelado', canceled_by = 'cliente'
   where id = p_entry and status = 'aguardando' and created_at > now() - interval '2 days'
$$;
grant execute on function leave_queue(uuid) to anon, authenticated;

-- Trocar entre horário marcado e fila (o cardápio não muda por aqui).
create or replace function set_business_mode(p_business uuid, p_mode text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not can_manage(p_business) then raise exception 'Sem permissão.'; end if;
  if p_mode not in ('agenda', 'fila') then raise exception 'Modo inválido.'; end if;
  update businesses set kind = p_mode where id = p_business and kind in ('agenda', 'fila');
end $$;
grant execute on function set_business_mode(uuid, text) to authenticated;
