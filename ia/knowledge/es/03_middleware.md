# Middleware

El middleware se ejecuta antes de la acción de ruta. Dos valores de retorno:
- `.T.` — continuar la cadena
- `.F.` — abortar (la acción no se ejecuta)

## Patrón estándar

Todo middleware HIX sigue este trío:

    // Setup: se llama una vez al arrancar, guarda config en un STATIC.
    PROCEDURE HixMwApiKeySetup( cKey )
       STATIC scKey := ""
       scKey := cKey
    RETURN

    // Middleware directo.
    FUNCTION HixMwApiKey( oCtx )
       LOCAL cProvided := oCtx:oReq:Header( "X-Api-Key", "" )
       IF cProvided != scKey                                // Nota: != no es fiable en strings; usa == abajo
          oCtx:lHandled := .T.
          oCtx:oReq:Respond( { "error" => "Unauthorized" }, 401, "json" )
          RETURN .F.
       ENDIF
    RETURN .T.

    // Factory: devuelve un codeblock -- para uso multi-instancia.
    FUNCTION HixMwApiKeyFactory( cKey )
    RETURN {|oCtx| iif( oCtx:oReq:Header("X-Api-Key","") == cKey, .T., ;
                   ( oCtx:lHandled := .T., oCtx:oReq:Respond({=>},401,"json"), .F. ) ) }

## `oCtx` — THixContext

| Propiedad | Significado |
|-----------|-------------|
| `oReq` | `THixRequest` actual |
| `hData` | Hash libre para que los MWs compartan datos (`hData["jwt"]`, `hData["session"]`, `hData["user"]`) |
| `lHandled` | Ponlo a `.T.` cuando ya has respondido para que el router no ejecute la acción |
| `cScope` | String de metadata de la ruta |
| `cOnFail` | Nombre de ruta a la que redirigir si el MW devuelve `.F.` |

## Vincular a rutas

Imperativo:

    oSrv:AddRouteGet( "admin", "/admin", bAction, "HIX_MwSession,MyGuard" )

Declarativo (JSON de rutas):

    { "url": "/admin", "method": "GET", "action": "admin@x", "middleware": "HIX_MwSession,MyGuard" }

La cadena se ejecuta de izquierda a derecha; el primer `.F.` aborta.

## Middleware incluido

| Nombre | Función setup | Propósito |
|--------|---------------|-----------|
| `HIX_MwSession` | `HIX_MwSessionSetup( cookie, ttl, gcEvery, storage, dir, prefix, encrypt, seed, cookieDays )` | Sesiones en memoria o fichero |
| `HIX_MwCsrf` | `HIX_MwCsrfSetup( redirect, ttl )` | Emisión + verificación de token CSRF |
| `HIX_MwCors` | `HIX_MwCorsSetup( origin, methods, headers )` | Headers CORS + preflight |
| `HIX_MwRateLimit` | `HIX_MwRateLimitSetup( ipPerMin, windowS )` | Throttle por IP |
| `HIX_MwJwt` | `HIX_MwJwtSetup( cKey, nExp )` | Verificar Bearer JWT |
| `HIX_MwMethodFilter` | `HIX_MwMethodFilterSetup( aMethods )` | Rechazar métodos no listados |

## Auto-apply desde `www/middlewares/config.json`

Bajo hixstyle, `HIX_LoadMiddleware()` llama a cada setup según el nombre de sección:

    {
      "load": [ "custom_guard.prg" ],
      "setup": {
        "cors":       { "origin": "*", "methods": "GET,POST", "headers": "Content-Type" },
        "session":    { "cookie": "sid", "ttl": 3600, "max": 60, "storage": "memory" },
        "csrf":       { "redirect": "/login", "ttl": 3600 },
        "ratelimit":  { "ip_per_min": 60, "window_s": 60 },
        "jwt":        { "key_ref": "jwt", "exp": 3600 },
        "methodfilter": { "methods": [ "GET", "POST", "OPTIONS" ] }
      }
    }

`jwt.key_ref` se resuelve contra `HIX_KeyGet(cRef)`, que a su vez se puebla desde `www/config.json > keys`.

Sección ausente = STATIC intacto (no sobrescribe).

## Patrón de rechazo

Al rechazar desde un middleware, siempre pon `lHandled`, responde, devuelve `.F.`:

    oCtx:lHandled := .T.
    IF oCtx:oReq:IsAjax() .OR. HIX_WantsJson( oCtx:oReq )
       oCtx:oReq:Respond( { "error" => "Forbidden" }, 403, "json" )
    ELSE
       oCtx:oReq:Redirect( "/login", 302 )
    ENDIF
    RETURN .F.

## Getters de config (para tests)

`HIX_MwCorsConfig()`, `HIX_MwRateLimitConfig()`, `HIX_MwMethodFilterConfig()`, `HIX_MwJwtConfig()` devuelven el estado actual del STATIC.
