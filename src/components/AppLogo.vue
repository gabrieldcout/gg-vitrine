<script setup>
import { APP_NAME } from '@/config/brand'

defineProps({
  to: { type: String, default: '/' },
  size: {
    type: String,
    default: 'md',
    validator: (v) => ['sm', 'md', 'lg'].includes(v),
  },
  showText: { type: Boolean, default: true },
})
</script>

<template>
  <RouterLink :to="to" class="logo" :class="[`logo--${size}`, { 'logo--mark-only': !showText }]">
    <img src="/logo.png" :alt="APP_NAME" class="logo-mark" />
    <span v-if="showText" class="gradient-text logo-text">{{ APP_NAME }}</span>
  </RouterLink>
</template>

<style scoped>
.logo {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  font-weight: 800;
  color: var(--text);
  text-decoration: none;
  line-height: 1;
}
.logo:hover { color: var(--text); }

.logo-mark {
  object-fit: contain;
  display: block;
  flex-shrink: 0;
  padding: 4px;
  background: #fff;
  border-radius: 10px;
  box-shadow: 0 4px 14px rgba(0, 0, 0, 0.3), 0 0 0 1px rgba(255, 255, 255, 0.1);
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}
.logo:hover .logo-mark {
  transform: translateY(-1px);
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.35), 0 0 0 1px rgba(255, 255, 255, 0.15);
}

.logo-text {
  font-size: 1.15rem;
  letter-spacing: -0.01em;
  white-space: nowrap;
}

/* Tamanhos contextuais */
.logo--sm .logo-mark { width: 28px; height: 28px; padding: 3px; border-radius: 8px; }
.logo--sm .logo-text { font-size: 0.98rem; }
.logo--sm { gap: 8px; }

.logo--md .logo-mark { width: 40px; height: 40px; }
.logo--md .logo-text { font-size: 1.15rem; }

.logo--lg .logo-mark { width: 56px; height: 56px; padding: 6px; border-radius: 14px; }
.logo--lg .logo-text { font-size: 1.5rem; }
.logo--lg { gap: 14px; }

.logo--mark-only { gap: 0; }

@media (prefers-reduced-motion: reduce) {
  .logo-mark { transition: none; }
  .logo:hover .logo-mark { transform: none; }
}
</style>
