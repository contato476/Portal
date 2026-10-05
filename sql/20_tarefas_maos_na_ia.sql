-- 20 · Tarefas do lançamento Mãos na IA (gerado em 05/10/2026)
-- Cria o projeto "Lançamento Mãos na IA" e as tarefas com subtarefas na tela de Tarefas.
-- Rodar uma vez no SQL Editor do Supabase. Se o projeto já existir, não faz nada.
do $$
declare v_proj uuid; v_mae uuid;
begin
  if exists (select 1 from public.projects where name = 'Lançamento Mãos na IA') then
    raise notice 'Projeto já existe, nada foi inserido.'; return;
  end if;
  insert into public.projects (name, description, start_date, end_date, color, priority)
  values ('Lançamento Mãos na IA', 'Masterclass 07/10, turma fundadora, Clube, Workshop e Palco.', '2026-10-05', '2026-12-05', '#00d286', 'alta')
  returning id into v_proj;

  -- Masterclass 07/10
  insert into public.tasks (title, description, project_id, start_date, due_date, estimate_minutes, priority, order_num)
  values ('Masterclass 07/10', 'Primeira oferta da Mentoria Mãos na IA. Roteiro e slides no Hub (06 · Reuniões › Reunião 03/10).', v_proj, '2026-10-05', '2026-10-07', 600, 'alta', 0) returning id into v_mae;
  insert into public.tasks (title, description, project_id, parent_task_id, start_date, due_date, estimate_minutes, priority, order_num) values
    ('Postar enquete de presença no grupo', 'Texto pronto em 05-funil/masterclass-07-10-mensagens.md', v_proj, v_mae, '2026-10-05', '2026-10-05', 10, 'alta', 0),
    ('Enviar lembrete 1 + card "coloque na agenda"', null, v_proj, v_mae, '2026-10-05', '2026-10-05', 15, 'alta', 1),
    ('Montar o formulário "o que tentou / onde travou" e mandar no grupo', 'As respostas viram a nuvem de palavras do slide 3', v_proj, v_mae, '2026-10-05', '2026-10-05', 30, 'alta', 2),
    ('Publicar 1º conteúdo de bastidores (feed ou Reels)', 'Bastidores da preparação da Masterclass', v_proj, v_mae, '2026-10-05', '2026-10-05', 45, 'alta', 3),
    ('Atualizar bio, foto e link: especialista em IA para negócios', 'Pedido da Pri: não pensa, já muda. Opções em 05-funil/instagram-posicionamento.md', v_proj, v_mae, '2026-10-06', '2026-10-06', 30, 'alta', 4),
    ('Comparar taxas InfinitePay x Asaas antes de criar os links', 'Sugestão da Pri: InfinitePay recebe no dia seguinte', v_proj, v_mae, '2026-10-06', '2026-10-06', 20, 'media', 5),
    ('Decidir se oferece valor especial a 2 ou 3 pessoas em troca de depoimento', 'Sugestão da Pri para prova social rápida', v_proj, v_mae, '2026-10-06', '2026-10-06', 15, 'media', 6),
    ('Revisar o deck e compartilhar com a Lari', null, v_proj, v_mae, '2026-10-06', '2026-10-06', 60, 'alta', 7),
    ('Confirmar o bônus (Assistente Financeiro) e o kit de boas-vindas', 'Estudo em 03 · Pesquisa › Estudo do bônus', v_proj, v_mae, '2026-10-06', '2026-10-06', 20, 'alta', 8),
    ('Criar e testar links de pagamento: Pix R$ 3.000, boleto entrada R$ 300 + 3x R$ 1.100, cartão 12x R$ 295,14', 'Cartão só no privado', v_proj, v_mae, '2026-10-06', '2026-10-06', 60, 'alta', 9),
    ('Enviar lembrete 2', null, v_proj, v_mae, '2026-10-06', '2026-10-06', 10, 'media', 10),
    ('Alinhamento rápido do pitch com a Lari (se precisar)', null, v_proj, v_mae, '2026-10-06', '2026-10-06', 30, 'media', 11),
    ('Gerar a nuvem de palavras com as respostas do formulário', null, v_proj, v_mae, '2026-10-07', '2026-10-07', 30, 'alta', 12),
    ('Testar sala, câmera, Projeto de demonstração e gravação', null, v_proj, v_mae, '2026-10-07', '2026-10-07', 45, 'alta', 13),
    ('Enviar lembretes 3 e 4 (manhã e 1h antes) + "estamos ao vivo"', null, v_proj, v_mae, '2026-10-07', '2026-10-07', 15, 'alta', 14),
    ('Publicar 2º conteúdo de bastidores', null, v_proj, v_mae, '2026-10-07', '2026-10-07', 45, 'alta', 15),
    ('Fazer a Masterclass', 'Pitch: uma condição por vez na tela; fechamento em "você"', v_proj, v_mae, '2026-10-07', '2026-10-07', 120, 'alta', 16);

  -- Turma fundadora (pós-Masterclass)
  insert into public.tasks (title, description, project_id, start_date, due_date, estimate_minutes, priority, order_num)
  values ('Turma fundadora (pós-Masterclass)', 'Meta: 10 mentorias a R$ 3.000. Três funis em paralelo: Masterclass, WhatsApp e indicação.', v_proj, '2026-10-08', '2026-10-26', 530, 'alta', 1) returning id into v_mae;
  insert into public.tasks (title, description, project_id, parent_task_id, start_date, due_date, estimate_minutes, priority, order_num) values
    ('Enviar replay + oferta para quem não fechou', null, v_proj, v_mae, '2026-10-08', '2026-10-08', 30, 'alta', 0),
    ('Chamar no privado quem demonstrou interesse', null, v_proj, v_mae, '2026-10-08', '2026-10-08', 120, 'alta', 1),
    ('Funil 2: WhatsApp para contatos de potencial e orçamentos antigos', 'Condição especial para Madalenas, Enchanté e clientes', v_proj, v_mae, '2026-10-08', '2026-10-08', 90, 'alta', 2),
    ('Criar o grupo de WhatsApp das mentoradas (chip de suporte)', null, v_proj, v_mae, '2026-10-08', '2026-10-08', 20, 'media', 3),
    ('Gravar e publicar o vídeo do módulo de boas-vindas', null, v_proj, v_mae, '2026-10-08', '2026-10-08', 90, 'alta', 4),
    ('Funil 3: convite de indicação para clientes atuais', 'Ganha encontro, análise ou cashback', v_proj, v_mae, '2026-10-09', '2026-10-09', 45, 'media', 5),
    ('Publicar 3º conteúdo de bastidores', null, v_proj, v_mae, '2026-10-09', '2026-10-09', 45, 'media', 6),
    ('Último aviso da condição de fundadora', null, v_proj, v_mae, '2026-10-10', '2026-10-10', 15, 'alta', 7),
    ('Onboarding de quem fechou: boas-vindas, diagnóstico e agendar encontro 1', 'Pergunta: o que precisa acontecer em 3 meses para valer a pena?', v_proj, v_mae, '2026-10-12', '2026-10-12', 60, 'alta', 8),
    ('Pedir depoimento às primeiras mentoradas após o encontro 1', null, v_proj, v_mae, '2026-10-26', '2026-10-26', 15, 'media', 9);

  -- Posicionamento e Instagram (Pri)
  insert into public.tasks (title, description, project_id, start_date, due_date, estimate_minutes, priority, order_num)
  values ('Posicionamento e Instagram (Pri)', 'Checklist dos 7 primeiros dias da devolutiva da Pri. Detalhes em 08 · Posicionamento e Marketing.', v_proj, '2026-10-09', '2026-10-14', 345, 'alta', 2) returning id into v_mae;
  insert into public.tasks (title, description, project_id, parent_task_id, start_date, due_date, estimate_minutes, priority, order_num) values
    ('Publicar a página de aplicação da mentoria', null, v_proj, v_mae, '2026-10-09', '2026-10-09', 30, 'alta', 0),
    ('Reorganizar os destaques do Instagram', null, v_proj, v_mae, '2026-10-09', '2026-10-09', 60, 'media', 1),
    ('Atualizar site e links', null, v_proj, v_mae, '2026-10-09', '2026-10-09', 60, 'media', 2),
    ('Enviar os novos conteúdos para validação da Pri', null, v_proj, v_mae, '2026-10-09', '2026-10-09', 15, 'media', 3),
    ('Mapear especialistas de referência', null, v_proj, v_mae, '2026-10-12', '2026-10-12', 60, 'media', 4),
    ('Estudar concorrentes', 'Base: 09-radar-ia/concorrentes.md', v_proj, v_mae, '2026-10-12', '2026-10-12', 60, 'media', 5),
    ('Melhorar os ganchos (pedido da Pri)', null, v_proj, v_mae, '2026-10-14', '2026-10-14', 60, 'media', 6);

  -- Mentoria da Pri · comunicação
  insert into public.tasks (title, description, project_id, start_date, due_date, estimate_minutes, priority, order_num)
  values ('Mentoria da Pri · comunicação', 'Tarefas da sessão de onboarding de 01/10 com a Pri.', v_proj, '2026-10-06', '2026-10-13', 315, 'media', 3) returning id into v_mae;
  insert into public.tasks (title, description, project_id, parent_task_id, start_date, due_date, estimate_minutes, priority, order_num) values
    ('Mandar para a Tamara 2 ou 3 perfis de referência em IA', 'Amanda Diniz (Divos da IA) e outros do 09-radar-ia/concorrentes.md', v_proj, v_mae, '2026-10-06', '2026-10-06', 15, 'media', 0),
    ('Sessão da Pri e desafio de 21 dias de conteúdo', null, v_proj, v_mae, '2026-10-08', '2026-10-08', 90, 'media', 1),
    ('Assistir à Masterclass de diferenciação de conteúdo', null, v_proj, v_mae, '2026-10-08', '2026-10-08', 60, 'media', 2),
    ('Assistir à Masterclass de percepção de valor (documentar a rotina)', null, v_proj, v_mae, '2026-10-09', '2026-10-09', 60, 'media', 3),
    ('Criar a mensagem de boas-vindas para novos seguidores (texto + áudio)', 'Perguntar por que começou a seguir', v_proj, v_mae, '2026-10-09', '2026-10-09', 30, 'media', 4),
    ('Fazer a implementação de conteúdo da Masterclass e mandar no grupo', null, v_proj, v_mae, '2026-10-13', '2026-10-13', 60, 'media', 5);

  -- Clube Mãos na IA
  insert into public.tasks (title, description, project_id, start_date, due_date, estimate_minutes, priority, order_num)
  values ('Clube Mãos na IA', 'R$ 797/ano ou R$ 119/mês. 1º lote para as 15 primeiras; o valor sobe a cada campanha.', v_proj, '2026-10-20', '2026-10-26', 300, 'alta', 4) returning id into v_mae;
  insert into public.tasks (title, description, project_id, parent_task_id, start_date, due_date, estimate_minutes, priority, order_num) values
    ('Definir a trilha e o conteúdo do 1º mês', null, v_proj, v_mae, '2026-10-20', '2026-10-20', 120, 'media', 0),
    ('Criar os links R$ 797/ano e R$ 119/mês', 'A Pri pediu para vender o Clube já', v_proj, v_mae, '2026-10-09', '2026-10-09', 30, 'alta', 1),
    ('Oferecer o Clube às Madalenas e a quem não fechar a mentoria', 'Promessa: tudo o que você precisa da IA para trabalhar no seu negócio, num único lugar', v_proj, v_mae, '2026-10-11', '2026-10-11', 60, 'alta', 2),
    ('Abrir o 1º lote no Instagram (15 vagas)', null, v_proj, v_mae, '2026-10-26', '2026-10-26', 60, 'media', 3),
    ('Definir o grupo aberto gratuito (enquetes e checklists pontuais)', 'Sem aula profunda, para não competir com o Clube', v_proj, v_mae, '2026-10-20', '2026-10-20', 30, 'baixa', 4);

  -- Workshop 05/11 e Palco 04-05/12
  insert into public.tasks (title, description, project_id, start_date, due_date, estimate_minutes, priority, order_num)
  values ('Workshop 05/11 e Palco 04-05/12', 'Segundo funil. As outras 5 mentorias da meta vêm daqui.', v_proj, '2026-10-12', '2026-12-04', 1215, 'alta', 5) returning id into v_mae;
  insert into public.tasks (title, description, project_id, parent_task_id, start_date, due_date, estimate_minutes, priority, order_num) values
    ('Confirmar a data do workshop de novembro (05/11 ou 07/11)', null, v_proj, v_mae, '2026-10-12', '2026-10-12', 15, 'media', 0),
    ('Abrir inscrições do workshop', null, v_proj, v_mae, '2026-10-15', '2026-10-15', 60, 'media', 1),
    ('Gravar a aula de configuração inicial', null, v_proj, v_mae, '2026-10-29', '2026-10-29', 120, 'media', 2),
    ('Workshop Mãos na IA', null, v_proj, v_mae, '2026-11-05', '2026-11-05', 240, 'alta', 3),
    ('Refinar o funil comercial (45 dias da Pri)', null, v_proj, v_mae, '2026-11-15', '2026-11-15', 120, 'media', 4),
    ('Preparar o pitch do Palco', null, v_proj, v_mae, '2026-11-27', '2026-11-27', 180, 'media', 5),
    ('Palco', '04 e 05/12', v_proj, v_mae, '2026-12-04', '2026-12-04', 480, 'alta', 6);
end $$;
