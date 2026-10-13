<script setup>
import { ref, computed } from 'vue'
import { useBusiness } from '@/lib/business'
import { APP_NAME, APP_DOMAIN, SUPPORT_WHATSAPP } from '@/config/brand'
import { waLink } from '@/lib/whatsapp'
import Icon from '@/components/Icon.vue'

const biz = useBusiness()
const openFaq = ref(null)
const copied = ref(false)

const publicLink = computed(() => biz.business && `${location.origin}/${biz.business.slug}`)
const publicLinkShort = computed(() => biz.business && `${APP_DOMAIN}/${biz.business.slug}`)
const supportLink = computed(() => SUPPORT_WHATSAPP &&
  waLink(SUPPORT_WHATSAPP, `Olá! Preciso de ajuda com ${APP_NAME}.`))
const whatsappShareLink = computed(() => biz.business && publicLink.value &&
  `https://api.whatsapp.com/send?text=${encodeURIComponent(`Agende um horário com ${biz.business.name}: ${publicLink.value}`)}`)

async function copyLink() {
  if (!publicLink.value) return
  await navigator.clipboard.writeText(publicLink.value)
  copied.value = true
  setTimeout(() => { copied.value = false }, 2000)
}

const steps = [
  {
    icon: 'store',
    title: 'Monte sua vitrine',
    text: 'Cadastre seus serviços, profissionais e horários de atendimento. Isso aparece no seu link público.',
    link: { to: '/painel/servicos', label: 'Ir para Serviços' },
  },
  {
    icon: 'link',
    title: 'Compartilhe seu link',
    text: 'Cada vitrine tem um link único. Compartilha no WhatsApp, Instagram, cartão de visita, QR code.',
    link: { to: '/painel/divulgar', label: 'Ir para Divulgar' },
  },
  {
    icon: 'calendar',
    title: 'Receba agendamentos',
    text: 'Seu cliente escolhe serviço, dia e hora direto pelo celular — mesmo de madrugada. Você só aparece pra atender.',
    link: { to: '/painel', label: 'Ir para Agenda' },
  },
]

const sections = [
  {
    icon: 'scissors',
    title: 'Serviços',
    text: 'Cadastre tudo que você oferece — nome, preço, duração. Cliente escolhe entre eles ao agendar.',
    to: '/painel/servicos',
  },
  {
    icon: 'users',
    title: 'Profissionais',
    text: 'Se você trabalha com mais pessoas (equipe) ou tem salas/quadras separadas, cadastra aqui. Cliente escolhe com quem agendar.',
    to: '/painel/profissionais',
  },
  {
    icon: 'clock',
    title: 'Horários',
    text: 'Define em que dias e horas cada profissional atende. O cliente só vê os slots livres respeitando isso.',
    to: '/painel/horarios',
  },
  {
    icon: 'ban',
    title: 'Folgas e bloqueios',
    text: 'Marca folgas, feriados ou momentos que você não vai atender. O horário fica indisponível pra agendamento.',
    to: '/painel/bloqueios',
  },
  {
    icon: 'contact',
    title: 'Clientes',
    text: 'Toda vez que alguém agenda, cria uma ficha. Histórico de agendamentos, total gasto, última visita.',
    to: '/painel/clientes',
  },
  {
    icon: 'bell',
    title: 'Lembretes automáticos',
    text: 'A gente avisa seu cliente antes do agendamento por e-mail. Reduz muito o "não compareceu".',
    to: '/painel/lembretes',
  },
  {
    icon: 'image',
    title: 'Galeria',
    text: 'Suba fotos do seu trabalho pra aparecer na vitrine. Vende mais que texto.',
    to: '/painel/galeria',
  },
  {
    icon: 'star',
    title: 'Avaliações',
    text: 'Clientes podem avaliar depois do atendimento. Você modera o que aparece na vitrine.',
    to: '/painel/avaliacoes',
  },
  {
    icon: 'gift',
    title: 'Cartão fidelidade',
    text: 'A cada atendimento, 1 carimbo. Fechou o cartão, ganha o prêmio que você definir. Volta mais.',
    to: '/painel/fidelidade',
  },
  {
    icon: 'tag',
    title: 'Cupons de desconto',
    text: 'Crie códigos tipo "PRIMEIRA20" que dão desconto. Divulga nas redes pra atrair clientes novos.',
    to: '/painel/cupons',
  },
  {
    icon: 'chart',
    title: 'Financeiro',
    text: 'Veja quanto faturou no mês, qual serviço mais vende, quais clientes mais gastaram.',
    to: '/painel/financeiro',
  },
  {
    icon: 'store',
    title: 'Perfil',
    text: 'Logo, cor da marca, descrição do negócio, endereço, contato. Tudo que aparece pros clientes na vitrine.',
    to: '/painel/perfil',
  },
]

