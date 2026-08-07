# Project Layout

Convention followed by every HIX application (web/API/server).

## Root

    MyApp/
        app.hbp              Harbour project file (compilation manifest)
        app.rc               Windows resource file (icon, version)
        go.bat               Compile script (invokes hbmk2)
        hix.json             App-level HIX config (hixstyle flag, worker counts)
        readme.md
        data/                DBFs, indexes, uploaded files
        docs/                Project-specific docs
        resources/           Static assets bundled into the exe (icons, etc.)
        src/                 Harbour source: app.prg, appconfig.prg, appmiddleware.prg
        www/                 Public webroot + hixstyle folders

## Inside `www/`

    www/
        config.json          Harbour SET config, RDD, encryption keys
        index.html           Homepage (or template)
        public/              Only dir served without whitelisting (css, js, images)
        controllers/         Controller .prg files (blocked by whitelist)
        middlewares/         Custom middleware .prg + config.json
            config.json      Middleware setup: cors, csrf, jwt, ratelimit, session
        routes/              Declarative route JSONs (e.g. web.json, api.json)
        models/              Model .prg files (DBF CRUD helpers)
        loaders/             .prg files auto-loaded at startup (extend functionality)
        views/               .view.html templates (rendered via action, never served directly)

Whitelist (hixstyle): only `/public/*` and any `AllowDir()` your code declares. Everything else → 403.

## `hix.json` — app config

    {
      "hixstyle": { "enabled": true },
      "server":   { "port": 8080, "host": "0.0.0.0" },
      "pools":    { "http": 8, "ws": 2, "rest": 4 }
    }

## `www/config.json` — Harbour + framework config

    {
      "sets": {
        "language":   "EN",
        "dateformat": "dd/mm/yy",
        "decimals":   2,
        "deleted":    false,
        "epoch":      1900
      },
      "dbf":  { "rddname": "DBFCDX" },
      "keys": { "csrf": "...", "jwt": "...", "session": "..." }
    }

Missing → `Start()` creates a default. Existing but incomplete → new keys are backfilled without overwriting yours.

Every worker thread applies these `sets` at spawn via `HIX_HarbourConfigApply()` — Harbour sets are thread-local so this is required.

## `www/middlewares/config.json`

    {
      "load": [ "auth_guard.prg" ],
      "setup": {
        "cors":       { "origin": "*", "methods": "GET,POST", "headers": "Content-Type" },
        "csrf":       { "redirect": "/login", "ttl": 3600 },
        "ratelimit":  { "ip_per_min": 60, "window_s": 60 },
        "jwt":        { "key_ref": "jwt", "exp": 3600 },
        "session":    { "cookie": "sid", "ttl": 3600, "max": 60, "storage": "memory" }
      }
    }

`load` = extra `.prg` files to compile into the worker. `setup` = auto-invokes `HIX_Mw<Section>Setup()` per section.

## `www/routes/<name>.json`

    [
      { "name": "home",       "url": "/",              "method": "GET",    "action": "home@index" },
      { "name": "users.list", "url": "/api/users",     "method": "GET",    "action": "users@list",   "middleware": "HIX_MwJwt" },
      { "name": "users.one",  "url": "/api/users/:id", "method": "GET",    "action": "users@show" }
    ]

See `02_routing.md`.
