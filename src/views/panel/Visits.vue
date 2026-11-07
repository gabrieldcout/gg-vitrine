<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useBusiness } from '@/lib/business'
import Icon from '@/components/Icon.vue'
import Upsell from '@/components/Upsell.vue'

const biz = useBusiness()
const allowed = computed(() => biz.hasFeature('relatorio_visitas'))
const kind = computed(() => biz.business.kind ?? 'agenda')
const days = ref(30)
const stats = ref(null)
const error = ref('')
const loading = ref(false)

async function load() {
  if (!allowed.value) return
  loading.value = true
  error.value = ''
  const { data, error: err } = await supabase.rpc('visit_stats', { p_business: biz.business.id, p_days: days.value })
  loading.value = false
  if (err) { error.value = err.message; return }
  stats.value = data
}
onMounted(load)
watch(days, load)

const t = computed(() => stats.value?.totals ?? {})
const n = (k) => Number(t.value[k] ?? 0)
const goal = computed(() => (kind.value === 'cardapio'
  ? { key: 'pedido', label: 'Pedidos feitos' }
  : kind.value === 'fila' ? { key: 'fila', label: 'Entradas na fila' } : { key: 'agendamento', label: 'Agendamentos' }))
const tiles = computed(() => [
  { label: 'Visitas na vitrine', value: n('visita'), icon: 'eye' },
  { label: 'Cliques no WhatsApp', value: n('whatsapp'), icon: 'whatsapp' },
  { label: 'Cliques nos links', value: n('link'), icon: 'link' },
  { label: goal.value.label, value: n(goal.value.key), icon: kind.value === 'cardapio' ? 'bag' : 'calendar' },
])
// De cada 100 visitas, quantas viraram pedido/agendamento.
const conversion = computed(() => (n('visita') ? Math.round((n(goal.value.key) / n('visita')) * 1000) / 10 : null))

const daily = computed(() => stats.value?.daily ?? [])
const maxDay = computed(() => Math.max(1, ...daily.value.map((d) => d.visitas)))
const dayLabel = (iso) => new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })
const weekday = (iso) => new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR', { weekday: 'short' }).replace('.', '')
// Rótulos do eixo: o primeiro, o último e alguns no meio.
const tickEvery = computed(() => Math.max(1, Math.ceil(daily.value.length / 6)))
const hover = ref(null)
const best = computed(() => daily.value.reduce((a, d) => (d.visitas > (a?.visitas ?? -1) ? d : a), null))
const showTable = ref(false)
</script>

