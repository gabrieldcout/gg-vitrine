<script setup>
// Tour do painel na landing: o visitante clica nas abas e vê uma prévia
// de cada tela, com dados de exemplo (nada aqui vem do banco).
import { ref, computed } from 'vue'
import { APP_DOMAIN } from '@/config/brand'
import Icon from '@/components/Icon.vue'

const tabs = [
  {
    id: 'agenda',
    icon: 'calendar',
    label: 'Agenda',
    title: 'Seu dia inteiro numa tela',
    text: 'Cada agendamento feito pelo link cai aqui na hora. Você vê quem vem, que horas, qual serviço e quanto está previsto no dia.',
  },
  {
    id: 'servicos',
    icon: 'scissors',
    label: 'Serviços',
    title: 'Cadastre o que você oferece',
    text: 'Nome, preço e duração de cada serviço. O template do seu segmento já traz os mais comuns, é só ajustar.',
  },
  {
    id: 'horarios',
    icon: 'clock',
    label: 'Horários',
    title: 'Defina quando você atende',
    text: 'Dias e horários por profissional, com intervalo de almoço. O cliente só enxerga os horários realmente livres.',
  },
  {
    id: 'clientes',
    icon: 'contact',
    label: 'Clientes',
    title: 'Ficha de cada cliente, sozinha',
    text: 'Quem agenda vira cliente cadastrado. Histórico de visitas, total gasto e contato a um toque.',
  },
  {
    id: 'financeiro',
    icon: 'chart',
    label: 'Financeiro',
    title: 'Saiba quanto entrou no mês',
    text: 'Faturamento, ticket médio, faltas e os serviços que mais vendem. Dá pra lançar venda de balcão também.',
  },
  {
    id: 'divulgar',
    icon: 'qr',
    label: 'Divulgar',
    title: 'Seu link e QR Code prontos',
    text: 'Copie o link, mande no WhatsApp, coloque na bio do Instagram ou imprima o cartaz com QR Code pro balcão.',
  },
]

const active = ref('agenda')
const current = computed(() => tabs.find((t) => t.id === active.value))

const agendaStats = [
  { label: 'Agendamentos', value: '6' },
  { label: 'Confirmados', value: '4' },
  { label: 'Previsto no dia', value: 'R$ 540', accent: true },
]
const appointments = [
  { time: '09:00', name: 'Mariana Souza', service: 'Corte feminino', status: 'Concluído', tone: 'green' },
  { time: '10:30', name: 'Carla Mendes', service: 'Coloração', status: 'Confirmado', tone: 'blue' },
  { time: '14:00', name: 'Juliana Reis', service: 'Escova', status: 'Confirmado', tone: 'blue' },
  { time: '16:00', name: 'Patrícia Lima', service: 'Corte + escova', status: 'Pendente', tone: 'yellow' },
]

const services = [
  { name: 'Corte feminino', dur: '45 min', price: 'R$ 80' },
  { name: 'Escova', dur: '30 min', price: 'R$ 60' },
  { name: 'Coloração', dur: '90 min', price: 'R$ 180' },
  { name: 'Hidratação', dur: '40 min', price: 'R$ 70' },
]

const hours = [
  { day: 'Seg', off: true },
  { day: 'Ter', ranges: ['09:00 – 12:00', '14:00 – 19:00'] },
  { day: 'Qua', ranges: ['09:00 – 12:00', '14:00 – 19:00'] },
  { day: 'Qui', ranges: ['09:00 – 12:00', '14:00 – 19:00'] },
  { day: 'Sex', ranges: ['09:00 – 12:00', '14:00 – 20:00'] },
  { day: 'Sáb', ranges: ['09:00 – 16:00'] },
]

const customers = [
  { name: 'Mariana Souza', visits: '8 visitas', spent: 'R$ 720' },
  { name: 'Carla Mendes', visits: '5 visitas', spent: 'R$ 610' },
  { name: 'Juliana Reis', visits: '3 visitas', spent: 'R$ 240' },
  { name: 'Patrícia Lima', visits: '1 visita', spent: 'R$ 140' },
]

