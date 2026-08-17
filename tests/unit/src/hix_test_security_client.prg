/*-----------------------------------------------------------
  File ......: hix_test_security_client.prg
  Author.....: Charly 9000
  Created....: 2026-07-16
  Description: Minimal HTTP client for the pentest battery.
               Sends raw HTTP/1.0 requests over hb_socket*
               and returns a parsed response hash:
                  { "status", "headers" (lowercase keys),
                    "body", "raw", "error" }
  Notes      : Pure Harbour, no external dependencies.
               Uses HTTP/1.0 + Connection: close so the
               server closes after responding.
 -----------------------------------------------------------*/
#include "hbsocket.ch"

#define TS_CRLF   ( Chr( 13 ) + Chr( 10 ) )
#define TS_HOST   "127.0.0.1"

// -------------------------------------------------------
// HixTS_Get( nPort, cPath, hHeaders ) -> hash respuesta
// -------------------------------------------------------
FUNCTION HixTS_Get( nPort, cPath, hHeaders )
   LOCAL cReq
   hb_default( @hHeaders, { => } )
   cReq := "GET " + cPath + " HTTP/1.0" + TS_CRLF
   cReq += _TsBuildHeaders( hHeaders )
   cReq += TS_CRLF
RETURN HixTS_Raw( nPort, cReq )

// -------------------------------------------------------
// HixTS_Post( nPort, cPath, cBody, cContentType, hHeaders )
// -------------------------------------------------------
FUNCTION HixTS_Post( nPort, cPath, cBody, cContentType, hHeaders )
   LOCAL cReq, hHdr
   hb_default( @cBody,         "" )
   hb_default( @cContentType,  "application/x-www-form-urlencoded" )
   hb_default( @hHeaders,      { => } )
   hHdr := hb_HClone( hHeaders )
   hHdr[ "Content-Type"   ] := cContentType
   hHdr[ "Content-Length" ] := hb_NToS( Len( cBody ) )
   cReq := "POST " + cPath + " HTTP/1.0" + TS_CRLF
   cReq += _TsBuildHeaders( hHdr )
   cReq += TS_CRLF
   cReq += cBody
RETURN HixTS_Raw( nPort, cReq )

// -------------------------------------------------------
// HixTS_Custom( nPort, cMethod, cPath, hHeaders )
// -------------------------------------------------------
FUNCTION HixTS_Custom( nPort, cMethod, cPath, hHeaders )
   LOCAL cReq
   hb_default( @hHeaders, { => } )
   cReq := cMethod + " " + cPath + " HTTP/1.0" + TS_CRLF
   cReq += _TsBuildHeaders( hHeaders )
   cReq += TS_CRLF
RETURN HixTS_Raw( nPort, cReq )

// -------------------------------------------------------
// HixTS_Raw( nPort, cRawRequest, nTimeoutMs ) -> hash respuesta
// -------------------------------------------------------
FUNCTION HixTS_Raw( nPort, cRawRequest, nTimeoutMs )
   LOCAL oSock, cBuf, nRead, cResp, nRecvTo, hResp

   hb_default( @nTimeoutMs, 3000 )

   hResp := { "status" => 0, "headers" => { => }, "body" => "", ;
              "raw" => "", "error" => NIL }

   oSock := hb_socketOpen()
   IF oSock == NIL
      hResp[ "error" ] := "socket open failed"
      RETURN hResp
   ENDIF

   IF ! hb_socketConnect( oSock, { HB_SOCKET_AF_INET, TS_HOST, nPort }, nTimeoutMs )
      hResp[ "error" ] := "connect failed to " + TS_HOST + ":" + hb_NToS( nPort )
      hb_socketClose( oSock )
      RETURN hResp
   ENDIF

   IF hb_socketSend( oSock, cRawRequest, Len( cRawRequest ), 0, nTimeoutMs ) < 0
      hResp[ "error" ] := "send failed"
      hb_socketClose( oSock )
      RETURN hResp
   ENDIF

   cResp   := ""
   nRecvTo := nTimeoutMs

   DO WHILE .T.
      cBuf  := Space( 8192 )
      nRead := hb_socketRecv( oSock, @cBuf, 8192, 0, nRecvTo )
      IF nRead <= 0 ; EXIT ; ENDIF
      cResp    += Left( cBuf, nRead )
      nRecvTo  := 500
   ENDDO

   hb_socketClose( oSock )

   IF Empty( cResp )
      hResp[ "error" ] := "empty response (timeout or reset)"
      RETURN hResp
   ENDIF

   _TsParseResponse( cResp, hResp )
