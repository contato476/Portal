-- ════════════════════════════════════════════════════════════════════
-- 32 · PLAYBOOK (copys, jornadas dos serviços e sistemas externos) · 21/10/2026
-- Rode este arquivo no SQL Editor do Supabase DO SISTEMA (jvtjhfganuuefswbnbrk).
-- Pode rodar mais de uma vez: só cria o que ainda não existe e só cadastra
-- os exemplos se as tabelas estiverem vazias.
--
-- Tabelas (prefixo pb_ = playbook):
--   pb_servicos     serviços (Mentoria, Clube, Workshop...)
--   pb_opcoes       listas editáveis: canal, momento e tipo da copy
--   pb_copys        as mensagens prontas
--   pb_etapas       etapas da jornada de cada serviço, em ordem
--   pb_etapa_copys  quais copys são usadas em cada etapa
--   pb_sistemas     atalhos para os outros sistemas (com indicadores)
--   pb_historico    quem mudou o quê e quando
-- Tudo só para admin (RLS com public.is_admin()).
-- ════════════════════════════════════════════════════════════════════

create table if not exists public.pb_servicos (
  id           uuid primary key default gen_random_uuid(),
  nome         text not null check (char_length(nome) between 1 and 80),
  cor          text not null default '#22A060' check (cor ~ '^#[0-9A-Fa-f]{6}$'),
  descricao    text,
  ordem        int not null default 0,
  arquivado_em timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists public.pb_opcoes (
  id           uuid primary key default gen_random_uuid(),
  lista        text not null check (lista in ('canal','momento','tipo')),
  nome         text not null check (char_length(nome) between 1 and 60),
  ordem        int not null default 0,
  arquivado_em timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- "on delete restrict": o banco não deixa apagar um serviço ou uma opção
-- que ainda tem copy usando. A tela oferece arquivar nesses casos.
create table if not exists public.pb_copys (
  id           uuid primary key default gen_random_uuid(),
  titulo       text not null check (char_length(titulo) between 1 and 120),
  texto        text not null check (char_length(texto) between 1 and 10000),
  observacao   text check (char_length(observacao) <= 2000),
  servico_id   uuid references public.pb_servicos(id) on delete restrict,   -- vazio = serve para todos
  canal_id     uuid references public.pb_opcoes(id) on delete restrict,
  momento_id   uuid references public.pb_opcoes(id) on delete restrict,
  tipo_id      uuid references public.pb_opcoes(id) on delete restrict,
  fixada       boolean not null default false,
  arquivado_em timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists public.pb_etapas (
  id           uuid primary key default gen_random_uuid(),
  servico_id   uuid not null references public.pb_servicos(id) on delete restrict,
  ordem        int not null default 0,
  titulo       text not null check (char_length(titulo) between 1 and 120),
  quando       text check (char_length(quando) <= 120),            -- ex.: "1 ou 2 dias depois do post"
  descricao    text check (char_length(descricao) <= 4000),        -- o que fazer nesta etapa
  crm_stage    text check (crm_stage in ('novo','contato','reuniao','proposta','negociacao','fechado','perdido')),
  arquivado_em timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists public.pb_etapa_copys (
  etapa_id uuid not null references public.pb_etapas(id) on delete cascade,
  copy_id  uuid not null references public.pb_copys(id) on delete cascade,
  ordem    int not null default 0,
  primary key (etapa_id, copy_id)
);

create table if not exists public.pb_sistemas (
  id           uuid primary key default gen_random_uuid(),
  nome         text not null check (char_length(nome) between 1 and 80),
  url          text not null check (url ~ '^https://'),
  descricao    text check (char_length(descricao) <= 500),
  indicador    text check (indicador in ('mentoria','maosnaia')),  -- quais números mostrar no card
  ordem        int not null default 0,
  arquivado_em timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists public.pb_historico (
  id          bigint generated always as identity primary key,
  tabela      text not null,
  registro_id uuid,
  acao        text not null,
  usuario_id  uuid default auth.uid(),
  em          timestamptz not null default now(),
  antes       jsonb,
  depois      jsonb
);

create index if not exists pb_copys_servico_idx on public.pb_copys (servico_id, arquivado_em);
create index if not exists pb_etapas_servico_idx on public.pb_etapas (servico_id, ordem);
create index if not exists pb_etapa_copys_copy_idx on public.pb_etapa_copys (copy_id);
create index if not exists pb_historico_reg_idx on public.pb_historico (tabela, registro_id);

-- ── updated_at automático (função já existe no 01_gestao_schema) ───
do $$
declare t text;
begin
  foreach t in array array['pb_servicos','pb_opcoes','pb_copys','pb_etapas','pb_sistemas'] loop
    execute format('drop trigger if exists %I_updated on public.%I', t, t);
    execute format('create trigger %I_updated before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;

-- ── Histórico de alterações ─────────────────────────────────────────
create or replace function public.pb_registrar_historico()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.pb_historico (tabela, registro_id, acao, antes, depois)
  values (
    tg_table_name,
    coalesce(new.id, old.id),
    lower(tg_op),
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end
  );
  return coalesce(new, old);
end $$;
revoke all on function public.pb_registrar_historico() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['pb_servicos','pb_opcoes','pb_copys','pb_etapas','pb_sistemas'] loop
    execute format('drop trigger if exists %I_hist on public.%I', t, t);
    execute format('create trigger %I_hist after insert or update or delete on public.%I for each row execute function public.pb_registrar_historico()', t, t);
  end loop;
end $$;

-- ── RLS: só admin ───────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['pb_servicos','pb_opcoes','pb_copys','pb_etapas','pb_etapa_copys','pb_sistemas','pb_historico'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists admin_all on public.%I', t);
  end loop;
  foreach t in array array['pb_servicos','pb_opcoes','pb_copys','pb_etapas','pb_etapa_copys','pb_sistemas'] loop
    execute format('create policy admin_all on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;
-- Histórico: admin só lê. Quem grava é o gatilho (security definer).
create policy admin_all on public.pb_historico for select to authenticated using (public.is_admin());


-- ════════════════════════════════════════════════════════════════════
-- DADOS INICIAIS (só se ainda não houver nenhum)
-- ════════════════════════════════════════════════════════════════════
do $$
declare
  v_mentoria uuid;
  c_grupos uuid; c_whats uuid; c_insta uuid;
  m_prosp uuid; m_contato uuid; m_convite uuid;
  t_post uuid; t_privada uuid; t_status uuid; t_story uuid; t_direct uuid;
  cp1 uuid; cp2 uuid; cp3 uuid; cp4 uuid; cp5 uuid; cp6 uuid; cp7 uuid;
  e1 uuid; e2 uuid; e3 uuid;
begin
  if not exists (select 1 from public.pb_servicos) then
    insert into public.pb_servicos (nome, cor, ordem) values
      ('Mentoria Mãos na IA',     '#22A060', 0),
      ('Clube Mãos na IA',        '#60A5FA', 1),
      ('Workshop',                '#E3B341', 2),
      ('Palestra',                '#F472B6', 3),
      ('Implementação de IA',     '#A78BFA', 4),
      ('Sistemas personalizados', '#2DD4BF', 5);
  end if;

  if not exists (select 1 from public.pb_opcoes) then
    insert into public.pb_opcoes (lista, nome, ordem) values
      ('canal','Grupos',0), ('canal','WhatsApp',1), ('canal','Instagram',2), ('canal','E-mail',3), ('canal','LinkedIn',4),
      ('momento','Prospecção',0), ('momento','Primeiro contato',1), ('momento','Convite para o diagnóstico',2),
      ('momento','Follow-up',3), ('momento','Pós-reunião',4), ('momento','Proposta',5), ('momento','Objeções',6), ('momento','Pós-venda',7),
      ('tipo','Post',0), ('tipo','Mensagem privada',1), ('tipo','Status',2), ('tipo','Story',3), ('tipo','Direct',4), ('tipo','E-mail',5);
  end if;

  if not exists (select 1 from public.pb_sistemas) then
    insert into public.pb_sistemas (nome, url, descricao, indicador, ordem) values
      ('Mãos na IA · painel', 'https://maosnaia.jpgestaodescomplicada.com/painel',
       'Formulários: aplicações da mentoria, teste da bio, masterclass e Desafio 21 dias.', 'maosnaia', 0),
      ('Portal da mentoria', 'https://mentoria.jpgestaodescomplicada.com/entrar',
       'Mentoradas e assinantes do Clube: encontros, aulas, tarefas e check-ins.', 'mentoria', 1);
  end if;

  -- Copys e jornada de exemplo: só se não houver nenhuma copy ainda
  if exists (select 1 from public.pb_copys) then return; end if;

  select id into v_mentoria from public.pb_servicos where nome = 'Mentoria Mãos na IA' limit 1;
  select id into c_grupos  from public.pb_opcoes where lista='canal'   and nome='Grupos' limit 1;
  select id into c_whats   from public.pb_opcoes where lista='canal'   and nome='WhatsApp' limit 1;
  select id into c_insta   from public.pb_opcoes where lista='canal'   and nome='Instagram' limit 1;
  select id into m_prosp   from public.pb_opcoes where lista='momento' and nome='Prospecção' limit 1;
  select id into m_contato from public.pb_opcoes where lista='momento' and nome='Primeiro contato' limit 1;
  select id into m_convite from public.pb_opcoes where lista='momento' and nome='Convite para o diagnóstico' limit 1;
  select id into t_post    from public.pb_opcoes where lista='tipo'    and nome='Post' limit 1;
  select id into t_privada from public.pb_opcoes where lista='tipo'    and nome='Mensagem privada' limit 1;
  select id into t_status  from public.pb_opcoes where lista='tipo'    and nome='Status' limit 1;
  select id into t_story   from public.pb_opcoes where lista='tipo'    and nome='Story' limit 1;
  select id into t_direct  from public.pb_opcoes where lista='tipo'    and nome='Direct' limit 1;

  insert into public.pb_copys (titulo, servico_id, canal_id, momento_id, tipo_id, fixada, observacao, texto) values
  ('Post no grupo', v_mentoria, c_grupos, m_prosp, t_post, true,
   'Só onde as regras do grupo permitem divulgar. Se não tiver certeza, peça antes a quem administra.',
$t$Meninas, queria dividir uma coisa com vocês 💚

Estou com um desafio de 21 dias no Instagram, ensinando a organizar o negócio com o Claude, e o que mais tenho ouvido é: “eu não sabia que dava para fazer isso com a IA”.

Por isso abri algumas vagas para acompanhar de perto quem quer montar um time de assistentes de IA, um para cada área do negócio, e tirar o trabalho repetido das próprias mãos. Mesmo quem ainda não usa IA no dia a dia.

Antes de tudo, faço um diagnóstico com cada uma para ver por onde começar. Quem quiser, me chama no privado 😉$t$)
  returning id into cp1;

  insert into public.pb_copys (titulo, servico_id, canal_id, momento_id, tipo_id, observacao, texto) values
  ('Privado para as mais quentes do grupo', v_mentoria, c_grupos, m_contato, t_privada,
   'Mandar um ou dois dias depois do post. Os ganchos por perfil (mentora, professora, tricologista...) estão em mensagens-pos-masterclass-mentora.md.',
$t$Oi, [nome]! Tudo bem?

Não sei se você viu o que eu postei no grupo, mas resolvi te chamar aqui porque pensei em você. [frase pessoal: o que você sabe do negócio dela]

Me conta: hoje você já usa IA no seu negócio? O que mais toma o seu tempo na rotina?$t$)
  returning id into cp2;

  insert into public.pb_copys (titulo, servico_id, canal_id, momento_id, tipo_id, observacao, texto) values
  ('Status do WhatsApp', v_mentoria, c_whats, m_prosp, t_status,
   'Versão curta do post do grupo. Quem responder ao status já é contato quente.',
$t$Estou com um desafio de 21 dias ensinando a organizar o negócio com o Claude, e abri algumas vagas para acompanhar de perto quem quer montar um time de assistentes de IA e tirar o trabalho repetido das próprias mãos.

Antes, faço um diagnóstico para ver por onde começar. Quer? Me responde aqui 😉$t$)
  returning id into cp3;

  insert into public.pb_copys (titulo, servico_id, canal_id, momento_id, tipo_id, observacao, texto) values
  ('Individual para quem tem negócio e você conhece', v_mentoria, c_whats, m_contato, t_privada,
   'Mande uma a uma, nunca por lista de transmissão.',
$t$Oi, [nome]! Tudo bem? Aqui é a Jenneffer 😊

Lembrei de você esses dias. Tenho trabalhado bastante com IA para organizar a rotina de quem tem negócio, e fiquei pensando em como isso poderia te ajudar com [algo do negócio dela].

Me conta, como estão as coisas por aí? Você já usa IA no dia a dia?$t$)
  returning id into cp4;

  insert into public.pb_copys (titulo, servico_id, canal_id, momento_id, tipo_id, observacao, texto) values
  ('Caixinha ou enquete nos stories', v_mentoria, c_insta, m_prosp, t_story,
   'Postar depois de um conteúdo do desafio. Quem responder recebe o direct.',
$t$Quer que eu olhe a sua rotina e diga por onde começar com a IA?$t$)
  returning id into cp5;

  insert into public.pb_copys (titulo, servico_id, canal_id, momento_id, tipo_id, observacao, texto) values
  ('Direct para quem interage', v_mentoria, c_insta, m_contato, t_direct,
   'Para quem responde stories, comenta ou está no desafio.',
$t$Oi, [nome]! Vi que você [respondeu meu story / está no desafio / comentou no post] e fiquei curiosa sobre o seu negócio. Você trabalha com o quê?$t$)
  returning id into cp6;

  insert into public.pb_copys (titulo, servico_id, canal_id, momento_id, tipo_id, observacao, texto) values
  ('Direct: resposta e convite para o diagnóstico', v_mentoria, c_insta, m_convite, t_direct,
   'Quando ela responder ao direct anterior.',
$t$Que legal! Pelo que você contou, acho que a IA pode tirar bastante coisa das suas mãos, principalmente [algo que ela falou]. Faço um diagnóstico para ver por onde começar. Posso te mandar o meu link de agendamento?$t$)
  returning id into cp7;

  -- Jornada inicial da Mentoria, montada a partir dessas copys (edite à vontade na tela)
  if v_mentoria is not null and not exists (select 1 from public.pb_etapas) then
    insert into public.pb_etapas (servico_id, ordem, titulo, quando, descricao, crm_stage) values
      (v_mentoria, 0, 'Divulgar', null,
       'Post nos grupos (só onde as regras permitem), status do WhatsApp e caixinha nos stories depois de um conteúdo do desafio.', null)
      returning id into e1;
    insert into public.pb_etapas (servico_id, ordem, titulo, quando, descricao, crm_stage) values
      (v_mentoria, 1, 'Chamar no privado', '1 ou 2 dias depois do post',
       'Privado para as mais quentes do grupo, mensagem individual para quem tem negócio e você conhece, direct para quem interagiu no Instagram.', 'contato')
      returning id into e2;
    insert into public.pb_etapas (servico_id, ordem, titulo, quando, descricao, crm_stage) values
      (v_mentoria, 2, 'Convidar para o diagnóstico', 'Quando ela contar do negócio',
       'Mostrar onde a IA tira trabalho das mãos dela e mandar o link de agendamento.', 'reuniao')
      returning id into e3;
    insert into public.pb_etapa_copys (etapa_id, copy_id, ordem) values
      (e1, cp1, 0), (e1, cp3, 1), (e1, cp5, 2),
      (e2, cp2, 0), (e2, cp4, 1), (e2, cp6, 2),
      (e3, cp7, 0);
  end if;
end $$;
