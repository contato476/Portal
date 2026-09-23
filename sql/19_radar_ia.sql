-- ════════════════════════════════════════════════════════════════════
-- 19_RADAR_IA.SQL
-- Radar IA — novidades de IA, dores do público e concorrentes, todo dia.
--
-- POR QUÊ ISTO EXISTE: uma rotina na nuvem (Claude, todo dia às 8h)
-- pesquisa o que a Anthropic lançou, o que está acontecendo em IA, o que
-- as empresárias estão perguntando e o que os concorrentes estão fazendo.
-- O resultado cai aqui, e a página radar.html mostra tudo com botões
-- para marcar: testei, vou postar, postado, virou produto.
--
-- COMO A ROTINA GRAVA SEM TER A SUA SENHA
--   A rotina não faz login. Ela chama a função radar_ingest() passando um
--   TOKEN que só serve para isso: inserir itens no radar. O token fica na
--   tabela radar_secrets, que ninguém lê pelo navegador (RLS sem política).
--   Se o token vazar, o pior que acontece é alguém inserir notícia no
--   radar. Para trocar: rode o bloco "TROCAR O TOKEN" no fim do arquivo.
--
-- COMO USAR: cole o arquivo inteiro no SQL Editor e clique em RUN.
-- É idempotente. A última consulta mostra o token: copie e mande
-- para o Claude configurar a rotina.
-- ════════════════════════════════════════════════════════════════════


-- ──────────── 1. OS ITENS DO RADAR ────────────
create table if not exists public.radar_items (
  id              uuid primary key default gen_random_uuid(),
  radar_date      date not null default (now() at time zone 'America/Sao_Paulo')::date,

  -- diario = radar de todo dia; semanal = radar de segunda (dores e concorrentes)
  edition         text not null default 'diario'
                  check (edition in ('diario','semanal')),

  -- resumo      = as 3 linhas do dia, abre o radar
  -- anthropic   = lançamento da Anthropic/Claude
  -- ia          = novidade do mercado de IA
  -- pratica     = o que as pessoas estão fazendo com IA (casos, usos)
  -- dor         = o que o público está perguntando/sofrendo
  -- concorrente = movimento de concorrente
  -- produto     = ideia de produto que nasce das dores
  category        text not null
                  check (category in ('resumo','anthropic','ia','pratica','dor','concorrente','produto')),

  title           text not null,
  summary         text,             -- o que é, em linguagem simples
  why_it_matters  text,             -- por que importa para empresárias / para você
  try_this        text,             -- teste isso hoje
  post_idea       text,             -- ideia de post no seu tom
  source_name     text,
  source_url      text,
  relevance       smallint not null default 3 check (relevance between 1 and 5),

  -- O seu check
  status          text not null default 'novo'
                  check (status in ('novo','testei','vou_postar','postado','virou_produto','descartado')),
  favorite        boolean not null default false,
  notes           text,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists idx_radar_date     on public.radar_items(radar_date desc, relevance desc);
create index if not exists idx_radar_status   on public.radar_items(status);
create index if not exists idx_radar_category on public.radar_items(category);
-- A mesma fonte não entra duas vezes no mesmo dia (a rotina pode rodar de novo).
create unique index if not exists uq_radar_url_dia
  on public.radar_items(radar_date, source_url) where source_url is not null;

create or replace function public.radar_touch_updated()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists trg_radar_updated on public.radar_items;
create trigger trg_radar_updated
  before update on public.radar_items
  for each row execute function public.radar_touch_updated();

alter table public.radar_items enable row level security;
drop policy if exists "admin_all" on public.radar_items;
create policy "admin_all" on public.radar_items
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());


-- ──────────── 2. O TOKEN DA ROTINA ────────────
-- RLS ligado e NENHUMA política: pelo navegador ninguém lê nem escreve.
-- Só as funções abaixo (security definer) enxergam.
create table if not exists public.radar_secrets (
  id         int primary key default 1 check (id = 1),
  token      text not null,
  created_at timestamptz not null default now()
);
alter table public.radar_secrets enable row level security;

insert into public.radar_secrets(id, token)
values (1, replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (id) do nothing;


-- ──────────── 3. A ROTINA GRAVA OS ITENS ────────────
-- p_items: lista JSON de itens com os mesmos nomes de coluna.
-- Devolve quantos entraram (repetidos no mesmo dia são ignorados).
create or replace function public.radar_ingest(p_token text, p_items jsonb)
returns int
language plpgsql security definer set search_path = public
as $$
declare
  v_count int;
begin
  if p_token is null or p_token <> (select token from public.radar_secrets where id = 1) then
    raise exception 'token inválido';
  end if;
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'p_items precisa ser uma lista';
  end if;

  insert into public.radar_items
    (radar_date, edition, category, title, summary, why_it_matters,
     try_this, post_idea, source_name, source_url, relevance)
  select
    coalesce((i->>'radar_date')::date, (now() at time zone 'America/Sao_Paulo')::date),
    coalesce(i->>'edition', 'diario'),
    i->>'category',
    left(i->>'title', 300),
    i->>'summary',
    i->>'why_it_matters',
    i->>'try_this',
    i->>'post_idea',
    i->>'source_name',
    nullif(i->>'source_url', ''),
    least(5, greatest(1, coalesce((i->>'relevance')::int, 3)))
  from jsonb_array_elements(p_items) as i
  on conflict do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end $$;


-- ──────────── 4. A ROTINA CONSULTA O QUE JÁ TROUXE ────────────
-- Para não repetir notícia dos últimos dias.
create or replace function public.radar_recent(p_token text, p_days int default 14)
returns table(radar_date date, category text, title text, source_url text)
language plpgsql security definer set search_path = public
as $$
begin
  if p_token is null or p_token <> (select token from public.radar_secrets where id = 1) then
    raise exception 'token inválido';
  end if;
  return query
    select r.radar_date, r.category, r.title, r.source_url
    from public.radar_items r
    where r.radar_date >= (now() at time zone 'America/Sao_Paulo')::date - p_days
    order by r.radar_date desc;
end $$;

revoke all on function public.radar_ingest(text, jsonb) from public;
revoke all on function public.radar_recent(text, int)   from public;
grant execute on function public.radar_ingest(text, jsonb) to anon, authenticated;
grant execute on function public.radar_recent(text, int)   to anon, authenticated;


-- ──────────── 5. MOSTRAR O TOKEN ────────────
-- Copie o valor e mande para o Claude.
select token as token_da_rotina from public.radar_secrets where id = 1;


-- ──────────── TROCAR O TOKEN (só se precisar) ────────────
-- update public.radar_secrets set token = replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') where id = 1;
-- select token from public.radar_secrets;
