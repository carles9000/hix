/*-----------------------------------------------------------
  File ......: hix_mw_auth.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Parametrizable authentication middleware for HIX.
               Handles session-based login/logout and route protection.
               Designed as a standalone module — copy to your app and
               customize via HIX_MwAuthSetup().
  Usage      : See examples/auth_session/ for a complete working example.
  Notes      : Web: yes (session) | API: yes (JWT fallback)
 -----------------------------------------------------------*/

// ============================================================
// Auth — session-based login + route protection
//
// Concept:
// HIX_MwAuth handles the login (POST) and logout flows.
// HIX_MwRequireAuth is the route guard: it checks whether
// a valid user exists in the session (or JWT fallback) and
// rejects with 401 if not.
//
// The user hash is stored in oCtx:hData["user"] and also in
// a THREAD STATIC (s_hCurrentUser) accessible via UCurrentUser().
//
// Pipeline order (session-based):
// HIX_MwSession  ->  HIX_MwAuth  ->  HIX_MwRequireAuth
//
// Pipeline order (JWT fallback):
// HIX_MwJwt  ->  HIX_MwRequireAuth
//
// User hash format (returned by bValidate):
// { "id" => "1", "name" => "Alice",
// "roles" => { "admin" => "", "editor" => "" } }
//
// roles hash: key = role name, value = "" (full access) or "op1;op2" (granular).
// Use when:
// - Traditional web app with login form + server-side sessions
// - API that supports both session cookies and JWT Bearer tokens
//
// Web: yes — primary auth mechanism with cookies
// API: yes — combine with HIX_MwJwt for stateless fallback
//
// Example — minimal setup:
// HIX_MwAuthSetup( { ;
// "bValidate"   => {|u,p| iif(u=="admin".AND.p=="1234", ;
// {"id"=>"1","name"=>"Admin"}, NIL)}, ;
// "cRedirectOk" => "/dashboard" ;
// } )
// oSrv:AddRoutePost( "login",  "/login",  {||NIL}, { "HIX_MwSession", "HIX_MwAuth" } )
// oSrv:AddRouteGet(  "logout", "/logout", {||NIL}, { "HIX_MwSession", "HIX_MwAuth" } )
// oSrv:AddRouteGet(  "dash",   "/dashboard", {|| USendHtml("<h1>Hi</h1>") }, ;
// { "HIX_MwSession", "HIX_MwRequireAuth" } )
//
// Example — role-based protection (via session_auth pipeline):
// o:Add( UMiddleware():New( "HIX_MwSession"   ) )
// o:Add( UMiddleware():New( "HIX_MwIsAuth"    ) )
// o:Add( UMiddleware():New( "HIX_MwHasRole"   ) )  // scope = "admin"
// ============================================================

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_bValidate     := NIL
STATIC s_cLoginRoute   := "/login"
STATIC s_cLogoutRoute  := "/logout"
STATIC s_cUserField    := "username"
STATIC s_cPassField    := "password"
STATIC s_cRedirectOk   := ""
STATIC s_cRedirectFail := ""
STATIC s_cSessionKey   := "_auth_user"

// Per-thread current user — set by HIX_MwRequireAuth, read by UCurrentUser()
THREAD STATIC s_hCurrentUser := NIL

// ============================================================
// HIX_MwAuthSetup — configure auth module before Start().
//
// hConfig keys (all optional except bValidate):
// bValidate     {|cUser,cPass| ...} -> hash user or NIL if invalid
// cLoginRoute   POST route for login             (default "/login")
// cLogoutRoute  route for logout GET or POST     (default "/logout")
// cUserField    field name for username in body  (default "username")
// cPassField    field name for password in body  (default "password")
// cRedirectOk   URL redirect after login OK      (default "" = JSON)
// cRedirectFail URL redirect after login FAIL    (default "" = JSON 401)
// cSessionKey   session key storing the user     (default "_auth_user")
// ============================================================
PROCEDURE HIX_MwAuthSetup( hConfig )

   IF ValType( hConfig ) != "H"

      RETURN

   ENDIF

   IF hb_HHasKey( hConfig, "bValidate"     ) ; s_bValidate     := hConfig[ "bValidate"     ] ; ENDIF

   IF hb_HHasKey( hConfig, "cLoginRoute"   ) ; s_cLoginRoute   := hConfig[ "cLoginRoute"   ] ; ENDIF

   IF hb_HHasKey( hConfig, "cLogoutRoute"  ) ; s_cLogoutRoute  := hConfig[ "cLogoutRoute"  ] ; ENDIF

   IF hb_HHasKey( hConfig, "cUserField"    ) ; s_cUserField    := hConfig[ "cUserField"    ] ; ENDIF

   IF hb_HHasKey( hConfig, "cPassField"    ) ; s_cPassField    := hConfig[ "cPassField"    ] ; ENDIF

   IF hb_HHasKey( hConfig, "cRedirectOk"   ) ; s_cRedirectOk   := hConfig[ "cRedirectOk"   ] ; ENDIF

   IF hb_HHasKey( hConfig, "cRedirectFail" ) ; s_cRedirectFail := hConfig[ "cRedirectFail" ] ; ENDIF

   IF hb_HHasKey( hConfig, "cSessionKey"   ) ; s_cSessionKey   := hConfig[ "cSessionKey"   ] ; ENDIF

