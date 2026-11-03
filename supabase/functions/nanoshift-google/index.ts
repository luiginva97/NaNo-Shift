// Sincronizzazione bidirezionale con Google Calendar (eventi personali + turni).
// verify_jwt = false: il callback OAuth di Google è una GET senza JWT. Le azioni dell'app verificano da sé
// il token dell'utente; l'azione "cron" richiede il token interno custodito in Vault.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const APP = "https://nanoshift.pages.dev";
const FN_URL = "https://mmkdibdomjaxwqfryqcw.supabase.co/functions/v1/nanoshift-google";
const CLIENT_ID = Deno.env.get("GOOGLE_CLIENT_ID") || "739771447888-1g9t5r99bcggaic8qfsduf5qp6j541o0.apps.googleusercontent.com";
const CLIENT_SECRET = Deno.env.get("GOOGLE_CLIENT_SECRET") || "";
const SCOPE = "openid email https://www.googleapis.com/auth/calendar.events.owned";
const TZ = "Europe/Rome";
const cors = {
  "Access-Control-Allow-Origin": APP,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

const b64 = (u: Uint8Array) => btoa(String.fromCharCode(...u));
const unb64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const hex = (u: Uint8Array) => [...u].map((x) => x.toString(16).padStart(2, "0")).join("");
async function sha256hex(s: string) { return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))); }
async function aesKey(h: string) { return crypto.subtle.importKey("raw", new Uint8Array(h.match(/.{2}/g)!.map((x) => parseInt(x, 16))), "AES-GCM", false, ["encrypt", "decrypt"]); }
async function encrypt(keyHex: string, text: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await aesKey(keyHex), new TextEncoder().encode(text)));
  return b64(iv) + "." + b64(ct);
}
async function decrypt(keyHex: string, packed: string) {
  const [iv, ct] = packed.split(".");
  return new TextDecoder().decode(await crypto.subtle.decrypt({ name: "AES-GCM", iv: unb64(iv) }, await aesKey(keyHex), unb64(ct)));
}

// ---- date helpers (Europe/Rome) ----
function romeDate(iso: string): string { return new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(iso)); }
function romeMidnightIso(date: string): string {
  const guess = new Date(date + "T00:00:00Z");
  const part = new Intl.DateTimeFormat("en-US", { timeZone: TZ, timeZoneName: "longOffset" }).formatToParts(guess).find((p) => p.type === "timeZoneName")?.value || "GMT+01:00";
  const m = part.match(/GMT([+-])(\d{2}):?(\d{2})?/);
  const off = m ? (m[1] === "-" ? -1 : 1) * (parseInt(m[2]) * 60 + parseInt(m[3] || "0")) : 60;
  return new Date(guess.getTime() - off * 60000).toISOString();
}
const addDay = (d: string, n: number) => { const x = new Date(d + "T12:00:00Z"); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };

// ---- Google API ----
async function gfetch(path: string, token: string, init: RequestInit = {}) {
  const r = await fetch("https://www.googleapis.com/calendar/v3" + path, { ...init, headers: { Authorization: "Bearer " + token, "Content-Type": "application/json", ...(init.headers || {}) } });
  if (r.status === 204) return null;
  const t = await r.text(); let d: any = null; try { d = t ? JSON.parse(t) : null; } catch (_) { /* */ }
  if (!r.ok) { const e: any = new Error(d?.error?.message || ("Google " + r.status)); e.status = r.status; throw e; }
  return d;
}
async function refreshAccess(refresh: string) {
  const r = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: CLIENT_ID, client_secret: CLIENT_SECRET, refresh_token: refresh, grant_type: "refresh_token" }) });
  const d = await r.json();
  if (!r.ok) { const e: any = new Error(d.error_description || d.error || "token"); e.invalid = d.error === "invalid_grant"; throw e; }
  return d.access_token as string;
}

const SHIFT_LABEL: Record<string, string> = { M: "Mattina", P: "Pomeriggio", G: "Giornata", N: "Notte", R: "Riposo" };
const evId = (uuid: string) => "nanoshiftev" + uuid.replace(/-/g, "").toLowerCase();
const shId = (uuid: string) => "nanoshift" + uuid.replace(/-/g, "").toLowerCase();

