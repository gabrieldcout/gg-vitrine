// Vercel Function: serve o index.html da vitrine (/:slug) com as tags de
// pré-visualização da loja (logo, nome e descrição). O WhatsApp e o Instagram
// não rodam o JavaScript do site, então elas precisam vir prontas do servidor.
// Qualquer falha devolve o index.html normal: o site funciona igual.

// Rotas do próprio site que caem na mesma regra de reescrita (/:slug).
const RESERVED = new Set(['painel', 'entrar', 'cadastro', 'termos', 'privacidade', 'admin', 'dev', 'api', 'assets', 'clientes'])

const esc = (v) => String(v ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])

function setMeta(html, attr, key, value) {
  const re = new RegExp(`<meta ${attr}="${key}" content="[^"]*"\\s*/?>`)
  const tag = `<meta ${attr}="${key}" content="${esc(value)}" />`
  return re.test(html) ? html.replace(re, tag) : html.replace('</head>', `    ${tag}\n  </head>`)
}

// Logo enviada pelo painel (Supabase Storage) pode passar de 600 KB, e o
// WhatsApp não mostra imagem pesada na prévia: usa a versão reduzida, no
// formato original (sem format=origin o Supabase manda WebP pra quem aceita).
function previewImage(url) {
  return url.includes('/storage/v1/object/public/')
    ? url.replace('/storage/v1/object/public/', '/storage/v1/render/image/public/') + '?width=400&height=400&resize=contain&quality=80&format=origin'
    : url
}

export function withBusiness(html, b, origin) {
  const isMenu = b.kind === 'cardapio'
  // Mesmos segmentos "não comida" de catalogWord() em src/config/brand.js.
  const word = ['Gás e água', 'Loja e catálogo', 'Outro (pedidos)'].includes(b.category) ? 'catálogo' : 'cardápio'
  const title = `${b.name} · ${isMenu ? `Visite nosso ${word}` : 'Agende seu horário'}`
  const description = b.description?.trim() ||
    (isMenu ? `Veja o cardápio e faça seu pedido online em ${b.name}.` : `Agende seu horário online em ${b.name}.`)
  const image = b.logo_url ? previewImage(b.logo_url) : `${origin}/logo.png`
  let out = html.replace(/<title>[^<]*<\/title>/, `<title>${esc(title)}</title>`)
  out = setMeta(out, 'name', 'description', description)
  out = setMeta(out, 'property', 'og:site_name', b.name)
  out = setMeta(out, 'property', 'og:title', title)
  out = setMeta(out, 'property', 'og:description', description)
  out = setMeta(out, 'property', 'og:image', image)
  out = setMeta(out, 'property', 'og:image:secure_url', image)
  out = setMeta(out, 'property', 'og:image:alt', b.name)
  if (b.logo_url) {
    out = setMeta(out, 'property', 'og:image:width', '400')
    out = setMeta(out, 'property', 'og:image:height', '400')
  }
  out = setMeta(out, 'property', 'og:url', `${origin}/${b.slug}`)
  out = setMeta(out, 'name', 'twitter:card', 'summary')
  if (b.logo_url) out = out.replace(/<link rel="icon"[^>]*>/, `<link rel="icon" href="${esc(b.logo_url)}" />`)
  return out
}

async function fetchBusiness(slug) {
  const url = process.env.VITE_SUPABASE_URL
  const key = process.env.VITE_SUPABASE_ANON_KEY
  if (!url || !key) return null
  const r = await fetch(`${url}/rest/v1/rpc/get_public_business`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_slug: slug }),
    signal: AbortSignal.timeout(3000),
  })
  return r.ok ? r.json() : null
}

export default async function handler(req, res) {
  const proto = req.headers['x-forwarded-proto'] ?? 'https'
  const origin = `${proto}://${req.headers.host}`
  const slug = String(req.query.slug ?? '').toLowerCase()
  let html
  try {
    html = await (await fetch(`${origin}/index.html`)).text()
  } catch {
    res.status(502).send('Erro ao carregar a página.')
    return
  }
  let cache = 'public, s-maxage=600, stale-while-revalidate=86400'
  if (slug && !RESERVED.has(slug)) {
    try {
      const b = await fetchBusiness(slug)
      if (b?.name) html = withBusiness(html, b, origin)
    } catch {
      cache = 'public, s-maxage=60'
    }
  }
  res.setHeader('Content-Type', 'text/html; charset=utf-8')
  res.setHeader('Cache-Control', cache)
  res.status(200).send(html)
}
