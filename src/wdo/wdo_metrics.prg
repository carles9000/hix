/*-----------------------------------------------------------
  File ......: wdo_metrics.prg
  Author.....: Charly 9000
  Created....: 2026-09-30
  Modified...: 2026-09-30
  Version....: 1.0.0
  Description: WDO metrics -- thread-safe performance counters for
               the MySQL / MariaDB driver + pool. Mirrors the shape
               of hix_metrics.prg but scoped to database traffic.

               Exposes: WDO_MetricsInit, WDO_MetricsClose,
               WDO_Metric, WDO_MetricSet, WDO_MetricDec,
               WDO_MetricGet, WDO_MetricsReset, WDO_MetricsJson,
               WDO_MetricsDump, WDO_MetricQuery, WDO_MetricAcquire,
               WDO_MetricsIsActive, WDO_MetricsSetTopN.

               Opt-in via www/config.json:
                 { "sets": { "wdo_metrics": true, "wdo_metrics_top_n": 10 } }

               When soMetrics == NIL every entry point returns
               immediately -- zero overhead when the feature is off.
  Usage      : WDO_MetricsInit()
               WDO_MetricQuery( "mysql", cSql, nMs, NIL )   -- driver hook
               cJson := WDO_MetricsJson()
  Notes      : Auto-source detection walks the ProcName stack up to
               20 frames, skipping any WDO_* / _HIXWDO_* / *_Metric*
               frame so the caller reported in top-N is the actual
               controller / handler that fired the query.
  License....: MPL 2.0
 -----------------------------------------------------------*/

#include 'hbclass.ch'
#include 'hix_logger.ch'
#include 'wdo_metrics.ch'

STATIC soMetrics := NIL
STATIC snTopN    := WDO_METRICS_TOP_N


//	=======================================================  //
//  Public API (paralela a HIX_Metric*)
//	=======================================================  //

FUNCTION WDO_MetricsInit( nTopN )

   IF soMetrics != NIL
      RETU NIL
   ENDIF

   hb_default( @nTopN, snTopN )
   soMetrics := WDO_Metrics():New( nTopN )
   l( "WDO metrics initialized (top_n=" + hb_NToS( nTopN ) + ")" )

RETU NIL


FUNCTION WDO_MetricsClose()

   IF soMetrics != NIL
      soMetrics:Dump()
      soMetrics := NIL
   ENDIF

RETU NIL


FUNCTION WDO_MetricsIsActive()
RETU soMetrics != NIL


FUNCTION WDO_MetricsSetTopN( n )

   IF n != NIL .AND. n > 0
      snTopN := n
      IF soMetrics != NIL
         soMetrics:nTopN := n
      ENDIF
   ENDIF

RETU NIL


FUNCTION WDO_Metric( cName, nValue )

   hb_default( @nValue, 1 )

   IF soMetrics != NIL
      soMetrics:Inc( cName, nValue )
   ENDIF

RETU NIL


FUNCTION WDO_MetricSet( cName, nValue )

   IF soMetrics != NIL
      soMetrics:Set( cName, nValue )
   ENDIF

RETU NIL


FUNCTION WDO_MetricDec( cName )

   IF soMetrics != NIL
      soMetrics:Dec( cName )
   ENDIF

RETU NIL


FUNCTION WDO_MetricGet( cName )

   IF soMetrics != NIL
      RETU soMetrics:Get( cName )
   ENDIF

RETU 0


FUNCTION WDO_MetricsJson()

   IF soMetrics != NIL
      RETU soMetrics:ToJson()
   ENDIF

RETU "{}"


FUNCTION WDO_MetricsDump()

   IF soMetrics != NIL
      soMetrics:Dump()
   ENDIF

RETU NIL


FUNCTION WDO_MetricsReset()

   IF soMetrics != NIL
      soMetrics:Reset()
   ENDIF

RETU NIL


//  ---------------------------------------------------------
//  Instrumenta una query completa. cKey = pool key ("mysql",
//  "analytics", "-" para conexiones fuera del pool).
//  cSource NIL => auto-detección vía ProcName walk.
//  ---------------------------------------------------------
FUNCTION WDO_MetricQuery( cKey, cSql, nMs, cSource )

   LOCAL cType

   IF soMetrics == NIL
      RETU NIL
   ENDIF

   hb_default( @cKey,   "-" )
   hb_default( @cSql,   "" )
   hb_default( @nMs,    0 )

   IF cSource == NIL
      cSource := _WdoSourceFromStack()
   ENDIF

   cType := _WdoSqlType( cSql )

   soMetrics:UpdateQuery( cKey, cSql, nMs, cSource, cType )

