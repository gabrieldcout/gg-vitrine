<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { supabase } from '@/lib/supabase'
import { useBusiness } from '@/lib/business'
import { money } from '@/lib/format'
import Icon from '@/components/Icon.vue'

const biz = useBusiness()

const PERIODS = [
  { key: 'today', label: 'Hoje' },
  { key: 'week', label: 'Esta semana' },
  { key: 'month', label: 'Este mês' },
  { key: 'lastMonth', label: 'Mês passado' },
  { key: '30d', label: 'Últimos 30 dias' },
]

// Cardápio: os números saem dos pedidos (calculados aqui no navegador);
// agenda: da RPC business_dashboard, a partir dos agendamentos concluídos.
const isMenu = computed(() => biz.business.kind === 'cardapio')
const T = computed(() => (isMenu.value
  ? { one: 'pedido', many: 'pedidos', countLabel: 'Pedidos', rateLabel: 'Pedidos cancelados',
      topTitle: 'Mais vendidos', topSub: 'Os produtos que mais faturaram no período', topEmpty: 'Sem vendas no período',
      byTitle: 'Faturamento por forma de pagamento', bySub: 'Como seus clientes estão pagando',
      lede: 'Veja seu faturamento, pedidos e os produtos e clientes que te rendem mais.',
      emptyTitle: 'Sem pedidos nesse período', emptyText: 'Quando chegarem pedidos pela sua vitrine',
      emptyCta: 'Ver pedidos', emptyTo: '/painel/pedidos', chartHint: 'pedidos cancelados não entram' }
  : { one: 'agendamento', many: 'agendamentos', countLabel: 'Agendamentos concluídos', rateLabel: 'Taxa de no-show',
      topTitle: 'Top serviços', topSub: 'Os que mais faturaram no período', topEmpty: 'Sem serviços no período',
      byTitle: `Faturamento por ${biz.business.staff_label}`, bySub: 'Veja quem gerou mais receita no período',
      lede: 'Veja seu faturamento, agendamentos e os serviços e clientes que te rendem mais.',
      emptyTitle: 'Sem agendamentos concluídos nesse período', emptyText: 'Quando você marcar atendimentos como concluídos',
      emptyCta: 'Cadastrar primeiro agendamento', emptyTo: '/painel', chartHint: 'passe o mouse nas barras pra ver cada dia' }))
const unit = (n) => (Number(n) === 1 ? T.value.one : T.value.many)
const itemUnit = (n) => (isMenu.value ? (Number(n) === 1 ? 'unidade vendida' : 'unidades vendidas') : unit(n))

