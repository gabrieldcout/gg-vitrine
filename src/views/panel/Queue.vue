<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { supabase, unwrap } from '@/lib/supabase'
import { useBusiness } from '@/lib/business'
import { money, formatTime, todayISO } from '@/lib/format'
import { waLink } from '@/lib/whatsapp'
import { alarmUrl } from '@/lib/alarm'
import { APP_DOMAIN } from '@/config/brand'
import Icon from '@/components/Icon.vue'
import { ask } from '@/lib/confirm'
import { toast } from '@/lib/toast'

// Fila por ordem de chegada: o cliente entra pela vitrine (ou o dono lança
// quem chegou no balcão) e a loja vai chamando um por um.
const biz = useBusiness()
const tz = computed(() => biz.business.timezone)
const ready = computed(() => 'queue_slots' in biz.business)   // migration 0023 rodada
const entries = ref([])
const services = ref([])
const day = ref(todayISO(tz.value))
const isToday = computed(() => day.value === todayISO(tz.value))
const filter = ref('fila')
const error = ref('')
const msg = ref('')
// Todo aviso de sucesso desta tela também aparece no canto (toast).
watch(msg, (m) => { if (m) toast(typeof m === 'string' ? m : m.text) })
const now = ref(Date.now())

const STATUS = {
  aguardando: { label: 'Na fila', badge: 'yellow' },
  atendendo: { label: 'Em atendimento', badge: 'blue' },
  pronto: { label: 'Pronto', badge: 'green' },
  cancelado: { label: 'Cancelado', badge: 'red' },
}
const FILTERS = { fila: 'Fila', pronto: 'Prontos', cancelado: 'Cancelados', todos: 'Todos' }
const WEEKDAYS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb']

const waiting = computed(() => entries.value.filter((e) => e.status === 'aguardando'))
const inService = computed(() => entries.value.filter((e) => e.status === 'atendendo'))
const done = computed(() => entries.value.filter((e) => e.status === 'pronto'))
const doneTotal = computed(() => done.value.reduce((t, e) => t + Number(e.price), 0))
const visible = computed(() => {
  if (filter.value === 'fila') return [...inService.value, ...waiting.value]
  if (filter.value === 'todos') return entries.value
  return entries.value.filter((e) => e.status === filter.value).reverse()
})

// Olhinho: mesmo do painel de pedidos (lembrado neste aparelho).
const HIDE_KEY = 'gg-esconder-valores'
const hideValues = ref((() => { try { return localStorage.getItem(HIDE_KEY) === '1' } catch { return false } })())
function toggleValues() {
  hideValues.value = !hideValues.value
  try { localStorage.setItem(HIDE_KEY, hideValues.value ? '1' : '0') } catch { /* sem armazenamento local */ }
}

// ---------------- Previsão (mesma conta da vitrine) ----------------
// Cada carro vai pro box que libera primeiro; quem está em atendimento ocupa
// o box pelo tempo que ainda falta.
const estimates = computed(() => {
  const slots = Array(Math.max(1, Number(biz.business.queue_slots) || 1)).fill(0)
  const take = (min) => { const i = slots.indexOf(Math.min(...slots)); const at = slots[i]; slots[i] += min; return at }
  for (const e of inService.value) {
    const elapsed = (now.value - new Date(e.started_at ?? now.value).getTime()) / 60000
    take(Math.max(e.duration_min - elapsed, 0))
  }
  const out = {}
  waiting.value.forEach((e, i) => { out[e.id] = { ahead: inService.value.length + i, wait: Math.ceil(take(e.duration_min)) } })
  out.next = Math.ceil(Math.min(...slots))
  return out
})
const clock = (min) => new Date(now.value + min * 60000).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: tz.value })
const waitText = (min) => (min <= 0 ? 'agora' : min < 60 ? `~${min} min` : `~${Math.floor(min / 60)}h${String(min % 60).padStart(2, '0')}`)

