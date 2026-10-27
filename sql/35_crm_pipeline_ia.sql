-- ════════════════════════════════════════════════════════════════════
-- 35 · CRM COM DOIS PIPELINES, JORNADA PÓS-VENDA E CONFIGURAÇÕES · 27/10/2026
-- Rode este arquivo no SQL Editor do Supabase DO SISTEMA (jvtjhfganuuefswbnbrk).
-- Pode rodar mais de uma vez: só cria o que ainda não existe e só cadastra
-- os dados iniciais se as tabelas estiverem vazias.
--
-- O que muda:
--   crm_deals            ganha pipeline ('sistemas' ou 'ia') e produto_id.
--                        Todos os negócios de hoje ficam em 'sistemas'.
--   crm_produtos         produtos de IA com valor padrão e regras do portal
--   crm_jornada_passos   modelo da jornada pós-venda de cada produto
--   crm_jornada_itens    a jornada de cada cliente ganha (checklist)
--   cfg_listas           listas editáveis na tela Configurações
--                        (origens dos contatos, motivos de perda)
--   cfg_historico        quem mudou o quê e quando nas configurações
--   fin_transactions     ganha deal_id, para saber de qual venda veio
-- Tudo só para admin (RLS com public.is_admin()).
-- ════════════════════════════════════════════════════════════════════

-- ── 1) Produtos de IA ──────────────────────────────────────────────
create table if not exists public.crm_produtos (
  id              uuid primary key default gen_random_uuid(),
  codigo          text not null unique,           -- nome fixo para o sistema achar (ex.: 'mentoria')
  nome            text not null,
  cor             text not null default '#22A060',
  valor_padrao    numeric(12,2) not null default 0,
  portal_tipo     text check (portal_tipo in ('mentorada','clube')),  -- vazio = não entra no portal
  portal_plano    text check (portal_plano in ('mentoria','permuta','clube_mensal','clube_anual','cortesia')),
  meses_clube     int not null default 0,         -- acesso ao Clube que o portal libera
  total_encontros int not null default 0,
  ordem           int not null default 0,
  arquivado_em    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- ── 2) Negócios: pipeline e produto ────────────────────────────────
alter table public.crm_deals
  add column if not exists pipeline text not null default 'sistemas',
  add column if not exists produto_id uuid references public.crm_produtos(id) on delete restrict;

alter table public.crm_deals drop constraint if exists crm_deals_pipeline_check;
alter table public.crm_deals add constraint crm_deals_pipeline_check
  check (pipeline in ('sistemas','ia'));

-- Etapas aceitas: as do pipeline Sistemas (iguais ao sql/31) mais as novas
-- do pipeline de IA. 'fechado' aparece como "Ganho" no pipeline de IA.
alter table public.crm_deals drop constraint if exists crm_deals_stage_check;
alter table public.crm_deals add constraint crm_deals_stage_check
  check (stage in ('prospeccao','novo','contato','followup_contato','reuniao','followup_reuniao',
                   'proposta','negociacao','fechado','reaquecer','perdido'));

create index if not exists idx_deals_pipeline on public.crm_deals(pipeline, stage);

-- As jornadas do Playbook (sql/32) apontam para uma etapa do CRM: passam a
-- aceitar as etapas novas também.
do $$
begin
  if to_regclass('public.pb_etapas') is not null then
    alter table public.pb_etapas drop constraint if exists pb_etapas_crm_stage_check;
    alter table public.pb_etapas add constraint pb_etapas_crm_stage_check
      check (crm_stage in ('prospeccao','novo','contato','followup_contato','reuniao','followup_reuniao',
                           'proposta','negociacao','fechado','reaquecer','perdido'));
  end if;
end $$;

-- ── 3) Jornada pós-venda ───────────────────────────────────────────
create table if not exists public.crm_jornada_passos (
  id           uuid primary key default gen_random_uuid(),
  produto_id   uuid not null references public.crm_produtos(id) on delete cascade,
  titulo       text not null,
  descricao    text,
  dias         int not null default 0,            -- prazo: dias depois do ganho
  ordem        int not null default 0,
  arquivado_em timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Cada cliente recebe uma cópia dos passos no dia do ganho. Assim, mudar o
-- modelo depois não bagunça a jornada de quem já está no meio dela.
create table if not exists public.crm_jornada_itens (
  id          uuid primary key default gen_random_uuid(),
  deal_id     uuid not null references public.crm_deals(id) on delete cascade,
  passo_id    uuid references public.crm_jornada_passos(id) on delete set null,
  titulo      text not null,
  descricao   text,
  ordem       int not null default 0,
  prazo       date,
  feito_em    timestamptz,
  feito_por   uuid default null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists crm_jornada_passos_prod_idx on public.crm_jornada_passos (produto_id, ordem);
create index if not exists crm_jornada_itens_deal_idx on public.crm_jornada_itens (deal_id, ordem);

-- ── 4) Listas editáveis (Configurações) ────────────────────────────
create table if not exists public.cfg_listas (
  id           uuid primary key default gen_random_uuid(),
  lista        text not null,                    -- 'crm_origem', 'crm_motivo_perda'
  valor        text not null,                    -- o que fica gravado nos registros
  rotulo       text not null,                    -- o nome que aparece na tela
  cor          text,
  ordem        int not null default 0,
  arquivado_em timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (lista, valor)
);

create table if not exists public.cfg_historico (
  id          bigint generated always as identity primary key,
  tabela      text not null,
  registro_id uuid,
  acao        text not null,
  usuario_id  uuid default auth.uid(),
  em          timestamptz not null default now(),
  antes       jsonb,
  depois      jsonb
);
create index if not exists cfg_historico_em_idx on public.cfg_historico (em desc);

-- ── 5) Financeiro: de qual venda veio o lançamento ─────────────────
alter table public.fin_transactions
  add column if not exists deal_id uuid references public.crm_deals(id) on delete set null;
