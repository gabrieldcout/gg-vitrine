-- =====================================================================
-- GG Vitrine — 0015a: adiciona 'trialing' ao enum subscription_status
--
-- Precisa rodar antes do 0015b (postgres não permite usar valor novo de
-- enum na mesma transação em que ele é criado).
-- =====================================================================

create extension if not exists pgcrypto;

do $$ begin
  alter type subscription_status add value if not exists 'trialing';
exception when duplicate_object then null; end $$;
