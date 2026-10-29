<script setup>
import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import { useBusiness } from '@/lib/business'
import { formatDate, todayISO, zonedToUtc } from '@/lib/format'
import Icon from '@/components/Icon.vue'
import PromoBanner from '@/components/public/PromoBanner.vue'

const biz = useBusiness()
const tz = computed(() => biz.business.timezone)
const b = biz.business
const form = ref({
  promo_active: b.promo_active ?? false,
  promo_title: b.promo_title ?? '',
  promo_text: b.promo_text ?? '',
  promo_until: b.promo_until ?? '',
})
const error = ref('')
const msg = ref('')
const busy = ref(false)

const expired = computed(() => form.value.promo_until && form.value.promo_until < todayISO(tz.value))
const preview = computed(() => ({
  title: form.value.promo_title.trim() || 'Título da promoção',
  text: form.value.promo_text.trim(),
  until: form.value.promo_until || null,
}))

async function save(active = form.value.promo_active) {
  error.value = msg.value = ''
  if (active && !form.value.promo_title.trim()) { error.value = 'Escreva o título da promoção.'; return }
  busy.value = true
  const patch = {
    promo_active: active,
    promo_title: form.value.promo_title.trim() || null,
    promo_text: form.value.promo_text.trim() || null,
    promo_until: form.value.promo_until || null,
  }
  const { error: err } = await supabase.from('businesses').update(patch).eq('id', b.id)
  busy.value = false
  if (err) { error.value = err.message; return }
  Object.assign(b, patch)
  form.value.promo_active = active
  if (!active) msg.value = 'Promoção salva, mas desligada: não aparece na vitrine.'
  else if (expired.value) msg.value = 'Salva, mas a data já passou: ajuste o "válida até" pra ela aparecer.'
  else msg.value = 'Promoção no ar na sua vitrine.'
}

const untilLabel = computed(() =>
  form.value.promo_until ? formatDate(zonedToUtc(form.value.promo_until, '12:00', tz.value), tz.value) : '')
</script>

<template>
  <div class="page-header">
    <div>
      <p class="eyebrow">Divulgar</p>
      <h1>Promoção</h1>
      <p class="muted">Escreva sua promoção e ela aparece em destaque na sua vitrine, logo antes do agendamento.</p>
    </div>
  </div>

  <div v-if="error" class="alert alert-danger">
    <span class="alert-icon"><Icon name="ban" /></span><span>{{ error }}</span>
  </div>
  <div v-if="msg" class="alert alert-success">
    <span class="alert-icon"><Icon name="check" /></span><span>{{ msg }}</span>
  </div>

  <div class="promo-status card" :class="{ on: form.promo_active && !expired }">
    <div>
      <strong>{{ form.promo_active ? (expired ? 'Promoção vencida' : 'Promoção no ar') : 'Promoção desligada' }}</strong>
      <small class="muted">
        {{ form.promo_active
          ? (expired ? 'A data de validade já passou, então ela não aparece mais.' : untilLabel ? `Aparece na vitrine até ${untilLabel}.` : 'Aparece na vitrine até você desligar.')
          : 'Não aparece na vitrine.' }}
      </small>
    </div>
    <button type="button" class="btn small" :class="{ secondary: form.promo_active }" :disabled="busy"
            @click="save(!form.promo_active)">
      <Icon :name="form.promo_active ? 'ban' : 'check'" />
      {{ form.promo_active ? 'Desligar' : 'Ligar' }}
    </button>
  </div>

  <form class="card promo-form" @submit.prevent="save()">
    <div class="ff">
      <input id="promo-title" v-model="form.promo_title" maxlength="80" placeholder=" " />
      <label for="promo-title">Título (ex.: Novembro com 20% de desconto)</label>
    </div>
    <div class="field">
      <label for="promo-text">Detalhes da promoção <small>(opcional)</small></label>
      <textarea id="promo-text" v-model="form.promo_text" rows="4" maxlength="600"
                placeholder="Ex.: tatuagens até 10 cm por R$ 150. Válido de segunda a quinta. Chama no WhatsApp!" />
      <small class="muted">{{ form.promo_text.length }}/600</small>
    </div>
    <div class="ff promo-until">
      <input id="promo-until" v-model="form.promo_until" type="date" placeholder=" " />
      <label for="promo-until">Válida até (opcional)</label>
    </div>
    <div class="promo-actions">
      <button v-if="form.promo_until" type="button" class="btn secondary" @click="form.promo_until = ''">Sem data de fim</button>
      <button class="btn" :disabled="busy"><Icon name="check" />Salvar</button>
    </div>
  </form>

  <section class="promo-preview">
    <p class="eyebrow">Como aparece na vitrine</p>
    <PromoBanner :promo="preview" :timezone="tz" />
  </section>
</template>

<style scoped>
.promo-status {
  display: flex; align-items: center; justify-content: space-between; gap: 14px;
  margin-bottom: 16px; border-left: 3px solid var(--border);
}
.promo-status.on { border-left-color: var(--success); }
.promo-status strong { display: block; }
.promo-status .btn :deep(svg) { width: 15px; height: 15px; }
.promo-form { display: grid; gap: 4px; }
.promo-form textarea { width: 100%; }
.promo-until { max-width: 260px; }
.promo-actions { display: flex; gap: 8px; justify-content: flex-end; flex-wrap: wrap; }
.promo-actions .btn :deep(svg) { width: 15px; height: 15px; }
.promo-preview { margin-top: 24px; }
@media (max-width: 640px) {
  .promo-status { flex-direction: column; align-items: stretch; }
  .promo-until { max-width: none; }
}
</style>
