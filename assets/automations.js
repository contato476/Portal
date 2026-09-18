/* ════════════════════════════════════════════════════════════════════
   AUTOMATIONS.JS — Motor das regras "quando X, faça Y"

   ══════════════════════════════════════════════════════════════════
   FRONTEIRA GESTÃO ↔ PORTAL DO CLIENTE
   Automação NUNCA escreve em tabela que o cliente enxerga. Publicar
   para o cliente continua sendo um ato deliberado seu, no admin.html.
   Toda ação passa por escrever(), que barra tabela do portal.
   Qualquer ação nova precisa passar por esta lista.
   ══════════════════════════════════════════════════════════════════

   COMO AS REGRAS DISPARAM
   Não existe servidor rodando isso por trás. As regras disparam a
   partir das SUAS ações na tela: você move o card no CRM, então a aba
   está aberta, então o motor roda. Isso é uma escolha, e tem dois
   efeitos que você precisa conhecer:

   1. Repetição: se você abrir duas abas ou refizer a ação, a regra NÃO
      roda duas vezes — a tabela automation_runs tem um índice único
      que trava isso no banco.
   2. Gatilhos por data ("prazo vence em 3 dias"): eles rodam quando
      você abre o Painel, uma vez por dia. Se você ficar 3 dias sem
      abrir, eles rodam atrasados. Isso está escrito na tela de
      Automações — não é para você descobrir depois.

   Depende de: helpers.js, shared.js (sb, getSetting/setSetting)
   ════════════════════════════════════════════════════════════════════ */

// Tabelas da GESTÃO — automação pode escrever.
const TABELAS_PERMITIDAS = new Set([
  'projects','tasks','project_milestones','revision_requests',
  'crm_deals','crm_contacts','crm_activities',
  'fin_transactions','contracts','time_entries',
]);

// Tabelas do PORTAL DO CLIENTE — automação nunca escreve.
// projects fica na lista de cima porque criar um projeto não publica
// nada: o cliente só passa a ver quando entra em project_members, que
// está aqui embaixo e continua sendo só pelo admin.html.
const TABELAS_PROIBIDAS = new Set([
  'checklist_items','checklist_states','project_phases','agreements',
  'documents','project_members','project_invites','allowed_emails','profiles',
]);

// Não é async de propósito: devolve o próprio construtor de query do
// Supabase, para quem chama poder encadear .select()/.eq() normalmente.
function escrever(tabela, op, payload){
  if(TABELAS_PROIBIDAS.has(tabela) || !TABELAS_PERMITIDAS.has(tabela)){
    throw new Error('Automação bloqueada: "'+tabela+'" pertence ao portal do cliente e só pode ser alterada por você, no Admin do portal.');
  }
  return sb.from(tabela)[op](payload);
}

// ──────────── CATÁLOGO (usado pela tela de Automações) ────────────
const EVENTOS = [
  {id:'deal.won',                    label:'Ganhei um negócio no CRM',        grupo:'CRM',       campos:['title','value','contact_id','stage','expected_close']},
  {id:'deal.lost',                   label:'Perdi um negócio no CRM',         grupo:'CRM',       campos:['title','value','contact_id','lost_reason']},
  {id:'deal.created',                label:'Criei um negócio no CRM',         grupo:'CRM',       campos:['title','value','contact_id','stage']},
  {id:'contract.signed',             label:'Um contrato foi assinado',        grupo:'Contratos', campos:['title','value','contact_id','project_id']},
  // Só RECEITA. Pagar uma despesa não é "o cliente me pagou" — se o
  // mesmo evento servisse para as duas, uma regra de nota fiscal
  // dispararia ao pagar o contador.
  {id:'finance.received',            label:'Recebi um pagamento de cliente',  grupo:'Financeiro',campos:['description','amount','contact_id','project_id','category_id','due_date']},
  {id:'project.status_changed',      label:'Mudei o status de um projeto',    grupo:'Projetos',  campos:['name','status','end_date','contact_id','priority']},
  {id:'task.completed',              label:'Concluí uma tarefa',              grupo:'Projetos',  campos:['title','project_id','priority']},
  {id:'revision.created',            label:'Registrei um pedido de ajuste',   grupo:'Projetos',  campos:['title','project_id','is_billable','charged_amount','priority']},
  {id:'daily.project_deadline_near', label:'Prazo de projeto chegando',       grupo:'Diários',   campos:['name','end_date','status']},
  {id:'daily.support_expiring',      label:'Suporte de projeto acabando',     grupo:'Diários',   campos:['name','support_end']},
  {id:'daily.task_overdue',          label:'Tarefa passou do prazo',          grupo:'Diários',   campos:['title','due_date','project_id','priority']},
  {id:'daily.invoice_overdue',       label:'Conta venceu sem pagar',          grupo:'Diários',   campos:['description','amount','due_date','kind']},
];
const EVENTO_LABEL = Object.fromEntries(EVENTOS.map(e=>[e.id, e.label]));

