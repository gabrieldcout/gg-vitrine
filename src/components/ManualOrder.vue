<script setup>
// Venda avulsa do cardápio (balcão, telefone): grava um pedido igual aos da
// vitrine, com os produtos do cardápio, e ele aparece em Pedidos e no Financeiro.
import { ref, computed, onMounted } from 'vue'
import { supabase, unwrap } from '@/lib/supabase'
import { useBusiness } from '@/lib/business'
import { money } from '@/lib/format'
import Icon from '@/components/Icon.vue'

const emit = defineEmits(['close', 'saved'])
const biz = useBusiness()

const categories = ref([])
const zones = ref([])
const qty = ref({})   // { itemId: quantidade }
const search = ref('')
const error = ref('')
const saving = ref(false)

const PAYMENTS = ['PIX', 'Dinheiro', 'Cartão na entrega/retirada']
const pad = (n) => String(n).padStart(2, '0')
const now = new Date()
const form = ref({
  name: '', phone: '', mode: 'retirada', address: '', zone: '', fee: '',
  payment: 'PIX', notes: '', done: true,
  at: `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`,
})

onMounted(async () => {
  const bid = biz.business.id
  try {
    const [cats, items, zs] = await Promise.all([
      supabase.from('menu_categories').select('id, name').eq('business_id', bid).order('sort_order').order('name'),
      supabase.from('menu_items').select('id, name, price, category_id, available').eq('business_id', bid).order('sort_order').order('name'),
      supabase.from('delivery_zones').select('id, name, fee').eq('business_id', bid).order('sort_order'),
    ])
    const list = unwrap(items)
    categories.value = unwrap(cats).map((c) => ({ ...c, items: list.filter((i) => i.category_id === c.id) }))
    zones.value = zs.data ?? []
  } catch (e) {
    error.value = e.message
  }
})

const allItems = computed(() => categories.value.flatMap((c) => c.items))
const visibleCats = computed(() => {
  const q = search.value.trim().toLowerCase()
  return categories.value
    .map((c) => ({ ...c, items: q ? c.items.filter((i) => i.name.toLowerCase().includes(q)) : c.items }))
    .filter((c) => c.items.length)
})
const lines = computed(() => allItems.value.filter((i) => qty.value[i.id])
  .map((i) => ({ ...i, qty: qty.value[i.id], total: qty.value[i.id] * Number(i.price) })))
const subtotal = computed(() => lines.value.reduce((s, l) => s + l.total, 0))
const zone = computed(() => zones.value.find((z) => z.id === form.value.zone))
const fee = computed(() => {
  if (form.value.mode !== 'entrega') return 0
  if (form.value.fee !== '') return Number(form.value.fee) || 0
  return Number(zone.value?.fee ?? 0)
})
const total = computed(() => subtotal.value + fee.value)

function add(i, d) {
  const n = Math.max(0, Math.min(99, (qty.value[i.id] ?? 0) + d))
  const next = { ...qty.value }
  if (n) next[i.id] = n
  else delete next[i.id]
  qty.value = next
}