// ---------------- Aberta / encerrada ----------------
// Só pro dia de hoje o dono pode abrir/encerrar na hora e escolher até quando
// aceita (migration 0024). No dia seguinte volta o horário padrão.
const hasToday = computed(() => 'queue_today_mode' in biz.business)
const hm = (t) => (t ? String(t).slice(0, 5) : '')
function localNow() {
  const d = new Date(now.value)
  return {
    wd: new Date(d.toLocaleString('en-US', { timeZone: tz.value })).getDay(),
    t: d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: tz.value }),
  }
}
const todayChoice = computed(() => (biz.business.queue_today === todayISO(tz.value) ? biz.business.queue_today_mode : null))
const closedToday = computed(() => todayChoice.value === 'encerrada' || biz.business.queue_closed_on === todayISO(tz.value))
const scheduleReason = computed(() => {
  const b = biz.business
  const { wd, t } = localNow()
  if (!(b.queue_weekdays ?? []).includes(wd)) return 'Hoje não é dia de fila no horário padrão'
  if (b.queue_open_time && t < hm(b.queue_open_time)) return `Pelo horário padrão, a fila abre às ${hm(b.queue_open_time)}`
  if (b.queue_close_time && t >= hm(b.queue_close_time)) return `Pelo horário padrão, a fila fechou às ${hm(b.queue_close_time)}`
  return ''
})
const until = computed(() => (todayChoice.value === 'aberta' ? hm(biz.business.queue_today_until) : hm(biz.business.queue_close_time)))
const isOpen = computed(() => {
  if (closedToday.value) return false
  if (todayChoice.value === 'aberta') return !until.value || localNow().t < until.value
  return !scheduleReason.value
})
const customUntil = ref('')

async function patchBusiness(patch) {
  const { error: err } = await supabase.from('businesses').update(patch).eq('id', biz.business.id)
  if (err) { error.value = err.message; return false }
  Object.assign(biz.business, patch)
  return true
}
async function setToday(mode, untilTime = null) {
  if (mode === 'encerrada' && !await ask('Encerrar a entrada de novos clientes por hoje? Quem já está na fila continua. Amanhã a fila volta ao horário de sempre.')) return
  const patch = hasToday.value
    ? { queue_today: todayISO(tz.value), queue_today_mode: mode, queue_today_until: untilTime, queue_closed_on: null }
    : { queue_closed_on: mode === 'encerrada' ? todayISO(tz.value) : null }
  if (await patchBusiness(patch)) {
    customUntil.value = ''
    flash(mode === 'encerrada' ? 'Fila encerrada por hoje.' : untilTime ? `Fila aberta até ${untilTime}.` : 'Fila aberta até você encerrar.')
  }
}
async function backToDefault() {
  const patch = hasToday.value
    ? { queue_today: null, queue_today_mode: null, queue_today_until: null, queue_closed_on: null }
    : { queue_closed_on: null }
  if (await patchBusiness(patch)) flash('Hoje vale o horário padrão da fila.')
}

// ---------------- "Me avise quando abrir" ----------------
const notifyList = ref([])
async function loadNotify() {
  if (!hasToday.value) return
  const { data } = await supabase.from('queue_notify').select('*')
    .eq('business_id', biz.business.id).is('notified_at', null).order('created_at')
  notifyList.value = data ?? []
}
function notifyLink(n) {
  return waLink(n.phone, `Oi ${n.name}! A fila da ${biz.business.name} está aberta. Entre pelo link e garanta sua vez: https://${APP_DOMAIN}/${biz.business.slug}`)
}
async function markNotified(n) {
  await supabase.from('queue_notify').update({ notified_at: new Date().toISOString() }).eq('id', n.id)
  notifyList.value = notifyList.value.filter((x) => x.id !== n.id)
  toast(`${n.name} marcado como avisado.`)
}
async function removeNotify(n) {
  if (!await ask(`Tirar ${n.name} da lista de aviso?`)) return
  await supabase.from('queue_notify').delete().eq('id', n.id)
  notifyList.value = notifyList.value.filter((x) => x.id !== n.id)
}

