-- Admin: ver quem ainda não confirmou o e-mail e confirmar pelo painel
-- (quando o e-mail de confirmação não chega pro cliente).

-- O retorno mudou (coluna email_confirmed_at), então precisa recriar.
drop function if exists admin_list_businesses();
create function admin_list_businesses()
returns table (id uuid, slug text, name text, category text, phone text, status business_status,
               status_reason text, created_at timestamptz, owner_id uuid, owner_email text,
               plan_id text, plan_name text, base_price numeric, subscription_status subscription_status,
               custom_price numeric, discount_amount numeric, discount_until date, discount_note text,
               monthly_price numeric, current_period_end timestamptz, max_businesses int,
               businesses_count bigint, professionals_count bigint, customers_count bigint, activity_count bigint,
               kind text, email_confirmed_at timestamptz)
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
         b.kind, u.email_confirmed_at
    from businesses b
    left join auth.users u    on u.id = b.created_by
    left join subscriptions s on s.owner_id = b.created_by
    left join plans p         on p.id = s.plan_id
   order by (u.email_confirmed_at is null) desc, (b.status = 'pending') desc, b.created_at desc;
end $$;
revoke all on function admin_list_businesses() from public, anon;
grant execute on function admin_list_businesses() to authenticated;

create or replace function admin_confirm_email(p_owner uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_platform_admin();
  update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now()) where id = p_owner;
end $$;
revoke all on function admin_confirm_email(uuid) from public, anon;
grant execute on function admin_confirm_email(uuid) to authenticated;
