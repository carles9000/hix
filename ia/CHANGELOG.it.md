# Changelog

Tutte le modifiche rilevanti all'HIX AI System saranno documentate in questo file.

Formato: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versionamento: allineato con i tag git (`ia-vX.Y.Z`)

---

## [Unreleased]

_(nessuna modifica ancora)_

---

## [0.2.1] — 2026-08-09 — Guida alla migrazione + auto-bootstrap di hix-init

Release minore: aggiunge la guida di migrazione da v0.1 a v0.2 e rimuove l'ultimo step manuale dall'onboarding (bootstrap di `hix.json`).

### Aggiunto

- **Guida alla migrazione `MIGRATE-v0.2.md` (+ `.es.md`)** - percorso di upgrade passo-passo da v0.1. Copre due scenari (resta source-first, passa a binary-first), una checklist di verifica, troubleshooting per i punti di rottura più comuni, e una FAQ.
- **`README.md` + `README.es.md`** - puntatore all'upgrade alla nuova guida di migrazione, subito sotto il link al QUICKSTART.

### Modificato

- **Pre-flight della skill `hix-init`** - non richiede più che `hix.json` esista nel root target. Se manca, la skill avvia `hix.exe` brevemente per fargli auto-generare la config di default, poi ferma il processo prima di continuare. Rimuove uno step manuale dall'onboarding.

### Verificato end-to-end

Protocollo completo di validazione in 6 step (`/hix-init` → `/hix-add-crud` → `/hix-add-route` → `/hix-add-middleware` → `/hix-test` → `/hix-review`) passato su un'install fresca di `C:\hix` il 2026-08-09.

---

## [0.2.0] — 2026-08-08 — Binary-first

Riorientamento maggiore: HIX è ora distribuito come `hix.exe` + DLL + cartella vuota. L'AI System fa lo scaffolding di `www/` sopra quel binario precompilato; **non serve compilazione** per il flusso predefinito. `hix.exe` ricompila a caldo `www/controllers|models|views/*.prg` per richiesta. Il source-first (compilare il proprio `.exe` linkato contro `hix_server.lib`) è preservato come opt-in legacy via `/hix-scaffold-source`.

### Aggiunto

- **Skill `hix-init`** (predefinita) - avvia un'app hixstyle dentro una cartella che contiene già `hix.exe`. Applica `templates/project-www/`, abilita `hixstyle` in `hix.json`, avvia `hix.exe` in background, verifica che `/health` ritorni 200. Zero prompt all'utente in caso di successo.
- **Slash command `/hix-init`** - wrapper sottile per la skill sopra.
- **Template `templates/project-www/`** - overlay binary-first minimale: `www/{config.json,index.html,public/,controllers/,models/,views/,routes/,middlewares/,loaders/}`. Token: `{{PROJECT_NAME}}`, `{{AUTHOR}}`, `{{DATE}}`, `{{HIX_ROOT}}`.
- **Live-runner dichiarativo `tests/run-live.ps1`** - riusa un `hix.exe` in esecuzione (o ne avvia uno via `hix.exe --serve`), esegue i `*.test.json` contro la porta live, demolisce solo ciò che ha lanciato. Exit code: 0 passa, N fallimenti, 2 input non valido, 4 timeout del server. **Nessuna fase di build, nessun patch della porta in `hix.json`.**
- **Tokenizzazione `{{HIX_ROOT}}` in `claude/CLAUDE.md`** - render al momento dell'install in `~\.claude\hix-claude-rendered.md` con il path reale del root HIX espanso. Rimuove la precedente assunzione hard-coded `C:\HIX.PROJECT\hix\`.
- **Writer di `.claude/settings.local.json` in `scripts/install.ps1`** - aggiunge `Bash(powershell.exe *)`, `PowerShell(*)`, `Bash(curl.exe *)` e voci correlate a `permissions.allow` così Claude Code non chiede per ogni comando che le skill invocano. Idempotente.

### Modificato