// ---------------- Configuração ----------------
const showSettings = ref(false)
const cfg = ref({})
function openSettings() {
  const b = biz.business
  cfg.value = {
    queue_slots: b.queue_slots ?? 1,
    queue_weekdays: [...(b.queue_weekdays ?? [1, 2, 3, 4, 5, 6])],
    queue_open_time: b.queue_open_time?.slice(0, 5) ?? '',
    queue_close_time: b.queue_close_time?.slice(0, 5) ?? '',
  }
  showSettings.value = !showSettings.value
}
function toggleDay(d) {
  const list = cfg.value.queue_weekdays
  cfg.value.queue_weekdays = list.includes(d) ? list.filter((x) => x !== d) : [...list, d].sort()
}
async function saveSettings() {
  const payload = {
    queue_slots: Math.min(20, Math.max(1, Number(cfg.value.queue_slots) || 1)),
    queue_weekdays: cfg.value.queue_weekdays,
    queue_open_time: cfg.value.queue_open_time || null,
    queue_close_time: cfg.value.queue_close_time || null,
  }
  const { error: err } = await supabase.from('businesses').update(payload).eq('id', biz.business.id)
  if (err) { error.value = err.message; return }
  Object.assign(biz.business, payload)
  showSettings.value = false
  flash('Configuração da fila salva.')
}

// ---------------- Lançar quem chegou no balcão ----------------
const showAdd = ref(false)
const add = ref({})
function openAdd() {
  add.value = { service_id: services.value[0]?.id ?? '', customer_name: '', phone: '', vehicle: 'Carro', notes: '', start: false }
  showAdd.value = true
}
async function saveAdd() {
  const s = services.value.find((x) => x.id === add.value.service_id)
  if (!s) { error.value = 'Escolha o serviço.'; return }
  const { data, error: err } = await supabase.from('queue_entries').insert({
    business_id: biz.business.id, service_id: s.id, service_name: s.name, price: s.price, duration_min: s.duration_min,
    customer_name: add.value.customer_name.trim() || 'Cliente do balcão', phone: add.value.phone.trim(),
    vehicle: add.value.vehicle || null, notes: add.value.notes.trim() || null, source: 'balcao',
    status: add.value.start ? 'atendendo' : 'aguardando',
  }).select('id, number').single()
  if (err) { error.value = err.message; return }
  seen?.add(data.id)
  showAdd.value = false
  flash(`#${data.number} adicionado à fila.`)
  day.value = todayISO(tz.value)
  load()
}

// ---------------- Ações ----------------
// "Pronto": já abre o WhatsApp do cliente com a mensagem escrita (o dono só
// aperta enviar). Abre antes de salvar, ainda dentro do toque, senão o
// navegador bloqueia a janela.
// Preferências deste aparelho.
const pref = (key, def) => { try { const v = localStorage.getItem(key); return v === null ? def : v === '1' } catch { return def } }
const waOnReady = ref(pref('gg-fila-wa-pronto', true))
function toggleWaOnReady() {
  waOnReady.value = !waOnReady.value
  try { localStorage.setItem('gg-fila-wa-pronto', waOnReady.value ? '1' : '0') } catch { /* sem armazenamento local */ }
}
function readyMessage(e) {
  return `Olá ${e.customer_name}! ✅ Seu veículo está pronto, pode vir buscar!` +
    (biz.business.address ? `\n📍 ${biz.business.address}` : '') + `\nObrigado pela preferência, ${biz.business.name}!`
}
function markReady(e) {
  const link = waOnReady.value && e.phone ? waLink(e.phone, readyMessage(e)) : null
  if (link) window.open(link, '_blank', 'noopener')
  setStatus(e, 'pronto')
}

