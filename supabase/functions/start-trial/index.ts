// GG Vitrine — Edge Function "start-trial"
//
// Lê o IP real do request e chama a RPC start_trial que valida o CPF,
// aplica rate limit por IP e cria a assinatura de teste de 7 dias.
import { createClient } from 'jsr:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const auth = req.headers.get('Authorization') ?? ''
    if (!auth) return json({ error: 'Sem autorização.' }, 401)

    const { cpf } = await req.json()
    if (!cpf) return json({ error: 'Informe o CPF.' }, 400)

    // Pega o IP real do cliente. Supabase passa 'x-forwarded-for' com uma lista
    // separada por vírgula — o primeiro IP é o do usuário.
    const fwd = req.headers.get('x-forwarded-for') ?? ''
    const ip = fwd.split(',')[0].trim() || null

    const client = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: auth } } },
    )

    const { data, error } = await client.rpc('start_trial', { p_cpf: cpf, p_ip: ip })
    if (error) return json({ error: error.message }, 400)
    return json(data ?? { ok: true })
  } catch (e) {
    console.error(e)
    return json({ error: e instanceof Error ? e.message : 'Erro inesperado.' }, 500)
  }
})
