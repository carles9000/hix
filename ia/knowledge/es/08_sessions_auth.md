# Sesiones y Auth

## Sesiones

### Setup (antes de `Start()`)

    HIX_MwSessionSetup( ;
       "hix_sess",   ;   // nombre cookie
       3600,         ;   // TTL sesión (segundos)
       60,           ;   // GC cada N llamadas
       "memory",     ;   // "memory" | "file"
       "sessions/",  ;   // si storage="file", directorio
       "sess_",      ;   // prefijo fichero
       .F.,          ;   // encriptar en disco
       "",           ;   // seed encriptación
       7 )               // vida cookie (días)

Registra como `HIX_MwSession` en la ruta o grupo.

Bajo hixstyle, en `www/middlewares/config.json`:

    "session": { "cookie": "sid", "ttl": 3600, "max": 60, "storage": "memory" }

### Leer / escribir desde una acción

    // Forma corta (request thread-local)
    LOCAL cUser := USession( "user" )                  // lee, NIL si no existe
    USession():Set( "user", hUserHash )                // escribe
    USession():Save()                                  // persiste + renueva cookie
    USession():Destroy()                               // limpia + expira cookie

    // Forma larga (con contexto explícito)
    HIX_SessionGet( oCtx, "user" )
    HIX_SessionSet( oCtx, "user", hUserHash )
    HIX_SessionSave( oCtx )
    HIX_SessionDestroy( oCtx )

`oCtx:hData["session"]` = hash completo de la sesión. `oCtx:hData["_sid"]` = SID actual.

### Comportamiento de la cookie

Los headers `Set-Cookie` llevan `HttpOnly; SameSite=Lax; Path=/`.

    HIX_SetCookie( oReq, cName, cValue, nMaxAge )
    // nMaxAge = 0   → cookie de sesión (sin Max-Age)
    //         = -1  → expira inmediatamente
    //         = > 0 → segundos

Desde una acción usa `USetCookie( cName, cValue, nMaxAge )`.

## JWT

### Setup

    HIX_MwJwtSetup( "SUPER_SECRET_KEY", 3600 )   // clave, exp en segundos

O en `www/middlewares/config.json`:

    "jwt": { "key_ref": "jwt", "exp": 3600 }

`key_ref` se resuelve contra `HIX_KeyGet( cRef )` poblado desde `www/config.json > keys`.

### Enganchar

    { "url": "/api/*", "method": "GET", "action": "api@fanout", "middleware": "HIX_MwJwt" }

Cuando el JWT valida, el payload queda en `oCtx:hData["jwt"]`. Desde una acción:

    LOCAL hClaims := HIX_JwtClaims()   // devuelve hash
    LOCAL cUserId := hb_HGetDef( hClaims, "sub", "" )

### Emitir un token (endpoint de login)

    LOCAL cJwt := HIX_JwtEncode( { "sub" => cUserId, "role" => "admin" }, "SUPER_SECRET_KEY", 3600 )
    USendJson( { "token" => cJwt } )

O:

    LOCAL cKey := HIX_KeyGet( "jwt" )
    LOCAL cJwt := HIX_JwtEncode( { "sub" => cUserId }, cKey, 3600 )

## Middleware auth propio (basado en sesión)

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

## Guards de rol

    FUNCTION HixMwRequireAdmin( oCtx )
       LOCAL hUser := HIX_Session( "user" )
       IF Empty( hUser ) .OR. hb_HGetDef( hUser, "role", "" ) != "admin"
          oCtx:lHandled := .T.
          oCtx:oReq:Respond( { "error" => "Forbidden" }, 403, "json" )
          RETURN .F.
       ENDIF
    RETURN .T.

Cadena: `"HIX_MwSession,HixMwRequireAuth,HixMwRequireAdmin"`

## Reglas de oro

- El middleware de sesión DEBE ejecutarse ANTES de cualquier código que la lea/escriba.
- JWT y sesión son independientes — puedes usar ambos (JWT para API, sesión para web).
- CSRF va aparte (`HIX_MwCsrf`) — actívalo en forms web que modifican estado; no hace falta para APIs con JWT.
- Nunca guardes contraseñas en sesión; hashea (bcrypt/argon2 vía contribs de Harbour), guarda el hash en la BBDD y el user_id en la sesión.
