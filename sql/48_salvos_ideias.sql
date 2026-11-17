-- ════════════════════════════════════════════════════════════════════
-- 48_SALVOS_IDEIAS.SQL
-- Salvos do Instagram viram banco de ideias (16/11/2026).
--
-- POR QUÊ ISTO EXISTE: toda segunda o Claude, no seu computador, lê os
-- posts que você salvou no Instagram, analisa cada um (gancho, formato,
-- estrutura, por que funciona) e propõe uma ideia adaptada ao seu
-- posicionamento. O resultado cai aqui, e a página salvos.html mostra
-- tudo para você favoritar, marcar "vou postar" ou descartar.
--
-- COMO O CLAUDE GRAVA SEM TER A SUA SENHA
--   Mesmo desenho do Radar IA (sql/19): ele chama funções passando um
--   TOKEN que só serve para isso. O token fica em salvos_secrets, que
--   ninguém lê pelo navegador (RLS sem política). Se o token vazar, o
--   pior que acontece é alguém inserir uma ficha nesta lista.
--
-- LGPD: a tabela guarda só dado público de post (link, @ do criador,
-- curtidas, comentários) e a análise. Nenhum dado de cliente ou contato.
--
-- COMO USAR: cole o arquivo inteiro no SQL Editor e clique em RUN.
-- Pode rodar de novo. A última consulta mostra o token: copie e cole no
-- arquivo .env da skill (não mande pelo chat).
-- ════════════════════════════════════════════════════════════════════


-- ──────────── 1. AS FICHAS ────────────
create table if not exists public.salvos_ideias (
  id             uuid primary key default gen_random_uuid(),
  captured_date  date not null default (now() at time zone 'America/Sao_Paulo')::date,

  -- De onde veio: varredura semanal, link colado por você ou arquivo exportado
  origin         text not null default 'varredura'
                 check (origin in ('varredura','link','exportacao')),

  -- A referência (dado público do post)
  source_url     text not null,
  creator        text,
  media_type     text check (media_type in ('reels','carrossel','post')),
  likes          int,
  comments       int,

  -- A análise
  hook_spoken    text,     -- primeira frase falada ou título da capa
  hook_visual    text,     -- o que aparece nos 3 primeiros segundos
  hook_type      text,     -- identificacao, curiosidade, beneficio, novidade...
  structure      text,     -- as partes, em ordem
  cta            text,
  why_it_works   text,
  take           text,     -- o que dá para levar
  avoid          text,     -- o que não levar
  transcript     text,     -- uso interno, nunca publicar
  fit            smallint check (fit between 1 and 5),   -- aderência ao seu posicionamento
  discard_reason text,     -- por que ficou fora do foco

  -- A ideia adaptada
  idea_title     text,
  idea_hook      text,
  idea_outline   text,
  idea_format    text check (idea_format in ('reels','carrossel','post','stories')),
  idea_acdv      text,

  -- O seu check
  status         text not null default 'novo'
                 check (status in ('novo','vou_postar','postado','descartado','fora_do_foco')),
  favorite       boolean not null default false,
  notes          text,

  analyzed_at    timestamptz,   -- vazio = link aguardando a próxima varredura
  unsaved_at     timestamptz,   -- quando o salvamento foi tirado no Instagram
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
-- O mesmo post não entra duas vezes.
create unique index if not exists uq_salvos_url     on public.salvos_ideias(source_url);
create index        if not exists idx_salvos_status on public.salvos_ideias(status);
create index        if not exists idx_salvos_data   on public.salvos_ideias(captured_date desc);

drop trigger if exists trg_salvos_updated on public.salvos_ideias;
create trigger trg_salvos_updated
  before update on public.salvos_ideias
  for each row execute function public.radar_touch_updated();   -- mesma função do Radar (sql/19)

alter table public.salvos_ideias enable row level security;
drop policy if exists "admin_all" on public.salvos_ideias;
create policy "admin_all" on public.salvos_ideias
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());


-- ──────────── 2. O TOKEN ────────────
-- RLS ligado e NENHUMA política: só as funções abaixo enxergam.
create table if not exists public.salvos_secrets (
  id         int primary key default 1 check (id = 1),
  token      text not null,
  created_at timestamptz not null default now()
);
alter table public.salvos_secrets enable row level security;

