# hixstyle — Data-Driven Autostart

Enable in `hix.json`:

    { "hixstyle": { "enabled": true } }

With this flag on, `oSrv:Start()` becomes an autoloader. Your `Main()` can be:

    PROCEDURE Main()
       LOCAL oSrv := THixServer():New()
       oSrv:Start()
       IF oSrv:hThread != NIL
          hb_threadJoin( oSrv:hThread )
       ENDIF
    RETURN

## What `Start()` does under hixstyle

| Step | Source | Result |
|------|--------|--------|
| 1. Load `www/config.json` | disk → memory | `sets`, `dbf`, `keys` available |
| 2. `HIX_HarbourConfigApply()` on main thread | config.json > sets | `hb_langSelect`, `_SET_DATEFORMAT`, all `SET`s, `rddSetDefault` |
| 3. `HIX_KeysLoadFromAppConfig()` | config.json > keys | Populates `HIX_KeyGet/Set` store |
| 4. `HIX_LoadMiddleware()` | www/middlewares/config.json | For each `setup.<name>` → invoke `HIX_Mw<Name>Setup(...)`; for each `.prg` in `load[]` → compile + load |
| 5. `HIX_LoadRoutes()` | www/routes/*.json | Registers every route in every JSON file found |
| 6. `HIX_Loaders()` | www/loaders/*.prg | Auto-compiles + executes each `.prg` (used to extend functionality: register custom types, background tasks, etc.) |
| 7. Whitelist ACL | dispatcher | Only `/public/*` + any `AllowDir()` you registered are served. Everything else → 403 |
| 8. Config propagated to workers | each `_HixPoolWorker` | Sets are thread-local: each worker applies `HIX_HarbourConfigApply()` at spawn |

## Extend the whitelist

Declare BEFORE `Start()`:

    LOCAL oSrv := THixServer():New()
    oSrv:AllowDir( "uploads", .F. )   // .F. read-only
    oSrv:AllowDir( "plugins", .T. )   // .T. allow .prg execution too
    oSrv:Start()

Entries accumulate on top of the automatic `AllowDir("public",.F.)`.

## Layout expected by hixstyle

    MyApp/
        hix.json
        app.hbp
        go.bat
        data/
        src/
            app.prg
            appconfig.prg      (optional)
            appmiddleware.prg  (optional)
        www/
            config.json            <-- required (or auto-generated)
            index.html
            public/                <-- automatically whitelisted
                css/  js/  images/
            controllers/           <-- blocked by whitelist
            middlewares/
                config.json
            routes/
                web.json
                api.json
            models/
            loaders/               <-- .prg auto-loaded at boot
            views/                 <-- served via action, never directly

## `www/config.json` — full example

    {
      "sets": {
        "language":   "EN",
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

If the file is missing, `Start()` creates a default. If it exists but new keys were added in a HIX upgrade, `HIX_ConfigAppMerge` backfills without overwriting your values.

## When to use hixstyle vs imperative

Prefer **hixstyle** for CRUD web apps and REST APIs — you edit JSON, HIX handles the wiring.

Prefer **imperative** when:
- Routes are generated dynamically (from a DB, at boot).
- You need code between framework hooks (custom `bOnError`, `bInit`).
- Building a specialised server (pure WebSocket, RPC-over-TCP, etc.).

Both styles can coexist: enable hixstyle to load routes/middleware from JSON, then in `Main()` still call `oSrv:AddRouteGet(...)` for the dynamic ones.
