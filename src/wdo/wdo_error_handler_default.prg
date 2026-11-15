/*-----------------------------------------------------------
  File ......: wdo_error_handler_default.prg
  Author.....: Charly 9000
  Created....: 2026-09-30
  Modified...: 2026-09-30
  Version....: 1.0.0
  Description: WDO_DefaultErrorHandler -- generic bError callback
               ready to plug into any WDO pool via
               "berror": "WDO_DefaultErrorHandler" in www/config.json.
               Logs the WDO error and, when reached from an HTTP
               handler, sends a 500 back to the client.
  Usage      : www/config.json:
                 "databases": {
                   "mysql": { ..., "berror": "WDO_DefaultErrorHandler" }
                 }
  Notes      : Public (not STATIC) because HIX_InitPoolsFromConfig
               resolves the name via macro (&(cExpr)) and needs it
               in the global symbol table.

               Projects needing custom behaviour (Slack alerts,
               retry, Sentry, WDO metrics tagging, etc.) should
               copy this file, rename the function and reference
               the new name in "berror". See
               examples/wdo/src/app.prg :: WdoErrorHandler for a
               template.
 -----------------------------------------------------------*/

#include "hix_logger.ch"


FUNCTION WDO_DefaultErrorHandler( oErr, oConn )

   HB_SYMBOL_UNUSED( oConn )

   le( "[WDO] " + oErr:description + " @ " + oErr:operation )

   IF HIX_GetRequest() != NIL
      USendError( 500, "DB error: " + oErr:description )
   ENDIF

RETU NIL
