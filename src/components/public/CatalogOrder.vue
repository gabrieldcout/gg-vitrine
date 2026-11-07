<script setup>
import { ref, computed, watch, onUnmounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { money } from '@/lib/format'
import { isOpenNow, nextOpening, hoursSummary } from '@/lib/store-hours'
import { waLink } from '@/lib/whatsapp'
import Icon from '@/components/Icon.vue'

const props = defineProps({ business: { type: Object, required: true } })

const store = computed(() => props.business.store)
const tz = computed(() => props.business.timezone)
const categories = computed(() => (props.business.menu ?? []).filter((c) => c.items.length))
const allItems = computed(() => categories.value.flatMap((c) => c.items))
// Destaques (marcados em Produtos): faixa no topo do cardápio.
const featured = computed(() => allItems.value.filter((i) => i.featured && i.available))
const hasCoupons = computed(() => props.business.features.includes('cupons'))

// Reavalia aberto/fechado a cada minuto, para quem deixa a página aberta.
const tick = ref(0)
const timer = setInterval(() => { tick.value++ }, 60000)
onUnmounted(() => clearInterval(timer))
const openNow = computed(() => tick.value >= 0 && isOpenNow(store.value.hours, tz.value))
const canOrder = computed(() => props.business.live && store.value.accepting_orders && openNow.value)
const closedReason = computed(() => {
  if (!props.business.live) return 'Esta loja não está recebendo pedidos online no momento.'
  if (!store.value.accepting_orders) return 'A loja pausou os pedidos por enquanto.'
  if (!openNow.value) {
    const next = nextOpening(store.value.hours, tz.value)
    return next ? `Fechado agora · abre ${next}` : 'Fechado agora'
  }
  return ''
})
const schedule = computed(() => hoursSummary(store.value.hours))
// Taxa por bairro: com bairros cadastrados, o cliente escolhe numa lista.
const zones = computed(() => store.value.zones ?? [])
const hasZones = computed(() => zones.value.length > 0)
// Bairro fora da lista: o pedido vai com a taxa de entrega a combinar.
const OTHER = '__outro'
const allowOther = computed(() => store.value.delivery_other === true)
const feeLabel = computed(() => {
  if (!hasZones.value) return Number(store.value.delivery_fee) ? money(store.value.delivery_fee) : 'grátis'
  const fees = zones.value.map((z) => Number(z.fee))
  const min = Math.min(...fees)
  const max = Math.max(...fees)
  if (max === 0) return 'grátis'
  return min === max ? money(min) : `a partir de ${min ? money(min) : 'grátis'}`
})
const showHours = ref(false)

// ---------------- Sacola ----------------
// Cada linha da sacola é um produto com os adicionais escolhidos:
// { chave: { itemId, qty, addons: [ids das opções], note } }. Produto sem
// adicionais usa o próprio id como chave.
const cart = ref({})
const itemsById = computed(() => Object.fromEntries(allItems.value.map((i) => [i.id, i])))
const groupsOf = (item) => (item.addon_groups ?? []).filter((g) => g.options?.length)
const hasAddons = (item) => groupsOf(item).length > 0
function addonObjs(item, ids) {
  return groupsOf(item).flatMap((g) => g.options.filter((o) => ids.includes(o.id))
    .map((o) => ({ id: o.id, group: g.name, name: o.name, price: Number(o.price) || 0 })))
}
const cartLines = computed(() => Object.entries(cart.value).map(([key, c]) => {
  const item = itemsById.value[c.itemId]
  if (!item) return null
  const addons = addonObjs(item, c.addons)
  const unit = Number(item.price) + addons.reduce((sum, a) => sum + a.price, 0)
  return { key, id: item.id, name: item.name, qty: c.qty, addons, note: c.note, unit, total: unit * c.qty }
}).filter(Boolean))
const cartCount = computed(() => cartLines.value.reduce((n, l) => n + l.qty, 0))
const subtotal = computed(() => cartLines.value.reduce((s, l) => s + l.total, 0))
const qtyOf = (item) => cartLines.value.filter((l) => l.id === item.id).reduce((n, l) => n + l.qty, 0)

function bump(key, delta, line) {
  const cur = cart.value[key] ?? line
  const qty = (cur?.qty ?? 0) + delta
  const next = { ...cart.value }
  if (qty > 0) next[key] = { ...cur, qty: Math.min(qty, 99) }
  else delete next[key]
  cart.value = next
}
function add(item) {
  if (!item.available || !canOrder.value) return
  if (hasAddons(item)) { openPicker(item); return }
  bump(item.id, 1, { itemId: item.id, qty: 0, addons: [], note: '' })
}
function remove(item) { bump(item.id, -1) }

// ---------------- Escolha de adicionais ----------------
const picker = ref(null)   // { item, chosen: { groupId: [optionIds] }, note, qty }
function openPicker(item) {
  picker.value = { item, chosen: Object.fromEntries(groupsOf(item).map((g) => [g.id, []])), note: '', qty: 1, tried: false }
}
const maxOf = (g) => (g.max == null || g.max === '' ? Infinity : Number(g.max))
function toggleOption(g, o) {
  const list = picker.value.chosen[g.id]
  const i = list.indexOf(o.id)
  if (i >= 0) list.splice(i, 1)
  else if (maxOf(g) === 1) list.splice(0, list.length, o.id)   // escolhe 1: troca
  else if (list.length < maxOf(g)) list.push(o.id)
}
function groupRule(g) {
  const max = maxOf(g)
  if (Number(g.min) > 0) return max === 1 ? 'Escolha 1 (obrigatório)' : max === Infinity ? 'Escolha pelo menos 1' : `Escolha de 1 até ${max}`
  return max === Infinity ? 'Escolha quantos quiser' : `Selecione até ${max} ${max === 1 ? 'opção' : 'opções'}`
}
const missingGroups = computed(() => picker.value
  ? groupsOf(picker.value.item).filter((g) => picker.value.chosen[g.id].length < (Number(g.min) || 0)) : [])
const pickerUnit = computed(() => {
  if (!picker.value) return 0
  const ids = Object.values(picker.value.chosen).flat()
  return Number(picker.value.item.price) + addonObjs(picker.value.item, ids).reduce((sum, a) => sum + a.price, 0)
})
function confirmPicker() {
  const p = picker.value
  if (missingGroups.value.length) { p.tried = true; return }
  // Mesma ordem dos grupos/opções do produto, pra combinação igual cair na mesma linha.
  const ids = addonObjs(p.item, Object.values(p.chosen).flat()).map((a) => a.id)
  const note = p.note.trim().slice(0, 200)
  const key = `${p.item.id}|${ids.join(',')}|${note}`
  bump(key, p.qty, { itemId: p.item.id, qty: 0, addons: ids, note })
  picker.value = null
}

// ---------------- Finalizar ----------------
const checkoutOpen = ref(false)
const placed = ref(null)   // resposta do place_order
const error = ref('')
const busy = ref(false)

const STORAGE_KEY = 'gg-vitrine-cliente'
function loadSaved() {
  try { return JSON.parse(localStorage.getItem(STORAGE_KEY)) ?? {} } catch { return {} }
}
const saved = loadSaved()
const form = ref({
  name: saved.name ?? '', phone: saved.phone ?? '',
  mode: store.value.pickup_enabled ? 'retirada' : 'entrega',
  street: saved.street ?? '', number: saved.number ?? '', district: saved.district ?? '', reference: saved.reference ?? '',
  payment: 'pix', change: '', notes: '',
  zone: '',
})
// Recupera o bairro salvo da última compra, se ele ainda estiver na lista.
form.value.zone = zones.value.find((z) => z.name === saved.district)?.id
  ?? (allowOther.value && saved.district ? OTHER : '')
const zone = computed(() => zones.value.find((z) => z.id === form.value.zone))
const otherZone = computed(() => hasZones.value && form.value.zone === OTHER)
watch(() => form.value.zone, (id, old) => {
  if (zone.value) form.value.district = zone.value.name
  else if (id === OTHER && old && old !== OTHER) form.value.district = ''
})
watch(() => [form.value.name, form.value.phone, form.value.street, form.value.number, form.value.district, form.value.reference], () => {
  const { name, phone, street, number, district, reference } = form.value
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify({ name, phone, street, number, district, reference })) } catch { /* sem armazenamento local */ }
})

