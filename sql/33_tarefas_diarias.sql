-- ════════════════════════════════════════════════════════════════════
-- 33 · TAREFAS DIÁRIAS (lembretes fixos do quadro de tarefas) · 21/10/2026
-- Rode este arquivo no SQL Editor do Supabase DO SISTEMA (jvtjhfganuuefswbnbrk).
-- Pode rodar mais de uma vez: só cria o que ainda não existe.
--
-- São as coisas que precisam ser feitas todo dia. Não têm status nem
-- check: ficam paradas na última coluna do Kanban, só como lembrete.
-- Por isso moram numa tabela própria, e não na tasks (que tem prazo,
-- status e entra nos relatórios).
-- Excluir na tela só arquiva (arquivado_em), o lembrete some do quadro.
-- Tudo só para admin (RLS com public.is_admin()).
-- ════════════════════════════════════════════════════════════════════

create table if not exists public.tarefas_diarias (
  id           uuid primary key default gen_random_uuid(),
  titulo       text not null check (char_length(titulo) between 1 and 200),
  ordem        int not null default 0,
  arquivado_em timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists tarefas_diarias_ordem_idx on public.tarefas_diarias (arquivado_em, ordem);

-- updated_at automático (função já existe no 01_gestao_schema)
drop trigger if exists tarefas_diarias_updated on public.tarefas_diarias;
create trigger tarefas_diarias_updated before update on public.tarefas_diarias
  for each row execute function public.set_updated_at();

-- RLS: só admin
alter table public.tarefas_diarias enable row level security;
drop policy if exists admin_all on public.tarefas_diarias;
create policy admin_all on public.tarefas_diarias for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
