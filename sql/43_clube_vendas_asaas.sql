-- ════════════════════════════════════════════════════════════════════
-- 43 · VENDAS DO CLUBE VINDAS DO ASAAS (webhook → sistema)
-- Rode este arquivo no SQL Editor do Supabase DO SISTEMA (jvtjhfganuuefswbnbrk).
-- Pode rodar mais de uma vez sem estragar nada.
--
-- O caminho completo:
--   Asaas avisa que um pagamento foi confirmado
--     → api/asaas-webhook.js (Vercel) confere o token e o formato do aviso
--     → chama a função clube_venda_ingest, aqui embaixo
--     → ela grava a venda, cria o aviso na tela Novidades e a tarefa
--       "Liberar acesso ao Clube".
--
-- O que este arquivo cria:
--   · clube_links_asaas  os links de pagamento aceitos (só vendas desses
--                        links viram venda do Clube; o resto é ignorado)
--   · clube_vendas       uma linha por compra
--   · asaas_eventos      diário dos avisos recebidos (sem dados pessoais),
--                        para não processar o mesmo aviso duas vezes
--   · clube_secrets      o token que só o servidor da Vercel conhece
--   · clube_venda_ingest a função que faz tudo, numa transação só
-- No fim, mostra o TOKEN: copie e cole na Vercel (CLUBE_INGEST_TOKEN).
-- ════════════════════════════════════════════════════════════════════


-- ──────────── 1. LINKS DE PAGAMENTO ACEITOS ────────────
-- O Asaas manda avisos de TODAS as cobranças da conta. Esta lista diz
-- quais links são do Clube. O script scripts/asaas-links.mjs mostra o
-- código de cada link e já escreve o INSERT pronto.
create table if not exists public.clube_links_asaas (
  link_id     text primary key,              -- código do link no Asaas (campo paymentLink)
  nome        text not null,                 -- ex.: "Clube Black · Pix à vista"
  teste       boolean not null default false,-- link de R$ 5 para testar: o aviso sai com "TESTE"
  liberar_em  date,                          -- dia de liberar o acesso (vazio = no dia da compra)
  ativo       boolean not null default true, -- desligar em vez de apagar
  created_at  timestamptz not null default now()
);

alter table public.clube_links_asaas enable row level security;
drop policy if exists "admin_all" on public.clube_links_asaas;
create policy "admin_all" on public.clube_links_asaas
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());


-- ──────────── 2. VENDAS ────────────
-- "chave" é o que garante uma linha por compra: no cartão parcelado é o
-- código do parcelamento (as 12 parcelas são UMA compra); no Pix é o
-- código do pagamento.
-- LGPD: só o necessário para liberar o acesso e falar com a assinante.
-- Não guardamos CPF, endereço nem dado de cartão.
create table if not exists public.clube_vendas (
  id                     uuid primary key default gen_random_uuid(),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  chave                  text not null unique,
  asaas_pagamento_id     text not null,
  asaas_parcelamento_id  text,
  asaas_cliente_id       text,
  link_id                text references public.clube_links_asaas(link_id),
  teste                  boolean not null default false,
  nome                   text not null,
  email                  text,
  telefone               text,
  valor                  numeric(12,2) not null,   -- total da compra
  valor_liquido          numeric(12,2),            -- depois das taxas do Asaas
  forma                  text not null check (forma in ('pix','cartao','boleto','outro')),
  parcelas               int,
  pago_em                date,
  status                 text not null default 'pago' check (status in ('pago','estornado','contestado')),
  status_em              timestamptz,              -- quando virou estornado ou contestado
  novidade_id            uuid references public.novidades(id) on delete set null,
  task_id                uuid references public.tasks(id) on delete set null,
  arquivado_em           timestamptz
);
create index if not exists idx_clube_vendas_pago on public.clube_vendas(pago_em desc);

alter table public.clube_vendas enable row level security;
drop policy if exists "admin_all" on public.clube_vendas;
create policy "admin_all" on public.clube_vendas
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());