const OPERADORES = [
  {id:'eq',       label:'é igual a',        precisaValor:true},
  {id:'neq',      label:'é diferente de',   precisaValor:true},
  {id:'gt',       label:'é maior que',      precisaValor:true},
  {id:'gte',      label:'é maior ou igual', precisaValor:true},
  {id:'lt',       label:'é menor que',      precisaValor:true},
  {id:'lte',      label:'é menor ou igual', precisaValor:true},
  {id:'contains', label:'contém o texto',   precisaValor:true},
  {id:'is_null',  label:'está vazio',       precisaValor:false},
  {id:'not_null', label:'está preenchido',  precisaValor:false},
];

const ACOES = [
  {id:'create_project',        label:'Criar um projeto'},
  {id:'create_tasks',          label:'Criar tarefas'},
  {id:'create_milestone',      label:'Criar um marco interno'},
  {id:'create_revision',       label:'Registrar um pedido de ajuste'},
  {id:'create_finance_entry',  label:'Lançar no financeiro'},
  {id:'create_contract_draft', label:'Criar rascunho de contrato'},
  {id:'create_reminder_task',  label:'Criar uma tarefa de lembrete'},
  {id:'update_deal',           label:'Atualizar o negócio do CRM'},
  {id:'update_project',        label:'Atualizar o projeto'},
  {id:'notify',                label:'Só me avisar na tela'},
];
const ACAO_LABEL = Object.fromEntries(ACOES.map(a=>[a.id, a.label]));

// ──────────── CONDIÇÕES ────────────
function valorDoCampo(row, campo){
  if(!row || !campo) return undefined;
  // Aceita "deal.value" ou só "value" — o prefixo é enfeite de leitura.
  const nome = String(campo).includes('.') ? String(campo).split('.').pop() : campo;
  return row[nome];
}

function condicaoBate(cond, row){
  const v = valorDoCampo(row, cond.field);
  const alvo = cond.value;
  const num = x => Number(x);
  switch(cond.op){
    case 'is_null':  return v===null || v===undefined || v==='';
    case 'not_null': return !(v===null || v===undefined || v==='');
    case 'eq':       return String(v) === String(alvo) || v === alvo;
    case 'neq':      return !(String(v) === String(alvo) || v === alvo);
    case 'gt':       return num(v) >  num(alvo);
    case 'gte':      return num(v) >= num(alvo);
    case 'lt':       return num(v) <  num(alvo);
    case 'lte':      return num(v) <= num(alvo);
    case 'contains': return String(v??'').toLowerCase().includes(String(alvo??'').toLowerCase());
    default:         return false;
  }
}

// Todas as condições precisam bater (E, nunca OU — é mais previsível).
function condicoesBatem(conds, row){
  if(!Array.isArray(conds) || !conds.length) return true;
  return conds.every(c=>condicaoBate(c, row));
}

// ──────────── AÇÕES ────────────
function somarDias(dias){
  const d = new Date();
  d.setDate(d.getDate() + (Number(dias)||0));
  return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
}

// Resolve "deal.title" a partir do registro que disparou; se não achar,
// usa o texto como está (assim dá para escrever um valor fixo).
function resolver(spec, row, padrao){
  if(spec===undefined || spec===null || spec==='') return padrao;
  const v = valorDoCampo(row, spec);
  return (v===undefined || v===null) ? (String(spec).includes('.') ? padrao : spec) : v;
}

