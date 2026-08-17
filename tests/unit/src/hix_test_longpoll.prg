/*-----------------------------------------------------------
  File ......: hix_test_longpoll.prg
  Author.....: Charly 9000
  Created....: 2026-06-06
  Description: Integrated test — LongPoll bus
               (HIX_LongPollSetup/Count/Push + _HixLpWait)
 -----------------------------------------------------------*/
#include "fileio.ch"
#include "hix_const.ch"

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[LongPoll] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

FUNCTION HIX_TestLongPoll_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TLog( "=== HIX_TestLongPoll_Run start ===" )
   _LpSetup(   hCtx )
   _LpPushNoWaiters( hCtx )
   _LpPushWait( hCtx )
   _TLog( "=== HIX_TestLongPoll_Run end ===" )
RETURN hCtx

STATIC PROCEDURE _LpSetup( hCtx )
   LOCAL oError
   _TLog( "_LpSetup" )
   TRY
      HIX_LongPollSetup( 30 )
      HixTU_Check( hCtx, .T., "LongPoll: Setup no crash", "ok", "ok" )
   CATCH oError
      _TLog( "Setup error: " + oError:description )
      HixTU_Check( hCtx, .F., "LongPoll: Setup no crash", "ok", oError:description )
   END
   _TLog( "Count ch_none=" + hb_NToS( HIX_LongPollCount( "test_lp_none_" + hb_NToS( Seconds() ) ) ) )
   HixTU_Check( hCtx, HIX_LongPollCount( "test_lp_none" ) == 0, "LongPoll: Count canal nuevo = 0", "0", hb_NToS( HIX_LongPollCount( "test_lp_none" ) ) )
RETURN

STATIC PROCEDURE _LpPushNoWaiters( hCtx )
   LOCAL nNotified
   _TLog( "_LpPushNoWaiters" )
   nNotified := HIX_LongPollPush( "test_lp_empty", "hello" )
   _TLog( "Push sin waiters -> " + hb_NToS( nNotified ) )
   HixTU_Check( hCtx, nNotified == 0, "LongPoll: Push sin waiters -> 0", "0", hb_NToS( nNotified ) )
   // Push con objeto (serializa a JSON)
   nNotified := HIX_LongPollPush( "test_lp_empty2", { "x" => 1 } )
   HixTU_Check( hCtx, nNotified == 0, "LongPoll: Push objeto sin waiters -> 0", "0", hb_NToS( nNotified ) )
RETURN

STATIC PROCEDURE _LpPushWait( hCtx )
   LOCAL aRes, hThr
   _TLog( "_LpPushWait: iniciando thread waiter" )
   // Thread hace Push tras 50ms, main espera con timeout 3s
   hThr := hb_threadStart( {|| ( hb_idleSleep( 0.05 ), HIX_LongPollPush( "test_lp_sync", '{"v":42}' ) ) } )
   aRes := _HixLpWait( "test_lp_sync", 3 )
   hb_threadJoin( hThr )
   _TLog( "LpWait result lGot=" + hb_ValToStr( aRes[1] ) + " data=" + hb_ValToStr( aRes[2] ) )
   HixTU_Check( hCtx, aRes[1],                  "LongPoll: Push+Wait -> lGot=.T.",           ".T.",     iif( aRes[1], ".T.", ".F." ) )
   HixTU_Check( hCtx, aRes[2] == '{"v":42}',    "LongPoll: Push+Wait -> data correcto",      '{"v":42}', hb_ValToStr( aRes[2] ) )
RETURN
