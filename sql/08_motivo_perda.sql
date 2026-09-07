-- ════════════════════════════════════════════════════════════════════
-- 08_MOTIVO_PERDA.SQL — Registra o motivo da perda de um negócio no CRM
-- e permite usá-lo como indicador no dashboard.
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em RUN.
-- Pode rodar mais de uma vez sem problema (idempotente).
-- ════════════════════════════════════════════════════════════════════

-- ──────────── CRM: MOTIVO DA PERDA ────────────
-- lost_reason = motivo padronizado (ex.: 'preco', 'concorrente'...). Fica
-- como texto livre, controlado pela aplicação (mesma estratégia dos status
-- do projeto), para você poder ajustar a lista de motivos sem mexer no banco.
-- lost_note   = detalhe opcional digitado na hora (ex.: nome do concorrente).
alter table public.crm_deals
  add column if not exists lost_reason text,
  add column if not exists lost_note   text;

-- Acelera o agrupamento por motivo nos indicadores do dashboard.
create index if not exists idx_crm_deals_lost_reason
  on public.crm_deals(lost_reason)
  where stage = 'perdido';

-- ════════════════════════════════════════════════════════════════════
-- SEGURANÇA / RLS: nada a fazer. crm_deals já é uma tabela existente e
-- as novas colunas herdam as policies que já protegem a tabela.
-- Pronto!
-- ════════════════════════════════════════════════════════════════════