const EXECUTORES = {

  async create_project(p, ctx, res){
    const nome = resolver(p.name_from, ctx.row, ctx.row?.title || ctx.row?.name || 'Novo projeto');
    const payload = {
      name: p.prefixo ? p.prefixo+' '+nome : nome,
      status: p.status || 'pre_inicio',
      priority: p.priority || 'media',
      start_date: somarDias(0),
      end_date: p.prazo_dias ? somarDias(p.prazo_dias) : null,
    };
    if(p.copiar_contato && ctx.row?.contact_id) payload.contact_id = ctx.row.contact_id;
    if(p.estimate_hours) payload.estimate_hours = p.estimate_hours;
    const {data, error} = await escrever('projects','insert', payload).select('id,name').single();
    if(error) throw error;
    res.project_id = data.id;
    res.criados = (res.criados||[]).concat('projeto "'+data.name+'"');
    // Fecha o ciclo: o negócio ganho passa a apontar para o projeto.
    if(ctx.table==='crm_deals' && ctx.id){
      await escrever('crm_deals','update',{project_id:data.id}).eq('id', ctx.id);
    }
    return res;
  },

  async create_tasks(p, ctx, res){
    const projectId = res.project_id || p.project_id || ctx.row?.project_id ||
                      (ctx.table==='projects' ? ctx.id : null);
    const titulos = Array.isArray(p.titles) ? p.titles : [];
    if(!titulos.length) return res;
    const linhas = titulos.map((t,i)=>({
      title: typeof t === 'string' ? t : t.title,
      project_id: projectId,
      priority: (typeof t === 'object' && t.priority) || 'media',
      due_date: (typeof t === 'object' && t.offset_days!=null) ? somarDias(t.offset_days) : null,
      order_num: i,
      status: 'pendente',
    })).filter(l=>l.title);
    const {error} = await escrever('tasks','insert', linhas);
    if(error) throw error;
    res.criados = (res.criados||[]).concat(linhas.length+' tarefa'+(linhas.length>1?'s':''));
    return res;
  },

  async create_milestone(p, ctx, res){
    const projectId = res.project_id || p.project_id || ctx.row?.project_id ||
                      (ctx.table==='projects' ? ctx.id : null);
    if(!projectId) throw new Error('Sem projeto para criar o marco');
    const {error} = await escrever('project_milestones','insert',{
      project_id: projectId,
      title: p.title || 'Marco',
      description: p.description || null,
      due_date: p.offset_days!=null ? somarDias(p.offset_days) : null,
    });
    if(error) throw error;
    res.criados = (res.criados||[]).concat('marco "'+(p.title||'Marco')+'"');
    return res;
  },

  async create_revision(p, ctx, res){
    const projectId = res.project_id || p.project_id || ctx.row?.project_id;
    if(!projectId) throw new Error('Sem projeto para registrar o ajuste');
    const {error} = await escrever('revision_requests','insert',{
      project_id: projectId,
      title: p.title || 'Pedido de ajuste',
      description: p.description || null,
      channel: p.channel || 'outro',
      priority: p.priority || 'media',
      is_billable: !!p.is_billable,
    });
    if(error) throw error;
    res.criados = (res.criados||[]).concat('pedido de ajuste');
    return res;
  },

  async create_finance_entry(p, ctx, res){
    const valor = Number(resolver(p.amount_from, ctx.row, p.amount || 0)) || 0;
    if(!valor) throw new Error('Sem valor para lançar no financeiro');
    const desc = (p.descricao ? p.descricao+' — ' : '') +
                 (ctx.row?.title || ctx.row?.name || ctx.row?.description || 'Automação');
    const payload = {
      kind: p.kind || 'receita',
      description: desc,
      amount: valor,
      due_date: somarDias(p.due_offset_days ?? 7),
      status: 'pendente',
      project_id: res.project_id || ctx.row?.project_id || null,
      contact_id: ctx.row?.contact_id || null,
    };
    const {error} = await escrever('fin_transactions','insert', payload);
    if(error) throw error;
    res.criados = (res.criados||[]).concat('lançamento de '+fmtMoney(valor));
    return res;
  },

  async create_contract_draft(p, ctx, res){
    const payload = {
      title: (p.title || 'Contrato') + ' — ' + (ctx.row?.title || ctx.row?.name || ''),
      status: 'rascunho',
      value: Number(resolver(p.amount_from, ctx.row, ctx.row?.value || 0)) || null,
      contact_id: ctx.row?.contact_id || null,
      project_id: res.project_id || ctx.row?.project_id || null,
      body: p.body || '',
    };
    if(p.template_id) payload.template_id = p.template_id;
    const {error} = await escrever('contracts','insert', payload);
    if(error) throw error;
    res.criados = (res.criados||[]).concat('rascunho de contrato');
    return res;
  },

  async create_reminder_task(p, ctx, res){
    // contact_name vem primeiro porque num lembrete o que identifica o
    // trabalho é o cliente, não a descrição do lançamento: "Emitir nota
    // fiscal — Gabriella" diz mais que "— Mensalidade setembro".
    // Quem dispara é que resolve o nome; sem ele, cai no que tiver.
    const alvo = ctx.row?.contact_name || ctx.row?.name || ctx.row?.title || ctx.row?.description || '';
    const {error} = await escrever('tasks','insert',{
      title: (p.title || 'Lembrete') + (alvo ? ' — '+alvo : ''),
      // Sem texto próprio, a tarefa carrega a descrição do que a
      // disparou — é o que diz QUAL recebimento gerou este lembrete.
      description: p.description || ctx.row?.description || null,
      project_id: ctx.table==='projects' ? ctx.id : (ctx.row?.project_id || null),
      priority: p.priority || 'media',
      due_date: somarDias(p.offset_days ?? 0),
      status: 'pendente',
    });
    if(error) throw error;
    res.criados = (res.criados||[]).concat('tarefa de lembrete');
    return res;
  },

  async update_deal(p, ctx, res){
    const id = ctx.table==='crm_deals' ? ctx.id : ctx.row?.deal_id;
    if(!id) throw new Error('Sem negócio para atualizar');
    const {error} = await escrever('crm_deals','update', p.set || {}).eq('id', id);
    if(error) throw error;
    res.criados = (res.criados||[]).concat('negócio atualizado');
    return res;
  },

  async update_project(p, ctx, res){
    const id = res.project_id || (ctx.table==='projects' ? ctx.id : ctx.row?.project_id);
    if(!id) throw new Error('Sem projeto para atualizar');
    const {error} = await escrever('projects','update', p.set || {}).eq('id', id);
    if(error) throw error;
    res.criados = (res.criados||[]).concat('projeto atualizado');
    return res;
  },

  async notify(p, ctx, res){
    const msg = p.message || 'Automação executada';
    const alvo = ctx.row?.name || ctx.row?.title || '';
    showToast(msg + (alvo ? ' — '+alvo : ''));
    if('Notification' in window && Notification.permission==='granted'){
      try{ new Notification(msg, {body: alvo, tag:'jp-automacao'}) }catch(e){}
    }
    res.criados = (res.criados||[]).concat('aviso');
    return res;
  },
};

