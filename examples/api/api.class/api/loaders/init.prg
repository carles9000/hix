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

   _t( 'My init process...' )   
   _t( HIX_BootLog() )           // Check DbgView

    
   // ModelRefreshInit -- create the token pool at startup (single thread).

      ModelRefreshInit()
   
   /*
      We are creating a web service and basing the responses on JSON.
      With this configuration, we force the server to send a JSON response 
      instead of an HTML error if it should respond with a 404 or 405 error.

      In the case of a 404 error, if the main path is '/', we will simply 
      display an "OK" message in JSON.         
   */      
   
   HIX_RouteSetHandler( "405", {| oReq, cAllowed | ;
      USendJson( { "error" => "method_not_allowed", "allow" => cAllowed }, 405 ) } )
   
   HIX_RouteSetHandler( "404", {| oReq | ;
      iif( oReq:cPath == "/", ;
           USendJson( { "name" => 'HIX ' + HIX_Version(), "status" => "ok", "now" => dtoc(date()) + ' ' + time() }, 200 ), ;
           USendJson( { "error" => "not_found", "path" => oReq:cPath }, 404 ) ) }  )

RETURN NIL


#include '/models/modeluser.prg'
#include '/models/modelrefresh.prg'
