/*-----------------------------------------------------------
  File ......: hix_metrics.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: Atomic thread-safe performance counters
               (HIX_MetricsInit, HIX_MetricInc).
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_METRICS
#INCLUDE "hix_logger.ch"

STATIC soMetrics := NIL
STATIC snTopN    := HIX_METRICS_TOP_N

FUNCTION HIX_MetricsInit()

   soMetrics := THixMetrics():New( snTopN )
   l( "Metrics initialized" )

RETURN NIL

FUNCTION HIX_MetricsClose()

   IF soMetrics != NIL

      soMetrics:Dump()
      soMetrics := NIL

   ENDIF

RETURN NIL

FUNCTION HIX_MetricsSetTopN( n )

   snTopN := n

RETURN NIL

FUNCTION HIX_Metric( cName, nValue )

   hb_default( @nValue, 1 )

   IF soMetrics != NIL

      soMetrics:Inc( cName, nValue )

   ENDIF

RETURN NIL

FUNCTION HIX_MetricSet( cName, nValue )

   IF soMetrics != NIL

      soMetrics:Set( cName, nValue )

   ENDIF

RETURN NIL

FUNCTION HIX_MetricDec( cName )

   IF soMetrics != NIL

      soMetrics:Dec( cName )

   ENDIF

RETURN NIL

FUNCTION HIX_MetricGet( cName )

   IF soMetrics != NIL

      RETURN soMetrics:Get( cName )

   ENDIF

RETURN 0

FUNCTION HIX_MetricsJson()

   IF soMetrics != NIL

      RETURN soMetrics:ToJson()

   ENDIF

RETURN "{}"

FUNCTION HIX_MetricsDump()

   IF soMetrics != NIL

      soMetrics:Dump()

   ENDIF

RETURN NIL

FUNCTION HIX_MetricsReset()

   IF soMetrics != NIL

      soMetrics:Reset()

   ENDIF

RETURN NIL

FUNCTION HIX_MetricTiming( nMs, cPath )

   hb_default( @cPath, "" )

   IF soMetrics != NIL

      soMetrics:UpdateTiming( nMs, cPath )

   ENDIF

RETURN NIL

FUNCTION HIX_MetricTimingDyn( nMs, cPath )

   hb_default( @cPath, "" )

   IF soMetrics != NIL

      soMetrics:UpdateTimingDyn( nMs, cPath )

   ENDIF

RETURN NIL

FUNCTION HIX_MetricTimingStat( nMs, cPath )

   hb_default( @cPath, "" )

   IF soMetrics != NIL

      soMetrics:UpdateTimingStat( nMs, cPath )

   ENDIF

RETURN NIL

// ============================================================
CLASS THixMetrics

   DATA hCounters INIT { => }
   DATA aTopDyn   INIT {}
   DATA aTopStat  INIT {}
   DATA nTopN     INIT HIX_METRICS_TOP_N
   DATA oMutex    INIT NIL
   DATA tStart    INIT NIL

   METHOD New( nTopN )
   METHOD Inc( cName, nValue )
   METHOD Dec( cName )
   METHOD Set( cName, nValue )
   METHOD Get( cName )
   METHOD UpdateTiming( nMs, cPath )
   METHOD UpdateTimingDyn( nMs, cPath )
   METHOD UpdateTimingStat( nMs, cPath )
   METHOD ToJson()
   METHOD Dump()
   METHOD Reset()

ENDCLASS

METHOD New( nTopN ) CLASS THixMetrics

   hb_default( @nTopN, HIX_METRICS_TOP_N )
   ::oMutex := hb_mutexCreate()
   ::tStart := hb_DateTime()
   ::nTopN  := nTopN
   ::hCounters[ HIXM_REQUESTS      ] := 0
   ::hCounters[ HIXM_ERRORS        ] := 0
   ::hCounters[ HIXM_ACTIVE_HTTP   ] := 0
   ::hCounters[ HIXM_ACTIVE_WS     ] := 0
   ::hCounters[ HIXM_ACTIVE_OTROS  ] := 0
   ::hCounters[ HIXM_BYTES_IN      ] := 0
   ::hCounters[ HIXM_BYTES_OUT     ] := 0
   ::hCounters[ HIXM_SATURATED     ] := 0
   ::hCounters[ HIXM_UPTIME        ] := 0
   ::hCounters[ HIXM_MEM_USED      ] := 0
   ::hCounters[ HIXM_MEM_PEAK      ] := 0
   ::hCounters[ HIXM_REQ_MS_MAX    ] := 0
   ::hCounters[ HIXM_REQ_MS_AVG    ] := 0
   ::hCounters[ HIXM_REQ_MS_COUNT  ] := 0
   ::hCounters[ HIXM_VCACHE_ENTRIES ] := 0
   ::hCounters[ HIXM_VCACHE_BYTES   ] := 0
   ::hCounters[ HIXM_VCACHE_HITS    ] := 0
   ::hCounters[ HIXM_VCACHE_MISSES  ] := 0

RETURN Self

METHOD Inc( cName, nValue ) CLASS THixMetrics

   hb_mutexLock( ::oMutex )

   IF hb_HHasKey( ::hCounters, cName )

      ::hCounters[ cName ] += nValue
   ELSE
      ::hCounters[ cName ] := nValue

   ENDIF

   hb_mutexUnlock( ::oMutex )

RETURN Self

METHOD Dec( cName ) CLASS THixMetrics

   hb_mutexLock( ::oMutex )

   IF hb_HHasKey( ::hCounters, cName )

      ::hCounters[ cName ] := Max( 0, ::hCounters[ cName ] - 1 )

   ENDIF

   hb_mutexUnlock( ::oMutex )

RETURN Self

METHOD Set( cName, nValue ) CLASS THixMetrics

   hb_mutexLock( ::oMutex )
   ::hCounters[ cName ] := nValue
   hb_mutexUnlock( ::oMutex )

RETURN Self

METHOD Get( cName ) CLASS THixMetrics

   LOCAL nVal := 0

   hb_mutexLock( ::oMutex )

   IF hb_HHasKey( ::hCounters, cName )

      nVal := ::hCounters[ cName ]

   ENDIF

   hb_mutexUnlock( ::oMutex )

RETURN nVal

METHOD UpdateTiming( nMs, cPath ) CLASS THixMetrics

   LOCAL nCount

   hb_default( @cPath, "" )
   hb_mutexLock( ::oMutex )
   nCount := ::hCounters[ HIXM_REQ_MS_COUNT ] + 1
   ::hCounters[ HIXM_REQ_MS_COUNT ] := nCount
   ::hCounters[ HIXM_REQ_MS_AVG ]   := Round( ::hCounters[ HIXM_REQ_MS_AVG ] + ;
      ( nMs - ::hCounters[ HIXM_REQ_MS_AVG ] ) / nCount, 2 )

   IF nMs > ::hCounters[ HIXM_REQ_MS_MAX ]

      ::hCounters[ HIXM_REQ_MS_MAX ] := nMs

   ENDIF

   _HixTopNUpdate( ::aTopDyn, ::nTopN, nMs, cPath )
   hb_mutexUnlock( ::oMutex )

RETURN Self

METHOD UpdateTimingDyn( nMs, cPath ) CLASS THixMetrics

   hb_default( @cPath, "" )
   hb_mutexLock( ::oMutex )
   _HixTopNUpdate( ::aTopDyn, ::nTopN, nMs, cPath )
   hb_mutexUnlock( ::oMutex )

RETURN Self

METHOD UpdateTimingStat( nMs, cPath ) CLASS THixMetrics

   hb_default( @cPath, "" )
   hb_mutexLock( ::oMutex )
   _HixTopNUpdate( ::aTopStat, ::nTopN, nMs, cPath )
   hb_mutexUnlock( ::oMutex )

RETURN Self

METHOD ToJson() CLASS THixMetrics

   LOCAL cJson  := "{"
   LOCAL lFirst := .T.
   LOCAL lFirstE, cKey, hEntry

   ::hCounters[ HIXM_UPTIME ] := Int( ( hb_DateTime() - ::tStart ) * 86400 )
   hb_mutexLock( ::oMutex )

   FOR EACH cKey IN hb_HKeys( ::hCounters )

      IF ! lFirst ; cJson += "," ; ENDIF

      cJson += Chr( 34 ) + cKey + Chr( 34 ) + ":" + hb_NToS( ::hCounters[ cKey ] )
      lFirst := .F.

   NEXT

   cJson   += "," + Chr( 34 ) + HIXM_REQ_SLOWEST_DYN + Chr( 34 ) + ":["
   lFirstE := .T.

   FOR EACH hEntry IN ::aTopDyn

      IF ! lFirstE ; cJson += "," ; ENDIF

      cJson += '{"ms":' + hb_NToS( hEntry[ "ms" ] ) + ;
         ',"at":"'   + hEntry[ "at"   ] + '"' + ;
         ',"path":"' + hEntry[ "path" ] + '"}'
      lFirstE := .F.

   NEXT

   cJson   += "]," + Chr( 34 ) + HIXM_REQ_SLOWEST_STAT + Chr( 34 ) + ":["
   lFirstE := .T.

   FOR EACH hEntry IN ::aTopStat

      IF ! lFirstE ; cJson += "," ; ENDIF

      cJson += '{"ms":' + hb_NToS( hEntry[ "ms" ] ) + ;
         ',"at":"'   + hEntry[ "at"   ] + '"' + ;
         ',"path":"' + hEntry[ "path" ] + '"}'
      lFirstE := .F.

   NEXT

   cJson += "]"
   hb_mutexUnlock( ::oMutex )
   cJson += "}"

RETURN cJson

METHOD Reset() CLASS THixMetrics

   hb_mutexLock( ::oMutex )
   ::hCounters[ HIXM_REQUESTS      ] := 0
   ::hCounters[ HIXM_ERRORS        ] := 0
   ::hCounters[ HIXM_BYTES_IN      ] := 0
   ::hCounters[ HIXM_BYTES_OUT     ] := 0
   ::hCounters[ HIXM_SATURATED     ] := 0
   ::hCounters[ HIXM_REQ_MS_MAX    ] := 0
   ::hCounters[ HIXM_REQ_MS_AVG    ] := 0
   ::hCounters[ HIXM_REQ_MS_COUNT  ] := 0
   ::hCounters[ HIXM_VCACHE_HITS   ] := 0
   ::hCounters[ HIXM_VCACHE_MISSES ] := 0
   ::aTopDyn  := {}
   ::aTopStat := {}
   ::tStart   := hb_DateTime()
   hb_mutexUnlock( ::oMutex )
   l( "Metrics reset" )

RETURN Self

METHOD Dump() CLASS THixMetrics

   LOCAL nUp := Int( ( hb_DateTime() - ::tStart ) * 86400 )
   LOCAL hEntry

   l( "=== Metrics ===============================" )
   l( "  uptime=" + hb_NToS( nUp ) + "s" + ;
      "  requests=" + hb_NToS( ::Get( HIXM_REQUESTS ) ) + ;
      "  errors="   + hb_NToS( ::Get( HIXM_ERRORS   ) ) )
   l( "  active_http="  + hb_NToS( ::Get( HIXM_ACTIVE_HTTP  ) ) + ;
      "  active_ws="    + hb_NToS( ::Get( HIXM_ACTIVE_WS    ) ) + ;
      "  active_otros=" + hb_NToS( ::Get( HIXM_ACTIVE_OTROS ) ) )
   l( "  bytes_in="    + hb_NToS( ::Get( HIXM_BYTES_IN  ) ) + ;
      "  bytes_out="   + hb_NToS( ::Get( HIXM_BYTES_OUT ) ) + ;
      "  saturations=" + hb_NToS( ::Get( HIXM_SATURATED ) ) )
   l( "  req_ms_max=" + hb_NToS( ::Get( HIXM_REQ_MS_MAX   ) ) + "ms" + ;
      "  req_ms_avg=" + hb_NToS( ::Get( HIXM_REQ_MS_AVG   ) ) + "ms" + ;
      "  req_count="  + hb_NToS( ::Get( HIXM_REQ_MS_COUNT ) ) )
   l( "  top slowest dyn (prg/hrb):" )

   FOR EACH hEntry IN ::aTopDyn

      l( "    " + hb_NToS( hEntry[ "ms" ] ) + "ms  " + hEntry[ "at" ] + "  " + hEntry[ "path" ] )

   NEXT

   l( "  top slowest stat (html/js/img/...):" )

   FOR EACH hEntry IN ::aTopStat

      l( "    " + hb_NToS( hEntry[ "ms" ] ) + "ms  " + hEntry[ "at" ] + "  " + hEntry[ "path" ] )

   NEXT

   l( "===========================================" )

RETURN Self

// ============================================================
// Inserta nMs/cPath en aList manteniendo top-N desc.
// Llamar siempre con el mutex ya tomado.
// ============================================================
STATIC FUNCTION _HixTopNUpdate( aList, nTopN, nMs, cPath )

   LOCAL hEntry

   IF Len( aList ) < nTopN .OR. nMs > ATail( aList )[ "ms" ]

      hEntry := { => }
      hEntry[ "ms"   ] := nMs
      hEntry[ "at"   ] := hb_TToC( hb_DateTime(), "YYYY-MM-DD", "HH:MM:SS" )
      hEntry[ "path" ] := cPath
      AAdd( aList, hEntry )
      ASort( aList, , , {| a, b | a[ "ms" ] > b[ "ms" ] } )

      IF Len( aList ) > nTopN

         ASize( aList, nTopN )

      ENDIF

   ENDIF

RETURN NIL