// Texto humano do que a regra vai fazer — usado no confirm e na tela.
function descreverAcoes(actions){
  return (actions||[]).map(a=>{
    const p = a.params || {};
    switch(a.type){
      case 'create_project':       return '• criar um projeto' + (p.prazo_dias?` com prazo de ${p.prazo_dias} dias`:'');
      case 'create_tasks':         return `• criar ${(p.titles||[]).length} tarefa(s): ` + (p.titles||[]).map(t=>typeof t==='string'?t:t.title).join(', ');
      case 'create_milestone':     return `• criar o marco "${p.title||''}"`;
      case 'create_revision':      return '• registrar um pedido de ajuste';
      case 'create_finance_entry': return `• lançar ${p.kind==='despesa'?'uma despesa':'uma receita'} no financeiro`;
      case 'create_contract_draft':return '• criar um rascunho de contrato';
      case 'create_reminder_task': return `• criar a tarefa "${p.title||'Lembrete'}"`;
      case 'update_deal':          return '• atualizar o negócio no CRM';
      case 'update_project':       return '• atualizar o projeto';
      case 'notify':               return '• te avisar na tela';
      default:                     return '• '+a.type;
    }
  }).join('\n');
}

// ──────────── DISPARO ────────────
// ctx = {table, id, row}
async function fireAutomation(event, ctx){
  let regras;
  try{
    const {data, error} = await sb.from('automation_rules')
      .select('*').eq('trigger_event', event).eq('enabled', true);
    // Sem a tabela ainda (sql/10 não rodou), o sistema segue normal.
    if(error) return [];
    regras = data || [];
  }catch(e){ return [] }
  if(!regras.length) return [];

  const feitos = [];
  for(const regra of regras){
    if(!condicoesBatem(regra.conditions, ctx.row)) continue;

    if(regra.confirm_before_run){
      const ok = confirm(
        `Automação "${regra.name}"\n\n` +
        `Vou fazer isto agora:\n${descreverAcoes(regra.actions)}\n\n` +
        `Confirmar?\n\n(Para parar de perguntar, desmarque "perguntar antes" na tela de Automações.)`
      );
      if(!ok){
        await sb.from('automation_runs').insert({
          rule_id: regra.id, trigger_event: event,
          source_table: ctx.table, source_id: ctx.id,
          status: 'ignorado', error: 'Você cancelou',
        });
        continue;
      }
    }

    // 1) A TRAVA vem ANTES de agir. Se este insert falhar por duplicado,
    //    é porque a regra já rodou para este registro — desiste calado.
    const {data: run, error: runErr} = await sb.from('automation_runs')
      .insert({rule_id: regra.id, trigger_event: event, source_table: ctx.table, source_id: ctx.id})
      .select('id').single();
    if(runErr) continue;

    // 2) Só então executa.
    try{
      let res = {};
      for(const acao of (regra.actions||[])){
        const fn = EXECUTORES[acao.type];
        if(!fn) throw new Error('Ação desconhecida: '+acao.type);
        res = await fn(acao.params||{}, ctx, res) || res;
      }
      await sb.from('automation_runs').update({status:'sucesso', result:res}).eq('id', run.id);
      await sb.from('automation_rules')
        .update({run_count:(regra.run_count||0)+1, last_run_at:new Date().toISOString()})
        .eq('id', regra.id);
      if(!(regra.actions||[]).some(a=>a.type==='notify'))
        showToast('Automação: '+regra.name+' ✓');
      feitos.push({regra: regra.name, res});
    }catch(e){
      await sb.from('automation_runs')
        .update({status:'erro', error:String(e.message||e)}).eq('id', run.id);
      showToast('Automação "'+regra.name+'" falhou: '+(e.message||e), true);
    }
  }
  return feitos;
}

