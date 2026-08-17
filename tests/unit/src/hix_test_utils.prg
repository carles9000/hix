/*-----------------------------------------------------------
  File ......: hix_test_utils.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Shared mock classes and peer-server helpers.
               TMockIO and TMockRequest are defined here once
               to avoid duplicate class symbol conflicts.
               HixTU_Peer* send real HTTP requests to the
               companion server (port 8100) via raw TCP.
 -----------------------------------------------------------*/
#include "hbclass.ch"
#include "hbsocket.ch"

#define PEER_CRLF ( Chr(13) + Chr(10) )

// -------------------------------------------------------
// TMockIO — covers all test needs (lWriteFail, chunks)
// -------------------------------------------------------
CLASS TMockIO
   DATA cHeaderData  INIT ""
   DATA cBodyData    INIT ""
   DATA cWritten     INIT ""
   DATA lClosed      INIT .F.
   DATA lWriteFail   INIT .F.

   METHOD New( cHeaders, cBody )
   METHOD ReadHeaders( nTimeout )
   METHOD Read( nBytes, nTimeout )
   METHOD Write( cData, nTimeout )
   METHOD WriteChunk( cData )
   METHOD WriteChunkEnd()
   METHOD Close()
ENDCLASS

METHOD New( cHeaders, cBody ) CLASS TMockIO
   ::cHeaderData := hb_defaultValue( cHeaders, "" )
   ::cBodyData   := hb_defaultValue( cBody,    "" )
RETURN Self

METHOD ReadHeaders( nTimeout ) CLASS TMockIO
   HB_SYMBOL_UNUSED( nTimeout )
   IF Empty( ::cHeaderData ) ; RETURN NIL ; ENDIF
RETURN ::cHeaderData

METHOD Read( nBytes, nTimeout ) CLASS TMockIO
   LOCAL cChunk
   HB_SYMBOL_UNUSED( nTimeout )
   IF Len( ::cBodyData ) == 0 ; RETURN NIL ; ENDIF
   nBytes      := Min( nBytes, Len( ::cBodyData ) )
   cChunk      := Left( ::cBodyData, nBytes )
   ::cBodyData := SubStr( ::cBodyData, nBytes + 1 )
RETURN cChunk

METHOD Write( cData, nTimeout ) CLASS TMockIO
   HB_SYMBOL_UNUSED( nTimeout )
   IF ::lWriteFail ; RETURN .F. ; ENDIF
   ::cWritten += cData
RETURN .T.

METHOD WriteChunk( cData ) CLASS TMockIO
   IF Empty( cData ) ; RETURN Self ; ENDIF
   ::cWritten += hb_NumToHex( Len( cData ) ) + Chr(13)+Chr(10) + cData + Chr(13)+Chr(10)
RETURN Self

METHOD WriteChunkEnd() CLASS TMockIO
   ::cWritten += "0" + Chr(13)+Chr(10) + Chr(13)+Chr(10)
RETURN Self

METHOD Close() CLASS TMockIO
   ::lClosed := .T.
RETURN Self

// -------------------------------------------------------
// TMockRequest — superset of all test file versions
// -------------------------------------------------------
CLASS TMockRequest
   DATA cPath           INIT "/"
   DATA cMethod         INIT "GET"
   DATA cIP             INIT "127.0.0.1"
   DATA hHeaders        INIT {=>}
   DATA hCookies        INIT NIL
   DATA hFormBody       INIT {=>}
   DATA xJsonBody       INIT NIL
   DATA hExtraHeaders   INIT {=>}
   DATA hParam          INIT {=>}
   DATA hQueryParams    INIT {=>}
   DATA hData           INIT {=>}
   DATA lResponded      INIT .F.
   DATA lStreaming       INIT .F.
   DATA lKeepAlive      INIT .T.
   DATA nStatus         INIT 0
   DATA cBody           INIT ""
   DATA cMime           INIT ""
   DATA cEchoBuffer     INIT ""
   DATA cResponseMime   INIT "html"
   DATA nResponseStatus INIT 200
   DATA cRawBody        INIT ""
   DATA oIO             INIT NIL

   METHOD New( cPath, cMethod )
   METHOD Respond( xData, nStatus, cMime, hExtra )
   METHOD Header( cKey, xDef )
   METHOD QueryParam( cKey, xDef )
   METHOD QueryParamsAll()
   METHOD Cookie( cName, xDef )
   METHOD FormBody()
   METHOD IsJson()
   METHOD IsForm()
   METHOD ReadBody()
   METHOD JsonBody()
   METHOD Redirect( cUrl )
ENDCLASS

