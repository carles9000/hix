/*-----------------------------------------------------------
  File ......: hix_test_mw.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — built-in middlewares (CORS, JWT, RateLimit)
 -----------------------------------------------------------*/
#include "hbclass.ch"

// Uses shared TMockRequest from hix_test_utils.prg

// Each run gets a fresh discriminator so rate-limit entries never collide across runs
STATIC s_nRLRun := 0

STATIC FUNCTION _CtxMw( cPath, cMethod, cIP )
   LOCAL oReq
   hb_default( @cPath,   "/" )
   hb_default( @cMethod, "GET" )
   hb_default( @cIP,     "127.0.0.1" )
   oReq     := TMockRequest():New( cPath, cMethod )
   oReq:cIP := cIP
RETURN THixContext():New( oReq )

FUNCTION HIX_TestMw_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TestCorsGet(        hCtx )
   _TestCorsOptions(    hCtx )
   _TestCorsCustomOrigin( hCtx )
   _TestJwtEncodeDecode( hCtx )
   _TestJwtExpired(      hCtx )
   _TestJwtInvalidSig(   hCtx )
   _TestMwJwtNoToken(    hCtx )
   _TestMwJwtInvalid(    hCtx )
   _TestMwJwtValid(      hCtx )
   _TestRateLimitAllow(  hCtx )
   _TestRateLimitBlock(  hCtx )
   _TestRateLimitWindow( hCtx )
RETURN hCtx

STATIC PROCEDURE _TestCorsGet( hCtx )
   LOCAL oCtx, lResult, lHasOrigin, cOrigin
   HIX_MwCorsSetup( "*", "GET,POST,OPTIONS", "Content-Type,Authorization" )
   oCtx    := _CtxMw( "/api/data", "GET" )
   lResult := HIX_MwCors( oCtx )
   lHasOrigin := hb_HHasKey( oCtx:oReq:hExtraHeaders, "Access-Control-Allow-Origin" )
   cOrigin    := hb_HGetDef( oCtx:oReq:hExtraHeaders, "Access-Control-Allow-Origin", "" )
   HixTU_Check( hCtx, lResult,          "CORS: GET -> .T.",                ".T.", hb_CStr( lResult ) )
   HixTU_Check( hCtx, ! oCtx:lHandled,  "CORS: lHandled = .F.",            ".F.", hb_CStr( oCtx:lHandled ) )
   HixTU_Check( hCtx, lHasOrigin,       "CORS: Origin en hExtraHeaders",   ".T.", ".F." )
   HixTU_Check( hCtx, cOrigin == "*",   "CORS: Origin = *",                "*",   cOrigin )
RETURN

