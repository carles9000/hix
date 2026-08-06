/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: Charly 9000
  Created....: 2026-05-24
  Modified...: 2026-05-24
  Version....: 1.0.0
  Description: Fenix web app — session-based auth example.
               /main is protected: redirects to /login if not
               authenticated. Login redirects back to /main.
  Usage      : go.bat -> compiles and starts server on port 80
               Credentials: admin/admin123  carles/1234
 -----------------------------------------------------------*/

#include "hbclass.ch"

FUNCTION Main()

   LOCAL oServer := THixServer():New()   
      
      
   // In HIXSTYLE mode, the root folder is protected.
   // Our application test is located within the /test folder, 
   // and we need to enable it to be run directly from our 
   // browser: http://localhost/test/index.html
   
      oServer:AllowDir( "test", .F. )  


   oServer:Start()

RETURN NIL 