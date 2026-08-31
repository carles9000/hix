/*-----------------------------------------------------------
  File ......: api_serverinfo.prg
  Author.....: Charly 9000
  Created....: 2026-08-18
  Modified...: 2026-08-18
  Version....: 1.1.0
  Description: Server introspection webservice. Collects live
               metrics, memory, timing and boot log into a
               single JSON payload for the /server-info screen.
  Usage      : GET /api/server-info
  Notes      : Flat single function on purpose — dynamic HRB
               controllers keep no static helpers and no
               #include. Memory() returns 0 unless Harbour was
               built with HB_FM_STATISTICS.
 -----------------------------------------------------------*/

// From hbmemory.ch — inlined, dynamic controllers do not include

#define MEM_USED     1001
#define MEM_USEDMAX  1002

FUNCTION Main()

   LOCAL hMet   := { => }
   LOCAL hOut   := { => }
   LOCAL cJson  := ''
   LOCAL nUsed  := 0
   LOCAL nPeak  := 0
   LOCAL oError

   BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }

      cJson := HIX_MetricsJson()
      hMet  := hb_jsonDecode( cJson )

      IF ! HB_ISHASH( hMet )
         hMet := { => }
      ENDIF

      nUsed := Memory( MEM_USED )
      nPeak := Memory( MEM_USEDMAX )

   RECOVER USING oError

      hMet := { => }

   END SEQUENCE

   hOut[ 'ok' ] := .T.

   hOut[ 'server' ] := { ;
      'name'       => UConfig( 'server', 'name', 'HIX' ),      ;
      'host'       => UConfig( 'server', 'host', '' ),         ;
      'port'       => UConfig( 'server', 'port', 0 ),          ;
      'mode'       => UConfig( 'server', 'mode', '' ),         ;
      'env'        => UConfig( 'app', 'env', '' ),             ;
      'gzip'       => UConfig( 'server', 'gzip', .F. ),        ;
      'hixstyle'   => UConfig( 'hixstyle', 'enabled', .F. ),   ;
      'running'    => HIX_ServerIsRunning(),                   ;
      'monitor'    => HIX_IsRunning(),                         ;
      'uptime_sec' => hb_HGetDef( hMet, 'uptimesec', 0 )       }

   hOut[ 'system' ] := { ;
      'harbour'  => Version(),      ;
      'compiler' => hb_Compiler(),  ;
      'os'       => OS(),           ;
      'host'     => hb_GetEnv( 'HOSTNAME', 'localhost' ), ;
      'date'     => DToC( Date() ), ;
      'time'     => Time()          }

   hOut[ 'memory' ] := { ;
      'used_now' => nUsed,                            ;
      'peak_now' => nPeak,                            ;
      'used_mon' => hb_HGetDef( hMet, 'memused', 0 ), ;
      'peak_mon' => hb_HGetDef( hMet, 'mempeak', 0 )  }

   hOut[ 'traffic' ] := { ;
      'requests'     => hb_HGetDef( hMet, 'requests',    0 ), ;
      'errors'       => hb_HGetDef( hMet, 'errors',      0 ), ;
      'active_http'  => hb_HGetDef( hMet, 'activehttp',  0 ), ;
      'active_ws'    => hb_HGetDef( hMet, 'activews',    0 ), ;
      'active_otros' => hb_HGetDef( hMet, 'activeotros', 0 ), ;
      'bytes_in'     => hb_HGetDef( hMet, 'bytesin',     0 ), ;
      'bytes_out'    => hb_HGetDef( hMet, 'bytesout',    0 ), ;
      'saturated'    => hb_HGetDef( hMet, 'saturated',   0 )  }

   // Pool sizes from hix.json — each connection holds one worker,
   // so these are the real concurrency ceilings per protocol

   hOut[ 'limits' ] := { ;
      'http'    => UConfig( 'pool_http', 'workers',      0 ), ;
      'ws'      => UConfig( 'pool_ws',   'workers',      0 ), ;
      'sse'     => UConfig( 'pool_rest', 'workers_sse',  0 ), ;
      'maxconn' => UConfig( 'server',    'maxconn',      0 )  }

   hOut[ 'timing' ] := { ;
      'ms_max'   => hb_HGetDef( hMet, 'req_ms_max',      0 ),  ;
      'ms_avg'   => hb_HGetDef( hMet, 'req_ms_avg',      0 ),  ;
      'count'    => hb_HGetDef( hMet, 'req_ms_count',    0 ),  ;
      'max_at'   => hb_HGetDef( hMet, 'req_ms_max_at',   '' ), ;
      'max_path' => hb_HGetDef( hMet, 'req_ms_max_path', '' )  }

   hOut[ 'slowest' ] := { ;
      'dyn'  => hb_HGetDef( hMet, 'req_slowest_dyn',  {} ), ;
      'stat' => hb_HGetDef( hMet, 'req_slowest_stat', {} )  }

   hOut[ 'boot' ] := { ;
      'loaders'     => HIX_BootLogSection( 'loaders' ),     ;
      'middlewares' => HIX_BootLogSection( 'middlewares' ), ;
      'routes'      => HIX_BootLogSection( 'routes' ),      ;
      'config'      => HIX_BootLogSection( 'config' )       }

   IF oError != NIL
      hOut[ 'ok'    ] := .F.
      hOut[ 'error' ] := oError:description
   ENDIF

RETURN USendJson( hOut )
