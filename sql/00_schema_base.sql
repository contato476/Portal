-- ════════════════════════════════════════════════════════════════════
-- 00_SCHEMA_BASE.SQL — as tabelas do PORTAL DO CLIENTE
--
-- ⚠️ VOCÊ NÃO PRECISA RODAR ESTE ARQUIVO AGORA.
-- Ele é o seu seguro contra perda total: estas tabelas foram criadas
-- direto pelo painel do Supabase e não existiam em lugar nenhum do
-- código. Se o projeto do Supabase for perdido, ou se você quiser
-- montar um ambiente de teste, é este arquivo que reconstrói a base.
--
-- Gerado em 07/09/2026 a partir do banco real (blocos 1, 2 e 3 do
-- arquivo 00_auditoria_e_backup.sql). Refaça sempre que criar uma
-- tabela nova ou uma coluna nova pelo painel.
--
-- ORDEM PARA RECONSTRUIR DO ZERO:
--   1. Este arquivo (00)
--   2. 01_gestao_schema.sql   (cria crm_contacts, tasks, financeiro...)
--   3. Este arquivo de novo   (agora a chave projects → crm_contacts entra)
--   4. Os arquivos 02 a 10, em ordem
--   5. As POLICIES de RLS — veja o aviso no fim do arquivo
--
-- É idempotente: rodar mais de uma vez não estraga nada.
-- ════════════════════════════════════════════════════════════════════


-- ──────────── 1. TABELAS ────────────

create table if not exists public.profiles (
  id         uuid not null,
  name       text not null,
  company    text,
  phone      text,
  role       text not null default 'client'::text,
  created_at timestamptz default now()
);

create table if not exists public.projects (
  id             uuid not null default gen_random_uuid(),
  client_id      uuid,
  name           text not null,
  description    text,
  status         text default 'pre_inicio'::text,
  start_date     date,
  end_date       date,
  color          text default '#1A7A4A'::text,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now(),
  contact_id     uuid,
  support_start  date,
  support_end    date,
  priority       text default 'media'::text,
  internal_notes text,
  archived       boolean not null default false,
  estimate_hours numeric(8,2),
  hourly_rate    numeric(10,2)
);

create table if not exists public.allowed_emails (
  id         uuid not null default gen_random_uuid(),
  email      text not null,
  invited_by uuid,
  used       boolean default false,
  created_at timestamptz default now()
);

create table if not exists public.project_members (
  id         uuid not null default gen_random_uuid(),
  project_id uuid not null,
  user_id    uuid not null,
  role       text not null default 'member'::text,
  added_by   uuid,
  created_at timestamptz default now()
);

create table if not exists public.project_invites (
  id          uuid not null default gen_random_uuid(),
  project_id  uuid not null,
  email       text not null,
  role        text not null default 'member'::text,
  invited_by  uuid,
  accepted_at timestamptz,
  created_at  timestamptz default now()
);

create table if not exists public.checklist_items (
  id          uuid not null default gen_random_uuid(),
  project_id  uuid not null,
  category    text not null,
  title       text not null,
  description text,
  urgent      boolean default false,
  order_num   integer default 0,
  created_at  timestamptz default now()
);

create table if not exists public.checklist_states (
  id             uuid not null default gen_random_uuid(),
  user_id        uuid not null,
  item_id        uuid not null,
  done           boolean default false,
  updated_at     timestamptz default now(),
  project_id     uuid,
  sent_by_client boolean default false,
  sent_at        timestamptz,
  approved_at    timestamptz,
  approved_by    uuid,
  rejection_note text,
  rejected_at    timestamptz
);

create table if not exists public.project_phases (
  id          uuid not null default gen_random_uuid(),
  project_id  uuid not null,
  title       text not null,
  description text,
  start_date  date,
  end_date    date,
  status      text default 'aguardando'::text,
  order_num   integer default 0,
  color       text default '#1A7A4A'::text,
  created_at  timestamptz default now()
);

create table if not exists public.agreements (
  id              uuid not null default gen_random_uuid(),
  project_id      uuid not null,
  type            text not null,
  title           text not null,
  description     text,
  meeting_date    date,
  start_date      date,
  end_date        date,
  status          text default 'pendente'::text,
  created_by      uuid not null,
  created_by_role text not null,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now(),
  link_url        text
);

create table if not exists public.documents (
  id          uuid not null default gen_random_uuid(),
  user_id     uuid,
  uploaded_by uuid,
  name        text not null,
  path        text not null,
  size        bigint,
  type        text,
  category    text default 'geral'::text,
  created_at  timestamptz default now(),
  project_id  uuid,
  kind        text not null default 'documento'::text
);


