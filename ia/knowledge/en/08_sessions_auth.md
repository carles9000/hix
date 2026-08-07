# Sessions & Auth

## Sessions

### Setup (before `Start()`)

    HIX_MwSessionSetup( ;
       "hix_sess",   ;   // cookie name
       3600,         ;   // session TTL (seconds)
       60,           ;   // GC every N calls
       "memory",     ;   // "memory" | "file"
       "sessions/",  ;   // if storage="file", directory
       "sess_",      ;   // filename prefix
       .F.,          ;   // encrypt on disk
       "",           ;   // encryption seed
       7 )               // cookie lifetime (days)

Register on the route or group as `HIX_MwSession`.

Under hixstyle, put in `www/middlewares/config.json`:

    "session": { "cookie": "sid", "ttl": 3600, "max": 60, "storage": "memory" }

### Reading / writing from an action

    // Short form (thread-local request)
    LOCAL cUser := USession( "user" )                  // read, NIL if missing
    USession():Set( "user", hUserHash )                // write
    USession():Save()                                  // persist + refresh cookie
    USession():Destroy()                               // wipe + expire cookie

    // Long form (with explicit context)
    HIX_SessionGet( oCtx, "user" )
    HIX_SessionSet( oCtx, "user", hUserHash )
    HIX_SessionSave( oCtx )
    HIX_SessionDestroy( oCtx )

`oCtx:hData["session"]` = full session hash. `oCtx:hData["_sid"]` = current SID string.

### Cookie behaviour

`Set-Cookie` headers use `HttpOnly; SameSite=Lax; Path=/`.

    HIX_SetCookie( oReq, cName, cValue, nMaxAge )
    // nMaxAge = 0   → session cookie (no Max-Age header)
    //         = -1  → expire immediately
    //         = > 0 → seconds

From an action use `USetCookie( cName, cValue, nMaxAge )`.

## JWT

### Setup

    HIX_MwJwtSetup( "SUPER_SECRET_KEY", 3600 )   // key, exp in seconds

Or in `www/middlewares/config.json`:

    "jwt": { "key_ref": "jwt", "exp": 3600 }

`key_ref` resolves against `HIX_KeyGet( cRef )` populated from `www/config.json > keys`.

### Attach

    { "url": "/api/*", "method": "GET", "action": "api@fanout", "middleware": "HIX_MwJwt" }

When JWT passes, payload is available as `oCtx:hData["jwt"]`. From an action:

    LOCAL hClaims := HIX_JwtClaims()   // returns hash
    LOCAL cUserId := hb_HGetDef( hClaims, "sub", "" )

### Issue a token (login endpoint)

    LOCAL cJwt := HIX_JwtEncode( { "sub" => cUserId, "role" => "admin" }, "SUPER_SECRET_KEY", 3600 )
    USendJson( { "token" => cJwt } )

Or:

    LOCAL cKey := HIX_KeyGet( "jwt" )
    LOCAL cJwt := HIX_JwtEncode( { "sub" => cUserId }, cKey, 3600 )

## Custom auth middleware (session-based)

    FUNCTION HixMwRequireAuth( oCtx )
       IF Empty( HIX_Session( "user" ) )
          oCtx:lHandled := .T.
          IF oCtx:oReq:IsAjax() .OR. HIX_WantsJson( oCtx:oReq )
             oCtx:oReq:Respond( { "error" => "Not authenticated" }, 401, "json" )
          ELSE
             oCtx:oReq:Redirect( "/login", 302 )
          ENDIF
          RETURN .F.
       ENDIF
    RETURN .T.

## Role guards

    FUNCTION HixMwRequireAdmin( oCtx )
       LOCAL hUser := HIX_Session( "user" )
       IF Empty( hUser ) .OR. hb_HGetDef( hUser, "role", "" ) != "admin"
          oCtx:lHandled := .T.
          oCtx:oReq:Respond( { "error" => "Forbidden" }, 403, "json" )
          RETURN .F.
       ENDIF
    RETURN .T.

Chain: `"HIX_MwSession,HixMwRequireAuth,HixMwRequireAdmin"`

## Golden rules

- Session middleware must run BEFORE any code that reads/writes session.
- JWT and session are independent — you can use both (JWT for API, session for web).
- CSRF is separate (`HIX_MwCsrf`) — enable on state-changing web forms; not needed for JWT-protected APIs.
- Never store passwords in session; hash them (bcrypt/argon2 via Harbour contribs) and store the hash in the DB, the user_id in session.
