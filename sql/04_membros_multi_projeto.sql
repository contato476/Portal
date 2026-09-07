-- ════════════════════════════════════════════════════════════════════
-- 04_MEMBROS_MULTI_PROJETO.SQL
-- Garante que quem está em project_members enxerga TODOS os projetos
-- de que é membro (e os dados deles: checklist, cronograma, combinados,
-- documentos). Necessário para parceiros com acesso a vários projetos.
-- Cole este arquivo inteiro no SQL Editor do Supabase e clique em RUN.
-- Pode rodar mais de uma vez sem problema (idempotente).
-- ════════════════════════════════════════════════════════════════════

-- Função auxiliar: o usuário logado é membro deste projeto?
create or replace function public.is_member(p_project uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists(
    select 1 from public.project_members
    where project_id = p_project and user_id = auth.uid()
  );
$$;

-- 1. Membro vê suas próprias linhas em project_members
drop policy if exists "member_read_own" on public.project_members;
create policy "member_read_own" on public.project_members
  for select to authenticated
  using (user_id = auth.uid());

-- 2. Membro vê todos os projetos de que participa
drop policy if exists "member_read_projects" on public.projects;
create policy "member_read_projects" on public.projects
  for select to authenticated
  using (public.is_member(id));

-- 3. Membro vê os dados dos projetos de que participa
do $$
declare t text;
begin
  foreach t in array array[
    'checklist_items','checklist_states','project_phases',
    'agreements','documents'
  ]
  loop
    if to_regclass('public.'||t) is not null then
      execute format('drop policy if exists "member_read" on public.%I', t);
      execute format(
        'create policy "member_read" on public.%I for select to authenticated using (public.is_member(project_id))', t);
    end if;
  end loop;
end $$;

-- 4. Membro pode interagir (checklist e combinados) nos seus projetos
drop policy if exists "member_write_states" on public.checklist_states;
create policy "member_write_states" on public.checklist_states
  for all to authenticated
  using (public.is_member(project_id))
  with check (public.is_member(project_id) and user_id = auth.uid());

drop policy if exists "member_insert_docs" on public.documents;
create policy "member_insert_docs" on public.documents
  for insert to authenticated
  with check (public.is_member(project_id) and user_id = auth.uid());

-- ════════════════════════════════════════════════════════════════════
-- DIAGNÓSTICO (opcional): rode este SELECT trocando o e-mail abaixo
-- para conferir em quantos projetos a pessoa está como membro.
-- ════════════════════════════════════════════════════════════════════
-- select p.name as projeto, m.role, u.email
--   from public.project_members m
--   join public.projects p on p.id = m.project_id
--   join auth.users u on u.id = m.user_id
--  where lower(u.email) = lower('email-do-parceiro@exemplo.com');