-- ──────────── 2. CHAVES E REGRAS ────────────
-- O Postgres não tem "add constraint if not exists", então a função
-- abaixo confere antes de criar. Assim o arquivo pode rodar de novo.
create or replace function public.add_constraint_se_faltar(
  p_tabela text, p_nome text, p_definicao text
) returns void language plpgsql as $fn$
begin
  if not exists (select 1 from pg_constraint where conname = p_nome) then
    execute format('alter table public.%I add constraint %I %s', p_tabela, p_nome, p_definicao);
  end if;
end $fn$;

-- Chaves primárias
select public.add_constraint_se_faltar('profiles',         'profiles_pkey',         'PRIMARY KEY (id)');
select public.add_constraint_se_faltar('projects',         'projects_pkey',         'PRIMARY KEY (id)');
select public.add_constraint_se_faltar('allowed_emails',   'allowed_emails_pkey',   'PRIMARY KEY (id)');
select public.add_constraint_se_faltar('project_members',  'project_members_pkey',  'PRIMARY KEY (id)');
select public.add_constraint_se_faltar('project_invites',  'project_invites_pkey',  'PRIMARY KEY (id)');
select public.add_constraint_se_faltar('checklist_items',  'checklist_items_pkey',  'PRIMARY KEY (id)');
select public.add_constraint_se_faltar('checklist_states', 'checklist_states_pkey', 'PRIMARY KEY (id)');
select public.add_constraint_se_faltar('project_phases',   'project_phases_pkey',   'PRIMARY KEY (id)');
select public.add_constraint_se_faltar('agreements',       'agreements_pkey',       'PRIMARY KEY (id)');
select public.add_constraint_se_faltar('documents',        'documents_pkey',        'PRIMARY KEY (id)');

-- Combinações que não podem repetir
select public.add_constraint_se_faltar('allowed_emails',   'allowed_emails_email_key',                'UNIQUE (email)');
select public.add_constraint_se_faltar('project_members',  'project_members_project_id_user_id_key',  'UNIQUE (project_id, user_id)');
select public.add_constraint_se_faltar('project_invites',  'project_invites_project_id_email_key',    'UNIQUE (project_id, email)');
select public.add_constraint_se_faltar('checklist_states', 'checklist_states_project_id_item_id_key', 'UNIQUE (project_id, item_id)');

-- Valores aceitos em cada campo de texto controlado
select public.add_constraint_se_faltar('profiles',        'profiles_role_check',              $$CHECK (role = ANY (ARRAY['admin'::text, 'client'::text]))$$);
select public.add_constraint_se_faltar('project_members', 'project_members_role_check',       $$CHECK (role = ANY (ARRAY['owner'::text, 'member'::text]))$$);
select public.add_constraint_se_faltar('project_invites', 'project_invites_role_check',       $$CHECK (role = ANY (ARRAY['owner'::text, 'member'::text]))$$);
select public.add_constraint_se_faltar('project_phases',  'project_phases_status_check',      $$CHECK (status = ANY (ARRAY['aguardando'::text, 'em_andamento'::text, 'concluido'::text, 'pausado'::text]))$$);
select public.add_constraint_se_faltar('agreements',      'agreements_status_check',          $$CHECK (status = ANY (ARRAY['pendente'::text, 'em_andamento'::text, 'concluido'::text, 'cancelado'::text]))$$);
select public.add_constraint_se_faltar('agreements',      'agreements_type_check',            $$CHECK (type = ANY (ARRAY['reuniao'::text, 'sprint'::text, 'alteracao'::text, 'decisao'::text, 'proximos_passos'::text]))$$);
select public.add_constraint_se_faltar('agreements',      'agreements_created_by_role_check', $$CHECK (created_by_role = ANY (ARRAY['admin'::text, 'client'::text]))$$);
select public.add_constraint_se_faltar('documents',       'documents_kind_check',             $$CHECK (kind = ANY (ARRAY['documento'::text, 'manual_uso'::text, 'manual_ferramentas'::text]))$$);

