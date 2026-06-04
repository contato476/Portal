-- ════════════════════════════════════════════════════════════════════
-- 03_CLIENTE_PROJETO_DIRETO.SQL
-- Permite criar cliente + projeto na hora, SEM esperar o cliente se
-- cadastrar no portal. O projeto nasce vinculado a um contato do CRM;
-- quando o cliente se cadastrar, tudo é vinculado automaticamente.
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em RUN.
-- Pode rodar mais de uma vez sem problema (idempotente).
-- ════════════════════════════════════════════════════════════════════

-- ──────────── 1. PROJETO PODE EXISTIR ANTES DO CADASTRO ────────────
alter table public.projects alter column client_id drop not null;

-- Vínculo do projeto com o contato do CRM (cliente "comercial")
alter table public.projects
  add column if not exists contact_id uuid references public.crm_contacts(id) on delete set null;
create index if not exists idx_projects_contact on public.projects(contact_id);

-- Documentos também não exigem mais o usuário do portal
alter table public.documents alter column user_id drop not null;

-- ──────────── 2. ADMIN PODE TUDO NAS TABELAS DO PORTAL ────────────
-- Políticas permissivas adicionais ("admin_all") — não afetam as
-- políticas existentes dos clientes, apenas garantem o acesso do admin.
do $$
declare t text;
begin
  foreach t in array array[
    'projects','agreements','checklist_items','checklist_states',
    'documents','project_phases','project_members','project_invites'
  ]
  loop
    if to_regclass('public.'||t) is not null then
      execute format('alter table public.%I enable row level security', t);
      execute format('drop policy if exists "admin_all" on public.%I', t);
      execute format('create policy "admin_all" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
    end if;
  end loop;
end $$;

-- ──────────── 3. AUTO-VÍNCULO QUANDO O CLIENTE SE CADASTRAR ────────────
-- Quando um novo profile é criado (cadastro no portal), procura o
-- contato do CRM com o mesmo e-mail e vincula contato + projetos.
create or replace function public.link_new_client()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare v_email text;
begin
  select lower(email) into v_email from auth.users where id = new.id;
  if v_email is null then return new; end if;

  -- Vincula o contato do CRM ao novo usuário
  update public.crm_contacts
     set profile_id = new.id
   where profile_id is null and lower(email) = v_email;

  -- Vincula projetos criados antes do cadastro
  update public.projects p
     set client_id = new.id
    from public.crm_contacts c
   where p.contact_id = c.id
     and p.client_id is null
     and lower(c.email) = v_email;

  -- Documentos enviados antes do cadastro passam a pertencer ao cliente
  update public.documents d
     set user_id = new.id
    from public.projects p
   where d.project_id = p.id
     and d.user_id is null
     and p.client_id = new.id;

  return new;
end;
$$;

drop trigger if exists trg_link_new_client on public.profiles;
create trigger trg_link_new_client
  after insert on public.profiles
  for each row execute function public.link_new_client();

-- Pronto! Agora é possível criar cliente + projeto imediatamente.
