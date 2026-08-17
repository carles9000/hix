/*-----------------------------------------------------------
  File ......: hix_test_auth_session.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — session-based authentication middleware
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"

// Uses shared TMockRequest from hix_test_utils.prg

STATIC FUNCTION _MakeCtxAuth( oReq, hSessionData )
   LOCAL oCtx
   hb_default( @hSessionData, { => } )
   oCtx               := THixContext():New( oReq, "", "", "" )
   oCtx:hData["session"] := hSessionData
   oCtx:hData["_sid"   ] := "test-sid-001"
RETURN oCtx

STATIC FUNCTION _FakeValidator( cUser, cPass )
   LOCAL hStore := {                                                              ;
      "admin"  => { "id" => "1", "name" => "Admin",  "pass" => "secret",        ;
                    "roles" => { "admin" => "", "editor" => "" } },              ;
      "editor" => { "id" => "2", "name" => "Editor", "pass" => "ed123",         ;
                    "roles" => { "editor" => "" } }                              ;
   }
   LOCAL hEntry := hb_HGetDef( hStore, Lower( cUser ), NIL )
   IF hEntry == NIL .OR. hEntry["pass"] != cPass
      RETURN NIL
   ENDIF
RETURN { "id" => hEntry["id"], "name" => hEntry["name"], "roles" => hEntry["roles"] }

FUNCTION HIX_TestAuthSession_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   HIX_MwSessionSetup( "HIXSID", 3600, 100, "memory" )
   HIX_MwAuthSetup( {                                       ;
      "bValidate"    => {|u,p| _FakeValidator( u, p )},    ;
      "cLoginRoute"  => "/api/login",                       ;
      "cLogoutRoute" => "/api/logout"                       ;
   } )
   _TestLogin(          hCtx )
   _TestRequireAuth(    hCtx )
   _TestRoles(          hCtx )
   _TestLogout(         hCtx )
   _TestUHelpers(       hCtx )
   _TestRequireAuthJwt( hCtx )
   _TestCsrf(           hCtx )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _TestLogin( hCtx )
   LOCAL oReq, oCtx, hUser

   oReq           := TMockRequest():New( "/api/login", "POST" )
   oReq:hFormBody := { "username" => "admin", "password" => "secret" }
   oCtx           := _MakeCtxAuth( oReq )
   HIX_MwAuth( oCtx )
   HixTU_Check( hCtx, oReq:nStatus == 200,       "Auth Login: status 200",             "200", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oCtx:lHandled,             "Auth Login: lHandled .T.",           ".T.", iif( oCtx:lHandled, ".T.", ".F." ) )
   hUser := hb_HGetDef( oCtx:hData["session"], "_auth_user", NIL )
   HixTU_Check( hCtx, ValType( hUser ) == "H",   "Auth Login: user en session",        "hash", ValType( hUser ) )
   HixTU_Check( hCtx, ValType( hUser ) == "H" .AND. hUser["id"] == "1", "Auth Login: user id correcto", "1", iif( ValType(hUser)=="H", hUser["id"], "?" ) )

   oReq                           := TMockRequest():New( "/api/login", "POST" )
   oReq:hHeaders["content-type"] := "application/json"
   oReq:cRawBody                 := hb_jsonEncode( { "username" => "editor", "password" => "ed123" } )
   oCtx                          := _MakeCtxAuth( oReq )
   HIX_MwAuth( oCtx )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Auth Login JSON: status 200", "200", hb_NToS( oReq:nStatus ) )
   hUser := hb_HGetDef( oCtx:hData["session"], "_auth_user", NIL )
   HixTU_Check( hCtx, ValType( hUser ) == "H" .AND. hUser["id"] == "2", "Auth Login JSON: user id=2", "2", iif( ValType(hUser)=="H", hUser["id"], "?" ) )

   oReq           := TMockRequest():New( "/api/login", "POST" )
   oReq:hFormBody := { "username" => "admin", "password" => "wrong" }
   oCtx           := _MakeCtxAuth( oReq )
   HIX_MwAuth( oCtx )
   HixTU_Check( hCtx, oReq:nStatus == 401, "Auth Login FAIL pass erronea: 401",  "401", hb_NToS( oReq:nStatus ) )
   hUser := hb_HGetDef( oCtx:hData["session"], "_auth_user", NIL )
   HixTU_Check( hCtx, hUser == NIL,        "Auth Login FAIL: no user en session", "NIL", ValType( hUser ) )

   oReq           := TMockRequest():New( "/api/login", "POST" )
   oReq:hFormBody := { "username" => "ghost", "password" => "x" }
   oCtx           := _MakeCtxAuth( oReq )
   HIX_MwAuth( oCtx )
   HixTU_Check( hCtx, oReq:nStatus == 401, "Auth Login FAIL usuario desconocido: 401", "401", hb_NToS( oReq:nStatus ) )

   oReq           := TMockRequest():New( "/api/login", "POST" )
   oReq:hFormBody := { "username" => "", "password" => "" }
   oCtx           := _MakeCtxAuth( oReq )
   HIX_MwAuth( oCtx )
   HixTU_Check( hCtx, oReq:nStatus == 401, "Auth Login FAIL creds vacias: 401", "401", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestRequireAuth( hCtx )
   LOCAL oReq, oCtx, hUser
   LOCAL hFakeUser := { "id" => "1", "name" => "Admin", "roles" => { "admin" => "" } }

   oReq := TMockRequest():New( "/api/me", "GET" )
   oCtx := _MakeCtxAuth( oReq, { "_auth_user" => hFakeUser } )
   HixTU_Check( hCtx, HIX_MwRequireAuth( oCtx ),   "Auth RequireAuth: pasa con sesion valida",    ".T.", ".F." )
   HixTU_Check( hCtx, ! oCtx:lHandled,             "Auth RequireAuth: lHandled queda .F.",        ".F.", iif( oCtx:lHandled, ".T.", ".F." ) )
   hUser := hb_HGetDef( oCtx:hData, "user", NIL )
   HixTU_Check( hCtx, ValType( hUser ) == "H",     "Auth RequireAuth: hData[user] es hash",       "hash", ValType( hUser ) )
   HixTU_Check( hCtx, ValType( hUser ) == "H" .AND. hUser["id"] == "1", "Auth RequireAuth: user id correcto", "1", iif( ValType(hUser)=="H", hUser["id"], "?" ) )

   oReq := TMockRequest():New( "/api/me", "GET" )
   oCtx := _MakeCtxAuth( oReq, { => } )
   HixTU_Check( hCtx, ! HIX_MwRequireAuth( oCtx ), "Auth RequireAuth: rechaza sesion vacia",      ".F.", ".T." )
   HixTU_Check( hCtx, oReq:nStatus == 401,         "Auth RequireAuth: 401 sesion vacia",          "401", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oCtx:lHandled,               "Auth RequireAuth: lHandled .T. al rechazar",  ".T.", iif( oCtx:lHandled, ".T.", ".F." ) )

   oReq := TMockRequest():New( "/api/me", "GET" )
   oCtx := THixContext():New( oReq, "", "", "" )
   HixTU_Check( hCtx, ! HIX_MwRequireAuth( oCtx ), "Auth RequireAuth: rechaza sin sesion",        ".F.", ".T." )
   HixTU_Check( hCtx, oReq:nStatus == 401,         "Auth RequireAuth: 401 sin sesion en hData",   "401", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestRoles( hCtx )
   LOCAL oReq, oCtx, bAdminMw, bEditorMw, lResult
   LOCAL hAdmin    := { "id" => "1", "name" => "Admin",    "roles" => { "admin" => "", "editor" => "" } }
   LOCAL hEditor   := { "id" => "2", "name" => "Editor",   "roles" => { "editor" => "" } }
   LOCAL hViewer   := { "id" => "3", "name" => "Viewer",   "roles" => { => } }
   LOCAL hCustomer := { "id" => "4", "name" => "Customer", "roles" => { "customers" => "edit;delete" } }

   bAdminMw  := {|oCtx| ( oCtx:cScope := "admin",  HIX_MwHasRole( oCtx ) ) }
   bEditorMw := {|oCtx| ( oCtx:cScope := "editor", HIX_MwHasRole( oCtx ) ) }

   oReq               := TMockRequest():New( "/api/admin", "GET" )
   oCtx               := _MakeCtxAuth( oReq )
   oCtx:hData["user"] := hAdmin
   lResult := Eval( bAdminMw, oCtx )
   HixTU_Check( hCtx, lResult,  "Auth Roles: admin pasa rol admin",   ".T.", iif( lResult, ".T.", ".F." ) )

   oReq               := TMockRequest():New( "/api/admin", "GET" )
   oCtx               := _MakeCtxAuth( oReq )
   oCtx:hData["user"] := hEditor
   lResult := Eval( bAdminMw, oCtx )
   HixTU_Check( hCtx, ! lResult,            "Auth Roles: editor denegado para admin",  ".F.", iif( lResult, ".T.", ".F." ) )
   HixTU_Check( hCtx, oReq:nStatus == 403,  "Auth Roles: 403 para rol incorrecto",     "403", hb_NToS( oReq:nStatus ) )

   oReq               := TMockRequest():New( "/api/edit", "GET" )
   oCtx               := _MakeCtxAuth( oReq )
   oCtx:hData["user"] := hEditor
   lResult := Eval( bEditorMw, oCtx )
   HixTU_Check( hCtx, lResult,  "Auth Roles: editor pasa rol editor", ".T.", iif( lResult, ".T.", ".F." ) )

   // scope vacio -> siempre pasa
   oReq               := TMockRequest():New( "/api/any", "GET" )
   oCtx               := _MakeCtxAuth( oReq )
   oCtx:cScope        := ""
   oCtx:hData["user"] := hViewer
   HixTU_Check( hCtx, HIX_MwHasRole( oCtx ), "Auth Roles: scope vacio siempre pasa", ".T.", ".F." )

   oReq := TMockRequest():New( "/api/admin", "GET" )
   oCtx := _MakeCtxAuth( oReq )
   lResult := Eval( bAdminMw, oCtx )
   HixTU_Check( hCtx, ! lResult,            "Auth Roles: sin user en hData -> 403",   ".F.", iif( lResult, ".T.", ".F." ) )
   HixTU_Check( hCtx, oReq:nStatus == 403,  "Auth Roles: 403 cuando no hay user",      "403", hb_NToS( oReq:nStatus ) )

   oReq               := TMockRequest():New( "/api/admin", "GET" )
   oCtx               := _MakeCtxAuth( oReq )
   oCtx:hData["user"] := hViewer
   lResult := Eval( bAdminMw, oCtx )
   HixTU_Check( hCtx, ! lResult, "Auth Roles: roles vacios -> denegado", ".F.", iif( lResult, ".T.", ".F." ) )

   // scope con op: customers:delete
   oReq               := TMockRequest():New( "/api/customers", "DELETE" )
   oCtx               := _MakeCtxAuth( oReq )
   oCtx:cScope        := "customers:delete"
   oCtx:hData["user"] := hCustomer
   lResult := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, lResult,  "Auth Roles: customers:delete, tiene op -> pasa",    ".T.", iif( lResult, ".T.", ".F." ) )

   // scope con op ausente: customers:xxx
   oReq               := TMockRequest():New( "/api/customers", "GET" )
   oCtx               := _MakeCtxAuth( oReq )
   oCtx:cScope        := "customers:xxx"
   oCtx:hData["user"] := hCustomer
   lResult := HIX_MwHasRole( oCtx )
   HixTU_Check( hCtx, ! lResult,            "Auth Roles: customers:xxx, op ausente -> denegado",  ".F.", iif( lResult, ".T.", ".F." ) )
   HixTU_Check( hCtx, oReq:nStatus == 403,  "Auth Roles: 403 op ausente",                          "403", hb_NToS( oReq:nStatus ) )

   // acceso total (ops vacias) -> pasa cualquier scope
   oReq               := TMockRequest():New( "/api/customers", "GET" )
   oCtx               := _MakeCtxAuth( oReq )
   oCtx:cScope        := "customers"
   oCtx:hData["user"] := { "id" => "5", "name" => "Full", "roles" => { "customers" => "" } }
   HixTU_Check( hCtx, HIX_MwHasRole( oCtx ), "Auth Roles: ops vacias (acceso total) -> pasa", ".T.", ".F." )
RETURN

STATIC PROCEDURE _TestLogout( hCtx )
   LOCAL oReq, oCtx
   LOCAL hFakeUser := { "id" => "1", "name" => "Admin", "roles" => { "admin" => "" } }

   oReq := TMockRequest():New( "/api/logout", "GET" )
   oCtx := _MakeCtxAuth( oReq, { "_auth_user" => hFakeUser } )
   HIX_MwAuth( oCtx )
   HixTU_Check( hCtx, oReq:nStatus == 200,              "Auth Logout: status 200",            "200",   hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oCtx:lHandled,                    "Auth Logout: lHandled .T.",           ".T.",   iif( oCtx:lHandled, ".T.", ".F." ) )
   HixTU_Check( hCtx, Empty( oCtx:hData["session"] ),   "Auth Logout: sesion limpiada",        "empty", iif( Empty( oCtx:hData["session"] ), "empty", "not empty" ) )

   oReq := TMockRequest():New( "/api/me", "GET" )
   oCtx := _MakeCtxAuth( oReq, { => } )
   HixTU_Check( hCtx, ! HIX_MwRequireAuth( oCtx ),  "Auth Logout then RequireAuth: rechazado", ".F.", ".T." )
   HixTU_Check( hCtx, oReq:nStatus == 401,           "Auth Logout then RequireAuth: 401",      "401", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestUHelpers( hCtx )
   LOCAL oReq, oCtx
   LOCAL hAdmin  := { "id" => "1", "name" => "Admin",  "roles" => { "admin" => "", "editor" => "", "customers" => "edit;delete;recall" } }
   LOCAL hEditor := { "id" => "2", "name" => "Editor", "roles" => { "editor" => "", "customers" => "edit" } }

   oReq := TMockRequest():New( "/api/me", "GET" )
   oCtx := _MakeCtxAuth( oReq, { "_auth_user" => hAdmin } )
   HIX_SetContext( oCtx )
   HIX_MwRequireAuth( oCtx )
   HixTU_Check( hCtx, ValType( UCurrentUser() ) == "H",  "Auth U: UCurrentUser() es hash",    "H",  ValType( UCurrentUser() ) )
   HixTU_Check( hCtx, ValType( UCurrentUser() ) == "H" .AND. UCurrentUser()["id"] == "1", "Auth U: user id=1", "1", ;
           iif( ValType(UCurrentUser())=="H", UCurrentUser()["id"], "NIL" ) )
   HixTU_Check( hCtx, UHasRole( "admin" ),   "Auth U: admin tiene rol admin",       ".T.", iif( UHasRole("admin"),   ".T.", ".F." ) )
   HixTU_Check( hCtx, UHasRole( "editor" ),  "Auth U: admin tiene rol editor",      ".T.", iif( UHasRole("editor"),  ".T.", ".F." ) )
   HixTU_Check( hCtx, ! UHasRole( "super" ), "Auth U: admin no tiene superuser",    ".F.", iif( UHasRole("super"),   ".T.", ".F." ) )
   HixTU_Check( hCtx, UHasRole( "customers", "delete" ), "Auth U: admin customers op delete pasa",  ".T.", iif( UHasRole("customers","delete"), ".T.", ".F." ) )
   HixTU_Check( hCtx, UHasRole( "customers", "recall" ), "Auth U: admin customers op recall pasa",  ".T.", iif( UHasRole("customers","recall"), ".T.", ".F." ) )
   HixTU_Check( hCtx, ! UHasRole( "customers", "xxx" ),  "Auth U: admin customers op xxx denegado", ".F.", iif( UHasRole("customers","xxx"),    ".T.", ".F." ) )

   oReq := TMockRequest():New( "/api/edit", "GET" )
   oCtx := _MakeCtxAuth( oReq, { "_auth_user" => hEditor } )
   HIX_SetContext( oCtx )
   HIX_MwRequireAuth( oCtx )
   HixTU_Check( hCtx, ! UHasRole( "admin" ), "Auth U: editor no tiene admin",       ".F.", iif( UHasRole("admin"),  ".T.", ".F." ) )
   HixTU_Check( hCtx, UHasRole( "editor" ),  "Auth U: editor tiene editor",         ".T.", iif( UHasRole("editor"), ".T.", ".F." ) )
   HixTU_Check( hCtx, UHasRole( "customers", "edit" ),    "Auth U: editor customers op edit pasa",    ".T.", iif( UHasRole("customers","edit"),   ".T.", ".F." ) )
   HixTU_Check( hCtx, ! UHasRole( "customers", "delete" ), "Auth U: editor customers op delete denegado", ".F.", iif( UHasRole("customers","delete"), ".T.", ".F." ) )

   HIX_SetContext( NIL )
   HixTU_Check( hCtx, UCurrentUser() == NIL .OR. ValType( UCurrentUser() ) == "H", "Auth U: sin ctx value ok", "H/NIL", ValType( UCurrentUser() ) )
RETURN

STATIC PROCEDURE _TestRequireAuthJwt( hCtx )
   LOCAL oReq, oCtx, hUser
   LOCAL hJwtUser  := { "sub" => "jwt-1", "name" => "JWT User",  "roles" => { "viewer" => "" } }
   LOCAL hSessUser := { "id" => "sess-1", "name" => "Sess User", "roles" => { "admin" => "" } }

   oReq := TMockRequest():New( "/api/me", "GET" )
   oCtx := THixContext():New( oReq )
   oCtx:hData["jwt"] := hJwtUser
   HixTU_Check( hCtx, HIX_MwRequireAuth( oCtx ),  "Auth JWT: solo JWT pasa",             ".T.", ".F." )
   HixTU_Check( hCtx, ! oCtx:lHandled,            "Auth JWT: lHandled queda .F.",        ".F.", iif( oCtx:lHandled, ".T.", ".F." ) )
   hUser := hb_HGetDef( oCtx:hData, "user", NIL )
   HixTU_Check( hCtx, ValType( hUser ) == "H",    "Auth JWT: hData[user] es hash",       "H",   ValType( hUser ) )
   HixTU_Check( hCtx, ValType( hUser ) == "H" .AND. hb_HGetDef( hUser, "sub", "" ) == "jwt-1", "Auth JWT: sub correcto", "jwt-1", ;
           iif( ValType(hUser)=="H", hb_HGetDef(hUser,"sub","?"), "?" ) )

   oReq := TMockRequest():New( "/api/me", "GET" )
   oCtx := _MakeCtxAuth( oReq, { "_auth_user" => hSessUser } )
   oCtx:hData["jwt"] := hJwtUser
   HIX_MwRequireAuth( oCtx )
   hUser := hb_HGetDef( oCtx:hData, "user", NIL )
   HixTU_Check( hCtx, ValType(hUser) == "H" .AND. hb_HGetDef( hUser, "id", "" ) == "sess-1", "Auth JWT: sesion gana sobre JWT", "sess-1", ;
           iif( ValType(hUser)=="H", hb_HGetDef(hUser,"id","?"), "?" ) )

   oReq := TMockRequest():New( "/api/me", "GET" )
   oCtx := THixContext():New( oReq )
   HixTU_Check( hCtx, ! HIX_MwRequireAuth( oCtx ), "Auth JWT: sin sesion ni JWT -> rechazado", ".F.", ".T." )
   HixTU_Check( hCtx, oReq:nStatus == 401,          "Auth JWT: 401 sin auth",                   "401", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestCsrf( hCtx )
   LOCAL oReq, oCtx, lOk, cToken

   oReq := TMockRequest():New( "/page", "GET" )
   oCtx := _MakeCtxAuth( oReq, { => } )
   lOk  := HIX_MwCsrf( oCtx )
   HixTU_Check( hCtx, lOk,             "CSRF: GET genera token y pasa",     ".T.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, ! oCtx:lHandled, "CSRF: lHandled .F. en GET",         ".F.", hb_CStr( oCtx:lHandled ) )
   cToken := hb_HGetDef( oCtx:hData, "csrf_token", "" )
   HixTU_Check( hCtx, "." $ cToken,    "CSRF: token es HMAC-signed (tiene .)", "yes", hb_CStr( "." $ cToken ) )

   cToken := HIX_CsrfMakeToken()
   oReq   := TMockRequest():New( "/page", "GET" )
   oCtx   := _MakeCtxAuth( oReq, { "_csrf_token" => cToken } )
   HIX_MwCsrf( oCtx )
   HixTU_Check( hCtx, hb_HGetDef( oCtx:hData, "csrf_token", "" ) == cToken, "CSRF: token existente reutilizado", cToken, hb_HGetDef( oCtx:hData, "csrf_token", "" ) )

   cToken := HIX_CsrfMakeToken()
   oReq   := TMockRequest():New( "/submit", "POST" )
   oReq:hHeaders["x-csrf-token"] := cToken
   oCtx   := _MakeCtxAuth( oReq, { "_csrf_token" => cToken } )
   lOk    := HIX_MwCsrf( oCtx )
   HixTU_Check( hCtx, lOk, "CSRF: POST token valido en header pasa", ".T.", hb_CStr( lOk ) )

   oReq := TMockRequest():New( "/submit", "POST" )
   oReq:hHeaders["x-csrf-token"] := "wrong-token"
   oCtx := _MakeCtxAuth( oReq, { "_csrf_token" => "my-csrf-token" } )
   lOk  := HIX_MwCsrf( oCtx )
   HixTU_Check( hCtx, ! lOk,               "CSRF: POST token incorrecto rechazado", ".F.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, oReq:nStatus == 403, "CSRF: 403 token incorrecto",             "403", hb_NToS( oReq:nStatus ) )

   oReq := TMockRequest():New( "/submit", "POST" )
   oCtx := _MakeCtxAuth( oReq, { "_csrf_token" => "my-csrf-token" } )
   lOk  := HIX_MwCsrf( oCtx )
   HixTU_Check( hCtx, ! lOk,               "CSRF: POST sin token rechazado",  ".F.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, oReq:nStatus == 403, "CSRF: 403 token ausente",          "403", hb_NToS( oReq:nStatus ) )

   cToken         := HIX_CsrfMakeToken()
   oReq           := TMockRequest():New( "/submit", "POST" )
   oReq:hFormBody := { "_csrf" => cToken }
   oCtx           := _MakeCtxAuth( oReq, { "_csrf_token" => cToken } )
   lOk            := HIX_MwCsrf( oCtx )
   HixTU_Check( hCtx, lOk, "CSRF: POST token en form field pasa", ".T.", hb_CStr( lOk ) )

   oReq := TMockRequest():New( "/submit", "POST" )
   oCtx := THixContext():New( oReq )
   lOk  := HIX_MwCsrf( oCtx )
   HixTU_Check( hCtx, ! lOk,               "CSRF: sin sesion -> rechazado", ".F.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, oReq:nStatus == 500, "CSRF: 500 csrf_requires_session","500", hb_NToS( oReq:nStatus ) )
RETURN
