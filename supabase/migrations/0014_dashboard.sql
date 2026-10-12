-- =====================================================================
-- GG Vitrine — 0014: RPC do dashboard financeiro
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
--
-- Agrega agendamentos de um estabelecimento num período e devolve:
--   - total_revenue           (soma de preço dos "completed")
--   - total_appointments      (quantidade de "completed")
--   - avg_ticket              (ticket médio)
--   - no_show_rate            (% dos agendamentos marcados que viraram no_show)
--   - revenue_by_day          [{ day, revenue, count }]
--   - top_services            [{ service_id, name, revenue, count }]  top 5
--   - top_customers           [{ customer_id, name, revenue, count }] top 5
--   - revenue_by_professional [{ professional_id, name, revenue, count }]
-- =====================================================================

create or replace function business_dashboard(
  p_business uuid,
  p_start timestamptz,
  p_end timestamptz
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_result jsonb;
  v_total_rev numeric;
  v_total_appts int;
  v_total_noshow int;
  v_total_marked int;
begin
  if not (is_member(p_business) or is_platform_admin()) then
    raise exception 'Sem permissão.';
  end if;

  -- Métricas de topo (concluídos no período).
  select coalesce(sum(a.price), 0), count(*)
    into v_total_rev, v_total_appts
    from appointments a
   where a.business_id = p_business
     and a.status = 'completed'
     and a.starts_at >= p_start and a.starts_at < p_end;

  -- No-show rate: percentual sobre tudo que foi marcado no período
  -- (completed + no_show + canceled).
  select
    count(*) filter (where status = 'no_show'),
    count(*) filter (where status in ('completed', 'no_show', 'canceled'))
    into v_total_noshow, v_total_marked
    from appointments
   where business_id = p_business
     and starts_at >= p_start and starts_at < p_end;

  v_result := jsonb_build_object(
    'total_revenue', v_total_rev,
    'total_appointments', v_total_appts,
    'avg_ticket', case when v_total_appts > 0 then round(v_total_rev / v_total_appts, 2) else 0 end,
    'no_show_rate', case when v_total_marked > 0 then round(100.0 * v_total_noshow / v_total_marked, 1) else 0 end,

    'revenue_by_day', coalesce((
      select jsonb_agg(x order by x.day) from (
        select date_trunc('day', a.starts_at) as day,
               sum(a.price)::numeric as revenue,
               count(*)::int as count
          from appointments a
         where a.business_id = p_business
           and a.status = 'completed'
           and a.starts_at >= p_start and a.starts_at < p_end
         group by 1
      ) x), '[]'::jsonb),

    'top_services', coalesce((
      select jsonb_agg(x order by x.revenue desc) from (
        select a.service_id, s.name,
               sum(a.price)::numeric as revenue,
               count(*)::int as count
          from appointments a
          join services s on s.id = a.service_id
         where a.business_id = p_business
           and a.status = 'completed'
           and a.starts_at >= p_start and a.starts_at < p_end
         group by a.service_id, s.name
         order by sum(a.price) desc
         limit 5
      ) x), '[]'::jsonb),

    'top_customers', coalesce((
      select jsonb_agg(x order by x.revenue desc) from (
        select a.customer_id, c.name,
               sum(a.price)::numeric as revenue,
               count(*)::int as count
          from appointments a
          join customers c on c.id = a.customer_id
         where a.business_id = p_business
           and a.status = 'completed'
           and a.starts_at >= p_start and a.starts_at < p_end
         group by a.customer_id, c.name
         order by sum(a.price) desc
         limit 5
      ) x), '[]'::jsonb),

    'revenue_by_professional', coalesce((
      select jsonb_agg(x order by x.revenue desc) from (
        select a.professional_id, p.name,
               sum(a.price)::numeric as revenue,
               count(*)::int as count
          from appointments a
          join professionals p on p.id = a.professional_id
         where a.business_id = p_business
           and a.status = 'completed'
           and a.starts_at >= p_start and a.starts_at < p_end
         group by a.professional_id, p.name
      ) x), '[]'::jsonb)
  );

  return v_result;
end $$;
