/*-----------------------------------------------------------
  File ......: init.prg
  Author.....: Charly 9000
  Created....: 2026-07-19
  Modified...: 2026-07-21
  Version....: 1.1.0
  Description: Fenix.WS.Lite boot hook. Installs custom 404/405
               router handlers so the fallback stays inside the
               { error, meta } envelope contract.
  Notes      : No user provisioning here -- the fake model in
               modeluser.prg holds the store in memory.
 -----------------------------------------------------------*/


FUNCTION UserInit()

   _d( 'Ep!!!' )
   _d(  HIX_BootLog() )

   ModelTokenInit()

   HIX_RouteSetHandler( "405", {| oReq, cAllowed | ;
      USendJson( { "error" => "method_not_allowed", "allow" => cAllowed }, 405 ) } )

   HIX_RouteSetHandler( "404", {| oReq | ;
      USendJson( { "error" => "not_found", "path" => oReq:cPath }, 404 ) } )

RETURN NIL


#include '/models/modeluser.prg'
#include '/models/modeltoken.prg'