// ---------------- Cupom ----------------
const couponCode = ref('')
const coupon = ref(null)
const couponError = ref('')
watch(subtotal, () => { if (coupon.value) applyCoupon() })

async function applyCoupon() {
  couponError.value = ''
  const { data, error: err } = await supabase.rpc('check_coupon', {
    p_business: props.business.id, p_code: couponCode.value, p_subtotal: subtotal.value,
  })
  if (err) { couponError.value = err.message; return }
  if (!data.valid) { coupon.value = null; couponError.value = data.message; return }
  coupon.value = data
}

const deliveryFee = computed(() => {
  if (form.value.mode !== 'entrega') return 0
  if (hasZones.value) return otherZone.value ? 0 : Number(zone.value?.fee ?? 0)
  return Number(store.value.delivery_fee)
})
const discount = computed(() => Number(coupon.value?.discount ?? 0))
const baseTotal = computed(() => Math.max(subtotal.value + deliveryFee.value - discount.value, 0))
const belowMinimum = computed(() => Number(store.value.min_order) > 0 && subtotal.value < Number(store.value.min_order))

// Formas de pagamento que a loja aceita (Funcionamento). Antes da migration
// 0031 a loja não manda a lista e vale o jeito antigo (cartão sem acréscimo).
const newPayments = computed(() => Array.isArray(store.value.payment_methods))
const ALL_PAYMENTS = { pix: 'PIX', dinheiro: 'Dinheiro', debito: 'Cartão de débito', credito: 'Cartão de crédito' }
const PAYMENTS = computed(() => newPayments.value
  ? Object.fromEntries(store.value.payment_methods.filter((k) => ALL_PAYMENTS[k]).map((k) => [k, ALL_PAYMENTS[k]]))
  : { pix: 'PIX', dinheiro: 'Dinheiro', cartao: 'Cartão na entrega/retirada' })
watch(PAYMENTS, (list) => { if (!list[form.value.payment]) form.value.payment = Object.keys(list)[0] }, { immediate: true })
const isCard = computed(() => ['debito', 'credito'].includes(form.value.payment))
const cardFeePct = computed(() => (newPayments.value ? Number(store.value.card_fee_pct) || 0 : 0))
// Mesma conta do banco (place_order): acréscimo sobre a compra (produtos com
// desconto), sem a taxa de entrega, arredondado.
const cardFee = computed(() => (isCard.value
  ? Math.round(Math.max(subtotal.value - discount.value, 0) * cardFeePct.value) / 100 : 0))
const total = computed(() => baseTotal.value + cardFee.value)
const pctLabel = (n) => `${String(Number(n)).replace('.', ',')}%`
const paymentLabel = computed(() => {
  const label = PAYMENTS.value[form.value.payment]
  if (!isCard.value) return label
  return `${label} (maquininha na ${form.value.mode === 'entrega' ? 'entrega' : 'retirada'})`
})

// Chave PIX da loja: o cliente paga direto pro lojista e manda o comprovante no WhatsApp.
const pixKey = computed(() => store.value.pix_key?.trim() || '')
const pixName = computed(() => store.value.pix_name?.trim() || props.business.name)
const showPix = computed(() => form.value.payment === 'pix' && Boolean(pixKey.value))
const pixCopied = ref(false)
async function copyPix() {
  try {
    await navigator.clipboard.writeText(pixKey.value)
  } catch {
    const t = document.createElement('textarea')
    t.value = pixKey.value
    document.body.appendChild(t); t.select(); document.execCommand('copy'); t.remove()
  }
  pixCopied.value = true
  setTimeout(() => { pixCopied.value = false }, 2000)
}

function address() {
  const f = form.value
  return [`${f.street}, ${f.number} - ${f.district}`, f.reference && `Ref.: ${f.reference}`].filter(Boolean).join(' · ')
}

