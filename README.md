# NaNoShift

Applicazione web per la gestione personale dei turni e la condivisione dei turni con gruppi di colleghi.

## Pagine
- `index.html`: accesso e registrazione.
- `accesso.html`: pagina di accesso compatibile con i link di autenticazione e invito.
- `dashboard.html`: calendario, turni, riepiloghi, impostazioni del profilo, gruppi e notifiche.
- `reparto.html`: area del personale. Ingresso in un reparto con codice, disponibilità mensili, turni pubblicati e importazione nel calendario personale.
- `coordinatrice.html`: area della coordinatrice. Creazione reparto, approvazione del personale, conferma delle disponibilità, pianificazione e pubblicazione dei turni, avvisi (non disponibilità, riposo dopo la notte, oltre 6 giorni di fila) e stampa.

## Tipi di turno
- `M`: Mattina (07:00–14:00 come orario predefinito).
- `P`: Pomeriggio (14:00–19:00 come orario predefinito).
- `G`: Giornata (07:00–19:00 come orario predefinito).
- `N`: Notte (19:00–07:00 come orario predefinito).
- `R`: Riposo (nessuna ora lavorata e nessun compenso conteggiato).

Gli orari predefiniti possono essere adattati per i singoli turni; il riposo viene sempre conteggiato come zero ore.

## Identità visiva
- `nanoshift-logo.svg`: logo completo blu e giallo, vettoriale.
- `favicon.svg`, `favicon.ico`, `favicon-16.png`, `favicon-32.png`, `favicon-192.png`, `favicon-512.png`: icone browser.
- `nanoshift-icon.png`: icona ad alta risoluzione.
- `apple-touch-icon.png`: icona per i dispositivi Apple.

## Backend
Il progetto usa Supabase Auth e Postgres con policy RLS. Le migrazioni versionate si trovano in `supabase/migrations/`. In particolare, le migrazioni più recenti aggiungono le notifiche/inviti ai gruppi, correggono la ricorsione delle policy RLS e introducono il tipo di turno `R`.

## Sezione coordinatrice: migrazione da applicare
La migrazione `supabase/migrations/20261031120000_coordinator_section.sql` crea le tabelle `coord_*` (reparti, personale, disponibilità, turni assegnati), le policy RLS e le funzioni RPC. Va eseguita sul database Supabase del progetto (SQL Editor o `supabase db push`) prima di usare `reparto.html` e `coordinatrice.html`; finché non è applicata le due pagine mostrano un errore esplicito.

## Pubblicazione
Cloudflare Pages è collegato alla repository GitHub `luiginva97/NaNo-Shift`, con ramo di produzione `main` e directory radice `/`. I push su `main` avviano il deployment automatico.
