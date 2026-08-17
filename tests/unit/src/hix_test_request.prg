/*-----------------------------------------------------------
  File ......: hix_test_request.prg
  Author.....: Charly 9000
  Created....: 2026-06-06
  Modified...: 2026-06-07
  Description: Integrated test — THixRequest parsing (query, cookie,
               content-type helpers, redirect, headers, body, keep-alive).
               Uses TMockIO from hix_test_utils.
 -----------------------------------------------------------*/
#include "fileio.ch"
#include "hix_const.ch"

#define CRLF ( Chr(13) + Chr(10) )

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[Request] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

// Build raw GET request (simple)
STATIC FUNCTION _RQMake( cPath, cQS, cExtraHeaders )
   LOCAL cUrl
   hb_default( @cPath,         "/" )
   hb_default( @cQS,           "" )
   hb_default( @cExtraHeaders, "" )
   cUrl := cPath + iif( Empty( cQS ), "", "?" + cQS )
RETURN "GET " + cUrl + " HTTP/1.1" + CRLF + "Host: localhost" + CRLF + cExtraHeaders + CRLF

// Build raw request with any method, headers hash, and body
STATIC FUNCTION _RQMakeMethod( cMethod, cPath, hHeaders, cBody )
   LOCAL cRaw, cKey
   hb_default( @cMethod,  "GET" )
   hb_default( @cPath,    "/" )
   hb_default( @hHeaders, {=>} )
   hb_default( @cBody,    "" )
   IF ! Empty( cBody ) .AND. ! hb_HHasKey( hHeaders, "Content-Length" )
      hHeaders["Content-Length"] := hb_NToS( Len( cBody ) )
   ENDIF
   cRaw := cMethod + " " + cPath + " HTTP/1.1" + CRLF + "Host: localhost" + CRLF
   FOR EACH cKey IN hb_HKeys( hHeaders )
      cRaw += cKey + ": " + hHeaders[ cKey ] + CRLF
   NEXT
   cRaw += CRLF
RETURN cRaw

// Parse raw HTTP into THixRequest
STATIC FUNCTION _RQParse( cRaw, cBody )
   LOCAL oIO, oReq
   hb_default( @cBody, "" )
   oIO  := TMockIO():New( cRaw, cBody )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
RETURN oReq

// Parse raw HTTP response from oIO:cWritten
STATIC FUNCTION _RQParseResp( cRaw )
   LOCAL nSep, cHead, cBody, aLines, cLine, nStatus, hResp
   hResp := {=>}
   nSep  := At( CRLF + CRLF, cRaw )
   cHead := iif( nSep > 0, Left( cRaw, nSep - 1 ), cRaw )
   cBody := iif( nSep > 0, SubStr( cRaw, nSep + 4 ), "" )
   aLines := hb_ATokens( StrTran( cHead, Chr(13), "" ), Chr(10) )
   IF Len( aLines ) >= 1
      cLine   := aLines[1]
      nStatus := Val( SubStr( cLine, At( " ", cLine ) + 1, 3 ) )
   ELSE
      nStatus := 0
   ENDIF
   hResp["status"] := nStatus
   hResp["head"]   := cHead
   hResp["body"]   := cBody
RETURN hResp

FUNCTION HIX_TestRequest_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   _TLog( "=== HIX_TestRequest_Run start ===" )
   _RQRequestLine( hCtx )
   _RQHeaders(     hCtx )
   _RQKeepAlive(   hCtx )
   _RQReadBody(    hCtx )
   _RQQueryString( hCtx )
   _RQQueryFull(   hCtx )
   _RQCookie(      hCtx )
   _RQAjax(        hCtx )
   _RQContentType( hCtx )
   _RQBodyType(    hCtx )
   _RQBodyParsing( hCtx )
   _RQRespond(     hCtx )
   _RQRedirect(    hCtx )
   _RQEdgeCases(   hCtx )
   _TLog( "=== HIX_TestRequest_Run end ===" )
RETURN hCtx

// --- Suite: request line parsing ---

