import { supabase } from './supabase'

// Registra visita e cliques da vitrine pro relatório de visitas (0034).
// Não espera e não quebra nada se der erro.
export function track(businessId, kind, label = null) {
  if (!businessId) return
  supabase.rpc('track_event', { p_business: businessId, p_kind: kind, p_label: label }).then(() => {}, () => {})
}

// Uma visita por vitrine a cada 30 min no mesmo aparelho (recarregar não conta de novo).
export function trackVisit(businessId) {
  const key = `gg-visita-${businessId}`
  try {
    const last = Number(sessionStorage.getItem(key) || 0)
    if (Date.now() - last < 30 * 60 * 1000) return
    sessionStorage.setItem(key, String(Date.now()))
  } catch { /* sem armazenamento: conta assim mesmo */ }
  track(businessId, 'visita')
}
