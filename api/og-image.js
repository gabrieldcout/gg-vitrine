// Vercel Function: logo da vitrine pra pré-visualização de link, num endereço
// limpo do próprio site (/og/logos/<id>/<arquivo>), sempre em PNG reduzido.
// Endereço com "?a=1&b=2" quebra em alguns leitores de prévia (o & vira &amp;)
// e o Supabase então devolve WebP, que o WhatsApp do computador não mostra.
export default async function handler(req, res) {
  const path = String(req.query.path ?? '')
  const base = process.env.VITE_SUPABASE_URL
  // Só o bucket público de logos, sem subir de pasta.
  if (!base || !/^logos\/[\w-]+\/[\w.-]+$/.test(path)) {
    res.status(404).send('Not found')
    return
  }
  try {
    const r = await fetch(`${base}/storage/v1/render/image/public/${path}?width=256&height=256&resize=contain&quality=70&format=origin`, {
      headers: { Accept: 'image/png,image/jpeg,image/*' },
      signal: AbortSignal.timeout(5000),
    })
    if (!r.ok) {
      res.status(r.status === 404 ? 404 : 502).send('Imagem indisponível')
      return
    }
    res.setHeader('Content-Type', r.headers.get('content-type') ?? 'image/png')
    // O nome do arquivo muda quando o lojista troca a logo, então pode ficar em cache por muito tempo.
    res.setHeader('Cache-Control', 'public, max-age=86400, s-maxage=31536000, immutable')
    res.status(200).send(Buffer.from(await r.arrayBuffer()))
  } catch {
    res.status(502).send('Imagem indisponível')
  }
}
