/* Eventi personali nel calendario (tabella personal_commitments) + sincronizzazione con Google Calendar.
   Caricato dopo lo script di dashboard.html: usa le sue variabili globali (sb, user, shifts, cursor, view, ...). */
(function(){
"use strict";
let events=[];
const TZ="Europe/Rome";
const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const p2=n=>String(n).padStart(2,"0");
const dkey=d=>d.getFullYear()+"-"+p2(d.getMonth()+1)+"-"+p2(d.getDate());
const hhmm=d=>p2(d.getHours())+":"+p2(d.getMinutes());
const dayStart=k=>new Date(k+"T00:00:00");
const addDays=(d,n)=>{const x=new Date(d);x.setDate(x.getDate()+n);return x};

const css=document.createElement("style");
css.textContent=".evchip{display:block;width:100%;text-align:left;border:0;border-radius:6px;background:#e0ecff;color:#1457b8;font-size:11px;font-weight:700;padding:2px 5px;margin-top:2px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;cursor:pointer;line-height:1.3}.evchip.g{background:#fdf1d6;color:#8a5a00}.evchip:before{content:'● ';font-size:8px}.evlist{margin-top:14px}.evlist h3{margin:0 0 6px;font-size:15px}.evitem{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:10px 0;border-top:1px solid var(--line)}.evitem small{display:block;color:var(--muted)}#evDlg{border:0;border-radius:18px;padding:22px;width:min(92vw,440px);box-shadow:0 24px 80px #102b4e35}#evDlg::backdrop{background:#0b1f3d77}#evDlg .field{margin-bottom:10px}#evDlg .field label{display:block;font-weight:700;font-size:13px;margin-bottom:4px}#evDlg input[type=text],#evDlg input[type=date],#evDlg input[type=time],#evDlg textarea{width:100%;padding:10px;border:1px solid #cfdbe8;border-radius:9px;font:inherit}#evDlg .two{display:grid;grid-template-columns:1fr 1fr;gap:10px}#evDlg .acts{display:flex;gap:8px;flex-wrap:wrap;margin-top:14px}#evDlg .acts .btn{flex:1;justify-content:center;text-align:center}#evDlg .danger{color:#b42318}";
document.head.appendChild(css);

async function loadEvents(){
 try{
  const from=new Date(cursor.getFullYear(),0,1).toISOString(),to=new Date(cursor.getFullYear()+1,0,1).toISOString();
  const {data,error}=await sb.from("personal_commitments").select("*").eq("user_id",user.id).is("deleted_at",null).gte("ends_at",from).lt("starts_at",to).order("starts_at");
  events=error?[]:(data||[]);
 }catch(_){events=[]}
}
function eventsOn(key){
 const a=dayStart(key),b=addDays(a,1);
 return events.filter(e=>new Date(e.starts_at)<b&&new Date(e.ends_at)>a);
}
function timeLabel(e,key){
 if(e.all_day)return "Tutto il giorno";
 const s=new Date(e.starts_at),en=new Date(e.ends_at);
 return dkey(s)===key?hhmm(s)+(dkey(en)===key?"–"+hhmm(en):""):"Continua";
}
const chip=(e,key)=>'<button type="button" class="evchip'+(e.source==="google"?" g":"")+'" data-ev="'+esc(e.id)+'" title="'+esc(e.title+" · "+timeLabel(e,key))+'">'+(e.all_day?"":esc(hhmm(new Date(e.starts_at)))+" ")+esc(e.title)+'</button>';

function ensureDlg(){
 let d=document.getElementById("evDlg");
 if(!d){d=document.createElement("dialog");d.id="evDlg";document.body.appendChild(d)}
 return d;
}
function openEv(e,date){
 const d=ensureDlg(),ro=e&&e.source==="google";
 const s=e?new Date(e.starts_at):null,en=e?new Date(e.ends_at):null;
 const allDay=e?e.all_day:false;
 const sd=e?dkey(s):(date||dkey(new Date()));
 const ed=e?(allDay?dkey(addDays(en,-1)):dkey(en)):sd;
 d.innerHTML='<form method="dialog" id="evForm"><h2 style="margin:0 0 12px">'+(e?(ro?"Evento da Google":"Modifica evento"):"Nuovo evento personale")+'</h2>'
  +'<div class="field"><label for="evTitle">Titolo</label><input id="evTitle" type="text" maxlength="200" required value="'+esc(e?e.title:"")+'"'+(ro?" disabled":"")+'></div>'
  +'<label style="display:flex;gap:8px;align-items:center;margin:0 0 10px;font-weight:600"><input type="checkbox" id="evAll"'+(allDay?" checked":"")+(ro?" disabled":"")+'> Tutto il giorno</label>'
  +'<div class="two"><div class="field"><label for="evSd">Dal</label><input id="evSd" type="date" required value="'+sd+'"'+(ro?" disabled":"")+'></div><div class="field"><label for="evEd">Al</label><input id="evEd" type="date" required value="'+ed+'"'+(ro?" disabled":"")+'></div></div>'
  +'<div class="two" id="evTimes"><div class="field"><label for="evSt">Dalle</label><input id="evSt" type="time" value="'+(e&&!allDay?hhmm(s):"09:00")+'"'+(ro?" disabled":"")+'></div><div class="field"><label for="evEt">Alle</label><input id="evEt" type="time" value="'+(e&&!allDay?hhmm(en):"10:00")+'"'+(ro?" disabled":"")+'></div></div>'
  +'<div class="field"><label for="evLoc">Luogo (facoltativo)</label><input id="evLoc" type="text" maxlength="200" value="'+esc(e?.location||"")+'"'+(ro?" disabled":"")+'></div>'
  +'<div class="field"><label for="evDesc">Note (facoltative)</label><textarea id="evDesc" rows="2" maxlength="1000"'+(ro?" disabled":"")+'>'+esc(e?.description||"")+'</textarea></div>'
  +'<div id="evErr" class="muted" style="color:#b42318;min-height:18px" aria-live="polite"></div>'
  +'<div class="acts">'+(ro?'':'<button class="btn" id="evSave" type="button">Salva</button>')+(e?'<button class="btn secondary danger" id="evDel" type="button">'+(ro?"Nascondi":"Elimina")+'</button>':'')+'<button class="btn secondary" id="evX" type="button">Chiudi</button></div></form>';
 const tg=()=>{document.getElementById("evTimes").style.display=document.getElementById("evAll").checked?"none":"grid"};
 document.getElementById("evAll").onchange=tg;tg();
 const sdI=document.getElementById("evSd"),edI=document.getElementById("evEd");
 sdI.onchange=()=>{if(edI.value<sdI.value)edI.value=sdI.value};
 document.getElementById("evX").onclick=()=>d.close();
 const err=t=>{document.getElementById("evErr").textContent=t};
 const sv=document.getElementById("evSave");
 if(sv)sv.onclick=async()=>{
  const title=document.getElementById("evTitle").value.trim();if(!title){err("Scrivi un titolo.");return}
  const all=document.getElementById("evAll").checked,a=sdI.value,b=edI.value;if(!a||!b||b<a){err("Controlla le date.");return}
  let st,en;
  if(all){st=dayStart(a);en=addDays(dayStart(b),1)}
  else{st=new Date(a+"T"+(document.getElementById("evSt").value||"09:00")+":00");en=new Date(b+"T"+(document.getElementById("evEt").value||"10:00")+":00")}
  if(!(en>st)){err("L'orario di fine deve essere dopo l'inizio.");return}
  const row={title,description:document.getElementById("evDesc").value.trim()||null,location:document.getElementById("evLoc").value.trim()||null,starts_at:st.toISOString(),ends_at:en.toISOString(),all_day:all,updated_at:new Date().toISOString()};
  sv.disabled=true;
  const r=e?await sb.from("personal_commitments").update(row).eq("id",e.id).eq("user_id",user.id):await sb.from("personal_commitments").insert({...row,user_id:user.id,source:"nanoshift"});
  if(r.error){err("Non salvato: "+r.error.message);sv.disabled=false;return}
  d.close();await loadEvents();drawCalendar();
 };
 const del=document.getElementById("evDel");
 if(del)del.onclick=async()=>{
  if(!confirm(ro?"Nascondere questo evento dal calendario?":"Eliminare questo evento?"))return;
  const r=ro?await sb.from("personal_commitments").update({deleted_at:new Date().toISOString()}).eq("id",e.id).eq("user_id",user.id):await sb.from("personal_commitments").delete().eq("id",e.id).eq("user_id",user.id);
  if(r.error){err("Non riuscito: "+r.error.message);return}
  d.close();await loadEvents();drawCalendar();
 };
 d.showModal();
}

function decorate(){
 if(selectedCalendar!=="self")return;
 const host=document.getElementById("calendar");if(!host)return;
 const gs=document.getElementById("googleSync");
 if(gs&&!document.getElementById("addEvent")){
  gs.insertAdjacentHTML("beforebegin",'<button type="button" class="btn secondary" id="addEvent">＋ Evento personale</button>');
  document.getElementById("addEvent").onclick=()=>openEv(null,dkey(view==="week"?new Date(cursor):new Date()));
 }
 host.querySelectorAll(".day[data-date],.week-day[data-date]").forEach(el=>{
  const k=el.dataset.date;eventsOn(k).forEach(e=>el.insertAdjacentHTML("beforeend",chip(e,k)));
 });
 if(view==="list"){
  const y=cursor.getFullYear(),m=cursor.getMonth(),a=new Date(y,m,1),b=new Date(y,m+1,1);
  const list=events.filter(e=>new Date(e.starts_at)<b&&new Date(e.ends_at)>a).sort((x,z)=>new Date(x.starts_at)-new Date(z.starts_at));
  if(list.length)host.insertAdjacentHTML("beforeend",'<div class="evlist"><h3>Eventi personali</h3>'+list.map(e=>{const s=new Date(e.starts_at);return '<div class="evitem"><div><b>'+esc(e.title)+'</b><small>'+s.toLocaleDateString("it-IT",{weekday:"short",day:"numeric",month:"short"})+' · '+(e.all_day?"Tutto il giorno":hhmm(s)+"–"+hhmm(new Date(e.ends_at)))+(e.location?" · "+esc(e.location):"")+(e.source==="google"?" · Google":"")+'</small></div><button type="button" class="btn secondary" data-ev="'+esc(e.id)+'">'+(e.source==="google"?"Apri":"Modifica")+'</button></div>'}).join("")+'</div>');
 }
 host.querySelectorAll("[data-ev]").forEach(b=>b.onclick=ev=>{ev.stopPropagation();const e=events.find(x=>x.id===b.dataset.ev);if(e)openEv(e)});
}

// --- agganci alle funzioni dello script principale ---
const _draw=drawCalendar;
drawCalendar=function(){_draw();decorate()};
const _load=load;
load=async function(){await loadEvents();return _load.apply(this,arguments)};
const _day=showDayDialog;
showDayDialog=function(date){
 _day(date);
 if(selectedCalendar!=="self")return;
 const box=document.getElementById("dayDialogContent");if(!box)return;
 const arr=eventsOn(date);
 box.insertAdjacentHTML("beforeend",'<div class="evlist"><h3>Eventi personali</h3>'+(arr.map(e=>'<div class="evitem"><div><b>'+esc(e.title)+'</b><small>'+esc(timeLabel(e,date))+(e.location?" · "+esc(e.location):"")+(e.source==="google"?" · Google":"")+'</small></div><button type="button" class="btn secondary" data-dev="'+esc(e.id)+'">'+(e.source==="google"?"Apri":"Modifica")+'</button></div>').join("")||'<p class="muted" style="margin:0">Nessun evento.</p>')+'<button type="button" class="btn secondary" id="dayAddEv" style="margin-top:8px;width:100%;justify-content:center">＋ Aggiungi evento</button></div>');
 box.querySelectorAll("[data-dev]").forEach(b=>b.onclick=()=>{document.getElementById("dayDialog").close();const e=events.find(x=>x.id===b.dataset.dev);if(e)openEv(e)});
 document.getElementById("dayAddEv").onclick=()=>{document.getElementById("dayDialog").close();openEv(null,date)};
};

// --- Google Calendar: turni + eventi (invio) e importazione degli eventi di Google ---
syncGoogleCalendar=async function(){
 const button=document.getElementById("googleSync"),status=document.getElementById("status");
 const say=t=>{if(status)status.textContent=t};
 if(selectedCalendar!=="self"){say("Seleziona “Il mio calendario” per sincronizzare.");return}
 if(!user||!shifts){say("Calendario non ancora caricato.");return}
 const y=cursor.getFullYear(),m=cursor.getMonth(),month=y+"-"+p2(m+1);
 const first=new Date(y,m,1),next=new Date(y,m+1,1);
 const monthShifts=shifts.filter(s=>s.user_id===user.id&&s.shift_date.startsWith(month));
 const monthEvents=events.filter(e=>e.source==="nanoshift"&&new Date(e.starts_at)<next&&new Date(e.ends_at)>first);
 if(button){button.disabled=true;const sp=button.querySelector("span");if(sp)sp.textContent="Sincronizzazione…"}
 say("Collegamento a Google Calendar…");
 try{
  const token=await requestGoogleAccessToken();
  const listAll=async extra=>{const q=new URLSearchParams({timeMin:first.toISOString(),timeMax:next.toISOString(),singleEvents:"true",maxResults:"2500",...extra});let pt=null,out=[];do{if(pt)q.set("pageToken",pt);const page=await googleCalendarRequest("/calendars/primary/events?"+q.toString(),token);out.push(...(page.items||[]));pt=page.nextPageToken||null}while(pt);return out};
  const mine=await listAll({privateExtendedProperty:"nanoshiftSource=NaNoShift"});
  const byShift=new Map(mine.filter(e=>e.extendedProperties?.private?.nanoshiftShiftId).map(e=>[e.extendedProperties.private.nanoshiftShiftId,e]));
  const byEv=new Map(mine.filter(e=>e.extendedProperties?.private?.nanoshiftEventId).map(e=>[e.extendedProperties.private.nanoshiftEventId,e]));
  const activeShift=new Set(monthShifts.map(s=>String(s.id))),activeEv=new Set(monthEvents.map(e=>e.id));
  let created=0,updated=0,deleted=0;
  for(const shift of monthShifts){
   const id=String(shift.id),label=types[shift.code]?.label||"Turno";
   const event={summary:(shift.code||"")+" · "+label+" — NaNoShift",extendedProperties:{private:{nanoshiftSource:"NaNoShift",nanoshiftShiftId:id}}};
   if(shift.code==="R"){const end=new Date(shift.shift_date+"T12:00:00");end.setDate(end.getDate()+1);event.start={date:shift.shift_date};event.end={date:fmtDate(end)}}
   else{event.start={dateTime:shift.shift_date+"T"+shift.start_time.slice(0,5)+":00",timeZone:TZ};event.end={dateTime:shiftEndDate(shift)+"T"+shift.end_time.slice(0,5)+":00",timeZone:TZ}}
   const prior=byShift.get(id);
   if(prior){await googleCalendarRequest("/calendars/primary/events/"+encodeURIComponent(prior.id),token,{method:"PATCH",body:JSON.stringify(event)});updated++}
   else{await googleCalendarRequest("/calendars/primary/events",token,{method:"POST",body:JSON.stringify({...event,id:"nanoshift"+id.replace(/-/g,"").toLowerCase()})});created++}
  }
  for(const e of monthEvents){
   const body={summary:e.title,description:e.description||undefined,location:e.location||undefined,extendedProperties:{private:{nanoshiftSource:"NaNoShift",nanoshiftEventId:e.id}}};
   const s=new Date(e.starts_at),en=new Date(e.ends_at);
   if(e.all_day){body.start={date:dkey(s)};body.end={date:dkey(en)}}
   else{body.start={dateTime:s.toISOString()};body.end={dateTime:en.toISOString()}}
   const prior=byEv.get(e.id);
   if(prior){await googleCalendarRequest("/calendars/primary/events/"+encodeURIComponent(prior.id),token,{method:"PATCH",body:JSON.stringify(body)});updated++}
   else{await googleCalendarRequest("/calendars/primary/events",token,{method:"POST",body:JSON.stringify({...body,id:"nanoshiftev"+e.id.replace(/-/g,"").toLowerCase()})});created++}
  }
  for(const g of mine){
   const sid=g.extendedProperties?.private?.nanoshiftShiftId,eid=g.extendedProperties?.private?.nanoshiftEventId;
   if((sid&&!activeShift.has(sid))||(eid&&!activeEv.has(eid))){await googleCalendarRequest("/calendars/primary/events/"+encodeURIComponent(g.id),token,{method:"DELETE"}).catch(()=>null);deleted++}
  }
  // importa gli eventi creati direttamente su Google (non quelli di NaNoShift)
  const all=await listAll({});
  const foreign=all.filter(g=>g.status!=="cancelled"&&!g.extendedProperties?.private?.nanoshiftSource&&g.id);
  let imported=0,refreshed=0;
  if(foreign.length){
   const ids=foreign.map(g=>g.id);
   const {data:have}=await sb.from("personal_commitments").select("id,google_event_id,google_etag,deleted_at").eq("user_id",user.id).eq("source","google").in("google_event_id",ids);
   const haveBy=new Map((have||[]).map(r=>[r.google_event_id,r]));
   const toIns=[];
   for(const g of foreign){
    const allDay=!!g.start?.date;
    const st=allDay?dayStart(g.start.date):new Date(g.start?.dateTime),en=allDay?dayStart(g.end?.date||g.start.date):new Date(g.end?.dateTime);
    if(isNaN(st)||isNaN(en)||!(en>st))continue;
    const row={title:String(g.summary||"(Senza titolo)").slice(0,200),description:g.description?String(g.description).slice(0,1000):null,location:g.location?String(g.location).slice(0,200):null,starts_at:st.toISOString(),ends_at:en.toISOString(),all_day:allDay,google_etag:g.etag||null,google_updated_at:g.updated||null,updated_at:new Date().toISOString()};
    const prev=haveBy.get(g.id);
    if(!prev)toIns.push({...row,user_id:user.id,source:"google",google_calendar_id:"primary",google_event_id:g.id});
    else if(!prev.deleted_at&&prev.google_etag!==g.etag){const r=await sb.from("personal_commitments").update(row).eq("id",prev.id).eq("user_id",user.id);if(!r.error)refreshed++}
   }
   if(toIns.length){const r=await sb.from("personal_commitments").insert(toIns);if(r.error)throw new Error("Importazione eventi: "+r.error.message);imported=toIns.length}
  }
  await loadEvents();drawCalendar();
  say("Google Calendar aggiornato: "+created+" inviati, "+updated+" aggiornati"+(deleted?", "+deleted+" rimossi":"")+". Importati da Google: "+imported+(refreshed?" (+"+refreshed+" aggiornati)":"")+".");
 }catch(error){say("Sincronizzazione non completata: "+(error?.message||"errore sconosciuto"))}
 finally{if(button){button.disabled=selectedCalendar!=="self";const sp=button.querySelector("span");if(sp)sp.textContent="Sincronizza con Google"}}
};
})();