RETU NIL


//  ---------------------------------------------------------
//  Instrumenta el timing de un Acquire del pool.
//  ---------------------------------------------------------
FUNCTION WDO_MetricAcquire( nMs )

   IF soMetrics == NIL
      RETU NIL
   ENDIF

   hb_default( @nMs, 0 )

   soMetrics:UpdateAcquire( nMs )

RETU NIL


//	=======================================================  //
//  Class WDO_Metrics
//	=======================================================  //

CLASS WDO_Metrics

   DATA hCounters INIT { => }
   DATA aTopSlow  INIT {}
   DATA nTopN     INIT WDO_METRICS_TOP_N
   DATA oMutex    INIT NIL
   DATA tStart    INIT NIL

   METHOD New( nTopN )
   METHOD Inc( cName, nValue )
   METHOD Dec( cName )
   METHOD Set( cName, nValue )
   METHOD Get( cName )
   METHOD UpdateQuery( cKey, cSql, nMs, cSource, cType )
   METHOD UpdateAcquire( nMs )
   METHOD ToJson()
   METHOD Dump()
   METHOD Reset()

ENDCLASS


METHOD New( nTopN ) CLASS WDO_Metrics

   hb_default( @nTopN, WDO_METRICS_TOP_N )

   ::oMutex := hb_mutexCreate()
   ::tStart := hb_DateTime()
   ::nTopN  := nTopN

   ::hCounters[ WDOM_QUERIES_TOTAL      ] := 0
   ::hCounters[ WDOM_QUERIES_SELECT     ] := 0
   ::hCounters[ WDOM_QUERIES_INSERT     ] := 0
   ::hCounters[ WDOM_QUERIES_UPDATE     ] := 0
   ::hCounters[ WDOM_QUERIES_DELETE     ] := 0
   ::hCounters[ WDOM_QUERIES_PREPARE    ] := 0
   ::hCounters[ WDOM_QUERIES_EXECUTE    ] := 0
   ::hCounters[ WDOM_QUERIES_OTHER      ] := 0
   ::hCounters[ WDOM_QUERIES_ERRORS     ] := 0
   ::hCounters[ WDOM_QUERY_MS_MAX       ] := 0
   ::hCounters[ WDOM_QUERY_MS_AVG       ] := 0
   ::hCounters[ WDOM_QUERY_MS_COUNT     ] := 0
   ::hCounters[ WDOM_ACQUIRES_TOTAL     ] := 0
   ::hCounters[ WDOM_ACQUIRES_TIMEOUT   ] := 0
   ::hCounters[ WDOM_RELEASES_TOTAL     ] := 0
   ::hCounters[ WDOM_RELEASES_RECLAIMED ] := 0
   ::hCounters[ WDOM_ACTIVE_CONN        ] := 0
   ::hCounters[ WDOM_ACQUIRE_MS_MAX     ] := 0
   ::hCounters[ WDOM_ACQUIRE_MS_AVG     ] := 0
   ::hCounters[ WDOM_ACQUIRE_MS_COUNT   ] := 0

RETU SELF


METHOD Inc( cName, nValue ) CLASS WDO_Metrics

   hb_mutexLock( ::oMutex )
   ::hCounters[ cName ] := hb_HGetDef( ::hCounters, cName, 0 ) + nValue
   hb_mutexUnlock( ::oMutex )

RETU SELF


METHOD Dec( cName ) CLASS WDO_Metrics

   hb_mutexLock( ::oMutex )
   IF hb_HHasKey( ::hCounters, cName )
      ::hCounters[ cName ] := Max( 0, ::hCounters[ cName ] - 1 )
   ENDIF
   hb_mutexUnlock( ::oMutex )

RETU SELF


METHOD Set( cName, nValue ) CLASS WDO_Metrics

   hb_mutexLock( ::oMutex )
   ::hCounters[ cName ] := nValue
   hb_mutexUnlock( ::oMutex )

RETU SELF


METHOD Get( cName ) CLASS WDO_Metrics

   LOCAL nVal := 0

   hb_mutexLock( ::oMutex )
   IF hb_HHasKey( ::hCounters, cName )
      nVal := ::hCounters[ cName ]
   ENDIF
   hb_mutexUnlock( ::oMutex )