- **Skill/command `hix-scaffold` rinominata in `hix-scaffold-source`** - chiaramente marcata come percorso legacy source-first. Mantenuta per gli utenti che compilano il proprio `.exe` linkato contro `hix_server.lib` (richiede Harbour + hbmk2).
- **`scripts/install.ps1`** - ora renderizza il template master `CLAUDE.md` (sostituisce `{{HIX_ROOT}}`) in `~\.claude\hix-claude-rendered.md` al momento dell'install; il `CLAUDE.md` del progetto importa il file renderizzato, non il master.
- **`claude/CLAUDE.md` + `claude/CLAUDE.es.md`** - riscrittura completa. Tutti i path usano `{{HIX_ROOT}}`. La sezione compilazione spiega il binary-first di default con una nota legacy sul source-first. La tabella delle skill ora elenca `hix-init` prima e include `hix-run-tests`; la tabella dei command aggiunge `/hix-init` e marca `/hix-scaffold-source` come legacy. Rimosse regole che si applicano solo al flusso source-first (gestione custom di `.hbx`, `Start()` + `hb_threadJoin` nel codice utente).
- **Skill `hix-run-tests`** (rinominata da `hix-compile-and-test`) - nessuno step di build. Wrappa `tests/run-live.ps1`. Passa `--restart` quando il chiamante segnala che `hix.json` / `www/routes/*.json` / `www/loaders/*.prg` sono cambiati dall'ultima esecuzione.
- **Tutti i doc delle skill `hix-add-*`** - i link "creare un nuovo progetto" ora puntano a `hix-init` (predefinito) o `hix-scaffold-source` (legacy). Rimossi i riferimenti obsoleti a `hix-compile-and-test`.
- **`claude/skills/README.md` e `claude/commands/README.md`** - indici divisi in tabelle "Flusso predefinito (binary-first)" e "Legacy (source-first)".
- **Doc: `README.md`, `README.es.md`, `QUICKSTART.md`, `QUICKSTART.es.md`, `INSTALL.md`, `INSTALL.es.md`** - riscrittura completa per il canone binary-first. Harbour + hbmk2 esplicitamente rimossi dai prerequisiti predefiniti. L'onboarding di 5 minuti passa per `/hix-init` → `/hix-add-crud` → `/hix-add-route` → `/hix-add-middleware` → `/hix-test` → `/hix-review`. Verificato end-to-end: **11/11 test passano** su un'install fresca di `C:\hix`.

### Rimosso

- **Skill `hix-compile-and-test`** - eliminata; sostituita da `hix-run-tests` (nessuna build). La fase di build della vecchia skill non ha senso quando `hix.exe` è precompilato e controller/model/view si ricompilano per richiesta.

---

## [0.1.0] — 2026-08-07

Prima release pubblica. Tutte le 8 sessioni del build scoped complete; sistema esercitato end-to-end contro un progetto scratch pulito.

### Highlight

- **5 skill** - `hix-scaffold`, `hix-add-crud`, `hix-add-route`, `hix-add-middleware`, `hix-compile-and-test`.
- **6 slash command** - `/hix-scaffold`, `/hix-add-crud`, `/hix-add-route`, `/hix-add-middleware`, `/hix-test`, `/hix-review`.
- **4 agent** - `hix-architect` (design, read-only), `hix-router-expert` (route, edit + build/test), `hix-view-builder` (view, edit), `hix-reviewer` (audit, read-only).
- **4 template** - `project-web-crud`, `module-crud`, `module-route`, `module-middleware`.
- **Test runner dichiarativo** - schema `*.test.json` + `tests/run.ps1` (build, spawn, poll, itera, teardown, ripristina `hix.json`; exit 0 = passa, N = fallimenti).
- **Knowledge base** - 24 doc tematici (12 EN + 12 ES) che coprono overview, layout, routing, middleware, controller, view, model, validazione, sessioni/auth, hixstyle, helper `U*`, regole Harbour.
- **Doc** - README + INSTALL + UNINSTALL + CONTRIBUTING + QUICKSTART, tutti in EN e ES.

### Verificato end-to-end

