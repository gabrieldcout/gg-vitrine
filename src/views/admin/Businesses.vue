<script setup>
import { ref, computed, onMounted } from 'vue'
import { supabase, unwrap } from '@/lib/supabase'
import { money, formatDate, todayISO, BUSINESS_STATUS, SUBSCRIPTION_STATUS } from '@/lib/format'
import { ask } from '@/lib/confirm'
import Icon from '@/components/Icon.vue'
import { toast } from '@/lib/toast'
import { waLink } from '@/lib/whatsapp'
import { APP_NAME, APP_DOMAIN, CATEGORIES, MENU_CATEGORIES, kindForCategory } from '@/config/brand'
import { slugify } from '@/lib/format'

const rows = ref([])
const plans = ref([])
const filter = ref('')
const search = ref('')
const error = ref('')
const editing = ref(null)   // empresa aberta no formulário de assinatura
const payment = ref(null)   // empresa aberta no formulário de pagamento

const STATUS_BADGE = { pending: 'yellow', approved: 'green', rejected: 'red', blocked: 'red' }

const visible = computed(() => {
  const q = search.value.trim().toLowerCase()
  return rows.value.filter((r) =>
    (!filter.value || r.status === filter.value) &&
    (!q || `${r.name} ${r.slug} ${r.owner_email}`.toLowerCase().includes(q)))
})

async function load() {
  try {
    rows.value = unwrap(await supabase.rpc('admin_list_businesses'))
    plans.value = unwrap(await supabase.from('plans').select('*').order('sort_order'))
  } catch (e) {
    error.value = e.message
  }
}
onMounted(load)

async function call(fn, args) {
  error.value = ''
  const { error: err } = await supabase.rpc(fn, args)
  if (err) error.value = err.message
  await load()
  return !err
}

// E-mail de confirmação que não chegou: confirma por aqui. Só aparece depois
// da migration 0030 (antes disso a coluna não vem).
const unconfirmed = computed(() => rows.value.filter((r) => 'email_confirmed_at' in r && !r.email_confirmed_at))
async function confirmEmail(b) {
  if (!await ask(`Confirmar o e-mail ${b.owner_email} de ${b.name}?
Depois disso o cliente já entra com o e-mail e a senha que cadastrou${b.plan_id ? '' : ', e os 7 dias grátis começam'}.`,
    { confirmLabel: 'Confirmar e-mail' })) return
  const win = b.phone ? window.open('', '_blank') : null   // abre antes do await (celular bloqueia depois)
  if (await call('admin_confirm_email', { p_owner: b.owner_id })) {
    toast(`E-mail de ${b.name} confirmado.`)
    sendWelcome(b, win)
  } else win?.close()
}

// ---- Nova vitrine pra um cliente, sem ele se cadastrar (função admin-create-client) ----
const KIND_LABELS = { agenda: 'Agenda (agendamento)', cardapio: 'Cardápio (pedidos)', fila: 'Fila (por ordem de chegada)' }
const blankClient = () => ({ name: '', slug: '', category: CATEGORIES[0], kind: 'agenda', phone: '', email: '', password: '' })
const newClient = ref(null)       // formulário aberto
const createdClient = ref(null)   // acesso gerado, pra enviar ao cliente
const creating = ref(false)
const slugTouched = ref(false)
function openNewClient() { newClient.value = blankClient(); createdClient.value = null; slugTouched.value = false }
function onClientName() { if (!slugTouched.value) newClient.value.slug = slugify(newClient.value.name) }
function onClientCategory() { newClient.value.kind = kindForCategory(newClient.value.category) }
async function createClient() {
  const c = newClient.value
  error.value = ''
  if (!c.name.trim() || !c.email.trim()) { error.value = 'Preencha o nome do estabelecimento e o e-mail do cliente.'; return }
  creating.value = true
  const { data, error: err } = await supabase.functions.invoke('admin-create-client', { body: { ...c, slug: slugify(c.slug || c.name) } })
  creating.value = false
  // Erro da função vem no corpo da resposta.
  let msg = data?.error
  if (!msg && err) {
    try { msg = (await err.context?.json())?.error } catch { /* sem corpo */ }
    msg ||= /Failed to send|not found|404/i.test(err.message) ? 'A função admin-create-client ainda não foi publicada no Supabase.' : err.message
  }
  if (msg) { error.value = msg; return }
  createdClient.value = { ...data, name: c.name.trim(), phone: c.phone, kind: c.kind }
  newClient.value = null
  toast(`Vitrine de ${c.name.trim()} criada e liberada por 7 dias.`)
  load()
}
function accessText(c) {
  return `Olá! Aqui é da ${APP_NAME} 👋\n\n` +
    `Sua vitrine da *${c.name}* está pronta, com *7 dias grátis*! 🎉\n\n` +
    `🔗 Seu link: ${APP_DOMAIN}/${c.slug}\n\n` +
    `Pra entrar no seu painel: ${APP_DOMAIN}/entrar\n` +
    `*E-mail:* ${c.email}\n*Senha:* ${c.password}\n\n` +
    'Guarde essa senha. Qualquer dúvida, é só chamar!'
}
const accessLink = (c) => (c.phone ? waLink(c.phone, accessText(c)) : null)
async function copyAccess(c) {
  try { await navigator.clipboard.writeText(accessText(c).replace(/\*/g, '')); toast('Acesso copiado.') } catch { toast('Não deu pra copiar.', 'error') }
}

