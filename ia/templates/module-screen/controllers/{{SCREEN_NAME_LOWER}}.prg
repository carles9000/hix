/*-----------------------------------------------------------
  File ......: {{SCREEN_NAME_LOWER}}.prg
  Author.....: {{AUTHOR}}
  Created....: {{DATE}}
  Version....: 1.0.0
  Description: {{SCREEN_NAME}} screen controller. Renders
               view {{SCREEN_NAME_LOWER}}.view.html for
               GET {{SCREEN_URL}}.
 -----------------------------------------------------------*/

#include "hbclass.ch"

CLASS {{SCREEN_NAME}}

   METHOD New()   CONSTRUCTOR
   METHOD End()

   METHOD Index()

ENDCLASS

METHOD New() CLASS {{SCREEN_NAME}}
RETURN Self

METHOD End() CLASS {{SCREEN_NAME}}
RETURN Self

METHOD Index() CLASS {{SCREEN_NAME}}
RETURN USendView( "{{SCREEN_NAME_LOWER}}.view.html", "{{SCREEN_TITLE}}" )
