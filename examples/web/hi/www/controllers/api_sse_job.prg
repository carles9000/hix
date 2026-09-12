/*-----------------------------------------------------------
  File ......: api_sse_job.prg
  Author.....: Charly 9000
  Created....: 2026-09-09
  Modified...: 2026-09-09
  Version....: 1.0.0
  Description: SSE demo of a long-running batch job. Emits one
               "running" and one "done" event per phase, plus a
               final "finished" event with progress = 100. Total
               duration = SUM(base_ms) * mult, driven by the
               ?mult=N query param (clamped to 1..60).
  Usage      : GET /api/sse/job?mult=10
               Consumed by EventSource from views/job-test.html.
  Notes      : Uses UPeerAlive() (v2.1.03) so Stop / tab-close /
               F5 free the worker in <300 ms without waiting for
               the next USendChunk to notice the peer is gone.
               Each connection holds one worker of [pool_rest]
               for the whole job -- pool size caps concurrent
               users. Marked stream:true in web.json to bypass
               exec_timeout_ms.
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL nMult
   LOCAL nSeq        := 0
   LOCAL nStart      := hb_MilliSeconds()
   LOCAL nJobTotal
   LOCAL aPhases     := _JobPhases()
   LOCAL i, hPhase, nPhaseStart, nPhaseTarget
   LOCAL lAlive      := .T.
   LOCAL oError

   nMult := Max( 1, Min( 60, Val( UGet( "mult", "1" ) ) ) )
   nJobTotal := _JobTotalMs( aPhases, nMult )

   // Force TCP close after this stream. HIX hardcodes the Connection header
   // from oReq:lKeepAlive and ignores any override in the extra hash, so we
   // mutate the request flag directly.
   HIX_GetRequest():lKeepAlive := .F.

   // Cache-Control: no-store (not no-cache) -- Chrome silently caches SSE
   // responses even with a per-request query cache-buster and replays cached
   // headers on subsequent EventSource opens.
   IF ! USendStreamStart( "text/event-stream", 200, ;
         { "Cache-Control"     => "no-store", ;
           "Pragma"            => "no-cache", ;
           "X-Accel-Buffering" => "no" } )
      RETURN NIL
   ENDIF

   TRY

      FOR i := 1 TO Len( aPhases )

         hPhase       := aPhases[ i ]
         nPhaseTarget := hPhase[ "base_ms" ] * nMult
         nPhaseStart  := hb_MilliSeconds()

         IF ! _EmitPhase( ++nSeq, hPhase, "running", nStart, nJobTotal, 0 )
            lAlive := .F.
            EXIT
         ENDIF

         // Interruptible sleep: 300 ms probes with UPeerAlive() between them.
         // The peek catches a peer FIN in the same tick, so Stop / tab-close
         // frees the worker before the next event would have been emitted.
         DO WHILE hb_MilliSeconds() - nPhaseStart < nPhaseTarget

            hb_idleSleep( 0.3 )

            IF ! UPeerAlive()
               lAlive := .F.
               EXIT
            ENDIF

         ENDDO

         IF ! lAlive ; EXIT ; ENDIF

         IF ! _EmitPhase( ++nSeq, hPhase, "done", nStart, nJobTotal, ;
               hb_MilliSeconds() - nPhaseStart )
            lAlive := .F.
            EXIT
         ENDIF

      NEXT

      IF lAlive .AND. UPeerAlive()
         _EmitPhase( ++nSeq,                                        ;
            { "id" => "done", "label" => "Process finished" },     ;
            "finished", nStart, nJobTotal, 0 )
      ENDIF

   CATCH oError

      // Peer likely gone mid-write -- fall through to stream end.

   END

   USendStreamEnd()

RETURN NIL

// -----------------------------------------------------------
// Static phase catalogue. base_ms is the duration WITHOUT the
// multiplier. Total base ~3.6 s -- with mult=10 it becomes ~36 s.
// -----------------------------------------------------------
STATIC FUNCTION _JobPhases()
RETURN { ;
   { "id" => "init",    "label" => "Starting process...",                  "base_ms" => 300 }, ;
   { "id" => "collect", "label" => "Collecting data...",                   "base_ms" => 800 }, ;
   { "id" => "calc",    "label" => "Calculating totals", "base_ms" => 900 }, ;
   { "id" => "report",  "label" => "Generating report...",                 "base_ms" => 700 }, ;
   { "id" => "deliver", "label" => "Sending report...",                    "base_ms" => 500 }, ;
   { "id" => "notify",  "label" => "Notifying stakeholders...",            "base_ms" => 400 }  ;
   }

STATIC FUNCTION _JobTotalMs( aPhases, nMult )
   LOCAL n := 0, h
   FOR EACH h IN aPhases ; n += h[ "base_ms" ] ; NEXT
RETURN n * nMult

// -----------------------------------------------------------
// Build the JSON payload and push it as a single SSE event.
// Returns the USendChunk bool so the caller can bail out.
// -----------------------------------------------------------
STATIC FUNCTION _EmitPhase( nSeq, hPhase, cState, nStart, nJobTotal, nPhaseMs )

   LOCAL nElapsed := hb_MilliSeconds() - nStart
   LOCAL nProgress
   LOCAL cJson

   nProgress := iif( nJobTotal == 0, 100, ;
                     Min( 100, Int( ( nElapsed * 100 ) / nJobTotal ) ) )

   IF cState == "finished" ; nProgress := 100 ; ENDIF

   cJson := hb_jsonEncode( { ;
      "seq"        => nSeq,                     ;
      "phase"      => hPhase[ "id" ],           ;
      "label"      => hPhase[ "label" ],        ;
      "state"      => cState,                   ;
      "progress"   => nProgress,                ;
      "elapsed_ms" => nElapsed,                 ;
      "phase_ms"   => nPhaseMs                  ;
   } )

RETURN USendChunk( "data: " + cJson + hb_eol() + hb_eol() )
