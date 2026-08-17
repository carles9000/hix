/*-----------------------------------------------------------
  File ......: hix_test_jwt_scope.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — HIX_MwJwtScope and UHasScope()
 -----------------------------------------------------------*/
#include "hbclass.ch"

// Uses shared TMockRequest from hix_test_utils.prg (no class redefinition here)

STATIC FUNCTION _Ctx( cAuth, cScope )
   LOCAL oReq, oCtx
   hb_default( @cAuth,  "" )
   hb_default( @cScope, "" )
   oReq := TMockRequest():New()
   IF ! Empty( cAuth )
      oReq:hHeaders["authorization"] := cAuth
   ENDIF
   oCtx := THixContext():New( oReq, "", cScope )
RETURN oCtx

STATIC PROCEDURE _SetJwt( oCtx, hJwt )
   oCtx:hData["jwt"] := hJwt
RETURN

FUNCTION HIX_TestJwtScope_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MwJwtSetup( "test-scope-key", 3600 )
   _JwtScopeNoScope(        hCtx )
   _JwtScopeMatch(          hCtx )
   _JwtScopeMismatch(       hCtx )
   _JwtScopeNoJwt(          hCtx )
   _JwtScopeMultiAll(       hCtx )
   _JwtScopeMultiPartial(   hCtx )
   _JwtScopeEmptyClaim(     hCtx )
   _JwtScopeUHasScope(      hCtx )
RETURN hCtx

STATIC PROCEDURE _JwtScopeNoScope( hCtx )
   LOCAL oCtx, lR
   oCtx := _Ctx( "", "" )
   lR   := HIX_MwJwtScope( oCtx )
   HixTU_Check( hCtx, lR,              "JwtScope: sin scope sin jwt -> .T.", ".T.", hb_CStr( lR ) )
   HixTU_Check( hCtx, ! oCtx:lHandled,"JwtScope: sin scope lHandled .F.",   ".F.", hb_CStr( oCtx:lHandled ) )
   oCtx := _Ctx( "", "" )
   _SetJwt( oCtx, { "scope" => "read:x", "sub" => "42" } )
   lR := HIX_MwJwtScope( oCtx )
   HixTU_Check( hCtx, lR, "JwtScope: sin scope con jwt -> .T.", ".T.", hb_CStr( lR ) )
RETURN

STATIC PROCEDURE _JwtScopeMatch( hCtx )
   LOCAL oCtx, lR
   oCtx := _Ctx( "", "read:products" )
   _SetJwt( oCtx, { "scope" => "read:products write:orders", "sub" => "7" } )
   lR := HIX_MwJwtScope( oCtx )
   HixTU_Check( hCtx, lR,              "JwtScope: scope match -> .T.", ".T.", hb_CStr( lR ) )
   HixTU_Check( hCtx, ! oCtx:lHandled,"JwtScope: match lHandled .F.", ".F.", hb_CStr( oCtx:lHandled ) )
RETURN

STATIC PROCEDURE _JwtScopeMismatch( hCtx )
   LOCAL oCtx, lR
   oCtx := _Ctx( "", "delete:products" )
   _SetJwt( oCtx, { "scope" => "read:products write:products", "sub" => "7" } )
   lR := HIX_MwJwtScope( oCtx )
   HixTU_Check( hCtx, ! lR,                    "JwtScope: mismatch -> .F.", ".F.", hb_CStr( lR ) )
   HixTU_Check( hCtx, oCtx:lHandled,           "JwtScope: lHandled .T.",    ".T.", hb_CStr( oCtx:lHandled ) )
   HixTU_Check( hCtx, oCtx:oReq:nStatus == 403,"JwtScope: status 403",      "403", hb_NToS( oCtx:oReq:nStatus ) )
RETURN

STATIC PROCEDURE _JwtScopeNoJwt( hCtx )
   LOCAL oCtx, lR
   oCtx := _Ctx( "", "read:products" )
   lR := HIX_MwJwtScope( oCtx )
   HixTU_Check( hCtx, ! lR,                    "JwtScope: sin jwt -> .F.", ".F.", hb_CStr( lR ) )
   HixTU_Check( hCtx, oCtx:lHandled,           "JwtScope: lHandled .T.",   ".T.", hb_CStr( oCtx:lHandled ) )
   HixTU_Check( hCtx, oCtx:oReq:nStatus == 403,"JwtScope: status 403",     "403", hb_NToS( oCtx:oReq:nStatus ) )
RETURN

STATIC PROCEDURE _JwtScopeMultiAll( hCtx )
   LOCAL oCtx, lR
   oCtx := _Ctx( "", "read:x write:x" )
   _SetJwt( oCtx, { "scope" => "read:x write:x read:y", "sub" => "3" } )
   lR := HIX_MwJwtScope( oCtx )
   HixTU_Check( hCtx, lR, "JwtScope: multi todos presentes -> .T.", ".T.", hb_CStr( lR ) )
RETURN

STATIC PROCEDURE _JwtScopeMultiPartial( hCtx )
   LOCAL oCtx, lR
   oCtx := _Ctx( "", "read:x delete:x" )
   _SetJwt( oCtx, { "scope" => "read:x write:x", "sub" => "3" } )
   lR := HIX_MwJwtScope( oCtx )
   HixTU_Check( hCtx, ! lR,                    "JwtScope: multi parcial -> .F.", ".F.", hb_CStr( lR ) )
   HixTU_Check( hCtx, oCtx:oReq:nStatus == 403,"JwtScope: parcial status 403",   "403", hb_NToS( oCtx:oReq:nStatus ) )
RETURN

STATIC PROCEDURE _JwtScopeEmptyClaim( hCtx )
   LOCAL oCtx, lR
   oCtx := _Ctx( "", "read:x" )
   _SetJwt( oCtx, { "sub" => "5", "role" => "user" } )
   lR := HIX_MwJwtScope( oCtx )
   HixTU_Check( hCtx, ! lR,                    "JwtScope: sin claim scope -> .F.", ".F.", hb_CStr( lR ) )
   HixTU_Check( hCtx, oCtx:oReq:nStatus == 403,"JwtScope: sin claim status 403",   "403", hb_NToS( oCtx:oReq:nStatus ) )
RETURN

STATIC PROCEDURE _JwtScopeUHasScope( hCtx )
   LOCAL oCtx, lR
   oCtx := _Ctx( "", "" )
   _SetJwt( oCtx, { "scope" => "read:x write:x", "sub" => "1" } )
   HIX_SetContext( oCtx )
   lR := UHasScope( "read:x" )
   HixTU_Check( hCtx, lR,  "JwtScope: UHasScope presente -> .T.", ".T.", hb_CStr( lR ) )
   lR := UHasScope( "delete:x" )
   HixTU_Check( hCtx, ! lR,"JwtScope: UHasScope ausente -> .F.", ".F.", hb_CStr( lR ) )
   HIX_SetContext( _Ctx( "", "" ) )
   lR := UHasScope( "read:x" )
   HixTU_Check( hCtx, ! lR,"JwtScope: UHasScope sin jwt -> .F.", ".F.", hb_CStr( lR ) )
   HIX_SetContext( NIL )
RETURN