// ──────────── CHECAGENS DIÁRIAS ────────────
// Rodam quando você abre o Painel, no máximo uma vez por dia.
// NÃO existe worker: se você ficar dias sem abrir o sistema, elas rodam
// atrasadas na volta. Isso está dito na tela de Automações.
async function runDailyChecks({forcar=false} = {}){
  const hoje = todayISO();
  if(!forcar){
    const ultima = await getSetting('automation_last_daily');
    if(ultima === hoje) return {pulou:true};
  }

  // Só busca o que tem regra ligada — sem regras, custo zero.
  const {data: regras, error} = await sb.from('automation_rules')
    .select('trigger_event').eq('enabled', true).like('trigger_event','daily.%');
  if(error) return {erro:true};
  const eventos = new Set((regras||[]).map(r=>r.trigger_event));
  if(!eventos.size){ await setSetting('automation_last_daily', hoje); return {semRegras:true} }

  const em = n => { const d=new Date(); d.setDate(d.getDate()+n);
    return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0') };

  if(eventos.has('daily.project_deadline_near')){
    const {data} = await sb.from('projects').select('*')
      .not('status','in','(concluido,finalizado)').eq('archived', false)
      .gte('end_date', hoje).lte('end_date', em(7));
    for(const p of (data||[])) await fireAutomation('daily.project_deadline_near', {table:'projects', id:p.id, row:p});
  }

  if(eventos.has('daily.support_expiring')){
    const {data} = await sb.from('projects').select('*')
      .not('support_end','is',null).gte('support_end', hoje).lte('support_end', em(15));
    for(const p of (data||[])) await fireAutomation('daily.support_expiring', {table:'projects', id:p.id, row:p});
  }

  if(eventos.has('daily.task_overdue')){
    const {data} = await sb.from('tasks').select('*')
      .is('parent_task_id', null).in('status',['pendente','em_andamento'])
      .lt('due_date', hoje).limit(50);
    for(const t of (data||[])) await fireAutomation('daily.task_overdue', {table:'tasks', id:t.id, row:t});
  }

  if(eventos.has('daily.invoice_overdue')){
    const {data} = await sb.from('fin_transactions').select('*')
      .eq('status','pendente').lt('due_date', hoje).limit(50);
    for(const f of (data||[])) await fireAutomation('daily.invoice_overdue', {table:'fin_transactions', id:f.id, row:f});
  }

  await setSetting('automation_last_daily', hoje);
  return {ok:true};
}
