-- ════════════════════════════════════════════════════════════════════
-- 05_MELHORIAS.SQL — Follow-up no CRM, parcelamento/recorrência no
-- financeiro, novas métricas do Instagram e novos status de projeto.
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em RUN.
-- Pode rodar mais de uma vez sem problema (idempotente).
-- ════════════════════════════════════════════════════════════════════

-- ──────────── 1. CRM: FOLLOW-UP ────────────
-- Guarda o próximo follow-up direto no negócio (aparece no card do funil
-- e preenche o modal sem precisar consultar a tabela de tarefas).
alter table public.crm_deals
  add column if not exists next_followup date,
  add column if not exists followup_note text;

-- A tarefa de follow-up fica ligada ao negócio de origem. on delete cascade:
-- se o negócio for excluído, a tarefa de follow-up some junto.
alter table public.tasks
  add column if not exists deal_id uuid references public.crm_deals(id) on delete cascade;
create index if not exists idx_tasks_deal on public.tasks(deal_id);

-- ──────────── 2. FINANCEIRO: PARCELAMENTO E RECORRÊNCIA ────────────
-- series_id agrupa lançamentos que nasceram juntos (as 3 parcelas, ou os
-- 12 meses de uma conta fixa). series_kind diz se é parcela ou recorrência.
-- series_index/series_total: ex. parcela 2 de 3.
alter table public.fin_transactions
  add column if not exists series_id uuid,
  add column if not exists series_kind text,
  add column if not exists series_index int,
  add column if not exists series_total int;

-- Trava de valores válidos para series_kind (sem quebrar linhas antigas, que
-- têm series_kind nulo). Recria a constraint de forma idempotente.
alter table public.fin_transactions
  drop constraint if exists fin_series_kind_check;
alter table public.fin_transactions
  add constraint fin_series_kind_check
  check (series_kind is null or series_kind in ('parcela','recorrencia'));

create index if not exists idx_fin_series on public.fin_transactions(series_id);

-- ──────────── 3. MARKETING: NOVAS MÉTRICAS DO INSTAGRAM ────────────
-- O Instagram mudou o painel. Colunas novas (todas opcionais):
--   views          = visualizações
--   net_followers  = seguidores líquidos
--   interactions   = interações
--   profile_visits = visitas ao perfil
--   link_taps      = toques no link da bio
-- As colunas que já existiam continuam servindo:
--   reach     = contas alcançadas
--   followers = total de seguidores
alter table public.mkt_metrics
  add column if not exists views int,
  add column if not exists net_followers int,
  add column if not exists interactions int,
  add column if not exists profile_visits int,
  add column if not exists link_taps int;

-- ──────────── 4. PROJETOS: NOVOS STATUS ────────────
-- Novos status: Testes cliente e Ajustes pós testes.
-- Remove qualquer trava (CHECK) antiga de status para aceitar os novos
-- valores. A coluna passa a ser texto livre, controlada pela aplicação.
do $$
declare c record;
begin
  if to_regclass('public.projects') is not null then
    for c in
      select con.conname
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace nsp on nsp.oid = rel.relnamespace
      where nsp.nspname = 'public'
        and rel.relname = 'projects'
        and con.contype = 'c'
        and pg_get_constraintdef(con.oid) ilike '%status%'
    loop
      execute format('alter table public.projects drop constraint %I', c.conname);
    end loop;
  end if;
end $$;

-- Pronto! As tabelas estão atualizadas. A RLS (admin_all) já cobre todas
-- estas tabelas, então nenhuma policy precisou ser alterada.
