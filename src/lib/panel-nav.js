// Menu do painel. "kinds" limita o item a certos tipos de vitrine;
// "feature" marca itens que dependem do plano (aparecem com cadeado
// quando o plano não inclui o recurso).
export const PANEL_NAV = [
  { to: '/painel', label: 'Agenda', icon: 'calendar', kinds: ['agenda'] },
  { to: '/painel/fila', label: 'Fila', icon: 'users', kinds: ['fila'] },
  { to: '/painel/servicos', label: 'Serviços', icon: 'scissors', kinds: ['agenda', 'fila'] },
  { to: '/painel/profissionais', label: 'Profissionais', staffLabel: true, icon: 'users', kinds: ['agenda'] },
  { to: '/painel/horarios', label: 'Horários', icon: 'clock', kinds: ['agenda'] },
  { to: '/painel/clientes', label: 'Clientes', icon: 'contact', kinds: ['agenda'] },
  { to: '/painel/bloqueios', label: 'Folgas e bloqueios', icon: 'ban', kinds: ['agenda'] },

  { to: '/painel/pedidos', label: 'Pedidos', icon: 'bag', kinds: ['cardapio'] },
  { to: '/painel/cardapio', label: 'Produtos', icon: 'utensils', kinds: ['cardapio'] },
  { to: '/painel/funcionamento', label: 'Funcionamento', icon: 'clock', kinds: ['cardapio'] },

  { to: '/painel/lembretes', label: 'Lembretes', icon: 'bell', feature: 'lembretes', kinds: ['agenda'] },
  { to: '/painel/galeria', label: 'Galeria', icon: 'image', feature: 'galeria' },
  { to: '/painel/avaliacoes', label: 'Avaliações', icon: 'star', feature: 'avaliacoes' },
  { to: '/painel/fidelidade', label: 'Fidelidade', icon: 'gift', feature: 'fidelidade', kinds: ['agenda', 'cardapio'] },
  { to: '/painel/cupons', label: 'Cupons', icon: 'tag', feature: 'cupons', kinds: ['agenda', 'cardapio'] },
  { to: '/painel/promocao', label: 'Promoção', icon: 'sparkles' },
  { to: '/painel/divulgar', label: 'Divulgar', icon: 'qr' },
  { to: '/painel/tutorial', label: 'Tutorial', icon: 'sparkles', kinds: ['agenda'] },
  { to: '/painel/financeiro', label: 'Financeiro', icon: 'chart' },
  { to: '/painel/perfil', label: 'Perfil', icon: 'store' },
  { to: '/painel/assinatura', label: 'Assinatura', icon: 'card' },
]

export function navFor(kind = 'agenda') {
  return PANEL_NAV.filter((i) => !i.kinds || i.kinds.includes(kind))
}

// Página inicial do painel para cada tipo.
export function homeFor(kind = 'agenda') {
  return navFor(kind)[0].to
}

export function routeAllowed(path, kind = 'agenda') {
  return navFor(kind).some((i) => i.to === path)
}
