<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { supabase, unwrap } from '@/lib/supabase'
import { useBusiness } from '@/lib/business'
import { money, formatTime, formatDate, todayISO, addDaysISO, zonedToUtc } from '@/lib/format'
import { waLink } from '@/lib/whatsapp'
import { printOrder } from '@/lib/print'
import { alarmUrl } from '@/lib/alarm'
import ManualOrder from '@/components/ManualOrder.vue'
import SourceBadge from '@/components/SourceBadge.vue'
import Icon from '@/components/Icon.vue'
import { catalogWord } from '@/config/brand'
import { ask } from '@/lib/confirm'
import { toast } from '@/lib/toast'

const biz = useBusiness()
const tz = computed(() => biz.business.timezone)
const orders = ref([])
const filter = ref('abertos')
const error = ref('')
const showManual = ref(false)

// Olhinho: esconde o valor vendido (lembrado neste aparelho).
const HIDE_KEY = 'gg-esconder-valores'
const hideValues = ref((() => { try { return localStorage.getItem(HIDE_KEY) === '1' } catch { return false } })())
function toggleValues() {
  hideValues.value = !hideValues.value
  try { localStorage.setItem(HIDE_KEY, hideValues.value ? '1' : '0') } catch { /* sem armazenamento local */ }
}
const manualMsg = ref('')

function manualSaved(order) {
  showManual.value = false
  manualMsg.value = `Venda #${order.number} lançada.`
  setTimeout(() => { manualMsg.value = '' }, 4000)
  seen?.add(order.id)   // venda lançada aqui não é "pedido novo chegando"
  load()
}

// ---------------- Pedido novo: som, notificação, impressão ----------------
// Preferências deste aparelho (o balcão pode imprimir e o celular do dono não).
const pref = (key, def) => { try { const v = localStorage.getItem(key); return v === null ? def : v === '1' } catch { return def } }
const setPref = (key, v) => { try { localStorage.setItem(key, v ? '1' : '0') } catch { /* sem armazenamento local */ } }
const soundOn = ref(pref('gg-pedidos-som', true))
const autoPrint = ref(pref('gg-pedidos-imprimir', false))
const audioReady = ref(false)
const showPrintHelp = ref(false)
function toggleSound() { soundOn.value = !soundOn.value; setPref('gg-pedidos-som', soundOn.value); if (soundOn.value) enableSound() }
function toggleAutoPrint() { autoPrint.value = !autoPrint.value; setPref('gg-pedidos-imprimir', autoPrint.value) }

// Aceite automático: fica no banco (vale mesmo com o painel fechado). Só aparece
// depois da migration 0022.
const hasAutoAccept = computed(() => 'auto_accept' in biz.business)
async function toggleAutoAccept() {
  const value = !biz.business.auto_accept
  const { error: err } = await supabase.from('businesses').update({ auto_accept: value }).eq('id', biz.business.id)
  if (err) { error.value = err.message; return }
  biz.business.auto_accept = value
  toast(value ? 'Aceite automático ligado.' : 'Aceite automático desligado.')
}

// O navegador só libera som depois de um toque na página: o primeiro toque em
// qualquer lugar já "destrava" (ou o botão Ativar som).
let player
async function enableSound() {
  try {
    player ??= new Audio(alarmUrl())
    // Toca mudo uma vez pra o navegador liberar o som desta página.
    player.muted = true
    await player.play()
    player.pause()
    player.currentTime = 0
    player.muted = false
    audioReady.value = true
  } catch {
    if (player) player.muted = false
  }
  if ('Notification' in window && Notification.permission === 'default') Notification.requestPermission().catch(() => {})
}
async function testSound() { await enableSound(); alarm() }

function alarm() {
  if (!soundOn.value || !player) return
  player.currentTime = 0
  player.play().catch(() => { audioReady.value = false })   // navegador bloqueou: volta o botão Ativar som
}

// Mantém a tela do celular/tablet acesa com a tela de pedidos aberta: com a
// tela apagada o navegador para e o pedido novo não toca.
let wakeLock = null
async function keepAwake() {
  if (!soundOn.value || document.visibilityState !== 'visible' || !('wakeLock' in navigator)) return
  try { wakeLock = await navigator.wakeLock.request('screen') } catch { /* sem suporte ou bateria fraca */ }
}

function notify(o) {
  if (!('Notification' in window) || Notification.permission !== 'granted') return
  try {
    const n = new Notification(`Pedido #${o.number} · ${o.customer_name}`, {
      body: `${money(o.total)} · ${o.mode === 'entrega' ? 'Entrega' : 'Retirada'}`, tag: o.id,
    })
    n.onclick = () => { window.focus(); n.close() }
  } catch { /* sem notificação */ }
}

