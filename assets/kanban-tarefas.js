/* ════════════════════════════════════════════════════════════════════
   KANBAN-TAREFAS.JS — o quadro "A fazer / Fazendo / Concluído"

   Usado por projetos.html e tarefas.html. Nasceu duplicado nas duas
   telas; ficar assim era pedir para as duas versões divergirem — que é
   exatamente a história que o helpers.js conta no cabeçalho dele.

   Quem chama passa os dados e diz o que fazer quando algo muda; o
   desenho, o arrastar-e-soltar e a escrita no banco moram aqui.
   ════════════════════════════════════════════════════════════════════ */

// As colunas são os status que a tabela tasks já tem, com o nome do dia a
// dia. 'cancelada' não vira coluna: tarefa cancelada some do quadro.
const TASK_STATUS = [
  {id:'pendente',     label:'A fazer',   color:'#8B949E'},
  {id:'em_andamento', label:'Fazendo',   color:'#E3B341'},
  {id:'concluida',    label:'Concluído', color:'#22A060'},
];
const KB_MAX_CONCLUIDAS = 40;   // teto da coluna Concluído, para não virar arquivo morto

// ──────────── FILTRO DE PRAZO ────────────
// O quadro responde "o que eu faço agora?". Estes recortes são as três
// formas de perguntar isso: o que passou, o que é de hoje, o que vem na
// semana. Nas colunas abertas o que vale é o PRAZO; na coluna Concluído
// vale a data em que foi concluída — senão ela ficaria sempre vazia.
const KB_PRAZOS = [
  {id:'',          label:'Todos os prazos'},
  {id:'atrasadas', label:'Atrasadas'},
  {id:'hoje',      label:'Hoje'},
  {id:'semana',    label:'Próximos 7 dias'},
  {id:'sem_prazo', label:'Sem prazo'},
];

function kbOpcoesPrazo(){
  return KB_PRAZOS.map(p=>`<option value="${p.id}">${p.label}</option>`).join('');
}

function filtraPorPrazo(t, modo, hoje){
  if(!modo) return true;
  const maisSete  = kbSomaDias(hoje, 7);
  const menosSete = kbSomaDias(hoje, -7);

  if(t.status==='concluida'){
    const feitaEm = String(t.completed_at||'').slice(0,10);
    if(modo==='atrasadas') return false;                       // feita não está atrasada
    if(modo==='hoje')      return feitaEm===hoje;
    if(modo==='semana')    return !!feitaEm && feitaEm>=menosSete;   // concluídas na semana
    if(modo==='sem_prazo') return !t.due_date;
    return true;
  }
  if(modo==='sem_prazo') return !t.due_date;
  if(!t.due_date) return false;
  if(modo==='atrasadas') return t.due_date <  hoje;
  if(modo==='hoje')      return t.due_date === hoje;
  if(modo==='semana')    return t.due_date >= hoje && t.due_date <= maisSete;
  return true;
}

function kbSomaDias(iso, n){
  const d = new Date(iso+'T00:00:00');
  d.setDate(d.getDate()+n);
  return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
}

// Prazo primeiro, sem prazo por último; empate desempata pela prioridade.
const PESO_PRIO = {alta:0, media:1, baixa:2};
function ordenaPorPrazo(a,b){
  if(!!a.due_date !== !!b.due_date) return a.due_date ? -1 : 1;
  if(a.due_date && a.due_date !== b.due_date) return a.due_date < b.due_date ? -1 : 1;
  return (PESO_PRIO[a.priority]??1) - (PESO_PRIO[b.priority]??1);
}

// Guarda a última configuração para os handlers inline dos cartões.
let _kb = null;
let _kbDragId = null;

