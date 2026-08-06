/*-----------------------------------------------------------
  File ......: init.prg
  Author.....: Charly 9000
  Created....: 2026-07-17
  Modified...: 2026-07-17
  Version....: 1.1.0
  Description: Fenix boot hook. Runs once after all loaders,
               middlewares and routes are registered, right
               before the accept loop starts.

               Actions:
               1) Rotates default keys (H!x@...) with random
                  values on first run. Persists to config.json.
                  Fix for audit finding C1.
               2) Dumps HIX_BootLog() to hix_bootlog.json.

  Notes      : Must be NON-blocking. Any long loop or blocking
               socket here delays server startup.
 -----------------------------------------------------------*/

FUNCTION UserInit()   

   _t( 'My boot data trace !' )   
   _d( HIX_BootLog() )   

RETURN NIL
