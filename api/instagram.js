// ════════════════════════════════════════════════════════════════════
// Função serverless (Vercel) — busca as métricas do Instagram.
//
// Usa a "Instagram API with Instagram Login" (graph.instagram.com), que
// é o caminho novo da Meta. Diferenças que importam:
//   · NÃO precisa de Página do Facebook
//   · o login é direto na conta do Instagram
//   · o token de 60 dias PODE SER RENOVADO por chamada — então esta
//     função renova sozinha e você nunca mais mexe nisso
//
// ONDE MORA O TOKEN
// Em app_settings, no seu Supabase, que só o admin lê (policy admin_all).
// Ele não fica em variável de ambiente porque a Vercel não deixa a
// função reescrever a própria variável — e sem reescrever não dá para
// renovar sozinho. Guardando no banco, a renovação é automática.
// O token nunca é devolvido ao navegador: quem lê e escreve é esta
// função, usando a SUA sessão para falar com o Supabase.
//
// Esta função também NÃO grava as métricas: ela devolve o JSON pronto e
// o navegador grava, com a sua sessão. Assim não precisamos guardar aqui
// a service_role key, que ignoraria todas as permissões do banco.
//
// VARIÁVEIS DE AMBIENTE (Vercel → Settings → Environment Variables):
//   SUPABASE_URL       https://jvtjhfganuuefswbnbrk.supabase.co
//   SUPABASE_ANON_KEY  a mesma chave pública que o site já usa
//   IG_API_VERSION     opcional, padrão v23.0
// ════════════════════════════════════════════════════════════════════

const V       = process.env.IG_API_VERSION || 'v23.0';
const SB_URL  = process.env.SUPABASE_URL;
const SB_ANON = process.env.SUPABASE_ANON_KEY;
const HOST    = 'https://graph.instagram.com';

// ──────────── Supabase, com a sessão de quem chamou ────────────
// Toda leitura e escrita passa pela RLS normal: se quem chamou não for
// admin, não lê nada. Não há atalho de privilégio aqui.
async function lerConfig(auth) {
  const url = `${SB_URL}/rest/v1/app_settings?select=key,value&key=in.(ig_access_token,ig_user_id,ig_token_expires_at,ig_username)`;
  const r = await fetch(url, { headers: { apikey: SB_ANON, Authorization: auth } });
  if (!r.ok) throw new Error('Não consegui ler as configurações (sessão inválida?)');
  const linhas = await r.json();
  return Object.fromEntries((linhas || []).map((l) => [l.key, l.value]));
}

async function gravarConfig(auth, key, value) {
  await fetch(`${SB_URL}/rest/v1/app_settings`, {
    method: 'POST',
    headers: {
      apikey: SB_ANON,
      Authorization: auth,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates',
    },
    body: JSON.stringify({ key, value, updated_at: new Date().toISOString() }),
  });
}

// ──────────── Meta ────────────
async function ig(caminho, params, token) {
  const u = new URL(`${HOST}/${V}/${caminho}`);
  Object.entries({ ...params, access_token: token }).forEach(([k, v]) => u.searchParams.set(k, v));
  const r = await fetch(u.toString());
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j?.error?.message || `Instagram respondeu ${r.status}`);
  return j;
}

// Renova o token de 60 dias. A Meta só aceita se ele já tem mais de 24h
// e ainda não expirou — por isso renovamos quando faltam menos de 20
// dias, com folga de sobra.
async function renovarSePreciso(auth, token, expiraEm) {
  const faltamDias = expiraEm ? (new Date(expiraEm) - Date.now()) / 86400000 : 0;
  if (expiraEm && faltamDias > 20) return { token, expiraEm, renovado: false };
  try {
    const u = new URL(`${HOST}/refresh_access_token`);
    u.searchParams.set('grant_type', 'ig_refresh_token');
    u.searchParams.set('access_token', token);
    const r = await fetch(u.toString());
    const j = await r.json();
    if (!r.ok || !j.access_token) throw new Error(j?.error?.message || 'não foi possível renovar');
    const novoExpira = new Date(Date.now() + (j.expires_in || 5184000) * 1000).toISOString();
    await gravarConfig(auth, 'ig_access_token', j.access_token);
    await gravarConfig(auth, 'ig_token_expires_at', novoExpira);
    return { token: j.access_token, expiraEm: novoExpira, renovado: true };
  } catch (e) {
    // Renovação falhou, mas o token atual pode continuar valendo — segue
    // com ele e avisa. Só vira problema de verdade quando expirar.
    return { token, expiraEm, renovado: false, aviso: 'Não consegui renovar o acesso: ' + (e.message || e) };
  }
}

const diaISO = (d) => new Date(d).toISOString().slice(0, 10);