STATIC PROCEDURE _TestCorsOptions( hCtx )
   LOCAL oCtx, lResult
   oCtx    := _CtxMw( "/api/data", "OPTIONS" )
   lResult := HIX_MwCors( oCtx )
   HixTU_Check( hCtx, ! lResult,               "CORS: OPTIONS -> .F.",  ".F.", hb_CStr( lResult ) )
   HixTU_Check( hCtx, oCtx:lHandled,           "CORS: lHandled = .T.",  ".T.", hb_CStr( oCtx:lHandled ) )
   HixTU_Check( hCtx, oCtx:oReq:nStatus == 204,"CORS: status 204",      "204", hb_NToS( oCtx:oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestCorsCustomOrigin( hCtx )
   LOCAL oCtx, cOrigin
   HIX_MwCorsSetup( "https://myapp.com" )
   oCtx    := _CtxMw( "/api", "GET" )
   HIX_MwCors( oCtx )
   cOrigin := hb_HGetDef( oCtx:oReq:hExtraHeaders, "Access-Control-Allow-Origin", "" )
   HixTU_Check( hCtx, cOrigin == "https://myapp.com", "CORS: origen personalizado", "https://myapp.com", cOrigin )
   HIX_MwCorsSetup( "*" )
RETURN

STATIC PROCEDURE _TestJwtEncodeDecode( hCtx )
   LOCAL cKey, hData, cToken, hResult, nParts, cUser, cRole
   cKey   := "test-secret-key"
   hData  := { "user" => "carles", "role" => "admin" }
   cToken := HIX_JwtEncode( hData, cKey, 3600 )
   nParts := Len( hb_ATokens( cToken, "." ) )
   HixTU_Check( hCtx, ! Empty( cToken ), "MW JWT: token no vacio",    "non-empty", iif( Empty(cToken), "empty", "ok" ) )
   HixTU_Check( hCtx, nParts == 3,       "MW JWT: 3 partes JWT",      "3",         hb_NToS( nParts ) )
   hResult := HIX_JwtValidate( cToken, cKey )
   cUser   := hb_HGetDef( hResult, "user", "" )
   cRole   := hb_HGetDef( hResult, "role", "" )
   HixTU_Check( hCtx, ValType( hResult ) == "H", "MW JWT: validate retorna hash", "H",      ValType( hResult ) )
   HixTU_Check( hCtx, cUser == "carles",         "MW JWT: user=carles",            "carles", cUser )
   HixTU_Check( hCtx, cRole == "admin",          "MW JWT: role=admin",             "admin",  cRole )
RETURN

STATIC PROCEDURE _TestJwtExpired( hCtx )
   LOCAL cToken, hResult
   cToken  := HIX_JwtEncode( { "user" => "ghost" }, "test-secret-key", -1 )
   hResult := HIX_JwtValidate( cToken, "test-secret-key" )
   HixTU_Check( hCtx, hResult == NIL, "MW JWT: token expirado -> NIL", "NIL", iif( hResult == NIL, "NIL", "not-NIL" ) )
RETURN

STATIC PROCEDURE _TestJwtInvalidSig( hCtx )
   LOCAL cToken, hResult, aParts
   cToken := HIX_JwtEncode( { "user" => "hacker" }, "test-secret-key", 3600 )
   aParts  := hb_ATokens( cToken, "." )
   cToken  := aParts[1] + "." + aParts[2] + ".badsignature"
   hResult := HIX_JwtValidate( cToken, "test-secret-key" )
   HixTU_Check( hCtx, hResult == NIL, "MW JWT: firma invalida -> NIL", "NIL", iif( hResult == NIL, "NIL", "not-NIL" ) )
RETURN

STATIC PROCEDURE _TestMwJwtNoToken( hCtx )
   LOCAL oCtx, lResult
   HIX_MwJwtSetup( "test-key", 3600 )
   oCtx    := _CtxMw( "/api/secure", "GET" )
   lResult := HIX_MwJwt( oCtx )
   HixTU_Check( hCtx, ! lResult,                 "MwJwt: sin token -> .F.", ".F.", hb_CStr( lResult ) )
   HixTU_Check( hCtx, oCtx:lHandled,             "MwJwt: lHandled .T.",     ".T.", hb_CStr( oCtx:lHandled ) )
   HixTU_Check( hCtx, oCtx:oReq:nStatus == 401,  "MwJwt: status 401",       "401", hb_NToS( oCtx:oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestMwJwtInvalid( hCtx )
   LOCAL oCtx, lResult
   oCtx := _CtxMw( "/api/secure", "GET" )
   oCtx:oReq:hHeaders["authorization"] := "Bearer not.a.valid.token"
   lResult := HIX_MwJwt( oCtx )
   HixTU_Check( hCtx, ! lResult,                "MwJwt: token invalido -> .F.", ".F.", hb_CStr( lResult ) )
   HixTU_Check( hCtx, oCtx:oReq:nStatus == 401, "MwJwt: status 401",            "401", hb_NToS( oCtx:oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestMwJwtValid( hCtx )
   LOCAL oCtx, lResult, cKey, cToken, cJwtType, cUser
   cKey   := "test-key"
   cToken := HIX_JwtEncode( { "user" => "carles", "id" => 42 }, cKey, 3600 )
   oCtx := _CtxMw( "/api/secure", "GET" )
   oCtx:oReq:hHeaders["authorization"] := "Bearer " + cToken
   lResult  := HIX_MwJwt( oCtx )
   cJwtType := ValType( oCtx:hData["jwt"] )
   cUser    := hb_HGetDef( oCtx:hData["jwt"], "user", "" )
   HixTU_Check( hCtx, lResult,            "MwJwt: token valido -> .T.",   ".T.",    hb_CStr( lResult ) )
   HixTU_Check( hCtx, cJwtType == "H",    "MwJwt: jwt en hData",          "H",      cJwtType )
   HixTU_Check( hCtx, cUser == "carles",  "MwJwt: jwt.user=carles",       "carles", cUser )
RETURN

STATIC PROCEDURE _TestRateLimitAllow( hCtx )
   LOCAL oCtx, lResult, nCount, cIP
   s_nRLRun++
   cIP     := "rl-allow-" + hb_NToS( s_nRLRun )
   HIX_MwRateLimitSetup( 5, 60 )
   oCtx    := _CtxMw( "/", "GET", cIP )
   lResult := HIX_MwRateLimit( oCtx )
   nCount  := hb_HGetDef( oCtx:hData, "rate_count", 0 )
   HixTU_Check( hCtx, lResult,      "RateLimit: primera req -> .T.", ".T.", hb_CStr( lResult ) )
   HixTU_Check( hCtx, nCount == 1,  "RateLimit: rate_count = 1",    "1",   hb_NToS( nCount ) )
RETURN

STATIC PROCEDURE _TestRateLimitBlock( hCtx )
   LOCAL oCtx, lResult, i, cIP
   s_nRLRun++
   cIP  := "rl-block-" + hb_NToS( s_nRLRun )
   HIX_MwRateLimitSetup( 3, 60 )
   FOR i := 1 TO 3
      oCtx := _CtxMw( "/", "GET", cIP )
      HIX_MwRateLimit( oCtx )
   NEXT
   oCtx    := _CtxMw( "/", "GET", cIP )
   lResult := HIX_MwRateLimit( oCtx )
   HixTU_Check( hCtx, ! lResult,                "RateLimit: req 4 bloqueada -> .F.", ".F.", hb_CStr( lResult ) )
   HixTU_Check( hCtx, oCtx:lHandled,            "RateLimit: lHandled = .T.",         ".T.", hb_CStr( oCtx:lHandled ) )
   HixTU_Check( hCtx, oCtx:oReq:nStatus == 429, "RateLimit: status 429",             "429", hb_NToS( oCtx:oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestRateLimitWindow( hCtx )
   LOCAL oCtx, lResult, cFull, cNew
   s_nRLRun++
   cFull := "rl-full-"  + hb_NToS( s_nRLRun )
   cNew  := "rl-new-"   + hb_NToS( s_nRLRun )
   HIX_MwRateLimitSetup( 2, 60 )
   oCtx := _CtxMw( "/", "GET", cFull )
   HIX_MwRateLimit( oCtx )
   HIX_MwRateLimit( oCtx )
   oCtx    := _CtxMw( "/", "GET", cNew )
   lResult := HIX_MwRateLimit( oCtx )
   HixTU_Check( hCtx, lResult, "RateLimit: IP nueva no afectada", ".T.", hb_CStr( lResult ) )
RETURN
