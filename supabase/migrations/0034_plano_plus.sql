-- =====================================================================
-- GG Vitrine — 0034: plano Solo Plus (R$ 39,90) e relatório de visitas
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança. Precisa da 0033 antes.
--
-- Solo Plus = 1 vitrine com tudo do Solo e mais:
--   sem_marca            sem o "Feito com GG Vitrine" no rodapé da vitrine
--   relatorio_visitas    visitas e cliques da vitrine, por dia
--   videos               vídeos na galeria (quem já tinha vídeo continua com ele)
--   suporte_prioritario  atendimento na frente no WhatsApp (e montagem da vitrine)
-- Equipe e Rede ganham os mesmos extras.
-- =====================================================================

insert into plans (id, name, base_price, max_professionals, max_customers, max_businesses, features, sort_order)
values ('plus', 'Solo Plus', 39.90, null, null, 1, array[]::text[], 2)
on conflict (id) do update set name = excluded.name, base_price = excluded.base_price,
                               max_businesses = excluded.max_businesses, sort_order = excluded.sort_order;

-- Recursos: o Plus começa com os do Solo.
update plans set features = (select features from plans where id = 'solo') where id = 'plus';
update plans set sort_order = case id when 'solo' then 1 when 'plus' then 2 when 'equipe' then 3 when 'rede' then 4 else sort_order end;
update plans
   set features = array(select distinct unnest(features || array['sem_marca', 'relatorio_visitas', 'videos', 'suporte_prioritario']))
 where id in ('plus', 'equipe', 'rede');

-- ---------------------------------------------------------------------
-- Visitas e cliques da vitrine. Grava pra todo mundo (quem passar pro Plus
-- já vê o histórico); só quem tem o recurso consegue ler.
-- ---------------------------------------------------------------------
create table if not exists page_events (
  id          bigint generated always as identity primary key,
  business_id uuid not null references businesses (id) on delete cascade,
  kind        text not null check (kind in ('visita', 'whatsapp', 'link', 'pedido', 'agendamento', 'fila')),
  label       text check (label is null or char_length(label) <= 60),
  created_at  timestamptz not null default now()
);
create index if not exists page_events_business_created_idx on page_events (business_id, created_at);
alter table page_events enable row level security;   -- sem policies: só pelas funções abaixo

create or replace function track_event(p_business uuid, p_kind text, p_label text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_kind not in ('visita', 'whatsapp', 'link', 'pedido', 'agendamento', 'fila') then return; end if;
  if not exists (select 1 from businesses where id = p_business and status = 'approved') then return; end if;
  -- Trava contra robô: no máximo 3000 eventos por hora por vitrine.
  if (select count(*) from page_events
       where business_id = p_business and created_at > now() - interval '1 hour') >= 3000 then
    return;
  end if;
  insert into page_events (business_id, kind, label)
  values (p_business, p_kind, nullif(left(trim(coalesce(p_label, '')), 60), ''));
end $$;
grant execute on function track_event(uuid, text, text) to anon, authenticated;

-- Relatório do dono: totais do período, por dia e links mais clicados.
create or replace function visit_stats(p_business uuid, p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_tz    text;
  v_days  int := least(greatest(coalesce(p_days, 30), 1), 365);
  v_from  date;
  v_since timestamptz;
begin
  if not (is_member(p_business) or is_platform_admin()) then raise exception 'Sem permissão.'; end if;
  if not has_feature(p_business, 'relatorio_visitas') then raise exception 'Recurso do plano Solo Plus.'; end if;
  select timezone into v_tz from businesses where id = p_business;
  v_from := (now() at time zone v_tz)::date - (v_days - 1);
  v_since := v_from::timestamp at time zone v_tz;

  return jsonb_build_object(
    'from', v_from,
    'totals', coalesce((
      select jsonb_object_agg(kind, n) from (
        select kind, count(*) as n from page_events
         where business_id = p_business and created_at >= v_since group by kind) t), '{}'::jsonb),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('day', d.day::date, 'visitas', coalesce(e.visitas, 0), 'cliques', coalesce(e.cliques, 0))
                       order by d.day)
        from generate_series(v_from, (now() at time zone v_tz)::date, interval '1 day') as d(day)
        left join (
          select (created_at at time zone v_tz)::date as day,
                 count(*) filter (where kind = 'visita') as visitas,
                 count(*) filter (where kind in ('whatsapp', 'link')) as cliques
            from page_events where business_id = p_business and created_at >= v_since
           group by 1) e on e.day = d.day::date), '[]'::jsonb),
    'links', coalesce((
      select jsonb_agg(jsonb_build_object('label', label, 'n', n) order by n desc) from (
        select coalesce(label, 'Link') as label, count(*) as n from page_events
         where business_id = p_business and created_at >= v_since and kind = 'link'
         group by 1 order by 2 desc limit 8) t), '[]'::jsonb));
end $$;
grant execute on function visit_stats(uuid, int) to authenticated;