STATIC PROCEDURE _RQRequestLine( hCtx )
   LOCAL oReq, oIO, oR
   _TLog( "_RQRequestLine" )
   oReq := _RQParse( _RQMakeMethod( "GET", "/" ) )
   HixTU_Check( hCtx, oReq:cMethod   == "GET",      "Request line: GET method",    "GET",      oReq:cMethod )
   HixTU_Check( hCtx, oReq:cPath     == "/",         "Request line: GET path",      "/",        oReq:cPath )
   HixTU_Check( hCtx, oReq:cQuery    == "",          "Request line: GET query ''",  "",         oReq:cQuery )
   HixTU_Check( hCtx, oReq:cProtocol == "HTTP/1.1", "Request line: protocol",      "HTTP/1.1", oReq:cProtocol )
   oReq := _RQParse( _RQMakeMethod( "POST", "/api/users" ) )
   HixTU_Check( hCtx, oReq:cMethod == "POST",       "Request line: POST method",   "POST",       oReq:cMethod )
   HixTU_Check( hCtx, oReq:cPath   == "/api/users", "Request line: POST path",     "/api/users", oReq:cPath )
   oReq := _RQParse( _RQMakeMethod( "DELETE", "/items/42" ) )
   HixTU_Check( hCtx, oReq:cMethod == "DELETE",    "Request line: DELETE method",  "DELETE",    oReq:cMethod )
   HixTU_Check( hCtx, oReq:cPath   == "/items/42", "Request line: DELETE path",    "/items/42", oReq:cPath )
   oReq := _RQParse( _RQMakeMethod( "PUT", "/users/7" ) )
   HixTU_Check( hCtx, oReq:cMethod == "PUT",      "Request line: PUT method",  "PUT",      oReq:cMethod )
   oReq := _RQParse( _RQMake( "/search", "q=harbour&lang=es" ) )
   HixTU_Check( hCtx, oReq:cPath  == "/search",          "Request line: query path sin ?",  "/search",          oReq:cPath )
   HixTU_Check( hCtx, oReq:cQuery == "q=harbour&lang=es", "Request line: query string raw", "q=harbour&lang=es", oReq:cQuery )
   oReq := _RQParse( _RQMake( "/", "page=1" ) )
   HixTU_Check( hCtx, oReq:cPath  == "/",      "Request line: query raiz path",  "/",      oReq:cPath )
   HixTU_Check( hCtx, oReq:cQuery == "page=1", "Request line: query raiz query", "page=1", oReq:cQuery )
   oIO := TMockIO():New( "GET / HTTP/1.1" + CRLF + "Host: localhost" + CRLF + CRLF, "" )
   oR  := THixRequest():New( oIO, "1.2.3.4" )
   HixTU_Check( hCtx, oR:Read(),            "Request line: Read() .T. en request valida", ".T.", ".F." )
   HixTU_Check( hCtx, oR:cIP == "1.2.3.4", "Request line: IP almacenada",                "1.2.3.4", oR:cIP )
RETURN

// --- Suite: headers ---