-- Ligações entre tabelas
select public.add_constraint_se_faltar('profiles',         'profiles_id_fkey',                  'FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('projects',         'projects_client_id_fkey',           'FOREIGN KEY (client_id) REFERENCES auth.users(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('allowed_emails',   'allowed_emails_invited_by_fkey',    'FOREIGN KEY (invited_by) REFERENCES auth.users(id)');
select public.add_constraint_se_faltar('project_members',  'project_members_project_id_fkey',   'FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('project_members',  'project_members_user_id_fkey',      'FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('project_members',  'project_members_added_by_fkey',     'FOREIGN KEY (added_by) REFERENCES auth.users(id)');
select public.add_constraint_se_faltar('project_invites',  'project_invites_project_id_fkey',   'FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('project_invites',  'project_invites_invited_by_fkey',   'FOREIGN KEY (invited_by) REFERENCES auth.users(id)');
select public.add_constraint_se_faltar('checklist_items',  'checklist_items_project_id_fkey',   'FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('checklist_states', 'checklist_states_project_id_fkey',  'FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('checklist_states', 'checklist_states_item_id_fkey',     'FOREIGN KEY (item_id) REFERENCES public.checklist_items(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('checklist_states', 'checklist_states_user_id_fkey',     'FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('checklist_states', 'checklist_states_approved_by_fkey', 'FOREIGN KEY (approved_by) REFERENCES auth.users(id)');
select public.add_constraint_se_faltar('project_phases',   'project_phases_project_id_fkey',    'FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('agreements',       'agreements_project_id_fkey',        'FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('agreements',       'agreements_created_by_fkey',        'FOREIGN KEY (created_by) REFERENCES auth.users(id)');
select public.add_constraint_se_faltar('documents',        'documents_project_id_fkey',         'FOREIGN KEY (project_id) REFERENCES public.projects(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('documents',        'documents_user_id_fkey',            'FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE');
select public.add_constraint_se_faltar('documents',        'documents_uploaded_by_fkey',        'FOREIGN KEY (uploaded_by) REFERENCES auth.users(id)');

-- projects → crm_contacts só existe depois do 01_gestao_schema.sql.
-- Por isso fica separado: se a tabela ainda não existe, é pulado, e
-- entra quando você rodar este arquivo de novo depois do 01.
do $do$
begin
  if to_regclass('public.crm_contacts') is not null then
    perform public.add_constraint_se_faltar('projects','projects_contact_id_fkey',
      'FOREIGN KEY (contact_id) REFERENCES public.crm_contacts(id) ON DELETE SET NULL');
  end if;
end $do$;


-- ──────────── 3. ÍNDICES ────────────
-- (os índices de chave primária e de UNIQUE nascem junto das regras acima)
create index if not exists idx_projects_client          on public.projects(client_id);
create index if not exists idx_projects_contact         on public.projects(contact_id);
create index if not exists idx_projects_archived        on public.projects(archived);
create index if not exists idx_members_project          on public.project_members(project_id);
create index if not exists idx_members_user             on public.project_members(user_id);
create index if not exists idx_invites_project          on public.project_invites(project_id);
create index if not exists idx_invites_email            on public.project_invites(lower(email));
create index if not exists idx_checklist_items_project  on public.checklist_items(project_id);
create index if not exists idx_checklist_states_project on public.checklist_states(project_id);
create index if not exists idx_checklist_states_user    on public.checklist_states(user_id);
create index if not exists idx_phases_project           on public.project_phases(project_id);
create index if not exists idx_agreements_project       on public.agreements(project_id);
create index if not exists idx_agreements_created       on public.agreements(created_at desc);
create index if not exists idx_documents_project        on public.documents(project_id);
create index if not exists idx_documents_user           on public.documents(user_id);
create index if not exists idx_documents_kind           on public.documents(project_id, kind);
create unique index if not exists uniq_manual_por_projeto
  on public.documents(project_id, kind)
  where kind in ('manual_uso','manual_ferramentas');


-- ════════════════════════════════════════════════════════════════════
-- ⚠️ O QUE ESTE ARQUIVO NÃO TEM: AS PERMISSÕES (RLS)
--
-- As tabelas acima nascem SEM policy nenhuma — e sem policy, com RLS
-- ligado, ninguém lê nada. Numa reconstrução de verdade você precisa
-- também das permissões, que vêm de dois lugares:
--
--   · as versionadas: arquivos sql/03, sql/04, sql/09 e sql/10
--   · as criadas pelo painel: exporte com o BLOCO 7 do arquivo
--     00_auditoria_e_backup.sql e salve o resultado aqui embaixo
--
-- Ligue o RLS nas dez tabelas antes de aplicar as policies:
-- ════════════════════════════════════════════════════════════════════
do $do$
declare t text;
begin
  foreach t in array array['profiles','projects','allowed_emails','project_members',
                           'project_invites','checklist_items','checklist_states',
                           'project_phases','agreements','documents']
  loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $do$;
