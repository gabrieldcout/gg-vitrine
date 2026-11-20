<script setup>
import { ref, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'
import { useBusiness } from '@/lib/business'
import { APP_NAME } from '@/config/brand'
import { referralLink } from '@/lib/referral'
import { formatDate } from '@/lib/format'
import { toast } from '@/lib/toast'
import Icon from '@/components/Icon.vue'

const biz = useBusiness()
const data = ref(null)
const error = ref('')

onMounted(async () => {
  const { data: d, error: err } = await supabase.rpc('my_referrals')
  if (err) { error.value = err.message; return }
  data.value = d
})

const slug = computed(() => data.value?.slug || biz.business.slug)
const link = computed(() => referralLink(location.origin, slug.value))
const linkShort = computed(() => link.value.replace(/^https?:\/\//, ''))
const items = computed(() => data.value?.items ?? [])
const paid = computed(() => items.value.filter((i) => i.paid).length)
const available = computed(() => items.value.filter((i) => i.paid && !i.used).length)
const used = computed(() => items.value.filter((i) => i.used).length)

const shareText = computed(() =>
  `Oi! Uso a ${APP_NAME} na ${biz.business.name} pra ` +
  (biz.business.kind === 'cardapio' ? 'receber pedidos' : biz.business.kind === 'fila' ? 'organizar a fila' : 'receber agendamentos') +
  ` pelo link, e tá valendo muito a pena. 🚀\n\nSe cadastrar pelo meu link você ganha *17 dias grátis* pra testar (10 a mais que o normal):\n${link.value}`)
const whatsappShare = computed(() => `https://wa.me/?text=${encodeURIComponent(shareText.value)}`)

async function copy() {
  try { await navigator.clipboard.writeText(link.value); toast('Link copiado!') } catch { toast('Não deu pra copiar.', 'error') }
}

function statusOf(i) {
  if (i.used) return { label: 'Desconto usado', tone: 'muted' }
  if (i.paid) return { label: 'Assinou: 30% liberado', tone: 'green' }
  if (i.trial) return { label: 'Testando', tone: 'blue' }
  return { label: 'Cadastrou', tone: 'yellow' }
}
</script>

<template>
  <div class="page-header">
    <p class="eyebrow">Indique e ganhe</p>
    <h1>Ganhe 30% de desconto indicando a {{ APP_NAME }}</h1>
    <p class="muted">Indique pra outros negócios. Cada um que assinar te dá <strong>30% de desconto numa mensalidade</strong>, e quem você indicar ganha <strong>+10 dias</strong> no teste grátis.</p>
  </div>
  <div v-if="error" class="error">{{ error }}</div>

  <div class="card ref-link-card">
    <small class="muted">Seu link de indicação</small>
    <div class="ref-link">{{ linkShort }}</div>
    <div class="ref-actions">
      <a class="btn" :href="whatsappShare" target="_blank" rel="noopener">
        <Icon name="whatsapp" style="width: 16px; height: 16px" />Mandar no WhatsApp
      </a>
      <button type="button" class="btn secondary" @click="copy">Copiar link</button>
    </div>
    <small class="muted">O "Feito com {{ APP_NAME }}" no rodapé da sua vitrine também leva esse link: quem chegar por ali e assinar conta como indicação sua.</small>
  </div>

  <div class="ref-tiles">
    <div class="card ref-tile"><span class="ref-num">{{ items.length }}</span><small class="muted">Indicados</small></div>
    <div class="card ref-tile"><span class="ref-num">{{ paid }}</span><small class="muted">Assinaram</small></div>
    <div class="card ref-tile highlight"><span class="ref-num">{{ available }}</span><small class="muted">{{ available === 1 ? 'Desconto de 30% a usar' : 'Descontos de 30% a usar' }}</small></div>
    <div class="card ref-tile"><span class="ref-num">{{ used }}</span><small class="muted">Já usados</small></div>
  </div>

  <div class="card">
    <h3 style="margin-top: 0">Como funciona</h3>
    <ol class="ref-steps">
      <li>Mande seu link pra quem tem negócio (barbearia, salão, lanchonete, estúdio...).</li>
      <li>A pessoa se cadastra pelo link e ganha <strong>17 dias grátis</strong> pra testar.</li>
      <li>Quando ela pagar a 1ª mensalidade, você ganha <strong>30% de desconto</strong> na sua próxima mensalidade.</li>
      <li>Indicou mais de um? Cada indicação vale um mês com 30%, usados um por mês.</li>
    </ol>
  </div>

  <div class="card">
    <h3 style="margin-top: 0">Suas indicações</h3>
    <p v-if="data && !items.length" class="muted">Ninguém se cadastrou pelo seu link ainda. Que tal mandar agora pra 3 conhecidos?</p>
    <ul v-else class="ref-list">
      <li v-for="(i, k) in items" :key="k">
        <div><strong>{{ i.name }}</strong><small class="muted">Cadastrou em {{ formatDate(i.created_at) }}</small></div>
        <span class="ref-status" :class="`tone-${statusOf(i).tone}`">{{ statusOf(i).label }}</span>
      </li>
    </ul>
  </div>
</template>

<style scoped>
.ref-link-card { display: grid; gap: 10px; }
.ref-link { font-size: 1.1rem; font-weight: 700; word-break: break-all; }
.ref-actions { display: flex; flex-wrap: wrap; gap: 8px; }
.ref-tiles { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin: 16px 0; }
.ref-tile { display: grid; gap: 2px; text-align: center; margin: 0; }
.ref-tile.highlight { border: 1px solid var(--success, #16a34a); }
.ref-num { font-size: 1.8rem; font-weight: 800; }
.ref-steps { margin: 0; padding-left: 20px; display: grid; gap: 6px; }
.ref-list { list-style: none; margin: 0; padding: 0; }
.ref-list li { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 10px 0; border-top: 1px solid var(--border, rgba(127,127,127,.2)); }
.ref-list li:first-child { border-top: 0; }
.ref-list li div { display: grid; }
.ref-status { font-size: 0.82rem; font-weight: 600; padding: 4px 10px; border-radius: 999px; white-space: nowrap; background: rgba(127,127,127,.12); }
.ref-status.tone-green { background: rgba(22,163,74,.15); color: #16a34a; }
.ref-status.tone-blue { background: rgba(37,99,235,.15); color: #3b82f6; }
.ref-status.tone-yellow { background: rgba(234,179,8,.15); color: #ca8a04; }
@media (max-width: 640px) { .ref-tiles { grid-template-columns: repeat(2, 1fr); } }
</style>
