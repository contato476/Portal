-- ════════════════════════════════════════════════════════════════════
-- 12_PORTAL_PEDIDOS.SQL
-- Canal de pedidos do cliente + marcação de novidades no portal.
--
-- POR QUÊ ISTO EXISTE: hoje o pedido de ajuste chega por WhatsApp e
-- você transcreve à mão. O dado nasce fora do sistema, então o
-- relatório de tempo por ajuste sempre vai estar incompleto. Aqui o
-- cliente registra o pedido no portal, e você converte em ajuste com
-- um clique — cronometrando desde o começo.
--
-- ⚠️ A FRONTEIRA CONTINUA DE PÉ: o fluxo é do CLIENTE PARA VOCÊ.
-- Nada que ele escreve vira trabalho sozinho. Ele só pede; quem aceita,
-- recusa ou transforma em ajuste é você.
--
-- COMO USAR: cole o arquivo inteiro no SQL Editor e clique em RUN.
-- É idempotente.
-- ════════════════════════════════════════════════════════════════════


-- ──────────── 1. PEDIDOS FEITOS PELO CLIENTE ────────────
create table if not exists public.client_requests (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references public.projects(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  title        text not null,
  description  text,
  status       text not null default 'novo'
               check (status in ('novo','lido','convertido','recusado','arquivado')),
  -- Preenchido quando você transforma o pedido num ajuste seu.
  revision_id  uuid references public.revision_requests(id) on delete set null,
  admin_note   text,        -- sua resposta, visível para o cliente
  read_at      timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_client_requests_project on public.client_requests(project_id, status);
create index if not exists idx_client_requests_user    on public.client_requests(user_id);

drop trigger if exists trg_client_requests_updated on public.client_requests;
create trigger trg_client_requests_updated
  before update on public.client_requests
  for each row execute function public.set_updated_at();


-- ──────────── 2. PERMISSÕES ────────────
alter table public.client_requests enable row level security;

-- Você: acesso total.
drop policy if exists "admin_all" on public.client_requests;
create policy "admin_all" on public.client_requests
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Cliente: vê só os pedidos DELE, nos projetos em que é membro.
drop policy if exists "member_read_own_requests" on public.client_requests;
create policy "member_read_own_requests" on public.client_requests
  for select to authenticated
  using (user_id = auth.uid() and public.is_member(project_id));

-- Cliente: cria pedido só em nome dele e só nos projetos dele.
drop policy if exists "member_insert_own_requests" on public.client_requests;
create policy "member_insert_own_requests" on public.client_requests
  for insert to authenticated
  with check (user_id = auth.uid() and public.is_member(project_id));

-- Cliente: pode editar/apagar enquanto o pedido ainda está "novo".
-- Depois que você leu ou converteu, ele não mexe mais — senão o texto
-- mudaria embaixo do trabalho que você já começou.
drop policy if exists "member_update_new_requests" on public.client_requests;
create policy "member_update_new_requests" on public.client_requests
  for update to authenticated
  using      (user_id = auth.uid() and public.is_member(project_id) and status = 'novo')
  with check (user_id = auth.uid() and public.is_member(project_id) and status = 'novo');

drop policy if exists "member_delete_new_requests" on public.client_requests;
create policy "member_delete_new_requests" on public.client_requests
  for delete to authenticated
  using (user_id = auth.uid() and public.is_member(project_id) and status = 'novo');


-- ──────────── 3. NOVIDADES NO PORTAL ────────────
-- Guarda quando o cliente entrou no portal pela última vez, para a
-- home poder marcar o que chegou depois disso.
alter table public.profiles
  add column if not exists last_seen_at timestamptz;

-- Cada um atualiza o próprio carimbo. Se já existir uma policy de
-- update em profiles, esta soma-se a ela (policies são permissivas).
drop policy if exists "self_update_last_seen" on public.profiles;
create policy "self_update_last_seen" on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
