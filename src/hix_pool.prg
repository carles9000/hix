/*-----------------------------------------------------------
  File ......: hix_pool.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: Generic thread worker pool — mutex/notify pattern,
               configurable queue and worker count.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_POOL

#INCLUDE "hix_logger.ch"
#INCLUDE "error.ch"

// ============================================================
// HIX_WorkerProtect — todo Worker envuelve su ciclo en esto
// Si hay error no controlado: loguea, incrementa metrica,
// el Worker SIGUE VIVO.
// ============================================================
FUNCTION HIX_WorkerProtect( cModule, bBlock )

   LOCAL oErr, cLine

   hb_default( @cModule, "worker" )

   BEGIN SEQUENCE WITH {| e | Break( e ) }

      Eval( bBlock )
   RECOVER USING oErr

      IF __objHasData( oErr, "PROCLINE" )

         cLine := hb_NToS( hb_defaultValue( oErr:ProcLine, 0 ) )
      ELSE
         cLine := "0"

      ENDIF

      le( "[" + cModule + "] Error: " + oErr:Description + ;
         " (" + oErr:FileName + ":" + cLine + ")" )
      HIX_Metric( HIXM_ERRORS )

   END SEQUENCE

RETURN NIL

// ============================================================

CLASS THixPool

   DATA cTipo          INIT ""
   DATA bWorkerFunc    INIT NIL

   DATA oQueue         INIT NIL    // mutex usado como cola de mensajes
   DATA nQueueMax      INIT 512    // límite lógico (saturación)

   DATA aWorkers       INIT {}
   DATA nWorkers       INIT 0
   DATA nActiveWorkers INIT 0
   DATA nDispatched    INIT 0     // total de jobs encolados con exito (solo crece)

   DATA oMutex           INIT NIL    // protege contadores
   DATA lRunning         INIT .F.
   DATA nWorkersRunning  INIT 0     // workers vivos (decrementado al salir)
   DATA nAlertPct      INIT 75

   METHOD New( cTipo, bWorkerFunc )
   METHOD Init()
   METHOD Dispatch( aJob )
   METHOD Stop()
   METHOD WorkerCount()
   METHOD ActiveCount()
   METHOD IsSaturated()
   METHOD StatusJson()

   METHOD _JobDone()

ENDCLASS

// ------------------------------------------------------------
METHOD New( cTipo, bWorkerFunc ) CLASS THixPool

   LOCAL hSec

   ::cTipo       := cTipo
   ::bWorkerFunc := bWorkerFunc

   DO CASE

      CASE cTipo == HIX_POOL_DETECTOR
         hSec := HIX_GetConfig( "detector" )
         ::nWorkers  := hSec[ "workers" ]
         ::nQueueMax := hSec[ "queue_size" ]
      CASE cTipo == HIX_POOL_HTTP
         hSec := HIX_GetConfig( "pool_http" )
         ::nWorkers  := hSec[ "workers" ]
         ::nQueueMax := hSec[ "queue_size" ]
      CASE cTipo == HIX_POOL_WS
         hSec := HIX_GetConfig( "pool_ws" )
         ::nWorkers  := hSec[ "workers" ]
         ::nQueueMax := hSec[ "queue_size" ]
      CASE cTipo == HIX_POOL_REST
         hSec := HIX_GetConfig( "pool_rest" )
         ::nWorkers  := hSec[ "workers_sse" ] + hSec[ "workers_longpoll" ]
         ::nQueueMax := hSec[ "queue_size" ]
      CASE cTipo == HIX_POOL_HIX
         hSec := HIX_GetConfig( "pool_hix" )
         ::nWorkers  := hSec[ "workers" ]
         ::nQueueMax := hSec[ "queue_size" ]
      OTHERWISE
         ::nWorkers  := 4
         ::nQueueMax := 128

   ENDCASE

   ::nAlertPct := HIX_GetConfig( "monitor", "alert_pct" )
   ::oQueue    := hb_mutexCreate()
   ::oMutex    := hb_mutexCreate()

RETURN Self

// ------------------------------------------------------------
METHOD Init() CLASS THixPool

   LOCAL i

   ::lRunning := .T.
   ::aWorkers := {}

   FOR i := 1 TO ::nWorkers

      AAdd( ::aWorkers, hb_threadStart( @_HixPoolWorker(), Self ) )

   NEXT

   l( "Pool [" + ::cTipo + "] started: workers=" + hb_NToS( ::nWorkers ) + ;
      " queue=" + hb_NToS( ::nQueueMax ) )

RETURN Self

// ------------------------------------------------------------
// Dispatch — encolar un job vía mutexNotify
// Retorna .T. si encolado, .F. si saturado (> nQueueMax)
// ------------------------------------------------------------
METHOD Dispatch( aJob ) CLASS THixPool

   LOCAL nWorkers := 0, nJobs := 0

   IF ! ::lRunning

      RETURN .F.

   ENDIF

   // Verificar saturación antes de encolar
   hb_mutexQueueInfo( ::oQueue, @nWorkers, @nJobs )

   IF nJobs >= ::nQueueMax

      HIX_Metric( HIXM_SATURATED )
      le( "Pool [" + ::cTipo + "] FULL (" + hb_NToS( nJobs ) + ") — rejecting job" )
      RETURN .F.

   ENDIF

   // Alerta de capacidad

   IF nJobs > 0 .AND. ( nJobs * 100 / ::nQueueMax ) >= ::nAlertPct

      HIX_Metric( HIXM_SATURATED )
      lw( "Pool [" + ::cTipo + "] at " + ;
         hb_NToS( Int( nJobs * 100 / ::nQueueMax ) ) + "% capacity" )

   ENDIF

   // Encolar: el mutex actúa como cola FIFO
   hb_mutexNotify( ::oQueue, aJob )

   hb_mutexLock( ::oMutex )
   ::nDispatched++
   hb_mutexUnlock( ::oMutex )

RETURN .T.

// ------------------------------------------------------------
METHOD _JobDone() CLASS THixPool

   hb_mutexLock( ::oMutex )

   IF ::nActiveWorkers > 0

      ::nActiveWorkers--

   ENDIF

   hb_mutexUnlock( ::oMutex )

RETURN Self

// ------------------------------------------------------------
// Stop — marca lRunning=.F. y espera que los workers salgan solos.
// Los workers comprueban lRunning cada 200ms via timeout de subscribe.
// ------------------------------------------------------------
METHOD Stop() CLASS THixPool

   LOCAL hThread, i

   l( "Pool [" + ::cTipo + "] stopping..." )
   ::lRunning := .F.
   // Wake each worker with NIL so they drain pending jobs (FIFO) and exit cleanly

   FOR i := 1 TO ::nWorkers

      hb_mutexNotify( ::oQueue, NIL )

   NEXT

   FOR EACH hThread IN ::aWorkers

      hb_threadJoin( hThread )

   NEXT

   l( "Pool [" + ::cTipo + "] stopped" )

RETURN Self

// ------------------------------------------------------------
METHOD WorkerCount() CLASS THixPool
RETURN Len( ::aWorkers )

METHOD ActiveCount() CLASS THixPool

   LOCAL n

   hb_mutexLock( ::oMutex )
   n := ::nActiveWorkers
   hb_mutexUnlock( ::oMutex )

RETURN n

METHOD IsSaturated() CLASS THixPool

   LOCAL nW := 0, nJ := 0

   hb_mutexQueueInfo( ::oQueue, @nW, @nJ )

RETURN nJ >= ::nQueueMax

METHOD StatusJson() CLASS THixPool

   LOCAL nW := 0, nJ := 0, nActive

   hb_mutexQueueInfo( ::oQueue, @nW, @nJ )
   hb_mutexLock( ::oMutex )
   nActive := ::nActiveWorkers
   hb_mutexUnlock( ::oMutex )

RETURN '{"pool":"' + ::cTipo + '",' + ;
      '"workers":'  + hb_NToS( ::nWorkers ) + ',' + ;
      '"active":'   + hb_NToS( nActive )    + ',' + ;
      '"queued":'   + hb_NToS( nJ )         + ',' + ;
      '"max":'      + hb_NToS( ::nQueueMax ) + '}'

// ============================================================
// Hilo Worker: espera jobs vía mutexSubscribe
// ============================================================
STATIC FUNCTION _HixPoolWorker( oPool )

   LOCAL aJob

   ld( "Pool [" + oPool:cTipo + "] worker started" )

   // Harbour sets + RDD default heredados del hilo main via hb_setClone
   // (vm/thread.c:1109). El main llama HIX_HarbourConfigApply() antes de
   // spawn de este pool, asi que los sets ya llegan correctos.

   DO WHILE .T.

      // Wait for a job or timeout every 200ms (seconds, not ms)

      IF ! hb_mutexSubscribe( oPool:oQueue, 0.2, @aJob )

         // Timeout: only exit if Stop() was called

         IF ! oPool:lRunning

            EXIT

         ENDIF

         LOOP

      ENDIF

      // NIL is the stop signal sent by Stop() — drain remaining real jobs first (FIFO)

      IF aJob == NIL

         EXIT

      ENDIF

      hb_mutexLock( oPool:oMutex )
      oPool:nActiveWorkers++
      hb_mutexUnlock( oPool:oMutex )

      HIX_WorkerProtect( oPool:cTipo, {|| Eval( oPool:bWorkerFunc, aJob ) } )

      oPool:_JobDone()

   ENDDO

   ld( "Pool [" + oPool:cTipo + "] worker stopped" )

RETURN NIL