STATIC PROCEDURE _RQHeaders( hCtx )
   LOCAL oReq
   _TLog( "_RQHeaders" )
   oReq := _RQParse( _RQMakeMethod( "POST", "/", { ;
      "Content-Type"  => "application/json", ;
      "X-Custom"      => "valor123",         ;
      "Authorization" => "Bearer token"      ;
   } ) )
   HixTU_Check( hCtx, hb_HHasKey( oReq:hHeaders, "content-type" ),  "Headers: content-type normalizado lowercase",    "key", "?" )
   HixTU_Check( hCtx, hb_HHasKey( oReq:hHeaders, "x-custom" ),      "Headers: x-custom presente",                    "key", "?" )
   HixTU_Check( hCtx, hb_HHasKey( oReq:hHeaders, "authorization" ), "Headers: authorization presente",               "key", "?" )
   HixTU_Check( hCtx, oReq:Header( "content-type" )  == "application/json", "Header(): lowercase lookup",   "application/json", oReq:Header( "content-type" ) )
   HixTU_Check( hCtx, oReq:Header( "Content-Type" )  == "application/json", "Header(): mixed-case lookup",  "application/json", oReq:Header( "Content-Type" ) )
   HixTU_Check( hCtx, oReq:Header( "CONTENT-TYPE" )  == "application/json", "Header(): uppercase lookup",   "application/json", oReq:Header( "CONTENT-TYPE" ) )
   HixTU_Check( hCtx, oReq:Header( "x-custom" )      == "valor123",         "Header(): x-custom valor",     "valor123",         oReq:Header( "x-custom" ) )
   HixTU_Check( hCtx, oReq:Header( "authorization" )  == "Bearer token",    "Header(): authorization valor", "Bearer token",    oReq:Header( "authorization" ) )
   HixTU_Check( hCtx, oReq:Header( "x-missing" )     == "",                 "Header(): inexistente -> ''",   "",                oReq:Header( "x-missing" ) )
   HixTU_Check( hCtx, oReq:Header( "x-missing", "df" ) == "df",             "Header(): inexistente -> xDef", "df",              oReq:Header( "x-missing", "df" ) )
   oReq := _RQParse( _RQMakeMethod( "GET", "/", { "X-Date" => "2026-04-24T14:00:00Z" } ) )
   HixTU_Check( hCtx, oReq:Header( "x-date" ) == "2026-04-24T14:00:00Z", "Header: valor con ':' -> completo", "2026-04-24T14:00:00Z", oReq:Header( "x-date" ) )
   oReq := _RQParse( _RQMakeMethod( "POST", "/", { "Content-Length" => "512" } ) )
   HixTU_Check( hCtx, oReq:ContentLength() == 512, "ContentLength(): 512",          "512", hb_NToS( oReq:ContentLength() ) )
   oReq := _RQParse( _RQMakeMethod( "GET", "/" ) )
   HixTU_Check( hCtx, oReq:ContentLength() == 0,   "ContentLength(): sin header -> 0", "0", hb_NToS( oReq:ContentLength() ) )
RETURN

// --- Suite: keep-alive ---

STATIC PROCEDURE _RQKeepAlive( hCtx )
   LOCAL oIO, oR
   _TLog( "_RQKeepAlive" )
   oR := _RQParse( _RQMakeMethod( "GET", "/" ) )
   HixTU_Check( hCtx, oR:lKeepAlive,  "KeepAlive: HTTP/1.1 sin header -> .T.", ".T.", hb_ValToStr( oR:lKeepAlive ) )
   oR := _RQParse( _RQMakeMethod( "GET", "/", { "Connection" => "keep-alive" } ) )
   HixTU_Check( hCtx, oR:lKeepAlive,  "KeepAlive: Connection: keep-alive -> .T.", ".T.", hb_ValToStr( oR:lKeepAlive ) )
   oR := _RQParse( _RQMakeMethod( "GET", "/", { "Connection" => "close" } ) )
   HixTU_Check( hCtx, ! oR:lKeepAlive, "KeepAlive: Connection: close -> .F.", ".F.", hb_ValToStr( oR:lKeepAlive ) )
   oIO := TMockIO():New( "GET / HTTP/1.0" + CRLF + "Host: localhost" + CRLF + CRLF, "" )
   oR  := THixRequest():New( oIO, "127.0.0.1" )
   oR:Read()
   HixTU_Check( hCtx, ! oR:lKeepAlive, "KeepAlive: HTTP/1.0 sin header -> .F.", ".F.", hb_ValToStr( oR:lKeepAlive ) )
   oIO := TMockIO():New( "GET / HTTP/1.0" + CRLF + "Host: localhost" + CRLF + "Connection: keep-alive" + CRLF + CRLF, "" )
   oR  := THixRequest():New( oIO, "127.0.0.1" )
   oR:Read()
   HixTU_Check( hCtx, oR:lKeepAlive,   "KeepAlive: HTTP/1.0 + keep-alive -> .T.", ".T.", hb_ValToStr( oR:lKeepAlive ) )
RETURN

// --- Suite: ReadBody ---

