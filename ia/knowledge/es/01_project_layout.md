# Estructura de proyecto

Convención que sigue toda aplicación HIX (web/API/servidor).

## Raíz

    MiApp/
        app.hbp              Fichero de proyecto Harbour (manifest de compilación)
        app.rc               Fichero de recursos Windows (icono, versión)
        go.bat               Script de compilación (invoca hbmk2)
        hix.json             Config HIX a nivel de app (flag hixstyle, tamaños de pool)
        readme.md
        data/                DBFs, índices, ficheros subidos
        docs/                Documentación específica del proyecto
        resources/           Assets estáticos empaquetados en el exe (iconos, etc.)
        src/                 Código Harbour: app.prg, appconfig.prg, appmiddleware.prg
        www/                 Raíz web pública + carpetas hixstyle

## Dentro de `www/`

    www/
        config.json          Config Harbour (SETs), RDD, claves de cifrado
        index.html           Página principal (o plantilla)
        public/              Único directorio servido sin whitelist (css, js, imágenes)
        controllers/         Ficheros .prg de controllers (bloqueados por whitelist)
        middlewares/         Middlewares .prg propios + config.json
            config.json      Setup de middleware: cors, csrf, jwt, ratelimit, session
        routes/              JSONs de rutas declarativos (p. ej. web.json, api.json)
        models/              Ficheros .prg de modelos (helpers CRUD para DBF)
        loaders/             Ficheros .prg auto-cargados al arrancar (extienden funcionalidad)
        views/               Plantillas .view.html (renderizadas vía acción, nunca servidas directamente)

Whitelist (hixstyle): solo `/public/*` y los `AllowDir()` que declares en tu código. Todo lo demás → 403.

## `hix.json` — config de app

    {
      "hixstyle": { "enabled": true },
      "server":   { "port": 8080, "host": "0.0.0.0" },
      "pools":    { "http": 8, "ws": 2, "rest": 4 }
    }

## `www/config.json` — config Harbour + framework

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

Si falta → `Start()` crea uno por defecto. Si existe pero es incompleto → se rellenan las claves nuevas sin sobrescribir las tuyas.

Cada hilo worker aplica estos `sets` al arrancar mediante `HIX_HarbourConfigApply()` — los SETs de Harbour son thread-local, así que es obligatorio.

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

`load` = ficheros `.prg` adicionales que se compilan dentro del worker. `setup` = auto-invoca `HIX_Mw<Sección>Setup()` por cada sección.

## `www/routes/<nombre>.json`

    [
      { "name": "home",       "url": "/",              "method": "GET",    "action": "home@index" },
      { "name": "users.list", "url": "/api/users",     "method": "GET",    "action": "users@list",   "middleware": "HIX_MwJwt" },
      { "name": "users.one",  "url": "/api/users/:id", "method": "GET",    "action": "users@show" }
    ]

Ver `02_routing.md`.
