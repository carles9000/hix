/*-----------------------------------------------------------
  File ......: hix_test_usendchunk_propagate.prg
  Author.....: Charly 9000
  Created....: 2026-09-08
  Modified...: 2026-09-08
  Version....: 1.0.0
  Description: Regression test for the USendChunk / USendStreamStart /
               USendStreamEnd bool-return fix. Before the fix these
               helpers swallowed the write status and always returned
               NIL, so a stream handler had no way to notice a peer
               disconnect without an active dispatcher timeout --
               ending in a permanent worker zombie.
               The tests exercise the propagation chain via a mock
               request whose stream methods can flip to failure mode,
               and simulate the lAlive loop pattern documented in the
               HIX bible.
  Usage      : Runs as part of run_all_tests. Registered in app.hbp
               and dispatched from app.prg (Transport > USendChunk).
  Notes      : Uses TMockPropReq (unique name) so the mock stays
               scoped to this file and does not clash with the mock
               of hix_test_helpers.prg.
 -----------------------------------------------------------*/
#include "hbclass.ch"
#include "hix_const.ch"

// TMockPropReq -- request mock whose stream methods return .T./.F.
// and can be flipped to failure mode via lFailWrite.
CLASS TMockPropReq
   DATA cMethod        INIT "GET"
   DATA cPath          INIT "/stream"
   DATA cQuery         INIT ""
   DATA hHeaders       INIT { => }
   DATA hExtraHeaders  INIT { => }
   DATA cBody          INIT ""
   DATA cBodyResp      INIT ""
   DATA cMime          INIT ""
   DATA nStatus        INIT 0
   DATA lStreaming     INIT .F.
   DATA lResponded     INIT .F.
   DATA lKeepAlive     INIT .F.
   DATA cIP            INIT "127.0.0.1"
   DATA hParam         INIT { => }
   DATA nChunks        INIT 0     // count of successful RespondChunk calls
   DATA lFailWrite     INIT .F.   // when .T., all stream methods return .F.

   METHOD New()                            INLINE Self
   METHOD Header( cKey, xDef )             INLINE hb_HGetDef( ::hHeaders, Lower( cKey ), hb_defaultValue( xDef, "" ) )
   METHOD Cookie( cName, xDef )            INLINE hb_defaultValue( xDef, "" )
   METHOD IsAjax()                         INLINE .F.
   METHOD IsHttps()                        INLINE .F.
   METHOD Scheme()                         INLINE "http"
   METHOD RealIP()                         INLINE ::cIP
   METHOD RealHost()                       INLINE ""
   METHOD QueryParam( cKey, xDef )         INLINE hb_defaultValue( xDef, "" )
   METHOD QueryParamsAll()                 INLINE { => }
   METHOD FormBody()                       INLINE { => }
   METHOD JsonBody()                       INLINE NIL
   METHOD ReadBody()                       INLINE ""
   METHOD ContentType()                    INLINE ""
   METHOD IsJson()                         INLINE .F.
   METHOD IsForm()                         INLINE .F.
   METHOD Respond( xData, nStatus, cMime, hExtra )   INLINE ( HB_SYMBOL_UNUSED( xData ), HB_SYMBOL_UNUSED( nStatus ), HB_SYMBOL_UNUSED( cMime ), HB_SYMBOL_UNUSED( hExtra ), ::lResponded := .T., Self )
   METHOD Redirect( cUrl, nStatus )        INLINE ( HB_SYMBOL_UNUSED( cUrl ), HB_SYMBOL_UNUSED( nStatus ), Self )

   METHOD RespondStart( cMime, nStatus, hExtra )
   METHOD RespondChunk( cData )
   METHOD RespondEnd()
ENDCLASS

METHOD RespondStart( cMime, nStatus, hExtra ) CLASS TMockPropReq
   HB_SYMBOL_UNUSED( hExtra )
   hb_default( @cMime,   "html" )
   hb_default( @nStatus, 200 )
   ::cMime      := cMime
   ::nStatus    := nStatus
   ::lStreaming := .T.
   ::lResponded := .T.
   IF ::lFailWrite ; RETURN .F. ; ENDIF