STATIC PROCEDURE _RQReadBody( hCtx )
   LOCAL oIO, oR, cBody
   _TLog( "_RQReadBody" )
   oR := _RQParse( _RQMakeMethod( "GET", "/" ) )
   HixTU_Check( hCtx, oR:ReadBody() == "", "ReadBody: GET sin body -> ''", "", oR:ReadBody() )
   oIO := TMockIO():New( _RQMakeMethod( "POST", "/", { "Content-Length" => "11" } ), "hello world" )
   oR  := THixRequest():New( oIO, "127.0.0.1" )
   oR:Read()
   cBody := oR:ReadBody()
   HixTU_Check( hCtx, cBody == "hello world", "ReadBody: POST 11 bytes",   "hello world", cBody )
   oIO := TMockIO():New( _RQMakeMethod( "POST", "/", { "Content-Length" => "0" } ), "" )
   oR  := THixRequest():New( oIO, "127.0.0.1" )
   oR:Read()
   HixTU_Check( hCtx, oR:ReadBody() == "", "ReadBody: Content-Length:0 -> ''", "", oR:ReadBody() )
   oIO := TMockIO():New( _RQMakeMethod( "POST", "/", { "Content-Length" => "5" } ), "first" )
   oR  := THixRequest():New( oIO, "127.0.0.1" )
   oR:Read()
   oR:ReadBody()
   oIO:cBodyData := "other"
   HixTU_Check( hCtx, oR:ReadBody() == "first", "ReadBody: idempotente (cache)", "first", oR:ReadBody() )
   oIO := TMockIO():New( _RQMakeMethod( "POST", "/", { "Content-Length" => "100" } ), "short" )
   oR  := THixRequest():New( oIO, "127.0.0.1" )
   oR:Read()
   cBody := oR:ReadBody()
   HixTU_Check( hCtx, Len( cBody ) <= 100, "ReadBody: parcial no explota", "<=100", hb_NToS( Len( cBody ) ) )
RETURN

// --- Suite: query string (existing) ---

STATIC PROCEDURE _RQQueryString( hCtx )
   LOCAL oReq, hAll
   _TLog( "_RQQueryString" )
   oReq := _RQParse( _RQMake( "/page", "k=hello&n=42" ) )
   HixTU_Check( hCtx, oReq:QueryParam( "k" ) == "hello", "Request: QueryParam k=hello", "hello", oReq:QueryParam( "k" ) )
   HixTU_Check( hCtx, oReq:QueryParam( "n" ) == "42",    "Request: QueryParam n=42",    "42",    oReq:QueryParam( "n" ) )
   HixTU_Check( hCtx, oReq:QueryParam( "missing", "def" ) == "def", "Request: QueryParam missing -> default", "def", oReq:QueryParam( "missing", "def" ) )
   hAll := oReq:QueryParamsAll()
   HixTU_Check( hCtx, ValType( hAll ) == "H",  "Request: QueryParamsAll es hash",    "H", ValType( hAll ) )
   HixTU_Check( hCtx, hb_HHasKey( hAll, "k" ), "Request: QueryParamsAll tiene 'k'",  "key", "missing" )
   HixTU_Check( hCtx, hb_HHasKey( hAll, "n" ), "Request: QueryParamsAll tiene 'n'",  "key", "missing" )
RETURN

// --- Suite: query string extended (URL decode, idempotence) ---

STATIC PROCEDURE _RQQueryFull( hCtx )
   LOCAL oReq
   _TLog( "_RQQueryFull" )
   oReq := _RQParse( _RQMake( "/go", "name=hello+world&path=%2Fapi%2Fv1" ) )
   HixTU_Check( hCtx, oReq:QueryParam( "name" ) == "hello world", "QueryFull: + decodificado",   "hello world", oReq:QueryParam( "name" ) )
   HixTU_Check( hCtx, oReq:QueryParam( "path" ) == "/api/v1",     "QueryFull: %2F decodificado", "/api/v1",     oReq:QueryParam( "path" ) )
   oReq := _RQParse( _RQMake( "/", "Token=abc" ) )
   HixTU_Check( hCtx, oReq:QueryParam( "token" ) == "abc", "QueryFull: case-insensitive lowercase", "abc", oReq:QueryParam( "token" ) )
   HixTU_Check( hCtx, oReq:QueryParam( "TOKEN" ) == "abc", "QueryFull: case-insensitive uppercase", "abc", oReq:QueryParam( "TOKEN" ) )
   oReq := _RQParse( _RQMake( "/nada" ) )
   HixTU_Check( hCtx, oReq:QueryParam( "x" ) == "", "QueryFull: sin query string -> ''", "", oReq:QueryParam( "x" ) )
RETURN

// --- Suite: cookie (existing) ---

