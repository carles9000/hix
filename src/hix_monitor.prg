/*-----------------------------------------------------------
  File ......: hix_monitor.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: Background health monitor thread — checks pool saturation
               and uptime.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_MONITOR

#INCLUDE "hix_logger.ch"
#INCLUDE "hbmemory.ch"

STATIC shThread := NIL
STATIC slRunning := .F.

FUNCTION HIX_MonitorStart( oServer )

   LOCAL hMon := HIX_GetConfig( "monitor" )

   IF ! hMon[ "enabled" ]

      l( "Monitor disabled" )
      RETURN NIL

   ENDIF

   slRunning := .T.
   shThread  := hb_threadStart( @_HixMonitorThread(), oServer )
   l( "Monitor started: interval=" + hb_NToS( hMon[ "interval_s" ] ) + "s" )

RETURN NIL

FUNCTION HIX_MonitorStop()

   slRunning := .F.

   IF shThread != NIL

      hb_threadJoin( shThread )
      shThread := NIL

   ENDIF

   l( "Monitor stopped" )

RETURN NIL

FUNCTION HIX_IsRunning()
RETURN slRunning

STATIC FUNCTION _HixMonitorThread( oServer )

   LOCAL nUptime   := 0
   LOCAL nInterval := HIX_GetConfig( "monitor", "interval_s" )

   DO WHILE ! oServer:lRunning

      hb_idleSleep( 0.1 )

      IF ! slRunning ; RETURN NIL ; ENDIF

   ENDDO

   ld( "Monitor: server up — health checks active" )

   DO WHILE slRunning

      IF ! _SleepInterruptible( nInterval ) ; EXIT ; ENDIF

      IF oServer != NIL .AND. ! oServer:lRunning

         lw( "Monitor: server stopped unexpectedly" )
         slRunning := .F.
         EXIT

      ENDIF

      nUptime += nInterval
      HIX_MetricSet( HIXM_UPTIME,    nUptime )
      HIX_MetricSet( HIXM_MEM_USED,  Memory( HB_MEM_USED    ) )
      HIX_MetricSet( HIXM_MEM_PEAK,  Memory( HB_MEM_USEDMAX ) )
      ld( "Monitor tick uptime=" + hb_NToS( nUptime ) + "s" + ;
         " mem=" + hb_NToS( Int( Memory( HB_MEM_USED ) / 1024 ) ) + "KB" )

   ENDDO

RETURN NIL

// Sleep in 200ms chunks so a Stop() can wake us within one chunk.
// hb_idleSleep(N) with N>>1 is uninterruptible and blocks the
// shutdown hb_threadJoin for the full remaining interval.
STATIC FUNCTION _SleepInterruptible( nSeconds )

   LOCAL nEnd := hb_MilliSeconds() + nSeconds * 1000

   DO WHILE slRunning .AND. hb_MilliSeconds() < nEnd
      hb_idleSleep( 0.2 )
   ENDDO

RETURN slRunning
