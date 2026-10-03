/*-----------------------------------------------------------
  File ......: api_mysql_pool_stats.prg
  Author.....: Charly 9000
  Created....: 2026-10-03
  Modified...: 2026-10-03
  Version....: 1.0.0
  Description: Returns current WDO pool stats for the "mysql"
               pool without acquiring a connection or probing.
               Lightweight — safe to poll frequently from the UI.
  Usage      : GET /api/mysql-pool-stats
               Response: { ok, registered, size, busy, free, closed }
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL hStats := WDO_PoolStats( "mysql" )

   IF hStats == NIL
      USendJson( { "ok" => .T., "registered" => .F., ;
                   "size" => 0, "busy" => 0, "free" => 0, "closed" => .T. } )
      RETURN NIL
   ENDIF

   USendJson( { ;
      "ok"         => .T., ;
      "registered" => .T., ;
      "size"       => hStats[ "size"   ], ;
      "busy"       => hStats[ "busy"   ], ;
      "free"       => hStats[ "free"   ], ;
      "closed"     => hStats[ "closed" ] } )

RETURN NIL