// Sem plano (ou só escolheu e não pagou): libera o teste de 7 dias (0035).
const canTrial = (b) => b.status === 'approved' && (!b.plan_id || ['pending_payment', 'canceled'].includes(b.subscription_status))
async function startTrial(b) {
  if (!await ask(`Liberar 7 dias grátis pra ${b.name}?\nA vitrine entra no ar na hora e o WhatsApp do cliente abre com o aviso pronto.`,
    { confirmLabel: 'Liberar 7 dias' })) return
  const win = b.phone ? window.open('', '_blank') : null
  if (await call('admin_start_trial', { p_owner: b.owner_id })) {
    toast(`${b.name} liberada por 7 dias.`)
    sendWelcome(b, win)
  } else {
    win?.close()
    if (/admin_start_trial/.test(error.value)) error.value = 'Rode a migration 0035 no Supabase pra liberar o teste por aqui.'
  }
}

// Aviso pro dono no WhatsApp, com a mensagem pronta (é só tocar em enviar).
function welcomeText(b) {
  return `Olá! Aqui é da ${APP_NAME} 👋\n\n` +
    `Sua vitrine da *${b.name}* já está liberada, com *7 dias grátis* pra você testar tudo! 🎉\n\n` +
    `🔗 Seu link: ${APP_DOMAIN}/${b.slug}\n\n` +
    `Pra começar, entre no painel em ${APP_DOMAIN}/entrar (com o e-mail e a senha do cadastro) e preencha:\n` +
    (b.kind === 'cardapio'
      ? '1. Seus *produtos*, com foto e preço\n2. O *horário* de funcionamento\n3. *Entrega*, bairros e taxas\n4. Sua *logo* e o endereço\n\n'
      : '1. Seus *serviços*, com preço e duração\n2. Os *horários* de atendimento\n3. Quem atende (*profissionais*)\n4. Sua *logo* e o endereço\n\n') +
    'Se preferir, me manda essas informações por aqui que eu monto tudo pra você. Qualquer dúvida, é só chamar!'
}
function welcomeLink(b) { return b.phone ? waLink(b.phone, welcomeText(b)) : null }
function sendWelcome(b, win) {
  const link = welcomeLink(b)
  if (!link) return
  if (win) win.location.href = link
  else window.open(link, '_blank')
}

function setStatus(b, status) {
  let reason = null
  if (status === 'rejected' || status === 'blocked') {
    reason = prompt(status === 'rejected' ? 'Motivo da recusa (aparece para a empresa):' : 'Mensagem de bloqueio (aparece para a empresa):')
    if (reason === null) return
  }
  call('admin_set_business_status', { p_business: b.id, p_status: status, p_reason: reason })
}

// ---- Plano e preço negociado ----
function openEdit(b) {
  const plan = b.plan_id ?? 'solo'
  editing.value = {
    business: b, plan_id: plan,
    custom_price: b.custom_price, discount_amount: b.discount_amount ?? 0,
    discount_mode: b.discount_until ? 'months' : 'forever',
    discount_months: 3, discount_until: b.discount_until, discount_note: b.discount_note ?? '',
  }
}

const preview = computed(() => {
  const e = editing.value
  if (!e) return null
  const base = plans.value.find((p) => p.id === e.plan_id)?.base_price ?? 0
  const price = e.custom_price === '' || e.custom_price == null ? Number(base) : Number(e.custom_price)
  return { base, final: Math.max(0, price - Number(e.discount_amount || 0)) }
})

