/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 1.0.0
  Description: Fenix.WS.Class -- same REST API as Fenix.WS.Lite
               but controllers are class-based. Routes use the
               method@class.prg syntax supported by HIX dispatcher.
  Usage      : go.bat -> compile + launch on port 8083
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