-- 37 · Tarefas: novo status "Aguardando cliente", coluna entre Fazendo e Concluído (27/10/2026)
-- O banco só aceita os status listados na regra (check) da coluna status.
-- Este script troca a regra antiga por uma que inclui 'aguardando_cliente'. Rodar uma vez no SQL Editor.
do $$
declare v_nome text;
begin
  -- Acha o nome da regra atual (o Postgres gera o nome sozinho, ex.: tasks_status_check)
  select con.conname into v_nome
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public' and rel.relname = 'tasks'
    and con.contype = 'c' and pg_get_constraintdef(con.oid) ilike '%status%';

  if v_nome is not null then
    execute format('alter table public.tasks drop constraint %I', v_nome);
  end if;
end $$;

alter table public.tasks add constraint tasks_status_check
  check (status in ('pendente','em_andamento','aguardando_cliente','concluida','cancelada'));