function discountUntil(e) {
  if (!Number(e.discount_amount) || e.discount_mode === 'forever') return null
  if (e.discount_mode === 'date') return e.discount_until
  const d = new Date(todayISO() + 'T12:00:00')
  d.setMonth(d.getMonth() + Number(e.discount_months))
  return d.toISOString().slice(0, 10)
}

async function saveEdit() {
  const e = editing.value
  const ok = await call('admin_update_subscription', {
    p_owner: e.business.owner_id, p_plan: e.plan_id,
    p_custom_price: e.custom_price === '' || e.custom_price == null ? null : Number(e.custom_price),
    p_discount_amount: Number(e.discount_amount || 0),
    p_discount_until: discountUntil(e),
    p_discount_note: e.discount_note || null,
  })
  if (ok) {
    // Se o dono paga pelo Asaas, atualiza o valor lá também.
    supabase.functions.invoke('asaas-checkout', { body: { action: 'sync-price', owner_id: e.business.owner_id } }).catch(() => {})
    editing.value = null
  }
}

// ---- Pagamento manual ----
function openPayment(b) {
  payment.value = { business: b, amount: b.monthly_price ?? 0, months: 1, method: 'pix', note: '' }
}

async function savePayment() {
  const p = payment.value
  const ok = await call('admin_register_payment', {
    p_owner: p.business.owner_id, p_amount: Number(p.amount), p_months: Number(p.months),
    p_method: p.method, p_note: p.note || null,
  })
  if (ok) payment.value = null
}
</script>

