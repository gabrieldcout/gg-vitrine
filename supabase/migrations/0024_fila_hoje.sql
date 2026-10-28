-- =====================================================================
-- GG Vitrine — 0024: fila — "até quando aceitar hoje" e "me avise quando abrir"
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança. Precisa da 0023 antes.
--
-- 1. O dono decide só pro dia de hoje: abrir agora (até um horário ou até
--    ele encerrar) ou encerrar agora. No dia seguinte volta o horário padrão.
-- 2. Com a fila fechada, o cliente deixa o WhatsApp pra ser avisado quando
--    abrir; o dono vê a lista no painel e avisa com um toque.
-- =====================================================================

alter table businesses
  add column if not exists queue_today       date,    -- dia em que vale a escolha abaixo
  add column if not exists queue_today_mode  text,    -- 'aberta' ou 'encerrada'
  add column if not exists queue_today_until time;    -- aberta até (null = até o dono encerrar)
alter table businesses drop constraint if exists businesses_queue_today_mode_check;
alter table businesses add constraint businesses_queue_today_mode_check
  check (queue_today_mode is null or queue_today_mode in ('aberta', 'encerrada'));
grant update (queue_today, queue_today_mode, queue_today_until) on businesses to authenticated;

create or replace function queue_is_open(p_business uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select b.kind = 'fila'
     and business_is_live(b.id)
     and case
           when b.queue_today = l.day and b.queue_today_mode = 'encerrada' then false
           when b.queue_today = l.day and b.queue_today_mode = 'aberta'
             then b.queue_today_until is null or l.t < b.queue_today_until
           else b.queue_closed_on is distinct from l.day
            and extract(dow from l.day)::smallint = any (b.queue_weekdays)
            and (b.queue_open_time  is null or l.t >= b.queue_open_time)
            and (b.queue_close_time is null or l.t <  b.queue_close_time)
         end
    from businesses b,
         lateral (select (now() at time zone coalesce(b.timezone, 'America/Sao_Paulo'))::date as day,
                         (now() at time zone coalesce(b.timezone, 'America/Sao_Paulo'))::time as t) l
   where b.id = p_business
$$;

-- Situação da fila pra vitrine (agora com o horário de hoje e a escolha do dono).
create or replace function queue_public(p_business uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'open',         queue_is_open(b.id),
    'closed_today', (b.queue_today = _queue_today(b.id) and b.queue_today_mode = 'encerrada')
                    or b.queue_closed_on = _queue_today(b.id),
    'today_mode',   case when b.queue_today = _queue_today(b.id) then b.queue_today_mode end,
    'until',        case when b.queue_today = _queue_today(b.id) and b.queue_today_mode = 'aberta'
                         then b.queue_today_until else b.queue_close_time end,
    'waiting',      (select count(*) from queue_entries e
                      where e.business_id = b.id and e.service_day = _queue_today(b.id) and e.status = 'aguardando'),
    'in_service',   (select count(*) from queue_entries e
                      where e.business_id = b.id and e.service_day = _queue_today(b.id) and e.status = 'atendendo'),
    'wait_min',     _queue_wait(b.id, null),
    'open_time',    b.queue_open_time,
    'close_time',   b.queue_close_time,
    'weekdays',     b.queue_weekdays)
  from businesses b where b.id = p_business and b.kind = 'fila'
$$;
grant execute on function queue_public(uuid) to anon, authenticated;

-- "Me avise quando abrir"
create table if not exists queue_notify (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 80),
  phone       text not null check (char_length(phone) between 8 and 30),
  created_at  timestamptz not null default now(),
  notified_at timestamptz
);
create index if not exists queue_notify_business_idx on queue_notify (business_id, created_at);

alter table queue_notify enable row level security;
drop policy if exists queue_notify_read   on queue_notify;
drop policy if exists queue_notify_update on queue_notify;
drop policy if exists queue_notify_delete on queue_notify;
create policy queue_notify_read   on queue_notify for select using (is_member(business_id) or is_platform_admin());
create policy queue_notify_update on queue_notify for update using (can_manage(business_id)) with check (can_manage(business_id));
create policy queue_notify_delete on queue_notify for delete using (can_manage(business_id));

create or replace function queue_notify_me(p_business uuid, p_name text, p_phone text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
  if not exists (select 1 from businesses where id = p_business and kind = 'fila') then
    raise exception 'Fila não encontrada.';
  end if;
  if coalesce(trim(p_name), '') = '' or length(v_phone) < 10 then
    raise exception 'Informe seu nome e WhatsApp com DDD.';
  end if;
  -- Mesmo WhatsApp ainda esperando aviso: não duplica.
  if exists (select 1 from queue_notify where business_id = p_business and notified_at is null
               and regexp_replace(phone, '\D', '', 'g') = v_phone) then
    return;
  end if;
  if (select count(*) from queue_notify where business_id = p_business and notified_at is null) >= 300 then
    raise exception 'Lista de avisos cheia. Tente mais tarde.';
  end if;
  insert into queue_notify (business_id, name, phone) values (p_business, left(trim(p_name), 80), left(trim(p_phone), 30));
end $$;
grant execute on function queue_notify_me(uuid, text, text) to anon, authenticated;
