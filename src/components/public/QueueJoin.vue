<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { money, todayISO } from '@/lib/format'
import { waLink } from '@/lib/whatsapp'
import { alarmUrl } from '@/lib/alarm'
import Icon from '@/components/Icon.vue'

// Vitrine em modo fila: o cliente escolhe o serviço, entra na fila do dia e
// acompanha quantos estão na frente e a previsão. A senha fica guardada no
// aparelho (sem login) pra ele voltar e conferir.
const props = defineProps({ business: { type: Object, required: true } })
const emit = defineEmits(['status'])
const tz = computed(() => props.business.timezone || 'America/Sao_Paulo')
const KEY = computed(() => `gg-fila-${props.business.id}`)
const WEEKDAYS = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado']

const queue = ref(null)
const ticket = ref(null)
const service = ref(null)
const form = ref({ name: '', phone: '', vehicle: '', notes: '' })
const sending = ref(false)
const error = ref('')
const now = ref(Date.now())

const read = (k) => { try { return JSON.parse(localStorage.getItem(k) ?? 'null') } catch { return null } }
const write = (k, v) => { try { v === null ? localStorage.removeItem(k) : localStorage.setItem(k, JSON.stringify(v)) } catch { /* sem armazenamento local */ } }

const clock = (min) => new Date(now.value + min * 60000).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: tz.value })
const waitText = (min) => (min <= 0 ? 'agora' : min < 60 ? `~${min} min` : `~${Math.floor(min / 60)}h${String(min % 60).padStart(2, '0')}`)
const hhmm = (t) => (t ? String(t).slice(0, 5) : '')
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`

const ahead = computed(() => Number(queue.value?.waiting ?? 0) + Number(queue.value?.in_service ?? 0))
const closedText = computed(() => {
  const q = queue.value
  if (!q) return ''
  const days = (q.weekdays ?? []).map((d) => WEEKDAYS[d])
  const parts = []
  if (days.length && days.length < 7) parts.push(days.length === 6 && !q.weekdays.includes(0) ? 'de segunda a sábado' : days.join(', '))
  if (q.open_time && q.close_time) parts.push(`das ${hhmm(q.open_time)} às ${hhmm(q.close_time)}`)
  else if (q.close_time) parts.push(`até ${hhmm(q.close_time)}`)
  else if (q.open_time) parts.push(`a partir das ${hhmm(q.open_time)}`)
  return parts.length ? `A fila funciona ${parts.join(', ')}.` : ''
})
const activeTicket = computed(() => ticket.value && ['aguardando', 'atendendo'].includes(ticket.value.status))

// Hora e dia da semana no fuso da loja.
function localNow() {
  const d = new Date(now.value)
  return {
    wd: new Date(d.toLocaleString('en-US', { timeZone: tz.value })).getDay(),
    t: d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: tz.value }),
  }
}
const minutesUntil = (hm) => {
  const [h, m] = hm.split(':').map(Number)
  const [h0, m0] = localNow().t.split(':').map(Number)
  return h * 60 + m - (h0 * 60 + m0)
}
// Fechada: quando abre de novo (hoje mais tarde, amanhã ou o próximo dia de fila).
const nextOpen = computed(() => {
  const q = queue.value
  if (!q || q.open) return null
  const days = q.weekdays ?? []
  const { wd, t } = localNow()
  const at = q.open_time ? ` a partir das ${hhmm(q.open_time)}` : ''
  if (!q.closed_today && !q.today_mode && days.includes(wd) && q.open_time && t < hhmm(q.open_time)) {
    return { today: true, text: `hoje${at}` }
  }
  for (let i = 1; i <= 7; i++) {
    const w = (wd + i) % 7
    if (days.includes(w)) return { today: false, text: `${i === 1 ? 'amanhã' : WEEKDAYS[w]}${at}` }
  }
  return null
})
const closedTitle = computed(() => {
  const q = queue.value
  if (nextOpen.value?.today) return `A fila abre ${nextOpen.value.text}`
  if (!q.closed_today && !q.today_mode && !(q.weekdays ?? []).includes(localNow().wd)) return 'Hoje a fila não abre'
  return 'A fila de hoje já fechou'
})
// Perto do horário de fechar: "últimas vagas".
const lastCall = computed(() => {
  const q = queue.value
  if (!q?.open || !q.until) return false
  const left = minutesUntil(hhmm(q.until))
  return left > 0 && left <= 90
})
// Quando o carro fica pronto, se entrar agora com o serviço escolhido.
const readyAt = computed(() => (service.value && queue.value ? clock(Math.max(queue.value.wait_min, 0) + service.value.duration_min) : ''))
const ticketReadyAt = computed(() => {
  const t = ticket.value
  const s = props.business.services.find((x) => x.name === t?.service_name)
  return t?.status === 'aguardando' && s ? clock(Math.max(t.wait_min ?? 0, 0) + s.duration_min) : ''
})

// "Me avise quando abrir" (precisa da migration 0024; a fila nova manda today_mode).
const canNotify = computed(() => queue.value && 'today_mode' in queue.value)
const NOTIFY_KEY = computed(() => `gg-fila-aviso-${props.business.id}`)
const notified = ref(false)
const notifyForm = ref({ name: '', phone: '' })
const notifying = ref(false)
async function notifyMe() {
  error.value = ''
  if (!notifyForm.value.name.trim() || notifyForm.value.phone.replace(/\D/g, '').length < 10) {
    error.value = 'Informe seu nome e WhatsApp com DDD.'
    return
  }
  notifying.value = true
  const { error: err } = await supabase.rpc('queue_notify_me', {
    p_business: props.business.id, p_name: notifyForm.value.name.trim(), p_phone: notifyForm.value.phone.trim(),
  })
  notifying.value = false
  if (err) { error.value = err.message; return }
  write(NOTIFY_KEY.value, { at: Date.now(), name: notifyForm.value.name.trim() })
  write('gg-fila-cliente', { ...(read('gg-fila-cliente') ?? {}), name: notifyForm.value.name.trim(), phone: notifyForm.value.phone.trim() })
  notified.value = true
}
const storeWa = computed(() => waLink(props.business.phone, 'Olá! Vi que a fila está fechada. Queria saber sobre um serviço.'))
const ticketWa = computed(() => {
  const t = ticket.value
  if (!t) return null
  return waLink(props.business.phone, `Olá! Entrei na fila pelo link. Senha #${t.number} · ${t.customer_name} · ${t.service_name}${t.vehicle ? ` · ${t.vehicle}` : ''}.`)
})

