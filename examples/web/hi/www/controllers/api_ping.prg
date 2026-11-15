/*-----------------------------------------------------------
  File ......: api_ping.prg
  Author.....: Charly 9000
  Created....: 2026-08-18
  Modified...: 2026-08-18
  Version....: 1.0.0
  Description: Health check webservice. Returns server status
               as JSON. Used by the /ws-test screen.
  Usage      : GET /api/ping
  Notes      : No parameters, no database access.
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL hData := { ;
      'ok'     => .T.,          ;
      'server' => 'HIX',        ;
      'date'   => DToC( Date() ), ;
      'time'   => Time()        }

RETURN USendJson( hData )