// Imprime um por vez (duas janelas de impressão juntas se atrapalham).
let printQueue = Promise.resolve()
function queuePrint(o) {
  printQueue = printQueue.then(() => { printOrder(o, biz.business); return new Promise((r) => setTimeout(r, 2500)) })
}

let seen = null   // ids de pedido já vistos nesta tela
function handleNew(list) {
  if (!seen) { seen = new Set(list.map((o) => o.id)); return }
  const fresh = list.filter((o) => !seen.has(o.id) && (o.source ?? 'site') === 'site').reverse()
  list.forEach((o) => seen.add(o.id))
  if (!fresh.length) return
  hasNew.value = true
  alarm()
  fresh.forEach(notify)
  if (autoPrint.value) fresh.forEach(queuePrint)
}
const hasNew = ref(false)

const STATUS = {
  novo: { label: 'Novo', badge: 'yellow', next: 'preparando', action: 'Começar a preparar' },
  preparando: { label: 'Preparando', badge: 'blue', next: 'pronto', action: 'Marcar como pronto' },
  pronto: { label: 'Pronto', badge: 'green', next: 'entregue', action: 'Marcar como entregue' },
  entregue: { label: 'Entregue', badge: '' },
  cancelado: { label: 'Cancelado', badge: 'red' },
}
const FILTERS = { abertos: 'Em aberto', entregues: 'Entregues', cancelados: 'Cancelados', todos: 'Todos' }

// Período: um dia ou um mês. Busca direto no banco (a lista normal só traz os
// pedidos mais recentes).
const PERIODS = { todos: 'Qualquer data', dia: 'Dia', mes: 'Mês' }
const period = ref('todos')
const day = ref(todayISO(tz.value))
const month = ref(todayISO(tz.value).slice(0, 7))
const periodOrders = ref([])
const periodRange = computed(() => {
  if (period.value === 'dia' && day.value) return [day.value, addDaysISO(day.value, 1)]
  if (period.value === 'mes' && month.value) {
    const [y, m] = month.value.split('-').map(Number)
    return [`${month.value}-01`, new Date(Date.UTC(y, m, 1)).toISOString().slice(0, 10)]
  }
  return null
})
async function loadPeriod() {
  const range = periodRange.value
  if (!range) { periodOrders.value = []; return }
  try {
    periodOrders.value = unwrap(await supabase.from('orders').select('*, order_items(name, qty, unit_price, total)')
      .eq('business_id', biz.business.id)
      .gte('created_at', zonedToUtc(range[0], '00:00', tz.value).toISOString())
      .lt('created_at', zonedToUtc(range[1], '00:00', tz.value).toISOString())
      .order('created_at', { ascending: false }).limit(5000))
  } catch (e) {
    error.value = e.message
  }
}
watch(period, (p, old) => {
  // Olhando um período, o normal é querer ver tudo dele, não só os em aberto.
  if (old === 'todos' && filter.value === 'abertos') filter.value = 'todos'
})
watch(periodRange, loadPeriod)

const visible = computed(() => (periodRange.value ? periodOrders.value : orders.value).filter((o) => {
  if (filter.value === 'abertos') return ['novo', 'preparando', 'pronto'].includes(o.status)
  if (filter.value === 'entregues') return o.status === 'entregue'
  if (filter.value === 'cancelados') return o.status === 'cancelado'
  return true
}))
const todayTotal = computed(() => orders.value
  .filter((o) => o.status !== 'cancelado' && new Date(o.created_at) >= zonedToUtc(todayISO(tz.value), '00:00', tz.value))
  .reduce((s, o) => s + Number(o.total), 0))
const periodSold = computed(() => periodOrders.value.filter((o) => o.status !== 'cancelado'))
const periodTotal = computed(() => periodSold.value.reduce((s, o) => s + Number(o.total), 0))

async function load() {
  try {
    orders.value = unwrap(await supabase.from('orders').select('*, order_items(name, qty, unit_price, total)')
      .eq('business_id', biz.business.id).order('created_at', { ascending: false }).limit(1000))
    handleNew(orders.value)
    if (periodRange.value) loadPeriod()
  } catch (e) {
    error.value = e.message
  }
}

