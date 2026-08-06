/*-----------------------------------------------------------
  File ......: login.prg
  Author.....: Charly 9000
  Created....: 2026-05-26
  Modified...: 2026-05-26
  Version....: 1.0.0
  Description: GET /login controller — loads session, reads flash
               error and username set by auth.prg on failed login.
  Usage      : GET /login
 -----------------------------------------------------------*/

FUNCTION Main()
   LOCAL oFlash
   LOCAL cError
   LOCAL cUser

   oFlash := UFlash( "login" )
   cError := oFlash:Get( "error" )
   cUser  := oFlash:Get( "user"  )
   oFlash:Save()

   IF Empty( cError )
      oFlash := UFlash( "csrf" )
      cError := oFlash:Get( "error" )
      oFlash:Save()
   ENDIF

return UView( "sys/login.html", cUser, cError )