const localDay = (iso) => {
  const d = new Date(iso)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

// Mesmo formato da RPC, montado a partir dos pedidos do período.
async function loadMenuDashboard(start, end) {
  const { data: rows, error: err } = await supabase.from('orders')
    .select('total, status, created_at, customer_name, phone, payment, order_items(name, qty, total)')
    .eq('business_id', biz.business.id)
    .gte('created_at', start.toISOString()).lte('created_at', end.toISOString())
    .limit(5000)
  if (err) return { error: err }
  const all = rows ?? []
  const sold = all.filter((o) => o.status !== 'cancelado')
  const sum = (list) => list.reduce((t, x) => t + Number(x.total), 0)
  const group = (list, keyOf, nameOf, countOf = () => 1) => {
    const m = new Map()
    for (const x of list) {
      const k = keyOf(x)
      const g = m.get(k) ?? { name: nameOf(x), revenue: 0, count: 0 }
      g.revenue += Number(x.total); g.count += countOf(x)
      m.set(k, g)
    }
    return [...m.values()].sort((a, b) => b.revenue - a.revenue)
  }
  const total = sum(sold)
  return {
    data: {
      total_revenue: total,
      total_appointments: sold.length,
      avg_ticket: sold.length ? Math.round((total / sold.length) * 100) / 100 : 0,
      no_show_rate: all.length ? Math.round((1000 * (all.length - sold.length)) / all.length) / 10 : 0,
      revenue_by_day: group(sold, (o) => localDay(o.created_at), (o) => localDay(o.created_at))
        .map((g) => ({ day: g.name, revenue: g.revenue, count: g.count })),
      top_services: group(sold.flatMap((o) => o.order_items ?? []), (i) => i.name, (i) => i.name, (i) => Number(i.qty)).slice(0, 5),
      top_customers: group(sold, (o) => (o.phone ?? '').replace(/\D/g, '') || o.customer_name, (o) => o.customer_name).slice(0, 5),
      revenue_by_professional: group(sold, (o) => o.payment, (o) => o.payment),
    },
  }
}

const period = ref('30d')
const data = ref(null)
const loading = ref(false)
const error = ref('')

// Calcula início e fim do período selecionado (em horário local do navegador —
// a RPC trabalha com os timestamps absolutos dos agendamentos, então vale a
// faixa escolhida pelo dono do negócio).
function periodRange(p) {
  const now = new Date()
  const start = new Date(now)
  const end = new Date(now)
  if (p === 'today') {
    start.setHours(0, 0, 0, 0)
    end.setHours(23, 59, 59, 999)
  } else if (p === 'week') {
    // Segunda a domingo da semana atual
    const dow = now.getDay() // 0 = dom
    const diffToMon = dow === 0 ? -6 : 1 - dow
    start.setDate(now.getDate() + diffToMon)
    start.setHours(0, 0, 0, 0)
    end.setTime(start.getTime())
    end.setDate(start.getDate() + 6)
    end.setHours(23, 59, 59, 999)
  } else if (p === 'month') {
    start.setDate(1)
    start.setHours(0, 0, 0, 0)
    end.setMonth(start.getMonth() + 1, 0)
    end.setHours(23, 59, 59, 999)
  } else if (p === 'lastMonth') {
    start.setMonth(now.getMonth() - 1, 1)
    start.setHours(0, 0, 0, 0)
    end.setMonth(now.getMonth(), 0)
    end.setHours(23, 59, 59, 999)
  } else {
    // 30d (default)
    start.setDate(now.getDate() - 29)
    start.setHours(0, 0, 0, 0)
    end.setHours(23, 59, 59, 999)
  }
  return { start, end }
}

async function load() {
  loading.value = true
  error.value = ''
  const { start, end } = periodRange(period.value)
  const { data: r, error: err } = isMenu.value
    ? await loadMenuDashboard(start, end)
    : await supabase.rpc('business_dashboard', {
      p_business: biz.business.id,
      p_start: start.toISOString(),
      p_end: end.toISOString(),
    })
  if (err) error.value = err.message
  data.value = r ?? null
  loading.value = false
}

onMounted(load)
watch(period, load)

// ---------- Métricas ----------
const totalRevenue = computed(() => Number(data.value?.total_revenue ?? 0))
const totalAppts = computed(() => Number(data.value?.total_appointments ?? 0))
const avgTicket = computed(() => Number(data.value?.avg_ticket ?? 0))
const noShowRate = computed(() => Number(data.value?.no_show_rate ?? 0))

const noShowTone = computed(() => {
  if (noShowRate.value > 15) return 'danger'
  if (noShowRate.value > 10) return 'warning'
  return ''
})

// ---------- Gráfico de barras: faturamento por dia ----------
// Garante que todos os dias do período apareçam (até os zerados).
const chartData = computed(() => {
  if (!data.value) return []
  const map = new Map()
  for (const row of data.value.revenue_by_day ?? []) {
    // dia vem como ISO (YYYY-MM-DD ou timestamp); normaliza pra YYYY-MM-DD
    const key = String(row.day).slice(0, 10)
    map.set(key, { revenue: Number(row.revenue ?? 0), count: Number(row.count ?? 0) })
  }
  const { start, end } = periodRange(period.value)
  const days = []
  const cursor = new Date(start.getFullYear(), start.getMonth(), start.getDate())
  const limit = new Date(end.getFullYear(), end.getMonth(), end.getDate())
  while (cursor <= limit) {
    const y = cursor.getFullYear()
    const m = String(cursor.getMonth() + 1).padStart(2, '0')
    const d = String(cursor.getDate()).padStart(2, '0')
    const key = `${y}-${m}-${d}`
    const found = map.get(key)
    days.push({
      key,
      date: new Date(cursor),
      label: `${d}/${m}`,
      revenue: found?.revenue ?? 0,
      count: found?.count ?? 0,
    })
    cursor.setDate(cursor.getDate() + 1)
    if (days.length > 400) break // guard
  }
  return days
})

const chartMax = computed(() => Math.max(1, ...chartData.value.map((d) => d.revenue)))

// Quantas labels mostrar no eixo X (pra não ficar amontoado)
const xTickStep = computed(() => {
  const n = chartData.value.length
  if (n <= 10) return 1
  if (n <= 20) return 2
  if (n <= 35) return 4
  return 7
})

const hoverIndex = ref(null)

// ---------- Top listas ----------
const topServices = computed(() => data.value?.top_services ?? [])
const topCustomers = computed(() => data.value?.top_customers ?? [])
const byProfessional = computed(() => data.value?.revenue_by_professional ?? [])

const topServicesMax = computed(() => Math.max(1, ...topServices.value.map((s) => Number(s.revenue))))
const topCustomersMax = computed(() => Math.max(1, ...topCustomers.value.map((s) => Number(s.revenue))))
const byProMax = computed(() => Math.max(1, ...byProfessional.value.map((s) => Number(s.revenue))))

function pct(value, max) {
  if (!max) return 0
  return Math.max(2, Math.round((Number(value) / max) * 100))
}

const showProBlock = computed(() => byProfessional.value.length > 1)
const isEmpty = computed(() => !loading.value && data.value && totalAppts.value === 0)

const periodLabel = computed(() => PERIODS.find((p) => p.key === period.value)?.label ?? '')

// ---------- Lançamento de venda avulsa ----------
const showSale = ref(false)
const saleServices = ref([])
const salePros = ref([])
const saleForm = ref({
  service_id: '', professional_id: '', at: '', customer_name: '', customer_phone: '', price: '', notes: '',
})
const saleError = ref('')
const saleMsg = ref('')
const saleSaving = ref(false)

function nowLocalInput() {
  const d = new Date()
  const pad = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

async function openSaleModal() {
  saleError.value = saleMsg.value = ''
  // Carrega serviços e profissionais pra escolher.
  const [{ data: svcs }, { data: pros }] = await Promise.all([
    supabase.from('services').select('id, name, price').eq('business_id', biz.business.id).eq('active', true).order('name'),
    supabase.from('professionals').select('id, name').eq('business_id', biz.business.id).eq('active', true).order('name'),
  ])
  saleServices.value = svcs ?? []
  salePros.value = pros ?? []
  if (!saleServices.value.length) { saleError.value = 'Cadastre pelo menos 1 serviço antes.'; return }
  if (!salePros.value.length) { saleError.value = 'Cadastre pelo menos 1 profissional antes.'; return }
  saleForm.value = {
    service_id: saleServices.value[0].id,
    professional_id: salePros.value[0].id,
    at: nowLocalInput(),
    customer_name: '', customer_phone: '',
    price: '', notes: '',
  }
  showSale.value = true
}

function onSaleServiceChange() {
  const s = saleServices.value.find((x) => x.id === saleForm.value.service_id)
  if (s && !saleForm.value.price) saleForm.value.price = s.price
}

async function saveSale() {
  saleError.value = saleMsg.value = ''
  saleSaving.value = true
  const f = saleForm.value
  const atIso = new Date(f.at).toISOString()
  const { error: err } = await supabase.rpc('register_manual_sale', {
    p_business: biz.business.id,
    p_service: f.service_id,
    p_professional: f.professional_id,
    p_at: atIso,
    p_customer_name: f.customer_name,
    p_customer_phone: f.customer_phone || null,
    p_price: f.price === '' ? null : Number(f.price),
    p_notes: f.notes || null,
  })
  saleSaving.value = false
  if (err) { saleError.value = err.message; return }
  saleMsg.value = 'Venda registrada! Já aparece no faturamento.'
  showSale.value = false
  await load()
}
</script>

<template>
  <div class="page-header dash-header">
    <div>
      <p class="eyebrow dash-eyebrow">Painel financeiro</p>
      <h1>Dashboard</h1>
      <p class="muted dash-lede">
        {{ T.lede }}
      </p>
    </div>
    <button v-if="!isMenu" class="btn dash-sale-btn" @click="openSaleModal">
      <Icon name="plus" />
      Lançar venda avulsa
    </button>
  </div>

  <div v-if="saleMsg" class="alert alert-success" style="margin-bottom: 16px">
    <span class="alert-icon"><Icon name="check" /></span>
    <span>{{ saleMsg }}</span>
  </div>

  <!-- Filtro de período -->
  <div class="period-bar" role="tablist" aria-label="Período">
    <button v-for="p in PERIODS" :key="p.key" type="button"
            class="period-chip" :class="{ on: period === p.key }"
            role="tab" :aria-selected="period === p.key"
            @click="period = p.key">
      {{ p.label }}
    </button>
  </div>

  <div v-if="error" class="alert alert-danger">
    <span class="alert-icon"><Icon name="ban" /></span>
    <span>{{ error }}</span>
  </div>

  <!-- Loading -->
  <div v-if="loading && !data" class="dash-loading">
    <div class="loader-ring" />
    <small class="muted">Carregando seus números…</small>
  </div>

  <!-- Empty state -->
  <div v-else-if="isEmpty" class="empty-state">
    <div class="empty-icon-wrap">
      <div class="empty-icon-ring" />
      <div class="empty-icon-core"><Icon name="chart" /></div>
    </div>
    <h3>{{ T.emptyTitle }}</h3>
    <p class="muted">
      {{ T.emptyText }} em {{ periodLabel.toLowerCase() }},
      o faturamento, os clientes campeões e as métricas aparecem aqui.
    </p>
    <div class="empty-actions">
      <RouterLink :to="T.emptyTo" class="btn">
        <Icon :name="isMenu ? 'bag' : 'plus'" />
        {{ T.emptyCta }}
      </RouterLink>
    </div>
  </div>

  <template v-else-if="data">
    <!-- Métricas -->
    <div class="metrics-grid">
      <article class="metric-card accent">
        <div class="metric-ico"><Icon name="card" /></div>
        <small class="metric-label">Faturamento</small>
        <strong class="metric-value gradient-text">{{ money(totalRevenue) }}</strong>
      </article>
      <article class="metric-card">
        <div class="metric-ico"><Icon name="calendar" /></div>
        <small class="metric-label">{{ T.countLabel }}</small>
        <strong class="metric-value">{{ totalAppts }}</strong>
      </article>
      <article class="metric-card">
        <div class="metric-ico"><Icon name="sparkles" /></div>
        <small class="metric-label">Ticket médio</small>
        <strong class="metric-value">{{ money(avgTicket) }}</strong>
      </article>
      <article class="metric-card" :class="`tone-${noShowTone}`">
        <div class="metric-ico"><Icon name="ban" /></div>
        <small class="metric-label">{{ T.rateLabel }}</small>
        <strong class="metric-value">{{ noShowRate.toFixed(1) }}%</strong>
      </article>
    </div>

    <!-- Gráfico: Faturamento por dia -->
    <section class="dash-card chart-card">
      <div class="section-head">
        <span class="section-badge"><Icon name="chart" /></span>
        <div>
          <h3>Faturamento por dia</h3>
          <small class="muted">{{ periodLabel }} · {{ T.chartHint }}</small>
        </div>
      </div>

      <div class="chart-wrap">
        <div class="chart-scroll">
          <svg class="chart-svg" :viewBox="`0 0 ${Math.max(chartData.length * 36, 320)} 220`"
               :style="{ minWidth: `${Math.max(chartData.length * 36, 320)}px` }"
               preserveAspectRatio="none" aria-label="Faturamento por dia">
            <defs>
              <linearGradient id="barGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stop-color="var(--brand)" stop-opacity="1" />
                <stop offset="100%" stop-color="var(--brand-strong)" stop-opacity="0.6" />
              </linearGradient>
            </defs>

            <!-- Linhas de grade (4 níveis) -->
            <g class="chart-grid">
              <line v-for="n in 4" :key="n"
                    x1="0" :y1="40 + ((n - 1) * 35)"
                    :x2="Math.max(chartData.length * 36, 320)" :y2="40 + ((n - 1) * 35)" />
            </g>

            <!-- Barras -->
            <g>
              <g v-for="(d, i) in chartData" :key="d.key"
                 class="bar-group" :class="{ hover: hoverIndex === i }"
                 @mouseenter="hoverIndex = i" @mouseleave="hoverIndex = null">
                <!-- hitbox invisível pra captar hover em toda a coluna -->
                <rect :x="i * 36" y="20" width="36" height="180"
                      fill="transparent" />
                <rect :x="i * 36 + 7"
                      :y="200 - Math.max((d.revenue / chartMax) * 170, d.revenue > 0 ? 4 : 0)"
                      width="22"
                      :height="Math.max((d.revenue / chartMax) * 170, d.revenue > 0 ? 4 : 0)"
                      rx="4"
                      fill="url(#barGrad)"
                      class="bar-rect" />
                <text v-if="i % xTickStep === 0 || i === chartData.length - 1"
                      :x="i * 36 + 18" y="215"
                      class="bar-label" text-anchor="middle">{{ d.label }}</text>
              </g>
            </g>
          </svg>
        </div>

        <!-- Tooltip -->
        <div v-if="hoverIndex !== null && chartData[hoverIndex]" class="chart-tip">
          <strong>{{ chartData[hoverIndex].label }}</strong>
          <span class="gradient-text">{{ money(chartData[hoverIndex].revenue) }}</span>
          <small class="muted">
            {{ chartData[hoverIndex].count }}
            {{ unit(chartData[hoverIndex].count) }}
          </small>
        </div>
      </div>
    </section>

    <!-- Top listas (serviços + clientes) -->
    <div class="top-grid">
      <section class="dash-card">
        <div class="section-head">
          <span class="section-badge"><Icon name="briefcase" /></span>
          <div>
            <h3>{{ T.topTitle }}</h3>
            <small class="muted">{{ T.topSub }}</small>
          </div>
        </div>
        <div v-if="!topServices.length" class="mini-empty">
          <Icon name="briefcase" />
          <span>{{ T.topEmpty }}</span>
        </div>
        <ul v-else class="rank-list">
          <li v-for="(s, i) in topServices" :key="s.service_id ?? i" class="rank-row">
            <div class="rank-top">
              <span class="rank-pos">{{ i + 1 }}</span>
              <strong class="rank-name">{{ s.name }}</strong>
              <span class="rank-value">{{ money(s.revenue) }}</span>
            </div>
            <div class="rank-track">
              <div class="rank-fill" :style="{ width: pct(s.revenue, topServicesMax) + '%' }" />
            </div>
            <small class="muted rank-sub">
              {{ s.count }} {{ itemUnit(s.count) }}
            </small>
          </li>
        </ul>
      </section>

      <section class="dash-card">
        <div class="section-head">
          <span class="section-badge"><Icon name="users" /></span>
          <div>
            <h3>Top clientes</h3>
            <small class="muted">Quem mais investiu no seu negócio</small>
          </div>
        </div>
        <div v-if="!topCustomers.length" class="mini-empty">
          <Icon name="users" />
          <span>Sem clientes no período</span>
        </div>
        <ul v-else class="rank-list">
          <li v-for="(c, i) in topCustomers" :key="c.customer_id ?? i" class="rank-row">
            <div class="rank-top">
              <span class="rank-pos">{{ i + 1 }}</span>
              <strong class="rank-name">{{ c.name }}</strong>
              <span class="rank-value">{{ money(c.revenue) }}</span>
            </div>
            <div class="rank-track">
              <div class="rank-fill" :style="{ width: pct(c.revenue, topCustomersMax) + '%' }" />
            </div>
            <small class="muted rank-sub">
              {{ c.count }} {{ unit(c.count) }}
            </small>
          </li>
        </ul>
      </section>
    </div>

    <!-- Faturamento por profissional -->
    <section v-if="showProBlock" class="dash-card">
      <div class="section-head">
        <span class="section-badge"><Icon name="user" /></span>
        <div>
          <h3>{{ T.byTitle }}</h3>
          <small class="muted">{{ T.bySub }}</small>
        </div>
      </div>
      <ul class="rank-list">
        <li v-for="(p, i) in byProfessional" :key="p.professional_id ?? i" class="rank-row">
          <div class="rank-top">
            <span class="rank-pos">{{ i + 1 }}</span>
            <strong class="rank-name">{{ p.name }}</strong>
            <span class="rank-value">{{ money(p.revenue) }}</span>
          </div>
          <div class="rank-track">
            <div class="rank-fill" :style="{ width: pct(p.revenue, byProMax) + '%' }" />
          </div>
          <small class="muted rank-sub">
            {{ p.count }} {{ unit(p.count) }}
          </small>
        </li>
      </ul>
    </section>
  </template>

  <!-- Modal: lançar venda avulsa -->
  <div v-if="showSale" class="sale-modal-backdrop" @click.self="showSale = false">
    <form class="sale-modal" @submit.prevent="saveSale">
      <div class="sale-modal-head">
        <span class="section-badge"><Icon name="plus" /></span>
        <div style="flex: 1">
          <h3 style="margin: 0">Lançar venda avulsa</h3>
          <small class="muted">Pra atendimentos que não foram feitos pelo link.</small>
        </div>
        <button type="button" class="sale-modal-close" @click="showSale = false" aria-label="Fechar">×</button>
      </div>

      <div v-if="saleError" class="alert alert-danger" style="margin: 0 0 12px">
        <span class="alert-icon"><Icon name="ban" /></span>
        <span>{{ saleError }}</span>
      </div>

      <div class="ff-row">
        <div class="ff">
          <select v-model="saleForm.service_id" required @change="onSaleServiceChange">
            <option v-for="s in saleServices" :key="s.id" :value="s.id">{{ s.name }}</option>
          </select>
          <label>Serviço</label>
        </div>
        <div class="ff">
          <select v-model="saleForm.professional_id" required>
            <option v-for="p in salePros" :key="p.id" :value="p.id">{{ p.name }}</option>
          </select>
          <label>Profissional</label>
        </div>
      </div>

      <div class="ff-row">
        <div class="ff">
          <input v-model="saleForm.at" type="datetime-local" required placeholder=" " />
          <label>Quando</label>
        </div>
        <div class="ff">
          <input v-model="saleForm.price" type="number" min="0" step="0.01" placeholder=" " />
          <label>Valor (R$)</label>
        </div>
      </div>

      <div class="ff-row">
        <div class="ff">
          <input v-model="saleForm.customer_name" required placeholder=" " />
          <label>Nome do cliente</label>
        </div>
        <div class="ff">
          <input v-model="saleForm.customer_phone" type="tel" placeholder=" " />
          <label>WhatsApp (opcional)</label>
        </div>
      </div>

      <div class="ff">
        <textarea v-model="saleForm.notes" rows="2" placeholder=" " />
        <label>Observação (opcional)</label>
      </div>

      <div class="sale-modal-actions">
        <button type="button" class="btn secondary" @click="showSale = false">Cancelar</button>
        <button class="btn" :disabled="saleSaving">
          <Icon name="check" />
          {{ saleSaving ? 'Salvando...' : 'Registrar venda' }}
        </button>
      </div>
    </form>
  </div>
</template>

<style scoped>
/* =====================================================================
   Header
   ===================================================================== */
.dash-eyebrow { display: inline-block; margin-bottom: 6px; }
.dash-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
.dash-header h1 { font-size: clamp(1.4rem, 2.6vw, 1.9rem); letter-spacing: -0.02em; }
.dash-lede { font-size: 0.95rem; max-width: 540px; margin: 4px 0 0; }
.dash-sale-btn { flex-shrink: 0; align-self: center; }
@media (max-width: 520px) {
  .dash-sale-btn { width: 100%; }
}

/* Modal: lançar venda */
.sale-modal-backdrop {
  position: fixed; inset: 0; z-index: 90;
  background: rgba(5, 11, 22, 0.72);
  backdrop-filter: blur(6px);
  display: grid; place-items: center;
  padding: 16px;
  animation: fadein 0.2s ease;
}
@keyframes fadein { from { opacity: 0; } to { opacity: 1; } }
.sale-modal {
  width: min(560px, 100%);
  max-height: 90vh;
  overflow-y: auto;
  padding: 22px;
  border-radius: var(--radius);
  background:
    radial-gradient(ellipse 420px 200px at 100% 0%, var(--brand-soft), transparent 65%),
    var(--surface);
  border: 1px solid var(--border);
  box-shadow: var(--shadow), 0 0 40px rgba(0, 0, 0, 0.5);
}
.sale-modal-head { display: flex; align-items: center; gap: 12px; margin-bottom: 18px; }
.sale-modal-close {
  width: 32px; height: 32px; border-radius: 50%;
  background: var(--surface); border: 1px solid var(--border);
  color: var(--muted); font-size: 1.3rem; line-height: 1;
  cursor: pointer; transition: background 0.2s ease, color 0.2s ease, border-color 0.2s ease;
}
.sale-modal-close:hover { background: var(--danger-soft); color: var(--danger); border-color: var(--danger); }
.sale-modal-actions {
  display: flex; justify-content: flex-end; gap: 10px; margin-top: 10px;
  padding-top: 16px; border-top: 1px solid var(--border);
}
.ff-row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
@media (max-width: 520px) { .ff-row { grid-template-columns: 1fr; } }

/* =====================================================================
   Alertas
   ===================================================================== */
.alert {
  display: flex; align-items: flex-start; gap: 12px;
  padding: 12px 14px; border-radius: var(--radius-sm);
  border: 1px solid; margin-bottom: 16px; line-height: 1.5;
  font-size: 0.92rem;
}
.alert-danger { color: #fecaca; background: var(--danger-soft); border-color: rgba(248, 113, 113, 0.35); }
.alert-icon {
  flex-shrink: 0; width: 28px; height: 28px; border-radius: 10px;
  display: grid; place-items: center;
  background: rgba(248, 113, 113, 0.2); color: var(--danger);
}
.alert-icon :deep(svg) { width: 15px; height: 15px; stroke-width: 2.4; }

/* =====================================================================
   Filtro de período
   ===================================================================== */
.period-bar {
  display: flex; flex-wrap: wrap; gap: 6px;
  padding: 4px; margin-bottom: 20px;
  border-radius: 999px;
  background: var(--surface);
  border: 1px solid var(--border);
  width: fit-content;
  max-width: 100%;
  overflow-x: auto;
}
.period-chip {
  padding: 8px 16px;
  border-radius: 999px;
  background: transparent;
  border: none;
  color: var(--muted);
  font: inherit; font-size: 0.86rem; font-weight: 600;
  cursor: pointer;
  white-space: nowrap;
  min-height: 36px;
  transition: color 0.15s ease, background 0.15s ease, box-shadow 0.15s ease;
}
.period-chip:hover { color: var(--text); }
.period-chip.on {
  background: linear-gradient(120deg, var(--brand), var(--brand-strong));
  color: var(--brand-contrast);
  box-shadow: 0 0 18px var(--brand-glow);
}

/* =====================================================================
   Loading
   ===================================================================== */
.dash-loading {
  display: flex; flex-direction: column; align-items: center; gap: 14px;
  padding: 60px 20px;
}
.loader-ring {
  width: 36px; height: 36px;
  border-radius: 50%;
  border: 3px solid var(--brand-soft);
  border-top-color: var(--brand);
  animation: spin 0.9s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* =====================================================================
   Métricas (4 cards)
   ===================================================================== */
.metrics-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
  margin-bottom: 20px;
}
.metric-card {
  position: relative;
  padding: 18px;
  border-radius: var(--radius);
  background: var(--surface);
  border: 1px solid var(--border);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  overflow: hidden;
  transition: transform 0.2s ease, border-color 0.2s ease, box-shadow 0.2s ease;
}
.metric-card:hover {
  transform: translateY(-2px);
  border-color: var(--brand);
  box-shadow: 0 0 24px var(--brand-soft);
}
.metric-card.accent {
  background:
    radial-gradient(ellipse 300px 180px at 100% 0%, var(--brand-soft), transparent 70%),
    var(--surface);
  border-color: rgba(59, 130, 246, 0.3);
}
.metric-card.tone-warning {
  border-color: rgba(251, 191, 36, 0.4);
  background:
    radial-gradient(ellipse 240px 140px at 100% 0%, rgba(251, 191, 36, 0.12), transparent 70%),
    var(--surface);
}
.metric-card.tone-warning .metric-value { color: var(--warning); }
.metric-card.tone-warning .metric-ico { background: var(--warning-soft); color: var(--warning); border-color: rgba(251, 191, 36, 0.3); }
.metric-card.tone-danger {
  border-color: rgba(248, 113, 113, 0.4);
  background:
    radial-gradient(ellipse 240px 140px at 100% 0%, rgba(248, 113, 113, 0.12), transparent 70%),
    var(--surface);
}
.metric-card.tone-danger .metric-value { color: var(--danger); }
.metric-card.tone-danger .metric-ico { background: var(--danger-soft); color: var(--danger); border-color: rgba(248, 113, 113, 0.3); }

.metric-ico {
  width: 38px; height: 38px; border-radius: 12px;
  display: grid; place-items: center;
  background: var(--brand-soft);
  color: var(--brand-ink);
  border: 1px solid rgba(59, 130, 246, 0.3);
  margin-bottom: 12px;
}
.metric-ico :deep(svg) { width: 18px; height: 18px; }
.metric-label {
  display: block;
  font-size: 0.7rem;
  color: var(--muted);
  text-transform: uppercase;
  letter-spacing: 0.1em;
  font-weight: 700;
  margin-bottom: 6px;
}
.metric-value {
  display: block;
  font-size: clamp(1.3rem, 2.2vw, 1.75rem);
  font-weight: 800;
  letter-spacing: -0.02em;
  color: var(--text);
  line-height: 1.1;
}

/* =====================================================================
   Cartões de seção
   ===================================================================== */
.dash-card {
  padding: 22px;
  margin-bottom: 20px;
  border-radius: var(--radius);
  background:
    radial-gradient(ellipse 320px 180px at 100% 0%, var(--brand-soft), transparent 65%),
    var(--surface);
  border: 1px solid var(--border);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
}

.section-head {
  display: flex; align-items: center; gap: 12px;
  margin-bottom: 18px;
}
.section-badge {
  width: 40px; height: 40px; border-radius: 12px; flex-shrink: 0;
  display: grid; place-items: center;
  background: linear-gradient(140deg, var(--brand), var(--brand-strong));
  color: #fff;
  box-shadow: 0 0 18px var(--brand-glow);
}
.section-badge :deep(svg) { width: 18px; height: 18px; }
.section-head h3 { margin: 0; font-size: 1.1rem; font-weight: 700; letter-spacing: -0.01em; }
.section-head small { display: block; font-size: 0.84rem; margin-top: 2px; }

/* =====================================================================
   Gráfico de barras (SVG puro)
   ===================================================================== */
.chart-card { position: relative; }
.chart-wrap {
  position: relative;
}
.chart-scroll {
  overflow-x: auto;
  overflow-y: hidden;
  padding-bottom: 4px;
  -webkit-overflow-scrolling: touch;
}
.chart-scroll::-webkit-scrollbar { height: 6px; }
.chart-scroll::-webkit-scrollbar-thumb { background: var(--border); border-radius: 999px; }

.chart-svg {
  display: block;
  width: 100%;
  height: 220px;
}

.chart-grid line {
  stroke: var(--border);
  stroke-width: 0.5;
  stroke-dasharray: 2 4;
}
.bar-rect {
  transition: filter 0.15s ease, opacity 0.15s ease;
}
.bar-group:hover .bar-rect {
  filter: drop-shadow(0 0 8px var(--brand-glow));
}
.bar-group.hover .bar-rect {
  filter: drop-shadow(0 0 8px var(--brand-glow));
}
.bar-label {
  fill: var(--muted);
  font-size: 10px;
  font-weight: 600;
  font-family: inherit;
}

.chart-tip {
  position: absolute;
  top: 8px; right: 8px;
  display: flex; flex-direction: column; gap: 2px;
  padding: 10px 14px;
  border-radius: var(--radius-sm);
  background: rgba(5, 11, 22, 0.92);
  border: 1px solid var(--brand);
  box-shadow: 0 10px 24px rgba(0, 0, 0, 0.4), 0 0 20px var(--brand-soft);
  pointer-events: none;
  min-width: 140px;
}
.chart-tip strong {
  font-size: 0.78rem;
  color: var(--muted);
  text-transform: uppercase;
  letter-spacing: 0.08em;
  font-weight: 700;
}
.chart-tip .gradient-text {
  font-size: 1.1rem; font-weight: 800; letter-spacing: -0.02em;
}
.chart-tip small { font-size: 0.74rem; }

/* =====================================================================
   Top listas (rank)
   ===================================================================== */
.top-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}
.top-grid .dash-card { margin-bottom: 20px; }

.rank-list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.rank-row {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.rank-top {
  display: flex; align-items: center; gap: 10px;
}
.rank-pos {
  width: 24px; height: 24px; border-radius: 999px;
  display: grid; place-items: center;
  flex-shrink: 0;
  background: var(--brand-soft);
  color: var(--brand-ink);
  border: 1px solid rgba(59, 130, 246, 0.3);
  font-size: 0.74rem; font-weight: 800;
}
.rank-name {
  flex: 1;
  min-width: 0;
  font-size: 0.94rem;
  font-weight: 600;
  color: var(--text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.rank-value {
  font-size: 0.95rem;
  font-weight: 800;
  letter-spacing: -0.01em;
  color: var(--text);
  flex-shrink: 0;
}
.rank-track {
  position: relative;
  height: 6px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.05);
  overflow: hidden;
}
.rank-fill {
  position: absolute; left: 0; top: 0; bottom: 0;
  border-radius: 999px;
  background: linear-gradient(90deg, var(--brand), var(--brand-strong));
  box-shadow: 0 0 12px var(--brand-glow);
  transition: width 0.4s ease;
}
.rank-sub {
  font-size: 0.76rem;
  padding-left: 34px;
}

.mini-empty {
  display: flex; align-items: center; gap: 10px;
  justify-content: center;
  padding: 24px 16px;
  color: var(--muted);
  font-size: 0.88rem;
  border: 1px dashed var(--border);
  border-radius: var(--radius-sm);
}
.mini-empty :deep(svg) { width: 18px; height: 18px; }

/* =====================================================================
   Empty state
   ===================================================================== */
.empty-state {
  text-align: center;
  padding: 48px 24px;
  border-radius: var(--radius);
  background:
    radial-gradient(ellipse 400px 200px at 50% 0%, var(--brand-soft), transparent 70%),
    var(--surface);
  border: 1px dashed var(--border);
}
.empty-icon-wrap { position: relative; width: 88px; height: 88px; margin: 0 auto 20px; }
.empty-icon-ring {
  position: absolute; inset: 0; border-radius: 50%;
  background: radial-gradient(circle, var(--brand-glow), transparent 70%);
  animation: ringPulse 2.4s ease-in-out infinite;
}
@keyframes ringPulse {
  0%, 100% { transform: scale(1); opacity: 0.7; }
  50% { transform: scale(1.12); opacity: 0.35; }
}
.empty-icon-core {
  position: absolute; inset: 12px;
  border-radius: 50%; display: grid; place-items: center;
  background: linear-gradient(140deg, var(--brand), var(--brand-strong));
  color: #fff;
  box-shadow: 0 10px 30px var(--brand-glow);
}
.empty-icon-core :deep(svg) { width: 28px; height: 28px; }
.empty-state h3 {
  font-size: 1.2rem; font-weight: 800;
  letter-spacing: -0.02em; margin: 0 0 10px;
}
.empty-state p {
  margin: 0 auto 20px;
  max-width: 420px;
  font-size: 0.94rem; line-height: 1.5;
}
.empty-actions { display: flex; justify-content: center; gap: 10px; flex-wrap: wrap; }
.empty-actions .btn :deep(svg) { width: 16px; height: 16px; }

/* =====================================================================
   Responsive
   ===================================================================== */
@media (max-width: 900px) {
  .metrics-grid { grid-template-columns: repeat(2, 1fr); }
  .top-grid { grid-template-columns: 1fr; gap: 0; }
}

@media (max-width: 520px) {
  .dash-card { padding: 18px; }
  .metric-card { padding: 16px; }
  .metric-ico { width: 34px; height: 34px; margin-bottom: 10px; }
  .period-bar {
    width: 100%;
    justify-content: flex-start;
    flex-wrap: nowrap;
  }
  .period-chip { font-size: 0.82rem; padding: 7px 12px; }
  .chart-tip {
    top: auto; bottom: 8px; left: 8px; right: auto;
  }
  .rank-sub { padding-left: 0; }
}

@media (prefers-reduced-motion: reduce) {
  .empty-icon-ring { animation: none; }
  .loader-ring { animation: none; border-top-color: var(--brand-soft); }
  .rank-fill { transition: none; }
}
</style>
