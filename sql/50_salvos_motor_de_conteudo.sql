-- ════════════════════════════════════════════════════════════════════
-- 50_SALVOS_MOTOR_DE_CONTEUDO.SQL
-- O quadro dos salvos e o motor de conteúdo (16/11/2026).
-- Depende do sql/48_salvos_ideias.sql.
--
-- POR QUÊ ISTO EXISTE: a tela Salvos ganha um quadro em colunas. Você
-- arrasta a ideia para "Quero fazer", escolhe Reels ou carrossel e o
-- destino (conteúdo extra ou mês seguinte). Uma rotina do Claude, de
-- segunda a sexta, lê o quadro e produz: escreve o texto, espera a sua
-- aprovação, faz a arte do carrossel, espera a sua aprovação de novo.
--
-- AS ETAPAS (coluna stage)
--   ideia          Novas ideias (chegam da varredura, com dois esboços)
--   quero_fazer    Você escolheu formato e destino: o motor escreve
--   texto_aprovar  Texto pronto: você aprova ou pede ajuste
--   arte_aprovar   Só carrossel: o motor faz a arte, você aprova ou pede ajuste
--   pronto         Aprovado: pronto para postar (ou para gravar, no Reels)
--   postado        Publicado
--   nao_fazer      Guardado, fora do caminho
--
-- O MOTOR SÓ FAZ O QUE ESTAS FUNÇÕES DEIXAM: ler a fila e entregar
-- texto, esboço e arte. Ele não aprova nada e não move cartão para
-- "pronto": isso é só seu, pela tela.
--
-- COMO USAR: cole o arquivo inteiro no SQL Editor e clique em RUN.
-- Pode rodar de novo. O token continua o mesmo do sql/48.
-- ════════════════════════════════════════════════════════════════════


-- ──────────── 1. COLUNAS NOVAS ────────────
alter table public.salvos_ideias
  add column if not exists stage            text not null default 'ideia',
  add column if not exists chosen_format    text,     -- reels ou carrossel (você escolhe)
  add column if not exists destino          text,     -- extra ou proximo_mes
  add column if not exists sketch_reels     text,     -- esboço curto de Reels
  add column if not exists sketch_carrossel text,     -- esboço curto de carrossel
  add column if not exists final_text       text,     -- roteiro ou texto slide a slide
  add column if not exists caption          text,     -- legenda, CTA e hashtags
  add column if not exists art_url          text,     -- link da prévia da arte
  add column if not exists art_path         text,     -- pasta dos arquivos finais
  add column if not exists adjust_request   text,     -- o que você pediu para mudar
  add column if not exists motor_note       text,     -- recado do motor na entrega
  add column if not exists stage_changed_at timestamptz not null default now(),
  add column if not exists log              jsonb not null default '[]'::jsonb;   -- histórico das etapas

alter table public.salvos_ideias drop constraint if exists salvos_stage_chk;
alter table public.salvos_ideias add  constraint salvos_stage_chk
  check (stage in ('ideia','quero_fazer','texto_aprovar','arte_aprovar','pronto','postado','nao_fazer'));
alter table public.salvos_ideias drop constraint if exists salvos_chosen_format_chk;
alter table public.salvos_ideias add  constraint salvos_chosen_format_chk
  check (chosen_format is null or chosen_format in ('reels','carrossel'));
alter table public.salvos_ideias drop constraint if exists salvos_destino_chk;
alter table public.salvos_ideias add  constraint salvos_destino_chk
  check (destino is null or destino in ('extra','proximo_mes'));
-- Não entra em produção sem formato e destino escolhidos.
alter table public.salvos_ideias drop constraint if exists salvos_producao_chk;
alter table public.salvos_ideias add  constraint salvos_producao_chk
  check (stage in ('ideia','nao_fazer') or (chosen_format is not null and destino is not null));

create index if not exists idx_salvos_stage on public.salvos_ideias(stage);

-- Quem já estava marcado antes do quadro existir.
update public.salvos_ideias set stage = 'nao_fazer' where status = 'descartado' and stage = 'ideia';
update public.salvos_ideias set stage = 'postado', chosen_format = coalesce(chosen_format, case when idea_format in ('reels','carrossel') then idea_format else 'carrossel' end), destino = coalesce(destino, 'extra')
 where status = 'postado' and stage = 'ideia';


-- ──────────── 2. ETAPA E SITUAÇÃO ANDAM JUNTAS ────────────
-- A lista usa "status" e o quadro usa "stage". Este gatilho mantém os
-- dois coerentes e anota cada mudança de etapa no histórico do cartão.
create or replace function public.salvos_sync_stage()
returns trigger language plpgsql as $$
begin
  if new.stage is distinct from old.stage then
    new.stage_changed_at := now();
    new.log := coalesce(old.log, '[]'::jsonb) || jsonb_build_object(
      'quando', to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
      'de', old.stage, 'para', new.stage);
    if new.status <> 'fora_do_foco' or new.stage <> 'ideia' then
      new.status := case new.stage
        when 'ideia'     then 'novo'
        when 'postado'   then 'postado'
        when 'nao_fazer' then 'descartado'
        else 'vou_postar' end;
    end if;
    -- Ao sair de uma coluna de aprovação para frente, o pedido de ajuste perde o sentido.
    if new.stage in ('pronto','postado','nao_fazer','ideia') then new.adjust_request := null; end if;
  elsif new.status is distinct from old.status then
    -- Mudança feita pelos botões da lista.
    if    new.status = 'descartado' then new.stage := 'nao_fazer';
    elsif new.status = 'postado' and new.chosen_format is not null and new.destino is not null then new.stage := 'postado';
    elsif new.status = 'novo' and old.stage in ('nao_fazer','postado') then new.stage := 'ideia';
    end if;
    if new.stage is distinct from old.stage then new.stage_changed_at := now(); end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_salvos_stage on public.salvos_ideias;