Progetto scratch fresco in `C:\tmp\hix-e2e-v01\` (2026-08-07):
- `apply-template project-web-crud` → 10 file → `go.bat build` exit 0.
- `apply-template module-crud Note` + `render-tests` (7 test) → `run.ps1` → **7/7 passano, exit 0**.

Test forniti con le skill verificati nelle sessioni precedenti:
- `hix-add-route Ping /ping GET` → **2/2 passano** (200 JSON + 405 metodo sbagliato).
- `hix-add-middleware RequireApiKey` → **2/2 passano** (401 senza header + 200 con header).

### Rimandato al backlog

- `templates/project-api-class`, `templates/project-api-function` - rimandati (S3.5, S3.6); pattern già estensibile via `apply-template.ps1`.
- Supporto Cursor / Windsurf, telemetria, template aggiuntivi, framework-lint CI, distribuzione via `hbmk2 -pkg`, migrazione al repo standalone `hix-ia` (B1-B6).

### Dettaglio sessione per sessione

### Aggiunto — Sessione 7 (2026-08-07)

- `claude/agents/hix-architect.md` - agent di design read-only (tools: Read/Grep/Glob/WebFetch). Trasforma una descrizione fuzzy dell'app in una lista ordinata di invocazioni `/hix-scaffold` + `/hix-add-crud` + `/hix-add-route` + `/hix-add-middleware`, con tabelle entity/route/middleware e una sezione rischi. Non fa mai scaffolding né modifiche.
- `claude/agents/hix-router-expert.md` - chirurgo delle route (tools: Read/Grep/Glob/Bash/Edit/Write). Gestisce gruppi di route, `:var` regex, composizione della catena middleware, debug di precedenza. Dimostra ogni cambio con `go.bat build` + `tests/run.ps1`.
- `claude/agents/hix-view-builder.md` - agent per template + wiring del controller (tools: Read/Write/Edit/Grep/Glob). Porta HTML in `.view.html`, estrae partial, collega gli argomenti posizionali di `@args` correttamente. Non tocca mai route/middleware.
- `claude/agents/hix-reviewer.md` - agent di code-review (tools: Read/Grep/Glob only - no Write/Edit/Bash). Cammina lungo una checklist di regole pubbliche Harbour + HIX (posizionamento di LOCAL, `!=` sulle stringhe, `hb_UnixTime`, formato action `controllers/METHOD@CLASS.prg`, `Start()`+join, argomenti posizionali di `USendView`, registrazione MW via loaders, ACL whitelist) e produce findings per severità con citazioni `file:line`.
- `claude/agents/README.md` - indice dei 4 agent con tabella tools/scrittura-files, anatomia di un agent (campi del frontmatter), principi di design (un ruolo per agent, restringi i tool per intento, referenzia la knowledge base pubblica), e tabella di decisione skill-vs-agent-vs-command.
- `claude/commands/hix-review.md` - slash command che invoca `hix-reviewer` via il tool `Task`. Chiude l'elemento rimandato S6.5.
- `claude/commands/README.md` - aggiunta riga `/hix-review` + sezione "Note su `/hix-review`" che spiega la distinzione agent-vs-skill; rimossa la sezione `Planned`.

### Verificato — Sessione 7

- Tutti i 5 file creati (4 agent + agents README) con frontmatter valido (`name`, `description`, `tools`). La tool list del reviewer è intenzionalmente read-only.
- Il frontmatter di `/hix-review` include `description` e `argument-hint` coerenti con gli altri wrapper di command.
- Lo smoke test interattivo (invocare `Task(subagent_type="hix-architect", ...)` ecc. e confermare che Claude Code riconosca ogni agent) è uno step manuale - non può essere automatizzato dall'interno di questa sessione.

### Aggiunto — Sessione 6 (2026-08-07)

- `claude/commands/hix-scaffold.md` - wrapper di una riga per la skill `hix-scaffold`. Frontmatter: `description` + `argument-hint: <project-name>`. Parsing di `$ARGUMENTS` posizionalmente (token 1 = nome progetto).
- `claude/commands/hix-add-crud.md` - wrappa `hix-add-crud`. Argomento: `<entity-pascalcase>`. Rifiuta nomi con spazi / non-ASCII / cifra iniziale.
- `claude/commands/hix-add-route.md` - wrappa `hix-add-route`. Argomenti: `<name> <url> [method]`. Forza URL che inizia con `/` e method ∈ `GET|POST|PUT|DELETE|PATCH`.
- `claude/commands/hix-add-middleware.md` - wrappa `hix-add-middleware`. Argomenti: `<name> [probe-url]`. URL di probe di default è `/__mw_probe_<name_lower>`.
- `claude/commands/hix-test.md` - wrappa `hix-compile-and-test`. Argomento: `[project-path]` (default a cwd; deve contenere `hix.json`, `www/`, `go.bat`).
- `claude/commands/README.md` - indice con tabella di mappatura command→skill, esempi, razionale "perché così sottili?", istruzioni di install, nota sul command `/hix-review` rimandato.

### Rimandato — Sessione 6

- `/hix-review` - rimandato alla Sessione 7. Uno slash command che punta a un agent `hix-reviewer` non esistente sarebbe un link morto, quindi arriva insieme all'agent stesso.

### Verificato — Sessione 6

- Tutti i 6 file creati con frontmatter valido (`description` + `argument-hint`) e struttura coerente. Lo smoke test interattivo (digitare `/hix-scaffold`, `/hix-add-crud`, ecc. in una sessione Claude Code fresca dopo `scripts/install.bat`) è uno step manuale - non può essere automatizzato dall'interno di questa sessione.

### Aggiunto — Sessione 5 Tier 2 (2026-08-07)

- `claude/skills/hix-add-route/` - genera una singola route HTTP (controller CLASS + routes JSON) in uno scaffold esistente, renderizza 2 test (200-JSON + 405-su-metodo-sbagliato), e ritorna OK solo quando entrambi passano.
- `claude/skills/hix-add-middleware/` - fa lo scaffolding di un middleware di proprietà dell'utente (funzione `HixMw<Name>` + stub `www/loaders/init_mw_*.prg` che `#include` la MW), un controller di probe, una route di probe collegata con la MW, e 2 test che asseriscono che la MW nega le richieste non autenticate (401) e consente quelle autenticate (200).
- `templates/module-route/` - overlay di 2 file (controller + routes JSON). Token: `{{ROUTE_NAME}}`, `{{ROUTE_NAME_LOWER}}`, `{{ROUTE_URL}}`, `{{ROUTE_METHOD}}`. `-RouteMethod` validato contro `GET|POST|PUT|DELETE|PATCH`; `-RouteUrl` deve iniziare con `/`.
- `templates/module-middleware/` - overlay di 4 file (middleware `.prg` + stub di loader + controller di probe + route di probe). Token: `{{MIDDLEWARE_NAME}}`, `{{MIDDLEWARE_NAME_LOWER}}`, `{{PROBE_URL}}` (auto-derivato a `/__mw_probe_<lower>` se omesso). Nessun JSON viene modificato - la registrazione avviene tramite il loader.
- `scripts/apply-template.ps1`: aggiunti parametri `-RouteName / -RouteUrl / -RouteMethod / -MiddlewareName / -ProbeUrl` e un dispatch per template che calcola solo i token di cui ogni template di modulo ha bisogno.
- `scripts/render-tests.ps1`: stesso set di nuovi parametri, gated dal set di token che il chiamante ha fornito (route / middleware / entity).