const finStats = [
  { label: 'Faturamento', value: 'R$ 6.480', accent: true },
  { label: 'Ticket médio', value: 'R$ 96' },
  { label: 'Faltas', value: '4%' },
]
const finBars = [38, 52, 44, 70, 61, 88, 100, 57, 73, 66, 92, 80]
const topServices = [
  { name: 'Coloração', pct: 100, value: 'R$ 2.340' },
  { name: 'Corte feminino', pct: 72, value: 'R$ 1.680' },
  { name: 'Escova', pct: 48, value: 'R$ 1.120' },
]

// Desenho que lembra um QR Code (decorativo, não é um código real).
const qrCells = [
  1, 1, 1, 0, 1, 0, 1, 1, 1,
  1, 0, 1, 0, 0, 1, 1, 0, 1,
  1, 1, 1, 0, 1, 0, 1, 1, 1,
  0, 0, 0, 1, 0, 1, 0, 0, 0,
  1, 0, 1, 1, 0, 0, 1, 0, 1,
  0, 1, 0, 0, 1, 1, 0, 1, 0,
  1, 1, 1, 0, 0, 1, 0, 1, 1,
  1, 0, 1, 0, 1, 0, 1, 0, 0,
  1, 1, 1, 0, 1, 1, 0, 1, 1,
]
</script>

