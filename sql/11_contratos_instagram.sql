-- ════════════════════════════════════════════════════════════════════
-- 11_CONTRATOS_INSTAGRAM.SQL
-- Modelos de contrato vindos de arquivo (.docx/PDF), editor com
-- formatação, e sincronização das métricas do Instagram.
--
-- COMO USAR: cole este arquivo INTEIRO no SQL Editor do Supabase e
-- clique em RUN. Pode rodar quantas vezes quiser (é idempotente).
-- ════════════════════════════════════════════════════════════════════


-- ──────────── 1. MODELOS DE CONTRATO ────────────
-- body       = texto puro. Continua existindo e continua sendo
--              preenchido, para os contratos antigos não quebrarem.
-- body_html  = a versão com formatação (negrito, listas, títulos),
--              editada no editor.
-- source_*   = o arquivo original que deu origem ao modelo, guardado
--              para você poder conferir depois de onde veio o texto.
-- var_labels = nome amigável de cada variável, ex.:
--              {"cliente": "Nome do cliente", "valor": "Valor total"}
--              Assim o formulário mostra "Nome do cliente" em vez de
--              {{cliente}}.
alter table public.contract_templates
  add column if not exists body_html   text,
  add column if not exists format      text not null default 'texto',
  add column if not exists source_path text,
  add column if not exists source_name text,
  add column if not exists source_type text,
  add column if not exists var_labels  jsonb not null default '{}'::jsonb;

alter table public.contract_templates drop constraint if exists contract_templates_format_check;
alter table public.contract_templates add constraint contract_templates_format_check
  check (format in ('texto','html'));

alter table public.contracts
  add column if not exists body_html text,
  add column if not exists pdf_path  text;


-- ──────────── 2. INSTAGRAM: DE ONDE VEIO CADA NÚMERO ────────────
-- Isto é importante: mkt_metrics tem unique(channel, metric_date), então
-- a sincronização usa UPSERT. Sem a coluna "source", uma sincronização
-- passaria por cima dos números que VOCÊ digitou à mão, sem avisar.
-- Com ela, a tela sabe o que é seu e não sobrescreve sem perguntar.
alter table public.mkt_metrics
  add column if not exists source     text not null default 'manual',
  add column if not exists synced_at  timestamptz,
  add column if not exists raw        jsonb;

alter table public.mkt_metrics drop constraint if exists mkt_metrics_source_check;
alter table public.mkt_metrics add constraint mkt_metrics_source_check
  check (source in ('manual','instagram_api','importacao'));

create index if not exists idx_mkt_source on public.mkt_metrics(channel, source);

-- Configurações da integração.
-- ⚠️ O TOKEN NÃO FICA AQUI. Ele vive só nas variáveis de ambiente da
-- Vercel (IG_ACCESS_TOKEN) e nunca chega ao navegador. Aqui ficam
-- apenas informações que não são segredo.
insert into public.app_settings (key, value) values
  ('ig_username', null),
  ('ig_last_sync', null),
  ('ig_token_expires_at', null)
on conflict (key) do nothing;


-- ──────────── 3. ARQUIVOS DA GESTÃO (bucket próprio) ────────────
-- NÃO reusamos o bucket 'client-documents': ele tem permissão de
-- leitura para membros de projeto. Modelo de contrato e PDF gerado são
-- assunto seu, então vão para um bucket separado, só do admin.
insert into storage.buckets (id, name, public)
values ('gestao-files', 'gestao-files', false)
on conflict (id) do nothing;

-- Se der erro de permissão nas duas linhas abaixo, crie a policy pela
-- interface: Storage → gestao-files → Policies → New policy.
drop policy if exists "gestao_files_admin" on storage.objects;
create policy "gestao_files_admin" on storage.objects
  for all to authenticated
  using      (bucket_id = 'gestao-files' and public.is_admin())
  with check (bucket_id = 'gestao-files' and public.is_admin());