const faqs = [
  {
    q: 'Como meus clientes agendam?',
    a: 'Eles abrem o link da sua vitrine, escolhem o serviço, o profissional, o dia e a hora. Confirmam com nome e WhatsApp. O agendamento cai aqui na sua agenda automaticamente — não precisa WhatsApp, nem telefone.',
  },
  {
    q: 'Posso cancelar ou remarcar?',
    a: 'Pode. Tanto você quanto o cliente podem cancelar/remarcar. O cliente faz isso entrando com o mesmo e-mail que usou pra agendar (recebe um código de acesso).',
  },
  {
    q: 'E se eu quiser bloquear um dia (feriado, viagem)?',
    a: 'Vai em "Folgas e bloqueios" e marca o período. Enquanto estiver bloqueado, não aparece pra agendamento na vitrine.',
  },
  {
    q: 'Como mudar meus horários de atendimento?',
    a: 'Em "Horários". Define o horário por profissional e por dia da semana. Pode ter intervalos (ex: 9-12 e 14-18). Vale pra sempre, não precisa refazer.',
  },
  {
    q: 'Posso ter mais de um estabelecimento?',
    a: 'Depende do seu plano: Solo = 1, Equipe = 3, Rede = 5. Cada estabelecimento tem link, agenda e configurações próprias.',
  },
  {
    q: 'Como funciona o cartão fidelidade?',
    a: 'Você define: quantos carimbos pra ganhar prêmio (ex: 10) e qual o prêmio (ex: "1 serviço grátis"). A cada atendimento concluído, o cliente ganha 1 carimbo automaticamente. Ele pode consultar o próprio cartão pela vitrine.',
  },
  {
    q: 'E o cliente que não aparece no horário?',
    a: 'Marca o agendamento como "não compareceu" na agenda. O cliente fica registrado como "não comparecimento" na ficha dele. Com lembretes automáticos ligados, isso cai bastante.',
  },
  {
    q: 'A assinatura inclui o quê?',
    a: 'Todas as funcionalidades. O que muda entre os planos é só o número de estabelecimentos que você pode cadastrar na sua conta.',
  },
]
</script>

