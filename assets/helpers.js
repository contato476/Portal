/* ════════════════════════════════════════════════════════════════════
   HELPERS.JS — Funções puras usadas por TODO o sistema
   (páginas de gestão, admin do portal e portal do cliente).

   Este arquivo não conhece Supabase nem autenticação de propósito:
   assim ele pode ser carregado em qualquer página, inclusive nas que
   têm a própria configuração (admin.html, portal.html).

   Antes elas viviam duplicadas em 3 arquivos, com versões diferentes —
   e as cópias do admin/portal tinham dois bugs reais:
     · escapeHtml(5)  → "(5||'')" devolve o NÚMERO 5, e 5.replace(...)
                        lançava TypeError, derrubando o render inteiro.
     · escapeHtml(0)  → devolvia string vazia em silêncio.
     · fmtDateShort   → "new Date(d+'T00:00:00')" vira Invalid Date
                        quando d é nulo ou um timestamp completo.
   As versões abaixo tratam os dois casos.
   ════════════════════════════════════════════════════════════════════ */

// ──────────── TEXTO ────────────
// Aceita qualquer tipo (número, null, boolean) sem quebrar.
function escapeHtml(s){
  return (s==null?'':String(s)).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

// ──────────── DATAS ────────────
function fmtDate(d){
  if(!d) return '—';
  const x = new Date(d);
  return isNaN(x) ? '—' : x.toLocaleString('pt-BR',{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'});
}
// Aceita 'YYYY-MM-DD' e timestamp completo. Em datas puras acrescenta
// T00:00:00 para não cair no dia anterior por causa do fuso.
function fmtDateShort(d){
  if(!d) return '—';
  const s = String(d);
  const x = new Date(s.length<=10 ? s+'T00:00:00' : s);
  return isNaN(x) ? '—' : x.toLocaleDateString('pt-BR',{day:'2-digit',month:'2-digit',year:'2-digit'});
}
// Data de HOJE em YYYY-MM-DD no fuso local (toISOString erraria o dia).
function todayISO(){
  const d = new Date();
  return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
}
// Dias inteiros entre duas datas (string YYYY-MM-DD ou Date).
function daysBetween(a,b){
  const p = d => { const x = new Date(String(d).length<=10 ? d+'T00:00:00' : d); x.setHours(0,0,0,0); return x };
  return Math.round((p(b)-p(a))/86400000);
}

// ──────────── NÚMEROS ────────────
function fmtMoney(v){ return (Number(v)||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'}) }
function fmtSize(b){ return b>1048576 ? (b/1048576).toFixed(1)+' MB' : Math.round(b/1024)+' KB' }
// 5400s → "1h30";  180s → "3min"
function fmtDuration(sec){
  const s = Math.max(0, Math.round(Number(sec)||0));
  const h = Math.floor(s/3600), m = Math.floor((s%3600)/60);
  if(h) return h+'h'+String(m).padStart(2,'0');
  if(m) return m+'min';
  return s+'s';
}
// 3733s → "01:02:13" (relógio do cronômetro)
function fmtHHMMSS(sec){
  const s = Math.max(0, Math.floor(Number(sec)||0));
  return [Math.floor(s/3600), Math.floor((s%3600)/60), s%60]
    .map(n=>String(n).padStart(2,'0')).join(':');
}

// ──────────── INTERFACE ────────────
// Todas toleram o elemento não existir (páginas diferentes, mesmo helper).
function showToast(msg, isErr=false){
  const t = document.getElementById('toast');
  if(!t) return;
  t.textContent = msg;
  t.className = 'toast'+(isErr?' err':'');
  t.classList.add('show');
  setTimeout(()=>t.classList.remove('show'), 3500);
}
function openModal(id){ document.getElementById(id)?.classList.add('open') }
function closeModal(id){ document.getElementById(id)?.classList.remove('open') }
function setBadge(id,n){
  const el = document.getElementById(id);
  if(!el) return;
  el.textContent = n;
  el.style.display = n>0 ? 'inline' : 'none';
}

// ──────────── ARQUIVOS ────────────
// Tira acento e caractere estranho do nome antes de subir pro storage.
function sanitizeFileName(name){
  const lastDot = name.lastIndexOf('.');
  const ext = lastDot>0 ? name.substring(lastDot) : '';
  let base = lastDot>0 ? name.substring(0,lastDot) : name;
  base = base
    .normalize('NFD').replace(/[\u0300-\u036f]/g,'')
    .replace(/[^a-zA-Z0-9_-]+/g,'_')
    .replace(/_+/g,'_')
    .replace(/^_|_$/g,'')
    .substring(0,80);
  if(!base) base = 'arquivo';
  return base + ext.toLowerCase().replace(/[^a-z0-9.]/g,'');
}

// ──────────── ERROS ────────────
// Detecta "tabela não existe" → a tela orienta a rodar o SQL.
function isMissingTable(error){
  return error && /relation .* does not exist|Could not find the table|schema cache/i.test(error.message||'');
}
const SQL_HINT = '<div class="empty">Tabelas de gestão ainda não criadas.<br>Rode o arquivo <b>sql/01_gestao_schema.sql</b> no SQL Editor do Supabase.</div>';

// ──────────── STATUS DE PROJETO ────────────
// A cor de cada status, num lugar só: o quadro de projetos e os cartões de
// tarefa (em projetos.html e tarefas.html) pintam a mesma bolinha.
const PROJ_STATUS_COLOR = {
  pre_inicio:'#E3B341', em_andamento:'#22A060', testes_cliente:'#A78BFA',
  ajustes_pos_testes:'#E3B341', aguardando:'#8B949E', pausado:'#F85149',
  concluido:'#60A5FA', finalizado:'#6E7681',
};
// Projeto encerrado: entregue (concluido) ou sem mais vínculo, suporte
// terminado (finalizado). Nenhum dos dois conta como ativo nem atrasa.
function projetoEncerrado(s){ return s==='concluido' || s==='finalizado' }
const PROJ_SEM_STATUS_COLOR = '#3F4652';   // tarefa avulsa, sem projeto