// Atualiza sozinho para quem deixa o painel aberto no balcão.
let timer
const unlock = () => {
  if (!soundOn.value) return
  if (!audioReady.value) enableSound()
  if (!wakeLock) keepAwake()
}
// Voltou pra tela (desbloqueou o celular, trocou de aba): busca na hora e pede
// de novo pra manter a tela acesa.
function onVisible() {
  if (document.visibilityState !== 'visible') return
  load()
  wakeLock = null
  keepAwake()
}
onMounted(() => {
  load()
  timer = setInterval(load, 15000)
  document.addEventListener('pointerdown', unlock)
  document.addEventListener('visibilitychange', onVisible)
  if (soundOn.value) { enableSound(); keepAwake() }   // funciona se o navegador já liberou o som antes
})
onUnmounted(() => {
  clearInterval(timer)
  document.removeEventListener('pointerdown', unlock)
  document.removeEventListener('visibilitychange', onVisible)
  wakeLock?.release().catch(() => {})
})

async function setStatus(o, status) {
  const { error: err } = await supabase.from('orders').update({ status }).eq('id', o.id)
  if (err) error.value = err.message
  else toast(status === 'cancelado' ? `Pedido #${o.number} cancelado.` : `Pedido #${o.number} atualizado.`)
  load()
}

// Situação do WhatsApp do pedido (só aparece depois da migration 0019).
// O cliente tem uns minutos pra tocar no botão antes de virar alerta.
function waState(o) {
  // Só pedido feito pela vitrine passa pelo WhatsApp (venda avulsa/iFood/99 não).
  if (!('wa_clicked_at' in o) || o.status === 'cancelado' || (o.source && o.source !== 'site')) return null
  if (o.wa_clicked_at) return 'ok'
  // Só alerta no começo do pedido (com aceite automático ele já chega "Preparando");
  // depois de pronto/entregue a loja já tratou com o cliente.
  return ['novo', 'preparando'].includes(o.status) && Date.now() - new Date(o.created_at).getTime() > 3 * 60000 ? 'missing' : null
}

// Confirma antes de cancelar: o botão fica do lado dos outros e é fácil tocar sem querer.
async function cancelOrder(o) {
  if (!await ask(`Tem certeza que deseja cancelar o pedido #${o.number} de ${o.customer_name}?`)) return
  setStatus(o, 'cancelado')
}

function customerLink(o) {
  const msg = {
    novo: `Olá ${o.customer_name}! Recebemos seu pedido #${o.number}. Já já começamos a preparar.`,
    preparando: `Olá ${o.customer_name}! Seu pedido #${o.number} está sendo preparado.`,
    pronto: o.mode === 'entrega'
      ? `Olá ${o.customer_name}! Seu pedido #${o.number} saiu para entrega.`
      : `Olá ${o.customer_name}! Seu pedido #${o.number} está pronto para retirada.`,
  }[o.status] ?? `Olá ${o.customer_name}!`
  return waLink(o.phone, msg)
}
</script>