RETURN

// ============================================================
// HIX_MwAuth — handles login (POST cLoginRoute) and logout.
// Add this to the pipeline of your login and logout routes.
// Requires HIX_MwSession earlier in the same pipeline.
// ============================================================
FUNCTION HIX_MwAuth( oCtx )

   LOCAL cPath := oCtx:oReq:cPath

   IF oCtx:oReq:cMethod == "POST" .AND. cPath == s_cLoginRoute

      RETURN _HixAuthDoLogin( oCtx )

   ENDIF

   IF cPath == s_cLogoutRoute

      RETURN _HixAuthDoLogout( oCtx )

   ENDIF

RETURN .T.

// ============================================================
// HIX_MwRequireAuth — route guard: responds 401 if not logged in.
// On success: sets oCtx:hData["user"] and UCurrentUser().
// Requires HIX_MwSession earlier in the same pipeline.
// ============================================================
FUNCTION HIX_MwRequireAuth( oCtx )

   LOCAL hUser := NIL
   LOCAL hJwt

   // Session auth (takes priority)

   IF hb_HHasKey( oCtx:hData, "session" )

      hUser := hb_HGetDef( oCtx:hData[ "session" ], s_cSessionKey, NIL )

   ENDIF

   // JWT fallback (set by HIX_MwJwt earlier in pipeline)

   IF ValType( hUser ) != "H"

      hJwt := hb_HGetDef( oCtx:hData, "jwt", NIL )

      IF ValType( hJwt ) == "H"

         hUser := hJwt

      ENDIF

   ENDIF

   IF ValType( hUser ) != "H"

      _HixAuthSend( oCtx:oReq, 401, "unauthorized" )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

   oCtx:hData[ "user" ] := hUser
   s_hCurrentUser       := hUser

RETURN .T.

// ============================================================
// U* helpers — usable inside any route codeblock
// ============================================================

// Returns the current user hash, or NIL if not authenticated.
FUNCTION UCurrentUser()
RETURN s_hCurrentUser

// UHasRole( cRole )      -> .T. if user has the role (any ops or full access)
// UHasRole( cRole, cOp ) -> .T. if user has the role with op cOp
// roles hash: key=role, value="" (full) or "op1;op2" (granular).
// Reads s_hCurrentUser (HIX_MwAuth) or URequest():hData["user"] (HIX_MwIsAuth).
FUNCTION UHasRole( cRole, cOp )

   LOCAL hUser, hRoles, cKey, cOps

   hb_default( @cOp, "" )

   IF ValType( s_hCurrentUser ) == "H"

      hRoles := hb_HGetDef( s_hCurrentUser, "roles", { => } )
   ELSE
      hUser := hb_HGetDef( URequest():hData, "user", NIL )

      IF ValType( hUser ) != "H"

         RETURN .F.

      ENDIF

      cKey   := UMwConfig( "auth", "roles_key", "roles" )
      hRoles := hb_HGetDef( hUser, cKey, { => } )

   ENDIF

   cOps := hb_HGetDef( hRoles, cRole, NIL )

   IF cOps == NIL                       ; RETURN .F. ; ENDIF

   IF Empty( cOps ) .OR. Empty( cOp )  ; RETURN .T. ; ENDIF

RETURN ";" + cOp + ";" $ ";" + cOps + ";"

