-- ════════════════════════════════════════════════════════════════════
-- 38 · MENTORADAS PODEM CRIAR LOGIN
-- Rode no SQL Editor do Supabase (jvtjhfganuuefswbnbrk). Pode rodar mais de uma vez.
--
-- Problema: o botão "Gerar link de acesso" do portal da mentoria dava
-- "Database error saving new user". O gatilho on_auth_user_created
-- (função handle_new_user) só deixa criar login para quem tem convite de
-- projeto (project_invites) ou está em allowed_emails. Mentorada não está
-- em nenhum dos dois, então o banco recusava.
--
-- Correção: quem está em mn_membros (não arquivada) também pode criar login.
-- Só admin cadastra em mn_membros (RLS is_admin), então continua sendo a
-- Jenne quem autoriza. O resto da função fica igual ao que estava no banco
-- em 28/10/2026 (esta função não estava em nenhum arquivo sql/ até agora).
-- ════════════════════════════════════════════════════════════════════

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_allowed boolean;
  v_has_any_admin boolean;
  v_invite record;
begin
  -- Verifica se já existe algum admin (bootstrap)
  select exists (select 1 from public.profiles where role = 'admin') into v_has_any_admin;

  if not v_has_any_admin then
    insert into public.profiles (id, name, company, role)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
      new.raw_user_meta_data->>'company',
      'client'
    );
    return new;
  end if;

  -- Verifica se o email tem convite pendente em ALGUM projeto
  -- (se sim, o cadastro é permitido automaticamente)
  if exists (
    select 1 from public.project_invites
    where lower(email) = lower(new.email) and accepted_at is null
  ) then
    -- Cria perfil como cliente
    insert into public.profiles (id, name, company, role)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
      new.raw_user_meta_data->>'company',
      'client'
    );

    -- Para cada convite pendente desse email, cria membership
    for v_invite in
      select * from public.project_invites
      where lower(email) = lower(new.email) and accepted_at is null
    loop
      insert into public.project_members (project_id, user_id, role, added_by)
      values (v_invite.project_id, new.id, v_invite.role, v_invite.invited_by)
      on conflict (project_id, user_id) do nothing;

      -- Marca convite como aceito
      update public.project_invites
      set accepted_at = now()
      where id = v_invite.id;
    end loop;

    -- Também marca o email como usado em allowed_emails (se existir)
    update public.allowed_emails set used = true where lower(email) = lower(new.email);

    return new;
  end if;

  -- NOVO (sql/38): mentorada ou assinante do Clube cadastrada no portal da mentoria
  if exists (
    select 1 from public.mn_membros
    where lower(email) = lower(new.email) and arquivado_em is null
  ) then
    insert into public.profiles (id, name, company, role)
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
      new.raw_user_meta_data->>'company',
      'client'
    );
    return new;
  end if;

  -- Caminho antigo: verifica allowed_emails (cadastro de cliente sem convite específico)
  select exists (
    select 1 from public.allowed_emails
    where lower(email) = lower(new.email) and used = false
  ) into v_allowed;

  if not v_allowed then
    raise exception 'Email não autorizado. Solicite convite ao administrador.';
  end if;

  update public.allowed_emails set used = true where lower(email) = lower(new.email);

  insert into public.profiles (id, name, company, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    new.raw_user_meta_data->>'company',
    'client'
  );

  return new;
end;
$function$;

-- Conferência: deve mostrar "true" (a função já conhece mn_membros).
select pg_get_functiondef('public.handle_new_user'::regproc) like '%mn_membros%' as mentoradas_liberadas;
