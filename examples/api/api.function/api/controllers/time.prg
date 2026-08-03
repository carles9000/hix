/*-----------------------------------------------------------
  File ......: time.prg
  Author.....: Charly 9000
  Created....: 2026-07-19
  Modified...: 2026-07-19
  Version....: 1.0.0
  Description: GET /time -- returns current server time.
               Anonymous access, no auth required.
  Usage      : GET /time
 -----------------------------------------------------------*/


FUNCTION Main()

   USendApi( { ;
      "server_time" => hb_TSToStr( hb_DateTime(), .T. ), ;
      "unix"        => Int( hb_TToSec( hb_DateTime() ) ), ;
      "timezone"    => "local" ;
   } )

RETURN NIL