function buildMessage(order) {
  const f = form.value
  const lines = [`*Pedido #${order.number}: ${props.business.name}*`, '']
  for (const l of order.items) {
    lines.push(`${l.qty}x ${l.name}: ${money(l.total)}`)
    for (const a of l.addons ?? []) lines.push(`   + ${a.name}${Number(a.price) ? ` (${money(a.price)})` : ''}`)
    if (l.note) lines.push(`   Obs.: ${l.note}`)
  }
  lines.push('', `Subtotal: ${money(order.subtotal)}`)
  if (order.fee_pending) lines.push('Entrega: *a combinar* (meu bairro não está na lista)')
  else if (Number(order.delivery_fee)) lines.push(`Entrega: ${money(order.delivery_fee)}`)
  if (Number(order.discount)) lines.push(`Desconto (${order.coupon}): -${money(order.discount)}`)
  if (Number(order.card_fee)) lines.push(`Acréscimo do cartão (${pctLabel(cardFeePct.value)}): ${money(order.card_fee)}`)
  lines.push(`*Total: ${money(order.total)}*`, '')
  lines.push(`*Cliente:* ${f.name}`, `*Telefone:* ${f.phone}`)
  lines.push(f.mode === 'entrega' ? `*Entregar em:* ${address()}` : '*Retirada no local*')
  let payment = order.payment ?? paymentLabel.value
  if (f.payment === 'dinheiro' && f.change) payment += ` (troco para ${money(f.change)})`
  lines.push(`*Pagamento:* ${payment}`)
  if (f.payment === 'pix' && pixKey.value) lines.push('Vou pagar pela chave PIX da loja e mandar o comprovante aqui.')
  if (f.notes) lines.push(`*Observações:* ${f.notes}`)
  return lines.join('\n')
}

// Link pra conversa da loja com o pedido já escrito. Vai num botão que o
// cliente toca: abrir sozinho depois de salvar o pedido é bloqueado no celular.
const placedLink = computed(() => placed.value && waLink(props.business.phone, buildMessage(placed.value)))

// Avisa o painel que o cliente abriu a conversa (não espera, nem trava o link).
function markWhatsApp(id = placed.value?.id) {
  if (id) supabase.rpc('mark_order_whatsapp', { p_order: id }).then(() => {}, () => {})
}

// Mandar no WhatsApp é obrigatório: até tocar no botão, não dá pra fechar
// nem fazer outro pedido, e sair da página pede confirmação. (Não tem como
// saber se ele enviou mesmo, só que abriu a conversa.)
const waSent = ref(false)
const waNudge = ref(false)
function sendWhatsApp() {
  waSent.value = true
  waNudge.value = false
  markWhatsApp()
}
function nudgeWhatsApp() {
  waNudge.value = false
  requestAnimationFrame(() => { waNudge.value = true })
}
const mustSend = computed(() => !!placed.value && !!placedLink.value && !waSent.value)
function onBeforeUnload(e) {
  if (!mustSend.value) return
  e.preventDefault()
  e.returnValue = ''
}
window.addEventListener('beforeunload', onBeforeUnload)
onUnmounted(() => window.removeEventListener('beforeunload', onBeforeUnload))

// ---------------- Último pedido (evita pedido duplicado) ----------------
// Fica guardado no celular do cliente, sem login: se ele voltar achando que
// o pedido não foi, vê que já foi e pode só mandar no WhatsApp.
const LAST_KEY = `gg-vitrine-ultimo-pedido-${props.business.id}`
const RECENT_MS = 3 * 60 * 60 * 1000
function readLast() {
  try {
    const v = JSON.parse(localStorage.getItem(LAST_KEY))
    return v && Date.now() - v.at < RECENT_MS ? v : null
  } catch { return null }
}
const lastOrder = ref(readLast())
const lastDismissed = ref(false)
const cartSignature = () => cartLines.value.map((l) => `${l.key}:${l.qty}`).sort().join(',')
const timeOf = (ms) => new Date(ms).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: tz.value })

// ---------------- Pedir de novo ----------------
// O último pedido fica guardado neste celular (sem login) pra repetir com um
// toque. Só volta pra sacola o que ainda existe e está disponível.
const REORDER_KEY = `gg-vitrine-pedir-de-novo-${props.business.id}`
function readReorder() {
  try {
    const v = JSON.parse(localStorage.getItem(REORDER_KEY))
    return v && Date.now() - v.at < 120 * 864e5 && v.lines?.length ? v : null
  } catch { return null }
}
const reorder = ref(readReorder())
const reorderLines = computed(() => (reorder.value?.lines ?? [])
  .map((l) => {
    const item = itemsById.value[l.itemId]
    if (!item || !item.available) return null
    // Adicional que saiu do produto não volta.
    const addons = addonObjs(item, l.addons ?? []).map((a) => a.id)
    return { ...l, item, addons }
  }).filter(Boolean))
const reorderSummary = computed(() => reorderLines.value.map((l) => `${l.qty}x ${l.item.name}`).join(', '))
const reorderDate = computed(() => reorder.value && new Date(reorder.value.at)
  .toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: tz.value }))
function orderAgain() {
  if (!canOrder.value) return
  const next = {}
  for (const l of reorderLines.value) {
    const key = l.addons.length || l.note ? `${l.itemId}|${l.addons.join(',')}|${l.note ?? ''}` : l.itemId
    next[key] = { itemId: l.itemId, qty: l.qty, addons: l.addons, note: l.note ?? '' }
  }
  cart.value = next
  checkoutOpen.value = true
}
function saveReorder() {
  const v = { at: Date.now(), lines: Object.values(cart.value).map((c) => ({ itemId: c.itemId, qty: c.qty, addons: c.addons, note: c.note })) }
  reorder.value = v
  try { localStorage.setItem(REORDER_KEY, JSON.stringify(v)) } catch { /* sem armazenamento local */ }
}

