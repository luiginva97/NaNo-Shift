(function(){
  const $=id=>document.getElementById(id);
  function decodeKey(value){
    const padded=value.replace(/-/g,"+").replace(/_/g,"/");
    const raw=atob(padded+"=".repeat((4-padded.length%4)%4));
    return Uint8Array.from(raw,c=>c.charCodeAt(0));
  }
  async function enable(sb){
    if(!("serviceWorker" in navigator)||!("PushManager" in window)||!("Notification" in window)){
      throw new Error("Questo browser non supporta le notifiche push.");
    }
    const permission=await Notification.requestPermission();
    if(permission!=="granted")throw new Error("Permesso notifiche non concesso.");
    const {data:key,error:keyError}=await sb.rpc("get_push_public_key");
    if(keyError||!key)throw new Error("Configurazione notifiche non pronta. Riprova tra poco.");
    const registration=await navigator.serviceWorker.register("/sw.js",{scope:"/"});
    await navigator.serviceWorker.ready;
    let subscription=await registration.pushManager.getSubscription();
    if(!subscription){
      subscription=await registration.pushManager.subscribe({
        userVisibleOnly:true,
        applicationServerKey:decodeKey(key)
      });
    }
    const value=subscription.toJSON();
    const {error}=await sb.rpc("save_push_subscription",{
      p_endpoint:value.endpoint,
      p_p256dh:value.keys?.p256dh,
      p_auth:value.keys?.auth
    });
    if(error){await subscription.unsubscribe();throw new Error(error.message);}
    return "Notifiche push attivate su questo dispositivo.";
  }
  async function disable(sb){
    const registration=await navigator.serviceWorker.getRegistration("/");
    const subscription=await registration?.pushManager.getSubscription();
    if(!subscription)return "Non ci sono notifiche attive su questo dispositivo.";
    const {error}=await sb.rpc("delete_push_subscription",{p_endpoint:subscription.endpoint});
    if(error)throw new Error(error.message);
    await subscription.unsubscribe();
    return "Notifiche push disattivate su questo dispositivo.";
  }
  function mount(sb){
    const enableButton=$("enablePush"),disableButton=$("disablePush"),status=$("pushStatus");
    if(!enableButton||!disableButton||!status)return;
    const supported="serviceWorker" in navigator&&"PushManager" in window&&"Notification" in window;
    if(!supported){status.textContent="Le notifiche push non sono supportate da questo browser.";enableButton.disabled=true;disableButton.disabled=true;return;}
    const refresh=async()=>{
      const registration=await navigator.serviceWorker.getRegistration("/");
      const subscription=await registration?.pushManager.getSubscription();
      status.textContent=subscription?"Notifiche attive su questo dispositivo.":"Notifiche non attive su questo dispositivo.";
    };
    enableButton.onclick=async()=>{
      enableButton.disabled=true;
      try{status.textContent=await enable(sb);}catch(e){status.textContent=e.message||"Attivazione non riuscita.";}
      finally{enableButton.disabled=false;await refresh();}
    };
    disableButton.onclick=async()=>{
      disableButton.disabled=true;
      try{status.textContent=await disable(sb);}catch(e){status.textContent=e.message||"Disattivazione non riuscita.";}
      finally{disableButton.disabled=false;await refresh();}
    };
    refresh();
  }
  window.NaNoPush={mount,enable,disable};
})();