create trigger trg_salvos_stage
  before update on public.salvos_ideias
  for each row execute function public.salvos_sync_stage();


-- ──────────── 3. A VARREDURA GRAVA TAMBÉM OS DOIS ESBOÇOS ────────────
-- Mesma função do sql/48, com sketch_reels e sketch_carrossel.
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
     sketch_reels, sketch_carrossel,
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
    i->>'sketch_reels', i->>'sketch_carrossel',
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
    idea_acdv = excluded.idea_acdv,
    sketch_reels = excluded.sketch_reels, sketch_carrossel = excluded.sketch_carrossel,
    status = excluded.status, analyzed_at = excluded.analyzed_at
  where s.analyzed_at is null;

  get diagnostics v_count = row_count;
  return v_count;
end $$;


-- ──────────── 4. A FILA DO MOTOR ────────────
-- Devolve só os cartões em que o motor tem algo a fazer, com o motivo:
--   esbocos  ideia nova ainda sem os dois esboços
--   texto    você moveu para "Quero fazer": escrever o texto completo
--   ajuste_texto / ajuste_arte   você pediu ajuste
--   arte     texto de carrossel aprovado: fazer a arte
create or replace function public.salvos_queue(p_token text)
returns table(tarefa text, ficha jsonb)
language plpgsql security definer set search_path = public
as $$
begin
  perform public.salvos_check_token(p_token);
  return query
    select t.tarefa, to_jsonb(s) - 'log'
    from public.salvos_ideias s
    cross join lateral (select case
        when s.stage = 'quero_fazer'                                        then 'texto'
        when s.stage = 'texto_aprovar' and s.adjust_request is not null     then 'ajuste_texto'
        when s.stage = 'arte_aprovar'  and s.adjust_request is not null     then 'ajuste_arte'
        when s.stage = 'arte_aprovar'  and s.art_url is null and s.art_path is null then 'arte'
        when s.stage = 'ideia' and s.status = 'novo' and s.analyzed_at is not null
             and (s.sketch_reels is null or s.sketch_carrossel is null)     then 'esbocos'
      end as tarefa) t
    where t.tarefa is not null
    order by case t.tarefa when 'ajuste_texto' then 1 when 'ajuste_arte' then 2 when 'texto' then 3 when 'arte' then 4 else 5 end,
             s.stage_changed_at;
end $$;


-- ──────────── 5. A ENTREGA DO MOTOR ────────────
-- p_patch aceita só: sketch_reels, sketch_carrossel, final_text, caption,
-- art_url, art_path, motor_note. Qualquer outro campo é ignorado.
-- A única mudança de etapa permitida é quero_fazer → texto_aprovar.
create or replace function public.salvos_deliver(p_token text, p_id uuid, p_patch jsonb)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  r public.salvos_ideias%rowtype;
  v_url text := nullif(p_patch->>'art_url', '');
begin
  perform public.salvos_check_token(p_token);
  select * into r from public.salvos_ideias where id = p_id for update;
  if not found then raise exception 'ficha não encontrada'; end if;
  if v_url is not null and v_url !~ '^https://' then
    raise exception 'art_url precisa começar com https://';
  end if;

  update public.salvos_ideias set
    sketch_reels     = coalesce(nullif(p_patch->>'sketch_reels', ''),     sketch_reels),
    sketch_carrossel = coalesce(nullif(p_patch->>'sketch_carrossel', ''), sketch_carrossel),
    final_text       = coalesce(nullif(p_patch->>'final_text', ''),       final_text),
    caption          = coalesce(nullif(p_patch->>'caption', ''),          caption),
    art_url          = coalesce(v_url,                                     art_url),
    art_path         = coalesce(nullif(p_patch->>'art_path', ''),         art_path),
    motor_note       = coalesce(nullif(p_patch->>'motor_note', ''),       motor_note),
    -- Entregou o texto de quem estava em "Quero fazer": vai para a sua aprovação.
    stage = case when r.stage = 'quero_fazer' and nullif(p_patch->>'final_text', '') is not null
                 then 'texto_aprovar' else stage end,
    -- Entregou o que o ajuste pedia: limpa o pedido.
    adjust_request = case
      when r.stage = 'texto_aprovar' and nullif(p_patch->>'final_text', '') is not null then null
      when r.stage = 'arte_aprovar'  and (v_url is not null or nullif(p_patch->>'art_path', '') is not null) then null
      else adjust_request end
  where id = p_id;

  return (select stage from public.salvos_ideias where id = p_id);
end $$;

revoke all on function public.salvos_sync_stage()               from public, anon, authenticated;
revoke all on function public.salvos_queue(text)                from public;
revoke all on function public.salvos_deliver(text, uuid, jsonb) from public;
grant execute on function public.salvos_queue(text)                to anon, authenticated;
grant execute on function public.salvos_deliver(text, uuid, jsonb) to anon, authenticated;

-- Conferência: quantos cartões há em cada etapa.
select stage as etapa, count(*) as cartoes from public.salvos_ideias group by stage order by 1;
