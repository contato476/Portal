-- ════════════════════════════════════════════════════════════════════
-- 44 · VENDA DO CLUBE ENTRA NO CRM E NA JORNADA
-- Rode este arquivo no SQL Editor do Supabase DO SISTEMA (jvtjhfganuuefswbnbrk),
-- DEPOIS do 43. Pode rodar mais de uma vez sem estragar nada.
--
-- Antes: a venda do Asaas virava só venda, aviso em Novidades e tarefa.
-- Agora ela também vira:
--   · contato no CRM (usa o que já existe com o mesmo e-mail ou telefone;
--     se não existe, cria) marcado como cliente ativa;
--   · negócio "Clube Mãos na IA · Nome" já em Ganho, no pipeline Produtos
--     de IA, com o valor pago;
--   · a jornada pós-venda: cópia dos passos do Clube que estão em
--     Configurações, com os prazos contados a partir do dia de liberar o
--     acesso (01/12 na Black), e não do dia do pagamento.
-- A tarefa "Liberar acesso ao Clube" e o aviso ficam ligados ao negócio.
-- No fim, as vendas que já chegaram (o teste de R$ 5) entram na jornada.
--
-- Com o negócio em Ganho, o botão "Ações do ganho" do CRM serve para
-- cadastrar a assinante no portal e lançar no financeiro.
-- ════════════════════════════════════════════════════════════════════


-- ──────────── 1. A VENDA GUARDA O CONTATO E O NEGÓCIO ────────────
alter table public.clube_vendas
  add column if not exists contact_id uuid references public.crm_contacts(id) on delete set null,
  add column if not exists deal_id    uuid references public.crm_deals(id)    on delete set null;


-- ──────────── 2. LEVAR UMA VENDA PARA O CRM ────────────
-- Função interna: só o banco chama (a clube_venda_ingest e o passo 4).
-- Se a venda já tem negócio, não faz nada: nunca duplica.
create or replace function public.clube_venda_para_crm(p_venda_id uuid)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v         public.clube_vendas%rowtype;
  v_prod    public.crm_produtos%rowtype;
  v_contato uuid;
  v_deal    uuid;
  v_fone    text;
  v_base    date;
  v_prefixo text;
  v_nota    text;
begin
  -- "for update" trava a linha: dois pedidos ao mesmo tempo não criam dois negócios
  select * into v from public.clube_vendas where id = p_venda_id for update;
  if v.id is null then return null; end if;
  if v.deal_id is not null then return v.deal_id; end if;

  -- O produto Clube das Configurações. Sem ele, não há jornada para copiar.
  select * into v_prod from public.crm_produtos where codigo = 'clube';
  if v_prod.id is null then return null; end if;

  v_prefixo := case when v.teste then 'TESTE · ' else '' end;
  v_nota := 'Comprou o Clube Mãos na IA pelo Asaas em ' || to_char(v.pago_em, 'DD/MM/YYYY') || '.';

  -- Telefone só com números e sem o 55 da frente, para comparar
  v_fone := regexp_replace(regexp_replace(coalesce(v.telefone, ''), '\D', '', 'g'), '^55(?=\d{10,11}$)', '');

  -- 1) Contato: o mais antigo com o mesmo e-mail ou o mesmo telefone
  select c.id into v_contato
    from public.crm_contacts c
   where (v.email is not null and lower(btrim(c.email)) = v.email)
      or (v_fone <> '' and
          regexp_replace(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g'), '^55(?=\d{10,11}$)', '') = v_fone)
   order by c.created_at
   limit 1;

  if v_contato is null then
    insert into public.crm_contacts (name, email, phone, origin, status, notes)
    values (v.nome, v.email, v.telefone, 'clube (asaas)', 'ativo', v_nota)
    returning id into v_contato;
  else
    -- Já era contato (ex.: veio do desafio): vira cliente ativa e ganha a anotação
    update public.crm_contacts
       set status = 'ativo',
           email  = coalesce(nullif(btrim(email), ''), v.email),
           phone  = coalesce(nullif(btrim(phone), ''), v.telefone),
           notes  = left(concat_ws(E'\n\n', nullif(notes, ''), v_nota), 8000)
     where id = v_contato;
  end if;

  -- 2) Negócio já em Ganho ('fechado' é o Ganho do pipeline de IA)
  insert into public.crm_deals (contact_id, title, value, stage, closed_at, notes, pipeline, produto_id)
  values (
    v_contato,
    v_prefixo || v_prod.nome || ' · ' || v.nome,
    v.valor, 'fechado', v.created_at,
    'Venda automática pelo Asaas (' ||
      case v.forma when 'pix' then 'Pix à vista'
                   when 'cartao' then 'cartão' || case when coalesce(v.parcelas, 1) > 1 then ' em ' || v.parcelas || 'x' else ' à vista' end
                   when 'boleto' then 'boleto' else 'outra forma' end || ').',
    'ia', v_prod.id
  )
  returning id into v_deal;

  -- 3) Jornada: cópia dos passos ativos do Clube. Os prazos contam do dia de
  --    liberar o acesso; se a compra for depois dele, contam do dia da compra.
  select greatest(coalesce(l.liberar_em, v.pago_em), v.pago_em) into v_base
    from (select 1) x left join public.clube_links_asaas l on l.link_id = v.link_id;
  v_base := coalesce(v_base, v.pago_em, (now() at time zone 'America/Sao_Paulo')::date);

  insert into public.crm_jornada_itens (deal_id, passo_id, titulo, descricao, ordem, prazo)
  select v_deal, p.id, p.titulo, p.descricao,
         (row_number() over (order by p.ordem, p.created_at))::int - 1,
         v_base + coalesce(p.dias, 0)
    from public.crm_jornada_passos p
   where p.produto_id = v_prod.id and p.arquivado_em is null;

  -- 4) Liga a tarefa, o aviso e a venda ao negócio
  update public.tasks     set deal_id = v_deal where id = v.task_id;
  update public.novidades set contact_id = v_contato, deal_id = v_deal where id = v.novidade_id;
  update public.clube_vendas
     set contact_id = v_contato, deal_id = v_deal, updated_at = now()
   where id = v.id;

  return v_deal;
end $$;

-- Ninguém chama de fora: nem o site, nem usuária logada
revoke all on function public.clube_venda_para_crm(uuid) from public, anon, authenticated;


-- ──────────── 3. A FUNÇÃO QUE RECEBE O AVISO PASSA A CHAMAR O CRM ────────────
-- Igual à do sql/43, com uma linha a mais (marcada com NOVO).
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

          -- NOVO (sql/44): a venda vira contato, negócio ganho e jornada no CRM
          perform public.clube_venda_para_crm(v_venda_id);
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


-- ──────────── 4. VENDAS QUE JÁ CHEGARAM ────────────
-- Leva para o CRM as vendas pagas que ainda não têm negócio (o teste de R$ 5).
select v.nome, public.clube_venda_para_crm(v.id) as negocio_criado
  from public.clube_vendas v
 where v.deal_id is null and v.status = 'pago' and v.arquivado_em is null;