async function setStatus(e, status) {
  if (status === 'cancelado' && !await ask(`Tem certeza que deseja tirar #${e.number} (${e.customer_name}) da fila?`)) return
  const patch = { status, ...(status === 'cancelado' ? { canceled_by: 'loja' } : {}) }
  const { error: err } = await supabase.from('queue_entries').update(patch).eq('id', e.id)
  if (err) { error.value = err.message; return }
  toast(status === 'cancelado' ? `#${e.number} saiu da fila.` : `#${e.number} (${e.customer_name}) atualizado.`)
  load()
}
async function editPrice(e) {
  const v = prompt(`Valor do serviço de #${e.number} (${e.customer_name}):`, String(Number(e.price)).replace('.', ','))
  if (v === null) return
  const price = Number(v.replace(/[^\d,.-]/g, '').replace(',', '.'))
  if (!Number.isFinite(price) || price < 0) { error.value = 'Valor inválido.'; return }
  const { error: err } = await supabase.from('queue_entries').update({ price }).eq('id', e.id)
  if (err) { error.value = err.message; return }
  toast('Valor atualizado.')
  load()
}
function customerLink(e) {
  const est = estimates.value[e.id]
  const msgText = {
    aguardando: `Olá ${e.customer_name}! Você está na fila da ${biz.business.name} com a senha #${e.number}.` +
      (est ? ` Previsão de atendimento: ${est.wait <= 0 ? 'agora' : `por volta de ${clock(est.wait)}`}.` : ''),
    atendendo: `Olá ${e.customer_name}! Seu ${e.service_name.toLowerCase()} (senha #${e.number}) já começou.`,
    pronto: readyMessage(e),
  }[e.status] ?? `Olá ${e.customer_name}!`
  return waLink(e.phone, msgText)
}

function flash(text) {
  msg.value = text
  setTimeout(() => { if (msg.value === text) msg.value = '' }, 4000)
}

// ---------------- Carregar ----------------
async function load() {
  if (!ready.value) return
  try {
    entries.value = unwrap(await supabase.from('queue_entries').select('*')
      .eq('business_id', biz.business.id).eq('service_day', day.value).order('number'))
    if (isToday.value) handleNew(entries.value)
    loadNotify()
  } catch (e) {
    error.value = e.message
  }
}
async function loadServices() {
  services.value = unwrap(await supabase.from('services').select('id, name, price, duration_min')
    .eq('business_id', biz.business.id).eq('active', true).order('name')) ?? []
}

