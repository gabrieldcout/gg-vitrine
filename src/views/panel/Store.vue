<script setup>
import { ref, onMounted } from 'vue'
import { supabase, unwrap } from '@/lib/supabase'
import { useBusiness } from '@/lib/business'
import { WEEKDAYS } from '@/lib/format'
import { catalogWord } from '@/config/brand'

const biz = useBusiness()
const error = ref('')
const saved = ref('')
const settings = ref({})
const days = ref([])   // [{ weekday, open, intervals: [{ start, end }] }]
const zones = ref([])  // bairros atendidos: [{ name, fee }]

onMounted(async () => {
  const b = biz.business
  settings.value = {
    accepting_orders: b.accepting_orders, pickup_enabled: b.pickup_enabled, delivery_enabled: b.delivery_enabled,
    delivery_fee: b.delivery_fee, min_order: b.min_order, delivery_area: b.delivery_area ?? '',
    delivery_other: b.delivery_other ?? true,
  }
  zones.value = unwrap(await supabase.from('delivery_zones').select('name, fee')
    .eq('business_id', b.id).order('sort_order').order('name'))
    .map((z) => ({ name: z.name, fee: Number(z.fee) }))
  const rows = unwrap(await supabase.from('store_hours').select('*').eq('business_id', b.id).order('start_time'))
  days.value = WEEKDAYS.map((_, weekday) => {
    const mine = rows.filter((r) => r.weekday === weekday)
    return {
      weekday,
      open: mine.length > 0,
      intervals: mine.length
        ? mine.map((r) => ({ start: r.start_time.slice(0, 5), end: r.end_time.slice(0, 5) }))
        : [{ start: '18:00', end: '23:00' }],
    }
  })
})

function flash(msg) {
  saved.value = msg
  setTimeout(() => { if (saved.value === msg) saved.value = '' }, 3000)
}

async function togglePause() {
  error.value = ''
  const value = !settings.value.accepting_orders
  const { error: err } = await supabase.from('businesses').update({ accepting_orders: value }).eq('id', biz.business.id)
  if (err) { error.value = err.message; return }
  settings.value.accepting_orders = value
  biz.business.accepting_orders = value
  flash(value ? 'Loja aberta para pedidos.' : 'Pedidos pausados.')
}

async function saveSettings() {
  error.value = ''
  const s = settings.value
  if (!s.pickup_enabled && !s.delivery_enabled) {
    error.value = 'Ative pelo menos retirada ou entrega.'
    return
  }
  const { error: err } = await supabase.from('businesses').update({
    pickup_enabled: s.pickup_enabled, delivery_enabled: s.delivery_enabled,
    delivery_fee: Number(s.delivery_fee || 0), min_order: Number(s.min_order || 0),
    delivery_area: s.delivery_area || null,
    ...(biz.business.delivery_other === undefined ? {} : { delivery_other: s.delivery_other }),
  }).eq('id', biz.business.id)
  if (err) { error.value = err.message; return }
  await biz.reload()
  flash('Entrega e retirada salvas.')
}

// Bairros: apaga e grava a lista inteira de novo (é curta e editada de uma vez).
async function saveZones() {
  error.value = ''
  const rows = zones.value
    .map((z, i) => ({ business_id: biz.business.id, name: z.name.trim(), fee: Number(z.fee || 0), sort_order: i }))
    .filter((z) => z.name)
  const names = rows.map((z) => z.name.toLowerCase())
  if (new Set(names).size !== names.length) {
    error.value = 'Tem bairro repetido na lista.'
    return
  }
  try {
    unwrap(await supabase.from('delivery_zones').delete().eq('business_id', biz.business.id))
    if (rows.length) unwrap(await supabase.from('delivery_zones').insert(rows))
    zones.value = rows.map((z) => ({ name: z.name, fee: z.fee }))
    flash(rows.length ? 'Bairros e taxas salvos.' : 'Lista de bairros apagada. Vale a taxa única.')
  } catch (e) {
    error.value = e.message
  }
}

async function saveHours() {
  error.value = ''
  const rows = days.value.filter((d) => d.open).flatMap((d) =>
    d.intervals.map((i) => ({ business_id: biz.business.id, weekday: d.weekday, start_time: i.start, end_time: i.end })))
  if (rows.some((r) => r.start_time === r.end_time)) {
    error.value = 'Os horários de abertura e de fechamento não podem ser iguais.'
    return
  }
  try {
    unwrap(await supabase.from('store_hours').delete().eq('business_id', biz.business.id))
    if (rows.length) unwrap(await supabase.from('store_hours').insert(rows))
    flash('Horários salvos.')
  } catch (e) {
    error.value = e.message
  }
}
</script>

