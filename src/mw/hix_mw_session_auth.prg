/*-----------------------------------------------------------
  File ......: hix_mw_session_auth.prg
  Author.....: Charly 9000
  Created....: 2026-06-02
  Modified...: 2026-06-06
  Version....: 2.0.0
  Description: Session-based auth middleware primitives.
               HIX_MwIsAuth  — reads session user, puts in hData["user"].
               HIX_MwHasRole — checks oCtx:cScope against user roles.
  Usage      : o:Add( UMiddleware():New( "HIX_MwIsAuth"  ) )
               o:Add( UMiddleware():New( "HIX_MwHasRole" ) )  // scope = "masters"
               o:Add( UMiddleware():New( "HIX_MwHasRole" ) )  // scope = "compras:delete"
  Notes      : Keys are read from MW setup "auth" section (config.json).
               Defaults: session_user_key="_auth_user", roles_key="roles"
               Roles hash: key=role name, value="" (full) or "op1;op2" (granular).
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"

// Reads the user hash from session and puts it in hData["user"].
// Redirects to redirect_login (302) if no user found.
FUNCTION HIX_MwIsAuth( oCtx )

   LOCAL hUser := hb_HGetDef( oCtx:hData[ "session" ], ;
      UMwConfig( "auth", "session_user_key", "_auth_user" ), NIL )

   IF ValType( hUser ) != "H"

      oCtx:oReq:Respond( "", 302, "text", ;
         { "Location" => UMwConfig( "auth", "redirect_login", "/login" ) } )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

   oCtx:hData[ "user" ]      := hUser
   oCtx:oReq:hData[ "user" ] := hUser

RETURN .T.

// Checks oCtx:cScope against user roles hash.
// scope = "customers"        -> user has the role (any ops or full access)
// scope = "customers:delete" -> user has the role with op "delete"
// Empty scope -> always pass.
// Empty ops value in hash means full access (any op returns .T.).
// 403 if role missing or op not allowed.
FUNCTION HIX_MwHasRole( oCtx )

   LOCAL cKey   := UMwConfig( "auth", "roles_key", "roles" )
   LOCAL hRoles := hb_HGetDef( hb_HGetDef( oCtx:hData, "user", { => } ), cKey, { => } )
   LOCAL aScope, cRole, cOp, cOps

   IF Empty( oCtx:cScope )

      RETURN .T.

   ENDIF

   aScope := hb_ATokens( oCtx:cScope, ":" )
   cRole  := aScope[ 1 ]
   cOp    := iif( Len( aScope ) > 1, aScope[ 2 ], "" )
   cOps   := hb_HGetDef( hRoles, cRole, NIL )

   IF cOps == NIL

      oCtx:oReq:Respond( "", 403, "text", {} )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

   IF Empty( cOps ) .OR. Empty( cOp )

      RETURN .T.

   ENDIF

   IF !( ";" + cOp + ";" $ ";" + cOps + ";" )

      oCtx:oReq:Respond( "", 403, "text", {} )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

RETURN .T.