<template>
  <section id="painel" class="container section">
    <div class="section-head" data-reveal>
      <p class="eyebrow">Por dentro do painel</p>
      <h2 class="section-title">Veja como é <span class="gradient-text">antes de criar a conta</span></h2>
      <p class="section-sub">Clique nas abas pra conhecer as telas que você vai usar no dia a dia. Tudo funciona no celular e no computador.</p>
    </div>

    <div class="tour" data-reveal>
      <div class="tour-tabs" role="tablist" aria-label="Telas do painel">
        <button
          v-for="t in tabs"
          :id="`tour-tab-${t.id}`"
          :key="t.id"
          type="button"
          role="tab"
          class="tour-tab"
          :class="{ on: active === t.id }"
          :aria-selected="active === t.id"
          aria-controls="tour-panel"
          @click="active = t.id"
        >
          <Icon :name="t.icon" />
          <span>{{ t.label }}</span>
        </button>
      </div>

      <div id="tour-panel" class="tour-window" role="tabpanel" :aria-labelledby="`tour-tab-${active}`">
        <div class="tour-bar" aria-hidden="true">
          <span class="url-dot" /><span class="url-dot" /><span class="url-dot" />
          <code>{{ APP_DOMAIN }}/painel</code>
        </div>

        <div class="tour-body">
          <div class="tour-copy">
            <div class="tour-icon"><Icon :name="current.icon" /></div>
            <h3 class="tour-title">{{ current.title }}</h3>
            <p class="muted tour-text">{{ current.text }}</p>
          </div>

          <transition name="tour-fade" mode="out-in">
            <div :key="active" class="tour-screen" aria-hidden="true">
              <!-- Agenda -->
              <template v-if="active === 'agenda'">
                <div class="scr-head">
                  <div>
                    <small class="scr-eyebrow">Agenda</small>
                    <strong>Sexta, 12 de junho</strong>
                  </div>
                  <span class="scr-btn"><Icon name="plus" />Novo agendamento</span>
                </div>
                <div class="scr-stats">
                  <div v-for="s in agendaStats" :key="s.label" class="scr-stat" :class="{ accent: s.accent }">
                    <small>{{ s.label }}</small>
                    <strong :class="{ 'gradient-text': s.accent }">{{ s.value }}</strong>
                  </div>
                </div>
                <ul class="scr-list">
                  <li v-for="a in appointments" :key="a.time" class="scr-row">
                    <strong class="scr-time">{{ a.time }}</strong>
                    <div class="scr-main">
                      <strong>{{ a.name }}</strong>
                      <small>{{ a.service }}</small>
                    </div>
                    <span class="badge" :class="a.tone">{{ a.status }}</span>
                  </li>
                </ul>
              </template>

              <!-- Serviços -->
              <template v-else-if="active === 'servicos'">
                <div class="scr-head">
                  <div>
                    <small class="scr-eyebrow">Serviços</small>
                    <strong>O que você oferece</strong>
                  </div>
                  <span class="scr-btn"><Icon name="plus" />Novo serviço</span>
                </div>
                <ul class="scr-list">
                  <li v-for="s in services" :key="s.name" class="scr-row">
                    <span class="scr-dot"><Icon name="scissors" /></span>
                    <div class="scr-main">
                      <strong>{{ s.name }}</strong>
                      <small>{{ s.dur }}</small>
                    </div>
                    <strong class="scr-price">{{ s.price }}</strong>
                  </li>
                </ul>
              </template>

              <!-- Horários -->
              <template v-else-if="active === 'horarios'">
                <div class="scr-head">
                  <div>
                    <small class="scr-eyebrow">Horários</small>
                    <strong>Atendimento da semana</strong>
                  </div>
                </div>
                <ul class="scr-list">
                  <li v-for="h in hours" :key="h.day" class="scr-row hours-row" :class="{ off: h.off }">
                    <strong class="scr-day">{{ h.day }}</strong>
                    <div class="scr-ranges">
                      <span v-if="h.off" class="scr-off">Fechado</span>
                      <span v-for="r in h.ranges" v-else :key="r" class="scr-range">{{ r }}</span>
                    </div>
                  </li>
                </ul>
              </template>

              <!-- Clientes -->
              <template v-else-if="active === 'clientes'">
                <div class="scr-head">
                  <div>
                    <small class="scr-eyebrow">Clientes</small>
                    <strong>128 cadastrados</strong>
                  </div>
                  <span class="scr-search"><Icon name="search" />Buscar</span>
                </div>
                <ul class="scr-list">
                  <li v-for="c in customers" :key="c.name" class="scr-row">
                    <span class="scr-avatar">{{ c.name[0] }}</span>
                    <div class="scr-main">
                      <strong>{{ c.name }}</strong>
                      <small>{{ c.visits }}</small>
                    </div>
                    <strong class="scr-price">{{ c.spent }}</strong>
                  </li>
                </ul>
              </template>

              <!-- Financeiro -->
              <template v-else-if="active === 'financeiro'">
                <div class="scr-head">
                  <div>
                    <small class="scr-eyebrow">Painel financeiro</small>
                    <strong>Este mês</strong>
                  </div>
                </div>
                <div class="scr-stats">
                  <div v-for="s in finStats" :key="s.label" class="scr-stat" :class="{ accent: s.accent }">
                    <small>{{ s.label }}</small>
                    <strong :class="{ 'gradient-text': s.accent }">{{ s.value }}</strong>
                  </div>
                </div>
                <div class="scr-chart">
                  <small>Faturamento por dia</small>
                  <div class="scr-bars">
                    <span v-for="(b, i) in finBars" :key="i" class="scr-bar" :style="{ height: b + '%', '--d': i * 40 + 'ms' }" />
                  </div>
                </div>
                <ul class="scr-top">
                  <li v-for="s in topServices" :key="s.name">
                    <span class="scr-top-name">{{ s.name }}</span>
                    <span class="scr-top-track"><span :style="{ width: s.pct + '%' }" /></span>
                    <strong>{{ s.value }}</strong>
                  </li>
                </ul>
              </template>

              <!-- Divulgar -->
              <template v-else>
                <div class="scr-head">
                  <div>
                    <small class="scr-eyebrow">Divulgar</small>
                    <strong>Leve clientes pro seu link</strong>
                  </div>
                </div>
                <div class="scr-share">
                  <div class="scr-qr">
                    <span v-for="(c, i) in qrCells" :key="i" :class="{ on: c }" />
                  </div>
                  <div class="scr-share-body">
                    <div class="scr-link">
                      <Icon name="link" />
                      <span>{{ APP_DOMAIN }}/<strong>studio-aurora</strong></span>
                    </div>
                    <span class="scr-btn block"><Icon name="copy" />Copiar link</span>
                    <span class="scr-btn block ghost"><Icon name="whatsapp" />Enviar no WhatsApp</span>
                    <span class="scr-btn block ghost"><Icon name="qr" />Baixar cartaz</span>
                  </div>
                </div>
              </template>
            </div>
          </transition>
        </div>
      </div>

      <div class="tour-foot">
        <RouterLink class="btn" to="/cadastro">
          Quero meu painel
          <Icon name="plus" />
        </RouterLink>
        <span class="muted">Dentro do painel tem um tutorial passo a passo pra te guiar.</span>
      </div>
    </div>
  </section>