STATIC PROCEDURE _RQCookie( hCtx )
   LOCAL oReq
   _TLog( "_RQCookie" )
   oReq := _RQParse( _RQMake( "/", "", "Cookie: sid=abc123; user=bob" + CRLF ) )
   HixTU_Check( hCtx, oReq:Cookie( "sid" )         == "abc123", "Request: Cookie sid=abc123",     "abc123", oReq:Cookie( "sid" ) )
   HixTU_Check( hCtx, oReq:Cookie( "user" )        == "bob",    "Request: Cookie user=bob",       "bob",    oReq:Cookie( "user" ) )
   HixTU_Check( hCtx, oReq:Cookie( "nope", "def" ) == "def",    "Request: Cookie missing -> def", "def",    oReq:Cookie( "nope", "def" ) )
   oReq := _RQParse( _RQMake( "/" ) )
   HixTU_Check( hCtx, oReq:Cookie( "sid", "" ) == "", "Request: Cookie sin header -> empty", "", oReq:Cookie( "sid", "" ) )
RETURN

// --- Suite: Ajax detection (existing) ---

STATIC PROCEDURE _RQAjax( hCtx )
   LOCAL oReq
   _TLog( "_RQAjax" )
   oReq := _RQParse( _RQMake( "/", "", "X-Requested-With: XMLHttpRequest" + CRLF ) )
   HixTU_Check( hCtx, oReq:IsAjax(),   "Request: IsAjax() con header -> .T.", ".T.", ".F." )
   oReq := _RQParse( _RQMake( "/" ) )
   HixTU_Check( hCtx, ! oReq:IsAjax(), "Request: IsAjax() sin header -> .F.", ".F.", ".T." )
RETURN

// --- Suite: content-type (existing) ---

STATIC PROCEDURE _RQContentType( hCtx )
   LOCAL oReq
   _TLog( "_RQContentType" )
   oReq := _RQParse( _RQMake( "/", "", "Content-Type: application/json" + CRLF ) )
   HixTU_Check( hCtx, oReq:ContentType() == "application/json", "Request: ContentType() = application/json", "application/json", oReq:ContentType() )
   HixTU_Check( hCtx, oReq:ContentLength() == 0,                "Request: ContentLength() sin body = 0",     "0", hb_NToS( oReq:ContentLength() ) )
RETURN

// --- Suite: body type helpers (existing) ---

STATIC PROCEDURE _RQBodyType( hCtx )
   LOCAL oReq
   _TLog( "_RQBodyType" )
   oReq := _RQParse( _RQMake( "/", "", "Content-Type: application/json" + CRLF ) )
   HixTU_Check( hCtx, oReq:IsJson(),        "Request: IsJson() con application/json -> .T.", ".T.", ".F." )
   HixTU_Check( hCtx, ! oReq:IsForm(),      "Request: IsForm() con json -> .F.",             ".F.", ".T." )
   HixTU_Check( hCtx, ! oReq:IsMultipart(), "Request: IsMultipart() con json -> .F.",        ".F.", ".T." )
   oReq := _RQParse( _RQMake( "/", "", "Content-Type: application/x-www-form-urlencoded" + CRLF ) )
   HixTU_Check( hCtx, oReq:IsForm(),        "Request: IsForm() con form-urlencoded -> .T.", ".T.", ".F." )
   oReq := _RQParse( _RQMake( "/", "", "Content-Type: multipart/form-data; boundary=----XYZ" + CRLF ) )
   HixTU_Check( hCtx, oReq:IsMultipart(),   "Request: IsMultipart() con multipart -> .T.",  ".T.", ".F." )
   HixTU_Check( hCtx, oReq:MultipartBoundary() == "----XYZ", "Request: MultipartBoundary() extrae boundary", "----XYZ", oReq:MultipartBoundary() )
RETURN

// --- Suite: body parsing via real IO (JsonBody + FormBody) ---

