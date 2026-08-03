/*-----------------------------------------------------------
  File ......: time.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 1.0.0
  Description: GET /time -- returns current server time.
               Anonymous access, no auth required.
  Usage      : GET /time
               Route action: controllers/index@time.prg
 -----------------------------------------------------------*/

#include "hbclass.ch"

CLASS TimeController

   METHOD New()   CONSTRUCTOR
   METHOD End()
   METHOD Index()

ENDCLASS


METHOD New() CLASS TimeController
RETURN SELF


METHOD End() CLASS TimeController
RETURN SELF


METHOD Index() CLASS TimeController

   USendApi( { ;
      "server_time" => hb_TSToStr( hb_DateTime(), .T. ), ;
      "unix"        => Int( hb_TToSec( hb_DateTime() ) ), ;
      "timezone"    => "local" ;
   } )

RETURN NIL