function toGoogleBody(e: any) {
  const body: any = { summary: e.title, description: e.description || "", location: e.location || "",
    extendedProperties: { private: { nanoshiftSource: "NaNoShift", nanoshiftEventId: e.id } } };
  if (e.all_day) { body.start = { date: romeDate(e.starts_at) }; body.end = { date: romeDate(e.ends_at) }; }
  else { body.start = { dateTime: new Date(e.starts_at).toISOString() }; body.end = { dateTime: new Date(e.ends_at).toISOString() }; }
  return body;
}
function fromGoogle(g: any) {
  const allDay = !!g.start?.date;
  const starts = allDay ? romeMidnightIso(g.start.date) : new Date(g.start?.dateTime).toISOString();
  const ends = allDay ? romeMidnightIso(g.end?.date || addDay(g.start.date, 1)) : new Date(g.end?.dateTime).toISOString();
  return { title: String(g.summary || "(Senza titolo)").slice(0, 200), description: g.description ? String(g.description).slice(0, 1000) : null,
    location: g.location ? String(g.location).slice(0, 200) : null, starts_at: starts, ends_at: ends, all_day: allDay };
}

async function syncUser(admin: any, userId: string, keyHex: string) {
  const { data: conns } = await admin.rpc("google_get_connection", { p_user: userId });
  const conn = Array.isArray(conns) ? conns[0] : conns;
  if (!conn) throw new Error("Google Calendar non collegato");
  let token: string;
  try { token = await refreshAccess(await decrypt(keyHex, conn.refresh_token_ciphertext)); }
  catch (e: any) {
    await admin.rpc("google_mark_sync", { p_user: userId, p_error: e.invalid ? "Collegamento scaduto: ricollega Google Calendar" : "Accesso a Google non riuscito", p_disable: !!e.invalid });
    throw new Error(e.invalid ? "Collegamento scaduto: ricollega Google Calendar" : "Accesso a Google non riuscito");
  }

  const now = Date.now();
  const winFrom = new Date(now - 30 * 864e5), winTo = new Date(now + 180 * 864e5);
  const stats = { pushed: 0, pulled: 0, deleted: 0 };

  // eventi Google nella finestra
  const gAll: any[] = []; let pt: string | null = null;
  do {
    const q = new URLSearchParams({ timeMin: winFrom.toISOString(), timeMax: winTo.toISOString(), singleEvents: "true", maxResults: "2500" });
    if (pt) q.set("pageToken", pt);
    const page: any = await gfetch("/calendars/primary/events?" + q, token);
    gAll.push(...(page?.items || [])); pt = page?.nextPageToken || null;
  } while (pt);
  const gById = new Map<string, any>(gAll.filter((g) => g.status !== "cancelled").map((g) => [g.id, g]));

  // eventi locali
  const { data: locals } = await admin.from("personal_commitments").select("*").eq("user_id", userId)
    .lt("starts_at", winTo.toISOString()).gt("ends_at", winFrom.toISOString());
  const used = new Set<string>();

  for (const L of locals || []) {
    const gid = L.google_event_id as string | null;
    const G = gid ? gById.get(gid) : undefined;
    if (L.deleted_at) {
      if (gid && G && L.source === "nanoshift") { await gfetch("/calendars/primary/events/" + encodeURIComponent(gid), token, { method: "DELETE" }).catch(() => null); stats.deleted++; }
      if (G) used.add(G.id);
      continue;
    }
    if (G) {
      used.add(G.id);
      const gUpd = new Date(G.updated).getTime(), seen = L.google_updated_at ? new Date(L.google_updated_at).getTime() : 0;
      const lUpd = new Date(L.updated_at).getTime();
      const gChanged = gUpd > seen + 1000, lChanged = lUpd > seen + 1000;
      if (gChanged && (!lChanged || gUpd >= lUpd)) {
        const f = fromGoogle(G);
        await admin.from("personal_commitments").update({ ...f, google_etag: G.etag, google_updated_at: G.updated, updated_at: G.updated }).eq("id", L.id);
        stats.pulled++;
      } else if (lChanged && L.source === "nanoshift") {
        const res = await gfetch("/calendars/primary/events/" + encodeURIComponent(G.id), token, { method: "PATCH", body: JSON.stringify(toGoogleBody(L)) });
        await admin.from("personal_commitments").update({ google_etag: res.etag, google_updated_at: res.updated, updated_at: res.updated }).eq("id", L.id);
        stats.pushed++;
      }
    } else if (gid) {
      // sparito da Google → eliminato anche qui
      await admin.from("personal_commitments").update({ deleted_at: new Date().toISOString() }).eq("id", L.id);
      stats.deleted++;
    } else if (L.source === "nanoshift") {
      const id = evId(L.id);
      let res: any;
      try { res = await gfetch("/calendars/primary/events", token, { method: "POST", body: JSON.stringify({ ...toGoogleBody(L), id }) }); }
      catch (e: any) { if (e.status === 409) res = await gfetch("/calendars/primary/events/" + id, token, { method: "PATCH", body: JSON.stringify(toGoogleBody(L)) }); else throw e; }
      used.add(res.id);
      await admin.from("personal_commitments").update({ google_calendar_id: "primary", google_event_id: res.id, google_etag: res.etag, google_updated_at: res.updated, updated_at: res.updated }).eq("id", L.id);
      stats.pushed++;
    }
  }

  // eventi presenti solo su Google → importati
  const known = new Map<string, string>();
  { const ids = [...gById.keys()].filter((i) => !used.has(i));
    if (ids.length) { const { data: have } = await admin.from("personal_commitments").select("id,google_event_id").eq("user_id", userId).in("google_event_id", ids); (have || []).forEach((r: any) => known.set(r.google_event_id, r.id)); } }
  const toInsert: any[] = [];
  for (const [id, G] of gById) {
    if (used.has(id) || known.has(id)) continue;
    if (G.extendedProperties?.private?.nanoshiftShiftId) continue;
    if (G.eventType && G.eventType !== "default") continue;
    if (!G.start || !G.end) continue;
    const f = fromGoogle(G);
    if (isNaN(new Date(f.starts_at).getTime()) || !(new Date(f.ends_at) > new Date(f.starts_at))) continue;
    toInsert.push({ ...f, user_id: userId, source: "google", google_calendar_id: "primary", google_event_id: id, google_etag: G.etag, google_updated_at: G.updated, updated_at: G.updated });
  }
  if (toInsert.length) { const { error } = await admin.from("personal_commitments").insert(toInsert); if (error) throw new Error("Importazione: " + error.message); stats.pulled += toInsert.length; }

  // turni → Google (solo invio)
  const from = winFrom.toISOString().slice(0, 10), to = winTo.toISOString().slice(0, 10);
  const { data: shifts } = await admin.from("shifts").select("id,shift_date,start_time,end_time,code").eq("user_id", userId).gte("shift_date", from).lte("shift_date", to);
  const gShift = new Map<string, any>(gAll.filter((g) => g.status !== "cancelled" && g.extendedProperties?.private?.nanoshiftShiftId).map((g) => [g.extendedProperties.private.nanoshiftShiftId, g]));
  const active = new Set<string>();
  for (const s of shifts || []) {
    const id = String(s.id); active.add(id);
    const body: any = { summary: (s.code || "") + " · " + (SHIFT_LABEL[s.code] || "Turno") + " — NaNoShift", extendedProperties: { private: { nanoshiftSource: "NaNoShift", nanoshiftShiftId: id } } };
    if (s.code === "R") { body.start = { date: s.shift_date }; body.end = { date: addDay(s.shift_date, 1) }; }
    else {
      const st = String(s.start_time).slice(0, 5), en = String(s.end_time).slice(0, 5);
      body.start = { dateTime: s.shift_date + "T" + st + ":00", timeZone: TZ };
      body.end = { dateTime: (en > st ? s.shift_date : addDay(s.shift_date, 1)) + "T" + en + ":00", timeZone: TZ };
    }
    const prior = gShift.get(id);
    const same = prior && prior.summary === body.summary && JSON.stringify(prior.start) === JSON.stringify({ ...body.start, ...(prior.start?.timeZone ? {} : {}) });
    if (prior) { if (!same) { await gfetch("/calendars/primary/events/" + encodeURIComponent(prior.id), token, { method: "PATCH", body: JSON.stringify(body) }); stats.pushed++; } }
    else {
      try { await gfetch("/calendars/primary/events", token, { method: "POST", body: JSON.stringify({ ...body, id: shId(id) }) }); stats.pushed++; }
      catch (e: any) { if (e.status === 409) await gfetch("/calendars/primary/events/" + shId(id), token, { method: "PATCH", body: JSON.stringify(body) }).catch(() => null); else throw e; }
    }
  }
  for (const [sid, g] of gShift) if (!active.has(sid)) { await gfetch("/calendars/primary/events/" + encodeURIComponent(g.id), token, { method: "DELETE" }).catch(() => null); stats.deleted++; }

  await admin.rpc("google_mark_sync", { p_user: userId, p_error: null, p_disable: false });
  return stats;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = Deno.env.get("SUPABASE_URL")!, anon = Deno.env.get("SUPABASE_ANON_KEY")!, service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: cfgRows } = await admin.rpc("google_get_config");
  const cfg: any = Array.isArray(cfgRows) ? cfgRows[0] : cfgRows;
  if (!cfg?.token_key) return json({ error: "Configurazione Google non disponibile" }, 500);
  const u = new URL(req.url);

  // ---- callback OAuth (GET dal browser, dopo il consenso su Google) ----
  if (req.method === "GET") {
    const back = (q: string) => Response.redirect(APP + "/dashboard.html?area=personale&section=calendarView&google=" + q, 302);
    const code = u.searchParams.get("code"), state = u.searchParams.get("state");
    if (u.searchParams.get("error") || !code || !state) return back("annullato");
    const userId = (await admin.rpc("google_consume_state", { p_hash: await sha256hex(state) })).data as string | null;
    if (!userId) return back("errore");
    try {
      const r = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ code, client_id: CLIENT_ID, client_secret: CLIENT_SECRET, redirect_uri: FN_URL, grant_type: "authorization_code" }) });
      const d = await r.json();
      if (!r.ok || !d.refresh_token) return back("errore");
      let email: string | null = null;
      try { const info = await (await fetch("https://openidconnect.googleapis.com/v1/userinfo", { headers: { Authorization: "Bearer " + d.access_token } })).json(); email = info.email || null; } catch (_) { /* */ }
      await admin.rpc("google_save_connection", { p_user: userId, p_email: email, p_cipher: await encrypt(cfg.token_key, d.refresh_token), p_scope: d.scope || SCOPE });
      return back("collegato");
    } catch (_) { return back("errore"); }
  }
  if (req.method !== "POST") return json({ error: "Metodo non consentito" }, 405);
  let body: any = {}; try { body = await req.json(); } catch (_) { /* */ }
  const action = String(body.action || "");

  // ---- sincronizzazione pianificata (token interno) ----
  if (action === "cron") {
    if (!cfg.cron_token || req.headers.get("x-nanoshift-cron-token") !== cfg.cron_token) return json({ error: "Non autorizzato" }, 401);
    if (!CLIENT_SECRET) return json({ error: "GOOGLE_CLIENT_SECRET mancante" }, 500);
    const { data: list } = await admin.rpc("google_list_connections", { p_limit: 40 });
    let ok = 0, failed = 0;
    for (const row of list || []) { try { await syncUser(admin, row.user_id, cfg.token_key); ok++; } catch (e: any) { failed++; await admin.rpc("google_mark_sync", { p_user: row.user_id, p_error: String(e.message || e).slice(0, 200), p_disable: false }); } }
    return json({ ok, failed });
  }

  // ---- azioni dell'utente ----
  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "Sessione mancante" }, 401);
  const { data: { user }, error: aerr } = await createClient(url, anon, { global: { headers: { Authorization: authHeader } } }).auth.getUser();
  if (aerr || !user) return json({ error: "Sessione non valida" }, 401);

  if (action === "status") {
    const { data } = await admin.rpc("google_get_connection", { p_user: user.id });
    const c: any = Array.isArray(data) ? data[0] : data;
    return json({ configured: !!CLIENT_SECRET, connected: !!c && c.sync_enabled, email: c?.google_email || null, last_sync_at: c?.last_sync_at || null, last_error: c?.last_sync_error || null });
  }
  if (action === "connect_url") {
    if (!CLIENT_SECRET) return json({ error: "Il collegamento a Google non è ancora configurato sul server" }, 503);
    const state = b64(crypto.getRandomValues(new Uint8Array(24))).replace(/[+/=]/g, "x");
    await admin.rpc("google_create_state", { p_user: user.id, p_hash: await sha256hex(state) });
    const q = new URLSearchParams({ client_id: CLIENT_ID, redirect_uri: FN_URL, response_type: "code", scope: SCOPE, access_type: "offline", prompt: "consent", include_granted_scopes: "true", state });
    return json({ url: "https://accounts.google.com/o/oauth2/v2/auth?" + q });
  }
  if (action === "sync") {
    if (!CLIENT_SECRET) return json({ error: "Il collegamento a Google non è ancora configurato sul server" }, 503);
    try { return json({ success: true, ...(await syncUser(admin, user.id, cfg.token_key)) }); }
    catch (e: any) { await admin.rpc("google_mark_sync", { p_user: user.id, p_error: String(e.message || e).slice(0, 200), p_disable: false }); return json({ error: e.message || "Sincronizzazione non riuscita" }, 502); }
  }
  if (action === "disconnect") {
    const { data } = await admin.rpc("google_get_connection", { p_user: user.id });
    const c: any = Array.isArray(data) ? data[0] : data;
    if (c) { try { const t = await decrypt(cfg.token_key, c.refresh_token_ciphertext); await fetch("https://oauth2.googleapis.com/revoke?token=" + encodeURIComponent(t), { method: "POST" }); } catch (_) { /* */ } }
    await admin.rpc("google_delete_connection", { p_user: user.id });
    return json({ success: true });
  }
  return json({ error: "Azione non riconosciuta" }, 400);
});
