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

   LOCAL oServer := THixServer():New()
   
      // In HIXSTYLE mode, the root folder is protected.
      // Our application test is located within the /test folder,
      // and we need to enable it to be run directly from our
      // browser: http://localhost/test/index.html
      
         oServer:AllowDir( "test", .F. )
         
      // ---------------------------------------------------------   

   oServer:Start()

RETURN