</template>

<style scoped>
.section { padding: 80px 0; border-top: 1px solid var(--border); }
.section-head { text-align: center; max-width: 720px; margin: 0 auto 48px; }
.section-head .eyebrow { display: inline-block; margin-bottom: 14px; }
.section-title {
  font-size: clamp(1.7rem, 3.4vw, 2.5rem);
  font-weight: 800;
  letter-spacing: -0.025em;
  line-height: 1.1;
  margin: 0 0 14px;
}
.section-sub { color: var(--muted); font-size: 1rem; max-width: 540px; margin: 0 auto; }

.tour { max-width: 980px; margin: 0 auto; }

/* Scroll reveal (o observer fica na Landing) */
[data-reveal] { opacity: 0; transform: translateY(16px); transition: opacity 0.6s ease, transform 0.6s ease; }
[data-reveal].is-visible { opacity: 1; transform: translateY(0); }

/* ---------- Abas ---------- */
.tour-tabs {
  display: flex; flex-wrap: wrap; justify-content: center; gap: 8px;
  margin-bottom: 20px;
}
.tour-tab {
  display: inline-flex; align-items: center; gap: 8px;
  padding: 9px 16px;
  border-radius: 999px;
  border: 1px solid var(--border);
  background: var(--surface);
  color: var(--silver);
  font: inherit; font-size: 0.88rem; font-weight: 600;
  cursor: pointer;
  transition: border-color 0.2s ease, background 0.2s ease, color 0.2s ease, box-shadow 0.2s ease;
}
.tour-tab :deep(svg) { width: 16px; height: 16px; }
.tour-tab:hover { border-color: var(--border-strong); color: #fff; }
.tour-tab.on {
  background: linear-gradient(140deg, var(--brand), var(--brand-strong));
  border-color: rgba(59, 130, 246, 0.6);
  color: #fff;
  box-shadow: 0 0 24px var(--brand-soft);
}
.tour-tab:focus-visible { outline: 2px solid var(--brand); outline-offset: 2px; }

/* ---------- Janela ---------- */
.tour-window {
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--surface);
  box-shadow: var(--shadow), 0 0 40px var(--brand-soft);
  overflow: hidden;
}
.tour-bar {
  display: flex; align-items: center; gap: 6px;
  padding: 11px 16px;
  border-bottom: 1px solid var(--border);
  background: rgba(5, 11, 22, 0.5);
}
.tour-bar code { color: var(--muted); background: none; padding: 0; font-size: 0.78rem; }
.url-dot { width: 9px; height: 9px; border-radius: 50%; }
.url-dot:nth-child(1) { background: rgba(248, 113, 113, 0.6); }
.url-dot:nth-child(2) { background: rgba(251, 191, 36, 0.6); }
.url-dot:nth-child(3) { background: rgba(74, 222, 128, 0.6); margin-right: 8px; }

.tour-body {
  display: grid;
  grid-template-columns: minmax(0, 0.8fr) minmax(0, 1.2fr);
  gap: 32px;
  align-items: center;
  padding: 32px;
}
.tour-icon {
  width: 44px; height: 44px;
  display: grid; place-items: center; border-radius: 12px;
  background: var(--brand-soft); border: 1px solid rgba(59, 130, 246, 0.3);
  color: var(--brand-ink);
}
.tour-icon :deep(svg) { width: 22px; height: 22px; }
.tour-title { font-size: 1.35rem; font-weight: 800; letter-spacing: -0.02em; margin: 16px 0 10px; }
.tour-text { margin: 0; font-size: 0.98rem; }

