# Middleware

Middleware runs before the route action. Two return values:
- `.T.` — continue chain
- `.F.` — abort (route action not executed)

## Standard pattern

Every HIX middleware follows this trio:

    // Setup: called once at boot, stores config in a STATIC.
    PROCEDURE HixMwApiKeySetup( cKey )
       STATIC scKey := ""
       scKey := cKey
    RETURN

    // Direct middleware.
    FUNCTION HixMwApiKey( oCtx )
       LOCAL cProvided := oCtx:oReq:Header( "X-Api-Key", "" )
       IF cProvided != scKey                                // Note: != is unsafe on strings; use == below
          oCtx:lHandled := .T.
          oCtx:oReq:Respond( { "error" => "Unauthorized" }, 401, "json" )
          RETURN .F.
       ENDIF
    RETURN .T.

    // Factory: returns a codeblock — for multi-instance use.
    FUNCTION HixMwApiKeyFactory( cKey )
    RETURN {|oCtx| iif( oCtx:oReq:Header("X-Api-Key","") == cKey, .T., ;
                   ( oCtx:lHandled := .T., oCtx:oReq:Respond({=>},401,"json"), .F. ) ) }

## `oCtx` — THixContext

| Property | Meaning |
|----------|---------|
| `oReq` | Current `THixRequest` |
| `hData` | Free hash for MWs to share data (`hData["jwt"]`, `hData["session"]`, `hData["user"]`) |
| `lHandled` | Set `.T.` when you already responded so router skips action |
| `cScope` | Route metadata string |
| `cOnFail` | Route name to redirect to if MW returns `.F.` |

## Attach to routes

Imperative:

    oSrv:AddRouteGet( "admin", "/admin", bAction, "HIX_MwSession,MyGuard" )

Declarative (routes JSON):

    { "url": "/admin", "method": "GET", "action": "admin@x", "middleware": "HIX_MwSession,MyGuard" }

Chain executes left to right; first `.F.` aborts.

## Bundled middleware

| Name | Setup fn | Purpose |
|------|----------|---------|
| `HIX_MwSession` | `HIX_MwSessionSetup( cookie, ttl, gcEvery, storage, dir, prefix, encrypt, seed, cookieDays )` | In-memory or file sessions |
| `HIX_MwCsrf` | `HIX_MwCsrfSetup( redirect, ttl )` | CSRF token issue + verify |
| `HIX_MwCors` | `HIX_MwCorsSetup( origin, methods, headers )` | CORS headers + preflight |
| `HIX_MwRateLimit` | `HIX_MwRateLimitSetup( ipPerMin, windowS )` | IP throttle |
| `HIX_MwJwt` | `HIX_MwJwtSetup( cKey, nExp )` | Verify Bearer JWT |
| `HIX_MwMethodFilter` | `HIX_MwMethodFilterSetup( aMethods )` | Reject non-listed methods |

## Auto-apply from `www/middlewares/config.json`

Under hixstyle, `HIX_LoadMiddleware()` calls each setup based on section name:

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

`jwt.key_ref` resolves against `HIX_KeyGet(cRef)` which is populated from `www/config.json > keys`.

Missing section = STATIC not touched (no overwrite).

## Reject pattern

When rejecting from a middleware, always set `lHandled`, respond, return `.F.`:

    oCtx:lHandled := .T.
    IF oCtx:oReq:IsAjax() .OR. HIX_WantsJson( oCtx:oReq )
       oCtx:oReq:Respond( { "error" => "Forbidden" }, 403, "json" )
    ELSE
       oCtx:oReq:Redirect( "/login", 302 )
    ENDIF
    RETURN .F.

## Config getters (for tests)

`HIX_MwCorsConfig()`, `HIX_MwRateLimitConfig()`, `HIX_MwMethodFilterConfig()`, `HIX_MwJwtConfig()` return the current STATIC state.
