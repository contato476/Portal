// ════════════════════════════════════════════════════════════════════
// Função serverless (Vercel) — resolve um link curto de agendamento do
// Google (calendar.app.google/XXXX) para a forma que pode ser embutida
// dentro do sistema.
//
// POR QUE PRECISA DISSO:
// o link curto que o Google te dá responde com "X-Frame-Options:
// SAMEORIGIN" — ou seja, ele se recusa a aparecer dentro de outro site,
// e a prévia ficaria em branco. O MESMO agendamento tem uma segunda
// forma, com "?gv=true", que o Google libera para embutir.
//
// A diferença entre as duas está só no caminho da URL, e para descobrir
// o caminho é preciso seguir o redirecionamento do link curto — coisa
// que o navegador não faz sozinho por causa de CORS. Daí esta função.
//
// Ela só alcança endereços de agenda do Google: qualquer outro host é
// recusado, então isto não vira um proxy aberto.
// ════════════════════════════════════════════════════════════════════

const HOSTS_ACEITOS = ['calendar.app.google', 'calendar.google.com'];

export default async function handler(req, res) {
  const bruto = (req.query && req.query.url) || '';
  let u;
  try {
    u = new URL(String(bruto).trim());
  } catch {
    return res.status(400).json({ error: 'Link inválido' });
  }
  if (!HOSTS_ACEITOS.includes(u.hostname)) {
    return res.status(400).json({ error: 'Só aceito links de agendamento do Google (calendar.app.google)' });
  }

  try {
    // Segue o redirecionamento até a página final do agendamento.
    const r = await fetch(u.toString(), {
      redirect: 'follow',
      headers: { 'User-Agent': 'jp-gestao/1.0' },
    });
    const final = r.url || u.toString();

    // O identificador do agendamento aparece depois de
    // /appointments/schedules/ — é ele que monta a versão embutível.
    const m = final.match(/\/appointments\/schedules\/([^/?#]+)/);
    if (!m) {
      return res.status(422).json({
        error: 'Esse link não parece ser uma página de agendamento do Google. Confira se você copiou o link de "Agenda de compromissos".',
      });
    }

    // O link para COMPARTILHAR continua sendo o curto, quando foi ele
    // que veio: é bem mais apresentável num e-mail ou WhatsApp que a
    // URL longa de 100 caracteres. O longo serve só para a prévia.
    const curto = u.hostname === 'calendar.app.google';
    return res.status(200).json({
      abrir: curto ? u.toString() : final.split('?')[0],
      embed: `https://calendar.google.com/calendar/appointments/schedules/${m[1]}?gv=true`,
    });
  } catch (e) {
    return res.status(502).json({ error: 'Não consegui abrir o link no Google agora. Tente de novo.' });
  }
}
