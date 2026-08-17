/*-----------------------------------------------------------
  File ......: hix_test_jwt.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — JWT HIX (encode/validate/MW)
 -----------------------------------------------------------*/
#include "hbclass.ch"

// Uses shared TMockRequest from hix_test_utils.prg

STATIC FUNCTION _CtxJwt( cAuth )
   LOCAL oReq := TMockRequest():New( "/", "GET" )
   IF ! Empty( cAuth )
      oReq:hHeaders["authorization"] := cAuth
   ENDIF
RETURN THixContext():New( oReq )

FUNCTION HIX_TestJwt_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MwJwtSetup( "test-key-hix", 3600 )
   _TestEncodeStructure(   hCtx )
   _TestEncodeDecode(      hCtx )
   _TestMultipleVars(      hCtx )
   _TestClaimsPresent(     hCtx )
   _TestWrongKey(          hCtx )
   _TestExpiredToken(      hCtx )
   _TestMalformed1Part(    hCtx )
   _TestMalformed2Parts(   hCtx )
   _TestEmptyToken(        hCtx )
   _TestBadSignature(      hCtx )
   _TestFactoryCustomKey(  hCtx )
   _TestMwNoToken(         hCtx )
   _TestMwBearerInvalid(   hCtx )
   _TestMwBearerValid(     hCtx )
   _TestMwClaimsInHData(   hCtx )
RETURN hCtx

STATIC PROCEDURE _TestEncodeStructure( hCtx )
   LOCAL cToken, aParts
   cToken := HIX_JwtEncode( { "user" => "alice" }, "key", 3600 )
   aParts := hb_ATokens( cToken, "." )
   HixTU_Check( hCtx, ! Empty( cToken ),    "JWT T01: token no vacio",    "non-empty", iif(Empty(cToken),"empty","ok") )
   HixTU_Check( hCtx, Len( aParts ) == 3,   "JWT T01: 3 partes JWT",      "3",         hb_NToS( Len( aParts ) ) )
   HixTU_Check( hCtx, ! Empty( aParts[1] ), "JWT T01: header no vacio",   "non-empty", iif(Empty(aParts[1]),"empty","ok") )
   HixTU_Check( hCtx, ! Empty( aParts[2] ), "JWT T01: payload no vacio",  "non-empty", iif(Empty(aParts[2]),"empty","ok") )
   HixTU_Check( hCtx, ! Empty( aParts[3] ), "JWT T01: firma no vacia",    "non-empty", iif(Empty(aParts[3]),"empty","ok") )
RETURN

STATIC PROCEDURE _TestEncodeDecode( hCtx )
   LOCAL cKey, cToken, hResult, cUser, cRole
   cKey    := "secret-test-key"
   cToken  := HIX_JwtEncode( { "user" => "carles", "role" => "admin" }, cKey, 3600 )
   hResult := HIX_JwtValidate( cToken, cKey )
   HixTU_Check( hCtx, ValType( hResult ) == "H",  "JWT T02: validate retorna hash",  "H",       ValType( hResult ) )
   HixTU_Check( hCtx, hResult != NIL,             "JWT T02: resultado no NIL",        "not-NIL", iif( hResult==NIL,"NIL","ok" ) )
   cUser := hb_HGetDef( hResult, "user", "" )
   cRole := hb_HGetDef( hResult, "role", "" )
   HixTU_Check( hCtx, cUser == "carles", "JWT T02: user = carles", "carles", cUser )
   HixTU_Check( hCtx, cRole == "admin",  "JWT T02: role = admin",  "admin",  cRole )
RETURN

STATIC PROCEDURE _TestMultipleVars( hCtx )
   LOCAL cKey, hData, cToken, hResult
   cKey    := "multivar-key"
   hData   := { "name" => "bob", "age" => 30, "active" => .T., "level" => 5 }
   cToken  := HIX_JwtEncode( hData, cKey, 3600 )
   hResult := HIX_JwtValidate( cToken, cKey )
   HixTU_Check( hCtx, hb_HGetDef( hResult, "name",  "" ) == "bob", "JWT T03: name = bob",   "bob", hb_HGetDef( hResult, "name",  "" ) )
   HixTU_Check( hCtx, hb_HGetDef( hResult, "age",   0  ) == 30,    "JWT T03: age = 30",     "30",  hb_NToS( hb_HGetDef( hResult, "age", 0 ) ) )
   HixTU_Check( hCtx, hb_HGetDef( hResult, "level", 0  ) == 5,     "JWT T03: level = 5",    "5",   hb_NToS( hb_HGetDef( hResult, "level", 0 ) ) )
