# HIX AI System — Quickstart

**5 minuti da una cartella `hix.exe` vuota a un'app HIX funzionante con test verificati da Claude.**

## Prerequisiti

- Windows 10/11. Developer Mode consigliato (permette i symlink senza admin).
- CLI [Claude Code](https://claude.com/claude-code) installata e loggata.
- Una distribuzione binaria di HIX (tipicamente `C:\hix\` con `hix.exe`, `hix.json` e le DLL runtime).

Non ti servono **Harbour, `hbmk2` o alcun compilatore** per il flusso predefinito. `hix.exe` ricompila i tuoi file `.prg` in memoria per ogni richiesta.

## 1. Installa l'AI System (30 s)

```
cd C:\hix\ia
.\scripts\install.bat C:\hix
```

Questo:
- Symlinka ogni skill, agent e command `hix-*` in `~\.claude\`.
- Renderizza `~\.claude\hix-claude-rendered.md` con il tuo path HIX reale.
- Crea `C:\hix\CLAUDE.md` con un `@import` a quel file renderizzato.
- Scrive `C:\hix\.claude\settings.local.json` con i permessi che le skill necessitano (PowerShell / Bash / curl) così Claude Code non chiede per ogni comando.

Rieseguibile in qualsiasi momento - sicuro e idempotente.

## 2. Avvia l'app (30 s)

```
cd C:\hix
claude
> /hix-init MyFirstApp
```

Claude applica il template `project-www` in `C:\hix\www\`, abilita `hixstyle` in `hix.json`, avvia `hix.exe` in background e verifica che `GET http://127.0.0.1:<port>/health` ritorni 200. Se qualche step fallisce, la skill abortisce con l'errore esatto.

## 3. Aggiungi una risorsa CRUD (1 min)

```
> /hix-add-crud Note
```

Claude sovrappone il template `module-crud` (7 route: list / show / create-form / create-post / edit-form / update / delete), renderizza i 7 `*.test.json` forniti in `tests/` con `Note` al posto del token, cancella eventuali DBF vecchi, ed esegue `tests/run-live.ps1`. Atteso: **7/7 passano, exit 0**. Se qualche test fallisce, Claude si ferma e riporta l'asserzione fallita verbatim.

Non serve riavviare `hix.exe` - controller/model/view si ricompilano in memoria per richiesta.

## 4. Aggiungi un endpoint custom (1 min)

```
> /hix-add-route Ping /ping GET
```

Aggiunge un controller sotto `www/controllers/` e un entry in routes JSON sotto `www/routes/`, renderizza 2 test (200 JSON body + 405 sul metodo sbagliato), li esegue. Atteso: **2/2 passano**.

`www/routes/*.json` viene caricato una volta al boot - Claude passa `--restart` al runner così `hix.exe` rileva la nuova route.

## 5. Aggiungi un middleware (1 min)

```
> /hix-add-middleware RequireApiKey
```

Scaffolda `HixMwRequireApiKey` (nega a meno che `X-Api-Key` non sia presente), uno stub di loader sotto `www/loaders/` che lo pubblica, un controller + route di probe, e 2 test (401 senza header / 200 con header). Atteso: **2/2 passano**.

Lo scheletro fornito è un template - sostituisci il corpo di `HixMwRequireApiKey()` con la tua vera logica di auth. Registrazione e wiring sono già fatti.

## 6. Verifica tutto (30 s)

```
> /hix-test
```

Riesegue ogni `*.test.json` sotto `tests/` contro il `hix.exe` live. Nessuna fase di build. Dovrebbe essere ancora tutto verde (**11/11**). Se hai toccato `hix.json`, `www/routes/*.json` o `www/loaders/*.prg` dall'ultima esecuzione, aggiungi `--restart`.

## 7. Ottieni una code review (30 s)

```
> /hix-review
```

Invoca l'agent `hix-reviewer` (read-only): esegue l'audit di tutto sotto `www/` contro le regole pubbliche di HIX e Harbour (posizionamento di LOCAL, `!=` sulle stringhe, formato delle stringhe action, argomenti posizionali di `USendView`, registrazione middleware, ACL whitelist, ecc.). Risultati per severità con citazioni `file:line`. Su un progetto pulito, verdetto in una riga.

---

## Cosa hai adesso

- Un'app hixstyle sotto `C:\hix\www\` con:
  - 7 route CRUD per `Note` su `/notes/*`.
  - Un endpoint `GET /ping`.
  - Uno scheletro di middleware pronto a proteggere qualsiasi route.
- 11 test, tutti passanti, verificati contro il `hix.exe` live.
- Un `CLAUDE.md` alla root del progetto che qualsiasi futura sessione Claude carica automaticamente - con le regole del framework HIX integrate.

## Prossimi passi

- Profondità del framework: `knowledge/en/00_overview.md` (inizio), poi sfoglia `knowledge/en/*.md` (12 doc tematici) o `knowledge/es/*.md`.
- Capacità degli agent: `claude/agents/README.md` - quando raggiungere `hix-architect`, `hix-router-expert`, `hix-view-builder`, `hix-reviewer` invece dei command.
- Estendi i template: `templates/README.md` per il catalogo dei token; aggiungi il tuo overlay sotto `templates/module-<name>/`.
- Aggiungi le tue skill / command / agent: `CONTRIBUTING.md`.
- Disinstalla: `.\scripts\uninstall.bat C:\hix` - pulisce i symlink e ripristina il `CLAUDE.md` del progetto.

## Percorso source-first (legacy)

Se costruisci il tuo `.exe` linkato contro `hix_server.lib` (richiede Harbour + hbmk2), salta lo step 2 e usa `/hix-scaffold-source MyApp` invece. Dallo step 3 in poi il flusso è identico, tranne che esegui `go.bat build` a mano prima di `/hix-test` - l'AI System non gestisce le build source-first.

## Troubleshooting

- **`/hix-init` riporta `hix.exe did not open port`**: controlla `C:\hix\.logs\hix.log`. La causa più comune è un altro processo sulla porta configurata (la 80 di default richiede admin su Windows) o `hix.json` con `hixstyle.enabled` ancora `false`. La skill lo corregge, ma un JSON corrotto può impedire la modifica.
- **`/hix-add-crud` fallisce al test 3 o 4**: di solito un DBF vecchio da un'esecuzione precedente. La skill cancella `data/<entity>*.dbf` prima di ogni run, ma se hai bloccato manualmente il file (aperto in un altro processo), non può pulirlo. `taskkill //F //IM hix.exe` e riprova.
- **Gli slash command non si autocompletano in Claude Code**: riesegui `.\scripts\install.bat <project-path>` - i symlink sotto `~\.claude\commands\` potrebbero non essere stati creati (es. prima install fallita silenziosamente).
- **`/hix-review` riporta "unknown agent"**: il symlink dell'agent non ha funzionato. Stessa soluzione - reinstalla.
- **PowerShell chiede ancora per ogni comando**: `install.bat` non ha scritto `.claude/settings.local.json` (errore di permesso?). Reinstalla; il file dovrebbe elencare `Bash(powershell.exe *)`, `PowerShell(*)`, `Bash(curl.exe *)` in `permissions.allow`.
