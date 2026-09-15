-- ════════════════════════════════════════════════════════════════════
-- 17_AJUSTES_VIRAM_TAREFAS.SQL
-- Cada pedido de ajuste ganha uma tarefa própria no kanban.
--
-- POR QUÊ ISTO EXISTE: o ajuste já era um trabalho de verdade — tinha
-- prazo na sua cabeça, consumia hora, atrasava junto com o resto. Mas
-- só existia na aba Ajustes e no relatório de Tempo. Para vê-lo no
-- quadro você tinha que lembrar dele e criar a tarefa à mão; quando
-- não lembrava, o ajuste ficava fora da única tela que responde
-- "o que eu faço agora?".
--
-- COMO FUNCIONA: registrar um ajuste cria a tarefa junto, e as duas
-- ficam espelhadas. Concluir o cartão no kanban fecha o ajuste;
-- fechar o ajuste risca o cartão. Não são dois trabalhos — é o mesmo
-- trabalho visto de dois lugares.
--
-- ⚠️ A FRONTEIRA CONTINUA DE PÉ: tasks é admin-only desde o sql/01
-- (policy admin_all, nenhuma policy de member). A tarefa criada aqui
-- NÃO aparece no portal do cliente.
--
-- COMO USAR: cole o arquivo inteiro no SQL Editor e clique em RUN.
-- É idempotente.
-- ════════════════════════════════════════════════════════════════════


-- ──────────── 1. O ELO ────────────
-- A coluna revision_requests.task_id já existe desde o sql/09. O que
-- faltava era alguém preenchê-la. O índice é para o caminho inverso:
-- "esta tarefa é o cartão de qual ajuste?".
create index if not exists idx_revisions_task
  on public.revision_requests(task_id) where task_id is not null;


-- ──────────── 2. TRADUÇÃO DOS STATUS ────────────
-- Os dois vocabulários dizem a mesma coisa com palavras diferentes.
-- A correspondência é um-para-um: traduzir de ida e de volta devolve
-- sempre o valor de partida — é isso que impede os dois gatilhos de
-- ficarem se corrigindo em círculo.
create or replace function public.ajuste_status_para_tarefa(s text)
returns text language sql immutable as $fn$
  select case s
    when 'aberto'       then 'pendente'
    when 'em_andamento' then 'em_andamento'
    when 'concluido'    then 'concluida'
    when 'recusado'     then 'cancelada'
    else 'pendente' end
$fn$;

create or replace function public.tarefa_status_para_ajuste(s text)
returns text language sql immutable as $fn$
  select case s
    when 'pendente'     then 'aberto'
    when 'em_andamento' then 'em_andamento'
    when 'concluida'    then 'concluido'
    when 'cancelada'    then 'recusado'
    else 'aberto' end
$fn$;


-- ──────────── 3. AJUSTE NOVO NASCE COM TAREFA ────────────
-- Ajuste registrado já concluído (ou recusado) não ganha cartão: o
-- quadro é para o que ainda está por fazer, e nascer na coluna
-- "Concluído" só enche a tela.
create or replace function public.ajuste_cria_tarefa()
returns trigger language plpgsql as $fn$
declare v_task uuid;
begin
  if new.task_id is not null then return new; end if;
  if new.status in ('concluido','recusado') then return new; end if;

  insert into public.tasks (title, description, project_id, status, priority)
  values (new.title, new.description, new.project_id,
          public.ajuste_status_para_tarefa(new.status),
          new.priority)
  returning id into v_task;

  new.task_id := v_task;
  return new;
end $fn$;

drop trigger if exists trg_ajuste_cria_tarefa on public.revision_requests;
create trigger trg_ajuste_cria_tarefa
  before insert on public.revision_requests
  for each row execute function public.ajuste_cria_tarefa();


-- ──────────── 4. ESPELHO: AJUSTE → TAREFA ────────────
-- O "is distinct from" no WHERE não é economia: é a trava. Se nada
-- mudou de verdade, nenhuma linha é escrita, o gatilho do outro lado
-- não dispara, e a ida-e-volta morre no primeiro passo.
create or replace function public.ajuste_sincroniza_tarefa()
returns trigger language plpgsql as $fn$
declare v_status text;
begin
  if new.task_id is null then return null; end if;
  v_status := public.ajuste_status_para_tarefa(new.status);

  update public.tasks t set
    title        = new.title,
    description  = new.description,
    project_id   = new.project_id,
    priority     = new.priority,
    status       = v_status,
    completed_at = case when v_status = 'concluida'
                        then coalesce(t.completed_at, new.completed_at, now())
                        else null end
  where t.id = new.task_id
    and (t.title, t.description, t.project_id, t.priority, t.status)
        is distinct from
        (new.title, new.description, new.project_id, new.priority, v_status);

  return null;
