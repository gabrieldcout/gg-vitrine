<script setup>
// Oferta do serviço "montamos sua vitrine": abre o WhatsApp do suporte com a
// mensagem pronta. O valor é combinado por lá (ou fixo, se SETUP_PRICE tiver valor).
import { computed } from 'vue'
import { useBusiness } from '@/lib/business'
import { SUPPORT_WHATSAPP, SETUP_PRICE, APP_NAME, APP_DOMAIN } from '@/config/brand'
import { waLink } from '@/lib/whatsapp'
import { money } from '@/lib/format'
import Icon from '@/components/Icon.vue'

defineProps({ compact: { type: Boolean, default: false } })

const biz = useBusiness()
const isMenu = computed(() => biz?.business?.kind === 'cardapio')
const what = computed(() => (isMenu.value
  ? 'cardápio com fotos e preços, horário, bairros e taxas de entrega'
  : biz?.business ? 'serviços, preços, horários e equipe' : 'serviços ou cardápio, preços e horários'))
const link = computed(() => SUPPORT_WHATSAPP && waLink(SUPPORT_WHATSAPP,
  `Olá! Quero que o ${APP_NAME} monte minha vitrine` +
  `${biz?.business ? `: ${biz.business.name} (${APP_DOMAIN}/${biz.business.slug})` : ''}.`))
</script>

<template>
  <div v-if="link" class="setup-offer" :class="{ compact }">
    <span class="setup-offer-icon"><Icon name="sparkles" /></span>
    <div class="setup-offer-text">
      <strong>Sem tempo? A gente monta pra você.</strong>
      <small>
        Mande as fotos e os preços pelo WhatsApp e deixamos {{ what }} prontos.
        <template v-if="SETUP_PRICE">Taxa única de {{ money(SETUP_PRICE) }}.</template>
        <template v-else>Valor combinado pelo WhatsApp.</template>
      </small>
    </div>
    <a class="btn small setup-offer-btn" :href="link" target="_blank" rel="noopener">
      <Icon name="whatsapp" />Quero que montem pra mim
    </a>
  </div>
</template>

<style scoped>
.setup-offer {
  display: flex; align-items: center; gap: 14px; flex-wrap: wrap;
  margin: 18px 0; padding: 16px 18px;
  border-radius: var(--radius, 16px);
  border: 1px dashed rgba(37, 211, 102, 0.45);
  background: radial-gradient(ellipse 320px 140px at 0% 0%, rgba(37, 211, 102, 0.12), transparent 70%), var(--surface);
}
.setup-offer-icon {
  width: 40px; height: 40px; border-radius: 12px; flex-shrink: 0;
  display: grid; place-items: center;
  background: rgba(37, 211, 102, 0.15); color: #4ade80;
}
.setup-offer-icon :deep(svg) { width: 20px; height: 20px; }
.setup-offer-text { flex: 1 1 220px; min-width: 0; }
.setup-offer-text strong { display: block; font-size: 0.98rem; }
.setup-offer-text small { display: block; color: var(--muted); font-size: 0.85rem; margin-top: 3px; line-height: 1.4; }
.setup-offer-btn { background: #25d366; color: #fff; border: none; white-space: nowrap; }
.setup-offer-btn:hover { background: #1ebe5b; }
.setup-offer-btn :deep(svg) { width: 16px; height: 16px; }
.setup-offer.compact { margin: 12px 0; padding: 12px 14px; }
@media (max-width: 520px) { .setup-offer-btn { width: 100%; justify-content: center; } }
</style>
