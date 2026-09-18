-- ════════════════════════════════════════════════════════════════════
-- 18_CHECKLIST_ARQUIVOS.SQL
-- O cliente envia o arquivo direto na linha do item do checklist.
--
-- POR QUÊ ISTO EXISTE: antes o cliente mandava tudo pela aba
-- Documentos e depois voltava ao checklist para "marcar como enviado".
-- Você recebia uma pilha de arquivos soltos e tinha que adivinhar qual
-- era o logotipo, qual era o manual de marca etc.
--
-- COMO FUNCIONA: o arquivo continua sendo uma linha de documents (mesmo
-- bucket, mesmo download, mesma RLS). A única novidade é a coluna
-- checklist_item_id, que diz "este arquivo responde a este item".
-- Documentos sem item (null) continuam sendo o envio livre da aba
-- Documentos — para o que está fora do checklist.
--
-- Se o item for apagado, o arquivo NÃO some: só perde o vínculo e
-- continua na aba Documentos.
--
-- COMO USAR: cole o arquivo inteiro no SQL Editor e clique em RUN.
-- É idempotente.
-- ════════════════════════════════════════════════════════════════════

alter table public.documents
  add column if not exists checklist_item_id uuid
  references public.checklist_items(id) on delete set null;

create index if not exists idx_documents_checklist_item
  on public.documents(checklist_item_id)
  where checklist_item_id is not null;

-- ════════════════════════════════════════════════════════════════════
-- SEGURANÇA / RLS: nada a fazer aqui.
-- As policies de documents (member_insert_docs, member_read, admin_all)
-- já valem para a linha inteira, inclusive a coluna nova.
-- ════════════════════════════════════════════════════════════════════
