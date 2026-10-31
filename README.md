# NaNoShift

Applicazione web per la gestione personale dei turni e la condivisione dei turni con gruppi di colleghi.

## Pagine
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
