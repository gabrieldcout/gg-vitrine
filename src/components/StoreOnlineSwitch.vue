<script setup>
import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'
import { useBusiness } from '@/lib/business'
import { ask } from '@/lib/confirm'
import { toast } from '@/lib/toast'

// Botão "Online / Offline" do cardápio, no topo do painel (qualquer tela).
// Offline = pedidos pausados (accepting_orders), mesmo dentro do horário.
defineProps({ compact: { type: Boolean, default: false } })

const biz = useBusiness()
const busy = ref(false)
const online = computed(() => biz.business.accepting_orders !== false)

async function toggle() {
  const value = !online.value
  if (!value && !await ask('Ficar offline?\nSua vitrine para de aceitar pedidos até você ficar online de novo.', { confirmLabel: 'Ficar offline', danger: true })) return
  busy.value = true
  const { error } = await supabase.from('businesses').update({ accepting_orders: value }).eq('id', biz.business.id)
  busy.value = false
  if (error) { toast(error.message, 'error'); return }
  biz.business.accepting_orders = value
  toast(value ? 'Você está online: a vitrine aceita pedidos.' : 'Você está offline: pedidos pausados.')
}
</script>

<template>
  <button type="button" class="online-switch" :class="{ on: online, compact }" :disabled="busy" role="switch" :aria-checked="online"
          :title="online ? 'Recebendo pedidos. Toque pra ficar offline.' : 'Pedidos pausados. Toque pra ficar online.'" @click="toggle">
    <span class="online-track"><span class="online-knob" /></span>
    <span class="online-label">{{ online ? 'Online' : 'Offline' }}</span>
  </button>
</template>

<style scoped>
.online-switch {
  display: inline-flex; align-items: center; gap: 8px; padding: 6px 12px 6px 6px; border-radius: 999px; cursor: pointer;
  font: inherit; font-size: 0.85rem; font-weight: 700; color: #fca5a5;
  background: rgba(248, 113, 113, 0.12); border: 1px solid rgba(248, 113, 113, 0.45); transition: background 0.2s, border-color 0.2s, color 0.2s;
}
.online-switch.on { color: #86efac; background: rgba(74, 222, 128, 0.12); border-color: rgba(74, 222, 128, 0.45); }
.online-switch:disabled { opacity: 0.6; cursor: progress; }
.online-track { position: relative; width: 34px; height: 20px; border-radius: 999px; background: rgba(248, 113, 113, 0.35); flex-shrink: 0; transition: background 0.2s; }
.on .online-track { background: #22c55e; }
.online-knob { position: absolute; top: 2px; left: 2px; width: 16px; height: 16px; border-radius: 50%; background: #fff; transition: transform 0.2s; }
.on .online-knob { transform: translateX(14px); }
.online-switch.compact { padding: 4px 10px 4px 4px; font-size: 0.78rem; gap: 6px; }
.compact .online-track { width: 30px; height: 18px; }
.compact .online-knob { width: 14px; height: 14px; }
.compact.on .online-knob { transform: translateX(12px); }
@media (prefers-reduced-motion: reduce) { .online-knob, .online-track, .online-switch { transition: none; } }
</style>
