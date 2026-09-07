-- ════════════════════════════════════════════════════════════════════
-- 06_LINK_ACESSO.SQL — Novo tipo de combinado "Links de acesso".
-- Guarda a URL de um link (painel, drive, sistema, etc.) direto no
-- combinado, num campo próprio separado da descrição.
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em RUN.
-- Pode rodar mais de uma vez sem problema (idempotente).
-- ════════════════════════════════════════════════════════════════════

-- Coluna nova, nula por padrão. Só os combinados do tipo "link" vão usá-la.
-- A tabela agreements já tem RLS ativo, então a coluna nova herda as mesmas
-- policies automaticamente — não precisa mexer em permissão e não há risco
-- de recursão, porque nenhuma policy nova está sendo criada.
alter table public.agreements
  add column if not exists link_url text;