create index if not exists idx_fin_deal on public.fin_transactions(deal_id);

-- ── 6) updated_at automático (função já existe no 01_gestao_schema) ─
do $$
declare t text;
begin
  foreach t in array array['crm_produtos','crm_jornada_passos','crm_jornada_itens','cfg_listas'] loop
    execute format('drop trigger if exists %I_updated on public.%I', t, t);
    execute format('create trigger %I_updated before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;

-- ── 7) Histórico de alterações ─────────────────────────────────────
create or replace function public.cfg_registrar_historico()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.cfg_historico (tabela, registro_id, acao, antes, depois)
  values (
    tg_table_name,
    coalesce(new.id, old.id),
    lower(tg_op),
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end
  );
  return coalesce(new, old);
end $$;
revoke all on function public.cfg_registrar_historico() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['crm_produtos','crm_jornada_passos','cfg_listas'] loop
    execute format('drop trigger if exists %I_hist on public.%I', t, t);
    execute format('create trigger %I_hist after insert or update or delete on public.%I for each row execute function public.cfg_registrar_historico()', t, t);
  end loop;
end $$;

-- ── 8) Negócios que chegam dos formulários ─────────────────────────
-- A função novidades_ingest (sql/26) cria "Mentoria Mãos na IA · Nome" sem
-- dizer o pipeline. Este gatilho manda esses negócios para o pipeline de IA,
-- com o produto Mentoria e o valor padrão definido em Configurações.
create or replace function public.crm_deals_pipeline_formulario()
returns trigger language plpgsql security definer set search_path = public
as $$
declare v_prod record;
begin
  if new.produto_id is null and new.title ilike 'Mentoria Mãos na IA ·%' then
    select id, valor_padrao into v_prod from public.crm_produtos where codigo = 'mentoria';
    if v_prod.id is not null then
      new.pipeline   := 'ia';
      new.produto_id := v_prod.id;
      if v_prod.valor_padrao > 0 then new.value := v_prod.valor_padrao; end if;
    end if;
  end if;
  return new;
end $$;
revoke all on function public.crm_deals_pipeline_formulario() from public, anon, authenticated;

drop trigger if exists crm_deals_pipeline_formulario on public.crm_deals;
create trigger crm_deals_pipeline_formulario before insert on public.crm_deals
  for each row execute function public.crm_deals_pipeline_formulario();