STATIC PROCEDURE _RQBodyParsing( hCtx )
   LOCAL oIO, oReq, hBody, hForm, cJson, cForm
   _TLog( "_RQBodyParsing" )
   cJson := '{"user":"Carles","age":42,"active":true}'
   oIO   := TMockIO():New( _RQMakeMethod( "POST", "/", { "Content-Length" => hb_NToS( Len( cJson ) ), "Content-Type" => "application/json" } ), cJson )
   oReq  := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   hBody := oReq:JsonBody()
   HixTU_Check( hCtx, ValType( hBody ) == "H",                    "IO JSON: retorna hash",       "H",      ValType( hBody ) )
   HixTU_Check( hCtx, hb_HGetDef( hBody, "user", "" ) == "Carles","IO JSON: user = Carles",      "Carles", hb_HGetDef( hBody, "user", "" ) )
   HixTU_Check( hCtx, hb_HGetDef( hBody, "age",   0 ) == 42,      "IO JSON: age = 42",           "42",     hb_NToS( hb_HGetDef( hBody, "age", 0 ) ) )
   HixTU_Check( hCtx, hb_HGetDef( hBody, "active", NIL ) == .T.,  "IO JSON: active = .T.",       ".T.",    hb_ValToStr( hb_HGetDef( hBody, "active", NIL ) ) )
   oIO:cBodyData := "no-effect"
   HixTU_Check( hCtx, hb_HGetDef( oReq:JsonBody(), "user", "" ) == "Carles", "IO JSON: idempotente", "Carles", hb_HGetDef( oReq:JsonBody(), "user", "" ) )
   cForm := "first_name=Pere&last_name=Marti&city=Tarragona&zip=43001"
   oIO   := TMockIO():New( _RQMakeMethod( "POST", "/", { "Content-Length" => hb_NToS( Len( cForm ) ), "Content-Type" => "application/x-www-form-urlencoded" } ), cForm )
   oReq  := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   hForm := oReq:FormBody()
   HixTU_Check( hCtx, ValType( hForm ) == "H",                          "IO Form: retorna hash",     "H",         ValType( hForm ) )
   HixTU_Check( hCtx, hb_HGetDef( hForm, "first_name", "" ) == "Pere",  "IO Form: first_name=Pere",  "Pere",      hb_HGetDef( hForm, "first_name", "" ) )
   HixTU_Check( hCtx, hb_HGetDef( hForm, "city", "" ) == "Tarragona",   "IO Form: city=Tarragona",   "Tarragona", hb_HGetDef( hForm, "city", "" ) )
   HixTU_Check( hCtx, hb_HGetDef( hForm, "zip", "" ) == "43001",        "IO Form: zip=43001",        "43001",     hb_HGetDef( hForm, "zip", "" ) )
RETURN

// --- Suite: Respond (HTTP response output) ---

STATIC PROCEDURE _RQRespond( hCtx )
   LOCAL oIO, oReq, hResp
   _TLog( "_RQRespond" )
   oIO  := TMockIO():New( _RQMakeMethod( "GET", "/" ), "" )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   oReq:Respond( "Hello!", 200, "text" )
   hResp := _RQParseResp( oIO:cWritten )
   HixTU_Check( hCtx, hResp["status"] == 200,           "Respond: status 200",         "200",    hb_NToS( hResp["status"] ) )
   HixTU_Check( hCtx, hResp["body"]   == "Hello!",      "Respond: body texto",         "Hello!", hResp["body"] )
   HixTU_Check( hCtx, "text/plain" $ hResp["head"],     "Respond: Content-Type text",  "text/plain", "?" )
   oIO  := TMockIO():New( _RQMakeMethod( "POST", "/" ), "" )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   oReq:Respond( { "id" => 42, "ok" => .T. }, 201, "json" )
   hResp := _RQParseResp( oIO:cWritten )
   HixTU_Check( hCtx, hResp["status"] == 201,            "Respond: status 201",         "201",  hb_NToS( hResp["status"] ) )
   HixTU_Check( hCtx, "application/json" $ hResp["head"],"Respond: Content-Type json",  "json", "?" )
   HixTU_Check( hCtx, "id" $ hResp["body"],               "Respond: body contiene id",   "id",   hResp["body"] )
   oIO  := TMockIO():New( _RQMakeMethod( "GET", "/nope" ), "" )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   oReq:Respond( "Not Found", 404, "text" )
   hResp := _RQParseResp( oIO:cWritten )
   HixTU_Check( hCtx, hResp["status"] == 404, "Respond: status 404", "404", hb_NToS( hResp["status"] ) )
   oIO  := TMockIO():New( _RQMakeMethod( "GET", "/" ), "" )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   oReq:Respond( "12345" )
   HixTU_Check( hCtx, "Content-Length: 5" $ oIO:cWritten, "Respond: Content-Length = 5", "5", "?" )
   oIO  := TMockIO():New( _RQMakeMethod( "GET", "/" ), "" )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   oReq:Respond( "ok" )
   HixTU_Check( hCtx, "keep-alive" $ Lower( oIO:cWritten ), "Respond: Connection keep-alive", "keep-alive", "?" )
   oIO  := TMockIO():New( _RQMakeMethod( "GET", "/", { "Connection" => "close" } ), "" )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   oReq:Respond( "bye" )
   HixTU_Check( hCtx, "close" $ Lower( oIO:cWritten ), "Respond: Connection close", "close", "?" )