async function save() {
  error.value = ''
  if (!lines.value.length) { error.value = 'Escolha pelo menos um produto.'; return }
  const f = form.value
  if (f.mode === 'entrega' && !f.address.trim()) { error.value = 'Informe o endereço da entrega.'; return }
  saving.value = true
  const bid = biz.business.id
  const address = f.mode === 'entrega'
    ? [f.address.trim(), zone.value?.name].filter(Boolean).join(' - ')
    : null
  try {
    // Próximo número de pedido; se outro pedido entrar junto, tenta de novo.
    let order
    for (let attempt = 0; attempt < 3 && !order; attempt++) {
      const last = unwrap(await supabase.from('orders').select('number').eq('business_id', bid)
        .order('number', { ascending: false }).limit(1))
      const { data, error: err } = await supabase.from('orders').insert({
        business_id: bid, number: (last[0]?.number ?? 0) + 1,
        customer_name: f.name.trim() || 'Venda no balcão', phone: f.phone.trim(),
        mode: f.mode, address, payment: f.payment, notes: f.notes.trim() || null,
        subtotal: subtotal.value, delivery_fee: fee.value, discount: 0, total: total.value,
        status: f.done ? 'entregue' : 'novo', created_at: new Date(f.at).toISOString(),
      }).select('id, number').single()
      if (err && !/duplicate|unique/i.test(err.message)) throw new Error(err.message)
      order = data
    }
    if (!order) throw new Error('Não deu pra numerar o pedido. Tente de novo.')
    unwrap(await supabase.from('order_items').insert(lines.value.map((l) => ({
      order_id: order.id, business_id: bid, item_id: l.id, name: l.name,
      unit_price: Number(l.price), qty: l.qty, total: l.total,
    }))))
    emit('saved', order)
  } catch (e) {
    error.value = e.message
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="sheet-backdrop" @click.self="emit('close')">
    <form class="sheet mo" @submit.prevent="save">
      <div class="spread mo-head">
        <h2>Venda avulsa</h2>
        <button type="button" class="btn small secondary" @click="emit('close')">Fechar</button>
      </div>
      <p class="muted mo-lede">Pedido feito no balcão ou por telefone. Entra em Pedidos e no Financeiro.</p>

      <input v-model="search" class="mo-search" placeholder="Buscar produto..." />
      <div class="mo-menu">
        <p v-if="!categories.length && !error" class="muted">Carregando cardápio...</p>
        <div v-for="c in visibleCats" :key="c.id" class="mo-cat">
          <small class="mo-cat-name">{{ c.name }}</small>
          <div v-for="i in c.items" :key="i.id" class="mo-item" :class="{ on: qty[i.id], off: !i.available }">
            <span class="mo-item-name">{{ i.name }}<small v-if="!i.available"> · esgotado</small></span>
            <span class="mo-item-price">{{ money(i.price) }}</span>
            <div class="mo-step">
              <button type="button" aria-label="Diminuir" :disabled="!qty[i.id]" @click="add(i, -1)"><Icon name="minus" /></button>
              <span>{{ qty[i.id] ?? 0 }}</span>
              <button type="button" aria-label="Aumentar" @click="add(i, 1)"><Icon name="plus" /></button>
            </div>
          </div>
        </div>
      </div>

      <div class="tabs mo-tabs">
        <button type="button" :class="{ on: form.mode === 'retirada' }" @click="form.mode = 'retirada'">Retirada / balcão</button>
        <button type="button" :class="{ on: form.mode === 'entrega' }" @click="form.mode = 'entrega'">Entrega</button>
      </div>

      <div class="row">
        <div class="field"><label>Cliente <small>(opcional)</small></label><input v-model="form.name" placeholder="Venda no balcão" /></div>
        <div class="field"><label>WhatsApp <small>(opcional)</small></label><input v-model="form.phone" type="tel" /></div>
      </div>
      <template v-if="form.mode === 'entrega'">
        <div class="field"><label>Endereço</label><input v-model="form.address" placeholder="Rua, número e referência" /></div>
        <div class="row">
          <div v-if="zones.length" class="field">
            <label>Bairro</label>
            <select v-model="form.zone">
              <option value="">Outro / sem bairro</option>
              <option v-for="z in zones" :key="z.id" :value="z.id">{{ z.name }} · {{ money(z.fee) }}</option>
            </select>
          </div>
          <div class="field">
            <label>Taxa de entrega (R$)</label>
            <input v-model="form.fee" type="number" min="0" step="0.01" :placeholder="zone ? String(zone.fee) : '0'" />
          </div>
        </div>
      </template>
      <div class="row">
        <div class="field">
          <label>Pagamento</label>
          <select v-model="form.payment"><option v-for="p in PAYMENTS" :key="p">{{ p }}</option></select>
        </div>
        <div class="field"><label>Data e hora</label><input v-model="form.at" type="datetime-local" required /></div>
      </div>
      <div class="field"><label>Observações <small>(opcional)</small></label><input v-model="form.notes" /></div>
      <label class="mo-done"><input v-model="form.done" type="checkbox" /> Já foi entregue / pago (não precisa preparar)</label>

      <div class="mo-total">
        <div class="spread"><span class="muted">Subtotal</span><span>{{ money(subtotal) }}</span></div>
        <div v-if="form.mode === 'entrega'" class="spread"><span class="muted">Entrega</span><span>{{ money(fee) }}</span></div>
        <div class="spread mo-sum"><span>Total</span><span class="gradient-text">{{ money(total) }}</span></div>
      </div>
      <div v-if="error" class="error">{{ error }}</div>
      <button class="btn large block" :disabled="saving || !lines.length">
        <Icon name="check" style="width: 18px; height: 18px" />{{ saving ? 'Salvando...' : `Lançar venda de ${money(total)}` }}
      </button>
    </form>
  </div>
</template>

<style scoped>
.mo-head h2 { margin: 0; font-size: 1.25rem; }
.mo-lede { margin: 4px 0 12px; font-size: 0.88rem; }
.mo-search { width: 100%; margin-bottom: 8px; }
.mo-menu { max-height: 34vh; overflow-y: auto; border: 1px solid var(--border); border-radius: 14px; padding: 6px 10px; margin-bottom: 14px; }
.mo-cat-name { display: block; margin: 8px 0 2px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.08em; font-size: 0.7rem; font-weight: 700; }
.mo-item { display: flex; align-items: center; gap: 10px; padding: 7px 0; border-top: 1px solid var(--border); }
.mo-item.on .mo-item-name { color: var(--brand-ink); font-weight: 700; }
.mo-item.off { opacity: 0.6; }
.mo-item-name { flex: 1; min-width: 0; font-size: 0.92rem; }
.mo-item-price { font-size: 0.85rem; color: var(--muted); white-space: nowrap; }
.mo-step { display: inline-flex; align-items: center; gap: 4px; }
.mo-step button { width: 28px; height: 28px; border-radius: 50%; border: 1px solid var(--border); background: var(--surface); color: var(--text); display: grid; place-items: center; cursor: pointer; }
.mo-step button:disabled { opacity: 0.35; cursor: default; }
.mo-step button svg { width: 14px; height: 14px; }
.mo-step span { min-width: 20px; text-align: center; font-weight: 700; }
.mo-tabs { margin-bottom: 12px; }
.mo-done { display: flex; gap: 8px; align-items: center; font-size: 0.9rem; margin: 4px 0 12px; }
.mo-total { display: grid; gap: 4px; padding: 12px 0; border-top: 1px solid var(--border); margin-bottom: 10px; }
.mo-sum { font-size: 1.2rem; font-weight: 800; }
</style>
