-- ════════════════════════════════════════════════════════════════════
-- 21 · NOVIDADES DE FORA (formulários do Mãos na IA → sistema)
-- Rode este arquivo no SQL Editor do Supabase DO SISTEMA (jvtjhfganuuefswbnbrk).
--
-- O que faz:
--   · Cria a tabela "novidades" (aparece na página novidades.html, com o
--     contador vermelho no menu).
--   · Cria a função novidades_ingest, chamada pelo banco dos formulários
--     (workshop) sempre que chega uma resposta nova. Ela é protegida por token,
--     no mesmo esquema do Radar IA: o token nunca vai para o navegador.
--   · Aplicação da mentoria: além da novidade, cria o contato no CRM (lead),
--     uma negociação em "Novo" e a tarefa "Chamar no WhatsApp".
-- No fim, mostra o TOKEN: copie e cole no SQL do outro banco.
-- ════════════════════════════════════════════════════════════════════

-- ──────────── 1. TABELA DE NOVIDADES ────────────
create table if not exists public.novidades (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  origem      text not null check (origem in ('aplicacao','masterclass')),
  source_id   uuid not null,                 -- id da resposta no banco dos formulários
  titulo      text not null,
  resumo      text,
  dados       jsonb not null default '{}'::jsonb,
  link        text,                          -- abre a resposta no painel dos formulários
  status      text not null default 'novo' check (status in ('novo','visto','arquivado')),
  visto_em    timestamptz,
  contact_id  uuid references public.crm_contacts(id) on delete set null,
  deal_id     uuid references public.crm_deals(id) on delete set null,
  unique (origem, source_id)                 -- a mesma resposta nunca entra duas vezes
);
create index if not exists idx_novidades_status on public.novidades(status, created_at desc);

alter table public.novidades enable row level security;
drop policy if exists "admin_all" on public.novidades;
create policy "admin_all" on public.novidades
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());


-- ──────────── 2. O TOKEN ────────────
-- RLS ligado e NENHUMA política: pelo navegador ninguém lê.
create table if not exists public.novidades_secrets (
  id         int primary key default 1 check (id = 1),
  token      text not null,
  created_at timestamptz not null default now()
);
alter table public.novidades_secrets enable row level security;

insert into public.novidades_secrets(id, token)
values (1, replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (id) do nothing;


-- ──────────── 3. RECEBER UMA NOVIDADE ────────────
-- Chamada pelo banco dos formulários (pg_net), uma vez por resposta nova.
-- p_dados: a linha da resposta em JSON (sem o consentimento).
create or replace function public.novidades_ingest(
  p_token text, p_origem text, p_source_id uuid, p_dados jsonb
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id      uuid;
  v_contato uuid;
  v_deal    uuid;
  v_nome    text := left(coalesce(nullif(btrim(p_dados->>'nome'), ''), 'Sem nome'), 120);
  v_hoje    date := (now() at time zone 'America/Sao_Paulo')::date;
  v_base    text := 'https://maosnaia.jpgestaodescomplicada.com/painel/';
begin
  if p_token is null or p_token <> (select token from public.novidades_secrets where id = 1) then
    raise exception 'token inválido';
  end if;
  if p_origem not in ('aplicacao','masterclass') then
    raise exception 'origem inválida';
  end if;
  if jsonb_typeof(p_dados) <> 'object' then
    raise exception 'p_dados precisa ser um objeto';
  end if;

  insert into public.novidades (origem, source_id, titulo, resumo, dados, link)
  values (
    p_origem,
    p_source_id,
    case p_origem when 'aplicacao' then 'Aplicação para a mentoria · ' || v_nome
                  else 'Formulário da Masterclass · ' || v_nome end,
    left(case p_origem
      when 'aplicacao' then concat_ws(' · ', p_dados->>'faturamento', p_dados->>'equipe', 'Quer começar: ' || (p_dados->>'quando_comecar'))
      else 'Onde travou: ' || coalesce(p_dados->>'onde_travou', '—') end, 500),
    p_dados,
    v_base || case p_origem when 'aplicacao' then 'aplicacoes' else 'masterclass' end
  )
  on conflict (origem, source_id) do nothing
  returning id into v_id;

  -- Já tinha recebido esta resposta: não faz nada de novo
  if v_id is null then
    return null;
  end if;

  -- Aplicação: vira lead no CRM, negociação em "Novo" e tarefa para chamar
  if p_origem = 'aplicacao' then
    insert into public.crm_contacts (name, phone, origin, status, notes)
    values (
      v_nome,
      left(p_dados->>'whatsapp', 30),
      'aplicação mentoria',
      'lead',
      left(concat_ws(E'\n',
        'Aplicação para a Mentoria Mãos na IA (' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') || ')',
        'Instagram ou site: '  || nullif(btrim(p_dados->>'instagram'), ''),
        'Negócio: '            || (p_dados->>'negocio'),
        'Equipe: '             || (p_dados->>'equipe'),
        'Faturamento: '        || (p_dados->>'faturamento'),
        'Uso de IA: '          || (p_dados->>'uso_ia'),
        'Tarefa que quer largar: ' || (p_dados->>'tarefa_nunca_mais'),
        'Para valer a pena: '  || (p_dados->>'valeu_a_pena'),
        'Quando quer começar: '|| (p_dados->>'quando_comecar')
      ), 4000)
    )
    returning id into v_contato;

    insert into public.crm_deals (contact_id, title, stage, value, notes)
    values (v_contato, 'Mentoria Mãos na IA · ' || v_nome, 'novo', 3000, 'Veio pela página da bio (aplicação).')
    returning id into v_deal;

    insert into public.tasks (title, description, priority, status, start_date, due_date, deal_id)
    values (
      'Chamar no WhatsApp: ' || v_nome || ' (aplicação da mentoria)',
      'WhatsApp: ' || coalesce(p_dados->>'whatsapp', '—') || E'\nVer a aplicação em ' || v_base || 'aplicacoes',
      'alta', 'pendente', v_hoje, v_hoje, v_deal
    );

    update public.novidades set contact_id = v_contato, deal_id = v_deal where id = v_id;
  end if;

  return v_id;
end $$;

revoke all on function public.novidades_ingest(text, text, uuid, jsonb) from public;
grant execute on function public.novidades_ingest(text, text, uuid, jsonb) to anon, authenticated;


-- ──────────── 4. MOSTRAR O TOKEN ────────────
-- Copie o valor e cole no arquivo supabase-integracao-sistema.sql (banco dos formulários).
select token as token_novidades from public.novidades_secrets where id = 1;


-- ──────────── TROCAR O TOKEN (só se precisar) ────────────
-- update public.novidades_secrets set token = replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') where id = 1;
-- (depois atualize o token no banco dos formulários também)