<template>
  <div class="page-header spread">
    <div>
      <p class="eyebrow">{{ catalogWord(biz.business.category) }}</p>
      <h1>Pedidos</h1>
    </div>
    <div class="orders-head-right">
      <div class="card stat sold-today" style="padding: 12px 18px">
        <div class="label">Vendido hoje</div>
        <div class="sold-row">
          <div class="value" style="font-size: 1.4rem">{{ hideValues ? 'R$ •••••' : money(todayTotal) }}</div>
          <button type="button" class="eye-btn" :title="hideValues ? 'Mostrar valor' : 'Esconder valor'"
                  :aria-label="hideValues ? 'Mostrar valor' : 'Esconder valor'" @click="toggleValues">
            <Icon :name="hideValues ? 'eye-off' : 'eye'" />
          </button>
        </div>
      </div>
      <button class="btn" @click="showManual = true"><Icon name="plus" style="width: 16px; height: 16px" />Lançar venda avulsa</button>
    </div>
  </div>
  <ManualOrder v-if="showManual" @close="showManual = false" @saved="manualSaved" />

  <div class="order-settings card">
    <label v-if="hasAutoAccept" class="opt">
      <input type="checkbox" :checked="biz.business.auto_accept" @change="toggleAutoAccept" />
      <span><strong>Aceitar pedidos automaticamente</strong><small>Pedido do site já chega como "Preparando". Vale mesmo com o painel fechado.</small></span>
    </label>
    <label class="opt">
      <input type="checkbox" :checked="soundOn" @change="toggleSound" />
      <span><strong>Som e notificação de pedido novo</strong><small>Neste aparelho, com esta tela aberta.</small></span>
    </label>
    <label class="opt">
      <input type="checkbox" :checked="autoPrint" @change="toggleAutoPrint" />
      <span><strong>Imprimir pedidos novos automaticamente</strong><small>Neste aparelho, com esta tela aberta.
        <button type="button" class="link-btn" @click.prevent="showPrintHelp = !showPrintHelp">Imprimir sem a janela de confirmação</button></small></span>
    </label>
    <div v-if="showPrintHelp" class="print-help">
      <p>O navegador sempre pergunta antes de imprimir, por segurança. Pra imprimir direto no computador do balcão:</p>
      <ol>
        <li>Deixe a impressora da comanda como <strong>impressora padrão</strong> do Windows.</li>
        <li>Clique com o botão direito no atalho do <strong>Google Chrome</strong> e escolha <strong>Propriedades</strong>.</li>
        <li>No campo <strong>Destino</strong>, no final (depois das aspas), acrescente um espaço e <code>--kiosk-printing</code>.</li>
        <li>Feche todas as janelas do Chrome e abra de novo por esse atalho.</li>
      </ol>
      <p>Pronto: a comanda sai direto, sem perguntar, no botão Imprimir e na impressão automática.</p>
    </div>
    <button v-if="soundOn && !audioReady" type="button" class="btn small sound-btn sound-off" @click="testSound">
      <Icon name="bell" style="width: 15px; height: 15px" />Som desativado: toque aqui pra ativar
    </button>
    <button v-else-if="soundOn" type="button" class="link-btn sound-btn" @click="testSound">Testar som</button>
  </div>
  <div v-if="manualMsg" class="success">{{ manualMsg }}</div>

  <div v-if="hasNew" class="success spread" @click="hasNew = false">
    <strong>🔔 Chegou pedido novo!</strong><button class="btn small secondary">Ok</button>
  </div>
  <div v-if="error" class="error">{{ error }}</div>

  <div class="chips" style="margin-bottom: 10px">
    <button v-for="(label, key) in FILTERS" :key="key" class="chip" :class="{ selected: filter === key }" @click="filter = key">{{ label }}</button>
  </div>
  <div class="period">
    <div class="chips">
      <button v-for="(label, key) in PERIODS" :key="key" class="chip" :class="{ selected: period === key }" @click="period = key">{{ label }}</button>
    </div>
    <input v-if="period === 'dia'" v-model="day" type="date" class="period-input" aria-label="Dia" />
    <input v-else-if="period === 'mes'" v-model="month" type="month" class="period-input" aria-label="Mês" />
    <span v-if="periodRange" class="period-sum">
      {{ periodSold.length }} {{ periodSold.length === 1 ? 'pedido' : 'pedidos' }} ·
      <strong>{{ hideValues ? 'R$ •••••' : money(periodTotal) }}</strong>
      &nbsp;<small class="muted">(sem cancelados)</small>
    </span>
  </div>

  <div v-if="!orders.length && !error" class="card" style="text-align: center">
    <h3>Nenhum pedido ainda</h3>
    <p class="muted">Os pedidos feitos pelo seu link aparecem aqui e chegam no seu WhatsApp. Pra começar a receber:</p>
    <div class="chips" style="justify-content: center">
      <RouterLink class="btn small" to="/painel/cardapio">Cadastrar produtos</RouterLink>
      <RouterLink class="btn small secondary" to="/painel/funcionamento">Definir horário e entrega</RouterLink>
    </div>
  </div>
  <p v-else-if="!visible.length" class="card muted" style="text-align: center">Nenhum pedido neste filtro.</p>

  <div class="orders">
    <div v-for="o in visible" :key="o.id" class="card order" :class="{ fresh: o.status === 'novo' }">
      <div class="spread">
        <h3 style="margin: 0">#{{ o.number }} · {{ o.customer_name }} <SourceBadge v-if="o.source && o.source !== 'site'" :source="o.source" /></h3>
        <span :class="['badge', STATUS[o.status].badge]">{{ STATUS[o.status].label }}</span>
      </div>
      <small>{{ formatDate(o.created_at, tz, { day: '2-digit', month: '2-digit' }) }} às {{ formatTime(o.created_at, tz) }}</small>

      <ul class="items">
        <li v-for="(i, n) in o.order_items" :key="n"><strong>{{ i.qty }}x</strong> {{ i.name }} <span class="muted">{{ money(i.total) }}</span></li>
      </ul>

      <div class="meta">
        <span><Icon :name="o.mode === 'entrega' ? 'truck' : 'bag'" />{{ o.mode === 'entrega' ? o.address : 'Retirada no local' }}</span>
        <span v-if="o.fee_pending" class="fee-pending"><Icon name="whatsapp" />Bairro fora da lista: combine a taxa de entrega com o cliente</span>
        <span><Icon name="card" />{{ o.payment }}<template v-if="o.change_for"> · troco p/ {{ money(o.change_for) }}</template></span>
        <span v-if="o.notes"><Icon name="clipboard" />{{ o.notes }}</span>
        <span v-if="waState(o) === 'ok'" class="wa-ok"><Icon name="whatsapp" />Cliente abriu o WhatsApp com o pedido</span>
        <span v-else-if="waState(o) === 'missing'" class="wa-missing">
          <Icon name="whatsapp" />Cliente não abriu o WhatsApp. Confirme o pedido pelo botão "Avisar cliente".
        </span>
      </div>

      <div class="spread" style="margin-top: 12px">
        <div>
          <strong style="font-size: 1.15rem">{{ money(o.total) }}</strong>
          <small v-if="o.fee_pending"> + entrega a combinar</small>
          <small v-if="Number(o.discount)"> (desconto {{ money(o.discount) }} · {{ o.coupon_code }})</small>
        </div>
        <div class="chips">
          <button class="btn small secondary" title="Imprimir comanda" @click="printOrder(o, biz.business)">
            <Icon name="printer" style="width: 15px; height: 15px" />Imprimir
          </button>
          <a v-if="customerLink(o)" class="btn small secondary" :href="customerLink(o)" target="_blank" rel="noopener">
            <Icon name="whatsapp" style="width: 15px; height: 15px" />Avisar cliente
          </a>
          <button v-if="STATUS[o.status].next" class="btn small" @click="setStatus(o, STATUS[o.status].next)">{{ STATUS[o.status].action }}</button>
          <button v-if="['novo', 'preparando'].includes(o.status)" class="btn small danger" @click="cancelOrder(o)">Cancelar</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.orders { display: grid; gap: 12px; }
