/* ════════════════════════════════════════════════════════════════════
   TIMER.JS — Cronômetro de trabalho e lembretes

   A FONTE DA VERDADE É O BANCO, não o navegador.
   Cronômetro rodando = a única linha em time_entries com ended_at nulo.
   Por isso:
     · recarregar a página não perde o tempo;
     · o celular vê o mesmo cronômetro que o computador;
     · fechar a aba deixa o cronômetro aberto (o needs_review pega isso).

   O localStorage guarda SÓ um cache pra desenhar o widget antes da
   primeira consulta. Ele nunca é a verdade.

   Depende de: shared.js (sb, showToast, fmtDuration, fmtHHMMSS, escapeHtml)
   ════════════════════════════════════════════════════════════════════ */

const TIMER_CACHE_KEY = 'jp_timer';
const NUDGE_KEY       = 'jp_last_nudge';
const NUDGE_MS        = 15*60*1000;   // lembrete a cada 15 min
const LONGO_DEMAIS_MIN = 90;          // avisa se o cronômetro passa disso

let _timer   = null;   // linha de time_entries em execução (ou null)
let _tick    = null;   // setInterval que redesenha o relógio
let _nudger  = null;   // setInterval do lembrete
let _recentes = null;  // ultimos alvos cronometrados (cache da sessao)

// ──────────── ESTADO ────────────

async function getRunningTimer(){
  const {data, error} = await sb.from('time_entries')
    .select('*').is('ended_at', null).limit(1).maybeSingle();
  if(error) return null;
  return data || null;
}

function cacheTimer(t){
  try{
    if(t) localStorage.setItem(TIMER_CACHE_KEY, JSON.stringify(t));
    else  localStorage.removeItem(TIMER_CACHE_KEY);
  }catch(e){ /* modo anônimo / storage bloqueado — o widget só fica sem cache */ }
}

function readCache(){
  try{ return JSON.parse(localStorage.getItem(TIMER_CACHE_KEY)||'null') }
  catch(e){ return null }
}

// ──────────── AÇÕES ────────────

// opts: {project_id, task_id, revision_id, area, kind, description, label}
// `label` é só o texto exibido no widget (não vai pro banco).
async function startTimer(opts = {}){
  const {project_id=null, task_id=null, revision_id=null,
         area=null, description=null, label=null} = opts;
  const kind = opts.kind || (revision_id ? 'ajuste' : (project_id||task_id ? 'projeto' : 'geral'));

  // Para o anterior antes de abrir o novo. O índice único do banco
  // (uniq_timer_em_execucao) é a rede de segurança se isso falhar.
  await stopTimer({silent:true});

  const {data, error} = await sb.from('time_entries')
    .insert({project_id, task_id, revision_id, area, kind, description})
    .select('*').single();
  if(error){ showToast('Erro ao iniciar: '+error.message, true); return null }

  _timer = {...data, _label: label || descreverTimer(data)};
  _recentes = null;            // o alvo novo vira o primeiro da lista
  cacheTimer(_timer);
  renderTimerBar();
  showToast('Cronômetro iniciado ⏱');
  return _timer;
}

async function stopTimer({silent=false}={}){
  const run = _timer || await getRunningTimer();
  if(!run) return null;
  const {error} = await sb.from('time_entries')
    .update({ended_at:new Date().toISOString()}).eq('id', run.id);
  if(error){ if(!silent) showToast('Erro ao parar: '+error.message, true); return null }

  const seg = Math.max(0, Math.round((Date.now() - new Date(run.started_at))/1000));
  _timer = null;
  _recentes = null;
  cacheTimer(null);
  renderTimerBar();
  if(!silent) showToast('Cronômetro parado — '+fmtDuration(seg)+' registrados ✓');
  return seg;
}

// Alterna: se já está rodando exatamente neste alvo, para. Senão, troca.
async function toggleTimer(opts = {}){
  const run = _timer || await getRunningTimer();
  const mesmoAlvo = run
    && (run.revision_id||null) === (opts.revision_id||null)
    && (run.task_id||null)     === (opts.task_id||null)
    && (run.project_id||null)  === (opts.project_id||null);
  if(mesmoAlvo) return stopTimer();
  return startTimer(opts);
}

function descreverTimer(t){
  if(!t) return '';
  if(t.description) return t.description;
  if(t.area) return t.area;
  return {projeto:'Projeto', ajuste:'Ajuste', geral:'Trabalho geral'}[t.kind] || 'Trabalho';
}

