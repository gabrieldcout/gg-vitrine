-- =====================================================================
-- GG Vitrine — 0022: aceitar pedidos automaticamente
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança. Precisa da 0018 antes.
--
-- Com businesses.auto_accept ligado, o pedido feito pela vitrine já entra
-- como "preparando" (aceito), sem o lojista precisar tocar em nada.
-- O lojista liga/desliga na tela Pedidos.
-- =====================================================================

alter table businesses add column if not exists auto_accept boolean not null default false;
grant update (auto_accept) on businesses to authenticated;

-- place_order: igual à 0018, só muda o status inicial quando auto_accept está ligado.
create or replace function place_order(p_business uuid, p_items jsonb, p_name text, p_phone text, p_mode text,
                                       p_address text default null, p_payment text default 'pix',
                                       p_change numeric default null, p_notes text default null,
                                       p_coupon text default null, p_zone uuid default null)
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

  for v_line in
    select i.id, i.name, i.price, least(greatest((e->>'qty')::int, 1), 99) as qty
      from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) e
      join menu_items i on i.id = (e->>'id')::uuid and i.business_id = p_business and i.available
      join menu_categories c on c.id = i.category_id and c.active
  loop
    v_subtotal := v_subtotal + v_line.price * v_line.qty;
    v_lines := v_lines || jsonb_build_object('id', v_line.id, 'name', v_line.name, 'unit_price', v_line.price,
                                             'qty', v_line.qty, 'total', v_line.price * v_line.qty);
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

  perform pg_advisory_xact_lock(hashtext(p_business::text));
  select coalesce(max(number), 0) + 1 into v_number from orders where business_id = p_business;

  insert into orders (business_id, number, customer_name, phone, mode, address, payment, change_for, notes,
                      subtotal, delivery_fee, discount, total, coupon_code, fee_pending, status)
  values (p_business, v_number, left(trim(p_name), 80), left(trim(p_phone), 30), p_mode,
          case when p_mode = 'entrega' then v_address end, left(coalesce(p_payment, 'pix'), 40), p_change,
          nullif(left(trim(coalesce(p_notes, '')), 500), ''),
          v_subtotal, v_fee, v_discount, greatest(v_subtotal + v_fee - v_discount, 0), v_coupon->>'code', v_pending,
          case when b.auto_accept then 'preparando' else 'novo' end)
  returning id into v_order;

  insert into order_items (order_id, business_id, item_id, name, unit_price, qty, total)
  select v_order, p_business, (l->>'id')::uuid, l->>'name', (l->>'unit_price')::numeric,
         (l->>'qty')::int, (l->>'total')::numeric
    from jsonb_array_elements(v_lines) l;

  return jsonb_build_object('id', v_order, 'number', v_number, 'items', v_lines,
                            'subtotal', v_subtotal, 'delivery_fee', v_fee, 'fee_pending', v_pending,
                            'discount', v_discount, 'total', greatest(v_subtotal + v_fee - v_discount, 0),
                            'coupon', v_coupon->>'code');
end $$;
