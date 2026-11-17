-- 49 · Marketing: colocar no ar o banco de ideias dos salvos (gerado em 16/11/2026)
-- Entra no projeto "Marketing" (criado pelo sql/27). Rodar no SQL Editor do Supabase.
-- Pode rodar de novo: o grupo só entra se ainda não existir.
do $$
declare v_proj uuid; v_mae uuid;
begin
  select id into v_proj from public.projects where name = 'Marketing' limit 1;
  if v_proj is null then
    raise exception 'Projeto Marketing não encontrado. Rode antes o sql/27_projeto_marketing.sql.';
  end if;

  if not exists (select 1 from public.tasks where project_id = v_proj and parent_task_id is null and title = 'Banco de ideias dos salvos do Instagram') then
    insert into public.tasks (title, description, project_id, start_date, due_date, estimate_minutes, priority, order_num)
    values ('Banco de ideias dos salvos do Instagram',
      'Toda segunda o Claude lê os salvos novos do Instagram, analisa (gancho, formato, estrutura) e propõe uma ideia adaptada. A aprovação é na tela Salvos do sistema: estrela para favoritar, "Vou postar" ou "Descartar". Leva-se a estrutura, nunca texto, arte ou paleta.',
      v_proj, '2026-11-17', '2026-11-30', 95, 'media', 8) returning id into v_mae;
    insert into public.tasks (title, description, project_id, parent_task_id, start_date, due_date, estimate_minutes, priority, order_num) values
      ('Rodar o sql/48 e guardar o token',
       'Rodar sql/48_salvos_ideias.sql no SQL Editor. Copiar o token da última consulta e colar no arquivo .env da skill (pasta .claude/skills/roube-como-um-artista), junto com a chave pública do Supabase. Não mandar o token pelo chat.',
       v_proj, v_mae, '2026-11-17', '2026-11-18', 10, 'alta', 0),
      ('Pedir ao Instagram o arquivo dos salvos',
       'Perfil, menu, Central de contas, Suas informações e permissões, Baixar suas informações. Marcar só "Salvos", formato JSON. Quando chegar, colocar na pasta Marketing e avisar o Claude.',
       v_proj, v_mae, '2026-11-17', '2026-11-18', 10, 'media', 1),
      ('Primeira varredura acompanhada',
       'Segunda, com o computador ligado e o Chrome aberto e logado no Instagram. Conferir a lista antes de o Claude tirar os salvamentos.',
       v_proj, v_mae, '2026-11-23', '2026-11-23', 30, 'media', 2),
      ('Aprovar as ideias na tela Salvos',
       'Abrir Salvos no sistema, favoritar o que pretende postar e descartar o resto. O que for aprovado entra como conteúdo extra ou no calendário do mês seguinte.',
       v_proj, v_mae, '2026-11-23', '2026-11-24', 30, 'media', 3),
      ('Auditoria do acumulado, em lotes',
       'Com o arquivo exportado: o Claude separa o recente, descarta o que não combina com o posicionamento e carrega o banco em lotes de até 30.',
       v_proj, v_mae, '2026-11-24', '2026-11-30', 15, 'baixa', 4);
  end if;
end $$;
