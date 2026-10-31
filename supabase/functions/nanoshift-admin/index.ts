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
    if (!unitId) return json({ error: "Reparto non specificato" }, 400);
    const { data: coord } = await admin.from("unit_members").select("unit_id").eq("unit_id", unitId).eq("user_id", user.id).eq("unit_role", "coordinator").eq("status", "active").maybeSingle();
    if (!coord && profile?.role !== "admin") return json({ error: "Accesso riservato alla coordinatrice del reparto" }, 403);
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

  if (profile?.role !== "admin") return json({ error: "Operazione riservata all'amministratore" }, 403);

  if (action === "list_users") {
    const [{ data: profiles, error: pErr }, { data: users, error: uErr }, { data: units, error: unErr }, { data: members, error: mErr }] = await Promise.all([
      admin.from("profiles").select("id,display_name,first_name,last_name,profession,employment_type,role,created_at,tax_code,order_registration_number,blsd_expires_on,order_expires_on,fire_safety_expires_on,cv_visible_to_coordinators").order("created_at", { ascending: false }),
      admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
      admin.from("units").select("id,name"),
      admin.from("unit_members").select("unit_id,user_id,unit_role,status")
    ]);
    if (pErr || uErr || unErr || mErr) return json({ error: "Impossibile caricare l'elenco utenti" }, 500);
    const authById = new Map((users?.users || []).map((u) => [u.id, u]));
    return json({
      users: (profiles || []).map((p) => {
        const a = authById.get(p.id);
        return { ...p, email: a?.email || "", last_sign_in_at: a?.last_sign_in_at || null, email_confirmed: !!a?.email_confirmed_at,
          unit_memberships: (members || []).filter((m) => m.user_id === p.id).map((m) => ({ ...m, unit_name: (units || []).find((u) => u.id === m.unit_id)?.name || "Reparto" })) };
      }),
      units: units || []
    });
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

  if (action === "set_unit_role") {
    const target = String(body.user_id || ""), unit = String(body.unit_id || "");
    const role = String(body.role || "");
    if (!target || !unit || !["nurse", "coordinator"].includes(role)) return json({ error: "Dati ruolo reparto non validi" }, 400);
    const { data: existingMember, error: lookupError } = await admin.from("unit_members").select("staff_role").eq("user_id", target).eq("unit_id", unit).maybeSingle();
    if (lookupError) return json({ error: "Verifica iscrizione al reparto non riuscita" }, 500);
    const membership = { unit_id: unit, user_id: target, unit_role: role, status: "active", staff_role: existingMember?.staff_role || "infermiere" };
    const { error } = await admin.from("unit_members").upsert(membership, { onConflict: "unit_id,user_id" });
    if (error) return json({ error: "Modifica ruolo reparto non riuscita" }, 500);
    return json({ success: true });
  }

  return json({ error: "Azione non riconosciuta" }, 400);
});