RETU nVal


//  Registra 1 query: bumps counters + running avg/max + top-N.
METHOD UpdateQuery( cKey, cSql, nMs, cSource, cType ) CLASS WDO_Metrics

   LOCAL nCount, cKeyType, cKeyPool

   hb_mutexLock( ::oMutex )

   //  counters totales por tipo
   ::hCounters[ WDOM_QUERIES_TOTAL ] := ;
      hb_HGetDef( ::hCounters, WDOM_QUERIES_TOTAL, 0 ) + 1

   cKeyType := "queries_" + cType
   ::hCounters[ cKeyType ] := hb_HGetDef( ::hCounters, cKeyType, 0 ) + 1

   //  counter por pool (queries_by_pool_<key>)
   cKeyPool := "queries_by_pool_" + Lower( cKey )
   ::hCounters[ cKeyPool ] := hb_HGetDef( ::hCounters, cKeyPool, 0 ) + 1

   //  running avg + max + count
   nCount := ::hCounters[ WDOM_QUERY_MS_COUNT ] + 1
   ::hCounters[ WDOM_QUERY_MS_COUNT ] := nCount
   ::hCounters[ WDOM_QUERY_MS_AVG ]   := Round( ::hCounters[ WDOM_QUERY_MS_AVG ] + ;
      ( nMs - ::hCounters[ WDOM_QUERY_MS_AVG ] ) / nCount, 2 )

   IF nMs > ::hCounters[ WDOM_QUERY_MS_MAX ]
      ::hCounters[ WDOM_QUERY_MS_MAX ] := nMs
   ENDIF

   //  top-N slowest (con SQL recortado)
   _WdoTopNUpdate( ::aTopSlow, ::nTopN, nMs, cSql, cSource, cKey, cType )

   hb_mutexUnlock( ::oMutex )

RETU SELF


METHOD UpdateAcquire( nMs ) CLASS WDO_Metrics

   LOCAL nCount

   hb_mutexLock( ::oMutex )

   nCount := ::hCounters[ WDOM_ACQUIRE_MS_COUNT ] + 1
   ::hCounters[ WDOM_ACQUIRE_MS_COUNT ] := nCount
   ::hCounters[ WDOM_ACQUIRE_MS_AVG ]   := Round( ::hCounters[ WDOM_ACQUIRE_MS_AVG ] + ;
      ( nMs - ::hCounters[ WDOM_ACQUIRE_MS_AVG ] ) / nCount, 2 )

   IF nMs > ::hCounters[ WDOM_ACQUIRE_MS_MAX ]
      ::hCounters[ WDOM_ACQUIRE_MS_MAX ] := nMs
   ENDIF

   hb_mutexUnlock( ::oMutex )

RETU SELF


METHOD ToJson() CLASS WDO_Metrics

   LOCAL hOut := { => }
   LOCAL cKey, aList := {}, hEntry, hCopy

   hb_mutexLock( ::oMutex )

   FOR EACH cKey IN hb_HKeys( ::hCounters )
      hOut[ cKey ] := ::hCounters[ cKey ]
   NEXT

   //  aTopSlow: clonar entradas para no soltar el mutex con refs vivas
   FOR EACH hEntry IN ::aTopSlow
      hCopy := { => }
      hCopy[ "ms"     ] := hEntry[ "ms"     ]
      hCopy[ "at"     ] := hEntry[ "at"     ]
      hCopy[ "type"   ] := hEntry[ "type"   ]
      hCopy[ "pool"   ] := hEntry[ "pool"   ]
      hCopy[ "source" ] := hEntry[ "source" ]
      hCopy[ "sql"    ] := hEntry[ "sql"    ]
      AAdd( aList, hCopy )
   NEXT

   hOut[ WDOM_SLOWEST ] := aList
   hOut[ "uptime_sec" ] := Int( ( hb_DateTime() - ::tStart ) * 86400 )

   hb_mutexUnlock( ::oMutex )

RETU hb_JsonEncode( hOut )


METHOD Reset() CLASS WDO_Metrics

   LOCAL cKey

   hb_mutexLock( ::oMutex )
   FOR EACH cKey IN hb_HKeys( ::hCounters )
      ::hCounters[ cKey ] := 0
   NEXT
   ::aTopSlow := {}
   ::tStart   := hb_DateTime()
   hb_mutexUnlock( ::oMutex )
   l( "WDO metrics reset" )