<template>
  <div class="page-header tut-header">
    <p class="eyebrow tut-eyebrow">Ajuda</p>
    <h1>Como funciona o {{ APP_NAME }}</h1>
    <p class="muted tut-lede">
      Tudo que você precisa saber pra usar seu painel, montar sua vitrine e começar a receber clientes.
    </p>
  </div>

  <!-- Link rápido pra divulgação -->
  <section v-if="biz.live && publicLink" class="tut-cta">
    <div class="tut-cta-info">
      <span class="tut-cta-badge"><Icon name="link" /></span>
      <div>
        <strong>Seu link está pronto</strong>
        <small>{{ publicLinkShort }}</small>
      </div>
    </div>
    <div class="tut-cta-actions">
      <button class="btn small" @click="copyLink">
        <Icon :name="copied ? 'check' : 'copy'" />
        {{ copied ? 'Copiado' : 'Copiar' }}
      </button>
      <a class="btn small secondary" :href="whatsappShareLink" target="_blank" rel="noopener">
        <Icon name="whatsapp" />
        Enviar
      </a>
    </div>
  </section>

  <!-- 3 passos: como funciona -->
  <section class="tut-section">
    <div class="section-head">
      <span class="section-badge"><Icon name="sparkles" /></span>
      <div>
        <h2>Como funciona</h2>
        <small class="muted">O {{ APP_NAME }} em 3 passos.</small>
      </div>
    </div>

    <div class="tut-steps">
      <div v-for="(s, i) in steps" :key="s.title" class="tut-step">
        <div class="tut-step-num">{{ String(i + 1).padStart(2, '0') }}</div>
        <div class="tut-step-icon"><Icon :name="s.icon" /></div>
        <h3>{{ s.title }}</h3>
        <p class="muted">{{ s.text }}</p>
        <RouterLink v-if="s.link" :to="s.link.to" class="link-btn">{{ s.link.label }} →</RouterLink>
      </div>
    </div>
  </section>

  <!-- Divulgar sua vitrine (seção destacada) -->
  <section class="tut-section">
    <div class="section-head">
      <span class="section-badge"><Icon name="qr" /></span>
      <div>
        <h2>Como divulgar sua vitrine</h2>
        <small class="muted">Quanto mais gente vir seu link, mais agendamentos você recebe.</small>
      </div>
    </div>

    <div class="tut-grid-2">
      <div class="tut-card">
        <h3><Icon name="whatsapp" /> No WhatsApp</h3>
        <p>Cola o link na sua assinatura, no status, ou envia direto pros clientes. Na página "Divulgar" tem um botão que já abre o WhatsApp com texto pronto.</p>
      </div>
      <div class="tut-card">
        <h3><Icon name="instagram" /> No Instagram</h3>
        <p>Cola na bio do perfil. Ou nos stories como link clicável. Na página "Divulgar" tem um texto pronto pra isso.</p>
      </div>
      <div class="tut-card">
        <h3><Icon name="qr" /> QR Code impresso</h3>
        <p>A gente gera um QR do seu link. Imprime e deixa no balcão, mesa, cartão de visita. Cliente aponta a câmera e abre direto.</p>
      </div>
      <div class="tut-card">
        <h3><Icon name="map" /> No Google Meu Negócio</h3>
        <p>Se tem perfil no Google (seu negócio aparece no Maps), cola o link no campo "site". Quem buscar seu negócio no Google já encontra pra agendar.</p>
      </div>
    </div>
    <RouterLink to="/painel/divulgar" class="btn secondary" style="margin-top: 16px">
      <Icon name="qr" /> Ir para Divulgar
    </RouterLink>
  </section>

  <!-- Tudo que o painel oferece -->
  <section class="tut-section">
    <div class="section-head">
      <span class="section-badge"><Icon name="store" /></span>
      <div>
        <h2>O que tem no painel</h2>
        <small class="muted">Cada seção do seu painel, explicada.</small>
      </div>
    </div>

    <div class="tut-features">
      <RouterLink v-for="s in sections" :key="s.title" :to="s.to" class="tut-feature">
        <span class="tut-feature-icon"><Icon :name="s.icon" /></span>
        <div>
          <strong>{{ s.title }}</strong>
          <small class="muted">{{ s.text }}</small>
        </div>
        <span class="tut-feature-arrow">→</span>
      </RouterLink>
    </div>
  </section>

  <!-- FAQ -->
  <section class="tut-section">
    <div class="section-head">
      <span class="section-badge"><Icon name="sparkles" /></span>
      <div>
        <h2>Perguntas frequentes</h2>
        <small class="muted">Dúvidas que os donos mais fazem por aqui.</small>
      </div>
    </div>

    <div class="tut-faq">
      <details v-for="(f, i) in faqs" :key="f.q" :open="openFaq === i"
               @toggle="openFaq = $event.target.open ? i : openFaq">
        <summary>
          <span>{{ f.q }}</span>
          <span class="tut-faq-chevron">+</span>
        </summary>
        <p>{{ f.a }}</p>
      </details>
    </div>
  </section>

  <!-- Suporte -->
  <section v-if="supportLink" class="tut-support">
    <div>
      <strong>Precisa de ajuda com algo específico?</strong>
      <small class="muted">A gente responde no WhatsApp.</small>
    </div>
    <a class="btn" :href="supportLink" target="_blank" rel="noopener">
      <Icon name="whatsapp" /> Falar com suporte
    </a>
  </section>
