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
// Cartões com a lista de subtarefas aberta. Fica guardado enquanto a tela
// está aberta, para a lista não fechar sozinha a cada recarga do quadro.
const _kbAbertos = new Set();

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
     onNewSub  : (task_id) => abre o modal de nova subtarefa (opcional)
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
  }).join('') + `<div class="kb-col kb-diarias" id="kb-diarias">${kbColunaDiarias()}</div>`;

  if(_kbDiarias===null) kbCarregarDiarias();
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
            ${subs.length?`<button type="button" class="tk-sub tk-sub-btn${_kbAbertos.has(t.id)?' open':''}" aria-expanded="${_kbAbertos.has(t.id)}"
               title="${_kbAbertos.has(t.id)?'Esconder':'Ver'} as subtarefas" onclick="event.stopPropagation();kbAlternarLista('${t.id}')"><span class="seta">▶</span>${feitas}/${subs.length} subtarefas</button>`:''}
            <button class="play-btn" title="${rev?'Cronometrar este ajuste':'Cronometrar esta tarefa'}" style="margin-left:auto"
              onclick="event.stopPropagation();toggleTimer(${escapeHtml(JSON.stringify(alvo))})">▶</button>
          </div>
          ${subs.length && _kbAbertos.has(t.id) ? kbListaSubs(t.id, subs, hoje) : ''}
        </div>
      </div>
    </div>`;
}

// Lista das subtarefas dentro do cartão: concluir pelo quadradinho e
// abrir a subtarefa pelo título, sem sair do quadro.
function kbListaSubs(paiId, subs, hoje){
  return `<div class="tk-subs" onclick="event.stopPropagation()" ondragstart="event.stopPropagation()">
    ${subs.map(s=>kbLinhaSub(s, hoje, 'kbAlternarFeita', 'kbEditar')).join('')}
    ${_kb.onNewSub?`<button type="button" class="tk-subadd" onclick="kbNovaSub('${paiId}')">+ Adicionar subtarefa</button>`:''}
  </div>`;
}

// Uma linha de subtarefa. Serve ao cartão e à janela da tarefa: muda só
// a função chamada ao concluir e ao abrir.
function kbLinhaSub(s, hoje, fnConcluir, fnAbrir){
  const feita = s.status==='concluida';
  const atrasada = s.due_date && s.due_date<hoje && !feita;
  return `<div class="tk-subrow">
    <button type="button" class="task-check${feita?' done':''}" title="${feita?'Reabrir':'Concluir'}"
      aria-label="${feita?'Reabrir':'Concluir'}: ${escapeHtml(s.title)}" onclick="${fnConcluir}('${s.id}')">${feita?'✓':''}</button>
    <div class="tk-subinfo">
      <button type="button" class="tk-subtitle${feita?' done':''}" onclick="${fnAbrir}('${s.id}')">${escapeHtml(s.title)}</button>
      ${s.due_date?`<span class="tk-subdate${atrasada?' late':''}">${atrasada?'venceu ':'prazo '}${fmtDateShort(s.due_date)}</span>`:''}
    </div>
  </div>`;
}

function kbAlternarLista(id){
  _kbAbertos.has(id) ? _kbAbertos.delete(id) : _kbAbertos.add(id);
  renderTaskKanban(_kb);
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

// ──────────── TAREFAS DIÁRIAS ────────────
// Última coluna do quadro: o que precisa ser feito todo dia. É só um
// lembrete, sem check e sem status, por isso não aceita arrastar tarefa
// para cá. Mora na tabela tarefas_diarias (sql/33), carregada uma vez
// por tela aberta; as recargas do quadro reaproveitam o que já veio.
let _kbDiarias = null;         // null = ainda não carregou; {erro:true} = falhou
let _kbDiariaEditando = null;  // id do lembrete em edição, ou 'nova'

const KB_ICONE_REPETE = `<svg class="kd-ico" viewBox="0 0 24 24" aria-hidden="true"><path d="m17 2 4 4-4 4"/><path d="M3 11v-1a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/></svg>`;
const KB_ICONE_EDITAR = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/></svg>`;
const KB_ICONE_TIRAR  = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>`;

async function kbCarregarDiarias(){
  const {data, error} = await sb.from('tarefas_diarias')
    .select('id,titulo,ordem')
    .is('arquivado_em', null)
    .order('ordem').order('created_at');
  _kbDiarias = error ? {erro:true} : (data||[]);
  kbRedesenharDiarias();
}

