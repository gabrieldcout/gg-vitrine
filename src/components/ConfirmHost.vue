<script setup>
import { watch, nextTick, ref } from 'vue'
import { dialog, answer } from '@/lib/confirm'
import Icon from '@/components/Icon.vue'

const okBtn = ref(null)
watch(() => dialog.open, async (open) => { if (open) { await nextTick(); okBtn.value?.focus() } })
</script>

<template>
  <Transition name="ask">
    <div v-if="dialog.open" class="ask-backdrop" @click.self="answer(false)" @keydown.esc="answer(false)">
      <div class="ask-card" role="alertdialog" aria-modal="true" :aria-label="dialog.text">
        <div class="ask-ico" :class="{ danger: dialog.danger }"><Icon :name="dialog.danger ? 'ban' : 'check'" /></div>
        <p class="ask-text">{{ dialog.text }}</p>
        <div class="ask-actions">
          <button type="button" class="btn secondary" @click="answer(false)">Voltar</button>
          <button ref="okBtn" type="button" class="btn" :class="{ 'ask-danger': dialog.danger }" @click="answer(true)">
            {{ dialog.confirmLabel }}
          </button>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.ask-backdrop {
  position: fixed; inset: 0; z-index: 120; padding: 16px;
  display: grid; place-items: center;
  background: rgba(2, 6, 14, 0.72); backdrop-filter: blur(4px);
}
.ask-card {
  width: min(400px, 100%); padding: 22px; border-radius: 18px; text-align: center;
  background: var(--surface, #0b1730); border: 1px solid var(--border, rgba(255, 255, 255, 0.1));
  box-shadow: 0 24px 60px rgba(0, 0, 0, 0.5);
}
.ask-ico {
  width: 48px; height: 48px; margin: 0 auto 12px; border-radius: 50%;
  display: grid; place-items: center;
  background: rgba(59, 130, 246, 0.15); color: #93c5fd;
}
.ask-ico.danger { background: rgba(248, 113, 113, 0.15); color: #fca5a5; }
.ask-ico :deep(svg) { width: 22px; height: 22px; }
.ask-text { margin: 0 0 18px; color: var(--text, #fff); font-size: 1rem; line-height: 1.5; white-space: pre-line; }
.ask-actions { display: flex; gap: 10px; justify-content: center; flex-wrap: wrap; }
.ask-actions .btn { flex: 1 1 140px; justify-content: center; }
.ask-danger { background: #dc2626 !important; border-color: #dc2626 !important; color: #fff !important; box-shadow: none !important; }
.ask-enter-active, .ask-leave-active { transition: opacity 0.18s ease; }
.ask-enter-from, .ask-leave-to { opacity: 0; }
</style>