RETURN

STATIC PROCEDURE _TestClaimsPresent( hCtx )
   LOCAL cToken, hResult, nIat, nExp
   cToken  := HIX_JwtEncode( { "user" => "x" }, "k", 3600 )
   hResult := HIX_JwtValidate( cToken, "k" )
   HixTU_Check( hCtx, hb_HHasKey( hResult, "iss" ), "JWT T04: claim iss presente", ".T.", ".F." )
   HixTU_Check( hCtx, hb_HHasKey( hResult, "iat" ), "JWT T04: claim iat presente", ".T.", ".F." )
   HixTU_Check( hCtx, hb_HHasKey( hResult, "exp" ), "JWT T04: claim exp presente", ".T.", ".F." )
   HixTU_Check( hCtx, hResult["iss"] == "HIX",       "JWT T04: iss = HIX",          "HIX", hResult["iss"] )
   nIat := hb_HGetDef( hResult, "iat", 0 )
   nExp := hb_HGetDef( hResult, "exp", 0 )
   HixTU_Check( hCtx, nExp > nIat, "JWT T04: exp > iat", "exp>iat", hb_NToS(nExp) + ">" + hb_NToS(nIat) )
RETURN

STATIC PROCEDURE _TestWrongKey( hCtx )
   LOCAL cToken, hResult
   cToken  := HIX_JwtEncode( { "user" => "alice" }, "key-correct", 3600 )
   hResult := HIX_JwtValidate( cToken, "key-wrong" )
   HixTU_Check( hCtx, hResult == NIL, "JWT T05: clave incorrecta -> NIL", "NIL", iif(hResult==NIL,"NIL","not-NIL") )
RETURN

STATIC PROCEDURE _TestExpiredToken( hCtx )
   LOCAL cToken, hResult
   cToken  := HIX_JwtEncode( { "user" => "ghost" }, "key", -1 )
   hResult := HIX_JwtValidate( cToken, "key" )
   HixTU_Check( hCtx, hResult == NIL, "JWT T06: token expirado -> NIL", "NIL", iif(hResult==NIL,"NIL","not-NIL") )
RETURN

STATIC PROCEDURE _TestMalformed1Part( hCtx )
   LOCAL hResult
   hResult := HIX_JwtValidate( "solounaparte", "key" )
   HixTU_Check( hCtx, hResult == NIL, "JWT T07: 1 parte -> NIL", "NIL", iif(hResult==NIL,"NIL","not-NIL") )
RETURN

STATIC PROCEDURE _TestMalformed2Parts( hCtx )
   LOCAL hResult
   hResult := HIX_JwtValidate( "parte1.parte2", "key" )
   HixTU_Check( hCtx, hResult == NIL, "JWT T08: 2 partes -> NIL", "NIL", iif(hResult==NIL,"NIL","not-NIL") )
RETURN

STATIC PROCEDURE _TestEmptyToken( hCtx )
   LOCAL hResult
   hResult := HIX_JwtValidate( "", "key" )
   HixTU_Check( hCtx, hResult == NIL, "JWT T09: token vacio -> NIL", "NIL", iif(hResult==NIL,"NIL","not-NIL") )
RETURN

STATIC PROCEDURE _TestBadSignature( hCtx )
   LOCAL cToken, aParts, hResult
   cToken := HIX_JwtEncode( { "user" => "hacker" }, "key", 3600 )
   aParts := hb_ATokens( cToken, "." )
   cToken := aParts[1] + "." + aParts[2] + ".firmafalsa999"
   hResult := HIX_JwtValidate( cToken, "key" )
   HixTU_Check( hCtx, hResult == NIL, "JWT T10: firma alterada -> NIL", "NIL", iif(hResult==NIL,"NIL","not-NIL") )
RETURN