.tour-screen {
  min-height: 330px;
  padding: 18px;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  background: rgba(5, 11, 22, 0.55);
  display: flex; flex-direction: column; gap: 14px;
}
.tour-fade-enter-active, .tour-fade-leave-active { transition: opacity 0.18s ease, transform 0.18s ease; }
.tour-fade-enter-from { opacity: 0; transform: translateY(8px); }
.tour-fade-leave-to { opacity: 0; transform: translateY(-6px); }

/* ---------- Peças das telas ---------- */
.scr-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.scr-head > div { display: flex; flex-direction: column; min-width: 0; }
.scr-head strong { font-size: 1rem; }
.scr-eyebrow {
  color: var(--brand-ink); font-size: 0.62rem; font-weight: 700;
  letter-spacing: 0.2em; text-transform: uppercase;
}
.scr-btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 6px;
  padding: 7px 12px; border-radius: 10px;
  background: linear-gradient(140deg, var(--brand), var(--brand-strong));
  color: #fff; font-size: 0.74rem; font-weight: 700; white-space: nowrap;
}
.scr-btn :deep(svg) { width: 13px; height: 13px; }
.scr-btn.block { width: 100%; }
.scr-btn.ghost { background: var(--surface-strong); border: 1px solid var(--border); color: var(--silver); }
.scr-search {
  display: inline-flex; align-items: center; gap: 6px;
  padding: 7px 12px; border-radius: 10px;
  border: 1px solid var(--border); color: var(--muted); font-size: 0.74rem;
}
.scr-search :deep(svg) { width: 13px; height: 13px; }

.scr-stats { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; }
.scr-stat {
  display: flex; flex-direction: column; gap: 2px;
  padding: 10px 12px; border-radius: 10px;
  border: 1px solid var(--border); background: var(--surface);
}
.scr-stat.accent { border-color: rgba(59, 130, 246, 0.4); background: var(--brand-soft); }
.scr-stat small { color: var(--muted); font-size: 0.62rem; font-weight: 600; }
.scr-stat strong { font-size: 1.05rem; }

