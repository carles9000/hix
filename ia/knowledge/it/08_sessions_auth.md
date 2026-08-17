# Sessioni e Auth

## Sessioni

### Setup (prima di `Start()`)

    HIX_MwSessionSetup( ;
       "hix_sess",   ;   // nome cookie
       3600,         ;   // TTL sessione (secondi)
       60,           ;   // GC ogni N chiamate
       "memory",     ;   // "memory" | "file"
       "sessions/",  ;   // se storage="file", directory
       "sess_",      ;   // prefisso nome file
       .F.,          ;   // cripta su disco
       "",           ;   // seed di crittografia
       7 )               // durata cookie (giorni)

Registra sulla route o sul gruppo come `HIX_MwSession`.

Sotto hixstyle, metti in `www/middlewares/config.json`:

    "session": { "cookie": "sid", "ttl": 3600, "max": 60, "storage": "memory" }

### Lettura / scrittura da un'action

    // Forma breve (request thread-local)
    LOCAL cUser := USession( "user" )                  // read, NIL se mancante
    USession():Set( "user", hUserHash )                // write
    USession():Save()                                  // persist + refresh cookie
    USession():Destroy()                               // wipe + expire cookie

    // Forma lunga (con context esplicito)
    HIX_SessionGet( oCtx, "user" )
    HIX_SessionSet( oCtx, "user", hUserHash )
    HIX_SessionSave( oCtx )
    HIX_SessionDestroy( oCtx )

`oCtx:hData["session"]` = hash di sessione completo. `oCtx:hData["_sid"]` = stringa SID corrente.

### Comportamento dei cookie

Gli header `Set-Cookie` usano `HttpOnly; SameSite=Lax; Path=/`.

    HIX_SetCookie( oReq, cName, cValue, nMaxAge )
    // nMaxAge = 0   → cookie di sessione (no header Max-Age)
    //         = -1  → scade immediatamente
    //         = > 0 → secondi

Da un'action usa `USetCookie( cName, cValue, nMaxAge )`.

## JWT

### Setup

    HIX_MwJwtSetup( "SUPER_SECRET_KEY", 3600 )   // key, exp in secondi

O in `www/middlewares/config.json`:

    "jwt": { "key_ref": "jwt", "exp": 3600 }

`key_ref` viene risolto tramite `HIX_KeyGet( cRef )` popolato da `www/config.json > keys`.

### Collegamento

    { "url": "/api/*", "method": "GET", "action": "api@fanout", "middleware": "HIX_MwJwt" }

Quando il JWT passa, il payload è disponibile come `oCtx:hData["jwt"]`. Da un'action:

    LOCAL hClaims := HIX_JwtClaims()   // ritorna hash
    LOCAL cUserId := hb_HGetDef( hClaims, "sub", "" )

### Emettere un token (endpoint di login)

    LOCAL cJwt := HIX_JwtEncode( { "sub" => cUserId, "role" => "admin" }, "SUPER_SECRET_KEY", 3600 )
    USendJson( { "token" => cJwt } )

Oppure:

    LOCAL cKey := HIX_KeyGet( "jwt" )
    LOCAL cJwt := HIX_JwtEncode( { "sub" => cUserId }, cKey, 3600 )

## Middleware di auth custom (basato su sessione)

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

## Guardie per ruolo

    FUNCTION HixMwRequireAdmin( oCtx )
       LOCAL hUser := HIX_Session( "user" )
       IF Empty( hUser ) .OR. hb_HGetDef( hUser, "role", "" ) != "admin"
          oCtx:lHandled := .T.
          oCtx:oReq:Respond( { "error" => "Forbidden" }, 403, "json" )
          RETURN .F.
       ENDIF
    RETURN .T.

Catena: `"HIX_MwSession,HixMwRequireAuth,HixMwRequireAdmin"`

## Regole d'oro

- Il middleware di sessione deve girare PRIMA di qualsiasi codice che legge/scrive la sessione.
- JWT e sessione sono indipendenti — puoi usare entrambi (JWT per API, sessione per web).
- CSRF è separato (`HIX_MwCsrf`) — abilitalo sui form web che cambiano stato; non serve per le API protette da JWT.
- Non memorizzare mai le password in sessione; hashale (bcrypt/argon2 via contribs Harbour) e conserva l'hash nel DB, l'user_id in sessione.
