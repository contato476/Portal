// ════════════════════════════════════════════════════════════════════
// Função serverless (Vercel): recebe os avisos (webhooks) do Asaas e
// registra as vendas do Clube no sistema.
//
// Endereço: https://sistema.jpgestaodescomplicada.com/api/asaas-webhook
//
// O QUE ELA FAZ, EM ORDEM:
//   1. Só aceita POST.
//   2. Confere o token que o Asaas manda no cabeçalho "asaas-access-token".
//      Sem o token certo, responde 401 e não lê mais nada.
//   3. Valida o formato do aviso com zod (nunca confiar no que vem de fora).
//   4. Ignora eventos que não interessam (responde 200, para o Asaas não
//      ficar tentando de novo).
//   5. Chama a função clube_venda_ingest no banco. É ela que decide se o
//      aviso é repetido, se o link é do Clube e se a venda já existe.
//   6. Se o banco responder "falta_cliente", busca nome, e-mail e telefone
//      no Asaas (o aviso só traz o código do cliente) e chama de novo.
//
// SEGREDOS (só em variáveis de ambiente na Vercel, nunca no código):
//   ASAAS_WEBHOOK_TOKEN  o token criado na tela de Webhooks do Asaas
//   ASAAS_API_KEY        a chave de API do Asaas (para buscar o cliente)
//   CLUBE_INGEST_TOKEN   o token mostrado no fim do sql/43
// Opcional: ASAAS_API_URL (padrão: produção). Para testar no sandbox,
//   use https://api-sandbox.asaas.com/v3
//
// Documentação conferida em 11/11/2026:
//   https://docs.asaas.com/docs/sobre-os-webhooks
//   https://docs.asaas.com/docs/webhook-para-cobrancas
// ════════════════════════════════════════════════════════════════════

import { createHash, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';

// Endereço e chave PÚBLICA do banco (a mesma do assets/shared.js). Ela é
// pública por natureza: quem protege os dados é o RLS e o token da função.
const SUPABASE_URL = 'https://jvtjhfganuuefswbnbrk.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_HEWDXmsh3RwtUVAh541L_Q_UGvVickl';

const ASAAS_PADRAO = 'https://api.asaas.com/v3';

// Só estes eventos mudam alguma coisa no sistema.
// Pix manda só RECEIVED; cartão manda CONFIRMED na hora e RECEIVED 32 dias depois.
export const EVENTOS_USADOS = new Set([
  'PAYMENT_CONFIRMED',
  'PAYMENT_RECEIVED',
  'PAYMENT_REFUNDED',
  'PAYMENT_CHARGEBACK_REQUESTED',
]);

// ── Formato esperado do aviso ──
// O "envelope" vale para qualquer evento; o "pagamento" só é exigido nos
// eventos que usamos. Campos que o Asaas criar no futuro são ignorados.
const texto = (max) => z.string().trim().min(1).max(max);
const textoOpcional = (max) => z.string().trim().max(max).nullish();
const dataOpcional = z.string().regex(/^\d{4}-\d{2}-\d{2}/).nullish();

export const EnvelopeSchema = z.object({
  id: texto(200),
  event: texto(80),
});

export const AvisoSchema = EnvelopeSchema.extend({
  payment: z.object({
    id: texto(100),
    customer: textoOpcional(100),
    installment: textoOpcional(100),
    paymentLink: textoOpcional(100),
    value: z.number().finite().nonnegative(),
    netValue: z.number().finite().nullish(),
    billingType: texto(40),
    confirmedDate: dataOpcional,
    paymentDate: dataOpcional,
    clientPaymentDate: dataOpcional,
  }),
});

// O que usamos da ficha do cliente e do parcelamento no Asaas
const ClienteSchema = z.object({
  name: textoOpcional(200),
  email: textoOpcional(200),
  phone: textoOpcional(40),
  mobilePhone: textoOpcional(40),
});
const ParcelamentoSchema = z.object({
  value: z.number().finite().nonnegative(),
  netValue: z.number().finite().nullish(),
  installmentCount: z.number().int().positive(),
});

// Compara dois textos sem "vazar" pelo tempo de resposta quantos
// caracteres batem. Passar os dois pelo SHA-256 deixa os tamanhos iguais.
export function tokensIguais(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || !a || !b) return false;
  const ha = createHash('sha256').update(a).digest();
  const hb = createHash('sha256').update(b).digest();
  return timingSafeEqual(ha, hb);
}

const FORMAS = { PIX: 'pix', CREDIT_CARD: 'cartao', BOLETO: 'boleto' };

