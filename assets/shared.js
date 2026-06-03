/* ════════════════════════════════════════════════════════════════════
   SHARED.JS — Conexão Supabase, auth, helpers e sidebar do sistema
   Usado pelas páginas de gestão (gestao.html, tarefas.html, crm.html...)
   ════════════════════════════════════════════════════════════════════ */

// ──────────── CONFIGURAÇÃO ────────────
const SUPABASE_URL = 'https://jvtjhfganuuefswbnbrk.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_HEWDXmsh3RwtUVAh541L_Q_UGvVickl';

const { createClient } = supabase;
const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

let currentUser = null;
let currentProfile = null;

// ──────────── AUTH GUARD (admin) ────────────
// Páginas de gestão exigem sessão de admin. Sem sessão → volta pro admin.html (login).
async function requireAdmin(onReady){
  const {data:{session}} = await sb.auth.getSession();
  if(!session){ window.location.href = 'admin.html'; return; }
  const {data:profile} = await sb.from('profiles').select('*').eq('id', session.user.id).single();
  if(!profile || profile.role !== 'admin'){
    await sb.auth.signOut();
    window.location.href = 'admin.html';
    return;
  }
  currentUser = session.user;
  currentProfile = profile;
  const name = profile.name || session.user.email.split('@')[0];
  const nameEl = document.getElementById('sb-name');
  const avEl = document.getElementById('sb-av');
  if(nameEl) nameEl.textContent = name;
  if(avEl) avEl.textContent = name[0].toUpperCase();
  document.getElementById('app').style.display = 'block';
  if(onReady) onReady();
}

async function doLogout(){
  await sb.auth.signOut();
  window.location.href = 'admin.html';
}

// ──────────── SIDEBAR ────────────
// ready:false → módulo ainda em construção (badge "em breve")
const GESTAO_MODULES = [
  {id:'gestao',     href:'gestao.html',     label:'Painel',     ready:true,  icon:'<rect x="3" y="3" width="7" height="7" rx="1.5" stroke-width="1.8"/><rect x="14" y="3" width="7" height="7" rx="1.5" stroke-width="1.8"/><rect x="3" y="14" width="7" height="7" rx="1.5" stroke-width="1.8"/><rect x="14" y="14" width="7" height="7" rx="1.5" stroke-width="1.8"/>'},
  {id:'tarefas',    href:'tarefas.html',    label:'Tarefas',    ready:true, icon:'<path d="M9 11l3 3L22 4" stroke-width="1.8"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11" stroke-width="1.8"/>'},
  {id:'crm',        href:'crm.html',        label:'CRM',        ready:true, icon:'<path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2" stroke-width="1.8"/><circle cx="9" cy="7" r="4" stroke-width="1.8"/><path d="M23 21v-2a4 4 0 00-3-3.87M16 3.13a4 4 0 010 7.75" stroke-width="1.8"/>'},
  {id:'financeiro', href:'financeiro.html', label:'Financeiro', ready:false, icon:'<line x1="12" y1="1" x2="12" y2="23" stroke-width="1.8"/><path d="M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6" stroke-width="1.8"/>'},
  {id:'contratos',  href:'contratos.html',  label:'Contratos',  ready:false, icon:'<path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" stroke-width="1.8"/><polyline points="14 2 14 8 20 8" stroke-width="1.8"/><line x1="9" y1="13" x2="15" y2="13" stroke-width="1.8"/><line x1="9" y1="17" x2="13" y2="17" stroke-width="1.8"/>'},
  {id:'agenda',     href:'agenda.html',     label:'Agenda',     ready:false, icon:'<rect x="3" y="4" width="18" height="18" rx="2" stroke-width="1.8"/><line x1="16" y1="2" x2="16" y2="6" stroke-width="1.8"/><line x1="8" y1="2" x2="8" y2="6" stroke-width="1.8"/><line x1="3" y1="10" x2="21" y2="10" stroke-width="1.8"/>'},
  {id:'marketing',  href:'marketing.html',  label:'Marketing',  ready:false, icon:'<path d="M3 11l18-5v12L3 13v-2z" stroke-width="1.8"/><path d="M11.6 16.8a3 3 0 11-5.8-1.6" stroke-width="1.8"/>'},
];

function renderSidebar(activeId){
  const nav = document.getElementById('sb-nav');
  if(!nav) return;
  const item = m => m.ready
    ? `<a class="nav-item${m.id===activeId?' active':''}" href="${m.href}">
        <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">${m.icon}</svg><span>${m.label}</span></a>`
    : `<div class="nav-item soon" title="Em construção">
        <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">${m.icon}</svg><span>${m.label}</span><span class="nav-soon">breve</span></div>`;
  nav.innerHTML = `
    <div class="nav-section">Gestão</div>
    ${GESTAO_MODULES.map(item).join('')}
    <div class="nav-section">Portal do cliente</div>
    <a class="nav-item" href="admin.html">
      <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z" stroke-width="1.8"/><polyline points="9 22 9 12 15 12 15 22" stroke-width="1.8"/></svg>
      <span>Admin do portal</span></a>`;
}

// ──────────── HELPERS ────────────
function escapeHtml(s){return (s==null?'':String(s)).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function fmtDate(d){return new Date(d).toLocaleString('pt-BR',{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'})}
function fmtDateShort(d){if(!d)return '—';const s=String(d);return new Date(s.length<=10?s+'T00:00:00':s).toLocaleDateString('pt-BR',{day:'2-digit',month:'2-digit',year:'2-digit'})}
function fmtMoney(v){return (Number(v)||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'})}
function fmtSize(b){return b>1048576?(b/1048576).toFixed(1)+' MB':Math.round(b/1024)+' KB'}
function todayISO(){const d=new Date();return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0')}
function showToast(msg,isErr=false){const t=document.getElementById('toast');if(!t)return;t.textContent=msg;t.className='toast'+(isErr?' err':'');t.classList.add('show');setTimeout(()=>t.classList.remove('show'),3500)}
function openModal(id){document.getElementById(id)?.classList.add('open')}
function closeModal(id){document.getElementById(id)?.classList.remove('open')}
function setBadge(id,n){const el=document.getElementById(id);if(!el)return;el.textContent=n;el.style.display=n>0?'inline':'none'}

// Detecta erro de "tabela não existe" → orienta a rodar o SQL
function isMissingTable(error){
  return error && /relation .* does not exist|Could not find the table|schema cache/i.test(error.message||'');
}
const SQL_HINT = '<div class="empty">Tabelas de gestão ainda não criadas.<br>Rode o arquivo <b>sql/01_gestao_schema.sql</b> no SQL Editor do Supabase.</div>';

// Fecha modal clicando fora
window.addEventListener('DOMContentLoaded',()=>{
  document.querySelectorAll('.overlay').forEach(o=>{
    o.addEventListener('click',e=>{if(e.target===o)o.classList.remove('open')});
  });
});
