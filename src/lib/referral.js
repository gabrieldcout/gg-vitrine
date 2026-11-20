// Indique e ganhe: guarda quem indicou (?indique=<slug>) até a pessoa se cadastrar.
const KEY = 'gg-indicado-por'
const DAYS = 60

export function captureReferral(query) {
  const slug = String(query?.indique ?? '').toLowerCase().replace(/[^a-z0-9-]/g, '').slice(0, 40)
  if (slug.length < 3) return
  try { localStorage.setItem(KEY, JSON.stringify({ slug, at: Date.now() })) } catch { /* sem storage */ }
}

export function getReferral() {
  try {
    const v = JSON.parse(localStorage.getItem(KEY) || 'null')
    if (v?.slug && Date.now() - v.at < DAYS * 864e5) return v.slug
  } catch { /* sem storage */ }
  return null
}

export const referralLink = (origin, slug) => `${origin}/?indique=${slug}`