/* Desenha o quadro.
   cfg = {
     container : elemento onde o quadro é escrito
     tasks     : as tarefas já filtradas pela tela
     projectOf : (project_id) => {name, status} | null
     subsOf    : (task_id) => [subtarefas]
     taskOf    : (task_id) => tarefa
     revisionOf: (task_id) => ajuste | null   (opcional)
     onEdit    : (task_id) => abre o modal de edição da tela
     onNew     : (status)  => abre o modal de nova tarefa naquela coluna
     onChanged : ()        => recarrega os dados da tela
   } */
function renderTaskKanban(cfg){
  _kb = cfg;
  const hoje = todayISO();
  cfg.container.className = 'kanban tarefas';

  cfg.container.innerHTML = TASK_STATUS.map(s=>{
    const ts = cfg.tasks.filter(t=>t.status===s.id);
    const ordenadas = s.id==='concluida'
      ? ts.slice().sort((a,b)=>String(b.completed_at||b.due_date||'').localeCompare(String(a.completed_at||a.due_date||'')))
      : ts.slice().sort(ordenaPorPrazo);
    const mostradas = s.id==='concluida' ? ordenadas.slice(0, KB_MAX_CONCLUIDAS) : ordenadas;
    const atrasadas = s.id==='concluida' ? 0 : ts.filter(t=>t.due_date && t.due_date<hoje).length;

    return `
      <div class="kb-col">
        <div class="kb-hd">
          <div class="kb-dot" style="background:${s.color}"></div>
          <div class="kb-title">${escapeHtml(s.label)}</div>
          ${atrasadas?`<span class="badge bg-red" title="tarefas com prazo vencido">${atrasadas}</span>`:''}
          <div class="kb-sum">${ts.length}</div>
          <button class="kb-add" title="Nova tarefa nesta coluna" onclick="kbNovaTarefa('${s.id}')">＋</button>
        </div>
        <div class="kb-body" data-task-status="${s.id}"
             ondragover="kbDragOver(event)" ondragleave="kbDragLeave(event)" ondrop="kbDrop(event)">
          ${mostradas.map(t=>kbTaskCard(t, hoje)).join('') || '<div class="kb-more">nada por aqui</div>'}
          ${ts.length>mostradas.length?`<div class="kb-more">+ ${ts.length-mostradas.length} mais</div>`:''}
        </div>
      </div>`;
  }).join('');
}