.period { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; margin-bottom: 16px; }
.period-input { width: auto; padding: 7px 10px; }
.period-sum { font-size: 0.92rem; }
.order-settings { display: grid; gap: 10px; margin-bottom: 14px; padding: 14px 16px; }
.order-settings .opt { display: flex; gap: 10px; align-items: flex-start; cursor: pointer; }
.order-settings .opt input { margin-top: 3px; flex-shrink: 0; }
.order-settings .opt strong { display: block; font-size: 0.92rem; }
.order-settings .opt small { display: block; color: var(--muted); font-size: 0.8rem; margin-top: 2px; }
.order-settings .link-btn { font-size: 0.8rem; padding: 0; }
.print-help { font-size: 0.85rem; color: var(--silver); padding: 10px 12px; border-radius: 12px; background: var(--surface); border: 1px solid var(--border); }
.print-help p { margin: 0 0 6px; }
.print-help ol { margin: 0 0 6px; padding-left: 20px; display: grid; gap: 4px; }
.print-help code { background: rgba(255, 255, 255, 0.08); padding: 1px 5px; border-radius: 5px; }
.sound-btn { justify-self: start; }
.sound-off { animation: pulse-sound 1.6s ease-in-out infinite; }
@keyframes pulse-sound { 50% { box-shadow: 0 0 0 6px var(--brand-glow); } }
.sold-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.eye-btn { width: 34px; height: 34px; border-radius: 999px; display: grid; place-items: center; flex-shrink: 0;
  background: transparent; border: 1px solid var(--border); color: var(--muted); cursor: pointer; }
.eye-btn:hover { color: var(--text); border-color: var(--border-strong); }
.eye-btn svg { width: 17px; height: 17px; }
.orders-head-right { display: flex; flex-direction: column; align-items: stretch; gap: 8px; }
@media (max-width: 640px) { .orders-head-right { width: 100%; } }
.card + .card { margin-top: 0; }
.order.fresh { border-color: rgba(251, 191, 36, 0.5); box-shadow: 0 0 20px rgba(251, 191, 36, 0.12); }
.items { list-style: none; padding: 0; margin: 12px 0; display: grid; gap: 4px; }
.meta { display: grid; gap: 6px; font-size: 0.88rem; color: var(--silver); }
.meta span { display: flex; gap: 8px; align-items: flex-start; }
.meta svg { width: 16px; height: 16px; flex-shrink: 0; margin-top: 2px; color: var(--brand-ink); }
.meta .fee-pending { color: #fbbf24; font-weight: 600; }
.meta .fee-pending svg { color: #fbbf24; }
.meta .wa-ok, .meta .wa-ok svg { color: #4ade80; }
.meta .wa-missing { color: #fbbf24; font-weight: 600; }
.meta .wa-missing svg { color: #fbbf24; }
</style>
