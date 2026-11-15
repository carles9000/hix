/*-----------------------------------------------------------
  File ......: app.prg
  Author.....: Charly 9000
  Created....: 2026-05-24
  Modified...: 2026-09-29
  Version....: 1.2.0
  Description: WDO - Web Database Objects. 
  Usage      : go_msvc64.bat && app.exe
  Notes      : Pool config lives in www/config.json under the
               "databases" section. HIX_InitPoolsFromConfig()
               reads it and levants every declared pool. To go
               back to the legacy programmatic form, see the
               commented block below.
 -----------------------------------------------------------*/

#include "hbclass.ch"
#include "hix_logger.ch"

FUNCTION Main()

   LOCAL oServer := THixServer():New()

   // Load www/config.json into HIX_ConfigApp so HIX_InitPoolsFromConfig
   // can read the "databases" section. hixstyle=false so we call it
   // explicitly; hixstyle=true would do it during oServer:Start().
   
      HIX_ConfigAppLoad( "www/config.json" )

   // Read "databases" and levant every declared pool. Each entry:
   
      HIX_InitPoolsFromConfig()         

   oServer:Start()

   HIX_EndPoolsFromConfig()

RETURN NIL


//  ---------------------------------------------------------------
//  Pool-wide error handler -- TEMPLATE for custom logic.
//
//  The lib ships `WDO_DefaultErrorHandler` (src/wdo/wdo_error_handler_default.prg)
//  which already does log + `USendError(500)`. For the default case,
//  just point www/config.json:
//
//      "berror": "WDO_DefaultErrorHandler"
//
//  Keep this function only if you need custom behaviour on top of the
//  default (Slack alert, retry, Sentry, WDO metrics tagging, ...).
//  Then reference "berror": "WdoErrorHandler" as this example does.
//
//  Called by WDO:SetError() on any WDO_MySql failure (bad Query,
//  reconnect fail, etc.) reached from a handler that pulled its
//  connection from the pool. oConn is the affected connection -- NIL
//  if the error came from a phase without one (e.g. factory).
//
//  Public (not STATIC) because HIX_InitPoolsFromConfig resolves the
//  name via macro (&(cExpr)) and needs it in the global symbol table.
//  ---------------------------------------------------------------
FUNCTION WdoErrorHandler( oErr, oConn )

   HB_SYMBOL_UNUSED( oConn )

   le( "[WDO] " + oErr:description + " @ " + oErr:operation )

   IF HIX_GetRequest() != NIL
      USendError( 500, "DB error: " + oErr:description )
   ENDIF

RETU NIL
