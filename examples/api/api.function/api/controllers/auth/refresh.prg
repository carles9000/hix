/*-----------------------------------------------------------
  File ......: refresh.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 1.0.0
  Description: POST /refresh -- exchange a valid refresh token
               for a new access token plus a rotated refresh
               token. Enforces rotation: the old token is
               revoked and a new one is issued.

               Reuse detection: if a revoked token is presented
               the whole forward chain is revoked and the client
               must login again.

               Response 200: same shape as /login.

               Failures:
                 415 non-JSON body
                 422 validation error
                 401 invalid/expired/revoked (AUTH_REFRESH_INVALID)
  Usage      : POST /refresh
               Content-Type: application/json
               { "refresh_token": "..." }
 -----------------------------------------------------------*/


FUNCTION Main()

   LOCAL oVal, hRotated, hUser, cAccess, nExp

   IF ! UEnforceJson()
      RETURN NIL
   ENDIF

   oVal := UValidateJson( { ;
      "refresh_token" => "required|string|minlen:16|maxlen:128" ;
   } )

   IF ! oVal:Make()
      USendApiError( "VALIDATION_FAILED", oVal:GetErrorsTxt(), 422, ;
         { "fields" => oVal:GetErrorsJson() } )
      RETURN NIL
   ENDIF

   hRotated := ModelRefreshRotate( oVal:Get( "refresh_token" ), UIP() )

   IF hRotated == NIL
      USendApiError( "AUTH_REFRESH_INVALID", ;
         "Refresh token is invalid, expired or revoked", 401, ;
         { "hint" => "Login again via POST /login" } )
      AuditLog( "auth.fail", { "reason" => "refresh_invalid" } )
      RETURN NIL
   ENDIF

   hUser := ModelUserFindById( hRotated[ "user_id" ] )

   IF hUser == NIL
      USendApiError( "AUTH_USER_NOT_FOUND", "User no longer exists", 401 )
      RETURN NIL
   ENDIF

   nExp    := UMwConfig( "jwt", "exp", 900 )
   cAccess := HIX_JwtEncode( { ;
      "sub"   => hUser[ "id"    ], ;
      "name"  => hUser[ "name"  ], ;
      "scope" => hUser[ "scope" ]  ;
   }, HIX_KeyGet( "jwt" ), nExp )

   USendApi( { ;
      "access_token"  => cAccess, ;
      "token_type"    => "Bearer", ;
      "expires_in"    => nExp, ;
      "refresh_token" => hRotated[ "token" ] ;
   } )

   AuditLog( "auth.refresh", { "sub" => hUser[ "id" ] } )

RETURN NIL


#include '/models/modeluser.prg'
#include '/models/modelrefresh.prg'