</template>

<style scoped>
.tut-header { margin-bottom: 24px; }
.tut-eyebrow { display: inline-block; margin-bottom: 6px; }
.tut-lede { font-size: 0.95rem; max-width: 620px; margin: 4px 0 0; }

/* CTA do link no topo */
.tut-cta {
  display: flex; align-items: center; justify-content: space-between;
  gap: 16px; flex-wrap: wrap;
  padding: 16px 18px;
  margin-bottom: 28px;
  border-radius: var(--radius);
  background:
    radial-gradient(ellipse 320px 100px at 10% 50%, var(--brand-soft), transparent 70%),
    var(--surface);
  border: 1px solid var(--border);
}
.tut-cta-info { display: flex; align-items: center; gap: 12px; min-width: 0; flex: 1; }
.tut-cta-badge {
  width: 40px; height: 40px; border-radius: 12px; flex-shrink: 0;
  display: grid; place-items: center;
  background: linear-gradient(140deg, var(--brand), var(--brand-strong));
  color: #fff; box-shadow: 0 0 18px var(--brand-glow);
}
.tut-cta-badge :deep(svg) { width: 16px; height: 16px; }
.tut-cta-info strong { display: block; }
.tut-cta-info small { color: var(--muted); font-size: 0.85rem; }
.tut-cta-actions { display: flex; gap: 8px; flex-shrink: 0; }

/* Seções */
.tut-section { margin-bottom: 36px; }
.section-head { display: flex; align-items: center; gap: 12px; margin-bottom: 20px; }
.section-badge {
  width: 40px; height: 40px; border-radius: 12px; flex-shrink: 0;
  display: grid; place-items: center;
  background: linear-gradient(140deg, var(--brand), var(--brand-strong));
  color: #fff; box-shadow: 0 0 18px var(--brand-glow);
}
.section-badge :deep(svg) { width: 18px; height: 18px; }
.section-head h2 { margin: 0; font-size: 1.3rem; font-weight: 800; letter-spacing: -0.02em; }
.section-head small { display: block; font-size: 0.85rem; margin-top: 2px; }

/* 3 passos */
.tut-steps {
  display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px;
}
.tut-step {
  position: relative;
  padding: 22px 18px;
  border-radius: var(--radius);
  background:
    radial-gradient(ellipse 260px 140px at 100% 0%, var(--brand-soft), transparent 65%),
    var(--surface);
  border: 1px solid var(--border);
}
.tut-step-num {
  position: absolute; top: 14px; right: 16px;
  font-size: 1.8rem; font-weight: 900;
  color: rgba(148, 180, 220, 0.14);
  letter-spacing: -0.03em;
}
.tut-step-icon {
  width: 44px; height: 44px; border-radius: 12px;
  display: grid; place-items: center;
  background: var(--brand-soft);
  color: var(--brand-ink);
  border: 1px solid rgba(59, 130, 246, 0.3);
  margin-bottom: 14px;
}
.tut-step-icon :deep(svg) { width: 20px; height: 20px; }
.tut-step h3 { font-size: 1.05rem; margin: 0 0 6px; letter-spacing: -0.01em; }
.tut-step p { font-size: 0.92rem; margin: 0 0 10px; line-height: 1.5; }
.tut-step .link-btn { font-size: 0.85rem; font-weight: 600; }

