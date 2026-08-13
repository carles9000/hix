# HIX AI System

**Stato**: 🟢 v0.2.0 — Binary-first

Strumenti alimentati dall'AI per aiutarti a costruire applicazioni HIX con Claude Code.

**Inizia in 5 minuti → [QUICKSTART.md](QUICKSTART.md)** · [ES](QUICKSTART.es.md)

**Aggiorni da v0.1? → [MIGRATE-v0.2.md](MIGRATE-v0.2.md)** · [ES](MIGRATE-v0.2.es.md)

## Cos'è?

Una raccolta di asset di Claude Code (skill, agent, slash command, knowledge base) che permettono a Claude di generare codice HIX corretto e idiomatico per il tuo progetto.

HIX v0.2 è **binary-first**: ricevi `hix.exe` + DLL + una cartella vuota, e l'AI System fa lo scaffolding della app `www/` sopra. **Non serve compilazione** per il flusso predefinito - `hix.exe` ricompila i tuoi file `.prg` in memoria a ogni richiesta.

Una volta installato, puoi chiedere a Claude cose come:
- *"Inizializza un'app HIX chiamata MyNotes"*
- *"Aggiungi un modulo CRUD per `Note`"*
- *"Aggiungi una route `GET /ping` e un middleware che richieda una API key"*
- *"Fai la review di questo progetto secondo le best practice HIX"*

Claude fa lo scaffolding dei file, li collega al `hix.exe` in esecuzione, ed esegue test HTTP dichiarativi contro il server live - riporta OK solo quando ogni test passa.

## Cosa c'è in v0.2.0

- **6 skill** — `hix-init` (predefinita), `hix-add-crud`, `hix-add-route`, `hix-add-middleware`, `hix-run-tests`, `hix-scaffold-source` (legacy)
- **7 slash command** — `/hix-init`, `/hix-add-crud`, `/hix-add-route`, `/hix-add-middleware`, `/hix-test`, `/hix-review`, `/hix-scaffold-source`
- **4 agent** — `hix-architect` (design), `hix-router-expert` (route), `hix-view-builder` (view), `hix-reviewer` (audit)
- **4 template** — `project-www` (binary-first), `project-web-crud` (source-first), `module-crud`, `module-route`, `module-middleware`
- **Test runner dichiarativo** — file `*.test.json` verificati da `tests/run-live.ps1` contro un `hix.exe` live
- **Knowledge base** — 12 doc EN + 12 doc ES che coprono routing, middleware, controller, view, model, validazione, sessioni/auth, hixstyle, helper `U*`, regole Harbour

## Requisiti

- CLI [Claude Code](https://claude.com/claude-code) installata
- Windows 10/11 con:
  - **Developer Mode abilitato** (consigliato, permette i symlink senza admin), oppure
  - Capacità di eseguire PowerShell come Amministratore (solo durante l'install)
- Una distribuzione binaria di HIX (tipicamente `C:\hix\` con `hix.exe`, `hix.json` e le DLL richieste)

Il source-first (legacy) richiede in aggiunta Harbour + hbmk2 per compilare il tuo `.exe`. Non richiesto per il flusso predefinito.

## Install

    cd C:\hix\ia          # o ovunque tu abbia estratto il bundle AI System
    .\scripts\install.bat C:\MyProject

(Per dettagli e invocazione diretta di PowerShell vedi [INSTALL.md](INSTALL.md).)

Questo:
1. Symlinka `~\.claude\{skills,agents,commands}\hix-*` → il repo AI System (aggiornamenti via `git pull` si propagano istantaneamente).
2. Renderizza `~\.claude\hix-claude-rendered.md` con `{{HIX_ROOT}}` espanso al tuo path di install reale.
3. Crea/append `C:\MyProject\CLAUDE.md` con un `@import` al file renderizzato.
4. Scrive `C:\MyProject\.claude\settings.local.json` con i permessi che le skill necessitano (PowerShell / Bash / curl), così Claude Code non chiede per ogni comando.

Poi, dalla cartella che contiene `hix.exe`:

    cd C:\hix
    claude
    > /hix-init MyApp
    > /hix-add-crud Note
    > /hix-test

Per il walkthrough completo di 5 minuti vedi [QUICKSTART.md](QUICKSTART.md).

## Source-first (legacy)

Se costruisci il tuo `.exe` linkato contro `hix_server.lib` (richiede Harbour + hbmk2), usa:

    > /hix-scaffold-source MyApp

Questo genera lo scheletro `app.hbp` + `src/app.prg` + `go.bat`. Da quel momento in poi, tutto il resto (`/hix-add-crud`, `/hix-add-route`, `/hix-add-middleware`, `/hix-test`) funziona allo stesso modo - ma l'AI System non gestirà la tua build. Esegui `go.bat build` per conto tuo prima di invocare `/hix-test`.

## Architettura (referenziata, non copiata)

Gli asset vivono in questo repo (`hix/ia/claude/`) e sono **referenziati** dalla tua directory utente di Claude Code (`~/.claude/`) tramite symlink. Quando fai `git pull` in questo repo, il tuo Claude riceve l'aggiornamento istantaneamente - niente da reinstallare (tranne quando cambia il `CLAUDE.md` renderizzato stesso; in quel caso riesegui `install.bat`).

## Uninstall

    cd C:\hix\ia
    .\scripts\uninstall.bat C:\MyProject

Vedi [UNINSTALL.md](UNINSTALL.md) per i dettagli.

## Documentazione

- [QUICKSTART.md](QUICKSTART.md) — onboarding di 5 minuti (EN) · [ES](QUICKSTART.es.md)
- [INSTALL.md](INSTALL.md) — guida di install dettagliata (EN) · [ES](INSTALL.es.md)
- [UNINSTALL.md](UNINSTALL.md) — guida alla disinstallazione (EN) · [ES](UNINSTALL.es.md)
- [CONTRIBUTING.md](CONTRIBUTING.md) — come aggiungere skill / agent / command (EN) · [ES](CONTRIBUTING.es.md)
- `knowledge/` — knowledge base che Claude legge (12 doc EN + 12 doc ES)
- `templates/` — scheletri di progetto + modulo che Claude applica
- `tests/` — test runner dichiarativo + self-test forniti
- [claude/agents/README.md](claude/agents/README.md) — indice degli agent
- [claude/commands/README.md](claude/commands/README.md) — indice dei slash command
- [claude/skills/README.md](claude/skills/README.md) — indice delle skill
- [CHANGELOG.md](CHANGELOG.md) — cronologia delle versioni
- Spagnolo · [README.es.md](README.es.md)

## Verificato end-to-end (v0.2.0)

Install fresca di `C:\hix` con solo `hix.exe` + DLL:
- `/hix-init MyApp` → `/health` ritorna 200, nessun prompt
- `/hix-add-crud Note` → **7/7 test passano**
- `/hix-add-route Ping /ping GET` → **2/2 test passano**
- `/hix-add-middleware RequireApiKey` → **2/2 test passano**
- `/hix-test` suite completa → **11/11 test passano**

## Licenza

Stessa di HIX — vedi `../license.md`