function kbRedesenharDiarias(){
  const col = document.getElementById('kb-diarias');
  if(col) col.innerHTML = kbColunaDiarias();
  const campo = col && col.querySelector('.kd-input');
  if(campo){ campo.focus(); campo.setSelectionRange(campo.value.length, campo.value.length) }
}

function kbColunaDiarias(){
  const lista = Array.isArray(_kbDiarias) ? _kbDiarias : [];
  let corpo;
  if(_kbDiarias===null)     corpo = '<div class="kb-more">carregando…</div>';
  else if(_kbDiarias.erro)  corpo = `<div class="kd-vazio">Não foi possível carregar os lembretes.
                                       <button type="button" class="tk-subadd" onclick="kbCarregarDiarias()">Tentar de novo</button></div>`;
  else {
    corpo = (_kbDiariaEditando==='nova' ? kbFormDiaria('nova', '') : '')
      + lista.map(d=> d.id===_kbDiariaEditando ? kbFormDiaria(d.id, d.titulo) : kbItemDiaria(d)).join('');
    if(!lista.length && _kbDiariaEditando!=='nova')
      corpo = `<div class="kd-vazio">Anote aqui o que precisa ser feito todo dia, para não esquecer.
                 <button type="button" class="tk-subadd" onclick="kbDiariaNova()">+ Adicionar lembrete</button></div>`;
  }
  return `
    <div class="kb-hd">
      <div class="kb-dot" style="background:#60A5FA"></div>
      <div class="kb-title" title="Lembretes de todo dia. Não precisam de check.">Tarefas diárias</div>
      <div class="kb-sum">${lista.length||''}</div>
      <button class="kb-add" title="Novo lembrete diário" aria-label="Novo lembrete diário" onclick="kbDiariaNova()">＋</button>
    </div>
    <div class="kb-body">${corpo}</div>`;
}

function kbItemDiaria(d){
  return `
    <div class="kd-item">
      ${KB_ICONE_REPETE}
      <span class="kd-txt">${escapeHtml(d.titulo)}</span>
      <span class="kd-acoes">
        <button type="button" class="kd-btn" title="Editar" aria-label="Editar: ${escapeHtml(d.titulo)}" onclick="kbDiariaEditar('${d.id}')">${KB_ICONE_EDITAR}</button>
        <button type="button" class="kd-btn" title="Tirar da lista" aria-label="Tirar da lista: ${escapeHtml(d.titulo)}" onclick="kbDiariaTirar('${d.id}')">${KB_ICONE_TIRAR}</button>
      </span>
    </div>`;
}

function kbFormDiaria(id, titulo){
  return `
    <form class="kd-form" onsubmit="kbDiariaSalvar(event,'${id}')">
      <label class="sr-only" for="kd-campo">Lembrete diário</label>
      <input id="kd-campo" class="kd-input" maxlength="200" required value="${escapeHtml(titulo)}"
             placeholder="Ex.: responder o direct do Instagram" onkeydown="if(event.key==='Escape')kbDiariaCancelar()">
      <div class="kd-form-acoes">
        <button type="button" class="btn btn-ghost btn-sm" onclick="kbDiariaCancelar()">Cancelar</button>
        <button type="submit" class="btn btn-primary btn-sm">Salvar</button>
      </div>
    </form>`;
}

function kbDiariaNova(){ _kbDiariaEditando = 'nova'; kbRedesenharDiarias() }
function kbDiariaEditar(id){ _kbDiariaEditando = id; kbRedesenharDiarias() }
function kbDiariaCancelar(){ _kbDiariaEditando = null; kbRedesenharDiarias() }

async function kbDiariaSalvar(e, id){
  e.preventDefault();
  const titulo = e.target.querySelector('.kd-input').value.trim();
  if(!titulo){ showToast('Escreva o lembrete antes de salvar', true); return }
  if(titulo.length>200){ showToast('O lembrete passa de 200 caracteres. Encurte um pouco.', true); return }
  const lista = Array.isArray(_kbDiarias) ? _kbDiarias : [];
  const {error} = id==='nova'
    ? await sb.from('tarefas_diarias').insert({titulo, ordem: lista.reduce((m,d)=>Math.max(m,d.ordem), -1)+1})
    : await sb.from('tarefas_diarias').update({titulo}).eq('id', id);
  if(error){ showToast('Não foi possível salvar o lembrete', true); return }
  showToast(id==='nova' ? 'Lembrete adicionado' : 'Lembrete salvo');
  _kbDiariaEditando = null;
  await kbCarregarDiarias();
}