// ──────────── WIDGET NA TOPBAR ────────────
// Injeta a pílula do cronômetro na .topbar de toda página de gestão.
// Chamado no fim de renderSidebar() (shared.js).

function ensureTimerBar(){
  let bar = document.getElementById('timer-bar');
  if(bar) return bar;
  const topbar = document.querySelector('.topbar');
  if(!topbar) return null;
  bar = document.createElement('div');
  bar.id = 'timer-bar';
  bar.className = 'timer-bar';
  // Entra antes do último bloco da topbar (normalmente os botões da página)
  topbar.insertBefore(bar, topbar.lastElementChild);
  return bar;
}

function renderTimerBar(){
  const bar = ensureTimerBar();
  if(!bar) return;
  const t = _timer || readCache();

  if(!t){
    bar.className = 'timer-bar';
    bar.innerHTML = `<button class="timer-btn" onclick="abrirTrocaTimer(event)" title="Retomar algo recente ou escolher outro">⏱ Iniciar</button>`;
    if(_tick){ clearInterval(_tick); _tick = null }
    return;
  }

  bar.className = 'timer-bar on';
  const desenhar = ()=>{
    const el = document.getElementById('timer-clock');
    if(!el) return;
    el.textContent = fmtHHMMSS(Math.max(0,(Date.now()-new Date(t.started_at))/1000));
  };
  bar.innerHTML = `
    <span class="timer-dot"></span>
    <span class="timer-clock" id="timer-clock">00:00:00</span>
    <span class="timer-label">${escapeHtml(t._label || descreverTimer(t))}</span>
    <button class="timer-btn" onclick="abrirTrocaTimer(event)" title="Trocar de alvo — o tempo até agora fica gravado">⇄</button>
    <button class="timer-btn stop" onclick="stopTimer()" title="Parar cronômetro">■</button>`;
  desenhar();
  if(_tick) clearInterval(_tick);
  _tick = setInterval(desenhar, 1000);
}

// ──────────── TROCA EM 1 CLIQUE ────────────
// Só pode existir um cronômetro rodando (índice uniq_timer_em_execucao no
// banco). Como na prática você pula entre tarefas em vez de fazer duas no
// mesmo segundo, o que resolve não é rodar dois — é trocar rápido.
// O ⇄ abre os últimos alvos: um clique fecha o atual (o tempo já contado
// fica gravado) e abre o novo, sem passar pelo modal de 3 campos.

function chaveAlvo(o){
  return [o.revision_id||'', o.task_id||'', o.project_id||'', o.area||''].join('|');
}

// Os últimos alvos distintos, com o nome de cada um. Cache da sessão:
// zerado sempre que um cronômetro inicia ou para.
async function carregarRecentes(){
  if(_recentes) return _recentes;

  const {data} = await sb.from('time_entries')
    .select('project_id,task_id,revision_id,area,kind,description,started_at')
    .order('started_at',{ascending:false}).limit(80);
  const linhas = data || [];

  // Os nomes não estão em time_entries: uma consulta por tipo, só dos ids que apareceram.
  const ids = k => [...new Set(linhas.map(l=>l[k]).filter(Boolean))];
  const [pr, ta, re] = await Promise.all([
    ids('project_id').length  ? sb.from('projects').select('id,name').in('id', ids('project_id'))                : {data:[]},
    ids('task_id').length     ? sb.from('tasks').select('id,title').in('id', ids('task_id'))                     : {data:[]},
    ids('revision_id').length ? sb.from('revision_requests').select('id,number,title').in('id', ids('revision_id')) : {data:[]},
  ]);
  const nomeProj = Object.fromEntries((pr.data||[]).map(p=>[p.id, p.name]));
  const nomeTask = Object.fromEntries((ta.data||[]).map(t=>[t.id, t.title]));
  const nomeRev  = Object.fromEntries((re.data||[]).map(r=>[r.id, 'Ajuste #'+(r.number||'')+' — '+r.title]));

  const vistos = new Set(), out = [];
  for(const l of linhas){
    const chave = chaveAlvo(l);
    if(vistos.has(chave)) continue;

    let label = '', sub = '';
    if(l.revision_id)     { label = nomeRev[l.revision_id];  sub = nomeProj[l.project_id] || '' }
    else if(l.task_id)    { label = nomeTask[l.task_id];     sub = nomeProj[l.project_id] || '' }
    else if(l.project_id) { label = nomeProj[l.project_id];  sub = l.description || '' }
    else if(l.area)       { label = l.description || l.area; sub = l.description ? l.area : '' }
    // Sem nome = projeto/tarefa apagado depois, ou tempo solto sem alvo.
    // Não volta pro menu: ninguém saberia no que estaria clicando.
    if(!label) continue;

    vistos.add(chave);
    out.push({chave, label, sub, opts:{
      project_id: l.project_id, task_id: l.task_id, revision_id: l.revision_id,
      area: l.area, kind: l.kind, description: l.description, label,
    }});
    if(out.length >= 6) break;   // 6 pra sobrar um depois de tirar o alvo atual
  }
  _recentes = out;
  return out;
}

