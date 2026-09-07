// ════════════════════════════════════════════════════════════════════
// Função serverless (Vercel) — busca as métricas do Instagram na
// Graph API da Meta.
//
// DUAS DECISÕES QUE VALE ENTENDER:
//
// 1. O TOKEN SÓ EXISTE AQUI. Ele fica na variável de ambiente da
//    Vercel e nunca é enviado ao navegador. Por isso a busca passa por
//    esta função em vez de o site falar direto com a Meta.
//
// 2. ESTA FUNÇÃO NÃO ESCREVE NO SUPABASE. Ela só busca e devolve o
//    JSON já organizado; quem grava é o navegador, com a sessão da
//    própria admin. Assim não precisamos guardar aqui a service_role
//    key, que ignora todas as permissões do banco. É a diferença
//    entre ter um segredo e ter dois.
//
// VARIÁVEIS DE AMBIENTE NECESSÁRIAS (Vercel → Settings → Environment
// Variables, e depois Redeploy):
//   IG_ACCESS_TOKEN     token de longa duração (60 dias)
//   IG_USER_ID          id da conta Instagram Business
//   IG_API_VERSION      opcional, padrão v23.0
//   SUPABASE_URL        https://jvtjhfganuuefswbnbrk.supabase.co
//   SUPABASE_ANON_KEY   a mesma chave pública que o site já usa
// ════════════════════════════════════════════════════════════════════

const V        = process.env.IG_API_VERSION || 'v23.0';
const IG_ID    = process.env.IG_USER_ID;
const TOKEN    = process.env.IG_ACCESS_TOKEN;
const SB_URL   = process.env.SUPABASE_URL;
const SB_ANON  = process.env.SUPABASE_ANON_KEY;

// Só responde para quem está logado no sistema. Validamos o token da
// sessão contra o próprio Supabase — sem inventar senha nova, porque
// qualquer segredo que fosse para o navegador deixaria de ser segredo.
async function sessaoValida(req) {
  const auth = req.headers.authorization || '';
  if (!auth.startsWith('Bearer ')) return false;
  if (!SB_URL || !SB_ANON) return false;
  try {
    const r = await fetch(SB_URL + '/auth/v1/user', {
      headers: { apikey: SB_ANON, Authorization: auth },
    });
    return r.ok;
  } catch {
    return false;
  }
}

async function graph(caminho, params) {
  const u = new URL(`https://graph.facebook.com/${V}/${caminho}`);
  Object.entries({ ...params, access_token: TOKEN }).forEach(([k, v]) => u.searchParams.set(k, v));
  const r = await fetch(u.toString());
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j?.error?.message || ('Graph API respondeu ' + r.status));
  return j;
}

export default async function handler(req, res) {
  if (!TOKEN || !IG_ID) {
    return res.status(500).json({
      error: 'Integração não configurada. Defina IG_ACCESS_TOKEN e IG_USER_ID nas variáveis de ambiente da Vercel.',
    });
  }
  if (!(await sessaoValida(req))) {
    return res.status(401).json({ error: 'Não autorizado' });
  }

  // A Meta aceita no máximo 30 dias por chamada de insights.
  const dias  = Math.min(Math.max(Number(req.query?.days) || 30, 1), 30);
  const until = Math.floor(Date.now() / 1000);
  const since = until - dias * 86400;

  const porDia = {};
  const avisos = [];
  const add = (data, coluna, valor) => {
    if (!data || !coluna) return;
    (porDia[data] ||= { metric_date: data })[coluna] = valor;
  };

  // Cada grupo vai num try/catch separado DE PROPÓSITO: a Meta renomeia
  // e aposenta métricas com frequência (impressions virou views,
  // follower_count está migrando). Se uma cair, as outras continuam e
  // o problema aparece como aviso na tela, em vez de derrubar tudo.
  const grupos = [
    [['reach'],                          { period: 'day', since, until },
      { reach: 'reach' }],
    [['profile_views', 'website_clicks'], { period: 'day', metric_type: 'total_value', since, until },
      { profile_views: 'profile_visits', website_clicks: 'link_taps' }],
    [['views', 'total_interactions'],     { period: 'day', metric_type: 'total_value', since, until },
      { views: 'views', total_interactions: 'interactions' }],
    [['follower_count'],                  { period: 'day', since, until },
      { follower_count: 'net_followers' }],
  ];

  for (const [metricas, params, mapa] of grupos) {
    try {
      const j = await graph(`${IG_ID}/insights`, { metric: metricas.join(','), ...params });
      (j.data || []).forEach((m) =>
        (m.values || []).forEach((v) => {
          const dia = String(v.end_time || '').slice(0, 10);
          const valor = (v.value !== null && typeof v.value === 'object') ? null : v.value;
          if (valor !== null && valor !== undefined) add(dia, mapa[m.name], valor);
        })
      );
    } catch (e) {
      avisos.push(metricas.join(', ') + ': ' + (e.message || e));
    }
  }

  // Seguidores e total de posts são uma foto do AGORA, não série
  // histórica — por isso entram só no dia de hoje.
  let perfil = null;
  try {
    perfil = await graph(IG_ID, { fields: 'username,followers_count,media_count' });
    const hoje = new Date().toISOString().slice(0, 10);
    add(hoje, 'followers', perfil.followers_count);
    add(hoje, 'posts_total', perfil.media_count);
  } catch (e) {
    avisos.push('perfil: ' + (e.message || e));
  }

  // Validade do token, para a tela avisar antes de ele expirar.
  let expiraEm = null;
  try {
    const dbg = await graph('debug_token', { input_token: TOKEN });
    if (dbg?.data?.expires_at) expiraEm = new Date(dbg.data.expires_at * 1000).toISOString();
  } catch {
    // sem app secret o debug_token pode falhar — não é motivo de erro
  }

  res.setHeader('Cache-Control', 'no-store');
  return res.status(200).json({
    username: perfil?.username || null,
    followers_now: perfil?.followers_count ?? null,
    media_count: perfil?.media_count ?? null,
    token_expires_at: expiraEm,
    avisos,
    metrics: Object.values(porDia).sort((a, b) => a.metric_date.localeCompare(b.metric_date)),
  });
}