METHOD New( cPath, cMethod ) CLASS TMockRequest
   ::cPath         := hb_defaultValue( cPath,   "/" )
   ::cMethod       := hb_defaultValue( cMethod, "GET" )
   ::hHeaders      := {=>}
   ::hQueryParams  := {=>}
   ::hParam        := {=>}
   ::hData         := {=>}
   ::hExtraHeaders := {=>}
   ::hFormBody     := {=>}
   ::hCookies      := NIL
RETURN Self

METHOD Respond( xData, nStatus, cMime, hExtra ) CLASS TMockRequest
   LOCAL xTmp
   HB_SYMBOL_UNUSED( hExtra )
   IF ValType( nStatus ) == "C"
      xTmp    := nStatus
      nStatus := iif( ValType( cMime ) == "N", cMime, 200 )
      cMime   := xTmp
   ELSEIF nStatus == NIL .AND. ValType( cMime ) == "N"
      nStatus := cMime
      cMime   := NIL
   ENDIF
   hb_default( @nStatus, 200   )
   hb_default( @cMime,   "json" )
   ::nStatus    := nStatus
   ::cMime      := cMime
   ::lResponded := .T.
   DO CASE
   CASE ValType( xData ) == "C"                                  ; ::cBody := xData
   CASE ValType( xData ) == "H" .OR. ValType( xData ) == "A"    ; ::cBody := hb_jsonEncode( xData )
   CASE ValType( xData ) == "N"                                  ; ::cBody := hb_NToS( xData )
   CASE ValType( xData ) == "L"                                  ; ::cBody := iif( xData, "true", "false" )
   OTHERWISE                                                       ; ::cBody := ""
   ENDCASE
RETURN Self

METHOD Header( cKey, xDef ) CLASS TMockRequest
   LOCAL cLow := Lower( AllTrim( cKey ) )
   hb_default( @xDef, "" )
   IF hb_HHasKey( ::hHeaders, cLow ) ; RETURN ::hHeaders[ cLow ] ; ENDIF
RETURN xDef

METHOD QueryParam( cKey, xDef ) CLASS TMockRequest
   hb_default( @xDef, "" )
   IF hb_HHasKey( ::hQueryParams, cKey ) ; RETURN ::hQueryParams[ cKey ] ; ENDIF
RETURN xDef

METHOD Cookie( cName, xDef ) CLASS TMockRequest
   LOCAL cRaw, aPairs, cPair, nEq
   hb_default( @xDef, "" )
   IF ::hCookies == NIL
      ::hCookies := {=>}
      cRaw := ::Header( "cookie", "" )
      IF ! Empty( cRaw )
         aPairs := hb_ATokens( cRaw, ";" )
         FOR EACH cPair IN aPairs
            cPair := AllTrim( cPair )
            nEq   := At( "=", cPair )
            IF nEq > 0
               ::hCookies[ AllTrim( Left( cPair, nEq - 1 ) ) ] := AllTrim( SubStr( cPair, nEq + 1 ) )
            ENDIF
         NEXT
      ENDIF
   ENDIF
RETURN hb_HGetDef( ::hCookies, cName, xDef )

METHOD FormBody() CLASS TMockRequest
RETURN iif( ::hFormBody != NIL, ::hFormBody, {=>} )

METHOD IsJson() CLASS TMockRequest
RETURN "application/json" $ Lower( ::Header( "content-type", "" ) ) .OR. ::xJsonBody != NIL

METHOD IsForm() CLASS TMockRequest
RETURN "application/x-www-form-urlencoded" $ Lower( ::Header( "content-type", "" ) )

METHOD ReadBody() CLASS TMockRequest
RETURN ::cBody

METHOD JsonBody() CLASS TMockRequest
   LOCAL h := NIL
   IF ! Empty( ::cRawBody )
      hb_jsonDecode( ::cRawBody, @h )
   ELSEIF ::xJsonBody != NIL
      h := ::xJsonBody
   ENDIF
RETURN h

METHOD QueryParamsAll() CLASS TMockRequest
RETURN iif( ::hQueryParams != NIL, ::hQueryParams, {=>} )

METHOD Redirect( cUrl ) CLASS TMockRequest
   ::nStatus    := 302
   ::lResponded := .T.
   ::cBody      := cUrl
RETURN Self

// -------------------------------------------------------
// Shared test helpers — used by all integrated test files
// -------------------------------------------------------
PROCEDURE HixTU_Pass( hCtx, cTest, cExp, cGot )
   LOCAL nNow, nMs
   hb_default( @cExp, "" )
   hb_default( @cGot, "" )
   nNow := hb_MilliSeconds()
   nMs  := iif( hb_HHasKey( hCtx, "_tPrev" ), nNow - hCtx[ "_tPrev" ], 0 )
   hCtx[ "_tPrev" ] := nNow
   hCtx[ "total"  ]++ ; hCtx[ "passed" ]++
   AAdd( hCtx[ "results" ], { "status" => "pass", "name" => cTest, "msg" => "", "exp" => cExp, "got" => cGot, "ms" => nMs } )
