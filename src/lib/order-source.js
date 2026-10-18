// De onde veio o pedido (orders.source). 'site' é a vitrine; os outros são
// lançados como venda avulsa. iFood e 99Food usam só as cores e o nome das
// marcas, pra identificar o canal (sem a logo oficial).
export const ORDER_SOURCES = {
  site: { label: 'Site', short: 'Site', bg: 'rgba(59, 130, 246, 0.16)', fg: '#93c5fd' },
  balcao: { label: 'Balcão', short: 'Balcão', bg: 'rgba(148, 163, 184, 0.16)', fg: '#cbd5e1' },
  telefone: { label: 'Telefone', short: 'Telefone', bg: 'rgba(148, 163, 184, 0.16)', fg: '#cbd5e1' },
  ifood: { label: 'iFood', short: 'iFood', bg: '#ea1d2c', fg: '#ffffff' },
  '99food': { label: '99Food', short: '99', bg: '#ffd400', fg: '#111111' },
}

// Origens que podem ser escolhidas na venda avulsa.
export const MANUAL_SOURCES = ['balcao', 'telefone', 'ifood', '99food']

// Pedido vindo de app de delivery já foi pago pelo app.
export const isAppSource = (s) => s === 'ifood' || s === '99food'

export const sourceOf = (o) => ORDER_SOURCES[o?.source] ?? ORDER_SOURCES.site
