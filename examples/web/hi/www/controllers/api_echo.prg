/*-----------------------------------------------------------
  File ......: api_echo.prg
  Author.....: Charly 9000
  Created....: 2026-08-18
  Modified...: 2026-08-18
  Version....: 1.0.0
  Description: Echo webservice. Returns the received payload
               back to the caller. Used by the /ws-test screen
               to check POST body decoding (JSON and form).
  Usage      : POST /api/echo
  Notes      : Falls back to form data when body is not JSON.
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL xBody := UJson()

   IF xBody == NIL
      xBody := UPost()
   ENDIF

RETURN USendJson( { 'ok'       => .T.,        ;
                    'method'   => UMethod(),  ;
                    'received' => xBody,      ;
                    'time'     => Time()      } )