let _menuItens = [];

function _fecharMenuFora(e){
  // Sem menu na tela (a pílula foi redesenhada por baixo) também cai aqui:
  // o fechar solta os listeners e não deixa nada pendurado no document.
  const m = document.getElementById('timer-menu');
  if(!m || !m.contains(e.target)) fecharTrocaTimer();
}
function _fecharMenuEsc(e){ if(e.key === 'Escape') fecharTrocaTimer() }

function fecharTrocaTimer(){
  document.getElementById('timer-menu')?.remove();
  document.removeEventListener('click', _fecharMenuFora);
  document.removeEventListener('keydown', _fecharMenuEsc);
}

async function abrirTrocaTimer(ev){
  ev?.stopPropagation();                                   // senão o próprio clique fecha o menu
  if(document.getElementById('timer-menu')) return fecharTrocaTimer();
  const bar = document.getElementById('timer-bar');
  if(!bar) return;

  const menu = document.createElement('div');
  menu.id = 'timer-menu';
  menu.className = 'timer-menu';
  menu.innerHTML = '<div class="tm-empty">carregando…</div>';
  bar.appendChild(menu);
  document.addEventListener('click', _fecharMenuFora);
  document.addEventListener('keydown', _fecharMenuEsc);

  const atual = _timer ? chaveAlvo(_timer) : '';
  _menuItens = (await carregarRecentes()).filter(r => r.chave !== atual).slice(0,5);
  if(!document.getElementById('timer-menu')) return;       // fechou enquanto carregava

  menu.innerHTML =
    (_menuItens.length
      ? `<div class="tm-head">${_timer ? 'Trocar para' : 'Retomar'}</div>` +
        _menuItens.map((r,i)=>`
          <button class="tm-item" onclick="trocarTimerPara(${i})">${escapeHtml(r.label)}${
            r.sub ? `<span class="tm-sub">${escapeHtml(r.sub)}</span>` : ''}</button>`).join('') +
        '<div class="tm-sep"></div>'
      : '') +
    `<button class="tm-item" onclick="fecharTrocaTimer();abrirSeletorTimer()">${
      _menuItens.length ? 'Outro…' : 'Escolher no que trabalhar…'}</button>`;
}

async function trocarTimerPara(i){
  const alvo = _menuItens[i];
  fecharTrocaTimer();
  if(alvo) await startTimer(alvo.opts);   // startTimer já fecha o cronômetro anterior
}


// ──────────── SELETOR: no que você vai trabalhar? ────────────
// Antes, "Iniciar" ligava um cronômetro solto e todo tempo fora de
// projeto virava um balaio só. Agora ele pergunta — e a resposta pode
// ser um projeto, uma tarefa específica, ou uma ÁREA do negócio
// (marketing, comercial, gestão...). Sem isso, o relatório não separa
// atender cliente de tocar o negócio.
//
// O modal é criado por este arquivo, e não por cada página, porque a
// pílula do cronômetro aparece em todas elas.

const AREAS_PADRAO = ['Marketing','Comercial / prospecção','Gestão do negócio',
                      'Financeiro','Administrativo','Estudo e formação','Suporte a cliente'];

