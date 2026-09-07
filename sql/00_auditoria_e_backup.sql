-- ════════════════════════════════════════════════════════════════════
-- 00_AUDITORIA_E_BACKUP.SQL
--
-- Este arquivo NÃO altera nada. São consultas de conferência para você
-- rodar de vez em quando no SQL Editor do Supabase.
--
-- ⚠️ COMO RODAR: um bloco por vez. Selecione com o mouse só o bloco
-- que você quer, e clique em RUN. Se colar o arquivo inteiro e rodar
-- de uma vez, o editor do Supabase se perde entre as consultas.
-- ════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════
-- BLOCO 1 — BACKUP DO SCHEMA BASE  ⚠️ IMPORTANTE
--
-- POR QUÊ: as tabelas mais centrais do sistema (projects, profiles,
-- documents, agreements, checklist_items, checklist_states,
-- project_phases, project_members, project_invites, allowed_emails)
-- foram criadas direto pelo painel do Supabase, e NÃO existem em
-- nenhum arquivo aqui na pasta sql/. Os arquivos 01 a 09 só ALTERAM
-- essas tabelas.
--
-- Isso significa que hoje, se o projeto do Supabase for perdido ou
-- você quiser montar um ambiente de teste, o sistema é IRRECUPERÁVEL.
--
-- O QUE FAZER: selecione daqui até o final do bloco, rode, copie o
-- resultado da coluna "ddl" e salve num arquivo novo chamado
-- sql/00_schema_base.sql aqui na pasta. Refaça sempre que criar uma
-- tabela nova pelo painel.
--
-- Obs.: o resultado sai sem o ponto e vírgula no fim de cada comando —
-- acrescente ao colar no arquivo.
-- ════════════════════════════════════════════════════════════════════
select
  c.relname as tabela,
  'create table if not exists public.' || c.relname || ' (' || chr(10) ||
  string_agg(
    '  ' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod) ||
    coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '') ||
    case when a.attnotnull then ' not null' else '' end,
    ',' || chr(10) order by a.attnum
  ) || chr(10) || ')' as ddl
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relname in ('profiles','projects','allowed_emails','project_members',
                    'project_invites','checklist_items','checklist_states',
                    'project_phases','agreements','documents')
group by c.relname
order by c.relname;


-- ════════════════════════════════════════════════════════════════════
-- BLOCO 2 — CHAVES E ÍNDICES DESSAS TABELAS
-- Complemento do Bloco 1: copie o resultado para o mesmo arquivo.
-- ════════════════════════════════════════════════════════════════════
select tablename as tabela, indexdef as ddl
from pg_indexes
where schemaname = 'public'
  and tablename in ('profiles','projects','allowed_emails','project_members',
                    'project_invites','checklist_items','checklist_states',
                    'project_phases','agreements','documents')
order by tablename, indexname;


-- ════════════════════════════════════════════════════════════════════
-- BLOCO 3 — CHAVES ESTRANGEIRAS
-- Terceira parte do backup do schema.
-- ════════════════════════════════════════════════════════════════════
select
  conrelid::regclass::text as tabela,
  conname as nome,
  pg_get_constraintdef(oid) as definicao
from pg_constraint
where connamespace = 'public'::regnamespace
  and contype in ('f','p','u','c')
  and conrelid::regclass::text in ('profiles','projects','allowed_emails','project_members',
                    'project_invites','checklist_items','checklist_states',
                    'project_phases','agreements','documents')
order by tabela, contype, conname;


-- ════════════════════════════════════════════════════════════════════
-- BLOCO 4 — AUDITORIA DAS PERMISSÕES DE "documents"  ⚠️ IMPORTANTE
--
-- POR QUÊ: no portal, o cliente consegue apagar documento
-- (portal.html, botão de excluir). Mas o arquivo sql/04 só criou
-- policies de LEITURA (member_read) e de INSERÇÃO (member_insert_docs)
-- para o cliente — não existe policy de DELETE versionada aqui.
--
-- Ou seja, uma de duas coisas está acontecendo:
--   (a) o botão de excluir do cliente falha em silêncio; ou
--   (b) existe uma policy antiga, criada pelo painel e não versionada,
--       e ela pode estar ampla demais — deixando o cliente apagar
--       documento que VOCÊ subiu.
--
-- documents é a única tabela em que um cliente escreve no seu banco.
-- Rode o bloco e me mostre o resultado antes de decidir.
-- ════════════════════════════════════════════════════════════════════
select
  policyname as policy,
  cmd        as operacao,
  roles      as papeis,
  qual       as condicao_leitura,
  with_check as condicao_escrita
from pg_policies
where schemaname = 'public' and tablename = 'documents'
order by cmd, policyname;


-- ════════════════════════════════════════════════════════════════════
-- BLOCO 5 — RAIO-X GERAL DE RLS
-- Confere se toda tabela pública tem RLS ligado e quantas policies tem.
-- Qualquer linha com rls_ligado = false é uma tabela exposta.
-- ════════════════════════════════════════════════════════════════════
select
  c.relname as tabela,
  c.relrowsecurity as rls_ligado,
  count(p.policyname) as qtd_policies
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policies p on p.schemaname = 'public' and p.tablename = c.relname
where n.nspname = 'public' and c.relkind = 'r'
group by c.relname, c.relrowsecurity
order by c.relrowsecurity, c.relname;


-- ════════════════════════════════════════════════════════════════════
-- BLOCO 6 — CORREÇÃO SUGERIDA PARA O DELETE DE "documents"
--
-- ⚠️ Rode SÓ DEPOIS de olhar o resultado do BLOCO 4.
-- Este é o único bloco do arquivo que ALTERA alguma coisa, e por isso
-- está comentado. Para usar, tire os "--" do começo das linhas.
--
-- O que ele faz: garante que um cliente só possa apagar documento que
-- ELE MESMO enviou, nunca os que você enviou.
-- ════════════════════════════════════════════════════════════════════
-- drop policy if exists "member_delete_own" on public.documents;
--
-- create policy "member_delete_own" on public.documents
--   for delete to authenticated
--   using (
--     public.is_member(project_id)
--     and user_id = auth.uid()
--     and coalesce(uploaded_by, '') <> 'admin'
--   );
