# NaNo Shift — template email Supabase (bozza da applicare)

Questi template sono pronti da copiare in Supabase Dashboard → Authentication → Email Templates.
**Prima di attivarli:** aggiungere il logo corretto di NaNo Shift come immagine PNG/JPG pubblica su un URL HTTPS stabile e sostituire il blocco LOGO indicato qui sotto. Non usare il favicon SVG come sostituto del logo ufficiale finché non è stato confermato.

## Conferma email

**Subject:** Conferma il tuo indirizzo email · NaNo Shift

**Body (HTML):**
```html
<div style="margin:0;padding:32px 12px;background:#f4f7fb;font-family:Arial,Helvetica,sans-serif;color:#173052;">
  <div style="max-width:560px;margin:0 auto;background:#ffffff;border:1px solid #e0e8f2;border-radius:20px;overflow:hidden;">
    <div style="padding:28px 28px 8px;text-align:center;">
      <!-- LOGO NaNo Shift: inserire qui <img src="URL_HTTPS_LOGO" alt="NaNo Shift" width="150" style="display:block;width:150px;max-width:100%;height:auto;margin:0 auto 18px;"> -->
      <div style="font-size:25px;font-weight:700;letter-spacing:-.5px;color:#173052;">NaNo Shift</div>
      <div style="font-size:13px;color:#667995;margin-top:6px;">Gestione dei turni, con semplicità</div>
    </div>
    <div style="padding:22px 30px 32px;">
      <h1 style="font-size:23px;line-height:1.3;margin:0 0 14px;color:#173052;">Conferma la tua email</h1>
      <p style="font-size:15px;line-height:1.7;margin:0 0 22px;color:#465a75;">Ciao, grazie per esserti registrato su NaNo Shift. Per completare la creazione del tuo account, conferma che questo indirizzo email appartiene a te.</p>
      <p style="text-align:center;margin:28px 0;">
        <a href="{{ .ConfirmationURL }}" style="display:inline-block;background:#2463c5;color:#ffffff;text-decoration:none;font-weight:700;font-size:15px;padding:14px 24px;border-radius:12px;">Conferma indirizzo email</a>
      </p>
      <p style="font-size:13px;line-height:1.7;color:#667995;margin:20px 0 0;">Se il pulsante non funziona, copia questo indirizzo nella barra del browser:<br><a href="{{ .ConfirmationURL }}" style="color:#2463c5;word-break:break-all;">Conferma email</a></p>
      <div style="border-top:1px solid #e8edf5;margin-top:26px;padding-top:18px;font-size:12px;line-height:1.6;color:#78879c;">Se non hai creato tu un account NaNo Shift, puoi ignorare questa email. Per motivi di sicurezza, non inoltrare questo messaggio.</div>
    </div>
  </div>
</div>
```

## Reimpostazione password

**Subject:** Reimposta la tua password · NaNo Shift

**Body (HTML):**
```html
<div style="margin:0;padding:32px 12px;background:#f4f7fb;font-family:Arial,Helvetica,sans-serif;color:#173052;">
  <div style="max-width:560px;margin:0 auto;background:#ffffff;border:1px solid #e0e8f2;border-radius:20px;overflow:hidden;">
    <div style="padding:28px 28px 8px;text-align:center;">
      <!-- LOGO NaNo Shift: inserire qui <img src="URL_HTTPS_LOGO" alt="NaNo Shift" width="150" style="display:block;width:150px;max-width:100%;height:auto;margin:0 auto 18px;"> -->
      <div style="font-size:25px;font-weight:700;letter-spacing:-.5px;color:#173052;">NaNo Shift</div>
      <div style="font-size:13px;color:#667995;margin-top:6px;">Gestione dei turni, con semplicità</div>
    </div>
    <div style="padding:22px 30px 32px;">
      <h1 style="font-size:23px;line-height:1.3;margin:0 0 14px;color:#173052;">Reimposta la tua password</h1>
      <p style="font-size:15px;line-height:1.7;margin:0 0 22px;color:#465a75;">Abbiamo ricevuto una richiesta per modificare la password del tuo account NaNo Shift. Premi il pulsante qui sotto per scegliere una nuova password.</p>
      <p style="text-align:center;margin:28px 0;">
        <a href="{{ .ConfirmationURL }}" style="display:inline-block;background:#2463c5;color:#ffffff;text-decoration:none;font-weight:700;font-size:15px;padding:14px 24px;border-radius:12px;">Crea una nuova password</a>
      </p>
      <p style="font-size:13px;line-height:1.7;color:#667995;margin:20px 0 0;">Se il pulsante non funziona, copia questo indirizzo nella barra del browser:<br><a href="{{ .ConfirmationURL }}" style="color:#2463c5;word-break:break-all;">Reimposta password</a></p>
      <div style="border-top:1px solid #e8edf5;margin-top:26px;padding-top:18px;font-size:12px;line-height:1.6;color:#78879c;">Se non hai richiesto tu il ripristino, ignora questa email: la password non verrà modificata. Non condividere questo link con nessuno.</div>
    </div>
  </div>
</div>
```

## Invito utente Supabase (se usato)

**Subject:** Hai ricevuto un invito · NaNo Shift

**Body (HTML):**
```html
<div style="margin:0;padding:32px 12px;background:#f4f7fb;font-family:Arial,Helvetica,sans-serif;color:#173052;">
  <div style="max-width:560px;margin:0 auto;background:#ffffff;border:1px solid #e0e8f2;border-radius:20px;overflow:hidden;">
    <div style="padding:28px 28px 8px;text-align:center;">
      <!-- Inserire il logo ufficiale NaNo Shift come immagine HTTPS quando disponibile -->
      <div style="font-size:25px;font-weight:700;letter-spacing:-.5px;color:#173052;">NaNo Shift</div>
    </div>
    <div style="padding:22px 30px 32px;">
      <h1 style="font-size:23px;line-height:1.3;margin:0 0 14px;color:#173052;">Sei stato invitato</h1>
      <p style="font-size:15px;line-height:1.7;margin:0 0 22px;color:#465a75;">Hai ricevuto un invito a entrare in NaNo Shift. Usa il pulsante qui sotto per continuare.</p>
      <p style="text-align:center;margin:28px 0;"><a href="{{ .ConfirmationURL }}" style="display:inline-block;background:#2463c5;color:#ffffff;text-decoration:none;font-weight:700;font-size:15px;padding:14px 24px;border-radius:12px;">Accetta invito</a></p>
      <div style="border-top:1px solid #e8edf5;margin-top:26px;padding-top:18px;font-size:12px;line-height:1.6;color:#78879c;">Se non ti aspettavi questo invito, puoi ignorare questa email.</div>
    </div>
  </div>
</div>
```

## Note di configurazione

- I template si incollano in Supabase Dashboard → Authentication → Email Templates.
- La conferma e il reset password usano `{{ .ConfirmationURL }}`; non rinominare questa variabile.
- Verificare gli URL consentiti in Authentication → URL Configuration e impostare il Site URL corretto.
- Per inviare email a utenti reali, configurare un SMTP personalizzato. Non inserire API key o password SMTP nel frontend o in questo repository.
- Disabilitare il click tracking del provider per evitare che riscriva i link di autenticazione.
- La versione con logo non è definitiva finché non viene fornito/confermato il file del logo ufficiale.
