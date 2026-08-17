/*-----------------------------------------------------------
  File ......: hix_test_websocket.prg
  Author.....: Charly 9000
  Created....: 2026-06-06
  Description: Integrated test — WebSocket frame encoding via
               THixWsConn (Send/SendBinary/Close) + callbacks.
               Inspects raw bytes written to TMockIO.
 -----------------------------------------------------------*/
#include "fileio.ch"
#include "hix_const.ch"

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[WebSocket] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

FUNCTION HIX_TestWebSocket_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TLog( "=== HIX_TestWebSocket_Run start ===" )
   _WsConn(         hCtx )
   _WsTextFrame(    hCtx )
   _WsBinFrame(     hCtx )
   _WsClose(        hCtx )
   _WsCallbacks(    hCtx )
   _WsFrameOpcodes( hCtx )
   _TLog( "=== HIX_TestWebSocket_Run end ===" )
RETURN hCtx

STATIC PROCEDURE _WsConn( hCtx )
   LOCAL oIO, oConn
   _TLog( "_WsConn" )
   oIO   := TMockIO():New( "", "" )
   oConn := THixWsConn():New( oIO, "1.2.3.4" )
   _TLog( "cIP=" + oConn:cIP + " lClosed=" + hb_ValToStr( oConn:lClosed ) )
   HixTU_Check( hCtx, oConn:cIP    == "1.2.3.4", "WS: New -> cIP correcto",    "1.2.3.4", oConn:cIP )
   HixTU_Check( hCtx, oConn:lClosed == .F.,       "WS: New -> lClosed=.F.",    ".F.",      iif( oConn:lClosed, ".T.", ".F." ) )
RETURN

STATIC PROCEDURE _WsTextFrame( hCtx )
   LOCAL oIO, oConn, cW, nByte1, nByte2
   _TLog( "_WsTextFrame" )
   oIO   := TMockIO():New( "", "" )
   oConn := THixWsConn():New( oIO, "127.0.0.1" )
   oConn:Send( "hello" )
   cW := oIO:cWritten
   _TLog( "Written len=" + hb_NToS( Len( cW ) ) + " bytes" )
   // Frame text: byte1=0x81 (FIN+TEXT), byte2=len, payload
   nByte1 := Asc( SubStr( cW, 1, 1 ) )
   nByte2 := Asc( SubStr( cW, 2, 1 ) )
   _TLog( "byte1=0x" + hb_NumToHex( nByte1 ) + " byte2=" + hb_NToS( nByte2 ) )
   HixTU_Check( hCtx, nByte1 == 0x81,                    "WS: Text frame byte1 = 0x81 (FIN+TEXT)", "0x81", "0x" + hb_NumToHex( nByte1 ) )
   HixTU_Check( hCtx, nByte2 == 5,                       "WS: Text frame byte2 = len(hello)=5",    "5",    hb_NToS( nByte2 ) )
   HixTU_Check( hCtx, SubStr( cW, 3, 5 ) == "hello",     "WS: Text payload = 'hello'",             "hello", SubStr( cW, 3, 5 ) )
RETURN

STATIC PROCEDURE _WsBinFrame( hCtx )
   LOCAL oIO, oConn, cW, nByte1
   _TLog( "_WsBinFrame" )
   oIO   := TMockIO():New( "", "" )
   oConn := THixWsConn():New( oIO, "127.0.0.1" )
   oConn:SendBinary( "bin" )
   cW    := oIO:cWritten
   nByte1 := Asc( SubStr( cW, 1, 1 ) )
   _TLog( "Binary byte1=0x" + hb_NumToHex( nByte1 ) )
   HixTU_Check( hCtx, nByte1 == 0x82,                "WS: Binary frame byte1 = 0x82 (FIN+BINARY)", "0x82", "0x" + hb_NumToHex( nByte1 ) )
   HixTU_Check( hCtx, SubStr( cW, 3, 3 ) == "bin",   "WS: Binary payload = 'bin'",                 "bin",  SubStr( cW, 3, 3 ) )
RETURN

