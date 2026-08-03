/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 1.0.0
  Description: Fenix.WS.Class -- same REST API as Fenix.WS.Lite
               but controllers are class-based. Routes use the
               method@class.prg syntax supported by HIX dispatcher.
  Usage      : go.bat -> compile + launch on port 8083
 -----------------------------------------------------------*/

#include "hbclass.ch"

PROCEDURE Main()

   LOCAL oServer

   oServer := THixServer():New()

   oServer:Start()

RETURN