function saveLast(order) {
  saveReorder()
  const v = { id: order.id, number: order.number, total: order.total, at: Date.now(), sig: cartSignature(), link: placedLink.value }
  lastOrder.value = v
  lastDismissed.value = true   // acabou de fazer: o aviso só aparece quando ele voltar
  try { localStorage.setItem(LAST_KEY, JSON.stringify(v)) } catch { /* sem armazenamento local */ }
}

async function send() {
  error.value = ''
  if (belowMinimum.value) { error.value = `O pedido mínimo é ${money(store.value.min_order)}.`; return }
  if (form.value.payment === 'dinheiro' && Number(form.value.change) && Number(form.value.change) < total.value) {
    error.value = `O troco precisa ser para um valor maior que o total (${money(total.value)}).`; return
  }
  const last = readLast()
  if (last && last.sig === cartSignature() &&
      !confirm(`Você já fez um pedido igual a esse (#${last.number}) às ${timeOf(last.at)}.

` +
        'Se ainda não mandou no WhatsApp, é só mandar aquele. Quer fazer outro pedido mesmo assim?')) {
    checkoutOpen.value = false
    lastDismissed.value = false
    window.scrollTo({ top: 0, behavior: 'smooth' })
    return
  }
  const f = form.value
  busy.value = true
  const { data, error: err } = await supabase.rpc('place_order', {
    p_business: props.business.id,
    p_items: cartLines.value.map((l) => ({ id: l.id, qty: l.qty, addons: l.addons.map((a) => a.id), note: l.note || null })),
    p_name: f.name, p_phone: f.phone, p_mode: f.mode,
    p_address: f.mode === 'entrega' ? address() : null,
    p_payment: paymentLabel.value, p_change: f.payment === 'dinheiro' && f.change ? Number(f.change) : null,
    ...(newPayments.value ? { p_method: f.payment } : {}),
    p_notes: f.notes || null, p_coupon: coupon.value?.code ?? null,
    p_zone: f.mode === 'entrega' && hasZones.value && !otherZone.value ? f.zone : null,
  })
  busy.value = false
  if (err) { error.value = err.message; return }
  waSent.value = false
  waNudge.value = false
  placed.value = data
  saveLast(data)
}

// Fechar a janela depois do pedido feito equivale a "fazer outro pedido".
function closeSheet() {
  if (mustSend.value) nudgeWhatsApp()
  else if (placed.value) finish()
  else checkoutOpen.value = false
}

function finish() {
  if (mustSend.value) { nudgeWhatsApp(); return }
  cart.value = {}
  placed.value = null
  checkoutOpen.value = false
  coupon.value = null
  couponCode.value = ''
  form.value.notes = ''
  form.value.change = ''
}

