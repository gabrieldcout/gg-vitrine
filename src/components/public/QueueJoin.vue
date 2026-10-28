<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { money, todayISO } from '@/lib/format'
import { waLink } from '@/lib/whatsapp'
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
  ticket.value = data
}
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
        <small class="muted">A previsão é uma estimativa e atualiza sozinha.</small>
      </template>
      <template v-else-if="ticket.status === 'atendendo'">
        <h2>Seu atendimento começou!</h2>
        <p class="muted" style="margin: 0">Avisamos quando estiver pronto.</p>
      </template>
      <template v-else-if="ticket.status === 'pronto'">
        <h2>Pronto!</h2>
        <p class="muted" style="margin: 0">Seu serviço foi finalizado. Obrigado pela preferência!</p>
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

      <div class="done-actions">
        <a v-if="ticketWa && ticket.status !== 'pronto'" :href="ticketWa" target="_blank" rel="noopener" class="btn">
          <Icon name="whatsapp" />Falar com a loja no WhatsApp
        </a>
        <button v-if="ticket.status === 'aguardando'" class="btn secondary" @click="leave">Sair da fila</button>
        <button v-if="!activeTicket" class="btn secondary" @click="newTicket">Entrar na fila de novo</button>
      </div>
    </div>

    <template v-else>
      <!-- Situação da fila -->
      <div v-if="queue" class="card qj-status" :class="queue.open ? 'open' : 'closed'">
        <span class="qj-dot" />
        <div>
          <template v-if="queue.open">
            <strong>Fila aberta</strong>
            <p>
              {{ ahead === 0 ? 'Ninguém na fila agora.' : `${plural(ahead, 'cliente', 'clientes')} na sua frente.` }}
              Previsão se entrar agora: <strong>{{ queue.wait_min <= 0 ? 'atendimento imediato' : `por volta de ${clock(queue.wait_min)} (${waitText(queue.wait_min)})` }}</strong>.
            </p>
          </template>
          <template v-else>
            <strong>Novos serviços encerrados</strong>
            <p>{{ queue.closed_today ? 'Não estamos aceitando novos clientes hoje. ' : '' }}{{ closedText || 'Volte mais tarde.' }}</p>
          </template>
        </div>
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
      <div v-else-if="error" class="error">{{ error }}</div>
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
.qj-status.closed { border-color: rgba(239, 68, 68, 0.45); }
.qj-status.closed .qj-dot { background: #ef4444; box-shadow: 0 0 0 4px rgba(239, 68, 68, 0.2); }
.qj-form { display: grid; gap: 4px; }
.qj-submit { width: 100%; margin-top: 8px; }
</style>
