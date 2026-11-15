/*-----------------------------------------------------------
  File ......: api_mysql_bench.prg
  Author.....: Charly 9000
  Created....: 2026-10-01
  Modified...: 2026-10-01
  Version....: 1.0.0
  Description: One-shot MySQL query endpoint used by the bench
               screen. Each call is a single realistic SELECT
               through the WDO pool. The client stresses this
               endpoint with N concurrent / M total requests and
               measures throughput + latency on its side.
  Usage      : POST /api/mysql-bench  { "limit": 100 }
               Response: { ok, took_ms, rows_returned, source }
  Notes      : Prefers _hix_bench (populated by Test D). Falls
               back to information_schema.COLUMNS so the demo
               works even on a bare DB. source="bench"|"fallback".
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL oConn
   LOCAL oStmt
   LOCAL nLimit  := Max( 1, Min( 1000, Int( UPost( "limit", 100 ) ) ) )
   LOCAL cSource := "employees"
   LOCAL cSql
   LOCAL nT0     := hb_MilliSeconds()
   LOCAL nRows   := 0
   LOCAL nOff
   LOCAL oError
   LOCAL hStats

   HIX_Dbg( "bench: enter limit=" + hb_NToS( nLimit ) )

   oConn := WDO_Get( "mysql" )

   IF oConn == NIL
      HIX_Dbg( "bench: WDO_Get returned NIL (pool unavailable)" )
      hStats := WDO_PoolStats( "mysql" )
      _l( "[mysql:bench] pool unavailable" + ;
         iif( HB_ISHASH( hStats ), ;
              " busy=" + hb_NToS( hStats["busy"] ) + "/" + hb_NToS( hStats["size"] ), "" ), 4, "mysql" )
      USendJson( { "ok" => .F., "error" => "mysql pool unavailable" }, 503 )
      RETURN NIL
   ENDIF

   HIX_Dbg( "bench: got conn" )

   //  Random PK lookup against the `employees` sample DB (datacharmer).
   //  emp_no range is 10001..499999 (300k rows). WHERE emp_no BETWEEN
   //  is a PK range scan -- O(log N) seek + sequential read, sub-ms.
   nOff := hb_RandomInt( 10001, 499999 - nLimit )
   cSql := "/*+ MAX_EXECUTION_TIME(3000) */ " + ;
           "SELECT emp_no, first_name, last_name, hire_date FROM employees " + ;
           "WHERE emp_no BETWEEN " + hb_NToS( nOff ) + " AND " + ;
           hb_NToS( nOff + nLimit - 1 )

   TRY

      HIX_Dbg( "bench: sql primary = " + cSql )
      oStmt := oConn:Query( cSql )
      HIX_Dbg( "bench: primary stmt=" + iif( oStmt == NIL, "NIL", ;
               "ok=" + iif( oStmt:lError, "F err=" + oStmt:cError, "T" ) ) )

      IF oStmt == NIL .OR. oStmt:lError
         //  _hix_bench not populated yet -- fallback to a table that
         //  always exists. ORDER BY RAND() keeps the server honest.
         IF oStmt != NIL ; oStmt:Free() ; ENDIF
         cSource := "fallback"
         HIX_Dbg( "bench: falling back to information_schema" )
         cSql := "SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME " + ;
                 "FROM information_schema.COLUMNS " + ;
                 "WHERE TABLE_SCHEMA NOT IN ('mysql','performance_schema','sys') " + ;
                 "ORDER BY RAND() LIMIT " + hb_NToS( nLimit )
         HIX_Dbg( "bench: sql fallback = " + cSql )
         oStmt := oConn:Query( cSql )
         HIX_Dbg( "bench: fallback stmt=" + iif( oStmt == NIL, "NIL", ;
                  "ok=" + iif( oStmt:lError, "F err=" + oStmt:cError, "T" ) ) )
      ENDIF

      IF oStmt == NIL .OR. oStmt:lError
         HIX_Dbg( "bench: giving up, returning 500" )
         IF oStmt != NIL
            USendJson( { "ok" => .F., "error" => oStmt:cError, ;
                         "source" => cSource }, 500 )
            oStmt:Free()
         ELSE
            USendJson( { "ok" => .F., "error" => "query returned NIL", ;
                         "source" => cSource }, 500 )
         ENDIF
      ELSE
         nRows := oStmt:Count()
         HIX_Dbg( "bench: rows=" + hb_NToS( nRows ) + " source=" + cSource + ;
                  " took_ms=" + hb_NToS( hb_MilliSeconds() - nT0 ) )
         oStmt:Free()
         USendJson( { ;
            "ok"            => .T.,  ;
            "took_ms"       => hb_MilliSeconds() - nT0, ;
            "rows_returned" => nRows, ;
            "source"        => cSource } )
      ENDIF

   CATCH oError
      HIX_Dbg( "api_mysql_bench error: " + oError:description )
      _l( "[mysql:bench] exception: " + oError:description, 4, "mysql" )
      USendError( 500, oError:description )
   FINALLY
      oConn:Close()
   END

RETURN NIL