async function loadQueue() {
  const { data } = await supabase.rpc('queue_public', { p_business: props.business.id })
  queue.value = data
  now.value = Date.now()
  if (data) emit('status', Boolean(data.open))
}
async function loadTicket() {
  const saved = read(KEY.value)
  if (!saved?.id) { ticket.value = null; return }
  const { data } = await supabase.rpc('queue_ticket', { p_entry: saved.id })
  // Senha de outro dia que não foi atendida: já não vale.
  if (!data || (data.service_day !== todayISO(tz.value) && ['aguardando', 'atendendo'].includes(data.status))) {
    write(KEY.value, null); ticket.value = null; return
  }
  const before = ticket.value?.id === data.id ? ticket.value.status : null
  ticket.value = data
  if (before && before !== data.status) alertChange(data)
}

// Aviso neste celular: com a página aberta, toca e vibra quando chega a vez e
// quando fica pronto. O navegador só libera som/notificação depois de um toque.
const alertOn = ref(false)
let player
async function enableAlerts() {
  try {
    player ??= new Audio(alarmUrl())
    player.muted = true
    await player.play()
    player.pause()
    player.currentTime = 0
    player.muted = false
  } catch { /* sem som */ }
  if ('Notification' in window && Notification.permission === 'default') {
    try { await Notification.requestPermission() } catch { /* sem notificação */ }
  }
  alertOn.value = true
}
function alertChange(t) {
  const text = t.status === 'pronto' ? 'Seu carro está pronto! Pode vir buscar.'
    : t.status === 'atendendo' ? 'Chegou sua vez! Seu atendimento começou.' : ''
  if (!text) return
  try { navigator.vibrate?.([300, 150, 300, 150, 600]) } catch { /* sem vibração */ }
  if (player) { player.currentTime = 0; player.play().catch(() => {}) }
  if ('Notification' in window && Notification.permission === 'granted') {
    try { new Notification(`${props.business.name} · senha #${t.number}`, { body: text, tag: t.id }) } catch { /* sem notificação */ }
  }
}
const mapsLink = computed(() => props.business.address
  ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(props.business.address)}` : null)
function refresh() { loadQueue(); loadTicket() }

function pick(s) {
  service.value = service.value?.id === s.id ? null : s
  error.value = ''
}

async function join() {
  error.value = ''
  if (!service.value) { error.value = 'Escolha o serviço.'; return }
  if (!form.value.name.trim() || form.value.phone.replace(/\D/g, '').length < 10) {
    error.value = 'Informe seu nome e WhatsApp com DDD.'
    return
  }
  sending.value = true
  const { data, error: err } = await supabase.rpc('join_queue', {
    p_business: props.business.id, p_service: service.value.id,
    p_name: form.value.name.trim(), p_phone: form.value.phone.trim(),
    p_vehicle: form.value.vehicle.trim() || null, p_notes: form.value.notes.trim() || null,
  })
  sending.value = false
  if (err) { error.value = err.message; loadQueue(); return }
  write(KEY.value, { id: data.id })
  write('gg-fila-cliente', { name: form.value.name.trim(), phone: form.value.phone.trim(), vehicle: form.value.vehicle.trim() })
  service.value = null
  await loadTicket()
  loadQueue()
  document.getElementById('agendar')?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

async function leave() {
  if (!confirm(`Sair da fila? Você perde a senha #${ticket.value.number}.`)) return
  await supabase.rpc('leave_queue', { p_entry: ticket.value.id })
  refresh()
}
function newTicket() {
  write(KEY.value, null)
  ticket.value = null
}