STATIC PROCEDURE _WsClose( hCtx )
   LOCAL oIO, oConn, cBefore
   _TLog( "_WsClose" )
   oIO   := TMockIO():New( "", "" )
   oConn := THixWsConn():New( oIO, "127.0.0.1" )
   oConn:Close()
   _TLog( "lClosed=" + hb_ValToStr( oConn:lClosed ) )
   HixTU_Check( hCtx, oConn:lClosed, "WS: Close -> lClosed=.T.", ".T.", ".F." )
   // Send tras Close -> no escribe
   cBefore := oIO:cWritten
   oConn:Send( "after-close" )
   HixTU_Check( hCtx, oIO:cWritten == cBefore, "WS: Send tras Close no escribe", "sin cambio", iif( oIO:cWritten == cBefore, "ok", "cambio" ) )
RETURN

STATIC PROCEDURE _WsCallbacks( hCtx )
   LOCAL oError
   _TLog( "_WsCallbacks" )
   TRY
      HIX_WsSetCallbacks( {|| NIL }, {|| NIL }, {|| NIL } )
      HixTU_Check( hCtx, .T., "WS: SetCallbacks no crash", "ok", "ok" )
   CATCH oError
      _TLog( "SetCallbacks error: " + oError:description )
      HixTU_Check( hCtx, .F., "WS: SetCallbacks no crash", "ok", oError:description )
   END
RETURN

STATIC PROCEDURE _WsFrameOpcodes( hCtx )
   LOCAL cFrame, nByte1, nByte2, cPayload, i
   _TLog( "_WsFrameOpcodes" )

   // CLOSE = 0x08 → byte1 must be 0x88 (FIN+CLOSE), NOT 0x89 (PING)
   cFrame := HIX_WsBuildFrame( 0x08, "" )
   nByte1 := Asc( SubStr( cFrame, 1, 1 ) )
   nByte2 := Asc( SubStr( cFrame, 2, 1 ) )
   _TLog( "CLOSE: byte1=0x" + hb_NumToHex( nByte1 ) + " len=" + hb_NToS( nByte2 ) )
   HixTU_Check( hCtx, nByte1 == 0x88, "WS: CLOSE frame byte1 = 0x88 (FIN+CLOSE)", "0x88", "0x" + hb_NumToHex( nByte1 ) )
   HixTU_Check( hCtx, nByte2 == 0,    "WS: CLOSE frame len = 0",                  "0",    hb_NToS( nByte2 ) )

   // PING = 0x09 → byte1 = 0x89
   cFrame := HIX_WsBuildFrame( 0x09, "" )
   nByte1 := Asc( SubStr( cFrame, 1, 1 ) )
   _TLog( "PING: byte1=0x" + hb_NumToHex( nByte1 ) )
   HixTU_Check( hCtx, nByte1 == 0x89, "WS: PING frame byte1 = 0x89 (FIN+PING)", "0x89", "0x" + hb_NumToHex( nByte1 ) )

   // PONG = 0x0A → byte1 = 0x8A, payload encoded
   cFrame := HIX_WsBuildFrame( 0x0A, "ping-data" )
   nByte1 := Asc( SubStr( cFrame, 1, 1 ) )
   nByte2 := Asc( SubStr( cFrame, 2, 1 ) )
   _TLog( "PONG: byte1=0x" + hb_NumToHex( nByte1 ) + " len=" + hb_NToS( nByte2 ) )
   HixTU_Check( hCtx, nByte1 == 0x8A, "WS: PONG frame byte1 = 0x8A (FIN+PONG)", "0x8A", "0x" + hb_NumToHex( nByte1 ) )
   HixTU_Check( hCtx, nByte2 == 9,    "WS: PONG payload len = 9",                "9",    hb_NToS( nByte2 ) )

   // Large payload (130 bytes) → byte2 = 126 + 2 ext bytes
   cPayload := ""
   FOR i := 1 TO 130
      cPayload += "A"
   NEXT
   cFrame := HIX_WsBuildFrame( 0x02, cPayload )
   nByte1 := Asc( SubStr( cFrame, 1, 1 ) )
   nByte2 := Asc( SubStr( cFrame, 2, 1 ) )
   _TLog( "Large: byte1=0x" + hb_NumToHex( nByte1 ) + " byte2=" + hb_NToS( nByte2 ) )
   HixTU_Check( hCtx, nByte1 == 0x82, "WS: Large frame byte1 = 0x82 (FIN+BINARY)", "0x82", "0x" + hb_NumToHex( nByte1 ) )
   HixTU_Check( hCtx, nByte2 == 126,  "WS: Large frame byte2 = 126 (ext len)",      "126",  hb_NToS( nByte2 ) )
RETURN
