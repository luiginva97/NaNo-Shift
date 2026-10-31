# NaNoShift

Applicazione web per la gestione personale dei turni e la condivisione dei turni con gruppi di colleghi.

## Pagine
- `demo.html`: demo pubblica interattiva, con dati sintetici e funzioni simulate, separata da Supabase. Riutilizza le icone SVG, il marchio e la navigazione responsive condivisi (`nav.js`, `nav.css`, `ui.css`) per mantenere la stessa cornice grafica dell'app reale.
- `index.html`: accesso e registrazione.
- `accesso.html`: pagina di accesso compatibile con i link di autenticazione e invito.
- `dashboard.html`: calendario, turni, riepiloghi, impostazioni del profilo, gruppi e notifiche.
- `reparto.html`: area del personale. Ingresso in un reparto con link di invito personale o con codice (scegliendo ruolo Infermiere/OSS), disponibilità mensili, turni pubblicati e importazione nel calendario personale.
- `coordinamento.html`: area della coordinatrice/coordinatore. Creazione reparto, inviti con link personali (ruolo Infermiere/OSS, validi 14 giorni, monouso), approvazione del personale, ruoli visibili e modificabili, conferma delle disponibilità, generazione bozza e pianificazione dei turni, pubblicazione, avvisi (non disponibilità, riposo dopo la notte, oltre 6 giorni di fila), totali ore e stampa.
- `ui.css`: stile condiviso (intestazione, navigazione mobile con menu «Altro», menu «Strumenti» del calendario, tabelle, accessibilità). Viene caricato dopo gli stili inline delle pagine.

## Tipi di turno
- `M`: Mattina (07:00–14:00 come orario predefinito).
- `P`: Pomeriggio (14:00–19:00 come orario predefinito).
- `G`: Giornata (07:00–19:00 come orario predefinito).
- `N`: Notte (19:00–07:00 come orario predefinito).
- `R`: Riposo (nessuna ora lavorata e nessun compenso conteggiato).

Gli orari predefiniti possono essere adattati per i singoli turni; il riposo viene sempre conteggiato come zero ore.

## Identità visiva
- `nanoshift-logo.png`: logo completo (icona, nome e payoff), usato nelle pagine di accesso.
- `favicon-192.png`: solo icona, usata nelle intestazioni interne.
- `favicon.ico`, `favicon-16.png`, `favicon-32.png`, `favicon-512.png`, `apple-touch-icon.png`: icone browser e dispositivi Apple.

## Backend
Il progetto usa Supabase Auth e Postgres con policy RLS. Le migrazioni versionate si trovano in `supabase/migrations/`. In particolare, le migrazioni più recenti aggiungono le notifiche/inviti ai gruppi, correggono la ricorsione delle policy RLS e introducono il tipo di turno `R`.

## Sezione coordinatrice
Usa le tabelle `units`, `unit_members`, `unit_availability` e `unit_shifts` e le funzioni `create_unit`, `request_join_unit`, `get_my_units`, `get_unit_roster`, `review_unit_member`, `review_unit_availability`, `publish_unit_shifts`, già presenti nel database Supabase (migrazione `unit_planning`, applicata direttamente sul progetto e non ancora versionata in `supabase/migrations/`). Il codice di ingresso del reparto è di 8 caratteri.

## Pubblicazione
Cloudflare Pages è collegato alla repository GitHub `luiginva97/NaNo-Shift`, con ramo di produzione `main` e directory radice `/`. I push su `main` avviano il deployment automatico.


### Inviti al reparto e ruoli
Migrazione `20261031140000_unit_invitations_and_staff_roles.sql`: colonna `unit_members.staff_role` (infermiere|oss), tabella `unit_invitations` (solo hash SHA-256 del token), funzioni `create_unit_invitation`, `revoke_unit_invitation`, `preview_unit_invitation`, `accept_unit_invitation`; `request_join_unit` e `get_unit_roster` ora gestiscono il ruolo. Il link è `accesso.html?unit_invite=TOKEN` e dopo il login porta a `reparto.html`. **Va applicata al database prima di pubblicare il frontend.**


### Menu condiviso
`nav.js` + `nav.css` definiscono un solo menu (colonna laterale su desktop, barra in basso con "Altro" su telefono) usato da dashboard, reparto e coordinamento. L'ordine delle voci si cambia da Dati utente → Ordine del menu (salvato in `profiles.feature_preferences.nav_order`) e i toggle di Funzionalità nascondono le voci in tutte le pagine. Le coordinatrici aprono su Coordinamento; l'area personale è `dashboard.html?area=personale`.


### Master amministrativo e uscita dal reparto
Migrazione `20261031220000_master_account_and_leave_unit.sql`: definisce `private.is_master()` (admin senza alcuna iscrizione a reparti), estende `is_unit_coordinator()` al master, aggiunge la policy `units_select_master`, fa restituire a `get_my_units()` tutti i reparti al master senza creare iscrizioni e introduce `leave_unit(p_unit)`. La RPC di uscita elimina le disponibilità e i turni di reparto della persona, ma non i turni già importati nel calendario personale; impedisce alla sola coordinatrice di uscire finché non viene nominata un'altra coordinatrice. Il master che è anche membro resta un membro ordinario.

