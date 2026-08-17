/*-----------------------------------------------------------
  File ......: hix_test_csrf.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — CSRF token / HIX_MwCsrf
 -----------------------------------------------------------*/
#include "hbclass.ch"

// Uses shared TMockRequest from hix_test_utils.prg

STATIC FUNCTION _NewCtxCsrf( hCtx, cMethod, hHeaders, hForm, lSession )
   LOCAL oReq, oCtx
   hb_default( @cMethod,  "GET"  )
   hb_default( @hHeaders, { => }  )
   hb_default( @hForm,    { => }  )
   hb_default( @lSession, .T.    )
   oReq           := TMockRequest():New( "/", cMethod )
   oReq:hHeaders  := hHeaders
   oReq:hFormBody := hForm
   oCtx           := THixContext():New( oReq )
   HIX_SetRequest( oReq )
   IF lSession
      HIX_MwSession( oCtx )
   ENDIF
RETURN { oReq, oCtx }

FUNCTION HIX_TestCsrf_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MwSessionSetup( "HIXSID", 3600, 100, "memory" )
   HIX_KeySet( "csrf", "test-secret-csrf" )
   _TestCsrfRandom(      hCtx )
   _TestCsrfTokenMakeValid( hCtx )
   _TestCsrfToHtml(      hCtx )
   _TestCsrfMiddleware(  hCtx )
RETURN hCtx

STATIC PROCEDURE _TestCsrfRandom( hCtx )
   LOCAL cT1, cT2, i, lAlpha, cCh
   cT1 := HIX_CsrfGenRandom()
   HixTU_Check( hCtx, Len( cT1 ) == 16, "CSRF T01: default length 16", "16", hb_NToS( Len( cT1 ) ) )
   cT1 := HIX_CsrfGenRandom( 8 )
   HixTU_Check( hCtx, Len( cT1 ) == 8,  "CSRF T02: custom length 8",   "8",  hb_NToS( Len( cT1 ) ) )
   cT1 := HIX_CsrfGenRandom( 16 )
   cT2 := HIX_CsrfGenRandom( 16 )
   HixTU_Check( hCtx, !( cT1 == cT2 ), "CSRF T03: two calls differ", "different", "same" )
   cT1    := HIX_CsrfGenRandom( 32 )
   lAlpha := .T.
   FOR i := 1 TO Len( cT1 )
      cCh := SubStr( cT1, i, 1 )
      IF !( ( cCh >= "A" .AND. cCh <= "Z" ) .OR. ;
            ( cCh >= "a" .AND. cCh <= "z" ) .OR. ;
            ( cCh >= "0" .AND. cCh <= "9" ) )
         lAlpha := .F. ; EXIT
      ENDIF
   NEXT
   HixTU_Check( hCtx, lAlpha, "CSRF T04: only alphanumeric", ".T.", hb_CStr( lAlpha ) )
RETURN

STATIC PROCEDURE _TestCsrfTokenMakeValid( hCtx )
   LOCAL cToken, cTampered, cParts, cTokA, cTokB
   cToken := HIX_CsrfMakeToken()
   cParts := hb_ATokens( cToken, "." )
   HixTU_Check( hCtx, Len( cParts ) == 2,      "CSRF T05: 2 parts (base64.HMAC)", "2", hb_NToS( Len( cParts ) ) )
   HixTU_Check( hCtx, HIX_CsrfValidToken( cToken ),  "CSRF T06: valid token passes",    ".T.", ".F." )
   HixTU_Check( hCtx, ! HIX_CsrfValidToken( "" ),    "CSRF T07: empty token fails",     ".F.", ".T." )
   cTampered := "AAAA" + SubStr( cToken, 5 )
   HixTU_Check( hCtx, ! HIX_CsrfValidToken( cTampered ), "CSRF T08: tampered payload fails", ".F.", ".T." )
   cTampered := cParts[1] + ".BADHMACSIGNATURE1234"
   HixTU_Check( hCtx, ! HIX_CsrfValidToken( cTampered ), "CSRF T09: tampered HMAC fails",    ".F.", ".T." )
   HixTU_Check( hCtx, HIX_CsrfValidToken( cToken, 0 ),   "CSRF T10: lapsus=0 no expiry",     ".T.", ".F." )
   hb_idleSleep( 2 )
   HixTU_Check( hCtx, ! HIX_CsrfValidToken( cToken, 1 ), "CSRF T11: expired (lapsus=1) fails",".F.", ".T." )
   HIX_KeySet( "csrf", "secret-A" )
   cTokA := HIX_CsrfMakeToken( "data" )
   HIX_KeySet( "csrf", "secret-B" )
   cTokB := HIX_CsrfMakeToken( "data" )
   HixTU_Check( hCtx, !( cTokA == cTokB ),          "CSRF T12: diff secrets -> diff tokens", "different", "same" )
   HixTU_Check( hCtx, ! HIX_CsrfValidToken( cTokA ),"CSRF T13: token-A invalid under secret-B", ".F.", ".T." )
   HIX_KeySet( "csrf", "test-secret-csrf" )