RETURN hResp

// -------------------------------------------------------
// HixTS_Header( hResp, cKey, xDef ) -> case-insensitive lookup
// -------------------------------------------------------
FUNCTION HixTS_Header( hResp, cKey, xDef )
   LOCAL cLow
   hb_default( @xDef, "" )
   IF hResp == NIL .OR. ! hb_HHasKey( hResp, "headers" ) ; RETURN xDef ; ENDIF
   cLow := Lower( cKey )
   IF hb_HHasKey( hResp[ "headers" ], cLow ) ; RETURN hResp[ "headers" ][ cLow ] ; ENDIF
RETURN xDef

// -------------------------------------------------------
// HixTS_HasHeader( hResp, cKey ) -> .T./.F.
// -------------------------------------------------------
FUNCTION HixTS_HasHeader( hResp, cKey )
   IF hResp == NIL .OR. ! hb_HHasKey( hResp, "headers" ) ; RETURN .F. ; ENDIF
RETURN hb_HHasKey( hResp[ "headers" ], Lower( cKey ) )

// -------------------------------------------------------
// HixTS_WaitReady( nPort, nMaxSecs ) -> .T. si /ping responde antes de nMax
// -------------------------------------------------------
FUNCTION HixTS_WaitReady( nPort, cPath, nMaxSecs )
   LOCAL nEnd, hResp
   hb_default( @cPath,   "/ping" )
   hb_default( @nMaxSecs, 5 )
   nEnd := Seconds() + nMaxSecs
   DO WHILE Seconds() < nEnd
      hResp := HixTS_Get( nPort, cPath, NIL )
      IF hResp[ "error" ] == NIL .AND. hResp[ "status" ] > 0
         RETURN .T.
      ENDIF
      hb_idleSleep( 0.1 )
   ENDDO
RETURN .F.

// -------------------------------------------------------
// _TsBuildHeaders( hHeaders ) -> string con Host obligatorio
// -------------------------------------------------------
STATIC FUNCTION _TsBuildHeaders( hHeaders )
   LOCAL cOut := "", cKey, lHasHost := .F., lHasConn := .F.

   IF hHeaders != NIL
      FOR EACH cKey IN hb_HKeys( hHeaders )
         cOut += cKey + ": " + hb_CStr( hHeaders[ cKey ] ) + TS_CRLF
         IF Lower( cKey ) == "host"       ; lHasHost := .T. ; ENDIF
         IF Lower( cKey ) == "connection" ; lHasConn := .T. ; ENDIF
      NEXT
   ENDIF

   IF ! lHasHost
      cOut += "Host: " + TS_HOST + TS_CRLF
   ENDIF
   IF ! lHasConn
      cOut += "Connection: close" + TS_CRLF
   ENDIF
RETURN cOut

// -------------------------------------------------------
// _TsParseResponse( cResp, hResp ) — llena status, headers, body
// -------------------------------------------------------
STATIC PROCEDURE _TsParseResponse( cResp, hResp )
   LOCAL nSep, cHead, cBody, aLines, cLine, nSp, nColon, cKey, cVal, i

   hResp[ "raw" ] := cResp
   nSep := At( TS_CRLF + TS_CRLF, cResp )

   IF nSep == 0
      cHead := cResp
      cBody := ""
   ELSE
      cHead := Left( cResp, nSep - 1 )
      cBody := SubStr( cResp, nSep + 4 )
   ENDIF

   aLines := hb_ATokens( cHead, TS_CRLF )
   IF Len( aLines ) == 0 ; RETURN ; ENDIF

   // Status line "HTTP/x.x NNN Message"
   cLine := aLines[ 1 ]
   nSp   := At( " ", cLine )
   IF nSp > 0
      hResp[ "status" ] := Val( SubStr( cLine, nSp + 1, 3 ) )
   ENDIF

   FOR i := 2 TO Len( aLines )
      cLine  := aLines[ i ]
      nColon := At( ":", cLine )
      IF nColon > 0
         cKey := Lower( AllTrim( Left( cLine, nColon - 1 ) ) )
         cVal := AllTrim( SubStr( cLine, nColon + 1 ) )
         hResp[ "headers" ][ cKey ] := cVal
      ENDIF
   NEXT

   hResp[ "body" ] := cBody
RETURN
