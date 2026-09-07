-- ════════════════════════════════════════════════════════════════════
-- 01_GESTAO_SCHEMA.SQL — Tabelas do sistema gerencial
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em RUN.
-- Pode rodar mais de uma vez sem problema (idempotente).
-- ════════════════════════════════════════════════════════════════════

-- ──────────── FUNÇÕES AUXILIARES ────────────

-- Verifica se o usuário logado é admin (usada nas políticas RLS)
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- Atualiza updated_at automaticamente
create or replace function public.set_updated_at()
returns trigger language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ──────────── TAREFAS ────────────
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  project_id uuid references public.projects(id) on delete set null,
  status text not null default 'pendente' check (status in ('pendente','em_andamento','concluida','cancelada')),
  priority text not null default 'media' check (priority in ('baixa','media','alta')),
  due_date date,
  completed_at timestamptz,
  order_num int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_tasks_due on public.tasks(due_date);
create index if not exists idx_tasks_project on public.tasks(project_id);

-- ──────────── CRM ────────────
create table if not exists public.crm_contacts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  company text,
  email text,
  phone text,
  origin text,                -- de onde veio o lead (indicação, instagram, site...)
  status text not null default 'lead' check (status in ('lead','ativo','inativo')),
  profile_id uuid references public.profiles(id) on delete set null, -- vínculo com cliente do portal
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.crm_deals (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid references public.crm_contacts(id) on delete cascade,
  title text not null,
  value numeric(12,2) not null default 0,
  stage text not null default 'novo' check (stage in ('novo','contato','proposta','negociacao','fechado','perdido')),
  expected_close date,
  project_id uuid references public.projects(id) on delete set null,
  notes text,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_deals_stage on public.crm_deals(stage);
create index if not exists idx_deals_contact on public.crm_deals(contact_id);

create table if not exists public.crm_activities (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid references public.crm_contacts(id) on delete cascade,
  deal_id uuid references public.crm_deals(id) on delete set null,
  type text not null default 'nota' check (type in ('nota','ligacao','email','reuniao','mensagem')),
  content text not null,
  activity_date timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists idx_activities_contact on public.crm_activities(contact_id);

-- ──────────── FINANCEIRO ────────────
create table if not exists public.fin_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kind text not null check (kind in ('receita','despesa')),
  color text,
  created_at timestamptz not null default now(),
  unique (name, kind)
);

create table if not exists public.fin_transactions (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('receita','despesa')),
  description text not null,
  amount numeric(12,2) not null,
  category_id uuid references public.fin_categories(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  contact_id uuid references public.crm_contacts(id) on delete set null,
  due_date date,                       -- vencimento
  paid_at date,                        -- data de pagamento/recebimento
  status text not null default 'pendente' check (status in ('pendente','pago','cancelado')),
  recurring text not null default 'nao' check (recurring in ('nao','mensal')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_fin_due on public.fin_transactions(due_date);
create index if not exists idx_fin_status on public.fin_transactions(status);

-- Categorias iniciais
insert into public.fin_categories (name, kind, color) values
  ('Projetos',      'receita', '#22A060'),
  ('Consultoria',   'receita', '#2188FF'),
  ('Outras receitas','receita', '#8B5CF6'),
  ('Ferramentas',   'despesa', '#E3B341'),
  ('Marketing',     'despesa', '#F85149'),
  ('Impostos',      'despesa', '#8B949E'),
  ('Outras despesas','despesa', '#6E7681')
on conflict (name, kind) do nothing;

-- ──────────── CONTRATOS ────────────
create table if not exists public.contract_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  body text not null,                 -- texto com variáveis: {{cliente}}, {{valor}}, {{prazo}}...
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.contracts (
  id uuid primary key default gen_random_uuid(),
  template_id uuid references public.contract_templates(id) on delete set null,
  contact_id uuid references public.crm_contacts(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  title text not null,
  body text not null,                 -- texto final já com variáveis substituídas
  variables jsonb not null default '{}',
  value numeric(12,2),
  status text not null default 'rascunho' check (status in ('rascunho','enviado','assinado','cancelado')),
  signed_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ──────────── AGENDA ────────────
create table if not exists public.agenda_events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  start_at timestamptz not null,
  end_at timestamptz,
  all_day boolean not null default false,
  type text not null default 'compromisso' check (type in ('compromisso','reuniao','entrega','pessoal')),
  contact_id uuid references public.crm_contacts(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  location text,
  done boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_agenda_start on public.agenda_events(start_at);

-- ──────────── MARKETING ────────────
create table if not exists public.mkt_metrics (
  id uuid primary key default gen_random_uuid(),
  channel text not null check (channel in ('instagram','linkedin','tiktok','youtube','site','outro')),
  metric_date date not null,
  followers int,
  reach int,
  impressions int,
  engagement int,
  leads int,
  posts int,
  notes text,
  created_at timestamptz not null default now(),
  unique (channel, metric_date)
);

-- ──────────── TRIGGERS updated_at ────────────
do $$
declare t text;
begin
  foreach t in array array['tasks','crm_contacts','crm_deals','fin_transactions','contract_templates','contracts']
  loop
    execute format('drop trigger if exists trg_%s_updated on public.%I', t, t);
    execute format('create trigger trg_%s_updated before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;

-- ──────────── RLS: SOMENTE ADMIN ────────────
do $$
declare t text;
begin
  foreach t in array array['tasks','crm_contacts','crm_deals','crm_activities','fin_categories','fin_transactions','contract_templates','contracts','agenda_events','mkt_metrics']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "admin_all" on public.%I', t);
    execute format('create policy "admin_all" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

-- Pronto! Todas as tabelas criadas com acesso restrito a admins.