STATIC PROCEDURE _TestFactoryCustomKey( hCtx )
   LOCAL cKey1, cKey2, cToken1, cToken2, bMw1, bMw2
   LOCAL oCtx1, oCtx2, oCtxX, lR1, lR2, lRx, cUser1, cUser2
   cKey1   := "key-app-1"
   cKey2   := "key-app-2"
   cToken1 := HIX_JwtEncode( { "user" => "alice" }, cKey1, 3600 )
   cToken2 := HIX_JwtEncode( { "user" => "bob"   }, cKey2, 3600 )
   bMw1 := HIX_MwJwtFactory( cKey1 )
   bMw2 := HIX_MwJwtFactory( cKey2 )
   oCtx1 := _CtxJwt( "Bearer " + cToken1 )
   oCtx2 := _CtxJwt( "Bearer " + cToken2 )
   lR1 := Eval( bMw1, oCtx1 )
   lR2 := Eval( bMw2, oCtx2 )
   cUser1 := hb_HGetDef( oCtx1:hData["jwt"], "user", "" )
   cUser2 := hb_HGetDef( oCtx2:hData["jwt"], "user", "" )
   HixTU_Check( hCtx, lR1,               "JWT T11: factory1 valida token1",   ".T.",   hb_CStr( lR1 ) )
   HixTU_Check( hCtx, lR2,               "JWT T11: factory2 valida token2",   ".T.",   hb_CStr( lR2 ) )
   HixTU_Check( hCtx, cUser1 == "alice", "JWT T11: user1 = alice",             "alice", cUser1 )
   HixTU_Check( hCtx, cUser2 == "bob",   "JWT T11: user2 = bob",               "bob",   cUser2 )
   oCtxX := _CtxJwt( "Bearer " + cToken1 )
   lRx   := Eval( bMw2, oCtxX )
   HixTU_Check( hCtx, ! lRx, "JWT T11: token1 no valida con key2", ".F.", hb_CStr( lRx ) )
RETURN

STATIC PROCEDURE _TestMwNoToken( hCtx )
   LOCAL oCtx, lResult
   oCtx    := _CtxJwt( "" )
   lResult := HIX_MwJwt( oCtx )
   HixTU_Check( hCtx, ! lResult,                "JWT T12: sin token -> .F.",  ".F.", hb_CStr( lResult ) )
   HixTU_Check( hCtx, oCtx:lHandled,            "JWT T12: lHandled .T.",       ".T.", hb_CStr( oCtx:lHandled ) )
   HixTU_Check( hCtx, oCtx:oReq:nStatus == 401, "JWT T12: status 401",         "401", hb_NToS( oCtx:oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestMwBearerInvalid( hCtx )
   LOCAL oCtx, lResult
   oCtx    := _CtxJwt( "Bearer basura.sin.sentido" )
   lResult := HIX_MwJwt( oCtx )
   HixTU_Check( hCtx, ! lResult,                "JWT T13: Bearer invalido -> .F.", ".F.", hb_CStr( lResult ) )
   HixTU_Check( hCtx, oCtx:oReq:nStatus == 401, "JWT T13: status 401",             "401", hb_NToS( oCtx:oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestMwBearerValid( hCtx )
   LOCAL oCtx, lResult, cToken
   cToken  := HIX_JwtEncode( { "user" => "carles", "id" => 42 }, "test-key-hix", 3600 )
   oCtx    := _CtxJwt( "Bearer " + cToken )
   lResult := HIX_MwJwt( oCtx )
   HixTU_Check( hCtx, lResult,                         "JWT T14: Bearer valido -> .T.",  ".T.", hb_CStr( lResult ) )
   HixTU_Check( hCtx, ! oCtx:lHandled,                 "JWT T14: lHandled .F.",          ".F.", hb_CStr( oCtx:lHandled ) )
   HixTU_Check( hCtx, hb_HHasKey( oCtx:hData, "jwt" ), "JWT T14: jwt en hData",         ".T.", ".F." )
RETURN

STATIC PROCEDURE _TestMwClaimsInHData( hCtx )
   LOCAL oCtx, cToken, hJwt, cUser, nId
   cToken := HIX_JwtEncode( { "user" => "admin", "id" => 99 }, "test-key-hix", 3600 )
   oCtx   := _CtxJwt( "Bearer " + cToken )
   HIX_MwJwt( oCtx )
   hJwt  := oCtx:hData["jwt"]
   cUser := hb_HGetDef( hJwt, "user", "" )
   nId   := hb_HGetDef( hJwt, "id",   0  )
   HixTU_Check( hCtx, cUser == "admin",           "JWT T15: user = admin",   "admin", cUser )
   HixTU_Check( hCtx, nId   == 99,                "JWT T15: id = 99",        "99",    hb_NToS( nId ) )
   HixTU_Check( hCtx, hb_HHasKey( hJwt, "iss" ), "JWT T15: iss presente",   ".T.",   ".F." )
   HixTU_Check( hCtx, hb_HHasKey( hJwt, "exp" ), "JWT T15: exp presente",   ".T.",   ".F." )
RETURN