<template>
  <div class="page-header spread">
    <h1>Empresas</h1>
    <button class="btn" @click="openNewClient"><Icon name="plus" style="width: 16px; height: 16px" />Nova vitrine pra cliente</button>
  </div>
  <div v-if="error" class="error">{{ error }}</div>

  <!-- Nova vitrine pra cliente -->
  <form v-if="newClient" class="card new-client" @submit.prevent="createClient">
    <div class="spread"><h3 style="margin: 0">Nova vitrine pra cliente</h3>
      <button type="button" class="btn small secondary" @click="newClient = null">Fechar</button></div>
    <p class="muted">O cliente não precisa se cadastrar: a conta já sai confirmada, a vitrine aprovada e com 7 dias grátis. Depois você manda o acesso pelo WhatsApp.</p>
    <div class="row">
      <div class="field" style="flex: 2 1 220px"><label>Nome do estabelecimento</label><input v-model="newClient.name" required @input="onClientName" /></div>
      <div class="field" style="flex: 1 1 200px"><label>Link</label><input v-model="newClient.slug" @input="slugTouched = true" />
        <small class="muted">{{ APP_DOMAIN }}/<strong>{{ slugify(newClient.slug || newClient.name) || 'link' }}</strong></small></div>
    </div>
    <div class="row">
      <div class="field"><label>Categoria</label>
        <select v-model="newClient.category" @change="onClientCategory">
          <optgroup label="Agenda"><option v-for="c in CATEGORIES" :key="c">{{ c }}</option></optgroup>
          <optgroup label="Cardápio"><option v-for="c in MENU_CATEGORIES" :key="c">{{ c }}</option></optgroup>
        </select></div>
      <div class="field"><label>Tipo da vitrine</label>
        <select v-model="newClient.kind"><option v-for="(label, k) in KIND_LABELS" :key="k" :value="k">{{ label }}</option></select></div>
    </div>
    <div class="row">
      <div class="field"><label>WhatsApp do cliente</label><input v-model="newClient.phone" type="tel" placeholder="(21) 99999-9999" /></div>
      <div class="field"><label>E-mail do cliente (vira o login)</label><input v-model="newClient.email" type="email" required /></div>
      <div class="field"><label>Senha <small>(vazio = gera uma)</small></label><input v-model="newClient.password" placeholder="Ex.: Vitrine4821" /></div>
    </div>
    <button class="btn" :disabled="creating">{{ creating ? 'Criando...' : 'Criar vitrine e liberar 7 dias' }}</button>
  </form>

  <!-- Acesso criado -->
  <div v-if="createdClient" class="card created-client">
    <div class="spread"><h3 style="margin: 0">✅ Vitrine de {{ createdClient.name }} criada</h3>
      <button type="button" class="btn small secondary" @click="createdClient = null">Fechar</button></div>
    <div class="created-grid">
      <span class="muted">Link</span><a :href="`/${createdClient.slug}`" target="_blank">{{ APP_DOMAIN }}/{{ createdClient.slug }}</a>
      <span class="muted">E-mail</span><strong>{{ createdClient.email }}</strong>
      <span class="muted">Senha</span><strong>{{ createdClient.password }}</strong>
    </div>
    <p class="muted">Anote a senha: ela só aparece agora. Monte a vitrine entrando com esse acesso, ou me peça o SQL.</p>
    <div class="chips">
      <a v-if="accessLink(createdClient)" class="btn" :href="accessLink(createdClient)" target="_blank" rel="noopener">
        <Icon name="whatsapp" style="width: 16px; height: 16px" />Mandar acesso no WhatsApp
      </a>
      <button type="button" class="btn secondary" @click="copyAccess(createdClient)">Copiar acesso</button>
    </div>
  </div>

  <!-- Formulário: plano e preço -->
  <div v-if="editing" class="card">
    <div class="spread"><h3>Plano e preço · {{ editing.business.name }}</h3>
      <button class="btn small secondary" @click="editing = null">Fechar</button></div>
    <div class="row">
      <div class="field">
        <label>Plano</label>
        <select v-model="editing.plan_id">
          <option v-for="p in plans" :key="p.id" :value="p.id">{{ p.name }} ({{ money(p.base_price) }})</option>
        </select>
      </div>
      <div class="field">
        <label>Preço personalizado <small>(vazio = tabela)</small></label>
        <input v-model="editing.custom_price" type="number" min="0" step="0.01" :placeholder="String(preview.base)" />
      </div>
      <div class="field">
        <label>Desconto (R$)</label>
        <input v-model="editing.discount_amount" type="number" min="0" step="0.01" />
      </div>
    </div>
    <div v-if="Number(editing.discount_amount) > 0" class="row">
      <div class="field">
        <label>Duração do desconto</label>
        <select v-model="editing.discount_mode">
          <option value="forever">Permanente</option>
          <option value="months">Por alguns meses</option>
          <option value="date">Até uma data</option>
        </select>
      </div>
      <div v-if="editing.discount_mode === 'months'" class="field">
        <label>Meses</label><input v-model="editing.discount_months" type="number" min="1" />
      </div>
      <div v-if="editing.discount_mode === 'date'" class="field">
        <label>Até</label><input v-model="editing.discount_until" type="date" />
      </div>
      <div class="field"><label>Observação</label><input v-model="editing.discount_note" placeholder="Ex.: migração da concorrência" /></div>
    </div>
    <p class="notice">
      Tabela: {{ money(preview.base) }} → <strong>valor contratado: {{ money(preview.final) }}/mês</strong>
      <span v-if="discountUntil(editing)"> até {{ formatDate(discountUntil(editing) + 'T12:00:00') }}, depois {{ money(editing.custom_price || preview.base) }}</span>
    </p>
    <button class="btn" @click="saveEdit">Salvar</button>
  </div>

  <!-- Formulário: pagamento manual -->
  <div v-if="payment" class="card">
    <div class="spread"><h3>Registrar pagamento · {{ payment.business.name }}</h3>
      <button class="btn small secondary" @click="payment = null">Fechar</button></div>
    <div class="row">
      <div class="field"><label>Valor (R$)</label><input v-model="payment.amount" type="number" min="0" step="0.01" /></div>
      <div class="field"><label>Meses pagos</label><input v-model="payment.months" type="number" min="1" /></div>
      <div class="field">
        <label>Forma</label>
        <select v-model="payment.method">
          <option value="pix">PIX</option><option value="boleto">Boleto</option>
          <option value="cartao">Cartão</option><option value="dinheiro">Dinheiro</option>
        </select>
      </div>
      <div class="field"><label>Observação</label><input v-model="payment.note" /></div>
    </div>
    <p class="muted">A assinatura fica ativa e o vencimento avança os meses informados.</p>
    <button class="btn" @click="savePayment">Registrar</button>
  </div>

  <div v-if="unconfirmed.length" class="action-needed" style="margin: 0 0 16px">
    <Icon name="mail" />
    <span>
      <strong>{{ unconfirmed.length === 1 ? '1 cadastro esperando' : `${unconfirmed.length} cadastros esperando` }} confirmação de e-mail</strong>
      Se o código não chegou pro cliente, toque em "Confirmar e-mail" na empresa: {{ unconfirmed.map((r) => r.name).join(', ') }}.
    </span>
  </div>

  <div class="card">
    <div class="row" style="margin-bottom: 12px">
      <input v-model="search" placeholder="Buscar por nome, link ou e-mail" />
      <select v-model="filter" style="max-width: 200px">
        <option value="">Todos os status</option>
        <option v-for="(label, key) in BUSINESS_STATUS" :key="key" :value="key">{{ label }}</option>
      </select>
    </div>
    <div class="table-wrap">
      <table>
        <thead>
          <tr><th>Empresa</th><th>Status</th><th>Plano</th><th>Mensalidade</th><th>Uso</th><th>Ações</th></tr>
        </thead>
        <tbody>
          <tr v-for="b in visible" :key="b.id">
            <td>
              <strong>{{ b.name }}</strong><br />
              <small class="muted">/{{ b.slug }} · {{ b.category }}<br />{{ b.owner_email }} · {{ b.phone }}</small>
              <br v-if="'email_confirmed_at' in b && !b.email_confirmed_at" />
              <span v-if="'email_confirmed_at' in b && !b.email_confirmed_at" class="badge yellow">E-mail não confirmado</span>
            </td>
            <td>
              <span :class="['badge', STATUS_BADGE[b.status]]">{{ BUSINESS_STATUS[b.status] }}</span>
              <br /><small class="muted">desde {{ formatDate(b.created_at) }}</small>
            </td>
            <td>
              <template v-if="b.plan_id">
                {{ b.plan_name }}<br />
                <small class="muted">{{ SUBSCRIPTION_STATUS[b.subscription_status] }}</small>
                <br v-if="b.current_period_end" /><small v-if="b.current_period_end" class="muted">até {{ formatDate(b.current_period_end) }}</small>
              </template>
              <span v-else class="badge yellow">Sem plano</span>
            </td>
            <td>
              <template v-if="b.plan_id">
                <strong>{{ money(b.monthly_price) }}</strong>
                <br v-if="Number(b.monthly_price) !== Number(b.base_price)" />
                <small v-if="Number(b.monthly_price) !== Number(b.base_price)" class="muted" style="text-decoration: line-through">{{ money(b.base_price) }}</small>
                <br v-if="b.discount_note" /><small v-if="b.discount_note" class="muted">{{ b.discount_note }}</small>
              </template>
            </td>
            <td>
              <small>{{ b.professionals_count }} prof.<br />{{ b.customers_count }} clientes<br /></small>
              <small>{{ b.activity_count }} {{ b.kind === 'cardapio' ? 'pedidos' : b.kind === 'fila' ? 'na fila' : 'agendamentos' }}</small>
            </td>
            <td>
              <div class="chips">
                <button v-if="'email_confirmed_at' in b && !b.email_confirmed_at" class="btn small" @click="confirmEmail(b)">Confirmar e-mail</button>
                <button v-else-if="canTrial(b)" class="btn small" @click="startTrial(b)">Liberar 7 dias</button>
                <a v-if="welcomeLink(b)" class="btn small secondary" :href="welcomeLink(b)" target="_blank" rel="noopener" title="Abre o WhatsApp do cliente com o aviso de vitrine liberada">
                  <Icon name="whatsapp" style="width: 14px; height: 14px" />Avisar
                </a>
                <template v-if="b.status === 'pending'">
                  <button class="btn small" @click="setStatus(b, 'approved')">Aprovar</button>
                  <button class="btn small secondary" @click="setStatus(b, 'rejected')">Recusar</button>
                </template>
                <button v-if="b.status === 'approved'" class="btn small secondary" @click="setStatus(b, 'blocked')">Bloquear</button>
                <button v-if="b.status === 'blocked' || b.status === 'rejected'" class="btn small secondary" @click="setStatus(b, 'approved')">Reativar</button>
                <button v-if="b.status === 'approved'" class="btn small secondary" @click="openEdit(b)">Plano/preço</button>
                <button v-if="b.plan_id" class="btn small secondary" @click="openPayment(b)">Pagamento</button>
                <a class="btn small secondary" :href="`/${b.slug}`" target="_blank">Ver página</a>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
      <p v-if="!visible.length" class="muted">Nenhuma empresa encontrada.</p>
    </div>
  </div>
</template>

<style scoped>
.new-client .row { margin-bottom: 4px; }
.created-client { border-left: 3px solid var(--success); }
.created-grid { display: grid; grid-template-columns: auto 1fr; gap: 6px 14px; margin: 12px 0; font-size: 0.95rem; }
</style>
