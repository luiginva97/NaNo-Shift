import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const cors = {
  "Access-Control-Allow-Origin": "https://nanoshift.pages.dev",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  if (req.method !== "POST") return json({ error: "Metodo non consentito" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "Sessione mancante" }, 401);

  const callerClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: authError } = await callerClient.auth.getUser();
  if (authError || !user) return json({ error: "Sessione non valida" }, 401);

  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: profile, error: profileError } = await admin.from("profiles").select("role").eq("id", user.id).maybeSingle();
  if (profileError) return json({ error: "Impossibile verificare il profilo" }, 500);
  const { data: masterFlag, error: masterCheckError } = await callerClient.rpc("is_master_account");
  const isMaster = profile?.role === "admin" && !masterCheckError && masterFlag === true;

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Richiesta non valida" }, 400); }
  const action = String(body.action || "");

  if (action === "bootstrap_admin") {
    const { data: allAdmins, error: adminsError } = await admin.from("profiles").select("id").eq("role", "admin").limit(1);
    if (adminsError) return json({ error: "Verifica amministratori non riuscita" }, 500);
    if ((allAdmins || []).length) return json({ error: "Un amministratore è già stato configurato" }, 409);
    if (user.email?.toLowerCase() !== "nanoshift01@gmail.com" || !user.email_confirmed_at) {
      return json({ error: "È necessario accedere con l'indirizzo amministratore verificato" }, 403);
    }
    const { error } = await admin.from("profiles").update({ role: "admin", updated_at: new Date().toISOString() }).eq("id", user.id);
    if (error) return json({ error: "Assegnazione amministratore non riuscita" }, 500);
    return json({ success: true, message: "Account amministratore inizializzato" });
  }

  if (action === "list_visible_cvs") {
    const unitId = String(body.unit_id || "");
    if (isMaster) return json({ error: "Il Master non può consultare i CV delle strutture" }, 403);
    if (!unitId) return json({ error: "Reparto non specificato" }, 400);
    const { data: coord } = await admin.from("unit_members").select("unit_id").eq("unit_id", unitId).eq("user_id", user.id).eq("unit_role", "coordinator").eq("status", "active").maybeSingle();
    const { data: unit } = await admin.from("units").select("approval_status").eq("id", unitId).maybeSingle();
    if (!coord || unit?.approval_status !== "approved") return json({ error: "Accesso riservato alla coordinatrice attiva del reparto" }, 403);
    const { data: members, error: memberError } = await admin.from("unit_members").select("user_id").eq("unit_id", unitId).eq("status", "active");
    if (memberError) return json({ error: "Impossibile leggere il personale del reparto" }, 500);
    const ids = (members || []).map((m) => m.user_id);
    if (!ids.length) return json({ cvs: [] });
    const { data: profiles, error: profileListError } = await admin.from("profiles").select("id,display_name,first_name,last_name,cv_path").eq("cv_visible_to_coordinators", true).not("cv_path", "is", null).in("id", ids);
    if (profileListError) return json({ error: "Impossibile caricare i CV condivisi" }, 500);
    const cvs = [];
    for (const p of profiles || []) {
      const { data: signed, error: signedError } = await admin.storage.from("professional-documents").createSignedUrl(p.cv_path, 300);
      if (!signedError && signed?.signedUrl) cvs.push({ user_id: p.id, name: p.display_name || [p.first_name,p.last_name].filter(Boolean).join(" "), url: signed.signedUrl });
    }
    return json({ cvs });
  }

  if (!isMaster) return json({ error: "Operazione riservata al Master" }, 403);

  if (action === "list_users") {
    const [{ data: profiles, error: pErr }, { data: users, error: uErr }] = await Promise.all([
      admin.from("profiles").select("id,role,created_at").order("created_at", { ascending: false }),
      admin.auth.admin.listUsers({ page: 1, perPage: 1000 })
    ]);
    if (pErr || uErr) return json({ error: "Impossibile caricare l'elenco account" }, 500);
    const authById = new Map((users?.users || []).map((u) => [u.id, u]));
    return json({
      users: (profiles || []).map((p) => {
        const a = authById.get(p.id);
        return { id: p.id, role: p.role, created_at: p.created_at,
          last_sign_in_at: a?.last_sign_in_at || null, email_confirmed: !!a?.email_confirmed_at };
      })
    });
  }

  if (action === "list_units") {
    const { data, error } = await admin.from("units")
      .select("id,name,approval_status,created_at")
      .eq("approval_status", "pending")
      .order("created_at", { ascending: true });
    if (error) return json({ error: "Impossibile caricare le richieste delle strutture" }, 500);
    return json({ units: data || [] });
  }

  if (action === "unit_stats") {
    // Solo numeri aggregati: niente nomi del personale, turni o disponibilità.
    const [{ data: units, error: uErr }, { data: members, error: mErr }] = await Promise.all([
      admin.from("units").select("id,name,approval_status,created_at").order("created_at", { ascending: false }),
      admin.from("unit_members").select("unit_id,unit_role,status"),
    ]);
    if (uErr || mErr) return json({ error: "Impossibile caricare le statistiche delle strutture" }, 500);
    const by = new Map<string, { active: number; pending: number; coordinators: number }>();
    for (const m of members || []) {
      const c = by.get(m.unit_id) || { active: 0, pending: 0, coordinators: 0 };
      if (m.status === "active") { c.active++; if (m.unit_role === "coordinator") c.coordinators++; }
      else if (m.status === "pending") c.pending++;
      by.set(m.unit_id, c);
    }
    return json({
      units: (units || []).map((u) => ({
        id: u.id, name: u.name, approval_status: u.approval_status, created_at: u.created_at,
        ...(by.get(u.id) || { active: 0, pending: 0, coordinators: 0 }),
      })),
    });
  }

  if (action === "review_unit") {
    const unitId = String(body.unit_id || "");
    const decision = String(body.decision || "");
    if (!unitId || !["approve", "reject"].includes(decision)) return json({ error: "Decisione non valida" }, 400);
    const { data: unit, error: unitError } = await admin.from("units")
      .select("id,approval_status").eq("id", unitId).maybeSingle();
    if (unitError || !unit || unit.approval_status !== "pending") return json({ error: "Richiesta non più disponibile" }, 409);
    const { error: reviewError } = await admin.rpc("review_unit_approval", {
      p_unit: unitId,
      p_approve: decision === "approve",
      p_master: user.id
    });
    if (reviewError) return json({ error: reviewError.message || "Revisione struttura non riuscita" }, 409);
    return json({ success: true });
  }

  if (action === "set_global_role") {
    const target = String(body.user_id || "");
    const role = String(body.role || "");
    if (!target || !["nurse", "admin"].includes(role)) return json({ error: "Ruolo non valido" }, 400);
    if (target === user.id && role !== "admin") return json({ error: "Non puoi rimuovere il tuo ruolo amministratore" }, 400);
    const { error } = await admin.from("profiles").update({ role, updated_at: new Date().toISOString() }).eq("id", target);
    if (error) return json({ error: "Modifica ruolo non riuscita" }, 500);
    return json({ success: true });
  }



  return json({ error: "Azione non riconosciuta" }, 400);
});