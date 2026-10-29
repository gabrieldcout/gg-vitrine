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

// Mesmo estilo da logo da G&G Soluções: "GG" forte em prata e o resto
// do nome espaçado, mais leve, em azul.
const [brandFirst, ...brandRest] = APP_NAME.split(' ')
</script>

<template>
  <RouterLink :to="to" class="logo" :class="[`logo--${size}`, { 'logo--mark-only': !showText }]" :aria-label="APP_NAME">
    <img src="/logo-mark.png" alt="" class="logo-mark" />
    <span v-if="showText" class="logo-text">
      <span class="logo-first">{{ brandFirst }}</span>
      <span class="logo-rest">{{ brandRest.join(' ') }}</span>
    </span>
  </RouterLink>
</template>

<style scoped>
.logo {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  color: var(--text);
  text-decoration: none;
  line-height: 1;
}
.logo:hover { color: var(--text); }

.logo-mark {
  display: block;
  flex-shrink: 0;
  width: auto;
  object-fit: contain;
  filter: drop-shadow(0 0 10px rgba(59, 130, 246, 0.35));
  transition: transform 0.2s ease, filter 0.2s ease;
}
.logo:hover .logo-mark {
  transform: translateY(-1px);
  filter: drop-shadow(0 0 14px rgba(59, 130, 246, 0.55));
}

.logo-text {
  display: inline-flex;
  align-items: baseline;
  gap: 0.4em;
  white-space: nowrap;
  text-transform: uppercase;
}
.logo-first {
  font-weight: 800;
  letter-spacing: 0.02em;
  background: linear-gradient(180deg, #ffffff 0%, #d7dce4 55%, #9aa3b2 100%);
  -webkit-background-clip: text; background-clip: text; color: transparent;
}
.logo-rest {
  font-weight: 500;
  letter-spacing: 0.2em;
  background: linear-gradient(180deg, #93c5fd 0%, #3b82f6 100%);
  -webkit-background-clip: text; background-clip: text; color: transparent;
}

/* Tamanhos contextuais (a marca é larga, ~1,9 : 1) */
.logo--sm .logo-mark { height: 26px; }
.logo--sm .logo-text { font-size: 0.92rem; }
.logo--sm { gap: 8px; }

.logo--md .logo-mark { height: 38px; }
.logo--md .logo-text { font-size: 1.08rem; }

.logo--lg .logo-mark { height: 54px; }
.logo--lg .logo-text { font-size: 1.45rem; }
.logo--lg { gap: 14px; }

.logo--mark-only { gap: 0; }

@media (prefers-reduced-motion: reduce) {
  .logo-mark { transition: none; }
  .logo:hover .logo-mark { transform: none; }
}
</style>
