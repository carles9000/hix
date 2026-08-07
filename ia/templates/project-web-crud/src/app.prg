/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: {{AUTHOR}}
  Created....: {{DATE}}
  Version....: 1.0.0
  Description: {{PROJECT_NAME}} -- HIX web app entry point.
               Runs in hixstyle mode: routes, middleware and
               loaders are loaded from www/ JSON files.
  Usage      : go.bat         compiles and starts the server
               go.bat build   compiles only (used by tests)
 -----------------------------------------------------------*/

#include "hbclass.ch"

FUNCTION Main()

   LOCAL oServer := THixServer():New()

   oServer:Start()

   IF oServer:hThread != NIL
      hb_threadJoin( oServer:hThread )
   ENDIF

RETURN NIL
