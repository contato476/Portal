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
  {id:'gestao',      href:'gestao.html',      label:'Painel',      ready:true,  icon:'<rect x="3" y="3" width="7" height="7" rx="1.5" stroke-width="1.8"/><rect x="14" y="3" width="7" height="7" rx="1.5" stroke-width="1.8"/><rect x="3" y="14" width="7" height="7" rx="1.5" stroke-width="1.8"/><rect x="14" y="14" width="7" height="7" rx="1.5" stroke-width="1.8"/>'},
  {id:'projetos',    href:'projetos.html',    label:'Projetos',    ready:true, icon:'<path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2z" stroke-width="1.8"/>'},
  {id:'tarefas',     href:'tarefas.html',     label:'Tarefas',     ready:true, icon:'<path d="M9 11l3 3L22 4" stroke-width="1.8"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11" stroke-width="1.8"/>'},
  {id:'tempo',       href:'tempo.html',       label:'Tempo',       ready:true, icon:'<circle cx="12" cy="12" r="9" stroke-width="1.8"/><polyline points="12 7 12 12 15.5 14" stroke-width="1.8"/>'},
  {id:'crm',         href:'crm.html',         label:'CRM',         ready:true, icon:'<path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2" stroke-width="1.8"/><circle cx="9" cy="7" r="4" stroke-width="1.8"/><path d="M23 21v-2a4 4 0 00-3-3.87M16 3.13a4 4 0 010 7.75" stroke-width="1.8"/>'},
  {id:'indicacoes',  href:'indicacoes.html',  label:'Indicações',  ready:true, icon:'<circle cx="18" cy="5" r="3" stroke-width="1.8"/><circle cx="6" cy="12" r="3" stroke-width="1.8"/><circle cx="18" cy="19" r="3" stroke-width="1.8"/><line x1="8.6" y1="10.5" x2="15.4" y2="6.5" stroke-width="1.8"/><line x1="8.6" y1="13.5" x2="15.4" y2="17.5" stroke-width="1.8"/>'},
  {id:'financeiro',  href:'financeiro.html',  label:'Financeiro',  ready:true, icon:'<line x1="12" y1="1" x2="12" y2="23" stroke-width="1.8"/><path d="M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6" stroke-width="1.8"/>'},
  {id:'contratos',   href:'contratos.html',   label:'Contratos',   ready:true, icon:'<path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" stroke-width="1.8"/><polyline points="14 2 14 8 20 8" stroke-width="1.8"/><line x1="9" y1="13" x2="15" y2="13" stroke-width="1.8"/><line x1="9" y1="17" x2="13" y2="17" stroke-width="1.8"/>'},
  {id:'agendamento', href:'agendamento.html', label:'Agendamento', ready:true, icon:'<rect x="3" y="4" width="18" height="18" rx="2" stroke-width="1.8"/><line x1="3" y1="10" x2="21" y2="10" stroke-width="1.8"/><polyline points="8.5 15 11 17.5 15.5 13" stroke-width="1.8"/>'},
  {id:'marketing',   href:'marketing.html',   label:'Marketing',   ready:true, icon:'<path d="M3 11l18-5v12L3 13v-2z" stroke-width="1.8"/><path d="M11.6 16.8a3 3 0 11-5.8-1.6" stroke-width="1.8"/>'},
  {id:'automacoes',  href:'automacoes.html',  label:'Automações',  ready:true , icon:'<polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" stroke-width="1.8"/>'},
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
  // Pílula do cronômetro na topbar (só nas páginas que carregam timer.js)
  if(typeof initTimer === 'function') initTimer();
}

// ──────────── HELPERS ────────────
// As funcoes puras (escapeHtml, fmtDate, fmtMoney, fmtDuration, showToast,
// openModal/closeModal...) vivem em assets/helpers.js, carregado ANTES
// deste arquivo em todas as paginas. Aqui ficam so as que precisam do sb.

// ──────────── CONFIGURAÇÕES (app_settings) ────────────
async function getSetting(key){
  const {data} = await sb.from('app_settings').select('value').eq('key',key).maybeSingle();
  return data?.value || null;
}
async function setSetting(key,value){
  return sb.from('app_settings').upsert({key, value, updated_at:new Date().toISOString()});
}


// Fecha modal clicando fora
window.addEventListener('DOMContentLoaded',()=>{
  document.querySelectorAll('.overlay').forEach(o=>{
    o.addEventListener('click',e=>{if(e.target===o)o.classList.remove('open')});
  });
});