RETURN

PROCEDURE HixTU_Fail( hCtx, cTest, cExp, cGot )
   LOCAL nNow, nMs
   nNow := hb_MilliSeconds()
   nMs  := iif( hb_HHasKey( hCtx, "_tPrev" ), nNow - hCtx[ "_tPrev" ], 0 )
   hCtx[ "_tPrev" ] := nNow
   hCtx[ "total"  ]++ ; hCtx[ "failed" ]++
   AAdd( hCtx[ "results" ], { "status" => "fail", "name" => cTest, ;
         "msg" => "Expected: " + cExp + "  Got: " + cGot, "exp" => cExp, "got" => cGot, "ms" => nMs } )
RETURN

PROCEDURE HixTU_Check( hCtx, lCond, cTest, cExp, cGot )
   IF lCond ; HixTU_Pass( hCtx, cTest, cExp, cGot ) ; ELSE ; HixTU_Fail( hCtx, cTest, cExp, cGot ) ; ENDIF
RETURN

// -------------------------------------------------------
// Peer server helpers — HTTP real sobre TCP a puerto 8100
// -------------------------------------------------------

// Devuelve el puerto del peer server (lee de app.prg vía HIX_TestPeer_Port)
FUNCTION HixTU_PeerPort()
RETURN HIX_TestPeer_Port()

// Envía cRaw por TCP al peer y devuelve la respuesta HTTP completa (headers+body).
// Usa HTTP/1.0 + Connection: close: el server cierra tras responder → recv termina solo.
FUNCTION HixTU_PeerSend( cRaw )
   LOCAL oSock, cBuf, nRead, cResp, nTimeout

   oSock := hb_socketOpen()
   IF ! hb_socketConnect( oSock, { HB_SOCKET_AF_INET, "127.0.0.1", HixTU_PeerPort() }, 3000 )
      hb_socketClose( oSock )
      RETURN ""
   ENDIF

   hb_socketSend( oSock, cRaw, Len( cRaw ), 0, 3000 )

   cResp    := ""
   nTimeout := 3000
   DO WHILE .T.
      cBuf  := Space( 8192 )
      nRead := hb_socketRecv( oSock, @cBuf, 8192, 0, nTimeout )
      IF nRead <= 0 ; EXIT ; ENDIF
      cResp    += Left( cBuf, nRead )
      nTimeout := 500
   ENDDO

   hb_socketClose( oSock )
RETURN cResp

// GET /path — construye la petición y llama PeerSend
FUNCTION HixTU_PeerGet( cPath )
   LOCAL cReq
   cReq  := "GET " + cPath + " HTTP/1.0" + PEER_CRLF
   cReq  += "Host: 127.0.0.1" + PEER_CRLF
   cReq  += "Connection: close" + PEER_CRLF
   cReq  += PEER_CRLF
RETURN HixTU_PeerSend( cReq )

// POST /path con body — Content-Type por defecto: application/x-www-form-urlencoded
FUNCTION HixTU_PeerPost( cPath, cBody, cCT )
   LOCAL cReq
   hb_default( @cBody, "" )
   hb_default( @cCT,   "application/x-www-form-urlencoded" )
   cReq  := "POST " + cPath + " HTTP/1.0" + PEER_CRLF
   cReq  += "Host: 127.0.0.1" + PEER_CRLF
   cReq  += "Content-Type: " + cCT + PEER_CRLF
   cReq  += "Content-Length: " + hb_NToS( Len( cBody ) ) + PEER_CRLF
   cReq  += "Connection: close" + PEER_CRLF
   cReq  += PEER_CRLF
   cReq  += cBody
RETURN HixTU_PeerSend( cReq )

// Extrae el cuerpo de la respuesta HTTP (tras los headers)
FUNCTION HixTU_PeerBody( cResp )
   LOCAL n := At( PEER_CRLF + PEER_CRLF, cResp )
   IF n > 0 ; RETURN SubStr( cResp, n + 4 ) ; ENDIF
RETURN ""

// Extrae el código de estado HTTP (primera línea: "HTTP/x.x NNN ...")
FUNCTION HixTU_PeerStatus( cResp )
   LOCAL n := At( " ", cResp )
   IF n > 0 ; RETURN Val( SubStr( cResp, n + 1, 3 ) ) ; ENDIF
RETURN 0
