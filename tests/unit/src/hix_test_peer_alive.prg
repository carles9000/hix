/*-----------------------------------------------------------
  File ......: hix_test_peer_alive.prg
  Author.....: Charly 9000
  Created....: 2026-09-09
  Modified...: 2026-09-09
  Version....: 1.0.0
  Description: Tests for the new PeerAlive detection layer added
               in v2.1.03: THixIO:PeerAlive() (non-destructive
               recv MSG_PEEK), THixRequest:PeerAlive() wrapper,
               and UPeerAlive() route helper. Verifies delegation
               from U* -> request -> io, degradation to .F. when
               request/socket are absent, and the lAlive loop
               pattern where UPeerAlive() drives the exit.
  Usage      : Runs as part of run_all_tests. Registered in
               tests/unit/app.hbp and dispatched from app.prg
               (Transport > PeerAlive).
  Notes      : Uses TMockPeerReq / TMockPeerIO -- unique local
               mocks so the file is self-contained and does not
               depend on real TCP sockets (that path is exercised
               end-to-end by the /sse-test manual test in the
               examples/web/hi example).
 -----------------------------------------------------------*/
#include "hbclass.ch"
#include "hix_const.ch"


// Minimal IO mock that flips its alive state on demand.
CLASS TMockPeerIO
   DATA lAlive INIT .T.
   METHOD New() INLINE Self
   METHOD PeerAlive() INLINE ::lAlive
ENDCLASS

// Request mock that owns an oIO and exposes PeerAlive as the real
// THixRequest does (INLINE delegation with NIL-guard).
CLASS TMockPeerReq
   DATA oIO
   DATA cIP     INIT "127.0.0.1"
   METHOD New( oIO )
   METHOD PeerAlive() INLINE iif( ::oIO == NIL, .F., ::oIO:PeerAlive() )
ENDCLASS

METHOD New( oIO ) CLASS TMockPeerReq
   ::oIO := oIO
RETURN Self


FUNCTION HIX_TestPeerAlive_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _PeerAliveNoRequest( hCtx )
   _PeerAliveRequestNoIO( hCtx )
   _PeerAliveDelegatesAlive( hCtx )
   _PeerAliveDelegatesDead( hCtx )
   _PeerAliveLAliveLoop( hCtx )
   _RealIoEmptySocket( hCtx )
   HIX_SetRequest( NIL )
RETURN hCtx


// 1. UPeerAlive without an active request -> .F.
STATIC PROCEDURE _PeerAliveNoRequest( hCtx )
   LOCAL lRet
   HIX_SetRequest( NIL )
   lRet := UPeerAlive()
   HixTU_Check( hCtx, lRet == .F., "UPeerAlive without request -> .F.", ".F.", hb_CStr( lRet ) )
RETURN

// 2. Request without oIO -> PeerAlive returns .F. (NIL-guard).
STATIC PROCEDURE _PeerAliveRequestNoIO( hCtx )
   LOCAL oReq := TMockPeerReq():New( NIL ), lRet
   HIX_SetRequest( oReq )
   lRet := UPeerAlive()
   HixTU_Check( hCtx, lRet == .F., "UPeerAlive request without oIO -> .F.", ".F.", hb_CStr( lRet ) )
RETURN

// 3. Alive IO -> UPeerAlive returns .T.
STATIC PROCEDURE _PeerAliveDelegatesAlive( hCtx )
   LOCAL oIO  := TMockPeerIO():New()
   LOCAL oReq := TMockPeerReq():New( oIO )
   LOCAL lRet
   oIO:lAlive := .T.
   HIX_SetRequest( oReq )
   lRet := UPeerAlive()
   HixTU_Check( hCtx, lRet == .T., "UPeerAlive with alive IO -> .T.", ".T.", hb_CStr( lRet ) )
RETURN

// 4. Dead IO -> UPeerAlive returns .F.
STATIC PROCEDURE _PeerAliveDelegatesDead( hCtx )
   LOCAL oIO  := TMockPeerIO():New()
   LOCAL oReq := TMockPeerReq():New( oIO )
   LOCAL lRet
   oIO:lAlive := .F.
   HIX_SetRequest( oReq )
   lRet := UPeerAlive()
   HixTU_Check( hCtx, lRet == .F., "UPeerAlive with dead IO -> .F.", ".F.", hb_CStr( lRet ) )
RETURN

// 5. Bible-documented lAlive pattern: peer alive for 3 ticks then
// dies -- loop MUST exit on the 4th probe without any USendChunk.
STATIC PROCEDURE _PeerAliveLAliveLoop( hCtx )
   LOCAL oIO  := TMockPeerIO():New()
   LOCAL oReq := TMockPeerReq():New( oIO )
   LOCAL lAlive := .T.
   LOCAL nTicks := 0

   HIX_SetRequest( oReq )

   DO WHILE lAlive
      IF ! UPeerAlive()
         lAlive := .F.
         LOOP
      ENDIF
      nTicks++
      IF nTicks == 3 ; oIO:lAlive := .F. ; ENDIF
      IF nTicks > 100     // safety net -- test should never reach this
         EXIT
      ENDIF
   ENDDO

   HixTU_Check( hCtx, nTicks == 3, "lAlive loop exits after peer FIN", "3", hb_NToS( nTicks ) )
   HixTU_Check( hCtx, ! lAlive,    "lAlive flag flips to .F.",         ".F.", hb_CStr( lAlive ) )
RETURN

// 6. Real THixIO with an empty hSocket must return .F. -- guards
// against a NIL socket surviving as .T. through the DO CASE.
STATIC PROCEDURE _RealIoEmptySocket( hCtx )
   LOCAL oIO := THixIO():New( NIL )
   LOCAL lRet := oIO:PeerAlive()
   HixTU_Check( hCtx, lRet == .F., "THixIO:PeerAlive empty socket -> .F.", ".F.", hb_CStr( lRet ) )
RETURN
