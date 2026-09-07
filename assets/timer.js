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

// opts: {project_id, task_id, revision_id, kind, description, label}
// `label` é só o texto exibido no widget (não vai pro banco).
async function startTimer(opts = {}){
  const {project_id=null, task_id=null, revision_id=null,
         description=null, label=null} = opts;
  const kind = opts.kind || (revision_id ? 'ajuste' : (project_id||task_id ? 'projeto' : 'geral'));

  // Para o anterior antes de abrir o novo. O índice único do banco
  // (uniq_timer_em_execucao) é a rede de segurança se isso falhar.
  await stopTimer({silent:true});

  const {data, error} = await sb.from('time_entries')
    .insert({project_id, task_id, revision_id, kind, description})
    .select('*').single();
  if(error){ showToast('Erro ao iniciar: '+error.message, true); return null }

  _timer = {...data, _label: label || descreverTimer(data)};
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
    bar.innerHTML = `<button class="timer-btn" onclick="startTimer({kind:'geral'})" title="Iniciar cronômetro sem projeto">⏱ Iniciar</button>`;
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
    <button class="timer-btn stop" onclick="stopTimer()" title="Parar cronômetro">■</button>`;
  desenhar();
  if(_tick) clearInterval(_tick);
  _tick = setInterval(desenhar, 1000);
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
