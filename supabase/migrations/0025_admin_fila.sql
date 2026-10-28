-- =====================================================================
-- GG Vitrine — 0025: admin conta os atendimentos da fila
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança. Precisa da 0023 antes.
--
-- Na lista de empresas do admin, negócio em modo fila mostrava 0
-- agendamentos; agora conta os clientes que entraram na fila.
-- =====================================================================

create or replace function admin_list_businesses()
returns table (id uuid, slug text, name text, category text, phone text, status business_status,
               status_reason text, created_at timestamptz, owner_id uuid, owner_email text,
               plan_id text, plan_name text, base_price numeric, subscription_status subscription_status,
               custom_price numeric, discount_amount numeric, discount_until date, discount_note text,
               monthly_price numeric, current_period_end timestamptz, max_businesses int,
               businesses_count bigint, professionals_count bigint, customers_count bigint, activity_count bigint,
               kind text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform assert_platform_admin();
  return query
  select b.id, b.slug, b.name, b.category, b.phone, b.status, b.status_reason, b.created_at,
         b.created_by, u.email::text,
         s.plan_id, p.name, p.base_price, s.status,
         s.custom_price, s.discount_amount, s.discount_until, s.discount_note,
         case when s.id is null then null else effective_price(s) end,
         s.current_period_end, p.max_businesses,
         (select count(*) from businesses x where x.created_by = b.created_by),
         (select count(*) from professionals x where x.business_id = b.id and x.active),
         (select count(*) from customers x     where x.business_id = b.id),
         case when b.kind = 'cardapio' then (select count(*) from orders x        where x.business_id = b.id)
              when b.kind = 'fila'     then (select count(*) from queue_entries x where x.business_id = b.id)
              else (select count(*) from appointments x where x.business_id = b.id) end,
         b.kind
    from businesses b
    left join auth.users u    on u.id = b.created_by
    left join subscriptions s on s.owner_id = b.created_by
    left join plans p         on p.id = s.plan_id
   order by (b.status = 'pending') desc, b.created_at desc;
end $$;
