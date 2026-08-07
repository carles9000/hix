/*-----------------------------------------------------------
  File ......: {{MIDDLEWARE_NAME_LOWER}}_probe.prg
  Author.....: {{AUTHOR}}
  Created....: {{DATE}}
  Version....: 1.0.0
  Description: Probe controller for middleware HixMw{{MIDDLEWARE_NAME}}.
               Only runs when the middleware lets the request through.
 -----------------------------------------------------------*/

#include "hbclass.ch"

CLASS {{MIDDLEWARE_NAME}}Probe

   METHOD New()   CONSTRUCTOR
   METHOD End()

   METHOD Index()

ENDCLASS

METHOD New() CLASS {{MIDDLEWARE_NAME}}Probe
RETURN Self

METHOD End() CLASS {{MIDDLEWARE_NAME}}Probe
RETURN Self

METHOD Index() CLASS {{MIDDLEWARE_NAME}}Probe
RETURN USendJson( { ;
   "ok"         => .T., ;
   "middleware" => "HixMw{{MIDDLEWARE_NAME}}" ;
} )
