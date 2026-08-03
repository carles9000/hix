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
               Route action: controllers/index@health.prg
 -----------------------------------------------------------*/

#include "hbclass.ch"

CLASS HealthController

   METHOD New()   CONSTRUCTOR
   METHOD End()
   METHOD Index()

ENDCLASS


METHOD New() CLASS HealthController
RETURN SELF


METHOD End() CLASS HealthController
RETURN SELF


METHOD Index() CLASS HealthController

   USendApi( { ;
      "status"  => "ok", ;
      "service" => "fenix.ws.class", ;
      "version" => "1.0.0" ;
   } )

RETURN NIL
