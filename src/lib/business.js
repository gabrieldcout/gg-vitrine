import { inject, reactive } from 'vue'
import { supabase, unwrap } from './supabase'
import { session } from './session'

const KEY = Symbol('business')

// Contexto do estabelecimento do usuário logado, compartilhado pelas
// páginas do painel via provide/inject.
export function createBusinessContext() {
  const ctx = reactive({
    loading: true,
    business: null,
    subscription: null,
    plan: null,
    get live() {
      return this.business?.status === 'approved' &&
        ['active', 'past_due', 'trialing'].includes(this.subscription?.status)
    },
    get trial() {
      if (this.subscription?.status !== 'trialing' || !this.subscription?.trial_until) return null
      const until = new Date(this.subscription.trial_until)
      const diffMs = until - Date.now()
      const days = Math.max(0, Math.ceil(diffMs / 86400000))
      return { until, days, expiringSoon: days <= 2 }
    },
    hasFeature(feature) {
      return this.plan?.features?.includes(feature) ?? false
    },
    async reload() {
      this.loading = true
      try {
        const members = unwrap(await supabase.from('business_members')
          .select('business_id').eq('user_id', session.user.id).limit(1))
        if (!members.length) {
          this.business = this.subscription = this.plan = null
          return
        }
        this.business = unwrap(await supabase.from('businesses').select('*').eq('id', members[0].business_id).single())
        // A assinatura pertence ao dono do estabelecimento e cobre todos os negócios dele.
        this.subscription = unwrap(await supabase.from('subscriptions')
          .select('*, effective_price, charge_value, plan:plans(*)')
          .eq('owner_id', this.business.created_by).maybeSingle())
        this.plan = this.subscription?.plan ?? null
      } finally {
        this.loading = false
      }
    },
  })
  return ctx
}

export function provideKey() {
  return KEY
}

export function useBusiness() {
  return inject(KEY, null)   // null fora do painel (landing, cadastro)
}
