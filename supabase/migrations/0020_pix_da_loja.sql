-- =====================================================================
-- GG Vitrine — 0020: chave PIX da loja no cardápio
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança. Precisa da 0018 antes.
--
-- O lojista cadastra a chave PIX em Funcionamento. Na vitrine, quem
-- escolhe pagar por PIX vê a chave (com botão de copiar) e paga direto
-- pro lojista. A plataforma não intermedeia nem confere o pagamento.
-- =====================================================================

alter table businesses
  add column if not exists pix_key  text check (pix_key is null or char_length(pix_key) <= 120),
  add column if not exists pix_name text check (pix_name is null or char_length(pix_name) <= 80);  -- nome que aparece no PIX

grant update (pix_key, pix_name) on businesses to authenticated;

-- ---------------------------------------------------------------------
-- Página pública: manda a chave PIX junto com os dados da loja
-- (mesma função da 0018, com 'pix_key' e 'pix_name' a mais em 'store')
-- ---------------------------------------------------------------------
create or replace function get_public_business(p_slug text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', b.id, 'slug', b.slug, 'kind', b.kind, 'name', b.name, 'category', b.category,
    'description', b.description, 'phone', b.phone, 'address', b.address,
    'logo_url', b.logo_url, 'primary_color', b.primary_color, 'timezone', b.timezone,
    'staff_label', b.staff_label,
    'live', business_is_live(b.id),
    'features', coalesce((select to_jsonb(p.features)
                            from subscriptions s join plans p on p.id = s.plan_id
                           where s.owner_id = b.created_by), '[]'::jsonb),
    'services', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'name', s.name, 'description', s.description,
               'price', s.price, 'duration_min', s.duration_min) order by s.name)
        from services s where s.business_id = b.id and s.active), '[]'::jsonb),
    'professionals', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'name', p.name, 'photo_url', p.photo_url,
               'service_ids', coalesce((select jsonb_agg(ps.service_id)
                                          from professional_services ps
                                         where ps.professional_id = p.id), '[]'::jsonb)) order by p.name)
        from professionals p where p.business_id = b.id and p.active), '[]'::jsonb),
    'menu', case when b.kind = 'cardapio' then coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id, 'name', c.name,
               'items', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'id', i.id, 'name', i.name, 'description', i.description,
                          'price', i.price, 'photo_url', i.photo_url, 'available', i.available)
                        order by i.sort_order, i.name)
                   from menu_items i where i.category_id = c.id), '[]'::jsonb))
             order by c.sort_order, c.name)
        from menu_categories c where c.business_id = b.id and c.active), '[]'::jsonb) end,
    'store', case when b.kind = 'cardapio' then jsonb_build_object(
      'accepting_orders', b.accepting_orders,
      'open_now',         is_store_open(b.id),
      'pickup_enabled',   b.pickup_enabled,
      'delivery_enabled', b.delivery_enabled,
      'delivery_fee',     b.delivery_fee,
      'delivery_other',   b.delivery_other,
      'pix_key',          b.pix_key,
      'pix_name',         b.pix_name,
      'min_order',        b.min_order,
      'delivery_area',    b.delivery_area,
      'zones', coalesce((
        select jsonb_agg(jsonb_build_object('id', z.id, 'name', z.name, 'fee', z.fee)
                         order by z.sort_order, z.name)
          from delivery_zones z where z.business_id = b.id), '[]'::jsonb),
      'hours', coalesce((
        select jsonb_agg(jsonb_build_object('weekday', h.weekday, 'start', h.start_time, 'end', h.end_time)
                         order by h.weekday, h.start_time)
          from store_hours h where h.business_id = b.id), '[]'::jsonb)) end,
    'links', coalesce((
      select jsonb_agg(jsonb_build_object('id', l.id, 'label', l.label, 'url', l.url, 'icon', l.icon)
                       order by l.sort_order, l.label)
        from business_links l where l.business_id = b.id), '[]'::jsonb),
    'gallery', coalesce((
      select jsonb_agg(jsonb_build_object('id', g.id, 'url', g.url, 'caption', g.caption)
                       order by g.sort_order, g.created_at desc)
        from gallery_photos g where g.business_id = b.id), '[]'::jsonb),
    'reviews', case when has_feature(b.id, 'avaliacoes') then jsonb_build_object(
      'average', (select round(avg(r.rating), 1) from reviews r where r.business_id = b.id and r.status = 'approved'),
      'count',   (select count(*) from reviews r where r.business_id = b.id and r.status = 'approved'),
      'latest',  coalesce((
        select jsonb_agg(x order by x.created_at desc) from (
          select r.author_name, r.rating, r.comment, r.reply, r.created_at
            from reviews r where r.business_id = b.id and r.status = 'approved'
           order by r.created_at desc limit 12) x), '[]'::jsonb)) end,
    'loyalty', (select jsonb_build_object('required', lp.stamps_required, 'reward', lp.reward)
                  from loyalty_programs lp
                 where lp.business_id = b.id and lp.active and has_feature(b.id, 'fidelidade')))
  from businesses b
  where b.slug = lower(p_slug) and b.status = 'approved'
$$;