let timer
onMounted(() => {
  const saved = read('gg-fila-cliente')
  if (saved) Object.assign(form.value, { name: saved.name ?? '', phone: saved.phone ?? '', vehicle: saved.vehicle ?? '' })
  if (saved) Object.assign(notifyForm.value, { name: saved.name ?? '', phone: saved.phone ?? '' })
  // Já pediu aviso nas últimas 20h: não pede de novo.
  const asked = read(NOTIFY_KEY.value)
  notified.value = Boolean(asked && Date.now() - asked.at < 20 * 3600e3)
  refresh()
  timer = setInterval(refresh, 20000)
})
onUnmounted(() => clearInterval(timer))
</script>

<template>
  <div v-if="!business.live" class="card">
    <h3 style="margin: 0 0 8px">Temporariamente indisponível</h3>
    <p class="muted" style="margin: 0">Esta fila não está recebendo clientes online no momento.</p>
  </div>

  <template v-else>
    <!-- Senha do cliente -->
    <div v-if="ticket" class="card glow booking-done qj-ticket">
      <span class="qj-label">Sua senha</span>
      <div class="qj-number gradient-text">#{{ ticket.number }}</div>

      <template v-if="ticket.status === 'aguardando'">
        <h2>Você está na fila!</h2>
        <p class="qj-big">
          {{ ticket.ahead === 0 ? 'Você é o próximo' : `${plural(ticket.ahead, 'cliente', 'clientes')} na sua frente` }}
        </p>
        <p class="muted" style="margin: 0">
          Previsão de atendimento: <strong>{{ ticket.wait_min <= 0 ? 'agora' : `por volta de ${clock(ticket.wait_min)}` }}</strong>
          <template v-if="ticket.wait_min > 0"> ({{ waitText(ticket.wait_min) }})</template>
        </p>
        <p v-if="ticketReadyAt" class="qj-ready">Seu carro fica pronto por volta de <strong>{{ ticketReadyAt }}</strong></p>
        <small class="muted">Não precisa ficar esperando: acompanhe sua vez por esta página. A previsão é uma estimativa e atualiza sozinha.</small>
      </template>
      <template v-else-if="ticket.status === 'atendendo'">
        <h2>Seu atendimento começou!</h2>
        <p class="muted" style="margin: 0">Avisamos quando estiver pronto.</p>
      </template>
      <template v-else-if="ticket.status === 'pronto'">
        <div class="qj-ready-big">✅</div>
        <h2>Seu carro está pronto!</h2>
        <p class="qj-big">Pode vir buscar 🚗✨</p>
        <p v-if="business.address" class="muted" style="margin: 0">{{ business.address }}</p>
      </template>
      <template v-else>
        <h2>Senha cancelada</h2>
        <p class="muted" style="margin: 0">{{ ticket.canceled_by === 'cliente' ? 'Você saiu da fila.' : 'A loja tirou essa senha da fila. Fale com eles pelo WhatsApp.' }}</p>
      </template>

      <div class="summary">
        <div class="summary-row"><span class="label"><Icon name="sparkles" />Serviço</span><span class="value">{{ ticket.service_name }}</span></div>
        <div v-if="ticket.vehicle" class="summary-row"><span class="label"><Icon name="truck" />Veículo</span><span class="value">{{ ticket.vehicle }}</span></div>
        <div class="summary-row total"><span class="label">Valor</span><span class="value">{{ money(ticket.price) }}</span></div>
      </div>

      <button v-if="activeTicket && !alertOn" type="button" class="qj-alert-btn" @click="enableAlerts">
        <Icon name="bell" />
        <span><strong>Avise-me neste celular</strong><small>Toca e vibra quando chegar sua vez e quando o carro ficar pronto. Deixe esta página aberta.</small></span>
      </button>
      <p v-else-if="activeTicket" class="qj-alert-on"><Icon name="check" />Aviso ligado: deixe esta página aberta.</p>

      <div class="done-actions">
        <a v-if="ticket.status === 'pronto' && mapsLink" :href="mapsLink" target="_blank" rel="noopener" class="btn">
          <Icon name="map" />Como chegar
        </a>
        <a v-if="ticketWa && ticket.status !== 'pronto'" :href="ticketWa" target="_blank" rel="noopener" class="btn">
          <Icon name="whatsapp" />Falar com a loja no WhatsApp
        </a>
        <button v-if="ticket.status === 'aguardando'" class="btn secondary" @click="leave">Sair da fila</button>
        <button v-if="!activeTicket" class="btn secondary" @click="newTicket">Entrar na fila de novo</button>
      </div>
    </div>

    <template v-else>
      <!-- Situação da fila -->
      <div v-if="queue?.open" class="card qj-status open">
        <span class="qj-dot" />
        <div>
          <strong>Fila aberta{{ queue.until ? ` · aceitando até ${hhmm(queue.until)}` : '' }}</strong>
          <p>
            {{ ahead === 0 ? 'Ninguém na fila agora: você é atendido na hora!' : `${plural(ahead, 'cliente', 'clientes')} na sua frente.` }}
            <template v-if="ahead > 0">Se entrar agora, começa <strong>{{ queue.wait_min <= 0 ? 'na hora' : `por volta de ${clock(queue.wait_min)}` }}</strong>.</template>
          </p>
          <p class="qj-hint">Entre na fila pelo celular e acompanhe sua vez de onde estiver.</p>
          <p v-if="lastCall" class="qj-last">⏰ Últimas vagas de hoje: corre que fecha às {{ hhmm(queue.until) }}!</p>
        </div>
      </div>

      <!-- Fechada: sem desanimar, mostra quando abre e oferece aviso -->
      <div v-else-if="queue" class="card qj-closed">
        <div class="qj-closed-ico">🚗✨</div>
        <h3>{{ closedTitle }}</h3>
        <p v-if="nextOpen?.today" class="muted">Volte {{ nextOpen.text }} e garanta seu lugar. Quem chega primeiro, é atendido primeiro!</p>
        <p v-else class="muted">
          {{ queue.closed_today ? 'Foi um dia cheio por aqui, obrigado pela procura!' : 'Obrigado pela procura!' }}
          <template v-if="nextOpen"> A próxima fila abre <strong>{{ nextOpen.text }}</strong>.</template>
        </p>

        <template v-if="canNotify">
          <div v-if="notified" class="qj-notified">
            <Icon name="check" />
            <span>Combinado{{ notifyForm.name ? `, ${notifyForm.name.split(' ')[0]}` : '' }}! A gente te avisa no WhatsApp assim que a fila abrir.</span>
          </div>
          <form v-else class="qj-notify" @submit.prevent="notifyMe">
            <p class="qj-notify-title">Quer garantir seu lugar logo cedo?</p>
            <p class="muted" style="margin: 0 0 6px">Deixe seu WhatsApp e a gente te avisa assim que a fila abrir.</p>
            <div class="ff"><input v-model="notifyForm.name" required maxlength="80" placeholder=" " /><label>Seu nome</label></div>
            <div class="ff"><input v-model="notifyForm.phone" type="tel" required maxlength="30" placeholder=" " /><label>WhatsApp com DDD</label></div>
            <div v-if="error" class="error">{{ error }}</div>
            <button class="btn qj-submit" :disabled="notifying"><Icon name="bell" />{{ notifying ? 'Enviando…' : 'Me avise quando abrir' }}</button>
          </form>
        </template>
        <a v-if="storeWa" :href="storeWa" target="_blank" rel="noopener" class="btn secondary qj-submit">
          <Icon name="whatsapp" />Falar com a loja no WhatsApp
        </a>
      </div>

      <template v-if="queue?.open">
        <div class="card">
          <div class="step-head">
            <span class="step-chip"><span class="n">1</span>Serviço</span>
            <h3>Qual serviço você quer?</h3>
          </div>
          <p v-if="!business.services.length" class="muted">Nenhum serviço disponível no momento.</p>
          <div v-else class="svc-grid">
            <button v-for="s in business.services" :key="s.id" type="button" class="svc-card" :class="{ on: service?.id === s.id }" @click="pick(s)">
              <div class="svc-icon"><Icon name="sparkles" /></div>
              <div class="svc-body">
                <span class="name">{{ s.name }}</span>
                <span v-if="s.description" class="desc">{{ s.description }}</span>
              </div>
              <div class="svc-meta">
                <span class="svc-price">{{ money(s.price) }}</span>
                <span class="svc-duration"><Icon name="clock" />{{ s.duration_min }} min</span>
              </div>
            </button>
          </div>
        </div>

        <div v-if="service" class="card">
          <div class="step-head">
            <span class="step-chip"><span class="n">2</span>Seus dados</span>
            <h3>Entrar na fila</h3>
            <p v-if="readyAt">Se entrar agora, seu carro fica pronto por volta de <strong>{{ readyAt }}</strong>.</p>
          </div>
          <form class="qj-form" @submit.prevent="join">
            <div class="ff"><input v-model="form.name" required maxlength="80" placeholder=" " /><label>Seu nome</label></div>
            <div class="ff"><input v-model="form.phone" type="tel" required maxlength="30" placeholder=" " /><label>WhatsApp com DDD</label></div>
            <div class="ff"><input v-model="form.vehicle" maxlength="80" placeholder=" " /><label>Veículo <small>(modelo e cor, opcional)</small></label></div>
            <div class="ff"><input v-model="form.notes" maxlength="500" placeholder=" " /><label>Observação <small>(opcional)</small></label></div>
            <div v-if="error" class="error">{{ error }}</div>
            <button class="btn qj-submit" :disabled="sending">
              {{ sending ? 'Entrando…' : `Entrar na fila · ${money(service.price)}` }}
            </button>
          </form>
        </div>
      </template>
      <!-- Fila encerrada: mostra os serviços mesmo assim, pra página não ficar vazia -->
      <div v-else-if="queue && business.services.length" class="card">
        <div class="step-head">
          <h3>Nossos serviços</h3>
          <p>Quando a fila abrir, é só escolher, entrar e acompanhar pelo celular.</p>
        </div>
        <div class="svc-grid">
          <div v-for="s in business.services" :key="s.id" class="svc-card qj-static">
            <div class="svc-icon"><Icon name="sparkles" /></div>
            <div class="svc-body">
              <span class="name">{{ s.name }}</span>
              <span v-if="s.description" class="desc">{{ s.description }}</span>
            </div>
            <div class="svc-meta">
              <span class="svc-price">{{ money(s.price) }}</span>
              <span class="svc-duration"><Icon name="clock" />{{ s.duration_min }} min</span>
            </div>
          </div>
        </div>
      </div>

    </template>
  </template>
