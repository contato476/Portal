-- ════════════════════════════════════════════════════════════════════
-- 24 · APLICAÇÃO DA MENTORIA EM DUAS ETAPAS (contato primeiro)
-- Rode no SQL Editor do Supabase DO SISTEMA (jvtjhfganuuefswbnbrk),
-- ANTES do supabase-aplicacao-etapas.sql do banco dos formulários.
--
-- 1ª chegada (nome e WhatsApp): cria a novidade, o lead, a negociação e a tarefa.
-- 2ª chegada (aplicação completa): atualiza a novidade e as anotações do lead.
-- Teste da bio e Masterclass continuam como no 23.
-- ════════════════════════════════════════════════════════════════════
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
begin
  if p_token is null or p_token <> (select token from public.novidades_secrets where id = 1) then
    raise exception 'token inválido';
  end if;
  if p_origem not in ('aplicacao','masterclass','teste') then
    raise exception 'origem inválida';
  end if;
  if jsonb_typeof(p_dados) <> 'object' then
    raise exception 'p_dados precisa ser um objeto';
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
      -- chegaram as respostas: atualiza as anotações do lead
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