.scr-list, .scr-top { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 6px; }
.scr-row {
  display: flex; align-items: center; gap: 12px;
  padding: 9px 12px; border-radius: 10px;
  border: 1px solid var(--border); background: var(--surface);
}
.scr-main { display: flex; flex-direction: column; flex: 1; min-width: 0; }
.scr-main strong { font-size: 0.84rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.scr-main small { color: var(--muted); font-size: 0.7rem; }
.scr-time { font-size: 0.86rem; font-variant-numeric: tabular-nums; color: var(--silver); }
.scr-price { font-size: 0.84rem; color: var(--silver); white-space: nowrap; }
.scr-row .badge { font-size: 0.62rem; padding: 2px 8px; white-space: nowrap; }
.scr-dot, .scr-avatar {
  width: 30px; height: 30px; flex-shrink: 0;
  display: grid; place-items: center; border-radius: 9px;
  background: var(--brand-soft); color: var(--brand-ink);
  font-size: 0.8rem; font-weight: 800;
}
.scr-avatar { border-radius: 50%; }
.scr-dot :deep(svg) { width: 14px; height: 14px; }

.hours-row { padding: 7px 12px; }
.hours-row.off { opacity: 0.6; }
.scr-day { width: 34px; font-size: 0.8rem; }
.scr-ranges { display: flex; flex-wrap: wrap; gap: 6px; }
.scr-range {
  padding: 3px 9px; border-radius: 999px;
  background: var(--brand-soft); color: var(--silver);
  font-size: 0.7rem; font-weight: 600; font-variant-numeric: tabular-nums;
}
.scr-off { color: var(--muted); font-size: 0.74rem; }

.scr-chart {
  padding: 10px 12px; border-radius: 10px;
  border: 1px solid var(--border); background: var(--surface);
}
.scr-chart small { color: var(--muted); font-size: 0.62rem; font-weight: 600; }
.scr-bars { display: flex; align-items: flex-end; gap: 5px; height: 72px; margin-top: 8px; }
.scr-bar {
  flex: 1; border-radius: 4px 4px 0 0;
  background: linear-gradient(180deg, var(--brand), rgba(59, 130, 246, 0.25));
  transform-origin: bottom;
  animation: barGrow 0.5s cubic-bezier(0.2, 0.8, 0.2, 1) var(--d, 0ms) both;
}
@keyframes barGrow { from { transform: scaleY(0); } to { transform: scaleY(1); } }
.scr-top li { display: flex; align-items: center; gap: 10px; font-size: 0.74rem; }
.scr-top-name { width: 96px; color: var(--silver); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.scr-top-track { flex: 1; height: 6px; border-radius: 999px; background: var(--surface-strong); overflow: hidden; }
.scr-top-track span { display: block; height: 100%; border-radius: inherit; background: var(--brand); }
.scr-top strong { white-space: nowrap; }

.scr-share { display: flex; align-items: center; gap: 18px; flex: 1; }
.scr-qr {
  flex-shrink: 0;
  display: grid; grid-template-columns: repeat(9, 1fr); gap: 2px;
  width: 132px; height: 132px; padding: 10px;
  border-radius: 12px; background: #fff;
}
.scr-qr span { border-radius: 1px; }
.scr-qr span.on { background: #0b1730; }
.scr-share-body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 8px; }
.scr-link {
  display: flex; align-items: center; gap: 8px;
  padding: 9px 12px; border-radius: 10px;
  border: 1px solid var(--border); background: var(--surface);
  color: var(--muted); font-size: 0.76rem;
  white-space: nowrap; overflow: hidden;
}
.scr-link span { overflow: hidden; text-overflow: ellipsis; }
.scr-link strong { color: var(--brand-ink); font-weight: 600; }
.scr-link :deep(svg) { width: 14px; height: 14px; flex-shrink: 0; color: var(--brand-ink); }

/* ---------- Rodapé ---------- */
.tour-foot {
  display: flex; flex-wrap: wrap; align-items: center; justify-content: center; gap: 14px 18px;
  margin-top: 28px; text-align: center;
}
.tour-foot .muted { font-size: 0.9rem; }

@media (max-width: 900px) {
  .section { padding: 56px 0; }
  .tour-body { grid-template-columns: 1fr; gap: 22px; padding: 22px; }
  .tour-copy { text-align: center; }
  .tour-icon { margin: 0 auto; }
  .tour-title { font-size: 1.2rem; margin-top: 12px; }
}

@media (max-width: 560px) {
  .section-head { margin-bottom: 32px; }
  /* Abas viram uma faixa rolável, sem quebrar em várias linhas */
  .tour-tabs {
    flex-wrap: nowrap; justify-content: flex-start;
    overflow-x: auto; scrollbar-width: none;
    margin: 0 -16px 16px; padding: 4px 16px;
  }
  .tour-tabs::-webkit-scrollbar { display: none; }
  .tour-tab { flex-shrink: 0; padding: 8px 14px; font-size: 0.84rem; }
  .tour-body { padding: 16px; }
  .tour-screen { padding: 14px; min-height: 0; }
  .scr-head .scr-btn { padding: 7px 9px; font-size: 0.68rem; }
  .scr-stat { padding: 8px; }
  .scr-stat strong { font-size: 0.92rem; }
  .scr-share { flex-direction: column; align-items: stretch; }
  .scr-qr { align-self: center; }
}

@media (prefers-reduced-motion: reduce) {
  [data-reveal] { opacity: 1; transform: none; transition: none; }
  .tour-fade-enter-active, .tour-fade-leave-active { transition: none; }
  .scr-bar { animation: none; }
}
</style>
