import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import webpush from "npm:web-push@3.6.7";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Metodo non consentito" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json({ error: "Configurazione server incompleta" }, 500);

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: configRows, error: configError } = await admin.rpc("get_push_config");
  if (configError) return json({ error: "Configurazione push non disponibile" }, 500);
  const config = Array.isArray(configRows) ? configRows[0] : configRows;
  if (!config?.cron_token || req.headers.get("x-nanoshift-cron-token") !== config.cron_token) {
    return json({ error: "Non autorizzato" }, 401);
  }

  let privateKey = config.vapid_private_key as string | null;
  let publicKey = config.vapid_public_key as string | null;

  // La coppia VAPID viene generata sul server e la chiave privata viene salvata solo in Vault.
  if (!privateKey || !publicKey) {
    const pair = await crypto.subtle.generateKey(
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["sign", "verify"],
    );
    const rawPublic = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
    const privateJwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
    if (!privateJwk.d) return json({ error: "Generazione chiave VAPID non riuscita" }, 500);
    publicKey = base64Url(rawPublic);
    privateKey = privateJwk.d;
    const { error: storeError } = await admin.rpc("store_push_vapid", {
      p_private: privateKey,
      p_public: publicKey,
    });
    if (storeError) return json({ error: "Salvataggio chiavi VAPID non riuscito" }, 500);
  }

  try {
    webpush.setVapidDetails("https://nanoshift.pages.dev", publicKey, privateKey);
  } catch {
    return json({ error: "Configurazione VAPID non valida" }, 500);
  }

  const { data: pending, error: pendingError } = await admin
    .from("user_notifications")
    .select("id,user_id")
    .is("push_sent_at", null)
    .order("created_at", { ascending: true })
    .limit(200);
  if (pendingError) return json({ error: "Lettura notifiche non riuscita" }, 500);

  let delivered = 0;
  let retried = 0;
  let removed = 0;

  for (const notification of pending || []) {
    const { data: subscriptions, error: subscriptionError } = await admin
      .from("push_subscriptions")
      .select("id,endpoint,p256dh,auth")
      .eq("user_id", notification.user_id);

    if (subscriptionError) {
      retried++;
      continue;
    }

    let retry = false;
    for (const sub of subscriptions || []) {
      try {
        // Contenuto volutamente generico: non mostra scadenze o dati sanitari sul lock screen.
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          JSON.stringify({
            title: "NaNoShift",
            body: "Hai un aggiornamento da consultare. Apri l'app.",
            url: "/dashboard.html",
          }),
        );
        delivered++;
      } catch (error) {
        const status = Number((error as { statusCode?: number }).statusCode || 0);
        if (status === 404 || status === 410) {
          await admin.from("push_subscriptions").delete().eq("id", sub.id);
          removed++;
        } else {
          retry = true;
        }
      }
    }

    if (!retry) {
      await admin.from("user_notifications")
        .update({ push_sent_at: new Date().toISOString() })
        .eq("id", notification.id);
    } else {
      retried++;
    }
  }

  return json({
    success: true,
    notifications: pending?.length || 0,
    delivered,
    removedSubscriptions: removed,
    deferred: retried,
  });
});
