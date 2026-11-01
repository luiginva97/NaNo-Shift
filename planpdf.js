/* PDF orizzontale (A4) dei turni, generato nel browser senza librerie esterne.
   NanoPdf.plan({title,subtitle,days,rows,foot,legend,stamp,status}) -> Blob */
(function(){
 const MM=72/25.4;let W=297*MM,H=210*MM;
 const cv=document.createElement("canvas").getContext("2d");
 const widthOf=(t,size,bold)=>{cv.font=(bold?"bold ":"")+"100px Arial, Helvetica, sans-serif";return cv.measureText(t).width/100*size};
 const fix=t=>String(t==null?"":t).replace(/[–—]/g,"-").replace(/[·•]/g,"-").replace(/[“”]/g,'"').replace(/[‘’]/g,"'").replace(/[^\x20-\xFF]/g,"?");
 const esc=t=>fix(t).replace(/\\/g,"\\\\").replace(/\(/g,"\\(").replace(/\)/g,"\\)");
 const rgb=h=>{h=h.replace("#","");return [0,2,4].map(i=>(parseInt(h.substr(i,2),16)/255).toFixed(3)).join(" ")};
 function Page(){this.o=[]}
 Page.prototype={
  rect(x,y,w,h,fill,stroke,lw){ // y dall'alto in pt
   let s="";if(fill)s+=rgb(fill)+" rg ";if(stroke)s+=rgb(stroke)+" RG "+(lw||0.5)+" w ";
   s+=x.toFixed(2)+" "+(H-y-h).toFixed(2)+" "+w.toFixed(2)+" "+h.toFixed(2)+" re "+(fill&&stroke?"B":fill?"f":"S");this.o.push(s)},
  line(x1,y1,x2,y2,color,lw){this.o.push(rgb(color)+" RG "+lw+" w "+x1.toFixed(2)+" "+(H-y1).toFixed(2)+" m "+x2.toFixed(2)+" "+(H-y2).toFixed(2)+" l S")},
  text(t,x,y,size,bold,color,align,maxW){ // y = linea di base dall'alto
   t=fix(t);let w=widthOf(t,size,bold);
   if(maxW&&w>maxW){while(t.length>1&&widthOf(t+"...",size,bold)>maxW)t=t.slice(0,-1);t+="...";w=widthOf(t,size,bold)}
   if(align==="center")x=x-w/2;else if(align==="right")x=x-w;
   this.o.push("BT "+rgb(color||"#10284b")+" rg /"+(bold?"F2":"F1")+" "+size+" Tf "+x.toFixed(2)+" "+(H-y).toFixed(2)+" Td ("+esc(t)+") Tj ET")}
 };
 function build(pages){
  const objs=[];const add=s=>{objs.push(s);return objs.length};
  add("<< /Type /Catalog /Pages 2 0 R >>");add("");// 2 = Pages (riempito dopo)
  const f1=add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>");
  const f2=add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>");
  const kids=[];
  pages.forEach(p=>{
   const body=p.o.join("\n");
   const c=add("<< /Length "+body.length+" >>\nstream\n"+body+"\nendstream");
   const pg=add("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 "+W.toFixed(2)+" "+H.toFixed(2)+"] /Resources << /Font << /F1 "+f1+" 0 R /F2 "+f2+" 0 R >> >> /Contents "+c+" 0 R >>");
   kids.push(pg+" 0 R");
  });
  objs[1]="<< /Type /Pages /Kids ["+kids.join(" ")+"] /Count "+kids.length+" >>";
  let out="%PDF-1.4\n";const off=[];
  objs.forEach((o,i)=>{off.push(out.length);out+=(i+1)+" 0 obj\n"+o+"\nendobj\n"});
  const xr=out.length;
  out+="xref\n0 "+(objs.length+1)+"\n0000000000 65535 f \n"+off.map(n=>String(n).padStart(10,"0")+" 00000 n \n").join("")+"trailer\n<< /Size "+(objs.length+1)+" /Root 1 0 R >>\nstartxref\n"+xr+"\n%%EOF";
  const u=new Uint8Array(out.length);for(let i=0;i<out.length;i++)u[i]=out.charCodeAt(i)&255;
  return new Blob([u],{type:"application/pdf"});
 }
 const COL={M:"#c58a12",P:"#3478d4",G:"#13845b",N:"#7754c8",R:"#fff4bf"};
 function plan(o,orient){
  if(orient==="p")return planPortrait(o);
  W=297*MM;H=210*MM;
  const mx=8*MM,top=8*MM,bot=8*MM,usableW=W-2*mx;
  const nameW=48*MM,totW=16*MM,n=o.days.length,dayW=(usableW-nameW-totW)/n;
  const pages=[];let pg,y;
  const header=first=>{
   pg=new Page();pages.push(pg);y=top;
   if(first){
    pg.text(o.title,mx,y+17,19,true,"#10284b");
    pg.text(o.subtitle,mx,y+30,10,false,"#5b6b83");
    pg.text("NaNo",W-mx-widthOf("NaNoShift",14,true),y+17,14,true,"#0057b7");
    pg.text("Shift",W-mx-widthOf("Shift",14,true),y+17,14,true,"#e0a812");
    pg.rect(mx,y+36,usableW,3,"#0057b7");y+=46;
   }else{pg.text(o.title+" - "+o.subtitle,mx,y+10,10,true,"#5b6b83");y+=18}
   const hh=24;
   pg.rect(mx,y,nameW,hh,"#eaf0fb","#7f8da3",.6);pg.text("Persona",mx+6,y+15,9,true);
   o.days.forEach((d,i)=>{const x=mx+nameW+i*dayW;pg.rect(x,y,dayW,hh,d.we?"#fdecea":"#eaf0fb","#7f8da3",.6);
    pg.text(d.d,x+dayW/2,y+10,8,true,d.we?"#c0261b":"#10284b","center");pg.text(d.wd,x+dayW/2,y+20,7,true,d.we?"#c0261b":"#10284b","center")});
   pg.rect(mx+nameW+n*dayW,y,totW,hh,"#eaf0fb","#7f8da3",.6);pg.text("Ore",mx+nameW+n*dayW+totW/2,y+15,9,true,"#10284b","center");
   y+=hh;
  };
  const footH=o.foot.length*17+44;
  const avail=H-top-bot-60-footH;
  const rowH=Math.max(15,Math.min(34,avail/Math.max(1,o.rows.length)));
  header(true);
  o.rows.forEach(r=>{
   if(y+rowH>H-bot-footH){header(false)}
   pg.rect(mx,y,nameW,rowH,"#ffffff","#7f8da3",.6);
   const big=rowH>=22;
   pg.text(r.name,mx+6,y+(big?rowH/2-1:rowH/2+3),9.5,true,"#10284b","left",nameW-10);
   if(big)pg.text(r.sub,mx+6,y+rowH/2+9,7,false,"#5b6b83","left",nameW-10);
   r.cells.forEach((c,i)=>{const x=mx+nameW+i*dayW,d=o.days[i];
    pg.rect(x,y,dayW,rowH,c?COL[c]:(d.we?"#f3f5f9":"#ffffff"),"#7f8da3",.6);
    if(c)pg.text(c,x+dayW/2,y+rowH/2+4,Math.min(12,rowH*.5),true,c==="R"?"#0057b7":"#ffffff","center")});
   const tx=mx+nameW+n*dayW;pg.rect(tx,y,totW,rowH,"#eaf0fb","#7f8da3",.6);pg.text(r.total,tx+totW/2,y+rowH/2+4,10,true,"#10284b","center");
   y+=rowH;
  });
  o.foot.forEach(f=>{
   pg.rect(mx,y,nameW,17,"#f7f9fd","#7f8da3",.6);pg.text(f.label,mx+6,y+12,8.5,true,"#44546b");
   f.cells.forEach((c,i)=>{const x=mx+nameW+i*dayW;pg.rect(x,y,dayW,17,c.low?"#fde1de":"#f7f9fd","#7f8da3",.6);pg.text(c.v,x+dayW/2,y+12,8.5,true,c.low?"#b42318":"#44546b","center")});
   pg.rect(mx+nameW+n*dayW,y,totW,17,"#f7f9fd","#7f8da3",.6);y+=17;
  });
  y+=14;let x=mx;
  o.legend.forEach(l=>{pg.rect(x,y,13,13,COL[l.c],l.c==="R"?"#0057b7":null,.8);pg.text(l.t,x+18,y+10,8.5,false,"#44546b");x+=18+widthOf(l.t,8.5)+18});
  pg.text(o.stamp,mx,H-bot+2,8,false,"#7a879b");pg.text(o.status,W-mx,H-bot+2,8,false,"#7a879b","right");
  return build(pages);
 }

 function planPortrait(o){
  W=210*MM;H=297*MM;
  const mx=9*MM,top=9*MM,bot=9*MM,usableW=W-2*mx,n=o.rows.length,days=o.days;
  const dayColW=26*MM,pw=(usableW-dayColW)/Math.max(1,n);
  const pg=new Page();let y=top;
  pg.text(o.title,mx,y+16,17,true,"#10284b");pg.text(o.subtitle,mx,y+29,10,false,"#5b6b83");
  pg.text("NaNo",W-mx-widthOf("NaNoShift",13,true),y+16,13,true,"#0057b7");pg.text("Shift",W-mx-widthOf("Shift",13,true),y+16,13,true,"#e0a812");
  pg.rect(mx,y+34,usableW,3,"#0057b7");y+=44;
  const hh=30,legendH=34,sumH=20;
  const rowH=Math.min(30,(H-bot-y-hh-sumH-legendH-10)/days.length);
  pg.rect(mx,y,dayColW,hh,"#eaf0fb","#7f8da3",.6);pg.text("Giorno",mx+6,y+18,9,true);
  const fs=n>9?7:n>6?8:9.5;
  o.rows.forEach((r,i)=>{const x=mx+dayColW+i*pw;pg.rect(x,y,pw,hh,"#eaf0fb","#7f8da3",.6);
   pg.text(r.name,x+pw/2,y+13,fs,true,"#10284b","center",pw-4);pg.text(r.sub,x+pw/2,y+24,6.5,false,"#5b6b83","center",pw-4)});
  y+=hh;
  days.forEach((d,j)=>{
   pg.rect(mx,y,dayColW,rowH,d.we?"#fdecea":"#ffffff","#7f8da3",.6);
   pg.text(d.d+" "+d.wd,mx+6,y+rowH/2+3.5,9,true,d.we?"#c0261b":"#10284b");
   o.rows.forEach((r,i)=>{const x=mx+dayColW+i*pw,c=r.cells[j];
    pg.rect(x,y,pw,rowH,c?COL[c]:(d.we?"#f3f5f9":"#ffffff"),"#7f8da3",.6);
    if(c)pg.text(c,x+pw/2,y+rowH/2+4,Math.min(13,rowH*.55),true,c==="R"?"#0057b7":"#ffffff","center")});
   y+=rowH;
  });
  pg.rect(mx,y,dayColW,sumH,"#eaf0fb","#7f8da3",.6);pg.text("Ore mese",mx+6,y+13,9,true);
  o.rows.forEach((r,i)=>{const x=mx+dayColW+i*pw;pg.rect(x,y,pw,sumH,"#eaf0fb","#7f8da3",.6);pg.text(r.total,x+pw/2,y+13,9.5,true,"#10284b","center")});
  y+=sumH+14;let x=mx;
  o.legend.forEach(l=>{pg.rect(x,y,12,12,COL[l.c],l.c==="R"?"#0057b7":null,.8);pg.text(l.t,x+16,y+9.5,8,false,"#44546b");x+=16+widthOf(l.t,8)+14;if(x>W-mx-90){x=mx;y+=16}});
  pg.text(o.stamp,mx,H-bot+2,8,false,"#7a879b");pg.text(o.status,W-mx,H-bot+2,8,false,"#7a879b","right");
  return build([pg]);
 }

 function month(o,orient){
  const P=orient==="p";W=(P?210:297)*MM;H=(P?297:210)*MM;
  const mx=9*MM,top=9*MM,bot=9*MM,usableW=W-2*mx,pg=new Page();let y=top;
  pg.text(o.title,mx,y+16,P?17:19,true,"#10284b");pg.text(o.subtitle,mx,y+29,10,false,"#5b6b83");
  pg.text("NaNo",W-mx-widthOf("NaNoShift",13,true),y+16,13,true,"#0057b7");pg.text("Shift",W-mx-widthOf("Shift",13,true),y+16,13,true,"#e0a812");
  pg.rect(mx,y+34,usableW,3,"#0057b7");y+=44;
  const lead=(new Date(o.year,o.month,1).getDay()+6)%7,dim=new Date(o.year,o.month+1,0).getDate(),weeks=Math.ceil((lead+dim)/7);
  const cw=usableW/7,hh=18,sumH=44,ch=Math.min(P?90:80,(H-bot-y-hh-sumH)/weeks);
  ["Lun","Mar","Mer","Gio","Ven","Sab","Dom"].forEach((w,i)=>{pg.rect(mx+i*cw,y,cw,hh,"#eaf0fb","#7f8da3",.6);pg.text(w,mx+i*cw+cw/2,y+12,9,true,i>4?"#c0261b":"#10284b","center")});
  y+=hh;
  for(let k=0;k<weeks*7;k++){
   const d=k-lead+1,col=k%7,row=Math.floor(k/7),x=mx+col*cw,yy=y+row*ch;
   if(d<1||d>dim){pg.rect(x,yy,cw,ch,"#fafbfd","#d5dbe6",.5);continue}
   const c=o.days[d];
   pg.rect(x,yy,cw,ch,c?COL[c.code]:(col>4?"#f3f5f9":"#ffffff"),"#7f8da3",.6);
   pg.text(String(d),x+5,yy+12,10,true,c?(c.code==="R"?"#0057b7":"#ffffff"):(col>4?"#c0261b":"#10284b"));
   if(c){pg.text(c.code,x+cw/2,yy+ch/2+(P?8:7),Math.min(30,ch*.42),true,c.code==="R"?"#0057b7":"#ffffff","center");
    if(c.time)pg.text(c.time,x+cw/2,yy+ch-7,8,false,c.code==="R"?"#0057b7":"#ffffff","center",cw-6)}
  }
  y+=weeks*ch+14;let x=mx;
  o.legend.forEach(l=>{pg.rect(x,y,12,12,COL[l.c],l.c==="R"?"#0057b7":null,.8);pg.text(l.t,x+16,y+9.5,8.5,false,"#44546b");x+=16+widthOf(l.t,8.5)+16});
  pg.text(o.summary,W-mx,y+9.5,10,true,"#10284b","right");
  pg.text(o.stamp,mx,H-bot+2,8,false,"#7a879b");
  return build([pg]);
 }
 window.NanoPdf={plan,month};
})();
