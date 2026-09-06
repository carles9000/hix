/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: HIX Web Server main entry point                
 -----------------------------------------------------------*/

REQUEST DBFCDX

FUNCTION Main()

   LOCAL oServer := THixServer():New()

   RddSetDefault( 'DBFCDX' )

   oServer:Start()

RETURN NIL