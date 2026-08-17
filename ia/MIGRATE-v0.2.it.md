# Migrazione da HIX AI System v0.1 a v0.2

**Si applica a**: utenti che hanno installato `hix/ia` v0.1 (qualsiasi tag `ia-v0.1.x`) e vogliono passare a `ia-v0.2.0`.

**Tempo di lettura**: 5 minuti.
**Tempo di migrazione**: 2 minuti (Scenario A) o 10 minuti (Scenario B).

---

## TL;DR

| v0.1 | v0.2 | Azione |
|------|------|--------|
| `/hix-scaffold`         | `/hix-scaffold-source` | Rinomina nei tuoi script / memoria muscolare. |
| `/hix-compile-and-test` | `/hix-test`            | Rinomina **e** ri-impara la semantica: niente build step. |
| Source-first di default | Binary-first di default | `/hix-init` è il nuovo punto di ingresso. Il vecchio flusso preservato via `/hix-scaffold-source`. |
| `CLAUDE.md` hard-coded a `C:\HIX.PROJECT\hix\` | Token `{{HIX_ROOT}}`, espanso al momento dell'install | Re-installa — vedi verifica sotto. |
| Skill `hix-compile-and-test` | Skill `hix-run-tests` | Cartella della skill rinominata. Symlink vecchi? Elimina e reinstalla. |

Tutto quanto sopra è coperto in dettaglio in `CHANGELOG.md` sotto `[0.2.0]`. Questo documento ti dice **cosa fare**, non cosa è cambiato.

---

## Perché esiste v0.2

v0.1 assumeva che tu fossi uno sviluppatore Harbour con `hbmk2` nel PATH - l'AI System faceva lo scaffolding di un progetto sorgente e compilava un `.exe` per te. È una soglia alta per chi vuole solo un'app web.

v0.2 ribalta il default: HIX viene distribuito come `hix.exe` + DLL precompilate. L'AI System fa lo scaffolding di una directory `www/` sopra, e `hix.exe` ricompila i tuoi file `.prg` in memoria a ogni richiesta. Zero build step, zero install di Harbour, zero `hbmk2`.

Il percorso source-first è preservato per gli sviluppatori che ne hanno bisogno (linkando contro `hix_server.lib`, personalizzando il binario del server) - vedi Scenario A sotto.

---

## Scegli il tuo percorso di migrazione

- **Scenario A** - Uso già v0.1 source-first e voglio continuare a farlo. Modifiche minime.
- **Scenario B** - Voglio passare al nuovo flusso binary-first (consigliato per le nuove app).

---

## Scenario A - Resta source-first (sviluppatori)

Compili ancora il tuo `.exe` contro `hix_server.lib`. L'upgrade a v0.2 per te è essenzialmente cosmetico.

### 1. Aggiorna i tuoi command e la memoria muscolare

- Ovunque tu abbia scriptato o documentato `/hix-scaffold`, rinomina in `/hix-scaffold-source`.
- Ovunque tu abbia scriptato o documentato `/hix-compile-and-test`, rinomina in `/hix-test`.

I vecchi nomi di slash command non si risolvono più - le cartelle delle skill sono state rinominate su disco.

### 2. Re-installa

    cd C:\path\to\hix\ia
    .\scripts\install.bat C:\MyProject

Questo rigenera `~\.claude\hix-claude-rendered.md` con il nuovo token `{{HIX_ROOT}}` espanso, rinfresca i sei symlink `~\.claude\skills\hix-*` e aggiorna `.claude\settings.local.json` nel tuo progetto con eventuali nuove voci di permesso.

### 3. Verifica

    ls ~/.claude/skills/ | grep hix

Dovresti vedere:

    hix-add-crud
    hix-add-middleware
    hix-add-route
    hix-init
    hix-run-tests
    hix-scaffold-source

Se rimane qualche vecchia entry (`hix-scaffold`, `hix-compile-and-test`, ...), eliminala manualmente - `install.bat` non fa il garbage-collection dei symlink obsoleti:

    rm ~/.claude/skills/hix-scaffold
    rm ~/.claude/skills/hix-compile-and-test
    rm ~/.claude/commands/hix-scaffold.md
    rm ~/.claude/commands/hix-compile-and-test.md

### 4. Controllo di sanità sul tuo progetto esistente

Apri Claude in quel progetto ed esegui:

    > /hix-scaffold-source --help

Se Claude riconosce il command e stampa l'uso, hai finito.

---

## Scenario B - Passa a binary-first (consigliato)

Vuoi il nuovo flusso predefinito: niente install di Harbour, niente `hbmk2`, niente build.

### 1. Ottieni il bundle binario di HIX

Prendi `hix.exe` + DLL dal tuo canale di distribuzione HIX (release ZIP, share interno, ecc.). Ti servono:

    hix.exe
    libcrypto-3-x64.dll
    libssl-3-x64.dll
    libcurl.dll
    z.dll

Mettili in una directory vuota - la posizione canonica è `C:\hix\`, ma qualsiasi path assoluto va bene.

Nota: `hix.json` **non è richiesto subito**. Se manca, `/hix-init` avvia `hix.exe` brevemente per fargli auto-generare la config di default, poi ferma il processo prima di continuare.

### 2. Metti l'AI System accanto al binario

Copia la directory `ia/` di questo repo in `C:\hix\ia\` (o ovunque sia il tuo root HIX):

    xcopy C:\path\to\hix\ia C:\hix\ia /E /I /Y

### 3. Esegui l'installer verso il tuo root HIX

    cd C:\hix\ia
    .\scripts\install.bat C:\hix

Questo collega le sei skill `hix-*`, quattro agent e sette command nella tua directory utente di Claude Code. Crea anche `C:\hix\CLAUDE.md` e `C:\hix\.claude\settings.local.json`.

### 4. Avvia la tua prima app

Apri Claude dal tuo root HIX ed esegui:

    cd C:\hix
    claude
    > /hix-init MyFirstApp

Atteso: `/health` risponde 200, il browser mostra la welcome page, zero prompt durante il percorso.

### 5. Valida end-to-end

Esegui ognuno dei cinque command di follow-up e conferma i conteggi dei test riportati:

    > /hix-add-crud Note                        # 7/7 test
    > /hix-add-route Ping /ping GET             # 2/2 test
    > /hix-add-middleware RequireApiKey         # 2/2 test
    > /hix-test                                 # 11/11 test
    > /hix-review                               # pulito o citazioni con file:line

Se qualcuno di questi fallisce, cattura l'output e apri un issue - quella combinazione è il test di fumo canonico per v0.2.

### 6. Ritrai il tuo progetto v0.1 source (opzionale)

Se usavi v0.1 solo per costruire app di esempio, il tuo progetto source v0.1 è superato - il flusso binary-first fa tutto ciò che facevi prima, meno lo step di compilazione. Se avevi codice Harbour non banale nel tuo progetto source, mantienilo; puoi comunque aggiungervi route binary-first se lo desideri.

---

## Checklist di verifica

Dopo la migrazione, tutti i seguenti devono essere veri:
- `~/.claude/hix-claude-rendered.md` esiste e **non** contiene la stringa letterale `{{HIX_ROOT}}`. Grep: `grep HIX_ROOT ~/.claude/hix-claude-rendered.md` non deve restituire nulla.
- `~/.claude/skills/` contiene: `hix-init`, `hix-add-crud`, `hix-add-route`, `hix-add-middleware`, `hix-run-tests`, `hix-scaffold-source`.
- `~/.claude/commands/` contiene: `hix-init.md`, `hix-add-crud.md`, `hix-add-route.md`, `hix-add-middleware.md`, `hix-test.md`, `hix-review.md`, `hix-scaffold-source.md`.
- `~/.claude/agents/` contiene: `hix-architect.md`, `hix-reviewer.md`, `hix-router-expert.md`, `hix-view-builder.md`.
- Da un root HIX, `/hix-init MyApp` riesce con zero prompt e `/health` ritorna 200.

---

## Troubleshooting

**`{{HIX_ROOT}}` appare nell'output di Claude.**
L'installer non ha renderizzato il template, o l'execution policy di PowerShell lo ha bloccato. Reinstalla (il wrapper `install.bat` bypassa la policy). Se hai invocato `install.ps1` direttamente, usa `-ExecutionPolicy Bypass`.

**"Undefined function" o slash command sconosciuto dopo l'upgrade.**
Symlink vecchi. Elimina la voce offensiva sotto `~/.claude/skills/` o `~/.claude/commands/` e reinstalla.

**`/hix-init` abortisce con "not a HIX binary distribution".**
`hix.exe` non è nel root target. Controlla che la directory contenga `hix.exe` (le DLL vivono accanto).

**`/hix-init` riporta "did not create hix.json within 8 s".**
`hix.exe` non è partito silenziosamente. Eseguilo manualmente una volta dalla directory target (`.\hix.exe`) e ispeziona `.\.logs\hix.log`. Cause comuni: porta 80 bloccata (serve admin) o una DLL mancante.

**`hix-scaffold` / `hix-compile-and-test` vecchi appaiono ancora nella lista degli slash command di Claude.**
I symlink in `~/.claude/commands/` non sono stati puliti. Rimuovi `hix-scaffold.md` e `hix-compile-and-test.md` manualmente e riapri Claude.

**`install.bat` si lamenta di non poter creare symlink.**
Abilita Windows Developer Mode (Impostazioni → Aggiornamento e sicurezza → Per sviluppatori) o passa `/copy` per il fallback sulla copia di file:

    .\scripts\install.bat C:\hix /copy

La modalità copia funziona ma rompe la proprietà "`git pull` si propaga istantaneamente" - dovrai reinstallare dopo ogni aggiornamento del sorgente.

---

## FAQ

**Devo per forza migrare?**
No. v0.1 funziona ancora se non reinstalli. Ma le nuove correzioni e skill atterrano solo in v0.2+.

**Possono v0.1 e v0.2 coesistere sulla stessa macchina?**
Non in modo pulito - entrambi installano in `~/.claude/skills/hix-*` e i nomi delle cartelle collidono. Scegline uno.

**Possono source-first e binary-first coesistere sulla stessa macchina?**
Sì. È tutto lo scopo di mantenere `/hix-scaffold-source`. Progetti diversi possono usare flussi diversi.

**Dov'è il changelog?**
`CHANGELOG.md`, sezione `[0.2.0]`.

**Ho spostato la mia cartella `C:\hix\` dopo l'install. Ora niente funziona.**
Il `CLAUDE.md` renderizzato ha il vecchio path. Reinstalla dalla nuova posizione.

---

## Documenti correlati

- [CHANGELOG.md](CHANGELOG.md) - lista completa dei cambiamenti in v0.2.0.
- [INSTALL.md](INSTALL.md) - riferimento per l'installazione.
- [QUICKSTART.md](QUICKSTART.md) - walkthrough di 5 minuti del flusso binary-first.
- [README.md](README.md) - panoramica del progetto.
