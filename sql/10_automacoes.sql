-- ════════════════════════════════════════════════════════════════════
-- 10_AUTOMACOES.SQL
-- Regras "quando acontecer X, faça Y" e o histórico de execuções.
--
-- COMO USAR: cole este arquivo INTEIRO no SQL Editor do Supabase e
-- clique em RUN. Pode rodar quantas vezes quiser (é idempotente).
-- ════════════════════════════════════════════════════════════════════


-- ──────────── 1. AS REGRAS ────────────
-- trigger_event: o que faz a regra rodar (ex.: 'deal.won')
-- conditions:    filtros extras, todos precisam ser verdadeiros (E)
--                [{"field":"value","op":"gte","value":1000}]
-- actions:       o que fazer, na ordem
--                [{"type":"create_project","params":{...}}]
create table if not exists public.automation_rules (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  description        text,
  enabled            boolean not null default true,
  -- Ligado por padrão de propósito: nas primeiras semanas a regra
  -- mostra o que vai criar e pede confirmação antes de agir.
  confirm_before_run boolean not null default true,
  trigger_event      text not null,
  conditions         jsonb not null default '[]'::jsonb,
  actions            jsonb not null default '[]'::jsonb,
  run_count          int not null default 0,
  last_run_at        timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists idx_rules_event on public.automation_rules(trigger_event) where enabled;


-- ──────────── 2. HISTÓRICO E TRAVA DE REPETIÇÃO ────────────
-- Antes de executar qualquer coisa, o motor INSERE uma linha aqui.
-- Se o insert falhar por duplicidade, é porque essa regra já rodou
-- para esse mesmo registro — e ele desiste em silêncio.
--
-- É isso que torna seguro disparar as automações pelo navegador:
-- com duas abas abertas, ou recarregando a página e refazendo a ação,
-- o projeto NÃO é criado duas vezes. A trava é do banco, não do
-- JavaScript.
create table if not exists public.automation_runs (
  id            uuid primary key default gen_random_uuid(),
  rule_id       uuid references public.automation_rules(id) on delete cascade,
  trigger_event text not null,
  source_table  text,
  source_id     uuid,
  status        text not null default 'sucesso'
                check (status in ('sucesso','erro','ignorado')),
  result        jsonb not null default '{}'::jsonb,   -- o que foi criado
  error         text,
  created_at    timestamptz not null default now()
);
create index if not exists idx_runs_rule on public.automation_runs(rule_id, created_at desc);
create index if not exists idx_runs_data on public.automation_runs(created_at desc);

-- A chave da idempotência.
create unique index if not exists uniq_automation_run
  on public.automation_runs(rule_id, trigger_event, source_id)
  where source_id is not null;


-- ──────────── 3. TRIGGER updated_at ────────────
drop trigger if exists trg_automation_rules_updated on public.automation_rules;
create trigger trg_automation_rules_updated
  before update on public.automation_rules
  for each row execute function public.set_updated_at();


-- ──────────── 4. RLS: SOMENTE ADMIN ────────────
-- Automação é ferramenta sua. O cliente nunca vê nem dispara nada.
do $do$
declare t text;
begin
  foreach t in array array['automation_rules','automation_runs']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "admin_all" on public.%I', t);
    execute format('create policy "admin_all" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $do$;


-- ──────────── 5. CONFIGURAÇÕES ────────────
-- Nenhuma tabela nova para o agendamento: as chaves entram no
-- app_settings, que já existe desde o sql/02.
--   cal_embed_url            = link da sua página no Cal.com
--   gcal_ics_url             = endereço iCal secreto do Google (já usado)
--   automation_last_daily    = data da última rodada das checagens diárias
insert into public.app_settings (key, value) values
  ('cal_embed_url', null),
  ('automation_last_daily', null)
on conflict (key) do nothing;


-- ──────────── 6. REGRAS DE EXEMPLO (DESLIGADAS) ────────────
-- Entram desligadas e pedindo confirmação. Abra a tela de Automações,
-- ajuste do jeito que você trabalha e ligue quando quiser.
insert into public.automation_rules (name, description, enabled, confirm_before_run, trigger_event, conditions, actions)
select
  'Ganhou o cliente → abre o projeto',
  'Quando um negócio vai para Fechado no CRM, cria o projeto e as primeiras tarefas.',
  false, true, 'deal.won',
  '[]'::jsonb,
  '[
     {"type":"create_project","params":{"name_from":"deal.title","status":"pre_inicio","prazo_dias":30,"copiar_contato":true}},
     {"type":"create_tasks","params":{"titles":[
        {"title":"Reunião de kickoff","offset_days":2,"priority":"alta"},
        {"title":"Coletar materiais e acessos","offset_days":5,"priority":"alta"},
        {"title":"Montar cronograma do cliente","offset_days":7,"priority":"media"}
     ]}},
     {"type":"notify","params":{"message":"Projeto criado a partir do negócio ganho."}}
   ]'::jsonb
where not exists (select 1 from public.automation_rules where trigger_event = 'deal.won');

insert into public.automation_rules (name, description, enabled, confirm_before_run, trigger_event, conditions, actions)
select
  'Ajuste fora do escopo → lança a cobrança',
  'Quando você registra um pedido de ajuste marcado como cobrável e com valor, cria a receita no financeiro.',
  false, true, 'revision.created',
  '[{"field":"is_billable","op":"eq","value":true},{"field":"charged_amount","op":"not_null"}]'::jsonb,
  '[{"type":"create_finance_entry","params":{"kind":"receita","amount_from":"revision.charged_amount","due_offset_days":7,"descricao":"Ajuste extra"}}]'::jsonb
where not exists (select 1 from public.automation_rules where trigger_event = 'revision.created');

insert into public.automation_rules (name, description, enabled, confirm_before_run, trigger_event, conditions, actions)
select
  'Suporte acabando → me lembra de falar com o cliente',
  'Todo dia, avisa dos projetos cujo suporte termina em até 15 dias e cria uma tarefa para você.',
  false, true, 'daily.support_expiring',
  '[]'::jsonb,
  '[{"type":"create_reminder_task","params":{"title":"Falar sobre renovação do suporte","offset_days":0,"priority":"alta"}}]'::jsonb
where not exists (select 1 from public.automation_rules where trigger_event = 'daily.support_expiring');
