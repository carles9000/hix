# Layout del progetto

Convenzione seguita da ogni applicazione HIX (web/API/server).

## Root

    MyApp/
        app.hbp              File di progetto Harbour (manifest di compilazione)
        app.rc               File di risorse Windows (icona, versione)
        go.bat               Script di compilazione (invoca hbmk2)
        hix.json             Config HIX a livello app (flag hixstyle, numero worker)
        readme.md
        data/                DBF, indici, file caricati
        docs/                Documenti specifici del progetto
        resources/           Asset statici inclusi nell'exe (icone, ecc.)
        src/                 Sorgenti Harbour: app.prg, appconfig.prg, appmiddleware.prg
        www/                 Webroot pubblica + cartelle hixstyle

## Dentro `www/`

    www/
        config.json          Config Harbour SET, RDD, chiavi di crittografia
        index.html           Homepage (o template)
        public/              Unica dir servita senza whitelisting (css, js, immagini)
        controllers/         File controller .prg (bloccati dalla whitelist)
        middlewares/         Middleware custom .prg + config.json
            config.json      Setup middleware: cors, csrf, jwt, ratelimit, session
        routes/              Route dichiarative JSON (es. web.json, api.json)
        models/              File model .prg (helper CRUD DBF)
        loaders/             File .prg auto-caricati all'avvio (estendono le funzionalità)
        views/               Template .view.html (renderizzati via action, mai serviti direttamente)

Whitelist (hixstyle): solo `/public/*` e qualsiasi `AllowDir()` dichiarata dal tuo codice. Tutto il resto → 403.

## `hix.json` — config app

    {
      "hixstyle": { "enabled": true },
      "server":   { "port": 8080, "host": "0.0.0.0" },
      "pools":    { "http": 8, "ws": 2, "rest": 4 }
    }

## `www/config.json` — config Harbour + framework

    {
      "sets": {
        "language":   "IT",
        "dateformat": "dd/mm/yy",
        "decimals":   2,
        "deleted":    false,
        "epoch":      1900
      },
      "dbf":  { "rddname": "DBFCDX" },
      "keys": { "csrf": "...", "jwt": "...", "session": "..." }
    }

Se mancante → `Start()` ne crea uno di default. Se esistente ma incompleto → le nuove chiavi vengono aggiunte senza sovrascrivere le tue.

Ogni thread worker applica questi `sets` allo spawn tramite `HIX_HarbourConfigApply()` — i SET di Harbour sono thread-local quindi questo è richiesto.

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

`load` = file `.prg` extra da compilare nel worker. `setup` = auto-invoca `HIX_Mw<Section>Setup()` per ogni sezione.

## `www/routes/<name>.json`

    [
      { "name": "home",       "url": "/",              "method": "GET",    "action": "home@index" },
      { "name": "users.list", "url": "/api/users",     "method": "GET",    "action": "users@list",   "middleware": "HIX_MwJwt" },
      { "name": "users.one",  "url": "/api/users/:id", "method": "GET",    "action": "users@show" }
    ]

Vedi `02_routing.md`.
