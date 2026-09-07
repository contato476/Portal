-- ════════════════════════════════════════════════════════════════════
-- 09_PROJETOS_TEMPO.SQL
-- Subtarefas, marcos internos do projeto, pedidos de ajuste e
-- controle de tempo (cronômetro).
--
-- COMO USAR: cole este arquivo INTEIRO no SQL Editor do Supabase e
-- clique em RUN. Pode rodar quantas vezes quiser (é idempotente).
-- ════════════════════════════════════════════════════════════════════

-- ──────────── 1. TAREFAS: SUBTAREFAS E BARRA NA TIMELINE ────────────
-- parent_task_id preenchido = esta linha é uma SUBTAREFA da tarefa pai.
-- on delete cascade: apagar a tarefa pai apaga as subtarefas junto.
alter table public.tasks
  add column if not exists parent_task_id uuid references public.tasks(id) on delete cascade,
  add column if not exists start_date date,          -- início (desenha a barra na timeline)
  add column if not exists estimate_minutes int;     -- estimativa, p/ comparar com o realizado

create index if not exists idx_tasks_parent on public.tasks(parent_task_id);

-- Só 1 nível de aninhamento: subtarefa não pode ter subtarefa.
-- (Com aninhamento livre o kanban e a timeline ficam ambíguos.)
create or replace function public.tasks_max_um_nivel()
returns trigger language plpgsql as $fn$
declare v_avo uuid;
begin
  if new.parent_task_id is null then return new; end if;
  if new.parent_task_id = new.id then
    raise exception 'Uma tarefa não pode ser subtarefa dela mesma';
  end if;
  select parent_task_id into v_avo from public.tasks where id = new.parent_task_id;
  if v_avo is not null then
    raise exception 'Subtarefa não pode ter subtarefa (só 1 nível)';
  end if;
  return new;
end $fn$;

drop trigger if exists trg_tasks_max_um_nivel on public.tasks;
create trigger trg_tasks_max_um_nivel
  before insert or update of parent_task_id on public.tasks
  for each row execute function public.tasks_max_um_nivel();


-- ──────────── 2. PROJETOS: CAMPOS INTERNOS DE GESTÃO ────────────
-- Estes campos NÃO aparecem no portal do cliente: o portal.html lê
-- projects mas só renderiza nome, status e datas.
alter table public.projects
  add column if not exists priority       text default 'media',  -- baixa/media/alta
  add column if not exists internal_notes text,                  -- anotações só suas
  add column if not exists archived       boolean not null default false,
  add column if not exists estimate_hours numeric(8,2),          -- horas previstas
  add column if not exists hourly_rate    numeric(10,2);         -- valor/hora p/ rentabilidade

create index if not exists idx_projects_archived on public.projects(archived);


