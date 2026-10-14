-- =====================================================================
-- GG Vitrine — 0016: volta o cardápio online (pedidos)
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança. Precisa da 0015a/0015b antes.
--
-- A 0007 tinha deixado o sistema só de agendamento. Aqui o estabelecimento
-- volta a ter um tipo (businesses.kind):
--   'agenda'   → agendamento de horários (o que já existe)
--   'cardapio' → cardápio online: cliente monta a sacola na vitrine, o
--                pedido fica salvo no painel e vai pro WhatsApp da loja.
--
-- Os planos (Solo / Equipe / Rede) valem igual pros dois tipos. O tipo sai
-- do segmento escolhido no cadastro.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tipo do estabelecimento e configurações da loja
-- ---------------------------------------------------------------------
alter table businesses
  add column if not exists kind             text not null default 'agenda',
  add column if not exists accepting_orders boolean not null default true,     -- pausa manual ("fechado agora")
  add column if not exists pickup_enabled   boolean not null default true,
  add column if not exists delivery_enabled boolean not null default false,
  add column if not exists delivery_fee     numeric(10,2) not null default 0,
  add column if not exists min_order        numeric(10,2) not null default 0,
  add column if not exists delivery_area    text;                              -- ex.: "Centro e bairros próximos"

do $$ begin
  alter table businesses add constraint businesses_kind_check check (kind in ('agenda', 'cardapio'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table businesses add constraint businesses_delivery_fee_check check (delivery_fee >= 0);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table businesses add constraint businesses_min_order_check check (min_order >= 0);
exception when duplicate_object then null; end $$;

grant update (accepting_orders, pickup_enabled, delivery_enabled, delivery_fee, min_order, delivery_area)
  on businesses to authenticated;

-- ---------------------------------------------------------------------
-- Cardápio, horário da loja e pedidos
-- ---------------------------------------------------------------------
create table if not exists menu_categories (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 60),
  sort_order  int not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (business_id, id)
);

create table if not exists menu_items (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  category_id uuid not null,
  name        text not null check (char_length(name) between 1 and 80),
  description text,
  price       numeric(10,2) not null check (price >= 0),
  photo_url   text,
  available   boolean not null default true,   -- false = "esgotado"
  sort_order  int not null default 0,
  created_at  timestamptz not null default now(),
  foreign key (business_id, category_id) references menu_categories (business_id, id) on delete cascade
);
create index if not exists menu_items_business_category_idx on menu_items (business_id, category_id);

-- Horário de funcionamento. end_time menor que start_time = vira a noite (ex.: 18:00–02:00).
create table if not exists store_hours (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  weekday     smallint not null check (weekday between 0 and 6),   -- 0 = domingo
  start_time  time not null,
  end_time    time not null,
  check (end_time <> start_time)
);
create index if not exists store_hours_business_idx on store_hours (business_id, weekday);

create table if not exists orders (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references businesses (id) on delete cascade,
  number        int not null,
  customer_name text not null,
  phone         text not null,
  mode          text not null check (mode in ('retirada', 'entrega')),
  address       text,
  payment       text not null,
  change_for    numeric(10,2),
  notes         text,
  subtotal      numeric(10,2) not null,
  delivery_fee  numeric(10,2) not null default 0,
  discount      numeric(10,2) not null default 0,
  total         numeric(10,2) not null,
  coupon_code   text,
  status        text not null default 'novo' check (status in ('novo', 'preparando', 'pronto', 'entregue', 'cancelado')),
  created_at    timestamptz not null default now(),
  unique (business_id, number),
  unique (business_id, id)
);
create index if not exists orders_business_created_idx on orders (business_id, created_at desc);

create table if not exists order_items (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references orders (id) on delete cascade,
  business_id uuid not null references businesses (id) on delete cascade,
  item_id     uuid references menu_items (id) on delete set null,
  name        text not null,
  unit_price  numeric(10,2) not null,
  qty         int not null check (qty between 1 and 99),
  total       numeric(10,2) not null
);
create index if not exists order_items_order_idx on order_items (order_id);

alter table menu_categories enable row level security;
alter table menu_items      enable row level security;
alter table store_hours     enable row level security;
alter table orders          enable row level security;
alter table order_items     enable row level security;

-- Pedido novo só entra pela place_order; o dono lê, muda status e apaga.
do $$
declare t text;
begin
  foreach t in array array['menu_categories', 'menu_items', 'store_hours', 'orders', 'order_items'] loop
    execute format('drop policy if exists %1$s_read on %1$s', t);
    execute format('drop policy if exists %1$s_insert on %1$s', t);
    execute format('drop policy if exists %1$s_update on %1$s', t);
    execute format('drop policy if exists %1$s_delete on %1$s', t);
    execute format('create policy %1$s_read   on %1$s for select using (is_member(business_id) or is_platform_admin())', t);
    execute format('create policy %1$s_insert on %1$s for insert with check (can_manage(business_id))', t);
    execute format('create policy %1$s_update on %1$s for update using (can_manage(business_id)) with check (can_manage(business_id))', t);
    execute format('create policy %1$s_delete on %1$s for delete using (can_manage(business_id))', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Loja aberta agora, pelo horário de funcionamento (turnos podem virar a noite)
-- ---------------------------------------------------------------------
create or replace function is_store_open(bid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  with n as (
    select extract(dow from (now() at time zone b.timezone))::int as wd,
           (now() at time zone b.timezone)::time as t
      from businesses b where b.id = bid)
  select exists (
    select 1 from store_hours h, n
     where h.business_id = bid and (
       (h.end_time > h.start_time and h.weekday = n.wd and n.t >= h.start_time and n.t < h.end_time)
       or (h.end_time < h.start_time and ((h.weekday = n.wd and n.t >= h.start_time)
                                          or ((h.weekday + 1) % 7 = n.wd and n.t < h.end_time)))))
$$;

-- ---------------------------------------------------------------------
-- Fidelidade: carimbo quando o pedido é entregue
-- ---------------------------------------------------------------------
create or replace function loyalty_on_order() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'entregue' and (tg_op = 'INSERT' or old.status is distinct from 'entregue') then
    perform _add_loyalty_stamp(new.business_id, new.phone, new.customer_name);
  end if;
  return new;
end $$;
revoke execute on function loyalty_on_order() from public, anon, authenticated;

drop trigger if exists orders_loyalty on orders;
create trigger orders_loyalty after insert or update of status on orders
  for each row execute function loyalty_on_order();

-- ---------------------------------------------------------------------
-- place_order: pedido salvo no painel (o site manda pro WhatsApp depois)
-- ---------------------------------------------------------------------
drop function if exists place_order(uuid, jsonb, text, text, text, text, text, numeric, text, text);
create function place_order(p_business uuid, p_items jsonb, p_name text, p_phone text, p_mode text,
                            p_address text default null, p_payment text default 'pix',
                            p_change numeric default null, p_notes text default null,
                            p_coupon text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  b          businesses;
  v_line     record;
  v_subtotal numeric := 0;
  v_fee      numeric := 0;
  v_discount numeric := 0;
  v_coupon   jsonb;
  v_number   int;
  v_order    uuid;
  v_lines    jsonb := '[]'::jsonb;
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
    if coalesce(trim(p_address), '') = '' then raise exception 'Informe o endereço de entrega.'; end if;
    v_fee := b.delivery_fee;
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
                      subtotal, delivery_fee, discount, total, coupon_code)
  values (p_business, v_number, left(trim(p_name), 80), left(trim(p_phone), 30), p_mode,
          nullif(left(trim(coalesce(p_address, '')), 300), ''), left(coalesce(p_payment, 'pix'), 40), p_change,
          nullif(left(trim(coalesce(p_notes, '')), 500), ''),
          v_subtotal, v_fee, v_discount, greatest(v_subtotal + v_fee - v_discount, 0), v_coupon->>'code')
  returning id into v_order;

  insert into order_items (order_id, business_id, item_id, name, unit_price, qty, total)
  select v_order, p_business, (l->>'id')::uuid, l->>'name', (l->>'unit_price')::numeric,
         (l->>'qty')::int, (l->>'total')::numeric
    from jsonb_array_elements(v_lines) l;

  return jsonb_build_object('id', v_order, 'number', v_number, 'items', v_lines,
                            'subtotal', v_subtotal, 'delivery_fee', v_fee, 'discount', v_discount,
                            'total', greatest(v_subtotal + v_fee - v_discount, 0), 'coupon', v_coupon->>'code');
end $$;
grant execute on function place_order(uuid, jsonb, text, text, text, text, text, numeric, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Cadastro: o tipo vem junto (signup manda business_kind nos metadados)
-- ---------------------------------------------------------------------
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_meta jsonb := new.raw_user_meta_data;
  v_kind text  := case when new.raw_user_meta_data->>'business_kind' = 'cardapio' then 'cardapio' else 'agenda' end;
  v_id   uuid;
begin
  if v_meta ? 'business_name' and v_meta ? 'business_slug' then
    begin
      insert into businesses (name, slug, category, phone, kind, created_by)
      values (trim(v_meta->>'business_name'), lower(trim(v_meta->>'business_slug')),
              v_meta->>'business_category', v_meta->>'business_phone', v_kind, new.id)
      returning id into v_id;
      insert into business_members (business_id, user_id, role) values (v_id, new.id, 'owner');
    exception when others then
      null;
    end;
  end if;
  return new;
end $$;
revoke execute on function handle_new_user() from public, anon, authenticated;

-- Cadastro pelo painel (quem criou a conta sem os dados do estabelecimento).
drop function if exists request_business(text, text, text, text);
drop function if exists request_business(text, text, text, text, text);
create function request_business(p_name text, p_slug text, p_category text default null,
                                 p_phone text default null, p_kind text default 'agenda')
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id    uuid;
  v_count int;
  v_sub   subscriptions;
  v_max   int;
begin
  if auth.uid() is null then
    raise exception 'Faça login primeiro.';
  end if;
  select count(*) into v_count from businesses where created_by = auth.uid();
  -- A primeira vitrine é sempre liberada (pra o usuário poder assinar depois).
  if v_count >= 1 then
    select * into v_sub from subscriptions where owner_id = auth.uid();
    if v_sub.id is null or v_sub.status not in ('active', 'past_due', 'pending_payment', 'trialing') then
      raise exception 'Assine um plano antes de cadastrar outra vitrine.';
    end if;
    select max_businesses into v_max from plans where id = v_sub.plan_id;
    if v_count >= v_max then
      raise exception 'Seu plano permite até % estabelecimento(s). Faça upgrade para cadastrar mais.', v_max;
    end if;
  end if;
  insert into businesses (name, slug, category, phone, kind, created_by)
  values (trim(p_name), lower(trim(p_slug)), p_category, p_phone,
          case when p_kind = 'cardapio' then 'cardapio' else 'agenda' end, auth.uid())
  returning id into v_id;
  insert into business_members (business_id, user_id, role) values (v_id, auth.uid(), 'owner');
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Página pública: inclui o tipo e, no cardápio, a loja e os produtos
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
      'min_order',        b.min_order,
      'delivery_area',    b.delivery_area,
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

-- ---------------------------------------------------------------------
-- Lista do admin: mostra o tipo; "atividade" conta pedidos no cardápio
-- ---------------------------------------------------------------------
drop function if exists admin_list_businesses();
create function admin_list_businesses()
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
         case when b.kind = 'cardapio'
              then (select count(*) from orders x       where x.business_id = b.id)
              else (select count(*) from appointments x where x.business_id = b.id) end,
         b.kind
    from businesses b
    left join auth.users u    on u.id = b.created_by
    left join subscriptions s on s.owner_id = b.created_by
    left join plans p         on p.id = s.plan_id
   order by (b.status = 'pending') desc, b.created_at desc;
end $$;