insert into public.salvos_secrets(id, token)
values (1, replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (id) do nothing;

create or replace function public.salvos_check_token(p_token text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if p_token is null or p_token <> (select token from public.salvos_secrets where id = 1) then
    raise exception 'token inválido';
  end if;
end $$;


-- ──────────── 3. GRAVAR AS FICHAS ────────────
-- p_items: lista JSON com os mesmos nomes de coluna.
-- Link novo entra. Link que você cadastrou e ainda aguarda análise é
-- completado. Link já analisado é ignorado (o seu check não é mexido).
create or replace function public.salvos_ingest(p_token text, p_items jsonb)
returns int
language plpgsql security definer set search_path = public
as $$
declare
  v_count int;
begin
  perform public.salvos_check_token(p_token);
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'p_items precisa ser uma lista';
  end if;

  insert into public.salvos_ideias as s
    (origin, source_url, creator, media_type, likes, comments,
     hook_spoken, hook_visual, hook_type, structure, cta, why_it_works,
     take, avoid, transcript, fit, discard_reason,
     idea_title, idea_hook, idea_outline, idea_format, idea_acdv,
     status, analyzed_at)
  select
    coalesce(i->>'origin', 'varredura'),
    split_part(i->>'source_url', '?', 1),
    left(i->>'creator', 80),
    i->>'media_type',
    (i->>'likes')::int,
    (i->>'comments')::int,
    i->>'hook_spoken', i->>'hook_visual', left(i->>'hook_type', 40),
    i->>'structure', i->>'cta', i->>'why_it_works',
    i->>'take', i->>'avoid', i->>'transcript',
    case when i->>'fit' is null then null else least(5, greatest(1, (i->>'fit')::int)) end,
    i->>'discard_reason',
    left(i->>'idea_title', 300), i->>'idea_hook', i->>'idea_outline',
    i->>'idea_format', left(i->>'idea_acdv', 20),
    case when i->>'status' = 'fora_do_foco' then 'fora_do_foco' else 'novo' end,
    now()
  from jsonb_array_elements(p_items) as i
  where coalesce(i->>'source_url', '') like 'https://www.instagram.com/%'
  on conflict (source_url) do update set
    creator = excluded.creator, media_type = excluded.media_type,
    likes = excluded.likes, comments = excluded.comments,
    hook_spoken = excluded.hook_spoken, hook_visual = excluded.hook_visual,
    hook_type = excluded.hook_type, structure = excluded.structure,
    cta = excluded.cta, why_it_works = excluded.why_it_works,
    take = excluded.take, avoid = excluded.avoid, transcript = excluded.transcript,
    fit = excluded.fit, discard_reason = excluded.discard_reason,
    idea_title = excluded.idea_title, idea_hook = excluded.idea_hook,
    idea_outline = excluded.idea_outline, idea_format = excluded.idea_format,
    idea_acdv = excluded.idea_acdv, status = excluded.status,
    analyzed_at = excluded.analyzed_at
  where s.analyzed_at is null;

  get diagnostics v_count = row_count;
  return v_count;
end $$;


-- ──────────── 4. O QUE JÁ ESTÁ NA LISTA ────────────
-- Para a varredura não analisar duas vezes e saber o que está pendente.
create or replace function public.salvos_known(p_token text)
returns table(source_url text, pendente boolean, removido boolean)
language plpgsql security definer set search_path = public
as $$
begin
  perform public.salvos_check_token(p_token);
  return query
    select s.source_url, s.analyzed_at is null, s.unsaved_at is not null
    from public.salvos_ideias s
    order by s.created_at desc;
end $$;


-- ──────────── 5. MARCAR QUE SAIU DOS SALVOS DO INSTAGRAM ────────────
create or replace function public.salvos_mark_unsaved(p_token text, p_urls text[])
returns int
language plpgsql security definer set search_path = public
as $$
declare
  v_count int;
begin
  perform public.salvos_check_token(p_token);
  update public.salvos_ideias
     set unsaved_at = now()
   where source_url = any(p_urls) and unsaved_at is null and analyzed_at is not null;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.salvos_check_token(text)          from public, anon, authenticated;
revoke all on function public.salvos_ingest(text, jsonb)        from public;
revoke all on function public.salvos_known(text)                from public;
revoke all on function public.salvos_mark_unsaved(text, text[]) from public;
grant execute on function public.salvos_ingest(text, jsonb)        to anon, authenticated;
grant execute on function public.salvos_known(text)                to anon, authenticated;
grant execute on function public.salvos_mark_unsaved(text, text[]) to anon, authenticated;


-- ──────────── 6. MOSTRAR O TOKEN ────────────
-- Copie o valor e cole no .env da skill (SALVOS_TOKEN=...).
select token as token_dos_salvos from public.salvos_secrets where id = 1;


-- ──────────── TROCAR O TOKEN (só se precisar) ────────────
-- update public.salvos_secrets set token = replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') where id = 1;
-- select token from public.salvos_secrets;
