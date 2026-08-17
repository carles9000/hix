# hixstyle — Autostart Data-Driven

Abilita in `hix.json`:

    { "hixstyle": { "enabled": true } }

Con questo flag attivo, `oSrv:Start()` diventa un autoloader. Il tuo `Main()` può essere:

    PROCEDURE Main()
       LOCAL oSrv := THixServer():New()
       oSrv:Start()
       IF oSrv:hThread != NIL
          hb_threadJoin( oSrv:hThread )
       ENDIF
    RETURN

## Cosa fa `Start()` sotto hixstyle

| Passo | Sorgente | Risultato |
|------|--------|--------|
| 1. Carica `www/config.json` | disco → memoria | `sets`, `dbf`, `keys` disponibili |
| 2. `HIX_HarbourConfigApply()` sul thread principale | config.json > sets | `hb_langSelect`, `_SET_DATEFORMAT`, tutti i `SET`, `rddSetDefault` |
| 3. `HIX_KeysLoadFromAppConfig()` | config.json > keys | Popola lo store `HIX_KeyGet/Set` |
| 4. `HIX_LoadMiddleware()` | www/middlewares/config.json | Per ogni `setup.<nome>` → invoca `HIX_Mw<Name>Setup(...)`; per ogni `.prg` in `load[]` → compila + carica |
| 5. `HIX_LoadRoutes()` | www/routes/*.json | Registra ogni route in ogni file JSON trovato |
| 6. `HIX_Loaders()` | www/loaders/*.prg | Auto-compila + esegue ogni `.prg` (usato per estendere le funzionalità: registrare tipi custom, task in background, ecc.) |
| 7. Whitelist ACL | dispatcher | Solo `/public/*` + qualsiasi `AllowDir()` registrata vengono serviti. Tutto il resto → 403 |
| 8. Config propagata ai worker | ogni `_HixPoolWorker` | I SET sono thread-local: ogni worker applica `HIX_HarbourConfigApply()` allo spawn |

## Estendere la whitelist

Dichiara PRIMA di `Start()`:

    LOCAL oSrv := THixServer():New()
    oSrv:AllowDir( "uploads", .F. )   // .F. read-only
    oSrv:AllowDir( "plugins", .T. )   // .T. consenti anche esecuzione .prg
    oSrv:Start()

Le entry si accumulano sopra l'automatica `AllowDir("public",.F.)`.

## Layout atteso da hixstyle

    MyApp/
        hix.json
        app.hbp
        go.bat
        data/
        src/
            app.prg
            appconfig.prg      (opzionale)
            appmiddleware.prg  (opzionale)
        www/
            config.json            <-- richiesto (o auto-generato)
            index.html
            public/                <-- automaticamente in whitelist
                css/  js/  images/
            controllers/           <-- bloccato dalla whitelist
            middlewares/
                config.json
            routes/
                web.json
                api.json
            models/
            loaders/               <-- .prg auto-caricati al boot
            views/                 <-- serviti via action, mai direttamente

## `www/config.json` — esempio completo

    {
      "sets": {
        "language":   "IT",
        "dateformat": "dd/mm/yy",
        "decimals":   2,
        "deleted":    false,
        "epoch":      1900,
        "exact":      false,
        "exclusive":  false,
        "fixed":      false,
        "softseek":   false
      },
      "dbf":  { "rddname": "DBFCDX" },
      "keys": {
        "csrf":     "csrf-secret-here",
        "jwt":      "jwt-secret-here",
        "session":  "session-secret-here",
        "token":    "generic-token-secret",
        "resource": "resource-signing-secret"
      }
    }

Se il file manca, `Start()` ne crea uno di default. Se esiste ma nuove chiavi sono state aggiunte in un upgrade di HIX, `HIX_ConfigAppMerge` le aggiunge senza sovrascrivere i tuoi valori.

## Quando usare hixstyle vs imperativo

Preferisci **hixstyle** per app web CRUD e API REST — modifichi il JSON, HIX gestisce il wiring.

Preferisci **imperativo** quando:
- Le route sono generate dinamicamente (da un DB, al boot).
- Hai bisogno di codice tra gli hook del framework (custom `bOnError`, `bInit`).
- Stai costruendo un server specializzato (puro WebSocket, RPC-over-TCP, ecc.).

Entrambi gli stili possono coesistere: abilita hixstyle per caricare route/middleware da JSON, poi in `Main()` chiama comunque `oSrv:AddRouteGet(...)` per quelle dinamiche.
