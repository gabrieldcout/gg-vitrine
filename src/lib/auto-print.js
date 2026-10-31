import { ref } from 'vue'
import { supabase } from './supabase'
import { printOrder } from './print'

// Impressão automática de pedidos novos. Roda no layout do painel, então
// imprime com qualquer tela do painel aberta (não só a de Pedidos).
// A escolha é deste aparelho: o computador do balcão imprime, o celular do
// dono não. Os pedidos já impressos ficam guardados aqui também, assim duas
// abas abertas não imprimem o mesmo pedido duas vezes e recarregar a página
// não reimprime nada.

const KEY_ON = 'gg-pedidos-imprimir'
const KEY_DONE = 'gg-pedidos-impressos'
const POLL_MS = 15000
// Pedido que chegou com o painel fechado ainda sai, se for recente.
const CATCH_UP_MS = 10 * 60 * 1000

const read = (key, def) => { try { return localStorage.getItem(key) ?? def } catch { return def } }
const write = (key, v) => { try { localStorage.setItem(key, v) } catch { /* sem armazenamento local */ } }

export const autoPrintOn = ref(read(KEY_ON, '0') === '1')
export const lastCheck = ref(null)
export const lastPrinted = ref(null)

function printedIds() {
  try { return JSON.parse(read(KEY_DONE, '{}')) || {} } catch { return {} }
}
function markPrinted(ids) {
  const done = printedIds()
  const now = Date.now()
  ids.forEach((id) => { done[id] = now })
  // Guarda só os de 2 dias pra cá.
  for (const id in done) if (now - done[id] > 2 * 864e5) delete done[id]
  write(KEY_DONE, JSON.stringify(done))
}

// Imprime um por vez (duas janelas de impressão juntas se atrapalham).
let queue = Promise.resolve()
export function queuePrint(order, business) {
  queue = queue.then(() => { printOrder(order, business); return new Promise((r) => setTimeout(r, 2500)) })
}

async function fetchRecent(businessId) {
  const { data, error } = await supabase.from('orders')
    .select('*, order_items(name, qty, unit_price, total)')
    .eq('business_id', businessId)
    .gte('created_at', new Date(Date.now() - CATCH_UP_MS).toISOString())
    .order('created_at', { ascending: true })
  if (error) throw error
  return data ?? []
}

// Liga/desliga neste aparelho. Ao ligar, o que já chegou não sai de novo.
export async function setAutoPrint(on, business) {
  autoPrintOn.value = on
  write(KEY_ON, on ? '1' : '0')
  if (on && business) {
    try { markPrinted((await fetchRecent(business.id)).map((o) => o.id)) } catch { /* tenta na próxima */ }
  }
}

async function check(business) {
  if (!autoPrintOn.value || !business) return
  let list
  try { list = await fetchRecent(business.id) } catch { return }
  lastCheck.value = new Date()
  const done = printedIds()
  // Só pedido feito pela vitrine (venda lançada no painel não é "pedido chegando").
  const fresh = list.filter((o) => !done[o.id] && (o.source ?? 'site') === 'site' && o.status !== 'cancelado')
  if (!fresh.length) return
  markPrinted(fresh.map((o) => o.id))
  fresh.forEach((o) => queuePrint(o, business))
  lastPrinted.value = { number: fresh[fresh.length - 1].number, at: new Date() }
}

// Começa a vigiar os pedidos; devolve a função que para.
export function startAutoPrint(getBusiness) {
  const run = () => check(getBusiness())
  const timer = setInterval(run, POLL_MS)
  const onVisible = () => { if (document.visibilityState === 'visible') run() }
  // Ligou/desligou em outra aba deste aparelho.
  const onStorage = (e) => { if (e.key === KEY_ON) autoPrintOn.value = e.newValue === '1' }
  document.addEventListener('visibilitychange', onVisible)
  window.addEventListener('storage', onStorage)
  run()
  return () => {
    clearInterval(timer)
    document.removeEventListener('visibilitychange', onVisible)
    window.removeEventListener('storage', onStorage)
  }
}
