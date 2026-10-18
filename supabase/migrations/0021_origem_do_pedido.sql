-- =====================================================================
-- GG Vitrine — 0021: origem do pedido (site, balcão, telefone, iFood, 99)
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança. Precisa da 0016 antes.
--
-- Pedidos da vitrine ficam como 'site'. Na venda avulsa o lojista diz de
-- onde veio (balcão, telefone, iFood, 99Food) e o Financeiro separa as
-- vendas por canal. Não há integração com iFood/99: é lançamento manual.
-- =====================================================================

alter table orders add column if not exists source text not null default 'site';

do $$ begin
  alter table orders add constraint orders_source_check
    check (source in ('site', 'balcao', 'telefone', 'ifood', '99food'));
exception when duplicate_object then null; end $$;
