<script setup>
import { computed } from 'vue'
import { ORDER_SOURCES } from '@/lib/order-source'

const props = defineProps({ source: { type: String, default: 'site' } })
const s = computed(() => ORDER_SOURCES[props.source] ?? ORDER_SOURCES.site)
</script>

<template>
  <span class="source-badge" :style="{ background: s.bg, color: s.fg }">{{ s.label }}</span>
</template>

<style scoped>
.source-badge {
  display: inline-flex; align-items: center;
  padding: 2px 9px; border-radius: 999px;
  font-size: 0.72rem; font-weight: 800; letter-spacing: 0.01em; line-height: 1.5;
  white-space: nowrap; vertical-align: middle;
}
</style>
