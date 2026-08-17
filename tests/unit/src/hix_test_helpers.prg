/*-----------------------------------------------------------
  File ......: hix_test_helpers.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — U* helpers (hix_helpers.prg)
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"

// TMockReq — unique name, full-featured mock for helpers testing
CLASS TMockReq
   DATA cMethod         INIT "GET"
   DATA cPath           INIT "/"
   DATA cQuery          INIT ""
   DATA hParam          INIT { => }
   DATA hHeaders        INIT { => }
   DATA hExtraHeaders   INIT { => }
   DATA cBody           INIT ""
   DATA hFormBody       INIT NIL
   DATA hJsonBody       INIT NIL
   DATA lResponded      INIT .F.
   DATA nStatus         INIT 0
   DATA cBodyResp       INIT ""
   DATA cMime           INIT ""
   DATA lKeepAlive      INIT .F.
   DATA lStreaming       INIT .F.
   DATA cEchoBuffer     INIT ""
   DATA cResponseMime   INIT "html"
   DATA nResponseStatus INIT 200
   DATA lProxied        INIT .F.
   DATA cIP             INIT "127.0.0.1"
   DATA hQueryCache     INIT NIL
   DATA hCookieCache    INIT NIL

   METHOD New( cMethod, cPath, cQuery )
   METHOD Header( cKey, xDef )
   METHOD QueryParam( cKey, xDef )
   METHOD QueryParamsAll()
   METHOD Cookie( cName, xDef )
   METHOD FormBody()
   METHOD JsonBody()
   METHOD ReadBody()
   METHOD ContentType()
   METHOD IsJson()
   METHOD IsForm()
   METHOD IsAjax()
   METHOD IsHttps()
   METHOD Scheme()
   METHOD RealIP()
   METHOD RealHost()
   METHOD Respond( xData, nStatus, cMime, hExtra )
   METHOD Redirect( cUrl, nStatus )
   METHOD RespondStart( cMime, nStatus, hExtra )
   METHOD RespondChunk( cData )
   METHOD RespondEnd()
ENDCLASS

METHOD New( cMethod, cPath, cQuery ) CLASS TMockReq
   ::cMethod := hb_defaultValue( cMethod, "GET" )
   ::cPath   := hb_defaultValue( cPath,   "/" )
   ::cQuery  := hb_defaultValue( cQuery,  "" )
RETURN Self

METHOD Header( cKey, xDef ) CLASS TMockReq
   hb_default( @xDef, "" )
RETURN hb_HGetDef( ::hHeaders, Lower( cKey ), xDef )

METHOD QueryParam( cKey, xDef ) CLASS TMockReq
   LOCAL aPairs, cPair, nEq
   IF ::hQueryCache == NIL
      ::hQueryCache := { => }
      aPairs := hb_ATokens( ::cQuery, "&" )
      FOR EACH cPair IN aPairs
         nEq := At( "=", cPair )
         IF nEq > 0
            ::hQueryCache[ AllTrim( Left( cPair, nEq-1 ) ) ] := AllTrim( SubStr( cPair, nEq+1 ) )
         ENDIF
      NEXT
   ENDIF
RETURN hb_HGetDef( ::hQueryCache, cKey, xDef )

METHOD QueryParamsAll() CLASS TMockReq
   ::QueryParam( "", "" )
RETURN hb_HClone( ::hQueryCache )

METHOD Cookie( cName, xDef ) CLASS TMockReq
   LOCAL aPairs, cPair, nEq, cRaw
   hb_default( @xDef, "" )
   IF ::hCookieCache == NIL
      ::hCookieCache := { => }
      cRaw   := ::Header( "cookie", "" )
      aPairs := hb_ATokens( cRaw, ";" )
      FOR EACH cPair IN aPairs
         cPair := AllTrim( cPair )
         nEq   := At( "=", cPair )
         IF nEq > 0
            ::hCookieCache[ AllTrim( Left( cPair, nEq-1 ) ) ] := AllTrim( SubStr( cPair, nEq+1 ) )
         ENDIF
      NEXT
   ENDIF
RETURN hb_HGetDef( ::hCookieCache, cName, xDef )

METHOD FormBody() CLASS TMockReq
   LOCAL aPairs, cPair, nEq
   IF ::hFormBody == NIL
      ::hFormBody := { => }
      aPairs := hb_ATokens( ::cBody, "&" )
      FOR EACH cPair IN aPairs
         nEq := At( "=", cPair )
         IF nEq > 0
            ::hFormBody[ AllTrim( Left( cPair, nEq-1 ) ) ] := AllTrim( SubStr( cPair, nEq+1 ) )
         ENDIF
      NEXT
   ENDIF
RETURN ::hFormBody

METHOD JsonBody() CLASS TMockReq
   IF ::hJsonBody == NIL
      ::hJsonBody := hb_jsonDecode( ::cBody )
   ENDIF
RETURN ::hJsonBody

METHOD ReadBody() CLASS TMockReq
RETURN ::cBody

METHOD ContentType() CLASS TMockReq
RETURN Lower( ::Header( "content-type", "" ) )

METHOD IsJson() CLASS TMockReq
RETURN "application/json" $ ::ContentType()

METHOD IsForm() CLASS TMockReq
RETURN "application/x-www-form-urlencoded" $ ::ContentType()

METHOD IsAjax() CLASS TMockReq
RETURN ::Header( "x-requested-with", "" ) == "XMLHttpRequest"

METHOD IsHttps() CLASS TMockReq
RETURN ::Header( "x-forwarded-proto", "" ) == "https"

METHOD Scheme() CLASS TMockReq
   LOCAL cProto := ::Header( "x-forwarded-proto", "" )
RETURN iif( Empty( cProto ), "http", cProto )

METHOD RealIP() CLASS TMockReq
   LOCAL cFwd := ::Header( "x-forwarded-for", "" )
RETURN iif( Empty( cFwd ), ::cIP, AllTrim( hb_ATokens( cFwd, "," )[1] ) )

METHOD RealHost() CLASS TMockReq
RETURN ::Header( "host", "" )

METHOD Respond( xData, nStatus, cMime, hExtra ) CLASS TMockReq
   LOCAL xTmp
   HB_SYMBOL_UNUSED( hExtra )
   IF ValType( nStatus ) == "C"
      xTmp    := nStatus ; nStatus := iif( ValType( cMime ) == "N", cMime, 200 ) ; cMime := xTmp
   ELSEIF nStatus == NIL .AND. ValType( cMime ) == "N"
      nStatus := cMime ; cMime := NIL
   ENDIF
   hb_default( @nStatus, 200 )
   hb_default( @cMime,   "html" )
   ::nStatus    := nStatus
   ::cMime      := cMime
   ::lResponded := .T.
   DO CASE
   CASE ValType( xData ) == "C" ; ::cBodyResp := xData
   CASE ValType( xData ) == "H" ; ::cBodyResp := hb_jsonEncode( xData )
   OTHERWISE                    ; ::cBodyResp := ""
   ENDCASE
RETURN Self

METHOD RespondStart( cMime, nStatus, hExtra ) CLASS TMockReq
   hb_default( @cMime,   "html" )
   hb_default( @nStatus, 200 )
   hb_default( @hExtra,  {=>} )
   HB_SYMBOL_UNUSED( hExtra )
   ::nStatus    := nStatus
   ::cMime      := cMime
   ::lResponded := .T.
   ::lStreaming  := .T.
RETURN Self

METHOD RespondChunk( cData ) CLASS TMockReq
   ::cBodyResp += cData
RETURN Self

METHOD RespondEnd() CLASS TMockReq
   ::lStreaming := .F.
RETURN Self

METHOD Redirect( cUrl, nStatus ) CLASS TMockReq
   hb_default( @nStatus, 302 )
   ::nStatus    := nStatus
   ::lResponded := .T.
   ::hExtraHeaders[ "Location" ] := cUrl
RETURN Self

FUNCTION HIX_TestHelpers_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   _TestRequestHelpers( hCtx )
   _TestGetPost(        hCtx )
   _TestHeaderCookie(   hCtx )
   _TestBody(           hCtx )
   _TestResponse(       hCtx )
   _TestWrite(          hCtx )
   _TestContentType(    hCtx )
   _TestText(           hCtx )
   _TestStreaming(       hCtx )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _TestRequestHelpers( hCtx )
   LOCAL oMock

   oMock := TMockReq():New( "GET", "/api/users", "" )
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, UMethod() == "GET",        "Helpers: UMethod() GET",         "GET",       UMethod() )
   HixTU_Check( hCtx, UPath()   == "/api/users", "Helpers: UPath()",               "/api/users",UPath() )
   HixTU_Check( hCtx, UIsGet(),                  "Helpers: UIsGet() TRUE",          ".T.",       hb_CStr( UIsGet() ) )
   HixTU_Check( hCtx, ! UIsPost(),               "Helpers: UIsPost() FALSE",        ".F.",       hb_CStr( UIsPost() ) )
   HixTU_Check( hCtx, UScheme() == "http",       "Helpers: UScheme() default http", "http",      UScheme() )

   oMock := TMockReq():New( "POST", "/login", "" )
   oMock:hHeaders[ "x-forwarded-proto" ] := "https"
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, UIsPost(),             "Helpers: UIsPost() TRUE",   ".T.",   hb_CStr( UIsPost() ) )
   HixTU_Check( hCtx, UIsHttps(),            "Helpers: UIsHttps() TRUE",  ".T.",   hb_CStr( UIsHttps() ) )
   HixTU_Check( hCtx, UScheme() == "https",  "Helpers: UScheme() https",  "https", UScheme() )
RETURN

STATIC PROCEDURE _TestGetPost( hCtx )
   LOCAL oMock, hP, hG

   oMock := TMockReq():New( "GET", "/search", "q=harbour&page=2" )
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, UGet( "q",    "" ) == "harbour", "Helpers: UGet q=harbour",  "harbour", UGet( "q", "" ) )
   HixTU_Check( hCtx, UGet( "page", "" ) == "2",        "Helpers: UGet page=2",     "2",       UGet( "page", "" ) )
   HixTU_Check( hCtx, UGet( "nope", "def" ) == "def",   "Helpers: UGet default",    "def",     UGet( "nope", "def" ) )

   hG := UGet()
   HixTU_Check( hCtx, ValType( hG ) == "H",                        "Helpers: UGet() hash",          "H",       ValType( hG ) )
   HixTU_Check( hCtx, hb_HGetDef( hG, "q",    "" ) == "harbour",   "Helpers: UGet() q=harbour",     "harbour", hb_HGetDef( hG, "q",    "" ) )
   HixTU_Check( hCtx, hb_HGetDef( hG, "page", "" ) == "2",         "Helpers: UGet() page=2",        "2",       hb_HGetDef( hG, "page", "" ) )
   HixTU_Check( hCtx, Len( hG ) == 2,                              "Helpers: UGet() 2 claves",      "2",       hb_NToS( Len( hG ) ) )

   oMock := TMockReq():New( "POST", "/submit", "" )
   oMock:cBody    := "user=carles&pass=1234"
   oMock:hHeaders[ "content-type" ] := "application/x-www-form-urlencoded"
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, UPost( "user", "" ) == "carles", "Helpers: UPost user=carles", "carles", UPost( "user", "" ) )
   HixTU_Check( hCtx, UPost( "pass", "" ) == "1234",   "Helpers: UPost pass=1234",   "1234",   UPost( "pass", "" ) )
   HixTU_Check( hCtx, UPost( "nope", "x" ) == "x",     "Helpers: UPost default",     "x",      UPost( "nope", "x" ) )

   hP := UPost()
   HixTU_Check( hCtx, ValType( hP ) == "H",                        "Helpers: UPost() hash",         "H",       ValType( hP ) )
   HixTU_Check( hCtx, hb_HGetDef( hP, "user", "" ) == "carles",    "Helpers: UPost() user",         "carles",  hb_HGetDef( hP, "user", "" ) )
   HixTU_Check( hCtx, hb_HGetDef( hP, "pass", "" ) == "1234",      "Helpers: UPost() pass",         "1234",    hb_HGetDef( hP, "pass", "" ) )

   oMock := TMockReq():New( "POST", "/api/login", "" )
   oMock:cBody    := '{"user":"admin","pass":"1234"}'
   oMock:hHeaders[ "content-type" ] := "application/json"
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, UPost( "user", "" ) == "admin", "Helpers: UPost JSON user=admin", "admin", UPost( "user", "" ) )
   HixTU_Check( hCtx, UPost( "pass", "" ) == "1234",  "Helpers: UPost JSON pass=1234",  "1234",  UPost( "pass", "" ) )
   HixTU_Check( hCtx, UPost( "nope", "x" ) == "x",   "Helpers: UPost JSON default",    "x",     UPost( "nope", "x" ) )

   hP := UPost()
   HixTU_Check( hCtx, ValType( hP ) == "H",                         "Helpers: UPost() JSON hash",   "H",     ValType( hP ) )
   HixTU_Check( hCtx, hb_HGetDef( hP, "user", "" ) == "admin",      "Helpers: UPost() JSON user",   "admin", hb_HGetDef( hP, "user", "" ) )

   oMock := TMockReq():New( "GET", "/users/42", "" )
   oMock:hParam[ "id"   ] := "42"
   oMock:hParam[ "slug" ] := "harbour"
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, UParam( "id",   "" ) == "42",      "Helpers: UParam id=42",       "42",      UParam( "id",   "" ) )
   HixTU_Check( hCtx, UParam( "slug", "" ) == "harbour",  "Helpers: UParam slug=harbour","harbour", UParam( "slug", "" ) )
   HixTU_Check( hCtx, UParam( "none", "d" ) == "d",       "Helpers: UParam default",     "d",       UParam( "none", "d" ) )

   hP := UParam()
   HixTU_Check( hCtx, ValType( hP ) == "H",                              "Helpers: UParam() hash",         "H",       ValType( hP ) )
   HixTU_Check( hCtx, hb_HGetDef( hP, "id",   "" ) == "42",             "Helpers: UParam() id=42",        "42",      hb_HGetDef( hP, "id",   "" ) )
   HixTU_Check( hCtx, hb_HGetDef( hP, "slug", "" ) == "harbour",        "Helpers: UParam() slug",         "harbour", hb_HGetDef( hP, "slug", "" ) )
   HixTU_Check( hCtx, Len( hP ) == 2,                                    "Helpers: UParam() 2 claves",     "2",       hb_NToS( Len( hP ) ) )
RETURN

STATIC PROCEDURE _TestHeaderCookie( hCtx )
   LOCAL oMock

   oMock := TMockReq():New( "GET", "/", "" )
   oMock:hHeaders[ "accept-language"  ] := "es-ES"
   oMock:hHeaders[ "x-requested-with" ] := "XMLHttpRequest"
   oMock:hHeaders[ "x-forwarded-for"  ] := "10.0.0.1, 192.168.1.1"
   oMock:hHeaders[ "host"             ] := "example.com"
   oMock:hHeaders[ "cookie"           ] := "sessid=abc123; theme=dark"
   HIX_SetRequest( oMock )

   HixTU_Check( hCtx, UHeader( "accept-language", "" ) == "es-ES",  "Helpers: UHeader accept-language",  "es-ES",      UHeader( "accept-language", "" ) )
   HixTU_Check( hCtx, UHeader( "missing", "def" )       == "def",   "Helpers: UHeader default",           "def",        UHeader( "missing", "def" ) )
   HixTU_Check( hCtx, UIsAjax(),                                    "Helpers: UIsAjax() TRUE",            ".T.",        hb_CStr( UIsAjax() ) )
   HixTU_Check( hCtx, UIP()   == "10.0.0.1",                        "Helpers: UIP() x-forwarded-for",    "10.0.0.1",   UIP() )
   HixTU_Check( hCtx, UHost() == "example.com",                     "Helpers: UHost()",                  "example.com",UHost() )
   HixTU_Check( hCtx, UCookie( "sessid", "" ) == "abc123",          "Helpers: UCookie sessid=abc123",    "abc123",     UCookie( "sessid", "" ) )
   HixTU_Check( hCtx, UCookie( "theme",  "" ) == "dark",            "Helpers: UCookie theme=dark",       "dark",       UCookie( "theme", "" ) )
   HixTU_Check( hCtx, UCookie( "nope",   "x" ) == "x",              "Helpers: UCookie default",          "x",          UCookie( "nope", "x" ) )
RETURN

STATIC PROCEDURE _TestBody( hCtx )
   LOCAL oMock

   oMock := TMockReq():New( "POST", "/api", "" )
   oMock:cBody := '{"name":"carles","age":42}'
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, UBody() == '{"name":"carles","age":42}', "Helpers: UBody() raw",   '{"name":"carles","age":42}', UBody() )
   HixTU_Check( hCtx, ValType( UJson() ) == "H",               "Helpers: UJson() hash",  "H",      ValType( UJson() ) )
   HixTU_Check( hCtx, UJson()[ "name" ] == "carles",           "Helpers: UJson name",    "carles", UJson()[ "name" ] )
   HixTU_Check( hCtx, UJson()[ "age"  ] == 42,                 "Helpers: UJson age",     "42",     hb_NToS( UJson()[ "age" ] ) )
RETURN

STATIC PROCEDURE _TestResponse( hCtx )
   LOCAL oMock

   oMock := TMockReq():New( "GET", "/", "" )
   HIX_SetRequest( oMock )
   USendHtml( "<h1>ok</h1>" )
   HixTU_Check( hCtx, ! Empty( oMock:cEchoBuffer ),       "Helpers: USendHtml -> buffer",    "non-empty",   oMock:cEchoBuffer )
   HixTU_Check( hCtx, oMock:nResponseStatus == 200,       "Helpers: USendHtml -> 200",       "200",         hb_NToS( oMock:nResponseStatus ) )
   HixTU_Check( hCtx, oMock:cResponseMime   == "html",    "Helpers: USendHtml -> mime=html", "html",        oMock:cResponseMime )
   HixTU_Check( hCtx, oMock:cEchoBuffer == "<h1>ok</h1>","Helpers: USendHtml -> body",      "<h1>ok</h1>", oMock:cEchoBuffer )

   oMock := TMockReq():New( "GET", "/", "" )
   HIX_SetRequest( oMock )
   USendJson( { "ok" => .T. } )
   HixTU_Check( hCtx, oMock:nResponseStatus == 200,      "Helpers: USendJson -> 200",  "200",  hb_NToS( oMock:nResponseStatus ) )
   HixTU_Check( hCtx, oMock:cResponseMime   == "json",   "Helpers: USendJson -> json", "json", oMock:cResponseMime )

   oMock := TMockReq():New( "GET", "/", "" )
   HIX_SetRequest( oMock )
   URedirect( "/login", 302 )
   HixTU_Check( hCtx, oMock:nStatus == 302,                        "Helpers: URedirect -> 302",      "302",   hb_NToS( oMock:nStatus ) )
   HixTU_Check( hCtx, oMock:hExtraHeaders[ "Location" ] == "/login","Helpers: URedirect Location",   "/login",oMock:hExtraHeaders[ "Location" ] )

   oMock := TMockReq():New( "GET", "/", "" )
   HIX_SetRequest( oMock )
   USetHeader( "X-Custom", "valor" )
   HixTU_Check( hCtx, oMock:hExtraHeaders[ "X-Custom" ] == "valor", "Helpers: USetHeader X-Custom", "valor", oMock:hExtraHeaders[ "X-Custom" ] )

   oMock := TMockReq():New( "GET", "/", "" )
   HIX_SetRequest( oMock )
   USendError( 404 )
   HixTU_Check( hCtx, oMock:lResponded,      "Helpers: USendError -> responded", ".T.", hb_CStr( oMock:lResponded ) )
   HixTU_Check( hCtx, oMock:nStatus == 404,  "Helpers: USendError -> 404",       "404", hb_NToS( oMock:nStatus ) )
RETURN

STATIC PROCEDURE _TestWrite( hCtx )
   LOCAL cResult

   HIX_SetRequest( NIL )
   HIX_EchoClear()
   UEcho( "hola" )
   UEcho( " mundo" )
   cResult := HIX_EchoGet()
   HixTU_Check( hCtx, cResult == "hola mundo", "Helpers: UEcho acumula en echo buffer", "hola mundo", cResult )

   HixTU_Check( hCtx, ! Empty( UNow() ),   "Helpers: UNow() no vacio",    "no empty", UNow() )
   HixTU_Check( hCtx, Len( UNow() ) >= 14, "Helpers: UNow() longitud OK", ">=14",     hb_NToS( Len( UNow() ) ) )

   HIX_SetRequest( NIL )
   HixTU_Check( hCtx, UMethod()      == "",  "Helpers: sin request UMethod()=''",   "",  UMethod() )
   HixTU_Check( hCtx, UGet( "x","d") == "d", "Helpers: sin request UGet default",   "d", UGet( "x", "d" ) )
   HixTU_Check( hCtx, ! UIsAjax(),           "Helpers: sin request UIsAjax()=.F.", ".F.",hb_CStr( UIsAjax() ) )
RETURN

STATIC PROCEDURE _TestContentType( hCtx )
   LOCAL oMock

   oMock := TMockReq():New( "POST", "/api", "" )
   oMock:hHeaders[ "content-type" ] := "application/json"
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, UContentType() == "application/json", "Helpers: UContentType() json", "application/json", UContentType() )
   HixTU_Check( hCtx, UIsJson(),                            "Helpers: UIsJson() TRUE",        ".T.", hb_CStr( UIsJson() ) )

   oMock := TMockReq():New( "POST", "/form", "" )
   oMock:hHeaders[ "content-type" ] := "application/x-www-form-urlencoded"
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, ! UIsJson(), "Helpers: UIsJson() FALSE", ".F.", hb_CStr( UIsJson() ) )

   oMock := TMockReq():New( "GET", "/search", "q=test&lang=es" )
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, UQuery() == "q=test&lang=es", "Helpers: UQuery()", "q=test&lang=es", UQuery() )

   oMock := TMockReq():New( "GET", "/data", "" )
   oMock:hHeaders[ "accept" ] := "application/json"
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, UWantsJson(), "Helpers: UWantsJson() via Accept", ".T.", hb_CStr( UWantsJson() ) )

   oMock := TMockReq():New( "GET", "/data", "" )
   oMock:hHeaders[ "x-requested-with" ] := "XMLHttpRequest"
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, UWantsJson(), "Helpers: UWantsJson() via AJAX", ".T.", hb_CStr( UWantsJson() ) )

   oMock := TMockReq():New( "GET", "/page", "" )
   HIX_SetRequest( oMock )
   HixTU_Check( hCtx, ! UWantsJson(), "Helpers: UWantsJson() FALSE", ".F.", hb_CStr( UWantsJson() ) )
RETURN

STATIC PROCEDURE _TestText( hCtx )
   LOCAL oMock

   oMock := TMockReq():New( "GET", "/", "" )
   HIX_SetRequest( oMock )
   USendText( "hello plain" )
   HixTU_Check( hCtx, ! Empty( oMock:cEchoBuffer ),            "Helpers: USendText -> buffer",    "non-empty",   oMock:cEchoBuffer )
   HixTU_Check( hCtx, oMock:nResponseStatus == 200,            "Helpers: USendText -> 200",       "200",         hb_NToS( oMock:nResponseStatus ) )
   HixTU_Check( hCtx, oMock:cResponseMime == "text",           "Helpers: USendText -> mime=text", "text",        oMock:cResponseMime )
   HixTU_Check( hCtx, oMock:cEchoBuffer == "hello plain",      "Helpers: USendText -> body",      "hello plain", oMock:cEchoBuffer )

   oMock := TMockReq():New( "GET", "/", "" )
   HIX_SetRequest( oMock )
   USendText( "error", 422 )
   HixTU_Check( hCtx, oMock:nResponseStatus == 422, "Helpers: USendText -> 422", "422", hb_NToS( oMock:nResponseStatus ) )

   oMock := TMockReq():New( "DELETE", "/item/1", "" )
   HIX_SetRequest( oMock )
   USendEmpty()
   HixTU_Check( hCtx, oMock:lResponded,     "Helpers: USendEmpty -> responded", ".T.", hb_CStr( oMock:lResponded ) )
   HixTU_Check( hCtx, oMock:nStatus == 204, "Helpers: USendEmpty -> 204",       "204", hb_NToS( oMock:nStatus ) )
RETURN

STATIC PROCEDURE _TestStreaming( hCtx )
   LOCAL oMock

   oMock := TMockReq():New( "GET", "/stream", "" )
   HIX_SetRequest( oMock )
   USendStreamStart( "text", 200 )
   HixTU_Check( hCtx, oMock:lResponded,       "Helpers: USendStreamStart -> responded",  ".T.", hb_CStr( oMock:lResponded ) )
   HixTU_Check( hCtx, oMock:nStatus == 200,   "Helpers: USendStreamStart -> 200",        "200", hb_NToS( oMock:nStatus ) )
   HixTU_Check( hCtx, oMock:cMime == "text",  "Helpers: USendStreamStart -> mime=text", "text",hb_CStr( oMock:cMime == "text" ) )
   HixTU_Check( hCtx, oMock:lStreaming,       "Helpers: USendStreamStart -> lStreaming", ".T.", hb_CStr( oMock:lStreaming ) )

   USendChunk( "chunk1" )
   USendChunk( "chunk2" )
   HixTU_Check( hCtx, oMock:cBodyResp == "chunk1chunk2", "Helpers: USendChunk acumula", "chunk1chunk2", oMock:cBodyResp )

   USendStreamEnd()
   HixTU_Check( hCtx, ! oMock:lStreaming, "Helpers: USendStreamEnd -> lStreaming .F.", ".F.", hb_CStr( oMock:lStreaming ) )

   HIX_SetRequest( NIL )
   USendStreamStart( "html" )
   USendChunk( "x" )
   USendStreamEnd()
   HixTU_Pass( hCtx, "Helpers: streaming sin request sin crash" )
RETURN