RETU SELF


METHOD Dump() CLASS WDO_Metrics

   LOCAL nUp := Int( ( hb_DateTime() - ::tStart ) * 86400 )
   LOCAL hEntry, i

   l( "=== WDO Metrics ==========================" )
   l( "  uptime="        + hb_NToS( nUp ) + "s" + ;
      "  queries_total=" + hb_NToS( ::Get( WDOM_QUERIES_TOTAL ) ) + ;
      "  errors="        + hb_NToS( ::Get( WDOM_QUERIES_ERRORS ) ) )
   l( "  select=" + hb_NToS( ::Get( WDOM_QUERIES_SELECT ) ) + ;
      "  insert=" + hb_NToS( ::Get( WDOM_QUERIES_INSERT ) ) + ;
      "  update=" + hb_NToS( ::Get( WDOM_QUERIES_UPDATE ) ) + ;
      "  delete=" + hb_NToS( ::Get( WDOM_QUERIES_DELETE ) ) + ;
      "  other="  + hb_NToS( ::Get( WDOM_QUERIES_OTHER  ) ) )
   l( "  prepare=" + hb_NToS( ::Get( WDOM_QUERIES_PREPARE ) ) + ;
      "  execute=" + hb_NToS( ::Get( WDOM_QUERIES_EXECUTE ) ) )
   l( "  query_ms_max=" + hb_NToS( ::Get( WDOM_QUERY_MS_MAX ) ) + "ms" + ;
      "  query_ms_avg=" + hb_NToS( ::Get( WDOM_QUERY_MS_AVG ) ) + "ms" + ;
      "  count="        + hb_NToS( ::Get( WDOM_QUERY_MS_COUNT ) ) )
   l( "  acquires=" + hb_NToS( ::Get( WDOM_ACQUIRES_TOTAL   ) ) + ;
      "  timeouts=" + hb_NToS( ::Get( WDOM_ACQUIRES_TIMEOUT ) ) + ;
      "  reclaimed=" + hb_NToS( ::Get( WDOM_RELEASES_RECLAIMED ) ) )
   l( "  top slowest:" )

   i := 0
   FOR EACH hEntry IN ::aTopSlow
      i++
      IF i > 5 ; EXIT ; ENDIF
      l( "    " + hb_NToS( hEntry[ "ms" ] ) + "ms  " + ;
         hEntry[ "at"     ] + "  " + ;
         hEntry[ "type"   ] + "  [" + hEntry[ "pool" ] + "]  " + ;
         hEntry[ "source" ] + "  " + hEntry[ "sql" ] )
   NEXT

   l( "==========================================" )

RETU SELF


//	=======================================================  //
//  Static helpers
//	=======================================================  //

//  ---------------------------------------------------------
//  Inserta { ms, at, sql, source, pool, type } en aList
//  manteniendo top-N desc por ms. Llamar con el mutex tomado.
//  ---------------------------------------------------------
STATIC FUNCTION _WdoTopNUpdate( aList, nTopN, nMs, cSql, cSource, cPool, cType )

   LOCAL hEntry

   IF Len( aList ) < nTopN .OR. nMs > ATail( aList )[ "ms" ]

      hEntry             := { => }
      hEntry[ "ms"     ] := nMs
      hEntry[ "at"     ] := hb_TToC( hb_DateTime(), "YYYY-MM-DD", "HH:MM:SS" )
      hEntry[ "sql"    ] := _WdoCropSql( cSql )
      hEntry[ "source" ] := cSource
      hEntry[ "pool"   ] := cPool
      hEntry[ "type"   ] := cType

      AAdd( aList, hEntry )
      ASort( aList, , , {| a, b | a[ "ms" ] > b[ "ms" ] } )

      IF Len( aList ) > nTopN
         ASize( aList, nTopN )
      ENDIF

   ENDIF

RETU NIL


//  ---------------------------------------------------------
//  Recorta SQL a WDO_METRICS_SQL_CROP chars y colapsa
//  saltos/multi-espacio para una entrada de top-N legible.
//  ---------------------------------------------------------
STATIC FUNCTION _WdoCropSql( cSql )

   LOCAL c := AllTrim( cSql )

   c := StrTran( c, Chr( 13 ), " " )
   c := StrTran( c, Chr( 10 ), " " )
   c := StrTran( c, Chr( 9  ), " " )

   DO WHILE "  " $ c
      c := StrTran( c, "  ", " " )
   ENDDO

   IF Len( c ) > WDO_METRICS_SQL_CROP
      c := Left( c, WDO_METRICS_SQL_CROP ) + "..."
   ENDIF

