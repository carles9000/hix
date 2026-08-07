# hixstyle — Autostart Data-Driven

Actívalo en `hix.json`:

    { "hixstyle": { "enabled": true } }

Con este flag on, `oSrv:Start()` se convierte en un autoloader. Tu `Main()` puede ser:

    PROCEDURE Main()
       LOCAL oSrv := THixServer():New()
       oSrv:Start()
       IF oSrv:hThread != NIL
          hb_threadJoin( oSrv:hThread )
       ENDIF
    RETURN

## Qué hace `Start()` bajo hixstyle

| Paso | Fuente | Resultado |
|------|--------|-----------|
| 1. Carga `www/config.json` | disco → memoria | `sets`, `dbf`, `keys` disponibles |
| 2. `HIX_HarbourConfigApply()` en hilo main | config.json > sets | `hb_langSelect`, `_SET_DATEFORMAT`, todos los `SET`s, `rddSetDefault` |
| 3. `HIX_KeysLoadFromAppConfig()` | config.json > keys | Puebla el store `HIX_KeyGet/Set` |
| 4. `HIX_LoadMiddleware()` | www/middlewares/config.json | Por cada `setup.<nombre>` → llama `HIX_Mw<Name>Setup(...)`; por cada `.prg` en `load[]` → compila + carga |
| 5. `HIX_LoadRoutes()` | www/routes/*.json | Registra todas las rutas de cada JSON encontrado |
| 6. `HIX_Loaders()` | www/loaders/*.prg | Auto-compila + ejecuta cada `.prg` (útil para extender: registrar tipos, tareas en background, etc.) |
| 7. Whitelist ACL | dispatcher | Solo `/public/*` + los `AllowDir()` que registres son servidos. El resto → 403 |
| 8. Config propagada a workers | cada `_HixPoolWorker` | Los sets son thread-local: cada worker aplica `HIX_HarbourConfigApply()` al arrancar |

## Extender la whitelist

Declara ANTES de `Start()`:

    LOCAL oSrv := THixServer():New()
    oSrv:AllowDir( "uploads", .F. )   // .F. solo lectura
    oSrv:AllowDir( "plugins", .T. )   // .T. permite ejecutar .prg
    oSrv:Start()

Las entradas se acumulan sobre el `AllowDir("public",.F.)` automático.

## Layout esperado por hixstyle

    MyApp/
        hix.json
        app.hbp
        go.bat
        data/
        src/
            app.prg
            appconfig.prg      (opcional)
            appmiddleware.prg  (opcional)
        www/
            config.json            <-- requerido (o auto-generado)
            index.html
            public/                <-- whitelisted automáticamente
                css/  js/  images/
            controllers/           <-- bloqueado por whitelist
            middlewares/
                config.json
            routes/
                web.json
                api.json
            models/
            loaders/               <-- .prg auto-cargados al arrancar
            views/                 <-- servidos vía acción, nunca directamente

## `www/config.json` — ejemplo completo

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

Si falta el fichero, `Start()` crea uno con defaults. Si existe pero un upgrade de HIX añade claves nuevas, `HIX_ConfigAppMerge` las backfillea sin pisar tus valores.

## Cuándo usar hixstyle vs imperativo

Prefiere **hixstyle** para CRUD web y APIs REST — editas JSON, HIX cablea todo.

Prefiere **imperativo** cuando:
- Las rutas se generan dinámicamente (desde BBDD, en el arranque).
- Necesitas código entre hooks del framework (`bOnError`, `bInit` propios).
- Construyes un servidor especializado (WebSocket puro, RPC-sobre-TCP, etc.).

Ambos estilos coexisten: activa hixstyle para cargar rutas/mw desde JSON y en `Main()` sigue haciendo `oSrv:AddRouteGet(...)` para las dinámicas.
