/*-----------------------------------------------------------
  File ......: health.prg
  Author.....: {{AUTHOR}}
  Created....: {{DATE}}
  Modified...: {{DATE}}
  Version....: 1.0.0
  Description: Health endpoint. Returns liveness JSON. Used by
               the /hix-init verifier and by external monitors.
  Usage      : GET /health -> { "ok": true, "name": "{{PROJECT_NAME}}" }
  Notes      : No dependencies. Safe to keep in production.
 -----------------------------------------------------------*/

PROCEDURE Main( ... )

   USendJson( { ;
      "ok"   => .T., ;
      "name" => "{{PROJECT_NAME}}" ;
   } )

RETURN
