# Middleware

Il middleware gira prima dell'action della route. Due valori di ritorno:
- `.T.` — continua la catena
- `.F.` — interrompe (action della route non eseguita)

## Pattern standard

Ogni middleware HIX segue questo trio:

    // Setup: chiamato una volta al boot, salva la config in una STATIC.
    PROCEDURE HixMwApiKeySetup( cKey )
       STATIC scKey := ""
       scKey := cKey
    RETURN

    // Middleware diretto.
    FUNCTION HixMwApiKey( oCtx )
       LOCAL cProvided := oCtx:oReq:Header( "X-Api-Key", "" )
       IF cProvided != scKey                                // Nota: != è insicuro sulle stringhe; usa == sotto
          oCtx:lHandled := .T.
          oCtx:oReq:Respond( { "error" => "Unauthorized" }, 401, "json" )
          RETURN .F.
       ENDIF
    RETURN .T.

    // Factory: ritorna un codeblock — per uso multi-istanza.
    FUNCTION HixMwApiKeyFactory( cKey )
    RETURN {|oCtx| iif( oCtx:oReq:Header("X-Api-Key","") == cKey, .T., ;
                   ( oCtx:lHandled := .T., oCtx:oReq:Respond({=>},401,"json"), .F. ) ) }

## `oCtx` — THixContext

| Proprietà | Significato |
|----------|---------|
| `oReq` | `THixRequest` corrente |
| `hData` | Hash libero per condividere dati tra MW (`hData["jwt"]`, `hData["session"]`, `hData["user"]`) |
| `lHandled` | Imposta `.T.` quando hai già risposto così il router salta l'action |
| `cScope` | Stringa metadata della route |
| `cOnFail` | Nome route per redirect se il MW ritorna `.F.` |

## Collegamento alle route

Imperativo:

    oSrv:AddRouteGet( "admin", "/admin", bAction, "HIX_MwSession,MyGuard" )

Dichiarativo (route JSON):

    { "url": "/admin", "method": "GET", "action": "admin@x", "middleware": "HIX_MwSession,MyGuard" }

La catena viene eseguita da sinistra a destra; il primo `.F.` interrompe.

## Middleware integrati

| Nome | Funzione di setup | Scopo |
|------|----------|---------|
| `HIX_MwSession` | `HIX_MwSessionSetup( cookie, ttl, gcEvery, storage, dir, prefix, encrypt, seed, cookieDays )` | Sessioni in memoria o su file |
| `HIX_MwCsrf` | `HIX_MwCsrfSetup( redirect, ttl )` | Genera e verifica token CSRF |
| `HIX_MwCors` | `HIX_MwCorsSetup( origin, methods, headers )` | Header CORS + preflight |
| `HIX_MwRateLimit` | `HIX_MwRateLimitSetup( ipPerMin, windowS )` | Throttle per IP |
| `HIX_MwJwt` | `HIX_MwJwtSetup( cKey, nExp )` | Verifica Bearer JWT |
| `HIX_MwMethodFilter` | `HIX_MwMethodFilterSetup( aMethods )` | Rifiuta metodi non in lista |

## Auto-applicazione da `www/middlewares/config.json`

Sotto hixstyle, `HIX_LoadMiddleware()` chiama ogni setup in base al nome della sezione:

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

`jwt.key_ref` viene risolto tramite `HIX_KeyGet(cRef)` che è popolato da `www/config.json > keys`.

Sezione mancante = la STATIC non viene toccata (nessuna sovrascrittura).

## Pattern di rifiuto

Quando rifiuti da un middleware, imposta sempre `lHandled`, rispondi, ritorna `.F.`:

    oCtx:lHandled := .T.
    IF oCtx:oReq:IsAjax() .OR. HIX_WantsJson( oCtx:oReq )
       oCtx:oReq:Respond( { "error" => "Forbidden" }, 403, "json" )
    ELSE
       oCtx:oReq:Redirect( "/login", 302 )
    ENDIF
    RETURN .F.

## Getter di config (per i test)

`HIX_MwCorsConfig()`, `HIX_MwRateLimitConfig()`, `HIX_MwMethodFilterConfig()`, `HIX_MwJwtConfig()` ritornano lo stato STATIC corrente.