### Risolto — Sessione 5 Tier 2 (2026-08-07)

- `scripts/apply-template.ps1`: i template di modulo facevano trapelare il loro `README.md` di top-level nel `<project>/www/README.md` dell'utente. Pre-esistente per `module-crud` e avrebbe colpito `module-route` / `module-middleware` alla prima esecuzione. Ora viene saltato insieme a `.gitkeep` quando il kind è `module`.
- `scripts/apply-template.ps1`: la modalità overlay di modulo era gated su un controllo di directory obsoleto che saltava la copia quando lo scaffold parent aveva già `www/`. Riscritto il gate per rilevare i template di modulo tramite la presenza di `models/` + `controllers/` + `views/` nella root del template invece.

### Verificato — Sessione 5 Tier 2

- End-to-end (`hix-scaffold RouteE2E` -> `hix-add-route Ping /ping GET` -> `run.ps1`): **2/2 passano, exit 0**. Il secondo test asserisce `DELETE /ping` -> 405 (HIX ritorna 200 per `OPTIONS` a causa della gestione CORS, quindi il probe con metodo sbagliato usa `DELETE`).
- End-to-end (`hix-scaffold MwE2E` -> `hix-add-middleware RequireApiKey` -> `run.ps1`): **2/2 passano, exit 0** al primo tentativo.

