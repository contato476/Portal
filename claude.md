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

## LGPD
O Playbook não guarda dados pessoais: só textos de mensagens e links. Os dados de pessoas ficam no CRM e nas tabelas da mentoria.

## Decisões
- Copy sem serviço = "Geral", aparece para todos os serviços.
- Excluir de vez só a partir das arquivadas, com confirmação.
- Números dos sistemas externos lidos direto do banco (mesmo Supabase), sem chave nova.

## Pendências
- Rodar `sql/32_playbook.sql` no Supabase (cria as tabelas e já cadastra o exemplo da Mentoria).
- Cadastrar as outras copys e montar as jornadas dos demais serviços.
- Arquivos soltos fora do git: `agenda.html` e `sql/25`, `28`, `29`, `30`.
- Anotar aqui o endereço do site no Vercel.
