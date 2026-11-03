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
  d.close();await loadEvents();drawCalendar();window.NaNoGoogleKick&&window.NaNoGoogleKick();
 };
 const del=document.getElementById("evDel");
 if(del)del.onclick=async()=>{
  if(!confirm(ro?"Nascondere questo evento dal calendario?":"Eliminare questo evento?"))return;
  const r=await sb.from("personal_commitments").update({deleted_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq("id",e.id).eq("user_id",user.id);
  if(r.error){err("Non riuscito: "+r.error.message);return}
  d.close();await loadEvents();drawCalendar();window.NaNoGoogleKick&&window.NaNoGoogleKick();
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

// --- Google Calendar: sincronizzazione automatica bidirezionale (server) ---
let gState=null,gTimer=null,gBusy=false;
const gcall=async(action)=>{const r=await sb.functions.invoke("nanoshift-google",{body:{action}});if(r.error){let m=r.error.message;try{const j=await r.error.context.json();if(j&&j.error)m=j.error}catch(_){}throw new Error(m)}return r.data||{}};
const gLabel=()=>{const sp=document.querySelector("#googleSync span");if(!sp)return;sp.textContent=gBusy?"Sincronizzazione…":(gState&&gState.connected?"Google collegato · Sincronizza":"Collega Google Calendar")};
async function gSync(silent){
 if(gBusy||!gState||!gState.connected)return;
 const status=document.getElementById("status");gBusy=true;gLabel();
 try{
  const r=await gcall("sync");await loadEvents();drawCalendar();
  gState.last_sync_at=new Date().toISOString();gState.last_error=null;
  if(!silent&&status)status.textContent="Google Calendar aggiornato ("+(r.pushed||0)+" inviati, "+(r.pulled||0)+" ricevuti, "+(r.deleted||0)+" rimossi).";
 }catch(e){if(status)status.textContent="Sincronizzazione Google non riuscita: "+(e.message||"errore");gState.last_error=e.message}
 finally{gBusy=false;gLabel()}
}
// dopo ogni modifica/aggiunta di eventi: sincronizza (con breve attesa per raggruppare i salvataggi)
window.NaNoGoogleKick=()=>{if(!gState||!gState.connected)return;clearTimeout(gTimer);gTimer=setTimeout(()=>gSync(true),1500)};
async function gInit(){
 try{gState=await gcall("status")}catch(_){gState=null}
 gLabel();
 const q=new URLSearchParams(location.search),st=q.get("google");
 const status=document.getElementById("status");
 if(st){
  history.replaceState(null,"",location.pathname+"?area=personale");
  if(status)status.textContent=st==="collegato"?"Google Calendar collegato: sincronizzo…":st==="annullato"?"Collegamento a Google annullato.":"Collegamento a Google non riuscito. Riprova.";
  if(st==="collegato"){try{gState=await gcall("status")}catch(_){}await gSync(false);return}
 }
 // all'apertura: aggiorna se l'ultima sincronizzazione ha più di 10 minuti
 if(gState&&gState.connected&&(!gState.last_sync_at||Date.now()-new Date(gState.last_sync_at).getTime()>600000))gSync(true);
}
syncGoogleCalendar=async function(){
 const status=document.getElementById("status");
 if(selectedCalendar!=="self"){if(status)status.textContent="Seleziona “Il mio calendario” per sincronizzare.";return}
 try{
  if(!gState)gState=await gcall("status");
  if(!gState.connected){
   if(!gState.configured){if(status)status.textContent="Il collegamento a Google non è ancora attivo sul server.";return}
   if(status)status.textContent="Apro Google per il consenso…";
   const r=await gcall("connect_url");if(r.url)location.href=r.url;return;
  }
  await gSync(false);
 }catch(e){if(status)status.textContent="Google Calendar: "+(e.message||"errore")}
};
function gDisconnectLink(){
 const status=document.getElementById("status");if(!status||document.getElementById("gOff")||!gState||!gState.connected)return;
 status.insertAdjacentHTML("afterend",'<div class="muted" id="gOff" style="font-size:.85rem">Sincronizzazione automatica con Google'+(gState.email?" ("+esc(gState.email)+")":"")+' attiva: ad ogni modifica e 3 volte al giorno. <button type="button" class="btn secondary" id="gOffBtn" style="padding:2px 10px;min-height:0">Scollega</button></div>');
 document.getElementById("gOffBtn").onclick=async()=>{if(!confirm("Scollegare Google Calendar? Gli eventi già presenti restano dove sono."))return;try{await gcall("disconnect");gState={configured:true,connected:false};document.getElementById("gOff").remove();gLabel()}catch(e){alert(e.message)}};
}
const _dec=decorate;decorate=function(){_dec();gLabel();gDisconnectLink()};
document.addEventListener("DOMContentLoaded",()=>setTimeout(gInit,800));
})();
