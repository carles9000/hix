/*-----------------------------------------------------------
  File ......: hix_test_context.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — HIX_GetContext helpers
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"

// Unique name — does not conflict with shared TMockIO/TMockRequest
CLASS TMockReqCtx
   DATA hParam  INIT { => }
   DATA cMethod INIT "GET"
   DATA cPath   INIT "/"
ENDCLASS

FUNCTION HIX_TestContext_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   _CtxNoContext( hCtx )
   _CtxSession(   hCtx )
   _CtxJwt(       hCtx )
   _CtxRouteParam(hCtx )
   _CtxSetClear(  hCtx )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _CtxNoContext( hCtx )
   HIX_SetContext( NIL )
   HixTU_Check( hCtx, ValType( HIX_Session() ) == "H",         "Ctx: sin ctx Session()->hash",   "H", ValType( HIX_Session() ) )
   HixTU_Check( hCtx, HIX_Session( "user", "x" ) == "x",      "Ctx: sin ctx Session(key)->def", "x", hb_CStr( HIX_Session( "user", "x" ) ) )
   HixTU_Check( hCtx, ValType( HIX_JwtPayload() ) == "H",      "Ctx: sin ctx JwtPayload()->hash","H", ValType( HIX_JwtPayload() ) )
   HixTU_Check( hCtx, HIX_JwtPayload( "sub", "x" ) == "x",    "Ctx: sin ctx JwtPayload(key)->def","x", hb_CStr( HIX_JwtPayload( "sub", "x" ) ) )
   HixTU_Check( hCtx, HIX_RouteParam( "id", "none" ) == "none","Ctx: sin ctx RouteParam->def",   "none", HIX_RouteParam( "id", "none" ) )
RETURN

STATIC PROCEDURE _CtxSession( hCtx )
   LOCAL oCtx, hSess
   oCtx  := THixContext():New( TMockReqCtx():New(), "", "", "" )
   hSess := { "user" => "carles", "role" => "admin", "count" => 3 }
   oCtx:hData[ "session" ] := hSess
   HIX_SetContext( oCtx )
   HixTU_Check( hCtx, ValType( HIX_Session() ) == "H",          "Ctx: session->hash",         "H",      ValType( HIX_Session() ) )
   HixTU_Check( hCtx, HIX_Session( "user", "" ) == "carles",    "Ctx: session user=carles",   "carles", hb_CStr( HIX_Session( "user", "" ) ) )
   HixTU_Check( hCtx, HIX_Session( "role", "" ) == "admin",     "Ctx: session role=admin",    "admin",  hb_CStr( HIX_Session( "role", "" ) ) )
   HixTU_Check( hCtx, HIX_Session( "count", 0 ) == 3,           "Ctx: session count=3",       "3",      hb_NToS( HIX_Session( "count", 0 ) ) )
   HixTU_Check( hCtx, HIX_Session( "nope", "def" ) == "def",    "Ctx: session ausente->def",  "def",    hb_CStr( HIX_Session( "nope", "def" ) ) )
   oCtx := THixContext():New( TMockReqCtx():New(), "", "", "" )
   HIX_SetContext( oCtx )
   HixTU_Check( hCtx, ValType( HIX_Session() ) == "H",          "Ctx: sin session->hash vacio","H",     ValType( HIX_Session() ) )
   HixTU_Check( hCtx, Len( HIX_Session() ) == 0,                "Ctx: sin session len=0",     "0",      hb_NToS( Len( HIX_Session() ) ) )
   HixTU_Check( hCtx, HIX_Session( "x", "fb" ) == "fb",        "Ctx: sin session key->def",  "fb",     hb_CStr( HIX_Session( "x", "fb" ) ) )
RETURN

STATIC PROCEDURE _CtxJwt( hCtx )
   LOCAL oCtx, hJwt
   oCtx := THixContext():New( TMockReqCtx():New(), "", "", "" )
   hJwt := { "sub" => "user123", "role" => "editor", "exp" => 9999999 }
   oCtx:hData[ "jwt" ] := hJwt
   HIX_SetContext( oCtx )
   HixTU_Check( hCtx, ValType( HIX_JwtPayload() ) == "H",      "Ctx: jwt->hash",         "H",       ValType( HIX_JwtPayload() ) )
   HixTU_Check( hCtx, HIX_JwtPayload( "sub", "" ) == "user123","Ctx: jwt sub=user123",   "user123", hb_CStr( HIX_JwtPayload( "sub", "" ) ) )
   HixTU_Check( hCtx, HIX_JwtPayload( "role", "" ) == "editor","Ctx: jwt role=editor",   "editor",  hb_CStr( HIX_JwtPayload( "role", "" ) ) )
   HixTU_Check( hCtx, HIX_JwtPayload( "exp", 0 ) == 9999999,   "Ctx: jwt exp=9999999",   "9999999", hb_NToS( HIX_JwtPayload( "exp", 0 ) ) )
   HixTU_Check( hCtx, HIX_JwtPayload( "nope", "fb" ) == "fb",  "Ctx: jwt ausente->def",  "fb",      hb_CStr( HIX_JwtPayload( "nope", "fb" ) ) )
   oCtx := THixContext():New( TMockReqCtx():New(), "", "", "" )
   HIX_SetContext( oCtx )
   HixTU_Check( hCtx, Len( HIX_JwtPayload() ) == 0,            "Ctx: sin jwt->hash vacio","0",      hb_NToS( Len( HIX_JwtPayload() ) ) )
RETURN

STATIC PROCEDURE _CtxRouteParam( hCtx )
   LOCAL oCtx, oReq
   oReq := TMockReqCtx():New()
   oReq:hParam[ "id"   ] := "42"
   oReq:hParam[ "slug" ] := "harbour-web"
   oCtx := THixContext():New( oReq, "", "", "" )
   HIX_SetContext( oCtx )
   HixTU_Check( hCtx, HIX_RouteParam( "id",   "" ) == "42",          "Ctx: RouteParam id=42",        "42",          HIX_RouteParam( "id",   "" ) )
   HixTU_Check( hCtx, HIX_RouteParam( "slug", "" ) == "harbour-web", "Ctx: RouteParam slug",         "harbour-web", HIX_RouteParam( "slug", "" ) )
   HixTU_Check( hCtx, HIX_RouteParam( "nope", "fb" ) == "fb",        "Ctx: RouteParam ausente->def", "fb",          HIX_RouteParam( "nope", "fb" ) )
   HIX_SetContext( NIL )
   oReq := TMockReqCtx():New()
   oReq:hParam[ "cat" ] := "news"
   HIX_SetRequest( oReq )
   HixTU_Check( hCtx, HIX_RouteParam( "cat", "" ) == "news",         "Ctx: RouteParam fallback GetReq","news",       HIX_RouteParam( "cat", "" ) )
   HIX_SetRequest( NIL )
RETURN

STATIC PROCEDURE _CtxSetClear( hCtx )
   LOCAL oCtx
   HIX_SetContext( NIL )
   HixTU_Check( hCtx, HIX_GetContext() == NIL, "Ctx: GetContext NIL inicial",      "NIL", iif(HIX_GetContext()==NIL,"NIL","not NIL") )
   oCtx := THixContext():New( TMockReqCtx():New(), "", "", "" )
   HIX_SetContext( oCtx )
   HixTU_Check( hCtx, HIX_GetContext() != NIL, "Ctx: GetContext no NIL tras Set",  "not NIL", "NIL" )
   HixTU_Check( hCtx, HIX_GetContext() == oCtx,"Ctx: GetContext == oCtx",          ".T.", iif(HIX_GetContext()==oCtx,".T.",".F.") )
   HIX_SetContext( NIL )
   HixTU_Check( hCtx, HIX_GetContext() == NIL, "Ctx: GetContext NIL tras clear",   "NIL", iif(HIX_GetContext()==NIL,"NIL","not NIL") )
RETURN
