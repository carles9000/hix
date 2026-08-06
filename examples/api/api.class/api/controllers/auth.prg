/*-----------------------------------------------------------
  File ......: auth.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 1.0.0
  Description: Authentication controller. Consolidates login,
               refresh and logout into a single class.

               Login  POST /login   -- exchange credentials for
                                       access + refresh tokens.
               Refresh POST /refresh -- rotate refresh token into
                                        a new access token.
               Logout POST /logout  -- revoke the refresh token.

  Usage      : Route actions:
                 controllers/login@auth.prg
                 controllers/refresh@auth.prg
                 controllers/logout@auth.prg
 -----------------------------------------------------------*/

#include "hbclass.ch"

CLASS AuthController

   METHOD New()     CONSTRUCTOR
   METHOD End()
   METHOD Login()
   METHOD Refresh()
   METHOD Logout()

ENDCLASS


METHOD New() CLASS AuthController
RETURN SELF


METHOD End() CLASS AuthController
RETURN SELF


// ============================================================
// POST /login
// ============================================================
METHOD Login() CLASS AuthController

   LOCAL oVal, hAuth, hIssued, cAccess, nExp

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


// ============================================================
// POST /refresh
// ============================================================
METHOD Refresh() CLASS AuthController

   LOCAL oVal, hRotated, hUser, cAccess, nExp

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


// ============================================================
// POST /logout
// ============================================================
METHOD Logout() CLASS AuthController

   LOCAL oVal, hUser

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


#include '/models/modeluser.prg'
#include '/models/modelrefresh.prg'
