-- =====================================================================
-- GG Vitrine — 0035: liberar o teste grátis pelo admin
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança. Precisa da 0030 antes.
--
-- O teste de 7 dias só começava quando o cliente digitava o código do e-mail
-- (precisa do CPF). Quem tinha o e-mail confirmado na mão ficava sem plano e
-- com a vitrine "Temporariamente indisponível". Agora:
--   * Confirmar e-mail no admin já libera os 7 dias, se a conta não tiver plano;
--   * botão "Liberar 7 dias" pra quem já está confirmado e sem plano.
-- =====================================================================

create or replace function admin_start_trial(p_owner uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_platform_admin();
  insert into subscriptions (owner_id, plan_id, status, trial_until)
  values (p_owner, 'solo', 'trialing', now() + interval '7 days')
  on conflict (owner_id) do update
    set status = 'trialing', trial_until = now() + interval '7 days',
        plan_id = coalesce(subscriptions.plan_id, 'solo')
    where subscriptions.status in ('pending_payment', 'canceled');   -- quem paga ou já testa não é mexido
end $$;
revoke all on function admin_start_trial(uuid) from public, anon;
grant execute on function admin_start_trial(uuid) to authenticated;

create or replace function admin_confirm_email(p_owner uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_platform_admin();
  update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now()) where id = p_owner;
  -- Sem plano nenhum: já começa o teste (é o que aconteceria com o código do e-mail).
  if not exists (select 1 from subscriptions where owner_id = p_owner) then
    insert into subscriptions (owner_id, plan_id, status, trial_until)
    values (p_owner, 'solo', 'trialing', now() + interval '7 days');
  end if;
end $$;
revoke all on function admin_confirm_email(uuid) from public, anon;
grant execute on function admin_confirm_email(uuid) to authenticated;
