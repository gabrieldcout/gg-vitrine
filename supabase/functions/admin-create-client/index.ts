// GG Vitrine — Edge Function "admin-create-client"
//
// O admin cria a vitrine de um cliente sem ele se cadastrar: conta com e-mail
// já confirmado, senha provisória, vitrine aprovada e 7 dias grátis.
// Só o dono da plataforma (is_platform_admin) pode chamar.
import { createClient } from 'jsr:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

const KINDS = ['agenda', 'cardapio', 'fila']

// Senha fácil de ditar pelo WhatsApp: Vitrine + 4 números.
const tempPassword = () => `Vitrine${Math.floor(1000 + Math.random() * 9000)}`
const slugify = (v: string) => v.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
  .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40)

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    })
    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)

    const { data: { user } } = await userClient.auth.getUser()
    if (!user) return json({ error: 'Sua sessão expirou. Entre novamente.' }, 401)
    const { data: isAdmin } = await userClient.rpc('is_platform_admin')
    if (!isAdmin) return json({ error: 'Sem permissão.' }, 403)

    const body = await req.json()
    const name = String(body.name ?? '').trim()
    const slug = slugify(String(body.slug ?? '') || name)
    const email = String(body.email ?? '').trim().toLowerCase()
    const phone = String(body.phone ?? '').replace(/\D/g, '') || null
    const category = String(body.category ?? '').trim() || null
    const kind = KINDS.includes(body.kind) ? body.kind : 'agenda'
    const password = String(body.password ?? '').trim() || tempPassword()

    if (name.length < 2) return json({ error: 'Informe o nome do estabelecimento.' }, 400)
    if (slug.length < 3) return json({ error: 'O link precisa ter pelo menos 3 caracteres.' }, 400)
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: 'Informe um e-mail válido.' }, 400)
    if (password.length < 6) return json({ error: 'A senha precisa ter pelo menos 6 caracteres.' }, 400)

    const { data: free } = await admin.rpc('is_slug_available', { p_slug: slug })
    if (free === false) return json({ error: `O link "${slug}" já está em uso. Escolha outro.` }, 400)

    // Conta já confirmada; o gatilho do cadastro cria a vitrine com estes dados.
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email, password, email_confirm: true,
      user_metadata: {
        full_name: name, business_name: name, business_slug: slug,
        business_category: category, business_kind: kind, business_phone: phone,
        created_by_admin: true,
      },
    })
    if (createErr) {
      const msg = /already|registered|exists/i.test(createErr.message) ? 'Esse e-mail já tem conta na plataforma.' : createErr.message
      return json({ error: msg }, 400)
    }
    const ownerId = created.user.id

    // Se o gatilho não criou (ex.: link pego no meio do caminho), cria aqui.
    let { data: biz } = await admin.from('businesses').select('id').eq('created_by', ownerId).maybeSingle()
    if (!biz) {
      const ins = await admin.from('businesses')
        .insert({ name, slug, category, phone, kind, created_by: ownerId }).select('id').single()
      if (ins.error) {
        await admin.auth.admin.deleteUser(ownerId)   // não deixa conta sem vitrine
        return json({ error: ins.error.message }, 400)
      }
      biz = ins.data
      await admin.from('business_members').insert({ business_id: biz.id, user_id: ownerId, role: 'owner' })
    }

    // Aprovada (o tipo "fila" não passa pelo gatilho) e 7 dias grátis.
    await admin.from('businesses')
      .update({ status: 'approved', approved_at: new Date().toISOString(), kind })
      .eq('id', biz.id)
    await admin.from('subscriptions').upsert({
      owner_id: ownerId, plan_id: 'solo', status: 'trialing',
      trial_until: new Date(Date.now() + 7 * 864e5).toISOString(),
    }, { onConflict: 'owner_id' })

    return json({ ok: true, business_id: biz.id, owner_id: ownerId, slug, email, password })
  } catch (e) {
    console.error(e)
    return json({ error: e instanceof Error ? e.message : 'Erro inesperado.' }, 500)
  }
})