function kbTaskCard(t, hoje){
  const proj = t.project_id ? _kb.projectOf(t.project_id) : null;
  const feita = t.status==='concluida';
  const atrasada = t.due_date && t.due_date<hoje && !feita;
  const subs = _kb.subsOf(t.id) || [];
  const feitas = subs.filter(s=>s.status==='concluida').length;
  const pai = t.parent_task_id && _kb.taskOf(t.parent_task_id);
  // Quando o cartão é o retrato de um pedido de ajuste, o cronômetro
  // tem que marcar no AJUSTE — senão a hora cai como tempo de projeto
  // e o relatório volta a não saber quanto os ajustes custaram.
  const rev = _kb.revisionOf ? _kb.revisionOf(t.id) : null;
  const alvo = rev
    ? {revision_id:rev.id, project_id:t.project_id||rev.project_id, kind:'ajuste',
       label:'Ajuste #'+(rev.number||'')+' — '+t.title}
    : {task_id:t.id, project_id:t.project_id||null,
       kind:t.project_id?'projeto':'geral', label:t.title};

  const datas = [];
  if(t.start_date && !feita) datas.push('início '+fmtDateShort(t.start_date));
  if(t.due_date) datas.push((atrasada?'⚠ venceu ':'prazo ')+fmtDateShort(t.due_date));
  if(!datas.length) datas.push('sem prazo');

  return `
    <div class="kb-card" draggable="true" ondragstart="kbDragStart(event,'${t.id}')"
         onclick="kbEditar('${t.id}')">
      <div class="tk-card">
        <div class="task-check${feita?' done':''}" title="${feita?'Reabrir':'Concluir'}"
             onclick="event.stopPropagation();kbAlternarFeita('${t.id}')">${feita?'✓':''}</div>
        <div style="flex:1;min-width:0">
          <div class="tk-title${feita?' done':''}">${escapeHtml(t.title)}</div>
          <div class="tk-proj">
            <i style="background:${proj ? (PROJ_STATUS_COLOR[proj.status]||'#8B949E') : PROJ_SEM_STATUS_COLOR}"></i>
            ${proj ? escapeHtml(proj.name) : 'Tarefa avulsa'}${pai?' · sub de '+escapeHtml(pai.title):''}
          </div>
          <div class="tk-meta${atrasada?' late':''}">${escapeHtml(datas.join(' · '))}</div>
          <div class="tk-foot">
            ${PRIORITY_BADGE[t.priority||'media']||''}
            ${rev?`<span class="badge bg-amber" title="Pedido de ajuste do cliente">Ajuste #${rev.number||'?'}</span>`:''}
            ${rev&&rev.is_billable?'<span class="badge bg-red" title="Fora do escopo — é cobrável">fora do escopo</span>':''}
            ${subs.length?`<span class="tk-sub">${feitas}/${subs.length} subtarefas</span>`:''}
            <button class="play-btn" title="${rev?'Cronometrar este ajuste':'Cronometrar esta tarefa'}" style="margin-left:auto"
              onclick="event.stopPropagation();toggleTimer(${escapeHtml(JSON.stringify(alvo))})">▶</button>
          </div>
        </div>
      </div>
    </div>`;
}

// ──────────── ARRASTAR E SOLTAR ────────────
function kbDragStart(e,id){ _kbDragId = id; e.dataTransfer.effectAllowed='move' }
function kbDragOver(e){ e.preventDefault(); e.currentTarget.classList.add('dragover') }
function kbDragLeave(e){ e.currentTarget.classList.remove('dragover') }

async function kbDrop(e){
  e.preventDefault();
  e.currentTarget.classList.remove('dragover');
  const status = e.currentTarget.dataset.taskStatus;
  const id = _kbDragId; _kbDragId = null;
  if(!id) return;
  const t = _kb.taskOf(id);
  if(!t || t.status===status) return;
  const o = kbNome(id);
  await kbSalvarStatus(id, status,
    status==='concluida' ? o+' concluíd'+(o==='Ajuste'?'o':'a')+' ✓'
                         : o+' movid'+(o==='Ajuste'?'o':'a')+' para '+(TASK_STATUS.find(s=>s.id===status)?.label||status));
}

function kbAlternarFeita(id){
  const t = _kb.taskOf(id);
  if(!t) return;
  const feita = t.status==='concluida';
  const o = kbNome(id), a = o==='Ajuste' ? 'o' : 'a';
  return kbSalvarStatus(id, feita?'pendente':'concluida',
    feita ? o+' reabert'+a : o+' concluíd'+a+' ✓');
}

// O cartão de um ajuste é o mesmo trabalho da aba Ajustes; chamá-lo de
// "tarefa" no aviso faria parecer que são duas coisas diferentes.
function kbNome(id){
  return (_kb.revisionOf && _kb.revisionOf(id)) ? 'Ajuste' : 'Tarefa';
}

async function kbSalvarStatus(id, status, aviso){
  const t = _kb.taskOf(id) || {};
  const payload = {status, completed_at: status==='concluida' ? new Date().toISOString() : null};
  const {error} = await sb.from('tasks').update(payload).eq('id', id);
  if(error){ showToast('Erro: '+error.message, true); return }
  showToast(aviso);
  if(status==='concluida' && typeof fireAutomation === 'function')
    await fireAutomation('task.completed', {table:'tasks', id, row:{...t, status}});
  _kb.onChanged();
}

// ──────────── PONTES PARA A TELA ────────────
function kbEditar(id){ _kb.onEdit(id) }
function kbNovaTarefa(status){ _kb.onNew(status) }
