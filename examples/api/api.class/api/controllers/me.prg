/*-----------------------------------------------------------
  File ......: me.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 1.0.0
  Description: GET /me -- returns the authenticated user's
               profile derived from the JWT payload (no DB
               hit). Requires MyWsGuardScope + scope me:read.
  Usage      : GET /me
               Authorization: Bearer <token>
               Route action: controllers/read@me.prg
 -----------------------------------------------------------*/

#include "hbclass.ch"

CLASS MeController

   METHOD New()  CONSTRUCTOR
   METHOD End()
   METHOD Read()

ENDCLASS


METHOD New() CLASS MeController
RETURN SELF


METHOD End() CLASS MeController
RETURN SELF


METHOD Read() CLASS MeController

   LOCAL hUser := UWho()

   IF hUser == NIL
      USendApiError( "AUTH_UNAUTHENTICATED", "Authentication required", 401 )
      RETURN NIL
   ENDIF

   USendApi( { ;
      "id"    => hb_HGetDef( hUser, "sub",   "" ), ;
      "name"  => hb_HGetDef( hUser, "name",  "" ), ;
      "scope" => hb_HGetDef( hUser, "scope", "" )  ;
   } )

RETURN NIL
