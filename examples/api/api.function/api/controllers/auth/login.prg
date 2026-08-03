/*-----------------------------------------------------------
  File ......: login.prg
  Author.....: Charly 9000
  Created....: 2026-07-19
  Modified...: 2026-07-23
  Version....: 2.0.0
  Description: POST /login -- exchange { username, password }
               for a JWT access token plus a rotating refresh
               token.

               Response 200:
                 {
                   "data": {
                     "access_token":  "eyJ...",
                     "token_type":    "Bearer",
                     "expires_in":    900,
                     "refresh_token": "..."
                   }
                 }

               Failures:
                 415 non-JSON body
                 422 validation error
                 401 bad credentials (AUTH_INVALID_CREDENTIALS)

               Login attempts (success and fail) are audited
               via AuditLog.
  Usage      : POST /login
               Content-Type: application/json
               { "username": "admin", "password": "admin123" }
 -----------------------------------------------------------*/

#include "hbclass.ch"


FUNCTION Main()

   LOCAL oVal, hAuth, hIssued, cAccess, nExp

   IF ! UEnforceJson()
      RETURN NIL
   ENDIF

   oVal := UValidatePost( { ;
      "username" => "required|string|minlen:3|maxlen:30", ;
      "password" => "required|string|minlen:4|maxlen:128" ;
   }, { "username" => "lower|trim" } )

   IF ! oVal:Make()
      USendApiError( "VALIDATION_FAILED", oVal:GetErrorsTxt(), 422, ;
         { "fields" => oVal:GetErrorsJson() } )
      AuditLog( "auth.fail", { "reason" => "validation" } )
      RETURN NIL
   ENDIF

   hAuth := ModelUserAuthenticate( oVal:Get( "username" ), oVal:Get( "password" ) )

   IF hAuth == NIL
      USendApiError( "AUTH_INVALID_CREDENTIALS", ;
         "Invalid username or password", 401, ;
         { "hint" => "Check credentials or contact your administrator" } )
      AuditLog( "auth.fail", { "reason" => "bad_credentials", "user" => oVal:Get( "username" ) } )
      RETURN NIL
   ENDIF

   nExp    := UMwConfig( "jwt", "exp", 900 )
   cAccess := HIX_JwtEncode( hAuth, HIX_KeyGet( "jwt" ), nExp )
   
   hIssued := ModelRefreshIssue( hAuth[ "sub" ], UIP() )

   USendApi( { ;
      "access_token"  => cAccess, ;
      "token_type"    => "Bearer", ;
      "expires_in"    => nExp, ;
      "refresh_token" => hIssued[ "token" ] ;
   } )

   AuditLog( "auth.login", { "user" => oVal:Get( "username" ), "sub" => hAuth[ "sub" ] } )

RETURN NIL


#include '/models/modeluser.prg'
#include '/models/modelrefresh.prg'
