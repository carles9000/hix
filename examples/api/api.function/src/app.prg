/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: Charly 9000
  Created....: 2026-07-19
  Modified...: 2026-07-19
  Version....: 1.0.0
  Description: Fenix.WS.Lite -- minimal REST API example over
               HIX. Four endpoints: /time (public), /login,
               /logout (auth), /customer/:id (auth). Stateless
               Bearer JWT. No refresh, no scope, no audit.
  Usage      : go.bat -> compile + launch on port 8082
 -----------------------------------------------------------*/

#include "hbclass.ch"


PROCEDURE Main()

   LOCAL oServer

   oServer := THixServer():New()

   oServer:Start()

   DO WHILE oServer:lRunning
      IF Inkey( 1 ) == 27
         EXIT
      ENDIF
   ENDDO

   oServer:Stop()

RETURN