function montarSeletorTimer(){
  if(document.getElementById('modal-timer')) return;
  const div = document.createElement('div');
  div.className = 'overlay';
  div.id = 'modal-timer';
  div.innerHTML = `
    <div class="modal" style="width:520px">
      <div class="modal-title">No que você vai trabalhar?</div>

      <div class="tabs-row" style="margin-bottom:16px">
        <div class="dtab active" data-ttab="projeto" onclick="abaTimer('projeto')">Projeto de cliente</div>
        <div class="dtab" data-ttab="area" onclick="abaTimer('area')">Área do negócio</div>
      </div>

      <div id="ttab-projeto">
        <div class="form-group"><label class="form-label">Projeto *</label>
          <select class="form-input form-select" id="tm-project" onchange="tmCarregarTarefas()"></select></div>
        <div class="form-group"><label class="form-label">Tarefa (opcional)</label>
          <select class="form-input form-select" id="tm-task"><option value="">— o projeto todo —</option></select>
          <div style="font-size:11.5px;color:var(--text3);margin-top:5px">Escolher a tarefa deixa o relatório mais preciso, mas não é obrigatório.</div></div>
        <div class="form-group"><label class="form-label">Pedido de ajuste (opcional)</label>
          <select class="form-input form-select" id="tm-rev"><option value="">— não é ajuste —</option></select>
          <div style="font-size:11.5px;color:var(--text3);margin-top:5px">Se marcar aqui, o tempo conta como ajuste — é o que separa escopo de trabalho extra.</div></div>
      </div>

      <div id="ttab-area" style="display:none">
        <div class="form-group"><label class="form-label">Área *</label>
          <select class="form-input form-select" id="tm-area"></select></div>
        <div class="form-group"><label class="form-label">O que exatamente (opcional)</label>
          <input class="form-input" id="tm-desc" placeholder="Ex.: gravar reels da semana"></div>
        <div class="note-box">Este tempo não entra em nenhum projeto — entra no total da área, para você ver quanto do mês foi para tocar o negócio em vez de atender cliente.</div>
      </div>

      <div class="modal-footer">
        <button class="btn btn-ghost" onclick="closeModal('modal-timer')">Cancelar</button>
        <button class="btn btn-primary" id="btn-start-timer" onclick="confirmarSeletorTimer()">▶ Começar</button>
      </div>
    </div>`;
  document.body.appendChild(div);
  div.addEventListener('click', e=>{ if(e.target===div) div.classList.remove('open') });
}

let _tmProjetos = [], _tmTarefas = [], _tmAjustes = [], _tmAba = 'projeto';

function abaTimer(nome){
  _tmAba = nome;
  document.querySelectorAll('#modal-timer .dtab').forEach(t=>t.classList.toggle('active', t.dataset.ttab===nome));
  document.getElementById('ttab-projeto').style.display = nome==='projeto' ? 'block' : 'none';
  document.getElementById('ttab-area').style.display    = nome==='area'    ? 'block' : 'none';
}

function tmCarregarTarefas(){
  const pid = document.getElementById('tm-project').value;
  const st = document.getElementById('tm-task');
  st.innerHTML = '<option value="">— o projeto todo —</option>' +
    _tmTarefas.filter(t=>t.project_id===pid && t.status!=='concluida' && t.status!=='cancelada')
      .map(t=>`<option value="${t.id}">${escapeHtml(t.parent_task_id?'↳ ':'')}${escapeHtml(t.title)}</option>`).join('');
  const sr = document.getElementById('tm-rev');
  sr.innerHTML = '<option value="">— não é ajuste —</option>' +
    _tmAjustes.filter(r=>r.project_id===pid)
      .map(r=>`<option value="${r.id}">#${r.number||''} ${escapeHtml(r.title)}</option>`).join('');
}

async function abrirSeletorTimer(){
  montarSeletorTimer();
  openModal('modal-timer');

  const [projRes, taskRes, revRes, areasTxt] = await Promise.all([
    sb.from('projects').select('id,name,status,archived').eq('archived', false).order('name'),
    sb.from('tasks').select('id,title,project_id,status,parent_task_id').not('project_id','is',null).limit(500),
    sb.from('revision_requests').select('id,number,title,project_id').in('status',['aberto','em_andamento']),
    getSetting('areas_trabalho'),
  ]);
  _tmProjetos = projRes.data || [];
  _tmTarefas  = taskRes.data || [];
  _tmAjustes  = revRes.data || [];

  const sp = document.getElementById('tm-project');
  sp.innerHTML = _tmProjetos.length
    ? _tmProjetos.map(p=>`<option value="${p.id}">${escapeHtml(p.name)}</option>`).join('')
    : '<option value="">— nenhum projeto ativo —</option>';
  tmCarregarTarefas();

  const areas = (areasTxt || AREAS_PADRAO.join('\n')).split('\n').map(a=>a.trim()).filter(Boolean);
  document.getElementById('tm-area').innerHTML =
    areas.map(a=>`<option value="${escapeHtml(a)}">${escapeHtml(a)}</option>`).join('');

  // Sem projeto ativo, começa direto na aba de área — é o caso dela
  // antes de cadastrar o primeiro projeto.
  abaTimer(_tmProjetos.length ? 'projeto' : 'area');
}

