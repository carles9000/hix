/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: HIX Web Server main entry point                
 -----------------------------------------------------------*/
 
// Force to link all functions ---------------------
   #define __HBEXTERN__HIX_SERVER__REQUEST
   #include "../hix_server.hbx"

   #define __HBEXTERN__HARBOUR__REQUEST
   #include "harbour.hbx"
// ------------------------------------------------

REQUEST DBFCDX 

FUNCTION Main()

   LOCAL oServer := THixServer():New()
   
      RddSetDefault( 'DBFCDX' )

   oServer:Start()
   
RETURN NIL