RETURN

// --- Suite: redirect (existing) ---

STATIC PROCEDURE _RQRedirect( hCtx )
   LOCAL oIO, oReq, cWritten
   _TLog( "_RQRedirect" )
   oIO  := TMockIO():New( _RQMake( "/" ), "" )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   oReq:Redirect( "/new-path", 302 )
   cWritten := oIO:cWritten
   HixTU_Check( hCtx, "302" $ cWritten,       "Request: Redirect 302 en respuesta",   "302",      iif( "302" $ cWritten, "302", "no" ) )
   HixTU_Check( hCtx, "/new-path" $ cWritten, "Request: Redirect URL en respuesta",   "/new-path", iif( "/new-path" $ cWritten, "/new-path", "no" ) )
RETURN

// --- Suite: edge cases ---

STATIC PROCEDURE _RQEdgeCases( hCtx )
   LOCAL oIO, oReq, cRaw, i, cBody
   _TLog( "_RQEdgeCases" )
   oIO  := TMockIO():New( "", "" )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   HixTU_Check( hCtx, ! oReq:Read(), "Edge: IO vacio -> Read() .F.", ".F.", hb_ValToStr( oReq:Read() ) )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_CLOSED, "Edge: nReadError = CLOSED", hb_NToS( HIX_REQ_ERR_CLOSED ), hb_NToS( oReq:nReadError ) )
   oIO  := TMockIO():New( "NOTAVALIDREQUEST" + CRLF + CRLF, "" )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   HixTU_Check( hCtx, ! oReq:Read(), "Edge: request invalida -> Read() .F.", ".F.", ".T." )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_BADREQ, "Edge: nReadError = BADREQ", hb_NToS( HIX_REQ_ERR_BADREQ ), hb_NToS( oReq:nReadError ) )
   cRaw := "GET /x HTTP/1.1" + CRLF + "Host: localhost" + CRLF
   FOR i := 1 TO 20
      cRaw += "X-Header-" + hb_NToS(i) + ": value" + hb_NToS(i) + CRLF
   NEXT
   cRaw += CRLF
   oIO  := TMockIO():New( cRaw, "" )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   HixTU_Check( hCtx, Len( oReq:hHeaders ) >= 20, "Edge: 20 headers -> todos parseados", ">=20", hb_NToS( Len( oReq:hHeaders ) ) )
   oIO  := TMockIO():New( "get / HTTP/1.1" + CRLF + "Host: localhost" + CRLF + CRLF, "" )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   HixTU_Check( hCtx, oReq:cMethod == "GET", "Edge: metodo lowercase -> normalizado GET", "GET", oReq:cMethod )
   oReq := _RQParse( _RQMakeMethod( "GET", "/api/v2/my-resource.json" ) )
   HixTU_Check( hCtx, oReq:cPath == "/api/v2/my-resource.json", "Edge: path con guiones y puntos", "/api/v2/my-resource.json", oReq:cPath )
   cBody := "payload"
   oIO   := TMockIO():New( _RQMakeMethod( "POST", "/", { "Content-Length" => hb_NToS( Len( cBody ) ) } ), cBody )
   oReq  := THixRequest():New( oIO, "127.0.0.1" )
   HixTU_Check( hCtx, oReq:Read(), "Edge: Read() .T. antes de ReadBody()", ".T.", ".F." )
   HixTU_Check( hCtx, oReq:ReadBody() == cBody, "Edge: ReadBody() tras Read()", cBody, oReq:ReadBody() )
RETURN