<template>
  <div class="page-header">
    <p class="eyebrow">{{ catalogWord(biz.business.category) }}</p>
    <h1>Funcionamento</h1>
  </div>
  <div v-if="error" class="error">{{ error }}</div>
  <div v-if="saved" class="success">{{ saved }}</div>

  <!-- Pausa -->
  <div class="card spread" :class="{ glow: settings.accepting_orders }">
    <div>
      <h3 style="margin-bottom: 4px">
        <span :class="['badge', settings.accepting_orders ? 'green' : 'red']">
          {{ settings.accepting_orders ? 'Recebendo pedidos' : 'Pedidos pausados' }}
        </span>
      </h3>
      <p class="muted" style="margin: 0">
        {{ settings.accepting_orders
          ? 'Fora do horário de funcionamento, sua vitrine aparece como fechada automaticamente.'
          : 'Seus clientes veem os produtos, mas não conseguem enviar pedidos.' }}
      </p>
    </div>
    <button :class="['btn', settings.accepting_orders ? 'danger' : '']" @click="togglePause">
      {{ settings.accepting_orders ? 'Pausar pedidos agora' : 'Voltar a receber pedidos' }}
    </button>
  </div>

  <!-- Horários -->
  <div class="card">
    <h3>Dias e horários</h3>
    <p class="muted">Se fechar depois da meia-noite, é só colocar o horário normalmente (ex.: 18:00 até 01:00).</p>
    <div v-for="day in days" :key="day.weekday" class="row" style="padding: 10px 0; border-top: 1px solid var(--border)">
      <label class="shrink" style="width: 120px"><input v-model="day.open" type="checkbox" /> {{ WEEKDAYS[day.weekday] }}</label>
      <div v-if="day.open" style="flex: 1 1 300px">
        <div v-for="(interval, i) in day.intervals" :key="i" class="row" style="margin-bottom: 6px">
          <input v-model="interval.start" type="time" />
          <span class="shrink muted">até</span>
          <input v-model="interval.end" type="time" />
          <button v-if="day.intervals.length > 1" type="button" class="btn small secondary shrink"
                  @click="day.intervals.splice(i, 1)">Remover</button>
        </div>
        <button type="button" class="link-btn" @click="day.intervals.push({ start: '11:00', end: '14:00' })">+ outro turno</button>
      </div>
      <span v-else class="muted">Fechado</span>
    </div>
    <button class="btn" style="margin-top: 16px" @click="saveHours">Salvar horários</button>
  </div>

  <!-- Entrega e retirada -->
  <form class="card" @submit.prevent="saveSettings">
    <h3>Entrega e retirada</h3>
    <div class="row" style="margin-bottom: 14px">
      <label class="shrink"><input v-model="settings.pickup_enabled" type="checkbox" /> Cliente retira no local</label>
      <label class="shrink"><input v-model="settings.delivery_enabled" type="checkbox" /> Faço entrega</label>
    </div>
    <div class="row">
      <div v-if="settings.delivery_enabled" class="field">
        <label>Taxa de entrega (R$)</label>
        <input v-model="settings.delivery_fee" type="number" min="0" step="0.01" />
      </div>
      <div class="field">
        <label>Pedido mínimo (R$) <small>0 = sem mínimo</small></label>
        <input v-model="settings.min_order" type="number" min="0" step="0.01" />
      </div>
    </div>
    <div v-if="settings.delivery_enabled" class="field">
      <label>Onde você entrega <small>(aparece para o cliente)</small></label>
      <input v-model="settings.delivery_area" placeholder="Ex.: Centro, Vila Nova e Jardim América" />
    </div>
    <button class="btn">Salvar</button>
  </form>

  <!-- Taxa por bairro -->
  <div v-if="settings.delivery_enabled" class="card">
    <h3>Taxa de entrega por bairro</h3>
    <p class="muted">
      Cadastre os bairros que você atende e a taxa de cada um. O cliente escolhe o bairro na hora do pedido
      e só consegue pedir entrega para os bairros da lista. Com a lista vazia, vale a taxa única acima.
    </p>
    <div v-for="(z, i) in zones" :key="i" class="row zone-row">
      <div class="field" style="flex: 2 1 200px; margin: 0">
        <label v-if="i === 0">Bairro</label>
        <input v-model="z.name" maxlength="60" placeholder="Ex.: Centro" />
      </div>
      <div class="field" style="flex: 1 1 110px; margin: 0">
        <label v-if="i === 0">Taxa (R$)</label>
        <input v-model="z.fee" type="number" min="0" step="0.01" />
      </div>
      <button type="button" class="btn small secondary shrink" title="Remover" @click="zones.splice(i, 1)">Remover</button>
    </div>
    <div class="row" style="margin-top: 12px">
      <button type="button" class="btn secondary shrink" @click="zones.push({ name: '', fee: zones.at(-1)?.fee ?? 0 })">+ Adicionar bairro</button>
      <button type="button" class="btn shrink" @click="saveZones">Salvar bairros</button>
    </div>
    <label v-if="zones.length && biz.business.delivery_other !== undefined" class="other-zone">
      <input v-model="settings.delivery_other" type="checkbox" @change="saveSettings" />
      <span>
        Aceitar pedido de bairro fora da lista
        <small class="muted">O cliente digita o bairro e o pedido chega com a taxa "a combinar". Você informa o valor pelo WhatsApp.</small>
      </span>
    </label>
  </div>
</template>

<style scoped>
.zone-row { align-items: flex-end; padding: 6px 0; }
.other-zone { display: flex; gap: 10px; align-items: flex-start; margin-top: 16px; padding-top: 14px; border-top: 1px solid var(--border); cursor: pointer; }
.other-zone input { margin-top: 3px; }
.other-zone small { display: block; margin-top: 2px; }
</style>
