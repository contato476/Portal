-- ════════════════════════════════════════════════════════════════════
-- 02_APP_SETTINGS.SQL — Configurações do sistema (ex.: link do Google Agenda)
-- Cole no SQL Editor do Supabase e clique em RUN.
-- ════════════════════════════════════════════════════════════════════

create table if not exists public.app_settings (
  key text primary key,
  value text,
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;
drop policy if exists "admin_all" on public.app_settings;
create policy "admin_all" on public.app_settings
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