RETURN .T.

METHOD RespondChunk( cData ) CLASS TMockPropReq
   IF ::lFailWrite ; RETURN .F. ; ENDIF
   ::cBodyResp += cData
   ::nChunks++
RETURN .T.

METHOD RespondEnd() CLASS TMockPropReq
   ::lStreaming := .F.
   IF ::lFailWrite ; RETURN .F. ; ENDIF
RETURN .T.


FUNCTION HIX_TestUSendChunkPropagate_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _PropStartOk( hCtx )
   _PropStartFail( hCtx )
   _PropChunkOk( hCtx )
   _PropChunkFail( hCtx )
   _PropEndOk( hCtx )
   _PropEndFail( hCtx )
   _PropNoRequest( hCtx )
   _PropLAliveLoop( hCtx )
   _PropLAliveWallClock( hCtx )
   HIX_SetRequest( NIL )
RETURN hCtx


STATIC PROCEDURE _PropStartOk( hCtx )
   LOCAL oMock := TMockPropReq():New(), lRet
   HIX_SetRequest( oMock )
   lRet := USendStreamStart( "text/event-stream", 200 )
   HixTU_Check( hCtx, lRet == .T.,          "USendStreamStart peer alive -> .T.",   ".T.", hb_CStr( lRet ) )
   HixTU_Check( hCtx, oMock:lStreaming,     "USendStreamStart marks streaming",     ".T.", hb_CStr( oMock:lStreaming ) )
RETURN

STATIC PROCEDURE _PropStartFail( hCtx )
   LOCAL oMock := TMockPropReq():New(), lRet
   oMock:lFailWrite := .T.
   HIX_SetRequest( oMock )
   lRet := USendStreamStart( "text/event-stream", 200 )
   HixTU_Check( hCtx, lRet == .F.,          "USendStreamStart peer dead -> .F.",    ".F.", hb_CStr( lRet ) )
RETURN

STATIC PROCEDURE _PropChunkOk( hCtx )
   LOCAL oMock := TMockPropReq():New(), lRet
   HIX_SetRequest( oMock )
   USendStreamStart( "text", 200 )
   lRet := USendChunk( "hello" )
   HixTU_Check( hCtx, lRet == .T.,             "USendChunk peer alive -> .T.",         ".T.",     hb_CStr( lRet ) )
   HixTU_Check( hCtx, oMock:cBodyResp == "hello", "USendChunk writes payload",         "hello",   oMock:cBodyResp )
   HixTU_Check( hCtx, oMock:nChunks == 1,      "USendChunk increments chunk count",    "1",       hb_NToS( oMock:nChunks ) )
RETURN

STATIC PROCEDURE _PropChunkFail( hCtx )
   LOCAL oMock := TMockPropReq():New(), lRet
   HIX_SetRequest( oMock )
   USendStreamStart( "text", 200 )
   // First chunk goes through, then peer disconnects
   USendChunk( "before-close" )
   oMock:lFailWrite := .T.
   lRet := USendChunk( "after-close" )
   HixTU_Check( hCtx, lRet == .F.,                    "USendChunk peer dead -> .F.",             ".F.",           hb_CStr( lRet ) )
   HixTU_Check( hCtx, oMock:cBodyResp == "before-close", "USendChunk discards post-close data",   "before-close",  oMock:cBodyResp )
   HixTU_Check( hCtx, oMock:nChunks == 1,             "USendChunk keeps count at 1 after fail",  "1",             hb_NToS( oMock:nChunks ) )
RETURN

STATIC PROCEDURE _PropEndOk( hCtx )
   LOCAL oMock := TMockPropReq():New(), lRet
   HIX_SetRequest( oMock )
   USendStreamStart( "text", 200 )
   USendChunk( "payload" )
   lRet := USendStreamEnd()
   HixTU_Check( hCtx, lRet == .T.,          "USendStreamEnd peer alive -> .T.",     ".T.", hb_CStr( lRet ) )
   HixTU_Check( hCtx, ! oMock:lStreaming,   "USendStreamEnd clears streaming flag", ".F.", hb_CStr( oMock:lStreaming ) )
RETURN