### Preferenze, contatti e dashboard personale
La voce Documenti del menu usa ora la preferenza `documents`; in Dati utente è disponibile il toggle “Documenti e scadenze”. Le preferenze non presenti restano abilitate (`!== false`). La descrizione di Reparto include disponibilità, turni pubblicati e contatti. La dashboard saluta la persona usando nome e, in fallback, nome visualizzato. I pulsanti WhatsApp in Reparto e Coordinamento mostrano un'icona SVG accessibile. Reparto offre “Lascia il reparto” con conferma e gestione dell'errore restituito dalla RPC.


### Scadenze reparto, copertura e approvazione cambi turno
La migrazione `20261031221643_shift_approval_coverage_and_expiries` introduce lo stato `pending_approval`: il destinatario può accettare la proposta, ma lo scambio dei turni pubblicati avviene solo dopo l'approvazione della coordinatrice tramite `review_unit_shift_swap`. La RPC invia anche notifiche in-app ai coordinatori. Nel planning le righe “M/P/G/N disponibili” contano le disponibilità confermate (inclusa la preferenza ANY), mentre “coperti” continua a mostrare i turni già assegnati. La scheda Scadenze mostra alla coordinatrice solo nome, tipo e data degli attestati non sanitari entro 90 giorni o già scaduti; non espone file né idoneità sanitarie.

### Protezione dei dati di idoneità
NaNoShift non raccoglie né memorizza date di idoneità sanitaria e non prevede il caricamento di certificati sanitari. La migrazione `20261031233505_remove_medical_fitness_tracking` rimuove la tabella privata e le RPC dedicate, elimina il tipo documento sanitario e mantiene le notifiche di scadenza esclusivamente per BLSD, iscrizione all'Ordine e antincendio. I documenti professionali restano in bucket privato; il CV è condiviso solo tramite opt-in esplicito.

### Notifiche push (senza email)
Le migrazioni `20261031230000_web_push_notifications`, `20261031231500_push_vapid_server_setup` e `20261031232000_push_subscription_and_schedule` aggiungono sottoscrizioni Web Push, chiavi VAPID generate sul server e conservate in Supabase Vault, e un job ogni 5 minuti che invia notifiche generiche senza dettagli sanitari sul lock screen. I promemoria di scadenza vengono generati ogni giorno alle 06:15 UTC, includendo anche la soglia di un giorno prima; il dispatcher push controlla le notifiche in attesa. Il client usa `push.js` e `sw.js`; l'utente deve autorizzare le notifiche dal dispositivo. Su iOS/iPadOS è necessario aggiungere la PWA alla schermata Home.


### Stato privacy e sicurezza (01/11/2026)
L'informativa privacy versione 1.0 è pubblicata e collegata dalla landing e dalla pagina di accesso. La registrazione non raccoglie un consenso generico: per i dati del personale la struttura titolare individua la base giuridica e fornisce la propria informativa; il rapporto con NaNoShift deve essere formalizzato con accordo ex art. 28 GDPR prima dell'uso operativo. La funzione di raccolta dell'idoneità sanitaria è stata rimossa dal frontend e dal database. La migrazione `20261031222352_push_settings_service_policy` aggiunge la policy interna di lettura per il solo ruolo di servizio.

La protezione Supabase contro password compromesse resta disattivata: l'organizzazione del progetto è sul piano Free e la funzione richiede Pro o superiore. L'Advisor segnala inoltre l'estensione `pg_net` nello schema `public` (non relocatable) e avvisi generici su funzioni `SECURITY DEFINER`; le RPC introdotte applicano controlli espliciti su proprietario, destinatario o coordinatrice e le funzioni di configurazione push sono riservate a `service_role`.

La migrazione `20261031233500_notify_swap_accepted` aggiunge una seconda notifica alla coordinatrice quando il destinatario accetta il cambio, così il passaggio alla coda di approvazione produce un nuovo avviso push oltre a quello iniziale.

### Informativa privacy (versione 1.0)
`privacy.html` pubblica l'informativa versione 1.0 e descrive Supabase (backend, database e autenticazione; progetto nella regione AWS eu-central-1/Francoforte), Cloudflare Pages (hosting/distribuzione dell'interfaccia) e i servizi push del browser/dispositivo. La pagina distingue il ruolo della struttura sanitaria, titolare dei dati del proprio personale, da quello di NaNoShift quale responsabile del trattamento in base all'accordo previsto dall'art. 28 GDPR; Luigi Narvaez resta titolare autonomo per i trattamenti propri del sito, dei contatti e della sicurezza. L'app non raccoglie date di idoneità e non consente il caricamento di certificati sanitari. La versione pubblicata descrive il modello previsto e non sostituisce la formalizzazione degli accordi con ogni struttura né la verifica delle condizioni contrattuali dei fornitori prima dell'uso operativo.
