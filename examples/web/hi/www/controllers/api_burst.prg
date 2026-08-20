/*-----------------------------------------------------------
  File ......: api_burst.prg
  Author.....: Charly 9000
  Created....: 2026-08-18
  Modified...: 2026-08-18
  Version....: 1.0.0
  Description: Lightweight endpoint for the /stress-test screen.
               Answers a tiny JSON payload so the measured time
               is dominated by the server pipeline, not by the
               handler itself. Protected by HIX_MwRateLimit, so
               a burst above the configured limit gets HTTP 429.
  Usage      : GET /api/burst[?n=<seq>][&ms=<delay>]
  Notes      : ms simulates a slow handler (capped at 2000 ms) to
               watch how the worker pool queues under concurrency.
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL nSeq   := Val( UGet( 'n',  '0' ) )
   LOCAL nDelay := Val( UGet( 'ms', '0' ) )

   IF nDelay > 0
      nDelay := Min( nDelay, 2000 )
      hb_idleSleep( nDelay / 1000 )
   ENDIF

RETURN USendJson( { 'ok'   => .T.,           ;
                    'n'    => nSeq,          ;
                    'ms'   => nDelay,        ;
                    'tick' => hb_MilliSeconds() } )