// Transforma o aviso do Asaas nos campos que o banco espera
export function montarDados(aviso) {
  const p = aviso.payment;
  const dia = p.clientPaymentDate || p.paymentDate || p.confirmedDate || null;
  return {
    evento_id: aviso.id,
    evento: aviso.event,
    pagamento_id: p.id,
    parcelamento_id: p.installment || null,
    cliente_id: p.customer || null,
    link_id: p.paymentLink || null,
    forma: FORMAS[p.billingType] || 'outro',
    valor: p.value,
    valor_liquido: p.netValue ?? null,
    pago_em: dia ? dia.slice(0, 10) : null,
  };
}

// Chama a função do banco. Quem autoriza é o p_token, conferido lá dentro.
async function chamarBanco(dados) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/clube_venda_ingest`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
    },
    body: JSON.stringify({ p_token: process.env.CLUBE_INGEST_TOKEN, p_dados: dados }),
  });
  if (!r.ok) throw new Error(`banco respondeu ${r.status}`);
  return r.json();
}

// Consulta o Asaas com a chave de API. O "id" vem do próprio aviso, já
// validado, e vai codificado na URL.
async function buscarNoAsaas(caminho, id) {
  const base = (process.env.ASAAS_API_URL || ASAAS_PADRAO).replace(/\/+$/, '');
  const r = await fetch(`${base}/${caminho}/${encodeURIComponent(id)}`, {
    headers: {
      access_token: process.env.ASAAS_API_KEY,
      'User-Agent': 'sistema-gestao/1.0',
    },
  });
  if (!r.ok) throw new Error(`Asaas respondeu ${r.status} em ${caminho}`);
  return r.json();
}

export default async function handler(req, res) {
  // Resposta nunca fica guardada em cache nem aparece em busca
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Robots-Tag', 'noindex');

  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Método não permitido' });
  }

  const { ASAAS_WEBHOOK_TOKEN, ASAAS_API_KEY, CLUBE_INGEST_TOKEN } = process.env;
  if (!ASAAS_WEBHOOK_TOKEN || !ASAAS_API_KEY || !CLUBE_INGEST_TOKEN) {
    console.error('asaas-webhook: falta variável de ambiente na Vercel');
    return res.status(500).json({ error: 'Serviço indisponível' });
  }

  // 1) Quem está chamando é mesmo o Asaas?
  if (!tokensIguais(req.headers['asaas-access-token'], ASAAS_WEBHOOK_TOKEN)) {
    return res.status(401).json({ error: 'Não autorizado' });
  }

  // 2) O aviso tem o formato esperado?
  const envelope = EnvelopeSchema.safeParse(req.body);
  if (!envelope.success) {
    return res.status(400).json({ error: 'Aviso em formato inesperado' });
  }
  // Evento que não usamos: responde 200 para o Asaas seguir a fila
  if (!EVENTOS_USADOS.has(envelope.data.event)) {
    return res.status(200).json({ ok: true, status: 'ignorado' });
  }
  const aviso = AvisoSchema.safeParse(req.body);
  if (!aviso.success) {
    // Loga só o nome dos campos com problema, nunca o conteúdo
    console.error('asaas-webhook: aviso inválido', aviso.error.issues.map((i) => i.path.join('.')));
    return res.status(400).json({ error: 'Aviso em formato inesperado' });
  }

  try {
    const dados = montarDados(aviso.data);

    // 3) Primeira chamada: o banco diz se é repetido, ignorado ou venda nova
    let resposta = await chamarBanco(dados);

    // 4) Venda nova do Clube: busca os dados da pessoa e grava
    if (resposta && resposta.status === 'falta_cliente') {
      if (!dados.cliente_id) throw new Error('aviso sem código do cliente');
      const cliente = ClienteSchema.parse(await buscarNoAsaas('customers', dados.cliente_id));

      const completos = {
        ...dados,
        nome: cliente.name || '',
        email: cliente.email || null,
        telefone: cliente.mobilePhone || cliente.phone || null,
        parcelas: null,
      };

      // No cartão parcelado, o aviso traz o valor de UMA parcela. O total e
      // a quantidade de parcelas vêm da ficha do parcelamento.
      if (dados.parcelamento_id) {
        const parc = ParcelamentoSchema.parse(await buscarNoAsaas('installments', dados.parcelamento_id));
        completos.valor = parc.value;
        completos.valor_liquido = parc.netValue ?? null;
        completos.parcelas = parc.installmentCount;
      }

      resposta = await chamarBanco(completos);
    }

    return res.status(200).json({ ok: true, status: (resposta && resposta.status) || 'ok' });
  } catch (e) {
    // Erro nosso ou do Asaas: responde 500 para o Asaas tentar de novo mais
    // tarde. A mensagem detalhada fica só no log da Vercel.
    console.error('asaas-webhook: falha ao processar', e && e.message);
    return res.status(500).json({ error: 'Não foi possível processar agora' });
  }
}
