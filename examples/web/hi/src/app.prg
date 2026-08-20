/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: Charly 9000
  Created....: 2026-05-24
  Modified...: 2026-08-18
  Version....: 1.1.0
  Description: Fenix web app — session-based auth example.
               /main is protected: redirects to /login if not
               authenticated. Login redirects back to /main.
               WebSocket echo handler for the /ws-test screen.
  Usage      : go.bat -> compiles and starts server on port 80
               Credentials: admin/admin123  carles/1234
 -----------------------------------------------------------*/

#include "hbclass.ch"

FUNCTION Main()

   LOCAL oServer := THixServer():New()

   oServer:bOnWsMessage := {| oConn, cMsg, nOpcode | _WsPing( oConn, cMsg, nOpcode ) }

   oServer:Start()

RETURN NIL

/*-----------------------------------------------------------
  Answers every text frame with { 200, hb_MilliSeconds() }.
  Used by the /ws-test screen to measure round trip time.
 -----------------------------------------------------------*/

STATIC FUNCTION _WsPing( oConn, cMsg, nOpcode )

   HB_SYMBOL_UNUSED( cMsg )

   IF nOpcode == 1
      oConn:Send( hb_jsonEncode( { right( ltrim(str(hb_MilliSeconds())), 5 ) } ) )
   ENDIF

RETURN NIL 