### Aggiunto — Sessione 5 Tier 1 (2026-08-07)

- `claude/skills/hix-scaffold/` - riscritto da stub PoC. Wrappa `scripts/apply-template.ps1 project-web-crud`, risolve i token author/date, valida il layout di output, e asserisce che la `go.bat build` iniziale riesca prima di ritornare.
- `claude/skills/hix-add-crud/` - genera un modulo CRUD completo (controller CLASS + model in forma di funzione + 3 view + routes JSON + loader `#include`) in uno scaffold esistente, poi renderizza ed esegue 7 `*.test.json` (list/show/create-form/create-post-redirect/edit-form/update/delete). Ritorna OK solo quando tutti e 7 passano.
- `claude/skills/hix-compile-and-test/` - skill sottile che shella fuori su `go.bat build` e `tests/run.ps1` per qualsiasi directory di progetto HIX.
- `claude/skills/README.md` - indice delle skill installate con scopo di una riga, snippet di invocazione, e puntatori agli script/template sottostanti.
- `scripts/render-tests.ps1` - espande i `*.test.json.tmpl` sotto `templates/module-crud/tests/` in `*.test.json` concreti nel progetto target (sostituzione di token allineata con `apply-template.ps1`).

### Risolto — Template e runner (trovati durante l'end-to-end della Sessione 5)

