-- =====================================================================
-- GG Vitrine — 0032: adicionais nos produtos do cardápio
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança. Precisa da 0031 antes.
--
-- Cada produto pode ter grupos de adicionais (ex.: "Ingredientes adicionais",
-- escolha até 3: cheddar +R$ 3, catupiry +R$ 3). Ficam num jsonb no próprio
-- produto:
--   [{ id, name, min, max, options: [{ id, name, price, available }] }]
-- O cliente escolhe na vitrine; o preço e os limites são conferidos aqui na
-- place_order. O pedido guarda o que foi escolhido em order_items.addons.
-- =====================================================================

alter table menu_items add column if not exists addon_groups jsonb not null default '[]'::jsonb;
do $$ begin
  alter table menu_items add constraint menu_items_addon_groups_check
    check (jsonb_typeof(addon_groups) = 'array' and jsonb_array_length(addon_groups) <= 20);
exception when duplicate_object then null; end $$;

alter table order_items
  add column if not exists addons jsonb not null default '[]'::jsonb,   -- [{ group, name, price }]
  add column if not exists note   text;                                -- "sem cebola" do item

-- ---------------------------------------------------------------------
-- place_order: mesma da 0031, com adicionais e observação por item
-- ---------------------------------------------------------------------
create or replace function place_order(p_business uuid, p_items jsonb, p_name text, p_phone text, p_mode text,
                                       p_address text default null, p_payment text default 'pix',
                                       p_change numeric default null, p_notes text default null,
                                       p_coupon text default null, p_zone uuid default null,
                                       p_method text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  b          businesses;
  z          delivery_zones;
  v_line     record;
  v_subtotal numeric := 0;
  v_fee      numeric := 0;
  v_pending  boolean := false;
  v_discount numeric := 0;
  v_coupon   jsonb;
  v_number   int;
  v_order    uuid;
  v_lines    jsonb := '[]'::jsonb;
  v_address  text := nullif(left(trim(coalesce(p_address, '')), 300), '');
  v_payment  text := left(coalesce(p_payment, 'pix'), 40);
  v_change   numeric := p_change;
  v_card_fee numeric := 0;
  v_group    jsonb;
  v_chosen   jsonb;
  v_addons   jsonb;
  v_sum      numeric;
  v_count    int;
  v_extra    numeric;
  v_unit     numeric;
begin
  select * into b from businesses where id = p_business;
  if not found or b.kind <> 'cardapio' or not business_is_live(p_business) then
    raise exception 'Esta loja não está recebendo pedidos online.';
  end if;
  if not b.accepting_orders or not is_store_open(p_business) then
    raise exception 'A loja está fechada no momento.';
  end if;
  if coalesce(trim(p_name), '') = '' or length(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')) < 8 then
    raise exception 'Informe seu nome e WhatsApp.';
  end if;
  if p_mode = 'entrega' then
    if not b.delivery_enabled then raise exception 'Esta loja não faz entrega.'; end if;
    if v_address is null then raise exception 'Informe o endereço de entrega.'; end if;
    if exists (select 1 from delivery_zones where business_id = p_business) then
      if p_zone is null then
        -- Bairro fora da lista: só se a loja aceitar; a taxa fica a combinar.
        if not b.delivery_other then raise exception 'Escolha o bairro de entrega.'; end if;
        v_pending := true;
      else
        select * into z from delivery_zones where id = p_zone and business_id = p_business;
        if not found then raise exception 'Escolha o bairro de entrega.'; end if;
        v_fee := z.fee;
      end if;
    else
      v_fee := b.delivery_fee;
    end if;
  elsif p_mode = 'retirada' then
    if not b.pickup_enabled then raise exception 'Esta loja não tem retirada no local.'; end if;
  else
    raise exception 'Escolha retirada ou entrega.';
  end if;

  -- Cada linha: { id, qty, addons: [ids das opções], note }. O mesmo produto
  -- pode vir em várias linhas (com adicionais diferentes).
  for v_line in
    select i.id, i.name, i.price, least(greatest((e->>'qty')::int, 1), 99) as qty,
           coalesce(i.addon_groups, '[]'::jsonb) as groups,
           case when jsonb_typeof(e->'addons') = 'array' then e->'addons' else '[]'::jsonb end as picked,
           nullif(left(trim(coalesce(e->>'note', '')), 200), '') as note
      from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) e
      join menu_items i on i.id = (e->>'id')::uuid and i.business_id = p_business and i.available
      join menu_categories c on c.id = i.category_id and c.active
  loop
    v_addons := '[]'::jsonb;
    v_extra := 0;
    for v_group in select g from jsonb_array_elements(v_line.groups) g loop
      select coalesce(jsonb_agg(jsonb_build_object('group', v_group->>'name', 'name', o->>'name',
                                                   'price', (o->>'price')::numeric)), '[]'::jsonb),
             coalesce(sum((o->>'price')::numeric), 0), count(*)
        into v_chosen, v_sum, v_count
        from jsonb_array_elements(coalesce(v_group->'options', '[]'::jsonb)) o
       where v_line.picked ? (o->>'id') and coalesce((o->>'available')::boolean, true);
      if v_count < coalesce((v_group->>'min')::int, 0) then
        raise exception 'Em "%", escolha pelo menos % opção(ões) de "%".', v_line.name, (v_group->>'min')::int, v_group->>'name';
      end if;
      if nullif(v_group->>'max', '') is not null and v_count > (v_group->>'max')::int then
        raise exception 'Em "%", escolha no máximo % opção(ões) de "%".', v_line.name, (v_group->>'max')::int, v_group->>'name';
      end if;
      v_addons := v_addons || v_chosen;
      v_extra := v_extra + v_sum;
    end loop;
    v_unit := v_line.price + v_extra;
    v_subtotal := v_subtotal + v_unit * v_line.qty;
    v_lines := v_lines || jsonb_build_object('id', v_line.id, 'name', v_line.name, 'unit_price', v_unit,
                                             'qty', v_line.qty, 'total', v_unit * v_line.qty,
                                             'addons', v_addons, 'note', v_line.note);
  end loop;
  if jsonb_array_length(v_lines) = 0 then
    raise exception 'Sua sacola está vazia ou os itens não estão mais disponíveis.';
  end if;
  if v_subtotal < b.min_order then
    raise exception 'O pedido mínimo é %.', _money(b.min_order);
  end if;

  if coalesce(trim(p_coupon), '') <> '' then
    v_coupon := _coupon_lookup(p_business, p_coupon, v_subtotal);
    if not (v_coupon->>'valid')::boolean then
      raise exception '%', v_coupon->>'message';
    end if;
    v_discount := (v_coupon->>'discount')::numeric;
    update coupons set uses = uses + 1 where id = (v_coupon->>'coupon_id')::uuid;
  end if;

  -- Forma de pagamento (vitrine nova manda p_method; a antiga só o texto).
  -- Cartão é pago na maquininha, na entrega ou na retirada, com o acréscimo
  -- que a loja configurou sobre o total.
  if p_method is not null then
    if not (p_method = any(b.payment_methods)) then
      raise exception 'Esta forma de pagamento não está disponível.';
    end if;
    v_payment := case p_method
      when 'pix'      then 'PIX'
      when 'dinheiro' then 'Dinheiro'
      when 'debito'   then 'Cartão de débito'
      when 'credito'  then 'Cartão de crédito'
      else 'PIX' end;
    if p_method in ('debito', 'credito') then
      v_payment := v_payment || case when p_mode = 'entrega' then ' (maquininha na entrega)' else ' (maquininha na retirada)' end;
      -- Acréscimo em cima da compra (produtos, já com desconto), sem a entrega.
      v_card_fee := round(greatest(v_subtotal - v_discount, 0) * b.card_fee_pct / 100, 2);
    end if;
    if p_method <> 'dinheiro' then v_change := null; end if;
  end if;

  perform pg_advisory_xact_lock(hashtext(p_business::text));
  select coalesce(max(number), 0) + 1 into v_number from orders where business_id = p_business;

  insert into orders (business_id, number, customer_name, phone, mode, address, payment, change_for, notes,
                      subtotal, delivery_fee, discount, card_fee, total, coupon_code, fee_pending, status)
  values (p_business, v_number, left(trim(p_name), 80), left(trim(p_phone), 30), p_mode,
          case when p_mode = 'entrega' then v_address end, v_payment, v_change,
          nullif(left(trim(coalesce(p_notes, '')), 500), ''),
          v_subtotal, v_fee, v_discount, v_card_fee, greatest(v_subtotal + v_fee - v_discount, 0) + v_card_fee,
          v_coupon->>'code', v_pending,
          case when b.auto_accept then 'preparando' else 'novo' end)
  returning id into v_order;

  insert into order_items (order_id, business_id, item_id, name, unit_price, qty, total, addons, note)
  select v_order, p_business, (l->>'id')::uuid, l->>'name', (l->>'unit_price')::numeric,
         (l->>'qty')::int, (l->>'total')::numeric, l->'addons', l->>'note'
    from jsonb_array_elements(v_lines) l;

  return jsonb_build_object('id', v_order, 'number', v_number, 'items', v_lines,
                            'subtotal', v_subtotal, 'delivery_fee', v_fee, 'fee_pending', v_pending,
                            'discount', v_discount, 'card_fee', v_card_fee, 'payment', v_payment,
                            'total', greatest(v_subtotal + v_fee - v_discount, 0) + v_card_fee,
                            'coupon', v_coupon->>'code');
end $$;

-- ---------------------------------------------------------------------
-- Página pública: mesma da 0031, com 'addon_groups' em cada produto
-- ---------------------------------------------------------------------
create or replace function get_public_business(p_slug text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', b.id, 'slug', b.slug, 'kind', b.kind, 'name', b.name, 'category', b.category,
    'description', b.description, 'phone', b.phone, 'address', b.address,
    'logo_url', b.logo_url, 'cover_url', b.cover_url, 'primary_color', b.primary_color, 'timezone', b.timezone,
    'staff_label', b.staff_label,
    'live', business_is_live(b.id),
    'features', coalesce((select to_jsonb(p.features)
                            from subscriptions s join plans p on p.id = s.plan_id
                           where s.owner_id = b.created_by), '[]'::jsonb),
    'services', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'name', s.name, 'description', s.description,
               'price', s.price, 'duration_min', s.duration_min, 'quote', s.quote) order by s.name)
        from services s where s.business_id = b.id and s.active and s.online), '[]'::jsonb),
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
                          'price', i.price, 'photo_url', i.photo_url, 'available', i.available,
                          'addon_groups', coalesce(i.addon_groups, '[]'::jsonb))
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
      'payment_methods',  to_jsonb(b.payment_methods),
      'card_fee_pct',     b.card_fee_pct,
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
                 where lp.business_id = b.id and lp.active and has_feature(b.id, 'fidelidade')),
    'promo', case when b.promo_active and coalesce(trim(b.promo_title), '') <> ''
                   and (b.promo_until is null or b.promo_until >= (now() at time zone b.timezone)::date)
                  then jsonb_build_object('title', b.promo_title, 'text', b.promo_text, 'until', b.promo_until) end)
  from businesses b
  where b.slug = lower(p_slug) and b.status = 'approved'
$$;
