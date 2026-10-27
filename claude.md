# Sistema de gestão (Jenneffer Prazeres)

## Objetivo
Sistema interno de gestão do meu negócio: projetos, tarefas, tempo, CRM, financeiro, contratos, agendamento, marketing, automações, novidades dos formulários e o Playbook comercial. Inclui o portal do cliente (admin.html e portal.html).

## Cliente
Projeto meu (uso interno, só admin entra nas telas de gestão).

## Identidade visual
O sistema já tem tema próprio, e as telas novas seguem ele (não o padrão #00d286/#242637):
- Fundo escuro: #0D1117, #161B22, #21262D. Bordas #30363D.
- Verde: #1A7A4A e #22A060. Textos #E6EDF3, #8B949E, #6E7681.
- Fontes: DM Sans (texto) e Cormorant Garamond (títulos).
- Ícones: SVG no estilo Lucide, desenhados direto no código.
- Tudo em `assets/shared.css`.

## Stack
- HTML + JavaScript puro, uma página por módulo. Funções puras em `assets/helpers.js`; conexão, login e menu em `assets/shared.js`.
- Supabase (banco, auth). Projeto `jvtjhfganuuefswbnbrk`.
- Vercel: publica sozinho a cada push no `main`. Funções serverless em `api/`.
- Scripts do banco em `sql/`, numerados. Cada um roda uma vez no SQL Editor do Supabase.

## Links
- Repositório: https://github.com/contato476/Portal
- Mãos na IA (formulários): https://maosnaia.jpgestaodescomplicada.com/painel
- Portal da mentoria: https://mentoria.jpgestaodescomplicada.com/entrar (usa o mesmo banco, tabelas `mn_`)

## Segurança
- Toda tela de gestão chama `requireAdmin()`, e o banco garante com RLS `public.is_admin()` em todas as tabelas.
- Páginas com `noindex`.

## Módulos recentes
- **CRM** (`crm.html`): funil Novo, Contato, Reunião agendada, Proposta, Negociação, Fechado, Perdido. A etapa Reunião agendada entrou em 21/10/2026 (`sql/31`).
- **Playbook** (`playbook.html`, `sql/32_playbook.sql`), 21/10/2026:
  - Copys: mensagens prontas separadas por serviço, canal, momento e tipo. Botão copiar, campos [entre colchetes] destacados, fixar, arquivar e lixeira.
  - Jornadas: etapas de cada serviço em ordem, com "quando", etapa do CRM e as copys da etapa.
  - Sistemas: atalhos para os outros sistemas com números (mentoria: tabelas `mn_`; Mãos na IA: tabela `novidades`).
  - Listas: serviços, canais, momentos e tipos editáveis na tela. Item em uso só arquiva.
  - Histórico de alterações em `pb_historico` (gatilho no banco).
  - Serviços: Mentoria Mãos na IA, Clube Mãos na IA, Workshop, Palestra, Implementação de IA, Sistemas personalizados. Desafio e Oficina não são serviços.

- **CRM com dois pipelines** (`crm.html`, `sql/35_crm_pipeline_ia.sql`), 27/10/2026:
  - Seletor no topo: **Sistemas** (funil de antes, sem mudança) e **Produtos de IA** (Mentoria Mãos na IA, Clube Mãos na IA, Implementação de IA). O pipeline aberto fica lembrado no navegador.
  - Etapas de IA: Prospecção, Novo (formulário), Contato inicial, Follow-up do contato, Reunião agendada, Follow-up da reunião, Proposta/Negociação, Ganho, Reaquecer, Perdido. "Ganho" é a etapa `fechado` (números e automações de ganho continuam valendo). `ETAPA_EQUIVALENTE` troca a etapa quando o negócio muda de pipeline.
  - Negócio tem `pipeline` e `produto_id`. Os negócios de IA que estavam no funil antigo são levados à mão (campo Pipeline no negócio).
  - Formulários: o gatilho `crm_deals_pipeline_formulario` manda "Mentoria Mãos na IA · Nome" para o pipeline de IA, com o valor padrão da Mentoria. A função `novidades_ingest` não mudou.
  - **Janela do ganho**: ao ir para Ganho, pergunta o que lançar: financeiro (à vista, entrada + parcelas, parcelado ou assinatura mensal, com as parcelas editáveis e `fin_transactions.deal_id`), tarefa "Gerar contrato: ..." ligada ao negócio, cadastro no portal da mentorada (`mn_membros`, com meses de Clube editáveis; e-mail que já existe é atualizado), jornada e contato como cliente ativo. Volta pelo botão "Ações do ganho" e avisa o que já foi feito, para não lançar em dobro.
  - **Jornada pós-venda** (aba Jornada, só no pipeline de IA): por cliente (lista com progresso e atrasados, janela com checklist, passo extra só daquela cliente) e Kanban (uma coluna por passo do produto; arrastar marca os passos anteriores). Cada cliente recebe uma cópia dos passos no dia do ganho (`crm_jornada_itens`), e mudar o modelo não mexe em quem já está na jornada.
  - `sql/35` já rodou no Supabase (27/10/2026) e foi conferido: 3 produtos, 22 passos, listas, RLS, regras de acesso e gatilhos ok.
- **Aguardando cliente** (`assets/kanban-tarefas.js`, `sql/37_tarefas_aguardando_cliente.sql`), 27/10/2026: status novo das tarefas (`aguardando_cliente`), coluna do Kanban entre Fazendo e Concluído. Conta como tarefa aberta (`TASK_ABERTAS` em `helpers.js`): aparece no Painel, nos atrasos e nas automações. `sql/37` já rodou no Supabase (27/10/2026).
- **Configurações** (`configuracoes.html`), 27/10/2026: produtos e valores (valor padrão, como entra no portal, plano, meses de Clube, encontros), passos da jornada de cada produto (`crm_jornada_passos`, com prazo em dias depois do ganho), listas do CRM (origens dos contatos e motivos de perda, em `cfg_listas`), categorias do financeiro e histórico (`cfg_historico`, por gatilho). Item em uso só arquiva. Passos iniciais tirados de `Produtos digitais - Jenneffer Prazeres` (whatsapp-grupos, módulo de boas-vindas, plano do Clube e especificação da Implementação).
- **Tarefas diárias** (`assets/kanban-tarefas.js`, `sql/33_tarefas_diarias.sql`), 21/10/2026: última coluna do Kanban de tarefas (Projetos e Tarefas), depois de Concluído. Lembretes do que fazer todo dia, sem check e sem status, numa tabela própria (`tarefas_diarias`). Adicionar, editar e tirar (só arquiva) direto na coluna. `sql/33` já rodou no Supabase (22/10/2026).

## LGPD
O Playbook não guarda dados pessoais: só textos de mensagens e links. Os dados de pessoas ficam no CRM e nas tabelas da mentoria.
A janela do ganho só leva ao portal o necessário para o acesso: nome, e-mail (login), WhatsApp e negócio, os mesmos campos que `mn_membros` já tinha. Configurações não guarda dados pessoais.

## Decisões
- Copy sem serviço = "Geral", aparece para todos os serviços.
- Excluir de vez só a partir das arquivadas, com confirmação.
- Números dos sistemas externos lidos direto do banco (mesmo Supabase), sem chave nova.

- Pipeline de IA usa `fechado` como Ganho (não criei etapa nova) para não quebrar Painel, automações e conversão.
- Valores, passos e listas ficam em Configurações, não no código. Etapas dos pipelines continuam no código, porque o sistema depende delas (ganho, perda).

## Pendências
- Levar à mão os negócios de IA do funil antigo para o pipeline de IA.
- Conferir os passos da jornada e os valores em Configurações (Clube começou com 6 meses e R$ 797).
- Próximas listas para Configurações: canais do Marketing, categorias do Radar IA, áreas do cronômetro e tipos de atividade do CRM.
- Rodar `sql/32_playbook.sql` no Supabase (cria as tabelas e já cadastra o exemplo da Mentoria).
- Cadastrar as outras copys e montar as jornadas dos demais serviços.
- Arquivos soltos fora do git: `agenda.html` e `sql/25`, `28`, `29`, `30`.
- Endereço no Vercel: https://sistema.jpgestaodescomplicada.com (conta contato476, projeto `portal`; também em portal-psi-ruddy.vercel.app).