RETU c


//  ---------------------------------------------------------
//  Clasifica el SQL por su primer token significativo.
//  Case-insensitive, tolera whitespace / newline / comentarios
//  al inicio -- si empieza con /* ... */ o -- ... salta hasta
//  encontrar código real.
//  ---------------------------------------------------------
STATIC FUNCTION _WdoSqlType( cSql )

   LOCAL c := _WdoStripLeading( cSql )
   LOCAL cUp := Upper( c )

   DO CASE
   CASE Left( cUp, 7 ) == "SELECT "   ; RETU "select"
   CASE Left( cUp, 7 ) == "INSERT "   ; RETU "insert"
   CASE Left( cUp, 7 ) == "UPDATE "   ; RETU "update"
   CASE Left( cUp, 7 ) == "DELETE "   ; RETU "delete"
   CASE Left( cUp, 8 ) == "PREPARE "  ; RETU "prepare"
   CASE Left( cUp, 8 ) == "EXECUTE "  ; RETU "execute"
   CASE Left( cUp, 6 ) == "WITH ("    ; RETU "select"    //  CTE => select
   CASE Left( cUp, 5 ) == "WITH "     ; RETU "select"
   ENDCASE

RETU "other"


STATIC FUNCTION _WdoStripLeading( cSql )

   LOCAL c := cSql
   LOCAL cCh
   LOCAL nLen, i, nEnd

   IF c == NIL ; RETU "" ; ENDIF

   //  Loop: quitar whitespace + comentarios al inicio
   DO WHILE .T.

      c    := LTrim( c )
      nLen := Len( c )

      IF nLen == 0 ; RETU "" ; ENDIF

      cCh := SubStr( c, 1, 1 )

      IF cCh == Chr( 13 ) .OR. cCh == Chr( 10 ) .OR. cCh == Chr( 9 )
         c := SubStr( c, 2 )
         LOOP
      ENDIF

      //  -- comment
      IF nLen >= 2 .AND. SubStr( c, 1, 2 ) == "--"
         //  hasta fin de línea
         i := At( Chr( 10 ), c )
         IF i == 0 ; RETU "" ; ENDIF
         c := SubStr( c, i + 1 )
         LOOP
      ENDIF

      //  /* ... */ comment
      IF nLen >= 2 .AND. SubStr( c, 1, 2 ) == "/*"
         nEnd := At( "*/", c )
         IF nEnd == 0 ; RETU "" ; ENDIF
         c := SubStr( c, nEnd + 2 )
         LOOP
      ENDIF

      EXIT
   ENDDO

RETU c


//  ---------------------------------------------------------
//  Walk-stack para saber quién disparó la query. Devuelve el
//  primer frame que no vive dentro de wdo_metrics / WDO_* /
//  _HIXWDO_* / *_Metric*. Formato: "FUNC:LINE".
//  ---------------------------------------------------------
STATIC FUNCTION _WdoSourceFromStack()

   LOCAL n, cProc, cUp

   FOR n := 2 TO 20
      cProc := ProcName( n )
      IF Empty( cProc ) ; EXIT ; ENDIF
      cUp := Upper( cProc )

      //  Skip frames WDO_* / _HIXWDO_* / *_METRIC* / _WDO*
      IF Left( cUp, 4 ) == "WDO_"     .OR. ;
         Left( cUp, 8 ) == "_HIXWDO_" .OR. ;
         Left( cUp, 4 ) == "_WDO"     .OR. ;
         "_METRIC" $ cUp .OR. ;
         cUp == "WDO_METRICS"
         LOOP
      ENDIF

      //  Skip driver class methods
      IF Left( cUp, 11 ) == "WDO_MYSQL:"     .OR. ;
         Left( cUp, 14 ) == "WDO_MYSQLSTMT:" .OR. ;
         Left( cUp, 9  ) == "WDO_POOL:"
         LOOP
      ENDIF

      RETU cProc + ":" + hb_NToS( ProcLine( n ) )
   NEXT

RETU "unknown"