// "Tirar" só arquiva: o lembrete sai do quadro, mas fica guardado no banco.
async function kbDiariaTirar(id){
  const d = (_kbDiarias||[]).find?.(x=>x.id===id);
  if(!d || !confirm('Tirar "'+d.titulo+'" das tarefas diárias?')) return;
  const {error} = await sb.from('tarefas_diarias').update({arquivado_em: new Date().toISOString()}).eq('id', id);
  if(error){ showToast('Não foi possível tirar o lembrete', true); return }
  showToast('Lembrete tirado da lista');
  await kbCarregarDiarias();
}

// ──────────── PONTES PARA A TELA ────────────
function kbEditar(id){ _kb.onEdit(id) }
function kbNovaTarefa(status){ _kb.onNew(status) }
function kbNovaSub(paiId){ _kb.onNewSub && _kb.onNewSub(paiId) }

// ──────────── SUBTAREFAS NA JANELA DA TAREFA ────────────
// A janela "Editar tarefa" das duas telas mostra as subtarefas da tarefa
// principal, com o andamento. Concluir aqui grava na hora e não fecha a
// janela, para quem está revisando a lista seguir marcando.
/* cfg = {
     subsOf : (task_id) => [subtarefas]
     taskOf : (task_id) => tarefa
     reload : async ()  => recarrega os dados da tela
     onOpen : (task_id) => abre a subtarefa na mesma janela
     onAdd  : (task_id) => abre a janela de nova subtarefa
   }
   paiId nulo esconde o bloco (tarefa nova, subtarefa ou ajuste). */
let _kbJanela = null;
function kbSubsNaJanela(paiId, cfg){
  const box = document.getElementById('t-subs-box');
  if(!box) return;
  if(!paiId){ box.style.display = 'none'; _kbJanela = null; return }
  _kbJanela = Object.assign({paiId}, cfg || (_kbJanela||{}));
  const subs = _kbJanela.subsOf(paiId) || [];
  const feitas = subs.filter(s=>s.status==='concluida').length;
  const pct = subs.length ? Math.round(feitas/subs.length*100) : 0;
  const hoje = todayISO();
  box.style.display = '';
  box.innerHTML = `
    <div class="tsubs-hd">
      <span class="tsubs-title">Subtarefas</span>
      <span class="tsubs-count">${subs.length ? feitas+' de '+subs.length+' concluídas' : ''}</span>
    </div>
    ${subs.length ? `<div class="tsubs-track" role="img" aria-label="${pct}% concluído"><i style="width:${pct}%"></i></div>` : ''}
    <div class="tsubs-list">
      ${subs.length ? subs.map(s=>kbLinhaSub(s, hoje, 'kbJanelaConcluir', 'kbJanelaAbrir')).join('')
                    : '<div class="tsubs-vazio">Nenhuma subtarefa ainda. Divida a tarefa em passos menores.</div>'}
    </div>
    <button type="button" class="tk-subadd" onclick="kbJanelaNova()">+ Adicionar subtarefa</button>`;
}

async function kbJanelaConcluir(id){
  if(!_kbJanela) return;
  const t = _kbJanela.taskOf(id);
  if(!t) return;
  const feita = t.status==='concluida';
  const payload = feita ? {status:'pendente', completed_at:null}
                        : {status:'concluida', completed_at:new Date().toISOString()};
  const {error} = await sb.from('tasks').update(payload).eq('id', id);
  if(error){ showToast('Erro: '+error.message, true); return }
  showToast(feita ? 'Subtarefa reaberta' : 'Subtarefa concluída ✓');
  if(!feita && typeof fireAutomation === 'function')
    await fireAutomation('task.completed', {table:'tasks', id, row:{...t, status:'concluida'}});
  await _kbJanela.reload();
  kbSubsNaJanela(_kbJanela.paiId);
}
function kbJanelaAbrir(id){ _kbJanela && _kbJanela.onOpen(id) }
function kbJanelaNova(){ _kbJanela && _kbJanela.onAdd(_kbJanela.paiId) }
