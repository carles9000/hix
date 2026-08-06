/*-----------------------------------------------------------
  File ......: logout.prg
  Author.....: Charly 9000
  Created....: 2026-05-24
  Modified...: 2026-05-24
  Version....: 1.0.0
  Description: Logout controller — destroys the session and
               redirects to /login.
  Usage      : GET /logout
 -----------------------------------------------------------*/

#include "hbclass.ch"

PROCEDURE Main(...)

   LOCAL oSess := USession()

   oSess:Destroy()

   URedirect( URoute( 'sys.login' ) )     // => /login 

RETURN
