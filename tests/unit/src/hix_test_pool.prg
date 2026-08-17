/*-----------------------------------------------------------
  File ......: hix_test_pool.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — THixPool (ring buffer, workers, HIX_WorkerProtect)
 -----------------------------------------------------------*/
#include "hix_const.ch"

STATIC PROCEDURE _PoolConfigure( nWorkers, nQueue )
   LOCAL hCfg
   hb_default( @nWorkers, 2 )
   hb_default( @nQueue,   8 )
   HIX_LoadConfig()
   hCfg := HIX_GetConfig()
   hCfg[ "pool_http" ][ "workers" ]    := nWorkers
   hCfg[ "pool_http" ][ "queue_size" ] := nQueue
RETURN

FUNCTION HIX_TestPool_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _PoolRingBuffer(    hCtx )
   _PoolDispatch(      hCtx )
   _PoolSaturation(    hCtx )
   _PoolStop(          hCtx )
   _PoolWorkerProtect( hCtx )
RETURN hCtx

STATIC PROCEDURE _PoolRingBuffer( hCtx )
   LOCAL oPool, aOut, mtxOut, i

   aOut   := {}
   mtxOut := hb_mutexCreate()
   _PoolConfigure( 1, 8 )
   oPool   := THixPool():New( HIX_POOL_HTTP, {| j |
      hb_mutexLock( mtxOut )
      AAdd( aOut, j )
      hb_mutexUnlock( mtxOut )
      RETURN NIL
   } )
   oPool:Init()

   FOR i := 1 TO 4
      oPool:Dispatch( i )
   NEXT

   hb_idleSleep( 0.3 )
   oPool:Stop()

   HixTU_Check( hCtx, Len( aOut ) == 4,                "Pool: FIFO 4 items procesados", "4",    hb_NToS( Len( aOut ) ) )
   HixTU_Check( hCtx, aOut[1] == 1 .AND. aOut[4] == 4, "Pool: FIFO orden correcto",     "1..4", "check" )
RETURN

STATIC PROCEDURE _PoolDispatch( hCtx )
   LOCAL oPool

   _PoolConfigure( 3, 10 )
   oPool := THixPool():New( HIX_POOL_HTTP, {| j | HB_SYMBOL_UNUSED(j) } )
   oPool:Init()
   HixTU_Check( hCtx, oPool:WorkerCount() == 3, "Pool: WorkerCount=3", "3", hb_NToS( oPool:WorkerCount() ) )
   oPool:Stop()
RETURN

STATIC PROCEDURE _PoolSaturation( hCtx )
   LOCAL oPool, mtxBlock, i, nRejected

   // mtxBlock held by main thread keeps the worker busy after it picks up job 1,
   // so the queue fills deterministically before we call IsSaturated().
   mtxBlock  := hb_mutexCreate()
   nRejected := 0
   _PoolConfigure( 1, 2 )
   oPool := THixPool():New( HIX_POOL_HTTP, {| j |
      hb_mutexLock( mtxBlock )
      hb_mutexUnlock( mtxBlock )
      HB_SYMBOL_UNUSED( j )
      RETURN NIL
   } )
   oPool:Init()

   hb_mutexLock( mtxBlock )
   oPool:Dispatch( 1 )
   hb_idleSleep( 0.05 )      // give worker time to pick up job 1 and block on mtxBlock

   FOR i := 2 TO 5
      IF ! oPool:Dispatch( i )
         nRejected++
      ENDIF
   NEXT

   HixTU_Check( hCtx, oPool:IsSaturated(), "Pool: IsSaturated despues de overflow", ".T.", iif(oPool:IsSaturated(),".T.",".F.") )
   HixTU_Check( hCtx, nRejected >= 1,      "Pool: overflow rechaza jobs",           ">=1", hb_NToS( nRejected ) )

   hb_mutexUnlock( mtxBlock )
   hb_idleSleep( 0.3 )
   oPool:Stop()
RETURN

STATIC PROCEDURE _PoolStop( hCtx )
   LOCAL oPool, lStopped

   lStopped := .F.
   _PoolConfigure( 2, 5 )
   oPool := THixPool():New( HIX_POOL_HTTP, {| j | HB_SYMBOL_UNUSED(j) } )
   oPool:Init()
   hb_idleSleep( 0.1 )
   oPool:Stop()
   lStopped := .T.
   HixTU_Check( hCtx, lStopped, "Pool: Stop sin crash", ".T.", ".F." )
RETURN

STATIC PROCEDURE _PoolWorkerProtect( hCtx )
   LOCAL nVal := 0

   HIX_WorkerProtect( "test", {|| nVal := 1 } )
   HixTU_Check( hCtx, nVal == 1, "Pool: WorkerProtect bloque ejecutado", "1", hb_NToS( nVal ) )

   HIX_WorkerProtect( "test", {|| nVal := 42 } )
   HixTU_Check( hCtx, nVal == 42, "Pool: WorkerProtect segundo bloque", "42", hb_NToS( nVal ) )
RETURN