end $fn$;

drop trigger if exists trg_ajuste_sincroniza_tarefa on public.revision_requests;
create trigger trg_ajuste_sincroniza_tarefa
  after update of title, description, project_id, priority, status, task_id
  on public.revision_requests
  for each row execute function public.ajuste_sincroniza_tarefa();


-- ──────────── 5. ESPELHO: TAREFA → AJUSTE ────────────
-- De propósito o project_id NÃO volta. O ajuste é o "#3 deste projeto";
-- arrastá-lo para outro projeto deixaria a numeração mentindo. A tela
-- trava o campo Projeto nos cartões de ajuste.
create or replace function public.tarefa_sincroniza_ajuste()
returns trigger language plpgsql as $fn$
declare v_status text;
begin
  v_status := public.tarefa_status_para_ajuste(new.status);

  update public.revision_requests r set
    title        = new.title,
    description  = new.description,
    priority     = new.priority,
    status       = v_status,
    completed_at = case when v_status = 'concluido'
                        then coalesce(r.completed_at, new.completed_at, now())
                        else null end
  where r.task_id = new.id
    and (r.title, r.description, r.priority, r.status)
        is distinct from
        (new.title, new.description, new.priority, v_status);

  return null;
end $fn$;

drop trigger if exists trg_tarefa_sincroniza_ajuste on public.tasks;
create trigger trg_tarefa_sincroniza_ajuste
  after update of title, description, priority, status on public.tasks
  for each row execute function public.tarefa_sincroniza_ajuste();


-- ──────────── 6. APAGAR ────────────
-- Apagar o AJUSTE leva o cartão junto: o pedido deixou de existir.
-- Apagar a TAREFA não apaga o ajuste — ali moram o escopo, o valor
-- cobrado e o vínculo com as horas. O cartão vira só uma vista que
-- você fechou, e a tela de Projetos oferece recriá-lo.
--
-- AFTER, não BEFORE: apagar a tarefa dispara o "on delete set null" da
-- coluna task_id, que é um UPDATE no próprio ajuste. Se ele acontecesse
-- ANTES do delete, o Postgres recusaria apagar uma linha que o comando
-- acabou de alterar. Depois, a linha já não existe e não há conflito.
create or replace function public.ajuste_apaga_tarefa()
returns trigger language plpgsql as $fn$
begin
  if old.task_id is not null then
    delete from public.tasks where id = old.task_id;
  end if;
  return null;
end $fn$;

drop trigger if exists trg_ajuste_apaga_tarefa on public.revision_requests;
create trigger trg_ajuste_apaga_tarefa
  after delete on public.revision_requests
  for each row execute function public.ajuste_apaga_tarefa();


-- ──────────── 7. RECRIAR O CARTÃO ────────────
-- Chamada pela tela de Projetos (rpc) quando um ajuste está sem
-- tarefa: os que já existiam antes deste arquivo, e os que perderam o
-- cartão porque você apagou a tarefa.
create or replace function public.ajuste_garantir_tarefa(p_revision uuid)
returns uuid language plpgsql as $fn$
declare r public.revision_requests; v_task uuid;
begin
  select * into r from public.revision_requests where id = p_revision;
  if not found then raise exception 'Ajuste não encontrado'; end if;
  if r.task_id is not null then return r.task_id; end if;

  insert into public.tasks (title, description, project_id, status, priority)
  values (r.title, r.description, r.project_id,
          public.ajuste_status_para_tarefa(r.status), r.priority)
  returning id into v_task;

  update public.revision_requests set task_id = v_task where id = p_revision;
  return v_task;
end $fn$;


-- ──────────── 8. OS AJUSTES QUE JÁ EXISTEM ────────────
-- Só os que ainda estão de pé. Os concluídos e recusados ficam onde
-- estão: são histórico, e não há o que fazer com eles no quadro.
do $do$
declare r record;
begin
  for r in select id from public.revision_requests
           where task_id is null and status in ('aberto','em_andamento')
  loop
    perform public.ajuste_garantir_tarefa(r.id);
  end loop;
end $do$;
