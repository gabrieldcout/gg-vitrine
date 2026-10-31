<script setup>
import { computed } from 'vue'
import { useBusiness } from '@/lib/business'
import { formatTime } from '@/lib/format'
import { autoPrintOn, lastCheck, lastPrinted, setAutoPrint, queuePrint } from '@/lib/auto-print'
import Icon from '@/components/Icon.vue'
import { toast } from '@/lib/toast'

const biz = useBusiness()
const tz = computed(() => biz.business.timezone)

async function toggle() {
  const on = !autoPrintOn.value
  await setAutoPrint(on, biz.business)
  toast(on ? 'Impressão automática ligada neste computador.' : 'Impressão automática desligada neste computador.')
}

// Comanda de exemplo: se aparecer a janela "Imprimir", o Chrome não está
// aberto pelo atalho com --kiosk-printing.
function testPrint() {
  const now = new Date().toISOString()
  queuePrint({
    number: 'TESTE', created_at: now, customer_name: 'Cliente de teste', phone: '(00) 00000-0000',
    mode: 'retirada', subtotal: 25, delivery_fee: 0, discount: 0, total: 25, payment: 'Pix',
    order_items: [{ qty: 1, name: 'Produto de teste', total: 25 }],
    notes: 'Comanda de teste: se saiu sem perguntar nada, está tudo certo.',
  }, biz.business)
}

const isChrome = /Chrome\//.test(navigator.userAgent) && !/Edg\//.test(navigator.userAgent)
</script>

<template>
  <div class="page-header">
    <div>
      <p class="eyebrow">Loja</p>
      <h1>Impressão</h1>
      <p class="muted">Configure o computador do balcão pra imprimir a comanda sozinho quando chegar pedido novo pelo site. Sem pedido, não imprime nada.</p>
    </div>
  </div>

  <div class="pr-status card" :class="{ on: autoPrintOn }">
    <div class="pr-ico"><Icon name="printer" /></div>
    <div class="pr-status-text">
      <strong>{{ autoPrintOn ? 'Impressão automática ligada neste computador' : 'Impressão automática desligada neste computador' }}</strong>
      <small class="muted">
        <template v-if="autoPrintOn">
          Confere pedido novo a cada 15 segundos, com qualquer tela do painel aberta.
          <template v-if="lastCheck"> Última conferência às {{ formatTime(lastCheck, tz) }}.</template>
          <template v-if="lastPrinted"> Último impresso: pedido #{{ lastPrinted.number }} às {{ formatTime(lastPrinted.at, tz) }}.</template>
        </template>
        <template v-else>Ligue só no computador que tem a impressora. No celular, deixe desligado.</template>
      </small>
    </div>
    <button type="button" class="btn" :class="{ secondary: autoPrintOn }" @click="toggle">
      <Icon :name="autoPrintOn ? 'ban' : 'check'" />{{ autoPrintOn ? 'Desligar' : 'Ligar' }}
    </button>
  </div>

  <section class="card pr-section">
    <h2>1. Imprimir sem a janela "Imprimir?"</h2>
    <p class="muted">Por segurança, o navegador sempre pergunta antes de imprimir. Pra comanda sair direto:</p>
    <ol>
      <li>Deixe a impressora da comanda como <strong>impressora padrão</strong> do Windows (Configurações › Impressoras).</li>
      <li>Clique com o botão direito no atalho do <strong>Google Chrome</strong> na área de trabalho › <strong>Propriedades</strong>.</li>
      <li>No campo <strong>Destino</strong>, depois das aspas, coloque um espaço e <code>--kiosk-printing</code>. Fica assim:<br>
        <code class="pr-code">"C:\Program Files\Google\Chrome\Application\chrome.exe" --kiosk-printing</code></li>
      <li>Clique em <strong>OK</strong>. Feche o Chrome <strong>por completo</strong> (veja o item 2 abaixo) e abra de novo <strong>por esse atalho</strong>.</li>
    </ol>
  </section>

  <section class="card pr-section">
    <h2>2. Ainda pergunta antes de imprimir?</h2>
    <ul>
      <li><strong>O Chrome não fechou de verdade.</strong> Ele fica rodando escondido perto do relógio. Clique na setinha ˄ ao lado do relógio do Windows; se tiver o ícone do Chrome, botão direito › <strong>Sair</strong>. Pra não acontecer mais: no Chrome, Configurações › Sistema › desligue <em>"Continuar executando apps em segundo plano"</em>.</li>
      <li><strong>Abriu por outro atalho</strong> (barra de tarefas, menu Iniciar). Só o atalho que você editou tem a opção. Fixe esse atalho na barra de tarefas e use sempre ele.</li>
      <li><strong>Pra conferir:</strong> digite <code>chrome://version</code> na barra de endereço. Na linha <em>Linha de comando</em> tem que aparecer <code>--kiosk-printing</code>.</li>
      <li v-if="!isChrome"><strong>Você não está no Google Chrome agora.</strong> O passo a passo acima é pro Chrome.</li>
    </ul>
  </section>

  <section class="card pr-section">
    <h2>3. Teste</h2>
    <p class="muted">Imprime uma comanda de exemplo. Se saiu direto na impressora, está pronto. Se apareceu a janela de impressão, volte no item 2.</p>
    <button type="button" class="btn secondary" @click="testPrint"><Icon name="printer" />Imprimir comanda de teste</button>
  </section>

  <section class="card pr-section">
    <h2>No dia a dia</h2>
    <ul>
      <li>Deixe o painel aberto no Chrome do balcão (qualquer tela do painel serve). Pode usar outros programas por cima, mas <strong>não minimize nem feche</strong> a janela do painel.</li>
      <li>Se o computador ficou desligado, os pedidos dos últimos 10 minutos saem assim que o painel abrir. Pedido já impresso não sai de novo.</li>
      <li>Venda lançada à mão no painel não sai sozinha; use o botão <strong>Imprimir</strong> do pedido.</li>
    </ul>
  </section>
</template>

<style scoped>
.pr-status { display: flex; align-items: center; gap: 14px; margin-bottom: 16px; border-left: 3px solid var(--border); }
.pr-status.on { border-left-color: var(--success); }
.pr-ico { width: 44px; height: 44px; flex-shrink: 0; border-radius: 12px; display: grid; place-items: center; background: var(--surface); color: var(--silver); }
.pr-status.on .pr-ico { color: var(--success); }
.pr-ico :deep(svg) { width: 22px; height: 22px; }
.pr-status-text { flex: 1; min-width: 0; }
.pr-status-text strong { display: block; }
.pr-status-text small { display: block; margin-top: 2px; }
.pr-status .btn :deep(svg), .pr-section .btn :deep(svg) { width: 15px; height: 15px; }
.pr-section { margin-bottom: 14px; }
.pr-section h2 { font-size: 1.02rem; margin: 0 0 8px; }
.pr-section p { margin: 0 0 10px; }
.pr-section ol, .pr-section ul { margin: 0; padding-left: 20px; display: grid; gap: 8px; font-size: 0.92rem; }
.pr-section code { background: rgba(255, 255, 255, 0.08); padding: 1px 5px; border-radius: 5px; word-break: break-all; }
.pr-code { display: inline-block; margin-top: 6px; font-size: 0.8rem; }
@media (max-width: 640px) {
  .pr-status { flex-direction: column; align-items: stretch; }
}
</style>