-- ──────────── 3. MARCOS INTERNOS DO PROJETO ────────────
-- Proposital: tabela SEPARADA de project_phases.
-- project_phases é o cronograma que o CLIENTE vê no portal (policy
-- member_read do sql/04). project_milestones é só sua, na gestão.
create table if not exists public.project_milestones (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects(id) on delete cascade,
  title       text not null,
  description text,
  due_date    date,
  done        boolean not null default false,
  done_at     timestamptz,
  order_num   int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists idx_milestones_project on public.project_milestones(project_id, order_num);


-- ──────────── 4. PEDIDOS DE AJUSTE (REVISÕES) ────────────
-- Cada pedido de ajuste do cliente vira uma linha aqui, com tempo próprio.
-- INTERNO: sem policy de member, então o cliente nunca lê esta tabela.
create table if not exists public.revision_requests (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects(id) on delete cascade,
  task_id        uuid references public.tasks(id) on delete set null,
  number         int,                              -- "ajuste nº 3 deste projeto"
  title          text not null,
  description    text,
  requested_by   text,                             -- quem pediu
  channel        text not null default 'whatsapp'
                 check (channel in ('whatsapp','email','reuniao','portal','outro')),
  requested_at   date not null default current_date,
  status         text not null default 'aberto'
                 check (status in ('aberto','em_andamento','concluido','recusado')),
  priority       text not null default 'media'
                 check (priority in ('baixa','media','alta')),
  is_billable    boolean not null default false,   -- está no escopo ou é cobrável?
  charged_amount numeric(12,2),
  scope_note     text,                             -- por que é (ou não é) escopo
  completed_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists idx_revisions_project on public.revision_requests(project_id, status);

-- Numeração automática por projeto (ajuste #1, #2, #3...).
create or replace function public.set_revision_number()
returns trigger language plpgsql as $fn$
begin
  if new.number is null then
    select coalesce(max(number),0)+1 into new.number
      from public.revision_requests where project_id = new.project_id;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_revision_number on public.revision_requests;
create trigger trg_revision_number before insert on public.revision_requests
  for each row execute function public.set_revision_number();


-- ──────────── 5. CONTROLE DE TEMPO ────────────
-- Uma linha por sessão de trabalho. ended_at NULO = cronômetro RODANDO.
-- kind diz se o tempo foi num projeto, num ajuste, ou geral.
create table if not exists public.time_entries (
  id               uuid primary key default gen_random_uuid(),
  project_id       uuid references public.projects(id) on delete set null,
  task_id          uuid references public.tasks(id) on delete set null,
  revision_id      uuid references public.revision_requests(id) on delete set null,
  kind             text not null default 'projeto'
                   check (kind in ('projeto','ajuste','geral')),
  description      text,
  started_at       timestamptz not null default now(),
  ended_at         timestamptz,
  duration_seconds int not null default 0,   -- calculado pelo trigger ao parar
  source           text not null default 'timer' check (source in ('timer','manual')),
  needs_review     boolean not null default false,  -- true quando passou de 12h
  billable         boolean not null default true,
  created_at       timestamptz not null default now()
);
create index if not exists idx_time_project  on public.time_entries(project_id, started_at desc);
create index if not exists idx_time_revision on public.time_entries(revision_id);
create index if not exists idx_time_task     on public.time_entries(task_id);
create index if not exists idx_time_started  on public.time_entries(started_at desc);

-- REGRA DE OURO: no máximo UM cronômetro rodando ao mesmo tempo.
-- O índice parcial só enxerga as linhas com ended_at nulo; como a
-- expressão indexada é sempre TRUE nesse conjunto, o UNIQUE limita a 1.
-- A trava é do BANCO, não do JavaScript: 2 abas abertas não duplicam.
create unique index if not exists uniq_timer_em_execucao
  on public.time_entries ((ended_at is null))
  where ended_at is null;

-- Calcula a duração ao parar e sinaliza sessões absurdas (esqueceu de parar).
create or replace function public.set_time_entry_duration()
returns trigger language plpgsql as $fn$
begin
  if new.ended_at is not null then
    new.duration_seconds := greatest(0, extract(epoch from (new.ended_at - new.started_at))::int);
    if new.duration_seconds > 12*3600 then new.needs_review := true; end if;
  else
    new.duration_seconds := 0;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_time_duration on public.time_entries;
create trigger trg_time_duration before insert or update on public.time_entries
  for each row execute function public.set_time_entry_duration();


-- ──────────── 6. TRIGGERS updated_at ────────────
do $do$
declare t text;
begin
  foreach t in array array['project_milestones','revision_requests']
  loop
    execute format('drop trigger if exists trg_%s_updated on public.%I', t, t);
    execute format('create trigger trg_%s_updated before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $do$;


-- ──────────── 7. RLS: SOMENTE ADMIN ────────────
-- Mesmo padrão do sql/01_gestao_schema.sql. As três tabelas novas são
-- 100% internas: nenhuma policy de member é criada, então o portal do
-- cliente nunca as enxerga.
do $do$
declare t text;
begin
  foreach t in array array['project_milestones','revision_requests','time_entries']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "admin_all" on public.%I', t);
    execute format('create policy "admin_all" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $do$;


-- ──────────── 8. AGENDA APOSENTADA ────────────
-- A tela agenda.html foi removida do sistema (você passou a usar o
-- Google Agenda para compromissos e reuniões).
--
-- A tabela agenda_events NÃO é apagada aqui de propósito: seus eventos
-- antigos continuam guardados. Quando tiver CERTEZA de que não precisa
-- mais deles, rode a linha abaixo à mão (tirando os dois tracinhos):
--
-- drop table if exists public.agenda_events;