// ---------------- Cliente novo: som e notificação ----------------
const soundOn = ref(pref('gg-fila-som', true))
const audioReady = ref(false)
const hasNew = ref(false)
let player
function toggleSound() {
  soundOn.value = !soundOn.value
  try { localStorage.setItem('gg-fila-som', soundOn.value ? '1' : '0') } catch { /* sem armazenamento local */ }
  if (soundOn.value) enableSound()
}
async function enableSound() {
  try {
    player ??= new Audio(alarmUrl())
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
  player.play().catch(() => { audioReady.value = false })
}
let seen = null
function handleNew(list) {
  if (!seen) { seen = new Set(list.map((e) => e.id)); return }
  const fresh = list.filter((e) => !seen.has(e.id) && e.source === 'site')
  list.forEach((e) => seen.add(e.id))
  if (!fresh.length) return
  hasNew.value = true
  alarm()
  if ('Notification' in window && Notification.permission === 'granted') {
    for (const e of fresh) {
      try { new Notification(`Fila: #${e.number} · ${e.customer_name}`, { body: e.service_name, tag: e.id }) } catch { /* sem notificação */ }
    }
  }
}

// Tela do celular/tablet acesa enquanto a fila está aberta aqui.
let wakeLock = null
async function keepAwake() {
  if (!soundOn.value || document.visibilityState !== 'visible' || !('wakeLock' in navigator)) return
  try { wakeLock = await navigator.wakeLock.request('screen') } catch { /* sem suporte */ }
}
const unlock = () => {
  if (!soundOn.value) return
  if (!audioReady.value) enableSound()
  if (!wakeLock) keepAwake()
}
function onVisible() {
  if (document.visibilityState !== 'visible') return
  load()
  wakeLock = null
  keepAwake()
}

let timer, tick
onMounted(() => {
  load()
  loadServices()
  timer = setInterval(load, 15000)
  tick = setInterval(() => { now.value = Date.now() }, 30000)
  document.addEventListener('pointerdown', unlock)
  document.addEventListener('visibilitychange', onVisible)
  if (soundOn.value) { enableSound(); keepAwake() }
})
onUnmounted(() => {
  clearInterval(timer)
  clearInterval(tick)
  document.removeEventListener('pointerdown', unlock)
  document.removeEventListener('visibilitychange', onVisible)
  wakeLock?.release().catch(() => {})
})
function changeDay() { seen = null; load() }
</script>

<template>
  <div class="page-header">
    <p class="eyebrow">{{ biz.business.category }}</p>
    <h1>Fila</h1>
  </div>

  <div v-if="!ready" class="card">
    <h3>Falta ativar a fila no banco</h3>
    <p class="muted">Rode a migration <code>0023_fila.sql</code> no SQL Editor do Supabase e recarregue esta página.</p>
  </div>

  <template v-else>
    <!-- Aberta / encerrada -->
    <div class="card q-status" :class="isOpen ? 'open' : 'closed'">
      <div class="q-status-row">
        <div class="q-status-text">
          <span class="q-dot" />
          <div>
            <strong>{{ isOpen ? 'Fila aberta: aceitando novos clientes' : 'Fila fechada para novos clientes' }}</strong>
            <small v-if="isOpen">
              {{ until ? `Aceitando até ${until}` : 'Aceitando até você encerrar' }} ·
              próximo começa {{ estimates.next <= 0 ? 'agora' : `por volta de ${clock(estimates.next)}` }}
            </small>
            <small v-else-if="closedToday">Você encerrou por hoje. Amanhã a fila volta ao horário de sempre.</small>
            <small v-else-if="todayChoice === 'aberta'">Fechou às {{ until }}, como você escolheu.</small>
            <small v-else>{{ scheduleReason }}.</small>
          </div>
        </div>
        <button v-if="isOpen" class="btn danger" @click="setToday('encerrada')">Encerrar agora</button>
        <button v-else class="btn" @click="setToday('aberta', null)">Abrir agora</button>
      </div>
      <div v-if="hasToday" class="q-until">
        <span class="q-until-label">Hoje, aceitar clientes até:</span>
        <div class="chips">
          <button type="button" class="chip" :class="{ selected: !todayChoice && !closedToday }" @click="backToDefault">
            Horário padrão{{ biz.business.queue_close_time ? ` (${hm(biz.business.queue_close_time)})` : '' }}
          </button>
          <button type="button" class="chip" :class="{ selected: todayChoice === 'aberta' && !biz.business.queue_today_until }" @click="setToday('aberta', null)">
            Até eu encerrar
          </button>
          <span class="q-until-pick" :class="{ selected: todayChoice === 'aberta' && biz.business.queue_today_until }">
            <input v-model="customUntil" type="time" aria-label="Aceitar até" />
            <button type="button" class="btn small secondary" :disabled="!customUntil" @click="setToday('aberta', customUntil)">
              {{ todayChoice === 'aberta' && biz.business.queue_today_until && !customUntil ? `Até ${until}` : 'Usar este horário' }}
            </button>
          </span>
        </div>
      </div>
    </div>

    <!-- Quem pediu pra ser avisado -->
    <div v-if="notifyList.length" class="card q-notify">
      <div class="spread">
        <h3 style="margin: 0">🔔 {{ notifyList.length }} {{ notifyList.length === 1 ? 'cliente quer' : 'clientes querem' }} ser avisado{{ notifyList.length === 1 ? '' : 's' }} quando abrir</h3>
      </div>
      <p class="muted" style="margin: 4px 0 10px">Toque em "Avisar" pra mandar o link da fila no WhatsApp de cada um.</p>
      <div v-for="n in notifyList" :key="n.id" class="q-notify-row">
        <span><strong>{{ n.name }}</strong> <small class="muted">{{ n.phone }} · pediu às {{ formatTime(n.created_at, tz) }}</small></span>
        <span class="chips">
          <a class="btn small" :href="notifyLink(n)" target="_blank" rel="noopener" @click="markNotified(n)">
            <Icon name="whatsapp" style="width: 15px; height: 15px" />Avisar
          </a>
          <button type="button" class="btn small secondary" @click="removeNotify(n)">Remover</button>
        </span>
      </div>
    </div>

    <div class="q-stats">
      <div class="card stat"><div class="label">Na fila</div><div class="value">{{ waiting.length }}</div></div>
      <div class="card stat"><div class="label">Em atendimento</div><div class="value">{{ inService.length }}</div></div>
      <div class="card stat"><div class="label">Prontos {{ isToday ? 'hoje' : 'no dia' }}</div><div class="value">{{ done.length }}</div></div>
      <div class="card stat">
        <div class="label">Faturado {{ isToday ? 'hoje' : 'no dia' }}</div>
        <div class="q-sold">
          <div class="value">{{ hideValues ? 'R$ •••••' : money(doneTotal) }}</div>
          <button type="button" class="eye-btn" :aria-label="hideValues ? 'Mostrar valor' : 'Esconder valor'" @click="toggleValues">
            <Icon :name="hideValues ? 'eye-off' : 'eye'" />
          </button>
        </div>
      </div>
    </div>

    <div class="q-actions">
      <button class="btn" @click="openAdd"><Icon name="plus" style="width: 16px; height: 16px" />Adicionar cliente do balcão</button>
      <button class="btn secondary" @click="openSettings"><Icon name="clock" style="width: 16px; height: 16px" />Configurar fila</button>
    </div>

    <div v-if="showSettings" class="card q-form">
      <h3>Configurar fila</h3>
      <label class="q-field">
        <span>Atendimentos ao mesmo tempo</span>
        <input v-model.number="cfg.queue_slots" type="number" min="1" max="20" />
        <small class="muted">Quantos carros/clientes vocês atendem juntos. Usado pra calcular a previsão.</small>
      </label>
      <div class="q-field">
        <span>Dias com fila</span>
        <div class="chips">
          <button v-for="(d, i) in WEEKDAYS" :key="i" type="button" class="chip" :class="{ selected: cfg.queue_weekdays.includes(i) }" @click="toggleDay(i)">{{ d }}</button>
        </div>
      </div>
      <div class="q-row">
        <label class="q-field"><span>Abre às</span><input v-model="cfg.queue_open_time" type="time" /></label>
        <label class="q-field"><span>Aceita clientes até</span><input v-model="cfg.queue_close_time" type="time" /></label>
      </div>
      <small class="muted">Deixe em branco pra não ter horário. Fora dos dias e horários a vitrine mostra "Novos serviços encerrados".</small>
      <div class="q-actions" style="margin-top: 12px">
        <button class="btn" @click="saveSettings">Salvar</button>
        <button class="btn secondary" @click="showSettings = false">Cancelar</button>
      </div>
    </div>

    <div v-if="showAdd" class="card q-form">
      <h3>Adicionar cliente do balcão</h3>
      <p v-if="!services.length" class="muted">Cadastre e ative os serviços em <RouterLink to="/painel/servicos">Serviços</RouterLink> primeiro.</p>
      <template v-else>
        <label class="q-field">
          <span>Serviço</span>
          <select v-model="add.service_id">
            <option v-for="s in services" :key="s.id" :value="s.id">{{ s.name }} · {{ money(s.price) }}</option>
          </select>
        </label>
        <div class="q-row">
          <label class="q-field"><span>Nome</span><input v-model="add.customer_name" maxlength="80" placeholder="Cliente do balcão" /></label>
          <label class="q-field"><span>WhatsApp</span><input v-model="add.phone" inputmode="tel" maxlength="30" placeholder="Opcional" /></label>
        </div>
        <div class="q-row">
          <label class="q-field"><span>Veículo</span>
            <select v-model="add.vehicle"><option>Carro</option><option>Moto</option></select>
          </label>
          <label class="q-field"><span>Observação</span><input v-model="add.notes" maxlength="500" placeholder="Opcional" /></label>
        </div>
        <label class="q-check"><input v-model="add.start" type="checkbox" /> Já começar o atendimento agora</label>
        <div class="q-actions">
          <button class="btn" @click="saveAdd">Adicionar à fila</button>
          <button class="btn secondary" @click="showAdd = false">Cancelar</button>
        </div>
      </template>
    </div>

    <div class="card q-sound">
      <label class="q-check">
        <input type="checkbox" :checked="soundOn" @change="toggleSound" />
        <span><strong>Som quando alguém entrar na fila pela vitrine</strong><small class="muted"> · neste aparelho, com esta tela aberta</small></span>
      </label>
      <button v-if="soundOn && !audioReady" type="button" class="btn small sound-off" @click="testSound">
        <Icon name="bell" style="width: 15px; height: 15px" />Som desativado: toque aqui pra ativar
      </button>
      <button v-else-if="soundOn" type="button" class="link-btn" @click="testSound">Testar som</button>
      <label class="q-check" style="flex-basis: 100%">
        <input type="checkbox" :checked="waOnReady" @change="toggleWaOnReady" />
        <span><strong>Ao marcar pronto, abrir o WhatsApp do cliente com a mensagem "pode vir buscar"</strong></span>
      </label>
    </div>

    <div v-if="msg" class="success">{{ msg }}</div>
    <div v-if="hasNew" class="success spread" @click="hasNew = false">
      <strong>🔔 Entrou cliente novo na fila!</strong><button class="btn small secondary">Ok</button>
    </div>
    <div v-if="error" class="error" @click="error = ''">{{ error }}</div>

    <div class="q-filters">
      <div class="chips">
        <button v-for="(label, key) in FILTERS" :key="key" class="chip" :class="{ selected: filter === key }" @click="filter = key">{{ label }}</button>
      </div>
      <input v-model="day" type="date" class="q-day" aria-label="Dia" @change="changeDay" />
    </div>

    <p v-if="!visible.length" class="card muted" style="text-align: center">
      {{ filter === 'fila' ? (isToday ? 'Ninguém na fila agora.' : 'Ninguém ficou na fila nesse dia.') : 'Nada neste filtro.' }}
    </p>

    <div class="q-list">
      <div v-for="e in visible" :key="e.id" class="card q-item" :class="`st-${e.status}`">
        <div class="spread">
          <h3 style="margin: 0">
            #{{ e.number }} · {{ e.customer_name }}
            <span v-if="e.source === 'balcao'" class="badge">Balcão</span>
          </h3>
          <span :class="['badge', STATUS[e.status].badge]">{{ STATUS[e.status].label }}</span>
        </div>
        <div class="q-meta">
          <span><Icon name="sparkles" />{{ e.service_name }} · {{ hideValues ? 'R$ •••' : money(e.price) }}
            <button v-if="e.status !== 'cancelado'" type="button" class="link-btn" @click="editPrice(e)">alterar valor</button></span>
          <span v-if="e.vehicle"><Icon name="truck" />{{ e.vehicle }}</span>
          <span v-if="e.phone"><Icon name="phone" />{{ e.phone }}</span>
          <span v-if="e.notes"><Icon name="clipboard" />{{ e.notes }}</span>
          <span><Icon name="clock" />Entrou às {{ formatTime(e.created_at, tz) }}
            <template v-if="e.started_at"> · começou {{ formatTime(e.started_at, tz) }}</template>
            <template v-if="e.finished_at && e.status === 'pronto'"> · pronto {{ formatTime(e.finished_at, tz) }}</template>
          </span>
          <span v-if="e.status === 'aguardando' && isToday && estimates[e.id]" class="q-eta">
            {{ estimates[e.id].ahead === 0 ? 'É o próximo' : `${estimates[e.id].ahead} na frente` }} ·
            previsão {{ estimates[e.id].wait <= 0 ? 'agora' : `${clock(estimates[e.id].wait)} (${waitText(estimates[e.id].wait)})` }}
          </span>
          <span v-if="e.status === 'cancelado' && e.canceled_by === 'cliente'" class="muted">O cliente saiu da fila.</span>
        </div>
        <div class="chips q-item-actions">
          <a v-if="e.phone && customerLink(e) && e.status !== 'cancelado'" class="btn small secondary" :href="customerLink(e)" target="_blank" rel="noopener">
            <Icon name="whatsapp" style="width: 15px; height: 15px" />Avisar cliente
          </a>
          <button v-if="e.status === 'aguardando'" class="btn small" @click="setStatus(e, 'atendendo')">Começar atendimento</button>
          <button v-if="e.status === 'atendendo'" class="btn small" @click="markReady(e)">
            <Icon v-if="waOnReady && e.phone" name="whatsapp" style="width: 15px; height: 15px" />Marcar como pronto{{ waOnReady && e.phone ? ' e avisar' : '' }}
          </button>
          <button v-if="e.status === 'atendendo'" class="btn small secondary" @click="setStatus(e, 'aguardando')">Voltar pra fila</button>
          <button v-if="['aguardando', 'atendendo'].includes(e.status)" class="btn small danger" @click="setStatus(e, 'cancelado')">Tirar da fila</button>
        </div>
      </div>
    </div>
  </template>
</template>

<style scoped>
.q-status { margin-bottom: 14px; display: grid; gap: 14px; }
.q-status-row { display: flex; align-items: center; justify-content: space-between; gap: 14px; flex-wrap: wrap; }
.q-until { display: grid; gap: 8px; padding-top: 12px; border-top: 1px solid var(--border); }
.q-until-label { font-size: 0.85rem; font-weight: 600; color: var(--silver); }
.q-until-pick { display: inline-flex; align-items: center; gap: 6px; padding: 3px 4px 3px 3px; border-radius: 999px; border: 1px solid var(--border); }
.q-until-pick.selected { border-color: var(--brand); }
.q-until-pick input { width: auto; padding: 5px 8px; border: 0; background: transparent; }
.q-notify { margin-bottom: 14px; border-color: var(--brand); }
.q-notify-row { display: flex; align-items: center; justify-content: space-between; gap: 10px; flex-wrap: wrap; padding: 8px 0; border-top: 1px solid var(--border); }
.q-status-text { display: flex; gap: 12px; align-items: flex-start; }
.q-status-text strong { display: block; font-size: 1.02rem; }
.q-status-text small { display: block; color: var(--muted); margin-top: 2px; }
.q-dot { width: 12px; height: 12px; border-radius: 999px; margin-top: 5px; flex-shrink: 0; background: #22c55e; box-shadow: 0 0 0 4px rgba(34, 197, 94, 0.2); }
.q-status.closed .q-dot { background: #ef4444; box-shadow: 0 0 0 4px rgba(239, 68, 68, 0.2); }
.q-status.closed { border-color: rgba(239, 68, 68, 0.45); }
.q-stats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 10px; margin-bottom: 14px; }
.q-stats .stat { padding: 12px 16px; margin: 0; }
.q-list .card { margin: 0; }
.q-stats .value { font-size: 1.4rem; }
.q-sold { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.eye-btn { width: 32px; height: 32px; border-radius: 999px; display: grid; place-items: center; flex-shrink: 0;
  background: transparent; border: 1px solid var(--border); color: var(--muted); cursor: pointer; }
.eye-btn svg { width: 16px; height: 16px; }
.q-actions { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 14px; }
.q-form { margin-bottom: 14px; display: grid; gap: 12px; }
.q-form h3 { margin: 0; }
.q-field { display: grid; gap: 5px; }
.q-field > span { font-size: 0.85rem; font-weight: 600; color: var(--silver); }
.q-row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.q-check { display: flex; gap: 8px; align-items: center; cursor: pointer; font-size: 0.92rem; }
.q-sound { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 10px; margin-bottom: 14px; padding: 12px 16px; }
.sound-off { animation: pulse-sound 1.6s ease-in-out infinite; }
@keyframes pulse-sound { 50% { box-shadow: 0 0 0 6px var(--brand-glow); } }
.q-filters { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 10px; margin-bottom: 14px; }
.q-day { width: auto; padding: 7px 10px; }
.q-list { display: grid; gap: 12px; }
.q-item.st-atendendo { border-color: rgba(59, 130, 246, 0.55); }
.q-item.st-cancelado { opacity: 0.65; }
.q-meta { display: grid; gap: 6px; margin: 10px 0 12px; font-size: 0.92rem; }
.q-meta span { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.q-meta svg { width: 15px; height: 15px; color: var(--muted); flex-shrink: 0; }
.q-meta .link-btn { font-size: 0.8rem; padding: 0; }
.q-eta { font-weight: 700; color: var(--brand); }
@media (max-width: 640px) {
  .q-stats { grid-template-columns: 1fr 1fr; }
  .q-row { grid-template-columns: 1fr; }
}
</style>
