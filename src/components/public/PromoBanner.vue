<script setup>
import { computed } from 'vue'
import { formatDate, zonedToUtc } from '@/lib/format'
import Icon from '@/components/Icon.vue'

// Promoção em destaque na vitrine ({ title, text, until }).
const props = defineProps({
  promo: { type: Object, required: true },
  timezone: { type: String, default: 'America/Sao_Paulo' },
})
const until = computed(() => props.promo.until
  ? formatDate(zonedToUtc(props.promo.until, '12:00', props.timezone), props.timezone, { day: '2-digit', month: '2-digit' })
  : '')
</script>

<template>
  <div class="promo-banner">
    <div class="promo-ico"><Icon name="tag" /></div>
    <div class="promo-body">
      <span class="promo-kicker">Promoção{{ until ? ` · até ${until}` : '' }}</span>
      <strong class="promo-title">{{ promo.title }}</strong>
      <p v-if="promo.text" class="promo-text">{{ promo.text }}</p>
    </div>
  </div>
</template>

<style scoped>
.promo-banner {
  display: flex; gap: 14px; align-items: flex-start;
  padding: 18px; border-radius: 18px;
  background:
    radial-gradient(ellipse 320px 160px at 0% 0%, var(--brand-soft), transparent 70%),
    var(--surface);
  border: 1px solid var(--brand);
  box-shadow: 0 0 32px var(--brand-soft);
}
.promo-ico {
  width: 44px; height: 44px; border-radius: 12px; flex-shrink: 0;
  display: grid; place-items: center;
  background: linear-gradient(140deg, var(--brand), var(--brand-strong));
  color: var(--brand-contrast);
}
.promo-ico :deep(svg) { width: 22px; height: 22px; }
.promo-body { min-width: 0; }
.promo-kicker {
  display: block; font-size: 0.72rem; font-weight: 700; letter-spacing: 0.08em;
  text-transform: uppercase; color: var(--brand-ink);
}
.promo-title { display: block; font-size: 1.12rem; margin-top: 2px; }
.promo-text { margin: 6px 0 0; color: var(--muted); white-space: pre-line; overflow-wrap: anywhere; }
</style>
