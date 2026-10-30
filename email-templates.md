# NaNoShift — template email per Supabase Auth

Questi template vanno incollati manualmente in **Supabase → Authentication → Email Templates**. Il repository non può applicarli automaticamente alle impostazioni Auth del progetto.

## Conferma email

**Subject:** Conferma il tuo indirizzo email · NaNoShift

**Body (HTML):**

```html
<!doctype html>
<html lang="it">
<body style="margin:0;padding:0;background:#f3f7fc;font-family:Arial,Helvetica,sans-serif;color:#183456;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;">Conferma il tuo indirizzo email per completare la registrazione a NaNoShift.</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f3f7fc;padding:34px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:560px;background:#ffffff;border:1px solid #e1eaf5;border-radius:22px;overflow:hidden;">
        <tr><td style="height:8px;background:#0878df;font-size:0;line-height:8px;">&nbsp;</td></tr>
        <tr><td align="center" style="padding:34px 28px 12px;">
          <div style="font-size:34px;line-height:1;font-weight:800;letter-spacing:-1.5px;color:#0b3470;">NaNo<span style="color:#f4b900;">Shift</span></div>
          <div style="font-size:13px;letter-spacing:1.3px;text-transform:uppercase;color:#71839a;margin-top:10px;">I tuoi turni, sempre con te</div>
        </td></tr>
        <tr><td style="padding:22px 34px 36px;">
          <div style="width:54px;height:54px;line-height:54px;text-align:center;border-radius:17px;background:#eaf5ff;color:#0878df;font-size:27px;margin:0 0 20px;">✓</div>
          <h1 style="font-size:25px;line-height:1.25;letter-spacing:-.5px;color:#0b3470;margin:0 0 14px;">Conferma la tua email</h1>
          <p style="font-size:15px;line-height:1.75;color:#526780;margin:0 0 22px;">Ciao,<br>grazie per esserti registrato a NaNoShift. Per completare la registrazione e verificare il tuo indirizzo, premi il pulsante qui sotto.</p>
          <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center" style="margin:28px auto;">
            <tr><td align="center" bgcolor="#0878df" style="border-radius:12px;">
              <a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:15px 28px;border-radius:12px;background:#0878df;color:#ffffff;text-decoration:none;font-size:15px;font-weight:bold;">Conferma indirizzo email</a>
            </td></tr>
          </table>
          <p style="font-size:13px;line-height:1.7;color:#71839a;margin:22px 0 0;">Se il pulsante non si apre, copia questo link nel browser:<br><a href="{{ .ConfirmationURL }}" style="color:#0878df;word-break:break-all;">{{ .ConfirmationURL }}</a></p>
          <div style="border-top:1px solid #e8eef6;margin-top:28px;padding-top:18px;font-size:12px;line-height:1.7;color:#8291a5;">Se non hai richiesto tu la registrazione, puoi ignorare questa email. Non condividere il link con altre persone.</div>
        </td></tr>
      </table>
      <p style="font-size:11px;color:#91a0b3;margin:18px 0 0;">NaNoShift · Gestione semplice dei turni</p>
    </td></tr>
  </table>
</body>
</html>
```

## Reimpostazione password

**Subject:** Reimposta la tua password · NaNoShift

**Body (HTML):**

```html
<div style="margin:0;padding:34px 12px;background:#f3f7fc;font-family:Arial,Helvetica,sans-serif;color:#183456;">
  <div style="max-width:560px;margin:0 auto;background:#fff;border:1px solid #e1eaf5;border-radius:22px;overflow:hidden;">
    <div style="height:8px;background:#0878df;"></div>
    <div style="padding:34px 30px 10px;text-align:center;"><div style="font-size:34px;font-weight:800;letter-spacing:-1.5px;color:#0b3470;">NaNo<span style="color:#f4b900;">Shift</span></div><div style="font-size:13px;letter-spacing:1.3px;text-transform:uppercase;color:#71839a;margin-top:10px;">I tuoi turni, sempre con te</div></div>
    <div style="padding:22px 34px 36px;">
      <h1 style="font-size:25px;line-height:1.25;color:#0b3470;margin:0 0 14px;">Reimposta la tua password</h1>
      <p style="font-size:15px;line-height:1.75;color:#526780;">Abbiamo ricevuto una richiesta per modificare la password del tuo account NaNoShift. Premi il pulsante qui sotto per sceglierne una nuova.</p>
      <p style="text-align:center;margin:28px 0;"><a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:15px 28px;border-radius:12px;background:#0878df;color:#fff;text-decoration:none;font-size:15px;font-weight:bold;">Crea una nuova password</a></p>
      <p style="font-size:13px;line-height:1.7;color:#71839a;">Se il pulsante non funziona, copia questo link nel browser:<br><a href="{{ .ConfirmationURL }}" style="color:#0878df;word-break:break-all;">{{ .ConfirmationURL }}</a></p>
      <div style="border-top:1px solid #e8eef6;margin-top:28px;padding-top:18px;font-size:12px;line-height:1.7;color:#8291a5;">Se non hai richiesto tu il ripristino, ignora questa email. La password non verrà modificata.</div>
    </div>
  </div>
</div>
```

## Impostazioni Auth da controllare

In **Authentication → URL Configuration**:
- **Site URL:** https://nanoshift.pages.dev
- **Redirect URLs:** aggiungere https://nanoshift.pages.dev/accesso.html (e, se si usa anche un dominio personalizzato, il corrispondente URL /accesso.html).
- Non usare come Site URL il dominio del sito personale o un vecchio URL di anteprima.

La pagina di registrazione invia già emailRedirectTo verso /accesso.html sul dominio che ospita l'app. Il link del template usa {{ .ConfirmationURL }}: non sostituire questa variabile con un URL scritto a mano.

**Nota importante:** il template nel repository è solo una bozza finché non viene incollato e salvato nella dashboard Supabase. Per l'invio affidabile a utenti reali, configurare anche un SMTP personalizzato; non inserire credenziali SMTP o chiavi segrete nel frontend o nel repository.
