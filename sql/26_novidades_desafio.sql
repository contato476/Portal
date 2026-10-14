-- ════════════════════════════════════════════════════════════════════
-- 26 · DESAFIO 21 DIAS NAS NOVIDADES (e no CRM, para quem quer a conversa)
-- Rode no SQL Editor do Supabase DO SISTEMA (jvtjhfganuuefswbnbrk),
-- ANTES do supabase-desafio-sistema.sql do banco dos formulários.
--
-- 1ª chegada (nome e WhatsApp): cria a novidade "Desafio 21 dias".
-- 2ª chegada (respostas completas): atualiza a novidade. Se a pessoa marcou
--    "Sim, quero a conversa" (diagnóstico de 20 minutos), cria o lead no CRM,
--    a negociação em "Novo" e a tarefa "Marcar a conversa de diagnóstico".
--    Se o WhatsApp já existe no CRM, usa o mesmo contato (não duplica).
-- Aplicação, teste da bio e Masterclass continuam iguais ao 24.
-- ════════════════════════════════════════════════════════════════════

-- 1) A tabela passa a aceitar a origem "desafio"
alter table public.novidades drop constraint if exists novidades_origem_check;
alter table public.novidades add constraint novidades_origem_check
  check (origem in ('aplicacao','masterclass','teste','desafio'));

