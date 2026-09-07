// Função serverless (Vercel) — busca o iCal secreto do Google Agenda
// e devolve pro navegador (o Google não permite buscar direto do site por CORS).
export default async function handler(req, res) {
  const url = (req.query && req.query.url) || '';
  let u;
  try { u = new URL(url); } catch { return res.status(400).json({ error: 'URL inválida' }); }
  if (u.hostname !== 'calendar.google.com') {
    return res.status(400).json({ error: 'Apenas endereços do calendar.google.com são aceitos' });
  }
  try {
    const r = await fetch(u.toString(), { headers: { 'User-Agent': 'jp-gestao/1.0' } });
    if (!r.ok) return res.status(502).json({ error: 'Google retornou status ' + r.status });
    const text = await r.text();
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Cache-Control', 's-maxage=300, stale-while-revalidate=600');
    res.setHeader('Content-Type', 'text/calendar; charset=utf-8');
    return res.status(200).send(text);
  } catch (e) {
    return res.status(500).json({ error: 'Falha ao buscar a agenda do Google' });
  }
}
