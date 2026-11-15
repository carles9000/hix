/*-----------------------------------------------------------
  File ......: api_sse_ticker.prg
  Author.....: Charly 9000
  Created....: 2026-09-08
  Modified...: 2026-09-09
  Version....: 1.2.0
  Description: SSE ticker for the /sse-test demo.
               Emits one event every 1..4 seconds carrying the
               live user count and the current server time.
               The user count is a thread-safe atomic metric
               shared across all workers ("sse_liveroom_users").
  Usage      : GET /api/sse/ticker  (consumed by EventSource
               from views/sse-test.html)
  Notes      : Each open connection holds one worker of
               [pool_rest] until the client disconnects.
               Uses UPeerAlive() (non-destructive MSG_PEEK) as
               the primary exit -- catches a browser FIN in the
               same 300 ms probe, without relying on the TCP
               send buffer to surface the close. USendChunk is
               kept as a secondary check for aggressive RSTs.
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL lAlive := .T.
   LOCAL cJson
   LOCAL oError
   LOCAL nWaitMs
   LOCAL nSlept

   HIX_Metric( "sse_liveroom_users", 1 )

   IF ! USendStreamStart( "text/event-stream", 200, ;
         { "Cache-Control"     => "no-cache", ;
           "X-Accel-Buffering" => "no",       ;
           "Connection"        => "keep-alive" } )

      // Headers never reached the peer -- nothing to stream.
      HIX_MetricDec( "sse_liveroom_users" )
      RETURN NIL

   ENDIF

   TRY

      DO WHILE lAlive

         // Primary exit: MSG_PEEK detects peer FIN immediately.
         IF ! UPeerAlive()
            lAlive := .F.
            LOOP
         ENDIF

         cJson := hb_jsonEncode( { ;
            "users" => HIX_MetricGet( "sse_liveroom_users" ), ;
            "time"  => Time() } )

         // USendChunk kept as secondary safety net for aggressive RST.
         IF ! USendChunk( "data: " + cJson + hb_eol() + hb_eol() )
            lAlive := .F.
            LOOP
         ENDIF

         // Random cadence 1..4 s split into 300 ms probes so a disconnect
         // (tab closed, page refreshed, Stop button) is noticed within
         // one probe tick via UPeerAlive().

         nWaitMs := hb_randomInt( 1, 4 ) * 1000
         nSlept  := 0
         DO WHILE nSlept < nWaitMs .AND. lAlive
            hb_idleSleep( 0.3 )
            nSlept += 300
            IF ! UPeerAlive()
               lAlive := .F.
            ENDIF
         ENDDO

      ENDDO

   CATCH oError

      // Defensive fallback -- lAlive is the primary exit path but a
      // pathological failure elsewhere would still land here safely.

   END

   HIX_MetricDec( "sse_liveroom_users" )

   USendStreamEnd()

RETURN NIL