async function confirmarSeletorTimer(){
  const btn = document.getElementById('btn-start-timer');
  btn.disabled = true;
  try{
    if(_tmAba === 'area'){
      const area = document.getElementById('tm-area').value;
      if(!area){ showToast('Escolha uma área', true); return }
      const desc = document.getElementById('tm-desc').value.trim() || null;
      await startTimer({kind:'geral', area, description:desc, label: desc || area});
    }else{
      const pid = document.getElementById('tm-project').value;
      if(!pid){ showToast('Escolha um projeto', true); return }
      const tid = document.getElementById('tm-task').value || null;
      const rid = document.getElementById('tm-rev').value || null;
      const nome = rid ? (_tmAjustes.find(r=>r.id===rid)?.title)
                 : tid ? (_tmTarefas.find(t=>t.id===tid)?.title)
                 : (_tmProjetos.find(p=>p.id===pid)?.name);
      await startTimer({
        project_id: pid, task_id: tid, revision_id: rid,
        kind: rid ? 'ajuste' : 'projeto', label: nome,
      });
    }
    closeModal('modal-timer');
  }finally{
    btn.disabled = false;
  }
}

// Reconcilia o widget com o banco. Chamado no boot de cada página.
async function initTimer(){
  renderTimerBar();                 // desenha já, pelo cache
  const run = await getRunningTimer();
  _timer = run ? {...run, _label: descreverTimer(run)} : null;
  cacheTimer(_timer);
  renderTimerBar();                 // corrige com a verdade do banco
  iniciarLembretes();
}

// ──────────── LEMBRETES ────────────
// LIMITE REAL, e está escrito na tela tempo.html:
// isto só funciona com uma aba do sistema ABERTA. Não existe worker
// nem push — com o navegador fechado, nenhum lembrete chega.

function iniciarLembretes(){
  if(_nudger) return;
  // Checa por minuto e dispara pelo localStorage: com N abas abertas,
  // só uma cutuca (as outras veem o carimbo de tempo já atualizado).
  _nudger = setInterval(async ()=>{
    if(document.visibilityState !== 'visible') return;
    let ultimo = 0;
    try{ ultimo = +(localStorage.getItem(NUDGE_KEY)||0) }catch(e){ return }
    if(Date.now()-ultimo < NUDGE_MS-5000) return;
    try{ localStorage.setItem(NUDGE_KEY, String(Date.now())) }catch(e){}

    const run = await getRunningTimer();
    if(!run){
      nudge('Sem cronômetro rodando', 'Está trabalhando em algo? Clique em ⏱ Iniciar.');
    }else{
      const min = Math.round((Date.now()-new Date(run.started_at))/60000);
      if(min >= LONGO_DEMAIS_MIN){
        nudge('Cronômetro rodando há '+fmtDuration(min*60), 'Ainda nisso? Se esqueceu, pare agora.');
      }
    }
  }, 60*1000);
}

function nudge(titulo, corpo){
  showToast(titulo+' — '+corpo);
  if('Notification' in window && Notification.permission === 'granted'){
    try{ new Notification(titulo, {body:corpo, tag:'jp-timer'}) }catch(e){}
  }
}

// Só chamar a partir do CLIQUE num botão. O Chrome bloqueia pedido de
// permissão automático no load, e um "não" é permanente até a pessoa
// mexer nas configurações do site — é caro errar isso.
async function pedirPermissaoNotificacao(){
  if(!('Notification' in window)){
    showToast('Este navegador não suporta notificações', true); return false;
  }
  if(Notification.permission === 'granted'){
    showToast('Lembretes já estão ativos ✓'); return true;
  }
  if(Notification.permission === 'denied'){
    showToast('Notificações bloqueadas. Libere nas configurações do site (cadeado na barra de endereço).', true);
    return false;
  }
  const p = await Notification.requestPermission();
  if(p === 'granted'){
    showToast('Lembretes ativados ✓');
    nudge('Lembretes ativados', 'Vou te cutucar a cada 15 min enquanto o sistema estiver aberto.');
    return true;
  }
  showToast('Lembretes não ativados', true);
  return false;
}

function statusNotificacao(){
  if(!('Notification' in window)) return 'indisponivel';
  return Notification.permission;   // 'granted' | 'denied' | 'default'
}