- `scripts/apply-template.ps1`: la modalità overlay di modulo era gated su un controllo di directory obsoleto che saltava la copia quando lo scaffold parent aveva già `www/`. Riscritto il gate per rilevare i template di modulo tramite la presenza di `models/` + `controllers/` + `views/` nella root del template invece.
- `templates/module-crud/routes/{{ENTITY_PLURAL_LOWER}}.json`: le stringhe action devono essere `controllers/METHOD@CLASS.prg` (con `.prg`), non bare `CLASS@METHOD` - il dispatcher cerca il file su disco.
- `templates/module-crud/controllers/{{ENTITY_LOWER}}.prg`: riscritto come CLASS con una lista METHOD; tutte le chiamate `USendView` ora passano gli argomenti **posizionalmente** (corrispondenti alla riga `@args` nella view), non come hash - `hix_view_params.prg:64` conferma il binding posizionale.
- `templates/module-crud/models/{{ENTITY_LOWER}}.prg`: `_Open()` ora si auto-provvede del DBF (crea `data/` + `dbCreate` quando manca) perché HIX invoca solo il singolo `USERINIT()` globale - `UserInit_XXX` per-loader non viene mai chiamato. Update/Delete ora wrappano `FieldPut`/`dbDelete` in `dbRLock()` / `dbRUnlock()` (l'RDD rifiuta le scritture su record non lockati).
- `templates/module-crud/loaders/init_{{ENTITY_LOWER}}.prg`: ridotto a un singolo `#include '/models/{{ENTITY_LOWER}}.prg'`. L'include è ciò che porta le funzioni del model nell'unità di compilazione così `hb_hrbLoad` le registra; la procedura init precedente non veniva mai eseguita.
- `templates/module-crud/views/{{ENTITY_LOWER}}/show.view.html`: rimosse le chiamate a `HIX_EscapeHtml()` non esistente (greppato `hix.pro/src` - nessuna tale funzione). Usa l'interpolazione diretta `{{ hRow['name'] }}`.
- `tests/run.ps1`: `$buildPath` era definito solo dentro il blocco `if (-not $SkipBuild)` ma referenziato più tardi quando si lanciava il server - con `-SkipBuild` era `$null`, producendo un comando `cmd /c ""` vuoto. Spostata l'assegnazione sopra il gate.
- `tests/run.ps1`: sostituito `Invoke-WebRequest` con `[System.Net.HttpWebRequest]` raw perché PS 5.1 con `-MaximumRedirection 0` lancia `InvalidOperationException` invece di mostrare la response 302. `AllowAutoRedirect = $false` + catch esplicito di `WebException` per `$_.Exception.Response` dà una gestione pulita dei redirect.

### Verificato

- End-to-end: `hix-scaffold CrudE2E` -> `hix-add-crud Product` -> `go.bat build` -> `tests/run.ps1` contro i test generati -> **7/7 passano, exit 0**.
- Contratto enforced: `hix-add-crud` ritorna fallimento se qualche test generato fallisce.

### Aggiunto — Sessione 4 (2026-08-07)

- `tests/SCHEMA.md` - schema v1 per `*.test.json` (campi: `name`, `request.{method,path,headers,body}`, `expect.{status,content_type_contains,body_contains,body_matches}`). Lista esplicita di elementi out-of-scope per v2.
- `tests/run.ps1` - test runner dichiarativo. Compila via `go.bat` (o `-BuildScript`), sceglie una porta libera, patcha `hix.json`'s `server.port` sul posto, lancia il `.exe` del progetto nascosto, fa polling finché non è vivo (`Wait-ForHttp`), itera su ogni `*.test.json`, invia la request e valida status + content-type + body contains/matches, demolisce (`Stop-Process` + `taskkill /F /T`), ripristina `hix.json`. Exit code: 0 passa, N fallimenti, 2 input non valido, 3 build/exe fallisce, 4 timeout del server.
- `tests/helpers.ps1` - `Find-FreePort` (TcpListener porta 0), `Wait-ForHttp` (poll con tolleranza WebException), `Stop-ProjectExe` (kill idempotente per PID + nome), `Get-ProjectExeName` (default `app.exe`), `Set-HixJsonPort` / `Restore-HixJson` (patch JSON della porta con ripristino originale).
- `tests/self-test/` - meta-test (`basic-get.test.json` per `GET /`, `not-found.test.json` per 404) con README che spiega come eseguirli contro un progetto scaffoldato.
- `tests/README.md` - quick start, riferimento flag di `run.ps1`, exit code, convenzioni (un test per file, no stato condiviso, no porte hardcoded, UTF-8 no BOM), dove vivono i test (di proprietà delle skill vs del progetto), troubleshooting (timeout, exe orfano, ExecutionPolicy, manipolazione del path bash).

### Risolto — Template `project-web-crud` (trovato durante l'end-to-end della Sessione 4)

- Commento di header di `src/app.prg`: `www/**/*.json` dentro `/* */` chiudeva prematuramente il commento (il `*/` in `**/`). Riformulato il testo della descrizione.
- `src/app.prg`: `Main()` ora chiama `hb_threadJoin( oServer:hThread )` dopo `oServer:Start()` - `Start()` è non bloccante, senza la join il processo usciva immediatamente.
- PATH di `go.bat`: aggiunti `%hbdir%\dll\msvc64` e `%hix%\dll\msvc` così `app.exe` può trovare `libcrypto-3-x64.dll`, `libssl-3-x64.dll`, `libcurl.dll`.
- Modalità di `go.bat`: aggiunto `go.bat build` (solo compilazione) e `go.bat serve` (solo lancio, eredita l'env completo). Il test runner usa queste per compilare una volta e poi lanciare l'exe con il path delle DLL corretto.
- `go.bat`: lancia `.\app.exe` (non `app.exe`) - cmd.exe non ha `.` nel PATH.
- `www/index.html` spostato in `www/views/index.html` per corrispondere alla route `home` in `www/routes/web.json`.

### Verificato

- End-to-end: `apply-template.ps1 project-web-crud` -> `run.ps1` contro `tests/self-test/` -> **2/2 passano, exit 0**.
- Test di fallimento intenzionale: exit code 1.

### Aggiunto — Sessione 3 (2026-08-06)

- `templates/README.md` - catalogo dei token e utilizzo.
- `templates/project-web-crud/` - scheletro hixstyle minimale (`app.hbp`, `go.bat`, `hix.json`, `src/app.prg`, `www/{config.json,index.html,public/css/style.css,routes/web.json,middlewares/config.json}`, `data/` vuoto, `controllers/`, `models/`, `views/`, `loaders/`). Token: `{{PROJECT_NAME}}`, `{{PROJECT_NAME_LOWER}}`, `{{AUTHOR}}`, `{{DATE}}`, `{{YEAR}}`, `{{HIX_PATH}}`.
- `templates/module-crud/` - modulo CRUD a 7 route (controller + model + 3 view + routes + loader DBF al primo boot). Token: `{{ENTITY}}`, `{{ENTITY_LOWER}}`, `{{ENTITY_PLURAL_LOWER}}`, `{{DATE}}`, `{{AUTHOR}}`.
- `scripts/apply-template.ps1` - sostitutore di token. Sostituisce i token nel contenuto dei file E nei segmenti di path; auto-popola `{{AUTHOR}}` da `git config user.name`, fallback a `Developer`. Solo ASCII per regola `.ps1`. Verificato end-to-end sia con `project-web-crud` che con `module-crud`.

### Aggiunto — Sessione 2 (2026-08-06)

- `knowledge/INDEX.md` - indice bilingue di tutti i doc di knowledge (EN + ES).
- `knowledge/en/` - 12 doc: `00_overview`, `01_project_layout`, `02_routing`, `03_middleware`, `04_controllers`, `05_views`, `06_models`, `07_validation`, `08_sessions_auth`, `09_hixstyle`, `10_u_helpers_ref`, `11_harbour_rules`.
- `knowledge/es/` - 12 traduzioni in spagnolo (codice identico, prosa tradotta).
- Contenuto proveniente dal `hix.pro/.claude/rules/hix_bible.md` privato, potato alla superficie pubblica: pattern, regole e trappole di cui qualsiasi autore di app HIX ha bisogno.

### Aggiunto — Sessione 1 (2026-08-06)

- `README.es.md` - versione spagnola del README.
- `INSTALL.md` + `INSTALL.es.md` - guida di install dettagliata (EN + ES) con prerequisiti, troubleshooting, aggiornamento.
- `UNINSTALL.md` + `UNINSTALL.es.md` - guida alla disinstallazione (EN + ES).
- `CONTRIBUTING.md` + `CONTRIBUTING.es.md` - come aggiungere skill / agent / command / knowledge / template.
- `scripts/install.bat` - wrapper che bypassa l'execution policy di PowerShell così gli utenti non devono ricordare il flag.
- `scripts/uninstall.bat` - stesso wrapper per la disinstallazione.
- README.md aggiornato per linkare tutti i nuovi doc e raccomandare `install.bat` come punto di ingresso.

## [0.0.1] — 2026-08-06 — Proof of Concept

### Aggiunto

- Layout di directory iniziale sotto `hix/ia/`
- `claude/CLAUDE.md` minimale con regole di base per i progetti HIX
- `claude/skills/hix-scaffold/SKILL.md` minimale (skill di test echo)
- `scripts/install.ps1` - installer basato su symlink con fallback di copia
- `scripts/uninstall.ps1` - inverso dell'install
- `README.md` - panoramica POC e quick-start

### Limitazioni note

- Solo inglese (EN); spagnolo (ES) in arrivo nella Sessione 1.
- Solo skill `hix-scaffold` disponibile; altre nella Sessione 5.
- Nessuna knowledge base ancora - Claude si affida ai dati di addestramento + agli `examples/` di questo repo.
- Nessun framework di test ancora - Sessione 4.
- I symlink richiedono Windows Developer Mode o PowerShell admin.
