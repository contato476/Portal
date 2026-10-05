-- ════════════════════════════════════════════════════════════════════
-- 22 · NOVIDADES: TESTE "DESCUBRA O SEU CAMINHO" DA PÁGINA DA BIO
-- Rode no SQL Editor do Supabase DO SISTEMA (jvtjhfganuuefswbnbrk),
-- ANTES do supabase-setup-teste.sql do banco dos formulários.
--
-- Quem faz o teste deixa nome e WhatsApp. Aqui isso vira:
--   · uma novidade (origem "teste"), com o caminho que o teste indicou;
--   · um lead no CRM (origem "teste da bio");
--   · uma tarefa "Chamar no WhatsApp" (prioridade média).
-- Não cria negociação: a pessoa ainda não pediu proposta.
-- ════════════════════════════════════════════════════════════════════

-- 1) A tabela passa a aceitar a origem "teste"
alter table public.novidades drop constraint if exists novidades_origem_check;
alter table public.novidades add constraint novidades_origem_check
  check (origem in ('aplicacao','masterclass','teste'));

-- 2) A função de entrada passa a tratar o teste
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
  v_quando  text := to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI');
  v_base    text := 'https://maosnaia.jpgestaodescomplicada.com/painel/';
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

  insert into public.novidades (origem, source_id, titulo, resumo, dados, link)
  values (
    p_origem,
    p_source_id,
    case p_origem
      when 'aplicacao' then 'Aplicação para a mentoria · ' || v_nome
      when 'teste'     then 'Teste da página da bio · ' || v_nome
      else 'Formulário da Masterclass · ' || v_nome end,
    left(case p_origem
      when 'aplicacao' then concat_ws(' · ', p_dados->>'faturamento', p_dados->>'equipe', 'Quer começar: ' || (p_dados->>'quando_comecar'))
      when 'teste'     then concat_ws(' · ', 'Indicação do teste: ' || (p_dados->>'recomendacao'), p_dados->>'negocio')
      else 'Onde travou: ' || coalesce(p_dados->>'onde_travou', '—') end, 500),
    p_dados,
    case p_origem
      when 'aplicacao'   then v_base || 'aplicacoes'
      when 'masterclass' then v_base || 'masterclass'
      else null end
  )
  on conflict (origem, source_id) do nothing
  returning id into v_id;

  if v_id is null then
    return null;   -- já tinha recebido esta resposta
  end if;

  -- Aplicação: lead, negociação em "Novo" e tarefa (prioridade alta)
  if p_origem = 'aplicacao' then
    insert into public.crm_contacts (name, phone, origin, status, notes)
    values (
      v_nome, left(p_dados->>'whatsapp', 30), 'aplicação mentoria', 'lead',
      left(concat_ws(E'\n',
        'Aplicação para a Mentoria Mãos na IA (' || v_quando || ')',
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

  -- Teste da bio: lead e tarefa (prioridade média), sem negociação
  if p_origem = 'teste' then
    insert into public.crm_contacts (name, phone, origin, status, notes)
    values (
      v_nome, left(p_dados->>'whatsapp', 30), 'teste da bio', 'lead',
      left(concat_ws(E'\n',
        'Fez o teste "Descubra o seu caminho" na página da bio (' || v_quando || ')',
        'Indicação do teste: ' || (p_dados->>'recomendacao'),
        'IA na rotina: '       || (p_dados->>'uso'),
        'Negócio: '            || (p_dados->>'negocio'),
        'Como prefere avançar: ' || (p_dados->>'jeito'),
        'Tempo por semana: '   || (p_dados->>'tempo')
      ), 4000)
    )
    returning id into v_contato;

    insert into public.tasks (title, description, priority, status, start_date, due_date)
    values (
      'Chamar no WhatsApp: ' || v_nome || ' (teste da bio · ' || coalesce(p_dados->>'recomendacao', 'sem indicação') || ')',
      'WhatsApp: ' || coalesce(p_dados->>'whatsapp', '—') || E'\nO teste indicou: ' || coalesce(p_dados->>'recomendacao', '—'),
      'media', 'pendente', v_hoje, v_hoje
    );

    update public.novidades set contact_id = v_contato where id = v_id;
  end if;

  return v_id;
end $$;

revoke all on function public.novidades_ingest(text, text, uuid, jsonb) from public;
grant execute on function public.novidades_ingest(text, text, uuid, jsonb) to anon, authenticated;