</template>

<style scoped>
.qj-ticket { text-align: center; }
.qj-label { text-transform: uppercase; letter-spacing: 0.12em; font-size: 0.78rem; color: var(--muted); font-weight: 700; }
.qj-number { font-size: 3.6rem; font-weight: 800; line-height: 1.05; margin: 4px 0 6px; }
.qj-ticket h2 { margin: 0 0 6px; }
.qj-big { font-size: 1.15rem; font-weight: 700; margin: 0 0 6px; }
.qj-status { display: flex; gap: 12px; align-items: flex-start; margin-bottom: 14px; }
.qj-status strong { display: block; font-size: 1.05rem; }
.qj-status p { margin: 4px 0 0; color: var(--muted); }
.qj-status p strong { display: inline; font-size: inherit; color: var(--text); }
.qj-dot { width: 12px; height: 12px; border-radius: 999px; margin-top: 6px; flex-shrink: 0; background: #22c55e; box-shadow: 0 0 0 4px rgba(34, 197, 94, 0.2); }
.qj-hint { font-size: 0.86rem; }
.qj-last { color: #fbbf24 !important; font-weight: 700; }
.qj-ready { margin: 8px 0 4px; }
.qj-closed { text-align: center; margin-bottom: 14px; display: grid; gap: 6px; }
.qj-closed h3 { margin: 0; font-size: 1.25rem; }
.qj-closed > p { margin: 0; }
.qj-closed-ico { font-size: 2.2rem; line-height: 1; }
.qj-notify { text-align: left; display: grid; gap: 4px; margin-top: 10px; padding: 14px; border-radius: 14px; background: var(--surface); border: 1px solid var(--border); }
.qj-notify-title { margin: 0; font-weight: 700; }
.qj-notified { display: flex; gap: 10px; align-items: center; text-align: left; margin-top: 10px; padding: 12px 14px; border-radius: 14px;
  background: rgba(34, 197, 94, 0.12); border: 1px solid rgba(34, 197, 94, 0.4); }
.qj-notified svg { width: 20px; height: 20px; color: #22c55e; flex-shrink: 0; }
.qj-form { display: grid; gap: 4px; }
.qj-submit { width: 100%; margin-top: 8px; }
.qj-static { cursor: default; }
.qj-ready-big { font-size: 2.6rem; line-height: 1; margin: 4px 0 6px; }
.qj-alert-btn { display: flex; gap: 12px; align-items: flex-start; width: 100%; text-align: left; margin-top: 14px; padding: 12px 14px; border-radius: 14px;
  cursor: pointer; font: inherit; color: var(--text); background: var(--surface); border: 1px dashed var(--brand); }
.qj-alert-btn svg { width: 20px; height: 20px; color: var(--brand); flex-shrink: 0; margin-top: 2px; }
.qj-alert-btn strong { display: block; }
.qj-alert-btn small { display: block; color: var(--muted); margin-top: 2px; }
.qj-alert-on { display: flex; gap: 8px; align-items: center; justify-content: center; margin: 14px 0 0; font-size: 0.88rem; color: #22c55e; }
.qj-alert-on svg { width: 16px; height: 16px; }
</style>
