/* ════════════════════════════════════════════════════════════════════
   GCAL.JS — Leitura da Google Agenda pelo link iCal secreto

   Só LÊ o calendário. Quem cria reunião é o Cal.com (ou você mesma,
   direto no Google) — as reuniões confirmadas caem na sua agenda e
   aparecem aqui pelo mesmo iCal.

   O fetch passa pela função /api/gcal (Vercel) porque o Google não
   libera CORS para o navegador.

   Usado por: gestao.html (card de compromissos), agendamento.html.
   Depende de: shared.js (getSetting)
   ════════════════════════════════════════════════════════════════════ */

// ──────────── PARSER DE iCal (formato do Google) ────────────
function parseICS(text){
  const lines = text.replace(/\r\n[ \t]/g,'').replace(/\r/g,'').split('\n');
  const out = []; let cur = null;
  for(const line of lines){
    if(line==='BEGIN:VEVENT'){cur={};continue}
    if(line==='END:VEVENT'){if(cur)out.push(cur);cur=null;continue}
    if(!cur)continue;
    const i = line.indexOf(':');
    if(i<0)continue;
    const key = line.slice(0,i), val = line.slice(i+1);
    const name = key.split(';')[0];
    if(name==='DTSTART'){cur.start=parseICSDate(val);cur.allDay=/^\d{8}$/.test(val)}
    else if(name==='DTEND'){cur.end=parseICSDate(val)}
    else if(name==='SUMMARY'){cur.title=val.replace(/\\,/g,',').replace(/\\;/g,';').replace(/\\n/g,' ')}
    else if(name==='LOCATION'){cur.location=val.replace(/\\,/g,',')}
    else if(name==='RRULE'){cur.rrule=val}
    else if(name==='EXDATE'){(cur.exdates=cur.exdates||[]).push(...val.split(',').map(parseICSDate).filter(Boolean))}
    else if(name==='STATUS'&&val==='CANCELLED'){cur.cancelled=true}
  }
  return out;
}

function parseICSDate(v){
  const m = String(v).match(/(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?/);
  if(!m) return null;
  if(m[7]) return new Date(Date.UTC(+m[1],+m[2]-1,+m[3],+m[4],+m[5],+m[6]));
  return new Date(+m[1],+m[2]-1,+m[3],+(m[4]||0),+(m[5]||0),+(m[6]||0));
}

// Expande recorrências (DAILY/WEEKLY/MONTHLY/YEARLY com INTERVAL, UNTIL,
// COUNT e BYDAY semanal). Devolve as datas dentro da janela pedida.
function expandOccurrences(ev, winStart, winEnd){
  if(!ev.rrule){
    return (ev.start>=winStart && ev.start<=winEnd) ? [ev.start] : [];
  }
  const R = Object.fromEntries(ev.rrule.split(';').map(p=>p.split('=')));
  const freq = R.FREQ;
  const interval = +(R.INTERVAL||1);
  const until = R.UNTIL ? parseICSDate(R.UNTIL) : null;
  const maxCount = R.COUNT ? +R.COUNT : Infinity;
  const dowMap = {SU:0,MO:1,TU:2,WE:3,TH:4,FR:5,SA:6};
  const bydays = (freq==='WEEKLY' && R.BYDAY) ? R.BYDAY.split(',').map(s=>dowMap[s.slice(-2)]).filter(x=>x!=null).sort() : null;
  const occ = [];
  let produced = 0, guard = 0;

  if(bydays){
    const weekStart = new Date(ev.start);
    weekStart.setDate(weekStart.getDate()-weekStart.getDay());
    outer: while(guard++<3000){
      for(const dow of bydays){
        const d = new Date(weekStart);
        d.setDate(d.getDate()+dow);
        d.setHours(ev.start.getHours(), ev.start.getMinutes(), 0, 0);
        if(d<ev.start) continue;
        if(until && d>until) break outer;
        if(produced>=maxCount) break outer;
        produced++;
        if(d>=winStart && d<=winEnd) occ.push(d);
        if(d>winEnd) break outer;
      }
      weekStart.setDate(weekStart.getDate()+7*interval);
    }
  } else {
    let d = new Date(ev.start);
    while(guard++<3000 && produced<maxCount){
      if(until && d>until) break;
      produced++;
      if(d>=winStart && d<=winEnd) occ.push(new Date(d));
      if(d>winEnd) break;
      if(freq==='DAILY') d.setDate(d.getDate()+interval);
      else if(freq==='WEEKLY') d.setDate(d.getDate()+7*interval);
      else if(freq==='MONTHLY') d.setMonth(d.getMonth()+interval);
      else if(freq==='YEARLY') d.setFullYear(d.getFullYear()+interval);
      else break;
    }
  }
  const ex = new Set((ev.exdates||[]).map(x=>x.getTime()));
  return occ.filter(d=>!ex.has(d.getTime()));
}

// Data local no formato YYYY-MM-DD (de propósito não usa toISOString,
// que converte pra UTC e erra o dia de quem está no Brasil).
function localDateStr(iso){
  const d = new Date(iso);
  return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
}

// ──────────── BUSCA PRINCIPAL ────────────
// Devolve os compromissos do Google já expandidos e ordenados.
// NUNCA lança e NUNCA trava a página: sem link configurado, offline ou
// com erro no Google, devolve lista vazia. Quem chama decide o que mostrar.
async function loadGcalOccurrences(diasAtras = 1, diasFrente = 30){
  const url = await getSetting('gcal_ics_url');
  if(!url) return [];
  try{
    const r = await fetch('/api/gcal?url='+encodeURIComponent(url));
    if(!r.ok) return [];
    const raw = parseICS(await r.text());
    const winStart = new Date(Date.now() - diasAtras*86400000);
    const winEnd   = new Date(Date.now() + diasFrente*86400000);
    const out = [];
    raw.forEach(ev=>{
      if(ev.cancelled || !ev.start || !ev.title) return;
      expandOccurrences(ev, winStart, winEnd).forEach(d=>{
        out.push({
          date: localDateStr(d),
          at: d,
          time: ev.allDay ? '' : d.toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'}),
          title: ev.title,
          location: ev.location||'',
          allDay: !!ev.allDay,
        });
      });
    });
    return out.sort((a,b)=>a.at-b.at);
  }catch(e){
    return [];
  }
}
