-- =====================================================================
-- GG Vitrine — 0019: marca se o cliente abriu o WhatsApp do pedido
--
-- Como aplicar: Supabase > SQL Editor > cole este arquivo inteiro > Run.
-- Pode ser rodado de novo com segurança. Precisa da 0016 antes.
--
-- O pedido é salvo antes do WhatsApp. Quando o cliente toca em "Enviar
-- pedido no WhatsApp", a vitrine chama mark_order_whatsapp e o painel
-- passa a mostrar que ele abriu a conversa. Não dá pra saber se ele
-- apertou "enviar" lá dentro; serve pra loja ver quem precisa de contato.
-- =====================================================================

alter table orders add column if not exists wa_clicked_at timestamptz;

create or replace function mark_order_whatsapp(p_order uuid) returns void
language sql security definer set search_path = public as $$
  -- Só pedidos recentes; o id do pedido (uuid) só quem fez o pedido conhece.
  update orders set wa_clicked_at = coalesce(wa_clicked_at, now())
   where id = p_order and created_at > now() - interval '1 day'
$$;
grant execute on function mark_order_whatsapp(uuid) to anon, authenticated;
