-- =====================================================================
-- GG Vitrine — 0026: serviço de orçamento (foto + ideia pelo WhatsApp)
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança. Precisa da 0020 antes.
--
-- O dono marca um serviço como "orçamento". Na vitrine, quem agenda esse
-- serviço escolhe dia e horário, descreve a ideia e pode mandar uma foto
-- de referência. O agendamento entra na Agenda com a ideia e a foto, e o
-- cliente termina enviando tudo pelo WhatsApp do estabelecimento.
-- =====================================================================

alter table services     add column if not exists quote boolean not null default false;
alter table appointments add column if not exists reference_url text
  check (reference_url is null or char_length(reference_url) <= 500);

-- ---------------------------------------------------------------------
-- Fotos de referência: o cliente logado sobe na própria pasta (uid/...)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('referencias', 'referencias', true, 5 * 1024 * 1024,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do update
  set public = true, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists referencias_public_read on storage.objects;
create policy referencias_public_read on storage.objects for select
  using (bucket_id = 'referencias');

drop policy if exists referencias_own_insert on storage.objects;
create policy referencias_own_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'referencias' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- book_appointment: igual à 0003, com a foto de referência (p_photo).
-- A foto só vale se estiver na pasta do próprio cliente no bucket.
-- ---------------------------------------------------------------------
drop function if exists book_appointment(uuid, uuid, uuid, timestamptz, text, text, text, text);

create or replace function book_appointment(p_business uuid, p_service uuid, p_professional uuid,
                                            p_starts_at timestamptz, p_name text, p_phone text,
                                            p_notes text default null, p_coupon text default null,
                                            p_photo text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_uid      uuid := auth.uid();
  v_tz       text;
  v_duration int;
  v_price    numeric;
  v_quote    boolean;
  v_coupon   jsonb;
  v_customer uuid;
  v_id       uuid;
begin
  if v_uid is null then
    raise exception 'Faça login para confirmar o agendamento.';
  end if;
  if not business_is_live(p_business) then
    raise exception 'Este estabelecimento não está recebendo agendamentos no momento.';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'Informe seu nome.';
  end if;

  select timezone into v_tz from businesses where id = p_business;
  select duration_min, price, quote into v_duration, v_price, v_quote
    from services where id = p_service and business_id = p_business and active;
  if not found then
    raise exception 'Serviço não encontrado.';
  end if;

  if p_photo is not null and p_photo not like '%/storage/v1/object/public/referencias/' || v_uid || '/%' then
    raise exception 'Foto inválida. Envie de novo.';
  end if;
  if v_quote and p_photo is null and char_length(trim(coalesce(p_notes, ''))) < 5 then
    raise exception 'Conte sua ideia ou mande uma foto de referência.';
  end if;

  if not exists (
    select 1 from _free_slots(p_business, p_service, (p_starts_at at time zone v_tz)::date, p_professional) f
     where f.professional_id = p_professional and f.starts_at = p_starts_at) then
    raise exception 'Este horário não está mais disponível. Escolha outro.';
  end if;

  if coalesce(trim(p_coupon), '') <> '' then
    v_coupon := _coupon_lookup(p_business, p_coupon, v_price);
    if not (v_coupon->>'valid')::boolean then
      raise exception '%', v_coupon->>'message';
    end if;
    v_price := greatest(v_price - (v_coupon->>'discount')::numeric, 0);
    update coupons set uses = uses + 1 where id = (v_coupon->>'coupon_id')::uuid;
  end if;

  insert into customers (business_id, auth_user_id, name, phone, email)
  values (p_business, v_uid, trim(p_name), nullif(trim(p_phone), ''), auth.jwt() ->> 'email')
  on conflict (business_id, auth_user_id) do update
    set name  = excluded.name,
        phone = coalesce(excluded.phone, customers.phone),
        email = coalesce(excluded.email, customers.email)
  returning id into v_customer;

  insert into appointments (business_id, professional_id, service_id, customer_id,
                            starts_at, ends_at, price, notes, reference_url, created_by)
  values (p_business, p_professional, p_service, v_customer,
          p_starts_at, p_starts_at + make_interval(mins => v_duration), v_price,
          left(concat_ws(' · ', nullif(trim(coalesce(p_notes, '')), ''),
                         case when v_coupon is not null then 'Cupom ' || (v_coupon->>'code') end), 1000),
          p_photo, v_uid)
  returning id into v_id;

  return v_id;
exception
  when exclusion_violation then
    raise exception 'Este horário acabou de ser reservado por outra pessoa. Escolha outro.';
end $$;

-- ---------------------------------------------------------------------
-- Página pública: mesma função da 0020, com 'quote' em cada serviço
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
               'price', s.price, 'duration_min', s.duration_min, 'quote', s.quote) order by s.name)
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
