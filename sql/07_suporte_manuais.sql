-- ════════════════════════════════════════════════════════════════════
-- 07_SUPORTE_MANUAIS.SQL — Prazo de suporte (início/fim) no projeto e
-- manuais em PDF por projeto (Manual de uso e Manual das ferramentas).
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em RUN.
-- Pode rodar mais de uma vez sem problema (idempotente).
-- ════════════════════════════════════════════════════════════════════

-- ──────────── 1. PROJETOS: PRAZO DE SUPORTE ────────────
-- Período de suporte do projeto, INDEPENDENTE das datas do projeto
-- (start_date/end_date). Ex.: a entrega terminou, mas o suporte segue
-- ativo por mais 3 meses. Ambas opcionais.
alter table public.projects
  add column if not exists support_start date,
  add column if not exists support_end   date;

-- ──────────── 2. DOCUMENTOS: TIPO DO ARQUIVO (kind) ────────────
-- Reaproveitamos a tabela documents e o bucket client-documents que o
-- sistema já usa. A coluna kind diferencia um documento comum de um
-- manual. Assim o upload, o download e a RLS já existentes continuam
-- valendo, sem tabela nova.
--   'documento'           = arquivo comum (valor padrão, comportamento atual)
--   'manual_uso'          = Manual de uso do projeto
--   'manual_ferramentas'  = Manual das ferramentas do projeto
alter table public.documents
  add column if not exists kind text not null default 'documento';

-- Trava de valores válidos para kind. Recria de forma idempotente e não
-- quebra linhas antigas (que já vêm com 'documento' pelo default acima).
alter table public.documents
  drop constraint if exists documents_kind_check;
alter table public.documents
  add constraint documents_kind_check
  check (kind in ('documento','manual_uso','manual_ferramentas'));

-- Cada projeto tem no máximo UM manual de cada tipo. O índice único
-- parcial garante isso só para os manuais (documentos comuns ficam livres).
create unique index if not exists uniq_manual_por_projeto
  on public.documents(project_id, kind)
  where kind in ('manual_uso','manual_ferramentas');

-- Acelera a busca dos manuais de um projeto.
create index if not exists idx_documents_kind on public.documents(project_id, kind);

-- ════════════════════════════════════════════════════════════════════
-- SEGURANÇA / RLS: nada a fazer aqui.
-- A tabela documents já tem RLS (admin_all, member_read e as policies do
-- cliente). Como os manuais são apenas linhas de documents com um kind
-- diferente, ficam automaticamente protegidos pelas mesmas regras.
-- Pronto! As tabelas estão atualizadas.
-- ════════════════════════════════════════════════════════════════════