-- ── 9) RLS: só admin ───────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['crm_produtos','crm_jornada_passos','crm_jornada_itens','cfg_listas','cfg_historico'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists admin_all on public.%I', t);
  end loop;
  foreach t in array array['crm_produtos','crm_jornada_passos','crm_jornada_itens','cfg_listas'] loop
    execute format('create policy admin_all on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;
-- Histórico: admin só lê. Quem grava é o gatilho (security definer).
create policy admin_all on public.cfg_historico for select to authenticated using (public.is_admin());


-- ════════════════════════════════════════════════════════════════════
-- DADOS INICIAIS (só se ainda não houver nenhum)
-- ════════════════════════════════════════════════════════════════════
do $$
declare v_ment uuid; v_clube uuid; v_impl uuid;
begin
  if not exists (select 1 from public.crm_produtos) then
    insert into public.crm_produtos (codigo, nome, cor, valor_padrao, portal_tipo, portal_plano, meses_clube, total_encontros, ordem) values
      ('mentoria',      'Mentoria Mãos na IA', '#22A060', 3000, 'mentorada', 'mentoria',    6, 6, 0),
      ('clube',         'Clube Mãos na IA',    '#60A5FA',  797, 'clube',     'clube_anual', 6, 0, 1),
      ('implementacao', 'Implementação de IA', '#A78BFA', 7500, null,        null,          0, 0, 2);
  end if;

  if not exists (select 1 from public.crm_jornada_passos) then
    select id into v_ment  from public.crm_produtos where codigo = 'mentoria';
    select id into v_clube from public.crm_produtos where codigo = 'clube';
    select id into v_impl  from public.crm_produtos where codigo = 'implementacao';

    -- Mentoria: 04-plataforma/whatsapp-grupos.md, modulo-boas-vindas.md e o plano do Clube
    insert into public.crm_jornada_passos (produto_id, titulo, descricao, dias, ordem) values
      (v_ment, 'Criar o grupo individual no WhatsApp', 'Nome: Mentoria · [Nome] & Jenne. Com o número de suporte.', 0, 0),
      (v_ment, 'Incluir no grupo geral Mãos na IA', 'Grupo de assinantes do Clube e mentoradas.', 0, 1),
      (v_ment, 'Liberar o portal e mandar o acesso', 'mentoria.jpgestaodescomplicada.com/entrar', 0, 2),
      (v_ment, 'Liberar o Clube (e-mail Google na pasta do Drive)', 'Sem o e-mail Google o vídeo não abre.', 0, 3),
      (v_ment, 'Liberar os vídeos iniciais', 'Boas-vindas e Configuração Inicial.', 1, 4),
      (v_ment, 'Enviar o formulário de diagnóstico', null, 1, 5),
      (v_ment, 'Agendar o 1º encontro', null, 2, 6),
      (v_ment, 'Fazer a trilha personalizada', 'A partir do diagnóstico.', 7, 7),
      (v_ment, 'Mensagem do dia 7: "Conseguiu configurar? Me mostra!"', null, 7, 8);

    -- Clube: plano do Clube (tarefas automáticas na entrada)
    insert into public.crm_jornada_passos (produto_id, titulo, descricao, dias, ordem) values
      (v_clube, 'Incluir no grupo geral Mãos na IA', null, 0, 0),
      (v_clube, 'Incluir o e-mail Google na pasta do Clube no Drive', 'Sem o e-mail Google o vídeo não abre.', 0, 1),
      (v_clube, 'Liberar o portal e mandar o acesso', 'mentoria.jpgestaodescomplicada.com/entrar', 0, 2),
      (v_clube, 'Liberar os vídeos iniciais', 'Boas-vindas e Configuração Inicial.', 1, 3),
      (v_clube, 'Mensagem do dia 7: "Conseguiu configurar? Me mostra!"', null, 7, 4),
      (v_clube, 'Check-in do dia 30', 'Perguntar o que já aplicou e o que travou.', 30, 5);

    -- Implementação: 07-esteira/implementacao-high-ticket.md (6 semanas)
    insert into public.crm_jornada_passos (produto_id, titulo, descricao, dias, ordem) values
      (v_impl, 'Criar o grupo da implementação', 'Com a dona e o ponto focal do time.', 0, 0),
      (v_impl, 'Reunião de diagnóstico e mapa dos 5 processos', 'Semana 1.', 7, 1),
      (v_impl, 'Configurar o ambiente de IA e as automações', 'Semanas 2 e 3.', 21, 2),
      (v_impl, 'Manual de uso por área', 'Semana 4.', 28, 3),
      (v_impl, 'Treinamento do time', 'Semana 5. Sessões ao vivo, gravadas.', 35, 4),
      (v_impl, 'Ajustes, relatório de antes e depois e entrega', 'Semana 6. Incluir "O que a IA não resolve sozinha".', 42, 5),
      (v_impl, '30 dias de suporte no grupo', null, 72, 6);
  end if;

  if not exists (select 1 from public.cfg_listas) then
    -- valor = o texto que já está gravado nos contatos e negócios
    insert into public.cfg_listas (lista, valor, rotulo, ordem) values
      ('crm_origem', 'indicacao',          'Indicação',          0),
      ('crm_origem', 'instagram',          'Instagram',          1),
      ('crm_origem', 'linkedin',           'LinkedIn',           2),
      ('crm_origem', 'site',               'Site',               3),
      ('crm_origem', 'evento',             'Evento',             4),
      ('crm_origem', 'aplicação mentoria', 'Aplicação da mentoria', 5),
      ('crm_origem', 'teste da bio',       'Teste da bio',       6),
      ('crm_origem', 'desafio 21 dias',    'Desafio 21 dias',    7),
      ('crm_origem', 'outro',              'Outro',              8),
      ('crm_motivo_perda', 'preco',        'Preço/orçamento',       0),
      ('crm_motivo_perda', 'prazo',        'Prazo',                 1),
      ('crm_motivo_perda', 'concorrente',  'Escolheu concorrente',  2),
      ('crm_motivo_perda', 'sem_retorno',  'Sumiu/sem retorno',     3),
      ('crm_motivo_perda', 'fora_perfil',  'Fora do perfil',        4),
      ('crm_motivo_perda', 'adiou',        'Adiou decisão',         5),
      ('crm_motivo_perda', 'outro',        'Outro',                 6);
  end if;

  -- Categoria do financeiro para as vendas de IA
  insert into public.fin_categories (name, kind, color)
  values ('Produtos de IA', 'receita', '#22A060')
  on conflict (name, kind) do nothing;
end $$;
