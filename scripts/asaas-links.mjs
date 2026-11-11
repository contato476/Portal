// ════════════════════════════════════════════════════════════════════
// Lista os links de pagamento do Asaas e, se você pedir, define a página
// de obrigada dos links da Black do Clube.
//
// Roda no SEU computador, uma vez. A chave de API é pedida na hora e não
// aparece na tela, não é gravada em arquivo e não vai para conversa nenhuma.
//
// COMO USAR (no terminal, dentro da pasta "Meu sistema"):
//   node scripts/asaas-links.mjs            → só lista e escreve o SQL pronto
//   node scripts/asaas-links.mjs obrigada   → lista e define o redirecionamento
//
// Documentação conferida em 11/11/2026:
//   https://docs.asaas.com/reference/listar-links-de-pagamentos
//   https://docs.asaas.com/reference/atualizar-um-link-de-pagamentos
//   https://docs.asaas.com/docs/redirecionamento-apos-o-pagamento
// ════════════════════════════════════════════════════════════════════

import readline from 'node:readline';

const API = (process.env.ASAAS_API_URL || 'https://api.asaas.com/v3').replace(/\/+$/, '');
const OBRIGADA = 'https://maosnaia.jpgestaodescomplicada.com/clube/obrigada';
const LIBERAR_EM = '2026-12-01';

// Os dois links da Black, reconhecidos pelo final do endereço (lib/links.ts do site)
const LINKS_BLACK = {
  zh8qq14izzcf40xo: 'Clube Black · Pix à vista',
  ocapcz9uo57yxplt: 'Clube Black · Cartão parcelado',
};

// Pergunta no terminal. Com "oculto", o que você digita ou cola não aparece.
function perguntar(pergunta, oculto = false) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    if (oculto) {
      process.stdout.write(pergunta);
      rl._writeToOutput = () => {}; // não ecoa as teclas
      rl.question('', (r) => { rl.close(); process.stdout.write('\n'); resolve(r.trim()); });
    } else {
      rl.question(pergunta, (r) => { rl.close(); resolve(r.trim()); });
    }
  });
}

async function asaas(chave, caminho, opcoes = {}) {
  const r = await fetch(API + caminho, {
    ...opcoes,
    headers: {
      access_token: chave,
      'User-Agent': 'sistema-gestao/1.0',
      ...(opcoes.body ? { 'Content-Type': 'application/json' } : {}),
    },
  });
  const corpo = await r.json().catch(() => ({}));
  if (!r.ok) {
    const motivo = (corpo.errors || []).map((e) => e.description).join(' | ') || `status ${r.status}`;
    throw new Error(motivo);
  }
  return corpo;
}

const sqlTexto = (s) => "'" + String(s).replace(/'/g, "''") + "'";
const finalDoEndereco = (url) => String(url || '').split('/').filter(Boolean).pop() || '';

async function main() {
  const definirObrigada = process.argv[2] === 'obrigada';

  const chave = process.env.ASAAS_API_KEY
    || await perguntar('Cole a chave de API do Asaas e aperte Enter (ela não aparece na tela): ', true);
  if (!chave) { console.error('Sem chave, nada feito.'); process.exit(1); }

  // 1) Lista todos os links (de 100 em 100)
  const links = [];
  for (let offset = 0; ; offset += 100) {
    const pagina = await asaas(chave, `/paymentLinks?limit=100&offset=${offset}`);
    links.push(...(pagina.data || []));
    if (!pagina.hasMore) break;
  }
  if (!links.length) { console.log('Nenhum link de pagamento nesta conta.'); return; }

  console.log('\nLinks de pagamento da conta:\n');
  for (const l of links) {
    console.log(`  código ${l.id}  ·  ${l.name}  ·  R$ ${Number(l.value || 0).toFixed(2).replace('.', ',')}  ·  ${l.billingType}  ·  ${l.active ? 'ativo' : 'desativado'}`);
    console.log(`    ${l.url}`);
  }

  // 2) Escreve o SQL para cadastrar os links do Clube no sistema
  const linhas = [];
  for (const l of links) {
    const nomeBlack = LINKS_BLACK[finalDoEndereco(l.url)];
    if (nomeBlack) {
      linhas.push(`  (${sqlTexto(l.id)}, ${sqlTexto(nomeBlack)}, false, '${LIBERAR_EM}')`);
    } else if (Number(l.value) === 5) {
      linhas.push(`  (${sqlTexto(l.id)}, ${sqlTexto('Teste de R$ 5 · ' + l.name)}, true, null)`);
    }
  }
  if (linhas.length) {
    console.log('\nCopie e rode no SQL Editor do Supabase (banco do sistema):\n');
    console.log('insert into public.clube_links_asaas (link_id, nome, teste, liberar_em) values');
    console.log(linhas.join(',\n'));
    console.log('on conflict (link_id) do nothing;\n');
  } else {
    console.log('\nNão reconheci os links da Black nem um link de R$ 5. Confira a lista acima.\n');
  }

  // 3) Página de obrigada (só se você pediu)
  if (!definirObrigada) {
    console.log('Para definir a página de obrigada nos links da Black: node scripts/asaas-links.mjs obrigada\n');
    return;
  }
  const alvos = links.filter((l) => LINKS_BLACK[finalDoEndereco(l.url)]);
  if (!alvos.length) { console.log('Não achei os links da Black para definir a página de obrigada.'); return; }

  console.log(`Vou definir que, depois do pagamento, a pessoa vai para:\n  ${OBRIGADA}\nnos links:`);
  alvos.forEach((l) => console.log(`  · ${l.name} (${l.id})`));
  const ok = await perguntar('Confirma? Digite sim e aperte Enter: ');
  if (ok.toLowerCase() !== 'sim') { console.log('Cancelado. Nada foi alterado.'); return; }

  for (const l of alvos) {
    try {
      await asaas(chave, `/paymentLinks/${encodeURIComponent(l.id)}`, {
        method: 'PUT',
        body: JSON.stringify({ callback: { successUrl: OBRIGADA, autoRedirect: true } }),
      });
      console.log(`  feito: ${l.name}`);
    } catch (e) {
      console.log(`  NÃO deu em ${l.name}: ${e.message}`);
      console.log('  (o Asaas só aceita endereço do site cadastrado em Configurações da conta > Informações)');
    }
  }
}

main().catch((e) => { console.error('Erro:', e.message); process.exit(1); });