-- ──────────── 3. DIÁRIO DOS AVISOS ────────────
-- Um aviso do Asaas pode chegar repetido. Guardamos o código de cada um
-- (evt_...) e o que foi feito com ele. Sem nome, e-mail ou telefone.
-- Também serve para descobrir o código de um link: avisos de links
-- fora da lista aparecem aqui como "ignorado: link fora da lista".
create table if not exists public.asaas_eventos (
  evento_id     text primary key,
  recebido_em   timestamptz not null default now(),
  evento        text not null,
  pagamento_id  text,
  link_id       text,
  resultado     text not null
);

alter table public.asaas_eventos enable row level security;
drop policy if exists "admin_le" on public.asaas_eventos;
create policy "admin_le" on public.asaas_eventos
  for select to authenticated
  using (public.is_admin());


-- ──────────── 4. O TOKEN ────────────
-- RLS ligado e NENHUMA política: pelo navegador ninguém lê.
create table if not exists public.clube_secrets (
  id         int primary key default 1 check (id = 1),
  token      text not null,
  created_at timestamptz not null default now()
);
alter table public.clube_secrets enable row level security;

insert into public.clube_secrets(id, token)
values (1, replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (id) do nothing;


-- ──────────── 5. A TELA NOVIDADES ACEITA A ORIGEM "clube" ────────────
alter table public.novidades drop constraint if exists novidades_origem_check;
alter table public.novidades add constraint novidades_origem_check
  check (origem in ('aplicacao','masterclass','teste','desafio','clube'));


-- ──────────── 6. RECEBER UM AVISO DO ASAAS ────────────
-- Chamada só pelo servidor (api/asaas-webhook.js), com o token.
-- p_dados (montado pelo servidor, já validado):
--   evento_id, evento, pagamento_id, parcelamento_id, cliente_id, link_id,
--   forma, valor, valor_liquido, pago_em
--   e, na segunda chamada: nome, email, telefone, parcelas
--
-- Respostas (campo "status"):
--   repetido        este aviso já tinha sido processado
--   ignorado        não é venda do Clube (link fora da lista ou evento sem uso)
--   falta_cliente   é venda nova do Clube: o servidor busca nome, e-mail e
--                   telefone no Asaas e chama de novo com esses dados
--   venda_criada    venda, aviso e tarefa criados
--   ja_registrada   a compra já existia (ex.: 2ª parcela, ou o "recebido"
--                   do cartão 32 dias depois): nada é duplicado
--   estorno         a venda foi marcada como estornada ou contestada
create or replace function public.clube_venda_ingest(p_token text, p_dados jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_evento_id text := nullif(p_dados->>'evento_id', '');
  v_evento    text := coalesce(p_dados->>'evento', '');
  v_pag       text := nullif(p_dados->>'pagamento_id', '');
  v_parc      text := nullif(p_dados->>'parcelamento_id', '');
  v_link_id   text := nullif(p_dados->>'link_id', '');
  v_chave     text;
  v_link      public.clube_links_asaas%rowtype;
  v_venda     public.clube_vendas%rowtype;
  v_venda_id  uuid;
  v_nov       uuid;
  v_task      uuid;
  v_nome      text := left(coalesce(nullif(btrim(p_dados->>'nome'), ''), 'Sem nome'), 120);
  v_email     text := left(nullif(lower(btrim(p_dados->>'email')), ''), 200);
  v_fone      text := left(nullif(btrim(p_dados->>'telefone'), ''), 30);
  v_forma     text := case when p_dados->>'forma' in ('pix','cartao','boleto') then p_dados->>'forma' else 'outro' end;
  v_valor     numeric(12,2);
  v_liquido   numeric(12,2);
  v_parcelas  int;
  v_pago      date;
  v_hoje      date := (now() at time zone 'America/Sao_Paulo')::date;
  v_liberar   date;
  v_valor_txt text;
  v_forma_txt text;
  v_prefixo   text;
  v_novo_st   text;
  v_resultado text;
begin
  -- 1) Só o servidor, com o token certo, pode chamar
  if p_token is null or p_token <> (select token from public.clube_secrets where id = 1) then
    raise exception 'token inválido';
  end if;
  if jsonb_typeof(p_dados) <> 'object' or v_evento_id is null or v_pag is null then
    raise exception 'dados incompletos';
  end if;

  -- 2) Aviso repetido: não faz nada
  if exists (select 1 from public.asaas_eventos where evento_id = v_evento_id) then
    return jsonb_build_object('status', 'repetido');
  end if;

  -- Uma compra = um parcelamento (cartão em várias vezes) ou um pagamento (Pix)
  v_chave := coalesce(v_parc, v_pag);
  select * into v_venda from public.clube_vendas where chave = v_chave;

  -- ── PAGAMENTO CONFIRMADO OU RECEBIDO ──
  if v_evento in ('PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED') then

    if v_venda.id is not null then
      v_resultado := 'ja_registrada';

    else
      select * into v_link from public.clube_links_asaas where link_id = v_link_id and ativo;

      if v_link.link_id is null then
        v_resultado := 'ignorado: link fora da lista';

      elsif not (p_dados ? 'nome') then
        -- Venda nova do Clube, mas ainda sem os dados da pessoa.
        -- Não registra o aviso: o servidor vai chamar de novo com os dados.
        return jsonb_build_object('status', 'falta_cliente');

      else
        v_valor    := (p_dados->>'valor')::numeric;
        v_liquido  := nullif(p_dados->>'valor_liquido', '')::numeric;
        v_parcelas := nullif(p_dados->>'parcelas', '')::int;
        v_pago     := coalesce(nullif(p_dados->>'pago_em', '')::date, v_hoje);

        insert into public.clube_vendas (
          chave, asaas_pagamento_id, asaas_parcelamento_id, asaas_cliente_id, link_id, teste,
          nome, email, telefone, valor, valor_liquido, forma, parcelas, pago_em
        ) values (
          v_chave, v_pag, v_parc, nullif(p_dados->>'cliente_id', ''), v_link.link_id, v_link.teste,
          v_nome, v_email, v_fone, v_valor, v_liquido, v_forma, v_parcelas, v_pago
        )
        on conflict (chave) do nothing
        returning id into v_venda_id;

        if v_venda_id is null then
          -- Dois avisos da mesma compra chegaram ao mesmo tempo: o outro já gravou
          v_resultado := 'ja_registrada';
        else
          -- Textos no padrão brasileiro
          v_valor_txt := 'R$ ' || translate(to_char(v_valor, 'FM999,999,990.00'), ',.', '.,');
          v_forma_txt := case v_forma
            when 'pix'    then 'Pix à vista'
            when 'cartao' then 'Cartão' || case when coalesce(v_parcelas, 1) > 1 then ' em ' || v_parcelas || 'x' else ' à vista' end
            when 'boleto' then 'Boleto'
            else 'Outra forma' end;
          v_prefixo := case when v_link.teste then 'TESTE · ' else '' end;
          -- Libera no dia combinado; se a compra for depois dele, libera hoje
          v_liberar := greatest(coalesce(v_link.liberar_em, v_hoje), v_hoje);

          insert into public.novidades (origem, source_id, titulo, resumo, dados, link)
          values (
            'clube', v_venda_id,
            v_prefixo || 'Venda do Clube · ' || v_nome,
            concat_ws(' · ', v_forma_txt, v_valor_txt,
                      'pago em ' || to_char(v_pago, 'DD/MM/YYYY'),
                      'liberar o acesso em ' || to_char(v_liberar, 'DD/MM/YYYY')),
            jsonb_strip_nulls(jsonb_build_object(
              'email', v_email, 'telefone', v_fone,
              'valor', v_valor_txt, 'forma', v_forma_txt,
              'pago_em', to_char(v_pago, 'DD/MM/YYYY'),
              'liberar_em', to_char(v_liberar, 'DD/MM/YYYY'),
              'produto', v_link.nome)),
            null
          )
          returning id into v_nov;

          insert into public.tasks (title, description, priority, status, start_date, due_date)
          values (
            v_prefixo || 'Liberar acesso ao Clube: ' || v_nome,
            concat_ws(E'\n',
              'E-mail (login do portal): ' || coalesce(v_email, 'não veio do Asaas'),
              'Telefone: ' || coalesce(v_fone, 'não veio do Asaas'),
              'Compra: ' || v_forma_txt || ', ' || v_valor_txt || ', paga em ' || to_char(v_pago, 'DD/MM/YYYY'),
              'Cadastrar em mentoria.jpgestaodescomplicada.com (plano Clube anual) e colocar no grupo.'),
            'alta', 'pendente', v_liberar, v_liberar
          )
          returning id into v_task;

          update public.clube_vendas set novidade_id = v_nov, task_id = v_task where id = v_venda_id;
          v_resultado := 'venda_criada';
        end if;
      end if;
    end if;

  -- ── ESTORNO OU CONTESTAÇÃO NO CARTÃO ──
  elsif v_evento in ('PAYMENT_REFUNDED', 'PAYMENT_CHARGEBACK_REQUESTED') then
    v_novo_st := case v_evento when 'PAYMENT_REFUNDED' then 'estornado' else 'contestado' end;

    -- Só age se a venda existe e o status muda (no parcelado chega um aviso
    -- por parcela: o aviso e a tarefa nascem só no primeiro)
    if v_venda.id is not null and v_venda.status <> v_novo_st and v_venda.status <> 'estornado' then
      update public.clube_vendas
         set status = v_novo_st, status_em = now(), updated_at = now()
       where id = v_venda.id;

      v_prefixo := case when v_venda.teste then 'TESTE · ' else '' end;

      insert into public.novidades (origem, source_id, titulo, resumo, dados, link)
      values (
        'clube', gen_random_uuid(),
        v_prefixo || case v_novo_st when 'estornado' then 'Estorno no Clube · ' else 'Compra contestada no Clube · ' end || v_venda.nome,
        case v_novo_st
          when 'estornado' then 'O pagamento foi devolvido. Confira se o acesso precisa ser retirado.'
          else 'A compra foi contestada no cartão. Veja o prazo de resposta no painel do Asaas.' end,
        jsonb_strip_nulls(jsonb_build_object('email', v_venda.email, 'telefone', v_venda.telefone)),
        null
      );

      insert into public.tasks (title, description, priority, status, start_date, due_date)
      values (
        v_prefixo || case v_novo_st when 'estornado' then 'Estorno no Clube: retirar o acesso de ' else 'Compra contestada no Clube: responder no Asaas, ' end || v_venda.nome,
        'E-mail: ' || coalesce(v_venda.email, 'sem e-mail') || E'\nSe a tarefa de liberar o acesso ainda estiver aberta, cancele.',
        'alta', 'pendente', v_hoje, v_hoje
      );

      v_resultado := 'estorno';
    else
      v_resultado := 'ignorado: sem venda para estornar';
    end if;

  else
    v_resultado := 'ignorado: evento sem uso';
  end if;

  -- 3) Anota o aviso no diário, para não processar de novo
  insert into public.asaas_eventos (evento_id, evento, pagamento_id, link_id, resultado)
  values (v_evento_id, left(v_evento, 60), v_pag, v_link_id, v_resultado)
  on conflict (evento_id) do nothing;

  return jsonb_build_object('status', split_part(v_resultado, ':', 1));
