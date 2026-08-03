/*-----------------------------------------------------------
  File ......: health.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 1.0.0
  Description: GET /health -- liveness/readiness probe.
               Returns basic service status without touching
               any protected resource. Anonymous access.
  Usage      : GET /health
 -----------------------------------------------------------*/


FUNCTION Main()

   USendApi( { ;
      "status"  => "ok", ;
      "service" => "fenix.ws.lite", ;
      "version" => "1.0.0" ;
   } )

RETURN NIL