<template>
  <div class="page-header spread">
    <div>
      <p class="eyebrow">Divulgar</p>
      <h1>Visitas</h1>
      <p class="muted">Quantas pessoas abriram sua vitrine e o que elas fizeram lá.</p>
    </div>
    <div v-if="allowed" class="vs-range" role="group" aria-label="Período">
      <button v-for="d in [7, 30, 90]" :key="d" type="button" class="chip" :class="{ selected: days === d }" @click="days = d">
        {{ d }} dias
      </button>
    </div>
  </div>

  <Upsell v-if="!allowed" feature="relatorio_visitas" />

  <template v-else>
    <div v-if="error" class="error">{{ error }}</div>

    <div class="vs-tiles">
      <div v-for="tile in tiles" :key="tile.label" class="card vs-tile">
        <span class="vs-tile-ico"><Icon :name="tile.icon" /></span>
        <span class="vs-tile-label">{{ tile.label }}</span>
        <strong class="vs-tile-value">{{ loading && !stats ? '…' : tile.value.toLocaleString('pt-BR') }}</strong>
      </div>
    </div>
    <p v-if="conversion !== null" class="muted vs-conv">
      De cada 100 visitas, <strong>{{ String(conversion).replace('.', ',') }}</strong> viraram {{ goal.label.toLowerCase() }}.
    </p>

    <section class="card vs-chart-card">
      <div class="spread">
        <h3 style="margin: 0">Visitas por dia</h3>
        <button type="button" class="link-btn" @click="showTable = !showTable">{{ showTable ? 'Ver gráfico' : 'Ver em tabela' }}</button>
      </div>

      <template v-if="!showTable">
        <div class="vs-chart" @mouseleave="hover = null">
          <div v-for="d in daily" :key="d.day" class="vs-col" tabindex="0"
               :aria-label="`${dayLabel(d.day)}: ${d.visitas} visitas, ${d.cliques} cliques`"
               @mouseenter="hover = d" @focus="hover = d" @click="hover = d">
            <div class="vs-bar" :class="{ on: hover === d }" :style="{ height: `${(d.visitas / maxDay) * 100}%` }" />
          </div>
          <div v-if="hover" class="vs-tip">
            <strong>{{ weekday(hover.day) }}, {{ dayLabel(hover.day) }}</strong>
            <span>{{ hover.visitas }} {{ hover.visitas === 1 ? 'visita' : 'visitas' }}</span>
            <span>{{ hover.cliques }} {{ hover.cliques === 1 ? 'clique' : 'cliques' }}</span>
          </div>
        </div>
        <div class="vs-axis">
          <span v-for="(d, i) in daily" :key="d.day">{{ i % tickEvery === 0 || i === daily.length - 1 ? dayLabel(d.day) : '' }}</span>
        </div>
        <p v-if="best && best.visitas" class="muted vs-best">
          Dia com mais visitas: {{ weekday(best.day) }}, {{ dayLabel(best.day) }} ({{ best.visitas }}).
        </p>
        <p v-else-if="stats" class="muted vs-best">Ainda sem visitas nesse período. Divulgue seu link no WhatsApp e no Instagram.</p>
      </template>

      <div v-else class="table-wrap">
        <table>
          <thead><tr><th>Dia</th><th>Visitas</th><th>Cliques</th></tr></thead>
          <tbody>
            <tr v-for="d in [...daily].reverse()" :key="d.day">
              <td>{{ weekday(d.day) }}, {{ dayLabel(d.day) }}</td><td>{{ d.visitas }}</td><td>{{ d.cliques }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section v-if="stats?.links?.length" class="card">
      <h3 style="margin-top: 0">Links mais clicados</h3>
      <div v-for="l in stats.links" :key="l.label" class="vs-link">
        <span>{{ l.label }}</span>
        <div class="vs-link-track"><div class="vs-link-bar" :style="{ width: `${(l.n / stats.links[0].n) * 100}%` }" /></div>
        <strong>{{ l.n }}</strong>
      </div>
    </section>
  </template>
</template>

<style scoped>
.vs-range { display: flex; gap: 6px; }
.vs-tiles { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 10px; }
.vs-tile { display: grid; gap: 4px; padding: 16px; margin: 0; }
.vs-tile-ico { color: var(--muted); }
.vs-tile-ico :deep(svg) { width: 18px; height: 18px; }
.vs-tile-label { font-size: 0.84rem; color: var(--muted); }
.vs-tile-value { font-size: 1.7rem; letter-spacing: -0.02em; }
.vs-conv { margin: 0 0 16px; font-size: 0.9rem; }
.vs-chart-card { margin-top: 6px; }
.vs-chart { position: relative; display: flex; align-items: flex-end; gap: 2px; height: 180px; margin-top: 16px;
  border-bottom: 1px solid var(--border); }
.vs-col { flex: 1; height: 100%; display: flex; align-items: flex-end; cursor: pointer; outline: none; }
.vs-bar { width: 100%; min-height: 2px; border-radius: 4px 4px 0 0; background: #3b82f6; opacity: 0.85; transition: opacity 0.15s; }
.vs-bar.on, .vs-col:focus-visible .vs-bar { opacity: 1; box-shadow: 0 0 0 2px var(--bg, #050b16), 0 0 0 3px #93c5fd; }
.vs-tip { position: absolute; top: 0; right: 0; display: grid; gap: 2px; padding: 8px 10px; border-radius: 10px; font-size: 0.82rem;
  background: var(--surface-strong, #0b1730); border: 1px solid var(--border); box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4); pointer-events: none; }
.vs-tip span { color: var(--silver); }
.vs-axis { display: flex; gap: 2px; margin-top: 6px; }
.vs-axis span { flex: 1; font-size: 0.7rem; color: var(--muted); white-space: nowrap; overflow: visible; }
.vs-best { margin: 12px 0 0; font-size: 0.88rem; }
.vs-link { display: grid; grid-template-columns: minmax(90px, 160px) 1fr auto; gap: 10px; align-items: center; padding: 6px 0; }
.vs-link span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 0.9rem; }
.vs-link-track { height: 8px; border-radius: 4px; background: rgba(255, 255, 255, 0.06); }
.vs-link-bar { height: 100%; border-radius: 4px; background: #3b82f6; }
@media (max-width: 760px) { .vs-tiles { grid-template-columns: repeat(2, 1fr); } }
</style>