STATIC PROCEDURE _PropEndFail( hCtx )
   LOCAL oMock := TMockPropReq():New(), lRet
   HIX_SetRequest( oMock )
   USendStreamStart( "text", 200 )
   oMock:lFailWrite := .T.
   lRet := USendStreamEnd()
   HixTU_Check( hCtx, lRet == .F.,          "USendStreamEnd peer dead -> .F.",      ".F.", hb_CStr( lRet ) )
RETURN

STATIC PROCEDURE _PropNoRequest( hCtx )
   LOCAL lRetStart, lRetChunk, lRetEnd
   HIX_SetRequest( NIL )
   lRetStart := USendStreamStart( "text", 200 )
   lRetChunk := USendChunk( "orphan" )
   lRetEnd   := USendStreamEnd()
   HixTU_Check( hCtx, lRetStart == .F., "USendStreamStart no request -> .F.", ".F.", hb_CStr( lRetStart ) )
   HixTU_Check( hCtx, lRetChunk == .F., "USendChunk no request -> .F.",       ".F.", hb_CStr( lRetChunk ) )
   HixTU_Check( hCtx, lRetEnd   == .F., "USendStreamEnd no request -> .F.",   ".F.", hb_CStr( lRetEnd ) )
RETURN

// Simulates the bible-documented lAlive loop pattern.
// Peer stays alive for 3 chunks then disconnects. The loop MUST exit
// on the fourth attempt without needing an external timeout.
STATIC PROCEDURE _PropLAliveLoop( hCtx )
   LOCAL oMock := TMockPropReq():New()
   LOCAL lAlive := .T.
   LOCAL nSent  := 0

   HIX_SetRequest( oMock )
   USendStreamStart( "text/event-stream", 200 )
   DO WHILE lAlive
      IF nSent == 3 ; oMock:lFailWrite := .T. ; ENDIF
      IF ! USendChunk( "data: tick" + hb_eol() + hb_eol() )
         lAlive := .F.
         LOOP
      ENDIF
      nSent++
      IF nSent > 100     // safety net -- test would never reach this
         EXIT
      ENDIF
   ENDDO

   HixTU_Check( hCtx, nSent == 3,       "lAlive loop exits after peer close",   "3", hb_NToS( nSent ) )
   HixTU_Check( hCtx, ! lAlive,          "lAlive flag flips to .F.",             ".F.", hb_CStr( lAlive ) )
RETURN

// Wall-clock guard: even under a probe-based sleep loop the handler
// must not stay alive longer than a small budget after the peer dies.
STATIC PROCEDURE _PropLAliveWallClock( hCtx )
   LOCAL oMock := TMockPropReq():New()
   LOCAL lAlive := .T.
   LOCAL nStart := Seconds()
   LOCAL nWaitMs, nSlept
   LOCAL nElapsed

   HIX_SetRequest( oMock )
   USendStreamStart( "text/event-stream", 200 )

   // Simulate the ejemplo/hi ticker: emit one event, then probe-sleep,
   // and disconnect the peer mid-sleep. Wall-clock must land under 1 s.
   oMock:lFailWrite := .F.
   IF ! USendChunk( "data: first" + hb_eol() + hb_eol() )
      lAlive := .F.
   ENDIF

   nWaitMs := 2000    // handler thinks it will sleep 2 s
   nSlept  := 0
   DO WHILE nSlept < nWaitMs .AND. lAlive
      hb_idleSleep( 0.1 )
      nSlept += 100
      // Peer dies at ~300 ms; the very next probe must catch it.
      IF nSlept >= 300 ; oMock:lFailWrite := .T. ; ENDIF
      IF ! USendChunk( ":k" + hb_eol() + hb_eol() )
         lAlive := .F.
      ENDIF
   ENDDO

   nElapsed := Seconds() - nStart
   HixTU_Check( hCtx, ! lAlive,           "Wall-clock: lAlive false after peer close", ".F.",  hb_CStr( lAlive ) )
   HixTU_Check( hCtx, nElapsed < 1,       "Wall-clock: loop exits under 1 s",          "< 1",  hb_NToS( nElapsed ) + " s" )
RETURN