// Returns roles hash of the current user: { "role" => "op1;op2" } or { "role" => "" } for full access.
// Returns { => } if not authenticated.
FUNCTION UGetRoles()

   LOCAL hUser, cKey

   IF ValType( s_hCurrentUser ) == "H"

      RETURN hb_HGetDef( s_hCurrentUser, "roles", { => } )

   ENDIF

   hUser := hb_HGetDef( URequest():hData, "user", NIL )

   IF ValType( hUser ) != "H"

      RETURN { => }

   ENDIF

   cKey := UMwConfig( "auth", "roles_key", "roles" )

RETURN hb_HGetDef( hUser, cKey, { => } )

// Destroys the current session from inside a route handler.
FUNCTION UAuthLogout()

   LOCAL oCtx := HIX_GetContext()

   s_hCurrentUser := NIL

   IF oCtx == NIL

      RETURN NIL

   ENDIF

   HIX_SessionSet( oCtx, s_cSessionKey, NIL )
   HIX_SessionDestroy( oCtx )

RETURN NIL

// ============================================================
// Private implementation
// ============================================================

STATIC FUNCTION _HixAuthDoLogin( oCtx )

   LOCAL cUser, cPass, hUser

   IF ValType( s_bValidate ) != "B"

      _HixAuthSend( oCtx:oReq, 500, "auth_not_configured" )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

   IF ! hb_HHasKey( oCtx:hData, "session" )

      _HixAuthSend( oCtx:oReq, 500, "session_required" )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

   cUser := _HixAuthReadField( oCtx:oReq, s_cUserField, "" )
   cPass := _HixAuthReadField( oCtx:oReq, s_cPassField, "" )

   IF Empty( cUser ) .OR. Empty( cPass )

      _HixAuthRespondFail( oCtx )
      RETURN .F.

   ENDIF

   hUser := Eval( s_bValidate, cUser, cPass )

   IF ValType( hUser ) != "H"

      _HixAuthRespondFail( oCtx )
      RETURN .F.

   ENDIF

   HIX_SessionSet( oCtx, s_cSessionKey, hUser )
   HIX_SessionSave( oCtx )

   oCtx:lHandled := .T.

   IF ! Empty( s_cRedirectOk )

      oCtx:oReq:Respond( "", 302, "text", { "Location" => s_cRedirectOk } )
   ELSE
      oCtx:oReq:Respond( hb_jsonEncode( { "ok" => .T., "user" => _HixAuthPublicUser( hUser ) } ), 200, "json" )

   ENDIF

RETURN .F.

STATIC FUNCTION _HixAuthDoLogout( oCtx )

   s_hCurrentUser := NIL
   HIX_SessionDestroy( oCtx )
   oCtx:lHandled := .T.

   IF ! Empty( s_cRedirectFail )

      oCtx:oReq:Respond( "", 302, "text", { "Location" => s_cRedirectFail } )
   ELSE
      oCtx:oReq:Respond( hb_jsonEncode( { "ok" => .T. } ), 200, "json" )

   ENDIF

RETURN .F.

STATIC PROCEDURE _HixAuthSend( oReq, nStatus, cError )

   oReq:Respond( hb_jsonEncode( { "error" => cError } ), nStatus, "json" )

RETURN

STATIC PROCEDURE _HixAuthRespondFail( oCtx )

   oCtx:lHandled := .T.

   IF ! Empty( s_cRedirectFail )

      oCtx:oReq:Respond( "", 302, "text", { "Location" => s_cRedirectFail } )
   ELSE
      _HixAuthSend( oCtx:oReq, 401, "invalid_credentials" )

   ENDIF

RETURN

STATIC FUNCTION _HixAuthPublicUser( hUser )

   LOCAL hPub := { => }

   IF hb_HHasKey( hUser, "id"    ) ; hPub[ "id"    ] := hUser[ "id"    ] ; ENDIF

   IF hb_HHasKey( hUser, "name"  ) ; hPub[ "name"  ] := hUser[ "name"  ] ; ENDIF

   IF hb_HHasKey( hUser, "roles" ) ; hPub[ "roles" ] := hUser[ "roles" ] ; ENDIF

RETURN hPub

STATIC FUNCTION _HixAuthReadField( oReq, cField, xDef )

   LOCAL h

   IF oReq:IsJson()

      h := oReq:JsonBody()

      IF ValType( h ) == "H"

         RETURN hb_HGetDef( h, cField, xDef )

      ENDIF

      RETURN xDef

   ENDIF

   h := oReq:FormBody()

RETURN hb_HGetDef( h, cField, xDef )