function scrollTo(id) {
  document.getElementById(`cat-${id}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}
</script>

<template>
  <div :style="{ paddingBottom: cartCount ? '90px' : '0' }">
    <div v-if="lastOrder && !lastDismissed" class="last-order">
      <div class="last-order-text">
        <strong>Você já fez o pedido #{{ lastOrder.number }} às {{ timeOf(lastOrder.at) }} ({{ money(lastOrder.total) }})</strong>
        <small>A loja já recebeu. Se ainda não mandou a mensagem no WhatsApp, toque abaixo.</small>
      </div>
      <div class="last-order-actions">
        <a v-if="lastOrder.link" class="btn small wa-send" :href="lastOrder.link" target="_blank" rel="noopener" @click="markWhatsApp(lastOrder.id)">
          <Icon name="whatsapp" style="width: 16px; height: 16px" />Enviar no WhatsApp
        </a>
        <button type="button" class="btn small secondary" @click="lastDismissed = true">Fazer outro pedido</button>
      </div>
    </div>
    <div class="status-row">
      <span :class="['badge', canOrder ? 'green' : 'red']">{{ canOrder ? 'Aberto agora' : 'Fechado' }}</span>
      <button v-if="schedule.length" class="link-btn" @click="showHours = !showHours">{{ showHours ? 'ocultar horários' : 'ver horários' }}</button>
    </div>
    <div v-if="showHours" class="card hours">
      <div v-for="d in schedule" :key="d.name" class="spread"><span>{{ d.name }}</span><span class="muted">{{ d.ranges.join(' e ') }}</span></div>
    </div>

    <div v-if="closedReason" class="notice closed">{{ closedReason }}</div>

    <div class="info">
      <span v-if="store.pickup_enabled"><Icon name="bag" />Retirada no local</span>
      <span v-if="store.delivery_enabled"><Icon name="truck" />Entrega {{ feeLabel }}</span>
      <span v-if="Number(store.min_order)">Pedido mínimo {{ money(store.min_order) }}</span>
    </div>
    <p v-if="store.delivery_enabled && store.delivery_area" class="muted" style="font-size: 0.88rem">
      Entregamos em: {{ store.delivery_area }}
    </p>

    <div v-if="reorderLines.length && (!lastOrder || lastDismissed) && !cartCount" class="reorder card">
      <div class="reorder-text">
        <strong>Seu último pedido · {{ reorderDate }}</strong>
        <small class="muted">{{ reorderSummary }}</small>
      </div>
      <button type="button" class="btn small" :disabled="!canOrder" @click="orderAgain">
        <Icon name="bag" style="width: 15px; height: 15px" />Pedir de novo
      </button>
    </div>

    <section v-if="featured.length" class="featured">
      <h2>Destaques</h2>
      <div class="featured-row">
        <button v-for="i in featured" :key="i.id" type="button" class="featured-card" :disabled="!canOrder" @click="add(i)">
          <img v-if="i.photo_url" :src="i.photo_url" :alt="i.name" loading="lazy" />
          <div v-else class="featured-noimg"><Icon name="utensils" /></div>
          <span class="featured-name">{{ i.name }}</span>
          <span class="featured-foot">
            <span class="price">{{ money(i.price) }}</span>
            <span class="featured-add" aria-hidden="true"><Icon name="plus" /></span>
          </span>
          <span v-if="qtyOf(i)" class="featured-qty">{{ qtyOf(i) }}</span>
        </button>
      </div>
    </section>

    <nav v-if="categories.length > 1" class="cat-nav">
      <button v-for="c in categories" :key="c.id" class="chip" @click="scrollTo(c.id)">{{ c.name }}</button>
    </nav>

    <p v-if="!categories.length" class="card muted" style="text-align: center">Os produtos ainda estão sendo cadastrados.</p>

    <section v-for="c in categories" :id="`cat-${c.id}`" :key="c.id" class="category">
      <h2>{{ c.name }}</h2>
      <div class="items">
        <div v-for="i in c.items" :key="i.id" class="card item" :class="{ off: !i.available }">
          <div class="item-text">
            <strong>{{ i.name }}</strong>
            <p v-if="i.description" class="muted">{{ i.description }}</p>
            <div class="item-foot">
              <span class="price">{{ money(i.price) }}</span>
              <span v-if="!i.available" class="badge red">Esgotado</span>
              <template v-else-if="hasAddons(i)">
                <button class="btn small" :disabled="!canOrder" @click="add(i)">
                  <Icon name="plus" style="width: 15px; height: 15px" />{{ qtyOf(i) ? `Adicionar (${qtyOf(i)} na sacola)` : 'Adicionar' }}
                </button>
              </template>
              <div v-else-if="qtyOf(i)" class="stepper">
                <button aria-label="Diminuir" @click="remove(i)"><Icon name="minus" /></button>
                <span>{{ qtyOf(i) }}</span>
                <button aria-label="Aumentar" @click="add(i)"><Icon name="plus" /></button>
              </div>
              <button v-else class="btn small" :disabled="!canOrder" @click="add(i)">
                <Icon name="plus" style="width: 15px; height: 15px" />Adicionar
              </button>
            </div>
          </div>
          <img v-if="i.photo_url" :src="i.photo_url" :alt="i.name" class="item-photo" loading="lazy" />
        </div>
      </div>
    </section>

    <!-- Escolha de adicionais -->
    <div v-if="picker" class="sheet-backdrop" @click.self="picker = null">
      <div class="sheet picker">
        <img v-if="picker.item.photo_url" :src="picker.item.photo_url" :alt="picker.item.name" class="picker-photo" />
        <div class="picker-head">
          <div>
            <h2 style="margin: 0">{{ picker.item.name }}</h2>
            <p v-if="picker.item.description" class="muted" style="margin: 4px 0 0">{{ picker.item.description }}</p>
          </div>
          <button type="button" class="btn small secondary" aria-label="Fechar" @click="picker = null">✕</button>
        </div>
        <p class="price" style="margin: 8px 0 0">{{ money(picker.item.price) }}</p>

        <div v-for="g in groupsOf(picker.item)" :key="g.id" class="pick-group"
             :class="{ missing: picker.tried && missingGroups.includes(g) }">
          <div class="pick-head">
            <strong>{{ g.name }}</strong>
            <small>{{ groupRule(g) }}</small>
          </div>
          <div class="pick-options">
            <button v-for="o in g.options" :key="o.id" type="button" class="pick-option"
                    :class="{ selected: picker.chosen[g.id].includes(o.id) }"
                    :disabled="!picker.chosen[g.id].includes(o.id) && maxOf(g) > 1 && picker.chosen[g.id].length >= maxOf(g)"
                    @click="toggleOption(g, o)">
              <span class="pick-box"><Icon v-if="picker.chosen[g.id].includes(o.id)" name="check" /></span>
              <span><strong>{{ o.name }}</strong><small v-if="Number(o.price)">+ {{ money(o.price) }}</small></span>
            </button>
          </div>
          <small v-if="picker.tried && missingGroups.includes(g)" class="pick-error">Escolha uma opção aqui pra continuar.</small>
        </div>

        <div class="field" style="margin-top: 14px">
          <label>Observação <small>(opcional)</small></label>
          <input v-model="picker.note" maxlength="200" placeholder="Ex.: sem cebola, bem passado" />
        </div>

        <div class="picker-foot">
          <div class="stepper">
            <button type="button" aria-label="Diminuir" :disabled="picker.qty <= 1" @click="picker.qty--"><Icon name="minus" /></button>
            <span>{{ picker.qty }}</span>
            <button type="button" aria-label="Aumentar" @click="picker.qty = Math.min(picker.qty + 1, 99)"><Icon name="plus" /></button>
          </div>
          <button type="button" class="btn large" style="flex: 1" @click="confirmPicker">
            Adicionar · {{ money(pickerUnit * picker.qty) }}
          </button>
        </div>
      </div>
    </div>

    <!-- Barra da sacola -->
    <div v-if="cartCount && !checkoutOpen" class="cart-bar">
      <button class="btn large block" @click="checkoutOpen = true">
        <Icon name="bag" style="width: 20px; height: 20px" />
        Ver sacola · {{ cartCount }} {{ cartCount === 1 ? 'item' : 'itens' }} · {{ money(subtotal) }}
      </button>
    </div>

    <!-- Finalização -->
    <div v-if="checkoutOpen" class="sheet-backdrop" @click.self="closeSheet">
      <div class="sheet">
        <div v-if="placed" class="done">
          <div class="done-icon"><Icon name="check" /></div>
          <h2 class="gradient-text">Pedido #{{ placed.number }} anotado!</h2>
          <p><strong>Total: {{ money(placed.total) }}</strong></p>
          <p v-if="placed.fee_pending" class="muted">A taxa de entrega do seu bairro será informada pela loja no WhatsApp.</p>
          <div v-if="showPix" class="pix-box">
            <small>Pague por PIX para <strong>{{ pixName }}</strong> e mande o comprovante no WhatsApp</small>
            <div class="pix-key"><code>{{ pixKey }}</code><button type="button" class="btn small" @click="copyPix">{{ pixCopied ? 'Copiado!' : 'Copiar chave' }}</button></div>
          </div>
          <template v-if="placedLink">
            <div v-if="!waSent" class="action-needed wa-required" :class="{ nudge: waNudge }" role="alert">
              <Icon name="whatsapp" />
              <span><strong>Ação necessária</strong>Seu pedido só fica completo depois que você enviar a mensagem no WhatsApp da loja. Toque no botão verde abaixo e depois em <b>enviar</b> na conversa.</span>
            </div>
            <div v-else class="wa-sent-note">
              <Icon name="check" />
              <span>Conversa aberta. Confira se você tocou em <b>enviar</b> no WhatsApp. Não abriu? Toque no botão de novo.</span>
            </div>
            <a class="btn large block wa-send" :class="{ pulse: !waSent }" :href="placedLink" target="_blank" rel="noopener" @click="sendWhatsApp">
              <Icon name="whatsapp" style="width: 22px; height: 22px" />{{ waSent ? 'Abrir o WhatsApp de novo' : 'Enviar pedido no WhatsApp' }}
            </a>
          </template>
          <p v-else class="muted">A loja já recebeu seu pedido.</p>
          <button v-if="!mustSend" class="btn secondary block" style="margin-top: 10px" @click="finish">Fazer outro pedido</button>
        </div>

        <form v-else @submit.prevent="send">
          <div class="spread" style="margin-bottom: 12px">
            <h2 style="margin: 0">Sua sacola</h2>
            <button type="button" class="btn small secondary" @click="checkoutOpen = false">Continuar comprando</button>
          </div>
          <div v-for="l in cartLines" :key="l.key" class="line">
            <div class="stepper small">
              <button type="button" @click="bump(l.key, -1)"><Icon name="minus" /></button>
              <span>{{ l.qty }}</span>
              <button type="button" @click="bump(l.key, 1)"><Icon name="plus" /></button>
            </div>
            <span style="flex: 1">
              {{ l.name }}
              <small v-if="l.addons.length" class="line-extra">+ {{ l.addons.map((a) => a.name).join(', ') }}</small>
              <small v-if="l.note" class="line-extra">Obs.: {{ l.note }}</small>
            </span>
            <strong>{{ money(l.total) }}</strong>
          </div>

          <div v-if="store.pickup_enabled && store.delivery_enabled" class="tabs" style="margin-top: 18px">
            <button type="button" :class="{ on: form.mode === 'retirada' }" @click="form.mode = 'retirada'">Retirar no local</button>
            <button type="button" :class="{ on: form.mode === 'entrega' }" @click="form.mode = 'entrega'">Entrega</button>
          </div>
          <p v-if="form.mode === 'retirada' && business.address" class="muted" style="font-size: 0.88rem; margin-top: 10px">
            Retirada em: {{ business.address }}
          </p>

          <div class="row" style="margin-top: 16px">
            <div class="field"><label>Seu nome</label><input v-model="form.name" required autocomplete="name" /></div>
            <div class="field"><label>WhatsApp</label><input v-model="form.phone" type="tel" required autocomplete="tel" /></div>
          </div>

          <template v-if="form.mode === 'entrega'">
            <div class="row">
              <div class="field" style="flex-basis: 240px"><label>Rua</label><input v-model="form.street" required autocomplete="address-line1" /></div>
              <div class="field" style="max-width: 110px"><label>Número</label><input v-model="form.number" required /></div>
            </div>
            <div class="row">
              <div v-if="hasZones" class="field" style="flex: 1 1 100%">
                <label>Bairro</label>
                <select v-model="form.zone" required>
                  <option value="" disabled>Escolha o bairro</option>
                  <option v-for="z in zones" :key="z.id" :value="z.id">
                    {{ z.name }} · {{ Number(z.fee) ? money(z.fee) : 'grátis' }}
                  </option>
                  <option v-if="allowOther" :value="OTHER">Meu bairro não está na lista</option>
                </select>
                <template v-if="otherZone">
                  <input v-model="form.district" required placeholder="Digite seu bairro" style="margin-top: 8px" />
                  <small class="muted">A loja te informa a taxa de entrega pelo WhatsApp.</small>
                </template>
              </div>
              <div v-else class="field"><label>Bairro</label><input v-model="form.district" required /></div>
              <div class="field"><label>Ponto de referência</label><input v-model="form.reference" required placeholder="Ex.: perto da padaria, portão azul" /></div>
            </div>
          </template>

          <div class="field">
            <label>Pagamento</label>
            <div class="chips">
              <button v-for="(label, key) in PAYMENTS" :key="key" type="button" class="chip"
                      :class="{ selected: form.payment === key }" @click="form.payment = key">{{ label }}</button>
            </div>
          </div>
          <div v-if="showPix" class="pix-box">
            <small>Chave PIX de <strong>{{ pixName }}</strong>. Você paga depois de fazer o pedido e manda o comprovante no WhatsApp.</small>
            <div class="pix-key"><code>{{ pixKey }}</code><button type="button" class="btn small" @click="copyPix">{{ pixCopied ? 'Copiado!' : 'Copiar chave' }}</button></div>
          </div>
          <div v-if="form.payment === 'dinheiro'" class="field" style="max-width: 220px">
            <label>Troco para quanto? <small>(deixe vazio se não precisar)</small></label>
            <input v-model="form.change" type="number" min="0" step="0.01" placeholder="Ex.: 100" />
            <small v-if="Number(form.change) && Number(form.change) < total" style="color: var(--danger)">O valor do troco é menor que o total ({{ money(total) }}).</small>
            <small v-else-if="Number(form.change) > total" class="muted">Seu troco: {{ money(Number(form.change) - total) }}</small>
          </div>
          <p v-if="isCard" class="card-note">
            Pague no cartão na maquininha, {{ form.mode === 'entrega' ? 'na hora da entrega' : 'na retirada' }}.
            <template v-if="cardFeePct">Pagamento no cartão tem acréscimo de {{ pctLabel(cardFeePct) }}.</template>
          </p>
          <div class="field">
            <label>Observações <small>(opcional)</small></label>
            <input v-model="form.notes" placeholder="Ex.: sem cebola, bem passado" />
          </div>
          <div v-if="hasCoupons" class="field">
            <label>Cupom de desconto <small>(opcional)</small></label>
            <div class="row">
              <input v-model="couponCode" placeholder="Ex.: PROMO10" style="text-transform: uppercase" />
              <button type="button" class="btn secondary shrink" :disabled="!couponCode" @click="applyCoupon">Aplicar</button>
            </div>
            <small v-if="coupon" style="color: var(--success)">{{ coupon.message }}</small>
            <small v-if="couponError" style="color: var(--danger)">{{ couponError }}</small>
          </div>

          <div class="totals">
            <div class="spread"><span class="muted">Subtotal</span><span>{{ money(subtotal) }}</span></div>
            <div v-if="form.mode === 'entrega'" class="spread">
              <span class="muted">Entrega{{ zone ? ` (${zone.name})` : '' }}</span>
              <span>{{ otherZone ? 'a combinar' : hasZones && !zone ? 'escolha o bairro' : money(deliveryFee) }}</span>
            </div>
            <div v-if="discount" class="spread"><span class="muted">Desconto</span><span style="color: var(--success)">-{{ money(discount) }}</span></div>
            <div v-if="cardFee" class="spread"><span class="muted">Acréscimo do cartão ({{ pctLabel(cardFeePct) }})</span><span>{{ money(cardFee) }}</span></div>
            <div class="spread total"><span>Total</span><span class="gradient-text">{{ money(total) }}</span></div>
            <small v-if="form.mode === 'entrega' && otherZone" class="muted">+ taxa de entrega, que a loja informa pelo WhatsApp</small>
          </div>

          <div v-if="belowMinimum" class="notice">Faltam {{ money(store.min_order - subtotal) }} para o pedido mínimo de {{ money(store.min_order) }}.</div>
          <div v-if="error" class="error">{{ error }}</div>

          <div v-if="business.phone" class="action-needed" style="margin: 0 0 12px">
            <Icon name="whatsapp" />
            <span><strong>Importante</strong>Depois de tocar em Fazer pedido, você vai precisar enviar o pedido no WhatsApp da loja pra ele ficar completo.</span>
          </div>
          <button class="btn large block" :disabled="!canOrder || belowMinimum || busy">
            <Icon name="whatsapp" style="width: 20px; height: 20px" />{{ busy ? 'Enviando...' : 'Fazer pedido' }}
          </button>
          <p v-if="!canOrder" class="muted" style="text-align: center; margin-top: 8px">{{ closedReason }}</p>
        </form>
      </div>
    </div>
  </div>
</template>

<style scoped>
.status-row { display: flex; gap: 12px; align-items: center; margin-bottom: 12px; font-size: 0.88rem; }
.hours { display: grid; gap: 6px; font-size: 0.9rem; margin-bottom: 14px; }
.closed { text-align: center; font-weight: 600; }
.info { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 10px; }
.info span { display: inline-flex; align-items: center; gap: 6px; padding: 6px 12px; border-radius: 999px; background: var(--surface); border: 1px solid var(--border); font-size: 0.85rem; color: var(--silver); }
.info svg { width: 16px; height: 16px; color: var(--brand-ink); }

.cat-nav { position: sticky; top: 0; z-index: 10; display: flex; gap: 8px; overflow-x: auto; padding: 12px 0; margin: 8px 0; background: linear-gradient(180deg, rgba(5, 11, 22, 0.95) 70%, transparent); backdrop-filter: blur(8px); }
.cat-nav .chip { white-space: nowrap; }

.category { padding-top: 16px; scroll-margin-top: 70px; }
.category h2 { font-size: 1.3rem; margin-bottom: 12px; }
.items { display: grid; gap: 12px; }
.card + .card { margin-top: 0; }
.item { display: flex; gap: 14px; padding: 16px; align-items: stretch; transition: border-color 0.15s ease; }
.item:hover { border-color: var(--border-strong); }
.item.off { opacity: 0.55; }
.item-text { flex: 1; min-width: 0; display: flex; flex-direction: column; }
.item-text p { font-size: 0.87rem; margin: 4px 0 0; }
.item-foot { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin-top: auto; padding-top: 12px; }
.price { font-weight: 700; font-size: 1.05rem; }
.item-photo { width: 110px; height: 110px; border-radius: 14px; object-fit: cover; flex-shrink: 0; border: 1px solid var(--border); }

.stepper { display: inline-flex; align-items: center; gap: 4px; border-radius: 999px; border: 1px solid var(--brand); background: var(--brand-soft); padding: 3px; }
.stepper button { width: 30px; height: 30px; border-radius: 50%; border: none; display: grid; place-items: center; background: linear-gradient(120deg, var(--brand), var(--brand-strong)); color: var(--brand-contrast); cursor: pointer; }
.stepper button svg { width: 15px; height: 15px; }
.stepper span { min-width: 26px; text-align: center; font-weight: 700; }
.stepper.small button { width: 26px; height: 26px; }

.cart-bar { position: fixed; left: 0; right: 0; bottom: 0; z-index: 40; padding: 14px 16px calc(14px + env(safe-area-inset-bottom)); background: linear-gradient(0deg, rgba(5, 11, 22, 0.98) 60%, transparent); }
.cart-bar .btn { max-width: 728px; margin: 0 auto; display: flex; }
.line { display: flex; align-items: center; gap: 12px; padding: 10px 0; border-bottom: 1px solid var(--border); }
.totals { display: grid; gap: 6px; padding: 14px 0; margin: 6px 0 14px; border-top: 1px solid var(--border); }
.totals .total { font-size: 1.25rem; font-weight: 800; }
.reorder { display: flex; gap: 12px; align-items: center; justify-content: space-between; margin: 0 0 16px; border-left: 3px solid var(--brand); }
.reorder-text { min-width: 0; }
.reorder-text strong { display: block; }
.reorder-text small { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.reorder .btn { flex-shrink: 0; }
.featured { margin: 0 0 18px; }
.featured h2 { margin: 0 0 10px; }
.featured-row { display: flex; gap: 12px; overflow-x: auto; padding-bottom: 6px; scroll-snap-type: x mandatory; }
.featured-card { position: relative; flex: 0 0 150px; scroll-snap-align: start; display: flex; flex-direction: column; text-align: left; padding: 0;
  border-radius: 16px; overflow: hidden; background: var(--surface); border: 1px solid var(--border); color: var(--text); font: inherit; cursor: pointer; }
.featured-card:disabled { cursor: default; }
.featured-card img, .featured-noimg { width: 100%; height: 120px; object-fit: cover; display: block; }
.featured-noimg { display: grid; place-items: center; color: var(--muted); background: rgba(255, 255, 255, 0.04); }
.featured-noimg svg { width: 28px; height: 28px; }
.featured-name { padding: 10px 10px 4px; font-weight: 700; font-size: 0.92rem; line-height: 1.25; }
.featured-foot { display: flex; align-items: center; justify-content: space-between; padding: 0 10px 10px; margin-top: auto; }
.featured-add { width: 28px; height: 28px; border-radius: 50%; display: grid; place-items: center;
  background: linear-gradient(120deg, var(--brand), var(--brand-strong)); color: var(--brand-contrast); }
.featured-add svg { width: 15px; height: 15px; }
.featured-qty { position: absolute; top: 8px; right: 8px; min-width: 24px; height: 24px; padding: 0 6px; border-radius: 999px;
  display: grid; place-items: center; font-size: 0.8rem; font-weight: 800; background: var(--brand); color: var(--brand-contrast); }
.line-extra { display: block; color: var(--muted); font-size: 0.8rem; }
.picker { padding-top: 0; }
.picker:not(:has(.picker-photo)) { padding-top: 22px; }
.picker-photo { display: block; width: calc(100% + 36px); max-width: none; margin: 0 -18px 14px; height: 200px; object-fit: cover; }
.pick-group { margin-top: 16px; padding-top: 14px; border-top: 1px solid var(--border); }
.pick-group.missing .pick-head small { color: var(--danger); }
.pick-head strong { display: block; font-size: 1rem; }
.pick-head small { color: var(--muted); font-size: 0.84rem; }
.pick-options { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 8px; margin-top: 10px; }
.pick-option { display: flex; gap: 10px; align-items: center; padding: 10px 12px; border-radius: 12px; text-align: left; cursor: pointer;
  background: var(--surface); border: 1px solid var(--border); color: var(--text); font: inherit; }
.pick-option strong { display: block; font-size: 0.92rem; }
.pick-option small { display: block; color: var(--muted); font-size: 0.82rem; }
.picker-head { display: flex; gap: 12px; align-items: flex-start; justify-content: space-between; }
.picker-head .btn { flex-shrink: 0; }
.pick-option.selected { border-color: var(--brand); background: var(--brand-soft); }
.pick-option:disabled { opacity: 0.45; cursor: not-allowed; }
.pick-box { width: 20px; height: 20px; flex-shrink: 0; border-radius: 6px; border: 2px solid var(--border); display: grid; place-items: center; }
.pick-option.selected .pick-box { background: var(--brand); border-color: var(--brand); color: var(--brand-contrast); }
.pick-box svg { width: 13px; height: 13px; }
.pick-error { display: block; margin-top: 6px; color: var(--danger); }
.picker-foot { position: sticky; bottom: calc(-22px - env(safe-area-inset-bottom)); display: flex; gap: 12px; align-items: center;
  margin: 16px -18px calc(-22px - env(safe-area-inset-bottom)); padding: 14px 18px calc(14px + env(safe-area-inset-bottom));
  background: #0a1426; border-top: 1px solid var(--border); }
.card-note { margin: 0 0 14px; padding: 10px 12px; border-radius: 12px; font-size: 0.86rem; background: var(--surface); border: 1px solid var(--border); }
.pix-box { margin: 4px 0 14px; padding: 12px 14px; border-radius: 14px; border: 1px solid rgba(50, 188, 173, 0.45); background: rgba(50, 188, 173, 0.1); text-align: left; }
.pix-box small { display: block; color: var(--silver); font-size: 0.84rem; line-height: 1.4; }
.pix-key { display: flex; align-items: center; gap: 8px; margin-top: 8px; }
.pix-key code { flex: 1; min-width: 0; overflow-wrap: anywhere; font-size: 0.95rem; font-weight: 700; color: var(--text); }
.last-order { margin-bottom: 14px; padding: 14px; border-radius: 16px; border: 1px solid rgba(37, 211, 102, 0.45); background: rgba(37, 211, 102, 0.1); }
.last-order-text strong { display: block; font-size: 0.95rem; }
.last-order-text small { display: block; color: var(--silver); margin-top: 3px; font-size: 0.84rem; }
.last-order-actions { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 10px; }
.last-order-actions .btn { flex: 1 1 auto; justify-content: center; }
.wa-send { background: #25d366; color: #fff; box-shadow: 0 0 24px rgba(37, 211, 102, 0.4); margin-top: 6px; }
.wa-send:hover { background: #1ebe5b; }
.wa-required { margin: 4px 0 12px; }
.wa-required.nudge { animation: wa-shake 0.45s ease; border-color: #facc15; background: rgba(250, 204, 21, 0.2); }
.wa-send.pulse { animation: wa-pulse 1.6s ease-in-out infinite; }
.wa-sent-note { display: flex; gap: 8px; align-items: flex-start; margin: 4px 0 12px; padding: 10px 12px; border-radius: 12px;
  background: rgba(37, 211, 102, 0.1); border: 1px solid rgba(37, 211, 102, 0.4); font-size: 0.88rem; text-align: left; }
.wa-sent-note svg { width: 17px; height: 17px; flex-shrink: 0; margin-top: 1px; color: #25d366; }
@keyframes wa-shake { 0%, 100% { transform: translateX(0); } 20%, 60% { transform: translateX(-6px); } 40%, 80% { transform: translateX(6px); } }
@keyframes wa-pulse { 0%, 100% { box-shadow: 0 0 0 0 rgba(37, 211, 102, 0.55); } 50% { box-shadow: 0 0 0 10px rgba(37, 211, 102, 0); } }
@media (prefers-reduced-motion: reduce) { .wa-required.nudge, .wa-send.pulse { animation: none; } }

@media (max-width: 520px) { .item-photo { width: 88px; height: 88px; } }
</style>
