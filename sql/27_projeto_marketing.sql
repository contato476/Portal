-- 27 · Projeto Marketing (gerado em 19/10/2026)
-- Cria o projeto "Marketing" e as tarefas de marketing no kanban (status pendente = A fazer).
-- Rodar no SQL Editor do Supabase. Pode rodar de novo: o projeto não duplica e cada grupo de tarefas só entra se ainda não existir.
do $$
declare v_proj uuid; v_mae uuid;
begin
  select id into v_proj from public.projects where name = 'Marketing' limit 1;
  if v_proj is null then
    insert into public.projects (name, description, status, start_date, color, priority)
    values ('Marketing', 'Tudo de marketing e conteúdo: calendário do mês, padrão de percepção de valor, perfil do Instagram e entregas do comente IA. Novas tarefas de marketing entram aqui.', 'em_andamento', '2026-10-19', '#00d286', 'alta')
    returning id into v_proj;
  end if;

  -- Destaques do Instagram
  if not exists (select 1 from public.tasks where project_id = v_proj and parent_task_id is null and title = 'Destaques do Instagram') then
    insert into public.tasks (title, description, project_id, start_date, due_date, estimate_minutes, priority, order_num)
    values ('Destaques do Instagram', 'Foco nos serviços, no que já foi entregue, depoimentos, bastidores e eventos. Capas, roteiro do Comece aqui e o que vai em cada destaque em Marketing/destaques (Drive).', v_proj, '2026-10-20', '2026-11-03', 330, 'alta', 0) returning id into v_mae;
    insert into public.tasks (title, description, project_id, parent_task_id, start_date, due_date, estimate_minutes, priority, order_num) values
      ('Gravar os 9 stories do Comece aqui', 'Roteiro em Marketing/destaques/roteiro_comece_aqui.md. A sua história contada em tom de conversa.', v_proj, v_mae, '2026-10-20', '2026-10-20', 60, 'alta', 0),
      ('Criar o destaque Comece aqui com a capa', 'Capa 01_comece_aqui.png em Marketing/destaques/capas.', v_proj, v_mae, '2026-10-20', '2026-10-20', 10, 'alta', 1),
      ('Separar depoimentos autorizados e criar o destaque Depoimentos', 'Prints e vídeos de clientes de sistema e mentoradas. Sem nome e sem número quando a pessoa preferir; guardar a autorização.', v_proj, v_mae, '2026-10-21', '2026-10-21', 40, 'alta', 2),
      ('Criar o destaque Eventos', 'Fotos do workshop de 03/09 (G:/Meu Drive/Evento Maos na IA - fotos e videos/FOTOS) e cortes da masterclass de 07/10 (Marketing/cortes_masterclass/videos).', v_proj, v_mae, '2026-10-21', '2026-10-21', 30, 'media', 3),
      ('Criar o destaque Sistemas', 'Para quem é, como funciona, telas de demonstração com dados fictícios e o que já foi entregue por tipo de negócio. Sem tela de cliente e sem dizer a ferramenta.', v_proj, v_mae, '2026-10-22', '2026-10-22', 45, 'alta', 4),
      ('Criar o destaque Implementação', 'O que inclui (projetos, instruções, rotinas e treinamento da equipe), um exemplo de rotina funcionando e a diferença para a mentoria.', v_proj, v_mae, '2026-10-23', '2026-10-23', 40, 'alta', 5),
      ('Criar o destaque Mentoria', 'Para quem é, como funcionam os encontros, bastidor de um encontro e fala de mentorada autorizada.', v_proj, v_mae, '2026-10-24', '2026-10-24', 30, 'media', 6),
      ('Criar o destaque Bastidores', 'Rotina de trabalho, preparação dos eventos, reuniões sem cliente identificado e os stories de valor invisível.', v_proj, v_mae, '2026-10-25', '2026-10-25', 15, 'media', 7),
      ('Criar o destaque No Claude', 'Só o que você criou para o seu negócio: rotina de pautas, backup, painel do mês, materiais do comente IA, carrosséis. Nunca sistemas de clientes.', v_proj, v_mae, '2026-10-27', '2026-10-27', 30, 'media', 8),
      ('Criar o destaque Clube na abertura', 'O que é, o que tem dentro, diferença para a mentoria e link de entrada.', v_proj, v_mae, '2026-11-03', '2026-11-03', 30, 'alta', 9);
  end if;

  -- Percepção de valor (padrão fixo)
  if not exists (select 1 from public.tasks where project_id = v_proj and parent_task_id is null and title = 'Percepção de valor (padrão fixo)') then
    insert into public.tasks (title, description, project_id, start_date, due_date, estimate_minutes, priority, order_num)
    values ('Percepção de valor (padrão fixo)', 'Padrão de Valor: https://claude.ai/artifact/W3Qd731CKxB1sRGKSiZAn8 . Regras em Marketing/percepcao_de_valor (Drive).', v_proj, '2026-10-20', '2026-11-07', 60, 'alta', 1) returning id into v_mae;
    insert into public.tasks (title, description, project_id, parent_task_id, start_date, due_date, estimate_minutes, priority, order_num) values
      ('Validar os 10 valores invisíveis', 'Seção Valores invisíveis da central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN', v_proj, v_mae, '2026-10-21', '2026-10-21', 20, 'alta', 0),
      ('Completar os números entre colchetes dos stories de valor', 'Começa em 20/10: total de inscrições e tarefa mais citada (painel /painel/desafio).', v_proj, v_mae, '2026-10-20', '2026-10-20', 10, 'alta', 1),
      ('Pedir autorização de depoimentos no grupo do desafio', 'Mensagem pronta no dia 26/10 da central. Guardar o print da autorização.', v_proj, v_mae, '2026-10-26', '2026-10-26', 10, 'alta', 2),
      ('Escolher os 3 posts fixados: Reels de 1/11, carrossel de prova de 7/11 e um post de serviço', 'História, prova e serviço.', v_proj, v_mae, '2026-11-07', '2026-11-07', 10, 'media', 3),
      ('Decidir se reativa a rotina de segunda (Agência de Marketing)', 'O pedido novo, com a percepção de valor, já está em Marketing/agencia_marketing_rotina/PROMPT_rotina.md.', v_proj, v_mae, '2026-10-26', '2026-10-26', 10, 'baixa', 4);
  end if;

  -- Pendências do calendário de outubro
  if not exists (select 1 from public.tasks where project_id = v_proj and parent_task_id is null and title = 'Pendências do calendário de outubro') then
    insert into public.tasks (title, description, project_id, start_date, due_date, estimate_minutes, priority, order_num)
    values ('Pendências do calendário de outubro', 'Central de outubro: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN', v_proj, '2026-10-20', '2026-11-02', 260, 'alta', 2) returning id into v_mae;
    insert into public.tasks (title, description, project_id, parent_task_id, start_date, due_date, estimate_minutes, priority, order_num) values
      ('Escolher a capa A, B ou C de cada Reels da masterclass', 'Capas em Marketing/cortes_masterclass/capas.', v_proj, v_mae, '2026-10-20', '2026-10-20', 20, 'media', 0),
      ('Validar os rascunhos: nutrição, frases de domingo e post da cafeteria de Friends', 'Validar o texto slide a slide antes das artes.', v_proj, v_mae, '2026-10-21', '2026-10-21', 40, 'media', 1),
      ('Definir a mentoria: formato, duração, preço, vagas, bônus e dia da aula', 'Com isso saem os textos de 6/11, 8/11 e da semana da oferta (9 a 13/11).', v_proj, v_mae, '2026-10-31', '2026-10-31', 60, 'alta', 2),
      ('Preparar as 4 regras em um guia (entrega do Reels 06 de 22/10)', null, v_proj, v_mae, '2026-10-21', '2026-10-21', 30, 'media', 3),
      ('Exportar o CSV do /painel/desafio e mandar para o mapa do Amante de Marca', 'Junto com as falas do grupo que chamaram a sua atenção.', v_proj, v_mae, '2026-10-25', '2026-10-25', 10, 'media', 4),
      ('Preparar o roteiro de lapidação (entrega do Reels 01 de 26/10)', null, v_proj, v_mae, '2026-10-25', '2026-10-25', 30, 'media', 5),
      ('Preparar o modelo das minhas instruções (entrega do Reels 03 de 27/10)', 'Sem dados pessoais nem de clientes.', v_proj, v_mae, '2026-10-26', '2026-10-26', 30, 'media', 6),
      ('Exportar o CSV final do /painel/desafio (base da oferta)', null, v_proj, v_mae, '2026-11-01', '2026-11-01', 10, 'alta', 7),
      ('Preparar o mapa do time de assistentes (entrega do Reels 05 de 3/11)', null, v_proj, v_mae, '2026-11-02', '2026-11-02', 30, 'media', 8);
  end if;

  -- Postagens de outubro
  if not exists (select 1 from public.tasks where project_id = v_proj and parent_task_id is null and title = 'Postagens de outubro') then
    insert into public.tasks (title, description, project_id, start_date, due_date, estimate_minutes, priority, order_num)
    values ('Postagens de outubro', 'Uma tarefa por dia. Marque também Feito e Programado na central.', v_proj, '2026-10-20', '2026-11-08', 1200, 'alta', 3) returning id into v_mae;
    insert into public.tasks (title, description, project_id, parent_task_id, start_date, due_date, estimate_minutes, priority, order_num) values
      ('Postar o conteúdo de 20/10', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 2: Serviços e preços
- Feed: Nutrição em Reels falado: organizar vem antes de automatizar
- Stories: Caixinha do Café com IA
- Reels de teste: Reels 09: Design 2: alinhamento e hierarquia
- Mentora: Conteúdo extra: Reels "O que acontece quando sua empresa para de depender de cinco planilhas?"
- Valor: Stories de valor: eu li cada inscrição antes de montar o desafio', v_proj, v_mae, '2026-10-20', '2026-10-20', 60, 'media', 0),
      ('Postar o conteúdo de 21/10', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 3: Mapa da semana
- Reels de teste: POV da fatura do cartão
- Feed: Nutrição: quanto custa o improviso no seu negócio
- Valor: Stories de valor: eu testo cada tarefa antes de mandar', v_proj, v_mae, '2026-10-21', '2026-10-21', 60, 'media', 1),
      ('Postar o conteúdo de 22/10', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 4: Clientes num lugar só
- Grupo do WhatsApp: Grupo: check-in do meio da semana
- Feed: Café com IA #1
- Reels de teste: Reels 06: Regras que valem sempre
- Mentora: Conteúdo extra: carrossel "Seu problema não é falta de ferramenta"
- Valor: Stories de valor: o cuidado com os seus dados e os das suas clientes', v_proj, v_mae, '2026-10-22', '2026-10-22', 60, 'media', 2),
      ('Postar o conteúdo de 23/10', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 5: Semana por prioridade
- Reels de teste: POV do valor da hora
- Feed: Nutrição em Reels falado: quanto custa o improviso
- Feed: Nutrição: A IA te devolve respostas genéricas? (organizar vem antes de automatizar)
- Valor: Stories de valor: o que chega quando você comenta IA', v_proj, v_mae, '2026-10-23', '2026-10-23', 60, 'media', 3),
      ('Postar o conteúdo de 24/10', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 6: Etapas do atendimento
- Feed: Entretenimento: qual sistema eu faria para a cafeteria de Friends?
- Reels de teste: Reels 10: Design 3: no máximo duas fontes
- Valor: Stories de valor: como eu escolho o que vale a pena da IA', v_proj, v_mae, '2026-10-24', '2026-10-24', 60, 'media', 4),
      ('Postar o conteúdo de 25/10', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 7: Resumo da semana 1
- Reels de teste: Semana 1 em takes
- Feed: Reels de resumo da semana 1
- Feed: Frase de domingo', v_proj, v_mae, '2026-10-25', '2026-10-25', 60, 'media', 5),
      ('Postar o conteúdo de 26/10', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 8: Faturamento do mês
- Grupo do WhatsApp: Grupo: pedido de depoimentos (Evidência)
- Reels de teste: Frase sobre organização
- Feed: Reels 01: A primeira versão é rascunho
- Mentora: Conteúdo extra: enquete ou pergunta interativa nos stories
- Valor: Stories de valor: eu uso o que ensino', v_proj, v_mae, '2026-10-26', '2026-10-26', 60, 'media', 6),
      ('Postar o conteúdo de 27/10', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 9: Ticket médio
- Reels de teste: 3 tarefas que eu não faço mais na mão
- Stories: Caixinha do Café com IA
- Feed: Reels 03: Instruções e pasta de referências
- Mentora: Conteúdo extra: Reels "Quer saber se sua empresa está pronta para usar IA?"', v_proj, v_mae, '2026-10-27', '2026-10-27', 60, 'media', 7),
      ('Postar o conteúdo de 28/10', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 10: Gastos fixos e variáveis
- Stories: Stories de Evidência: bastidores do grupo
- Reels de teste: POV do serviço mais vendido
- Feed: Nutrição: faturar mais não é o mesmo que lucrar mais
- Valor: Stories de valor: antes de qualquer sistema, uma conversa', v_proj, v_mae, '2026-10-28', '2026-10-28', 60, 'media', 8),
      ('Postar o conteúdo de 29/10', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 11: Margem por serviço
- Reels de teste: Pedido vago x pedido específico
- Feed: Café com IA #2
- Mentora: Conteúdo extra: Reels "Você pode aprender IA. Ou pode contratar quem constrói isso para você."
- Valor: Stories de valor: nenhuma dúvida fica sem resposta', v_proj, v_mae, '2026-10-29', '2026-10-29', 60, 'media', 9),
      ('Postar o conteúdo de 30/10', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 12: A conta das horas
- Reels de teste: Mito ou verdade
- Feed: Nutrição: o serviço que lota a agenda e não paga as contas', v_proj, v_mae, '2026-10-30', '2026-10-30', 60, 'media', 10),
      ('Postar o conteúdo de 31/10', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 13: Painel com seus números
- Reels de teste: Halloween do empreendedor
- Feed: Nutrição em Reels falado: faturar mais não é lucrar mais', v_proj, v_mae, '2026-10-31', '2026-10-31', 60, 'media', 11),
      ('Postar o conteúdo de 1/11', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 14: Resumo da semana 2
- Grupo do WhatsApp: Grupo: check-in da semana 2
- Reels de teste: Semana 2 em takes
- Feed: Reels de resumo da semana 2
- Feed: Frase de domingo
- Valor: Reels falado de valor: por que eu ensino IA para empresárias', v_proj, v_mae, '2026-11-01', '2026-11-01', 60, 'media', 12),
      ('Postar o conteúdo de 2/11', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 15: Agenda e e-mail no Claude
- Reels de teste: Frase para um dia de pausa
- Feed: Nutrição em Reels falado: o serviço que lota a agenda', v_proj, v_mae, '2026-11-02', '2026-11-02', 60, 'media', 13),
      ('Postar o conteúdo de 3/11', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 16: Fatura do cartão
- Reels de teste: Erros que eu cometia com IA
- Stories: Caixinha do Café com IA
- Feed: Reels 05: Eu trabalho sozinha. Meu time é de IA.', v_proj, v_mae, '2026-11-03', '2026-11-03', 60, 'media', 14),
      ('Postar o conteúdo de 4/11', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 17: Documentos de clientes
- Stories: Stories de Evidência: resultados da semana 2
- Reels de teste: POV da segunda-feira pronta
- Stories: Lista de interesse da mentoria
- Feed: Nutrição: automatizar a bagunça só acelera a bagunça', v_proj, v_mae, '2026-11-04', '2026-11-04', 60, 'media', 15),
      ('Postar o conteúdo de 5/11', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 18: Checklist de novo cliente
- Reels de teste: Faltam 4
- Feed: Café com IA #3
- Valor: Carrossel de valor: o que existe por trás de uma tarefa de 15 minutos', v_proj, v_mae, '2026-11-05', '2026-11-05', 60, 'media', 16),
      ('Postar o conteúdo de 6/11', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 19: Relatório do mês
- Reels de teste: Frase de posicionamento
- Feed: Nutrição (fundo de funil): depois do desafio, o que muda com acompanhamento', v_proj, v_mae, '2026-11-06', '2026-11-06', 60, 'media', 17),
      ('Postar o conteúdo de 7/11', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 20: Uma rotina toda semana
- Reels de teste: Antes e depois da semana
- Feed: Nutrição em Reels falado: automatizar a bagunça só acelera a bagunça
- Valor: Carrossel de prova: 20 dias de desafio, nas palavras de quem fez', v_proj, v_mae, '2026-11-07', '2026-11-07', 60, 'media', 18),
      ('Postar o conteúdo de 8/11', 'Roteiros, legendas e capas na central: https://claude.ai/artifact/ASdExtPPCtpd3Rn52MsRkN
- Stories: Desafio dia 21: Antes e depois
- Reels de teste: O último post-it
- Feed: Reels de encerramento do desafio
- Feed: Frase de domingo', v_proj, v_mae, '2026-11-08', '2026-11-08', 60, 'media', 19);
  end if;
end $$;
