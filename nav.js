/* NaNoShift · menu condiviso da dashboard, reparto e coordinamento.
   Voci, icone, ordine personalizzabile (feature_preferences.nav_order) e visibilità (toggle) sono definiti qui una volta sola. */
(function(){
 const svg=p=>'<svg viewBox="0 0 24 24" aria-hidden="true">'+p+'</svg>';
 const ITEMS=[
  {id:"overview",label:"Riepilogo",section:"overviewView",icon:svg('<rect x="3" y="3" width="8" height="9" rx="2"/><rect x="13" y="3" width="8" height="5" rx="2"/><rect x="13" y="12" width="8" height="9" rx="2"/><rect x="3" y="16" width="8" height="5" rx="2"/>')},
  {id:"calendar",label:"Calendario",section:"calendarView",icon:svg('<rect x="3" y="4.5" width="18" height="16.5" rx="3"/><path d="M16 2.5v4M8 2.5v4M3 10h18"/><circle cx="8" cy="14" r=".6"/><circle cx="12" cy="14" r=".6"/><circle cx="16" cy="14" r=".6"/><circle cx="8" cy="17.5" r=".6"/><circle cx="12" cy="17.5" r=".6"/>')},
  {id:"groups",label:"Gruppi",section:"groupsView",pref:"groups",icon:svg('<circle cx="9" cy="8" r="3.2"/><path d="M2.8 20v-1.5A5.5 5.5 0 0 1 8.3 13h1.4a5.5 5.5 0 0 1 5.5 5.5V20"/><path d="M16 4.9a3.2 3.2 0 0 1 0 6.2M18.5 13.4a5.5 5.5 0 0 1 2.7 5.1V20"/>')},
  {id:"ward",label:"Reparto",href:"reparto.html",pref:"ward",icon:svg('<rect x="3.5" y="3.5" width="17" height="17" rx="4"/><path d="M12 8v8M8 12h8"/>')},
  {id:"coord",label:"Coordina",href:"coordinamento.html",coordOnly:true,icon:svg('<path d="M3 20V9l9-5 9 5v11"/><path d="M9 20v-6h6v6"/>')},
  {id:"list",label:"Elenco turni",section:"listView",pref:"list_view",icon:svg('<path d="M8 6h13M8 12h13M8 18h13"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/>')},
  {id:"sites",label:"Sedi e modelli",section:"sitesView",pref:"work_sites",icon:svg('<path d="M4 21V6.5L12 3l8 3.5V21M2.5 21h19"/><path d="M9 21v-4.5h6V21M8.5 9.5h1.5M14 9.5h1.5M8.5 13h1.5M14 13h1.5"/>')},
  {id:"tax",label:"Simulatore",section:"taxView",pref:"tax_simulator",notEmployee:true,icon:svg('<rect x="4.5" y="2.5" width="15" height="19" rx="3"/><path d="M8 7h8M8.5 12h.01M12 12h.01M15.5 12h.01M8.5 16h.01M12 16h.01M15.5 16h.01"/>')},
  {id:"docs",label:"Documenti",href:"professional.html",pref:"documents",icon:svg('<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 13h6M9 17h6"/>')},
  {id:"cvs",label:"CV condivisi",href:"cv-condivisi.html",coordOnly:true,icon:svg('<rect x="3" y="5" width="18" height="14" rx="3"/><circle cx="9" cy="11" r="2"/><path d="M6.5 16c.5-1.5 1.5-2 2.5-2s2 .5 2.5 2M14 10h4M14 14h4"/>')},
  {id:"users",label:"Utenti",href:"admin.html",adminOnly:true,icon:svg('<path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z"/><circle cx="12" cy="10" r="2.2"/><path d="M8.5 16.5c.8-1.6 2-2.3 3.5-2.3s2.7.7 3.5 2.3"/>')},
  {id:"profile",label:"Dati utente",section:"profileView",icon:svg('<circle cx="12" cy="8" r="4"/><path d="M4.5 21a7.5 7.5 0 0 1 15 0"/>')}
 ];
 const DEFAULT=["overview","calendar","groups","ward","coord","list","sites","tax","docs","cvs","users","profile"];
 const DEFAULT_COORD=["coord","ward","cvs","overview","calendar","groups","list","sites","tax","docs","users","profile"];
 const PRIMARY=4;
 const byId=Object.fromEntries(ITEMS.map(i=>[i.id,i]));
 // Pagina corrente → voce di menu evidenziata (le pagine "intere" non sono sezioni della dashboard).
 const PAGE_IDS={reparto:"ward",coordinamento:"coord",professional:"docs",cvs:"cvs",admin:"users"};

 // Una voce è disponibile per questa persona (ruolo e tipo di impiego), indipendentemente dai toggle.
 const available=(it,ctx)=>!(it.coordOnly&&!ctx.isCoord)&&!(it.adminOnly&&!ctx.isAdmin)&&!(it.notEmployee&&ctx.employee);
 const enabled=(it,prefs)=>!it.pref||(prefs||{})[it.pref]!==false;
 const visible=(it,prefs,ctx)=>available(it,ctx)&&enabled(it,prefs);

 function order(prefs,ctx){
  const base=ctx.isCoord?DEFAULT_COORD:DEFAULT;
  const saved=Array.isArray((prefs||{}).nav_order)?prefs.nav_order.filter(id=>byId[id]):[];
  const seen=new Set(saved);
  return [...saved,...base.filter(id=>!seen.has(id))].map(id=>byId[id]);
 }
 const ordered=(prefs,ctx)=>order(prefs,ctx).filter(it=>available(it,ctx));
 const visibleItems=(prefs,ctx)=>order(prefs,ctx).filter(it=>visible(it,prefs,ctx));

 const esc=s=>String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));

 // container: elemento <nav class="side-nav">; page: dashboard | reparto | coordinamento
 function render(o){
  const nav=o.container,ctx=o.ctx||{},prefs=o.prefs||{},page=o.page;
  document.body.classList.add("has-nav");
  const items=visibleItems(prefs,ctx);
  const activeId=page==="dashboard"?(items.find(i=>i.section===o.active)||{}).id:(PAGE_IDS[page]||null);
  const btn=it=>{
   const target=it.section?(page==="dashboard"?'data-section="'+it.section+'"':'data-href="dashboard.html?area=personale&section='+it.section+'"'):'data-href="'+it.href+'"';
   return '<button type="button" '+target+' class="'+(it.id===activeId?"active":"")+'"'+(it.id===activeId?' aria-current="page"':"")+'>'+it.icon+'<span>'+esc(it.label)+'</span></button>';
  };
  const main=items.length>PRIMARY+1?items.slice(0,PRIMARY):items,more=items.length>PRIMARY+1?items.slice(PRIMARY):[];
  nav.innerHTML='<div class="side-brand" role="link" tabindex="0" aria-label="Vai alla pagina iniziale"><img src="favicon-192.png" alt="" width="38" height="38"><span class="sb-name">NaNo<span>Shift</span></span></div>'
   +main.map(btn).join("")
   +(more.length?'<button type="button" class="nav-more-btn'+(more.some(i=>i.id===activeId)?" active":"")+'" aria-expanded="false" aria-controls="navMore"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5.5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="18.5" cy="12" r="1.3"/></svg><span>Altro</span></button><div class="nav-more" id="navMore">'+more.map(btn).join("")+'</div>':"");
  const acc=o.account;
  if(acc){
   nav.insertAdjacentHTML("beforeend",'<div class="side-account"><button type="button" class="side-account-btn" aria-haspopup="menu" aria-expanded="false"><span class="sa-avatar">'+(acc.avatar?'<img src="'+esc(acc.avatar)+'" alt="">':esc(String(acc.name||"?").trim().charAt(0).toUpperCase()))+'</span><span class="sa-name">'+esc(acc.name||"Account")+'</span></button><div class="side-account-menu" role="menu" hidden><button type="button" role="menuitem" data-acc="profile">Dati utente</button><button type="button" role="menuitem" data-acc="logout" class="logout-menu-item">Esci</button></div></div>');
   const ab=nav.querySelector(".side-account-btn"),am=nav.querySelector(".side-account-menu");
   ab.onclick=e=>{e.stopPropagation();am.hidden=!am.hidden;ab.setAttribute("aria-expanded",String(!am.hidden))};
   am.querySelector('[data-acc="profile"]').onclick=()=>{am.hidden=true;if(page==="dashboard")o.onSection("profileView");else location.href="dashboard.html?area=personale&section=profileView"};
   am.querySelector('[data-acc="logout"]').onclick=()=>acc.onLogout&&acc.onLogout();
  }
  nav.querySelectorAll("[data-section]").forEach(b=>b.onclick=()=>{nav.classList.remove("more-open");o.onSection&&o.onSection(b.dataset.section)});
  nav.querySelectorAll("[data-href]").forEach(b=>b.onclick=()=>{location.href=b.dataset.href});
  const mb=nav.querySelector(".nav-more-btn");
  if(mb)mb.onclick=e=>{e.stopPropagation();const open=nav.classList.toggle("more-open");mb.setAttribute("aria-expanded",String(open))};
  const brand=nav.querySelector(".side-brand"),home=()=>{location.href=ctx.isCoord?"coordinamento.html":"dashboard.html?area=personale"};
  brand.onclick=home;brand.onkeydown=e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();home()}};
  if(!window.__navGlobalBound){
   window.__navGlobalBound=true;
   document.addEventListener("click",e=>{const am=document.querySelector(".side-account-menu");if(am&&!e.target.closest(".side-account")){am.hidden=true;const b=document.querySelector(".side-account-btn");if(b)b.setAttribute("aria-expanded","false")}const n=document.querySelector(".side-nav");if(n&&!e.target.closest(".nav-more")&&!e.target.closest(".nav-more-btn")){n.classList.remove("more-open");const b=n.querySelector(".nav-more-btn");if(b)b.setAttribute("aria-expanded","false")}});
   document.addEventListener("keydown",e=>{if(e.key==="Escape"){const n=document.querySelector(".side-nav");if(n)n.classList.remove("more-open")}});
  }
 }

 // Contesto per le pagine che non caricano già il profilo (reparto, coordinamento).
 async function loadContext(sb,user){
  const [p,u]=await Promise.all([
   sb.from("profiles").select("display_name,first_name,avatar_url,employment_type,feature_preferences,role").eq("id",user.id).single(),
   sb.rpc("get_my_units")
  ]);
  const profile=p.data||{},units=u.data||[];
  return {profile,prefs:profile.feature_preferences||{},ctx:{isCoord:units.some(m=>m.unit_role==="coordinator"&&m.status==="active"),isAdmin:profile.role==="admin",employee:profile.employment_type==="employee"}};
 }

 // Menu account nell'intestazione (pagine diverse dalla dashboard).
 function mountAccount(el,o){
  const name=(o.profile&&(o.profile.display_name||o.profile.first_name))||(o.user&&o.user.email)||"?";
  const av=o.profile&&o.profile.avatar_url;
  el.innerHTML='<div class="header-actions"><div class="account-menu-wrap"><button type="button" class="avatar-button" id="navAvatar" aria-haspopup="menu" aria-expanded="false" aria-label="Menu account">'+(av?'<img src="'+esc(av)+'" alt="">':esc(String(name).trim().charAt(0).toUpperCase()))+'</button><div class="account-menu" id="navAccountMenu" role="menu" hidden><button type="button" role="menuitem" data-go="dashboard.html?area=personale&section=profileView">Dati utente</button><button type="button" role="menuitem" class="logout-menu-item" data-logout>Esci</button></div></div></div>';
  const b=el.querySelector("#navAvatar"),m=el.querySelector("#navAccountMenu");
  b.onclick=e=>{e.stopPropagation();m.hidden=!m.hidden;b.setAttribute("aria-expanded",String(!m.hidden))};
  document.addEventListener("click",e=>{if(!e.target.closest(".account-menu-wrap")){m.hidden=true;b.setAttribute("aria-expanded","false")}});
  m.querySelectorAll("[data-go]").forEach(x=>x.onclick=()=>{location.href=x.dataset.go});
  m.querySelector("[data-logout]").onclick=async()=>{await o.sb.auth.signOut();location.href="accesso.html"};
 }

 // Editor dell'ordine (Dati utente): ↑ ↓ + ripristino. save(nextPrefs) → Promise.
 function mountOrderEditor(el,o){
  const draw=()=>{
   const prefs=o.getPrefs(),ctx=o.getCtx(),items=ordered(prefs,ctx);
   el.innerHTML='<ul class="nav-order">'+items.map((it,i)=>'<li data-id="'+it.id+'">'+it.icon+'<b>'+esc(it.label)+(enabled(it,prefs)?"":' <small>(nascosta)</small>')+'</b><span class="mv"><button type="button" data-d="-1" aria-label="Sposta su '+esc(it.label)+'"'+(i===0?" disabled":"")+'>↑</button><button type="button" data-d="1" aria-label="Sposta giù '+esc(it.label)+'"'+(i===items.length-1?" disabled":"")+'>↓</button></span></li>').join("")+'</ul><div style="margin-top:10px"><button type="button" class="btn secondary" data-reset>Ripristina ordine</button></div>';
   el.querySelectorAll("[data-d]").forEach(b=>b.onclick=async()=>{
    const id=b.closest("li").dataset.id,ids=items.map(i=>i.id),i=ids.indexOf(id),j=i+Number(b.dataset.d);
    if(j<0||j>=ids.length)return;
    [ids[i],ids[j]]=[ids[j],ids[i]];
    await o.save({...prefs,nav_order:ids});draw();
   });
   el.querySelector("[data-reset]").onclick=async()=>{const n={...prefs};delete n.nav_order;await o.save(n);draw()};
  };
  draw();
 }

 window.NanoNav={ITEMS,render,loadContext,mountAccount,mountOrderEditor,visibleItems,ordered,isVisible:(id,prefs,ctx)=>byId[id]?visible(byId[id],prefs,ctx):true,sectionToId:s=>(ITEMS.find(i=>i.section===s)||{}).id};
})();