-- 2) A função que recebe as respostas
create or replace function public.novidades_ingest(
  p_token text, p_origem text, p_source_id uuid, p_dados jsonb
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_id      uuid;
  v_novo    boolean;
  v_contato uuid;
  v_deal    uuid;
  v_nome    text := left(coalesce(nullif(btrim(p_dados->>'nome'), ''), 'Sem nome'), 120);
  v_hoje    date := (now() at time zone 'America/Sao_Paulo')::date;
  v_quando  text := to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI');
  v_base    text := 'https://maosnaia.jpgestaodescomplicada.com/painel/';
  v_resumo  text;
  v_notas   text;
  v_fone    text;
begin
  if p_token is null or p_token <> (select token from public.novidades_secrets where id = 1) then
    raise exception 'token inválido';
  end if;
  if p_origem not in ('aplicacao','masterclass','teste','desafio') then
    raise exception 'origem inválida';
  end if;
  if jsonb_typeof(p_dados) <> 'object' then
    raise exception 'p_dados precisa ser um objeto';
  end if;

  -- ── DESAFIO 21 DIAS (contato primeiro, respostas depois) ──
  if p_origem = 'desafio' then
    v_resumo := case when nullif(p_dados->>'diagnostico', '') is null
                  then 'Entrou no desafio (deixou nome e WhatsApp, ainda não respondeu as perguntas)'
                  else left(concat_ws(' · ',
                         'O que mais falta: ' || (p_dados->>'prioridade'),
                         p_dados->>'faturamento',
                         case when p_dados->>'diagnostico' = 'Sim, quero a conversa'
                              then 'QUER A CONVERSA DE DIAGNÓSTICO' end), 500) end;
    v_notas := left(concat_ws(E'\n',
      'Desafio 21 dias: do manual ao automático (' || v_quando || ')',
      'Instagram: '                  || nullif(btrim(p_dados->>'instagram'), ''),
      'Negócio: '                    || nullif(p_dados->>'negocio', ''),
      'Equipe: '                     || nullif(p_dados->>'equipe', ''),
      'Faturamento: '                || nullif(p_dados->>'faturamento', ''),
      'Uso de IA: '                  || nullif(p_dados->>'uso_ia', ''),
      'O que mais falta: '           || nullif(p_dados->>'prioridade', ''),
      'Tarefa que mais toma tempo: ' || nullif(p_dados->>'tarefa_mais_tempo', ''),
      'Para valer a pena: '          || nullif(p_dados->>'valeu_a_pena', ''),
      'Dúvida sobre o Claude: '      || nullif(p_dados->>'duvida_claude', ''),
      'Conversa de diagnóstico: '    || nullif(p_dados->>'diagnostico', '')
    ), 4000);

    insert into public.novidades (origem, source_id, titulo, resumo, dados, link)
    values ('desafio', p_source_id, 'Desafio 21 dias · ' || v_nome, v_resumo, p_dados, v_base || 'desafio')
    on conflict (origem, source_id) do update
      set resumo = excluded.resumo, dados = excluded.dados
    returning id, contact_id into v_id, v_contato;

    -- Só quem quer a conversa vira lead, e uma vez só
    if p_dados->>'diagnostico' = 'Sim, quero a conversa' and v_contato is null then
      v_fone := regexp_replace(coalesce(p_dados->>'whatsapp', ''), '\D', '', 'g');

      select id into v_contato from public.crm_contacts
       where v_fone <> '' and regexp_replace(coalesce(phone, ''), '\D', '', 'g') in (v_fone, '55' || v_fone)
       order by created_at limit 1;

      if v_contato is null then
        insert into public.crm_contacts (name, phone, origin, status, notes)
        values (v_nome, left(p_dados->>'whatsapp', 30), 'desafio 21 dias', 'lead', v_notas)
        returning id into v_contato;
      else
        update public.crm_contacts
           set notes = left(concat_ws(E'\n\n', notes, v_notas), 8000)
         where id = v_contato;
      end if;

      insert into public.crm_deals (contact_id, title, stage, value, notes)
      values (v_contato, 'Mentoria Mãos na IA · ' || v_nome, 'novo', 3000,
              'Veio do Desafio 21 dias: pediu a conversa de diagnóstico de 20 minutos.')
      returning id into v_deal;

      insert into public.tasks (title, description, priority, status, start_date, due_date, deal_id)
      values (
        'Marcar a conversa de diagnóstico: ' || v_nome || ' (desafio 21 dias)',
        'WhatsApp: ' || coalesce(p_dados->>'whatsapp', '—') || E'\nAs respostas dela estão nas anotações do lead e em ' || v_base || 'desafio',
        'alta', 'pendente', v_hoje, v_hoje, v_deal
      );

      update public.novidades set contact_id = v_contato, deal_id = v_deal where id = v_id;
    end if;

    return v_id;
  end if;

  -- ── TESTE DA BIO ──
  if p_origem = 'teste' then
    v_resumo := case when nullif(p_dados->>'recomendacao', '') is null
                  then 'Deixou o contato e começou o teste (ainda sem resultado)'
                  else concat_ws(' · ', 'Indicação do teste: ' || (p_dados->>'recomendacao'), p_dados->>'negocio') end;
    v_notas := left(concat_ws(E'\n',
      'Fez o teste "Descubra o seu caminho" na página da bio (' || v_quando || ')',
      'Indicação do teste: '   || nullif(p_dados->>'recomendacao', ''),
      'IA na rotina: '         || nullif(p_dados->>'uso', ''),
      'Negócio: '              || nullif(p_dados->>'negocio', ''),
      'Como prefere avançar: ' || nullif(p_dados->>'jeito', ''),
      'Tempo por semana: '     || nullif(p_dados->>'tempo', '')
    ), 4000);

    insert into public.novidades (origem, source_id, titulo, resumo, dados, link)
    values ('teste', p_source_id, 'Teste da página da bio · ' || v_nome, v_resumo, p_dados, null)
    on conflict (origem, source_id) do update
      set resumo = excluded.resumo, dados = excluded.dados
    returning id, (xmax = 0) into v_id, v_novo;

    if v_novo then
      insert into public.crm_contacts (name, phone, origin, status, notes)
      values (v_nome, left(p_dados->>'whatsapp', 30), 'teste da bio', 'lead', v_notas)
      returning id into v_contato;

      insert into public.tasks (title, description, priority, status, start_date, due_date)
      values (
        'Chamar no WhatsApp: ' || v_nome || ' (teste da bio)',
        'WhatsApp: ' || coalesce(p_dados->>'whatsapp', '—') || E'\nO caminho indicado pelo teste fica nas anotações do lead no CRM.',
        'media', 'pendente', v_hoje, v_hoje
      );

      update public.novidades set contact_id = v_contato where id = v_id;
    else
      update public.crm_contacts c
         set notes = v_notas
        from public.novidades n
       where n.id = v_id and c.id = n.contact_id;
    end if;

    return v_id;
  end if;

  -- ── APLICAÇÃO (duas etapas: contato primeiro, respostas depois) ──
  if p_origem = 'aplicacao' then
    v_resumo := case when nullif(p_dados->>'quando_comecar', '') is null
                  then 'Começou a aplicação (deixou nome e WhatsApp, ainda não terminou)'
                  else left(concat_ws(' · ', p_dados->>'faturamento', p_dados->>'equipe', 'Quer começar: ' || (p_dados->>'quando_comecar')), 500) end;
    v_notas := left(concat_ws(E'\n',
      'Aplicação para a Mentoria Mãos na IA (' || v_quando || ')',
      'Instagram ou site: '      || nullif(btrim(p_dados->>'instagram'), ''),
      'Negócio: '                || nullif(p_dados->>'negocio', ''),
      'Equipe: '                 || nullif(p_dados->>'equipe', ''),
      'Faturamento: '            || nullif(p_dados->>'faturamento', ''),
      'Uso de IA: '              || nullif(p_dados->>'uso_ia', ''),
      'Tarefa que quer largar: ' || nullif(p_dados->>'tarefa_nunca_mais', ''),
      'Para valer a pena: '      || nullif(p_dados->>'valeu_a_pena', ''),
      'Quando quer começar: '    || nullif(p_dados->>'quando_comecar', '')
    ), 4000);

    insert into public.novidades (origem, source_id, titulo, resumo, dados, link)
    values ('aplicacao', p_source_id, 'Aplicação para a mentoria · ' || v_nome, v_resumo, p_dados, v_base || 'aplicacoes')
    on conflict (origem, source_id) do update
      set resumo = excluded.resumo, dados = excluded.dados
    returning id, (xmax = 0) into v_id, v_novo;

    if v_novo then
      insert into public.crm_contacts (name, phone, origin, status, notes)
      values (v_nome, left(p_dados->>'whatsapp', 30), 'aplicação mentoria', 'lead', v_notas)
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
    else
      update public.crm_contacts c
         set notes = v_notas
        from public.novidades n
       where n.id = v_id and c.id = n.contact_id;
    end if;

    return v_id;
  end if;

  -- ── MASTERCLASS ──
  insert into public.novidades (origem, source_id, titulo, resumo, dados, link)
  values (
    'masterclass', p_source_id, 'Formulário da Masterclass · ' || v_nome,
    left('Onde travou: ' || coalesce(p_dados->>'onde_travou', '—'), 500),
    p_dados, v_base || 'masterclass'
  )
  on conflict (origem, source_id) do nothing
  returning id into v_id;
  return v_id;
end $$;

revoke all on function public.novidades_ingest(text, text, uuid, jsonb) from public;
grant execute on function public.novidades_ingest(text, text, uuid, jsonb) to anon, authenticated;
