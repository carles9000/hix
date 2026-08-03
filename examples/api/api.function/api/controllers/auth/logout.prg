/*-----------------------------------------------------------
  File ......: logout.prg
  Author.....: Charly 9000
  Created....: 2026-07-19
  Modified...: 2026-07-23
  Version....: 2.0.0
  Description: POST /logout -- revoke the presented refresh
               token. Requires a valid Bearer access token
               (MyWsGuardAuth). The access token itself is
               NOT revoked server-side (short TTL, stateless
               JWT); only the refresh token is invalidated.
               Silent success if the token was already revoked.
  Usage      : POST /logout
               Authorization: Bearer <access>
               Content-Type: application/json
               { "refresh_token": "..." }
 -----------------------------------------------------------*/


FUNCTION Main()

   LOCAL oVal, hUser

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

   ModelRefreshRevoke( oVal:Get( "refresh_token" ) )

   hUser := UWho()
   
   AuditLog( "auth.logout", { ;
      "sub" => iif( hUser != NIL, hb_HGetDef( hUser, "sub", "" ), "" ) ;
   } )

   USendApi( { "revoked" => .T. } )

RETURN NIL


#include '/models/modelrefresh.prg'