// Um dia por chamada. É o jeito de ter valor DIÁRIO: nesta API, quase
// toda métrica só devolve um total do período pedido, não uma série.
async function metricasDoDia(token, igId, dia) {
  const inicio = Math.floor(new Date(dia + 'T00:00:00Z').getTime() / 1000);
  const fim = inicio + 86400;
  const j = await ig(`${igId}/insights`, {
    metric: 'views,total_interactions,profile_links_taps,follows_and_unfollows',
    metric_type: 'total_value',
    period: 'day',
    since: inicio,
    until: fim,
  }, token);

  const COLUNA = {
    views: 'views',
    total_interactions: 'interactions',
    profile_links_taps: 'link_taps',
    follows_and_unfollows: 'net_followers',
  };
  const linha = { metric_date: dia };
  (j.data || []).forEach((m) => {
    const col = COLUNA[m.name];
    if (!col) return;
    const tv = m.total_value;
    if (!tv) return;
    // follows_and_unfollows vem separado em seguiu / deixou de seguir —
    // o número que interessa é o saldo.
    if (Array.isArray(tv.breakdowns) && tv.breakdowns.length) {
      let saldo = 0;
      tv.breakdowns.forEach((b) =>
        (b.results || []).forEach((r) => {
          const rotulo = (r.dimension_values || []).join(',').toLowerCase();
          saldo += rotulo.includes('unfollow') ? -(r.value || 0) : (r.value || 0);
        })
      );
      linha[col] = saldo;
    } else if (typeof tv.value === 'number') {
      linha[col] = tv.value;
    }
  });
  return linha;
}

export default async function handler(req, res) {
  if (!SB_URL || !SB_ANON) {
    return res.status(500).json({ error: 'Faltam SUPABASE_URL e SUPABASE_ANON_KEY nas variáveis de ambiente da Vercel.' });
  }
  const auth = req.headers.authorization || '';
  if (!auth.startsWith('Bearer ')) return res.status(401).json({ error: 'Não autorizado' });

  let cfg;
  try {
    cfg = await lerConfig(auth);
  } catch (e) {
    return res.status(401).json({ error: e.message || 'Não autorizado' });
  }
  if (!cfg.ig_access_token) {
    return res.status(400).json({ error: 'Instagram ainda não conectado. Clique em "Conectar Instagram" e cole o token.', precisaConectar: true });
  }

  const avisos = [];
  const r = await renovarSePreciso(auth, cfg.ig_access_token, cfg.ig_token_expires_at);
  if (r.aviso) avisos.push(r.aviso);
  const token = r.token;

  // Quem sou eu. Com o login do Instagram, "me" resolve para a conta
  // conectada — não é preciso descobrir id nenhum na mão.
  let perfil = null;
  try {
    perfil = await ig('me', { fields: 'user_id,username,followers_count,media_count' }, token);
  } catch (e) {
    return res.status(400).json({ error: 'O acesso ao Instagram não está valendo: ' + (e.message || e), precisaConectar: true });
  }
  const igId = perfil.user_id || cfg.ig_user_id;
  if (perfil.username) await gravarConfig(auth, 'ig_username', perfil.username);
  if (igId) await gravarConfig(auth, 'ig_user_id', String(igId));

  const dias = Math.min(Math.max(Number(req.query?.days) || 7, 1), 30);
  const hoje = new Date();
  const datas = [];
  for (let i = dias; i >= 1; i--) datas.push(diaISO(hoje.getTime() - i * 86400000));

  const porDia = {};
  // Em blocos de 5 para não estourar o tempo da função nem o limite da Meta.
  for (let i = 0; i < datas.length; i += 5) {
    const bloco = datas.slice(i, i + 5);
    const resultados = await Promise.all(
      bloco.map((d) => metricasDoDia(token, igId, d).catch((e) => ({ metric_date: d, _erro: e.message || String(e) })))
    );
    resultados.forEach((linha) => {
      if (linha._erro) { if (avisos.length < 3) avisos.push(linha.metric_date + ': ' + linha._erro); return; }
      porDia[linha.metric_date] = linha;
    });
  }

  // reach é a única que devolve série diária de verdade — vem numa
  // chamada só, cobrindo a janela inteira.
  try {
    const inicio = Math.floor(new Date(datas[0] + 'T00:00:00Z').getTime() / 1000);
    const fim = Math.floor(hoje.getTime() / 1000);
    const j = await ig(`${igId}/insights`, {
      metric: 'reach', metric_type: 'time_series', period: 'day', since: inicio, until: fim,
    }, token);
    (j.data || []).forEach((m) =>
      (m.values || []).forEach((v) => {
        const dia = String(v.end_time || '').slice(0, 10);
        if (!dia) return;
        (porDia[dia] ||= { metric_date: dia }).reach = v.value;
      })
    );
  } catch (e) {
    avisos.push('alcance: ' + (e.message || e));
  }

  // Seguidores é uma foto do agora, não série — entra só no dia de hoje.
  if (typeof perfil.followers_count === 'number') {
    const hojeISO = diaISO(hoje);
    (porDia[hojeISO] ||= { metric_date: hojeISO }).followers = perfil.followers_count;
  }

  res.setHeader('Cache-Control', 'no-store');
  return res.status(200).json({
    username: perfil.username || null,
    followers_now: perfil.followers_count ?? null,
    media_count: perfil.media_count ?? null,
    token_expires_at: r.expiraEm || null,
    token_renovado: !!r.renovado,
    avisos,
    metrics: Object.values(porDia).sort((a, b) => a.metric_date.localeCompare(b.metric_date)),
  });
}