/* 2 colunas (card grid) */
.tut-grid-2 {
  display: grid; grid-template-columns: 1fr 1fr; gap: 12px;
}
.tut-card {
  padding: 16px 18px;
  border-radius: var(--radius-sm);
  background: var(--surface);
  border: 1px solid var(--border);
}
.tut-card h3 {
  display: inline-flex; align-items: center; gap: 8px;
  margin: 0 0 6px; font-size: 1rem; font-weight: 700;
}
.tut-card h3 :deep(svg) { width: 16px; height: 16px; color: var(--brand-ink); }
.tut-card p { font-size: 0.9rem; margin: 0; color: var(--silver); line-height: 1.5; }

/* Features list */
.tut-features {
  display: grid; grid-template-columns: 1fr 1fr; gap: 10px;
}
.tut-feature {
  display: flex; align-items: center; gap: 14px;
  padding: 14px 16px;
  border-radius: var(--radius-sm);
  background: var(--surface);
  border: 1px solid var(--border);
  color: var(--text);
  text-decoration: none;
  transition: transform 0.2s ease, border-color 0.2s ease, background 0.2s ease;
}
.tut-feature:hover {
  transform: translateY(-2px);
  border-color: var(--brand);
  background: var(--surface-strong);
  color: var(--text);
}
.tut-feature-icon {
  width: 40px; height: 40px; border-radius: 10px; flex-shrink: 0;
  display: grid; place-items: center;
  background: var(--brand-soft);
  color: var(--brand-ink);
  border: 1px solid rgba(59, 130, 246, 0.25);
}
.tut-feature-icon :deep(svg) { width: 18px; height: 18px; }
.tut-feature strong { display: block; margin-bottom: 2px; font-size: 0.95rem; }
.tut-feature small { font-size: 0.82rem; line-height: 1.4; display: block; color: var(--muted); }
.tut-feature-arrow { color: var(--muted); flex-shrink: 0; font-size: 1.2rem; font-weight: 400; transition: transform 0.2s ease, color 0.2s ease; }
.tut-feature:hover .tut-feature-arrow { color: var(--brand-ink); transform: translateX(2px); }

/* FAQ */
.tut-faq { display: flex; flex-direction: column; gap: 8px; }
.tut-faq details {
  padding: 0;
  border-radius: var(--radius-sm);
  background: var(--surface);
  border: 1px solid var(--border);
  overflow: hidden;
  transition: border-color 0.2s ease;
}
.tut-faq details[open] { border-color: var(--brand); }
.tut-faq summary {
  display: flex; justify-content: space-between; align-items: center; gap: 12px;
  padding: 14px 18px;
  cursor: pointer;
  font-weight: 600;
  list-style: none;
  user-select: none;
}
.tut-faq summary::-webkit-details-marker { display: none; }
.tut-faq-chevron {
  display: grid; place-items: center;
  width: 24px; height: 24px; border-radius: 50%;
  background: var(--brand-soft); color: var(--brand-ink);
  font-size: 1.2rem; font-weight: 300; line-height: 1;
  transition: transform 0.25s ease;
  flex-shrink: 0;
}
.tut-faq details[open] .tut-faq-chevron { transform: rotate(45deg); }
.tut-faq p {
  padding: 0 18px 16px;
  margin: 0;
  color: var(--silver);
  font-size: 0.92rem;
  line-height: 1.6;
}

/* Suporte final */
.tut-support {
  display: flex; align-items: center; justify-content: space-between;
  gap: 16px; flex-wrap: wrap;
  padding: 20px 22px;
  margin-top: 20px;
  border-radius: var(--radius);
  background:
    radial-gradient(ellipse 380px 160px at 100% 50%, rgba(74, 222, 128, 0.14), transparent 70%),
    var(--surface);
  border: 1px solid var(--border);
}
.tut-support strong { display: block; }
.tut-support small { color: var(--muted); font-size: 0.85rem; }

/* Mobile */
@media (max-width: 760px) {
  .tut-steps { grid-template-columns: 1fr; }
  .tut-grid-2 { grid-template-columns: 1fr; }
  .tut-features { grid-template-columns: 1fr; }
  .tut-cta-actions { flex: 1 1 100%; }
  .tut-cta-actions .btn { flex: 1; }
}
</style>
