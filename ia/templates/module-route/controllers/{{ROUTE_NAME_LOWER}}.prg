/*-----------------------------------------------------------
  File ......: {{ROUTE_NAME_LOWER}}.prg
  Author.....: {{AUTHOR}}
  Created....: {{DATE}}
  Version....: 1.0.0
  Description: {{ROUTE_NAME}} controller. Single-action CLASS
               wired to route {{ROUTE_METHOD}} {{ROUTE_URL}}
               via "controllers/index@{{ROUTE_NAME_LOWER}}.prg".
 -----------------------------------------------------------*/

#include "hbclass.ch"

CLASS {{ROUTE_NAME}}

   METHOD New()   CONSTRUCTOR
   METHOD End()

   METHOD Index()

ENDCLASS

METHOD New() CLASS {{ROUTE_NAME}}
RETURN Self

METHOD End() CLASS {{ROUTE_NAME}}
RETURN Self

METHOD Index() CLASS {{ROUTE_NAME}}
RETURN USendJson( { ;
   "ok"     => .T., ;
   "route"  => "{{ROUTE_NAME_LOWER}}", ;
   "method" => "{{ROUTE_METHOD}}",     ;
   "url"    => "{{ROUTE_URL}}"         ;
} )
