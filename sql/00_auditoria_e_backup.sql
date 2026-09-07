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
-- ✅ FEITO EM 07/09/2026: o arquivo sql/00_schema_base.sql já existe,
-- gerado a partir do resultado deste bloco. Rode de novo só quando
-- criar uma tabela nova ou uma coluna nova pelo painel — aí atualize
-- o 00_schema_base.sql com o resultado.
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
-- BLOCO 6 — DELETE DE "documents": VERIFICADO EM 07/09/2026, ESTÁ OK
--
-- ⚠️ NÃO HÁ NADA A FAZER AQUI. Deixo o registro para você não precisar
-- reinvestigar isso depois.
--
-- A dúvida era: o cliente consegue apagar documento que VOCÊ subiu?
-- Resposta: NÃO. A policy documents_delete, criada pelo painel e vista
-- no BLOCO 4, já diz exatamente o certo:
--
--   is_admin()
--   OR (uploaded_by = auth.uid()      <- só o que ele mesmo enviou
--       AND project_id IS NOT NULL
--       AND o usuário é membro daquele projeto)
--
-- Ou seja: você apaga tudo, o cliente apaga só o que ele enviou.
-- É o comportamento correto, e ele já estava assim antes desta revisão.
--
-- (A policy só não estava versionada em nenhum arquivo sql/ — isso sim
--  era o risco, e está resolvido pelo BLOCO 7 abaixo.)
-- ════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════
-- BLOCO 7 — BACKUP DAS PERMISSÕES (RLS)  ⚠️ IMPORTANTE
--
-- POR QUÊ: várias policies foram criadas pelo painel do Supabase e não
-- existem em nenhum arquivo aqui. Sem elas, um banco reconstruído fica
-- com as tabelas certas e ninguém conseguindo ler nada.
--
-- O QUE FAZER: rode e cole o resultado da coluna "ddl" no fim do
-- arquivo sql/00_schema_base.sql.
-- ════════════════════════════════════════════════════════════════════
select
  tablename as tabela,
  'drop policy if exists ' || quote_ident(policyname) || ' on public.' || quote_ident(tablename) ||
  chr(10) ||
  'create policy ' || quote_ident(policyname) || ' on public.' || quote_ident(tablename) ||
  ' as ' || permissive ||
  ' for ' || cmd ||
  ' to ' || array_to_string(roles, ', ') ||
  coalesce(chr(10) || '  using (' || qual || ')', '') ||
  coalesce(chr(10) || '  with check (' || with_check || ')', '') as ddl
from pg_policies
where schemaname = 'public'
order by tablename, policyname;