end $$;

revoke all on function public.clube_venda_ingest(text, jsonb) from public;
grant execute on function public.clube_venda_ingest(text, jsonb) to anon, authenticated;


-- ──────────── 7. MOSTRAR O TOKEN ────────────
-- Copie o valor e cole na Vercel, na variável CLUBE_INGEST_TOKEN.
-- Não cole em conversa, e-mail ou arquivo do projeto.
select token as clube_ingest_token from public.clube_secrets where id = 1;


-- ──────────── CADASTRAR OS LINKS (depois de rodar o script) ────────────
-- O scripts/asaas-links.mjs escreve estas linhas com os códigos certos:
-- insert into public.clube_links_asaas (link_id, nome, teste, liberar_em) values
--   ('CODIGO_DO_PIX',    'Clube Black · Pix à vista',       false, '2026-12-01'),
--   ('CODIGO_DO_CARTAO', 'Clube Black · Cartão parcelado',  false, '2026-12-01'),
--   ('CODIGO_DO_TESTE',  'Teste de R$ 5',                   true,  null)
-- on conflict (link_id) do nothing;

-- ──────────── TROCAR O TOKEN (só se precisar) ────────────
-- update public.clube_secrets set token = replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') where id = 1;
-- (depois atualize a variável CLUBE_INGEST_TOKEN na Vercel e publique de novo)
