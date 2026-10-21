-- 31 · CRM: nova etapa "Reunião agendada" no funil, entre Contato e Proposta (21/10/2026)
-- O banco só aceita as etapas listadas na regra (check) da coluna stage.
-- Este script troca a regra antiga por uma que inclui 'reuniao'. Rodar uma vez no SQL Editor.
do $$
declare v_nome text;
begin
  -- Acha o nome da regra atual (o Postgres gera o nome sozinho, ex.: crm_deals_stage_check)
  select con.conname into v_nome
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public' and rel.relname = 'crm_deals'
    and con.contype = 'c' and pg_get_constraintdef(con.oid) ilike '%stage%';

  if v_nome is not null then
    execute format('alter table public.crm_deals drop constraint %I', v_nome);
  end if;
end $$;

alter table public.crm_deals add constraint crm_deals_stage_check
  check (stage in ('novo','contato','reuniao','proposta','negociacao','fechado','perdido'));