RETURN

STATIC PROCEDURE _TestCsrfToHtml( hCtx )
   LOCAL cToken, cHtml
   cToken := HIX_CsrfMakeToken()
   cHtml  := UCsrfToHtml( cToken )
   HixTU_Check( hCtx, "<input" $ cHtml,         "CSRF T14: has <input",     "<input",    cHtml )
   HixTU_Check( hCtx, cToken $ cHtml,           "CSRF T15: token in HTML",  "yes",       "no" )
   HixTU_Check( hCtx, 'name="_csrf"' $ cHtml,   "CSRF T16: name=_csrf",     'name=_csrf', cHtml )
RETURN

STATIC PROCEDURE _TestCsrfMiddleware( hCtx )
   LOCAL aRC, oReq, oCtx, cToken
   aRC    := _NewCtxCsrf( hCtx, "GET" )
   oReq   := aRC[1] ; oCtx := aRC[2]
   HIX_MwCsrf( oCtx )
   cToken := hb_HGetDef( oCtx:hData, "csrf_token", "" )
   HixTU_Check( hCtx, ! Empty( cToken ),   "CSRF T17: GET genera csrf_token",   "non-empty", cToken )
   HixTU_Check( hCtx, ! oCtx:lHandled,     "CSRF T18: GET no bloquea",          ".F.", hb_CStr( oCtx:lHandled ) )
   aRC  := _NewCtxCsrf( hCtx, "POST", { "x-csrf-token" => cToken } )
   oReq := aRC[1] ; oCtx := aRC[2]
   oCtx:hData["session"] := { "_csrf_token" => cToken }
   HixTU_Check( hCtx, HIX_MwCsrf( oCtx ), "CSRF T19: POST header valido pasa", ".T.", ".F." )
   aRC  := _NewCtxCsrf( hCtx, "POST", { => }, { "_csrf" => cToken } )
   oReq := aRC[1] ; oCtx := aRC[2]
   oCtx:hData["session"] := { "_csrf_token" => cToken }
   HixTU_Check( hCtx, HIX_MwCsrf( oCtx ), "CSRF T20: POST form token pasa",    ".T.", ".F." )
   aRC  := _NewCtxCsrf( hCtx, "POST", { "x-csrf-token" => "bad-token" } )
   oReq := aRC[1] ; oCtx := aRC[2]
   oCtx:hData["session"] := { "_csrf_token" => cToken }
   HIX_MwCsrf( oCtx )
   HixTU_Check( hCtx, oReq:nStatus == 403, "CSRF T21: token incorrecto -> 403", "403", hb_NToS( oReq:nStatus ) )
   aRC  := _NewCtxCsrf( hCtx, "POST", { => }, { => }, .F. )
   oReq := aRC[1] ; oCtx := aRC[2]
   HIX_MwCsrf( oCtx )
   HixTU_Check( hCtx, oReq:nStatus == 500, "CSRF T22: sin session -> 500",      "500", hb_NToS( oReq:nStatus ) )
RETURN
