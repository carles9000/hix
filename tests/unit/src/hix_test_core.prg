/*-----------------------------------------------------------
  File ......: hix_test_core.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — Core (Config, Logger, Metrics, Error, Protocol, INI)
  Usage      : Route GET /api/test/core -> USendJson( HIX_TestCore_Run() )
 -----------------------------------------------------------*/
#include "hix_logger.ch"

// -- Mini-framework (thread-safe via hCtx local por request) ----

// -- Punto de entrada publico ------------------------------------

FUNCTION HIX_TestCore_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   HIX_LoggerInit( "traces/test_core.log", HIX_LOG_DEBUG, .F. )
   HIX_MetricsInit()

   _CoreConfig(          hCtx )
   _CoreLogger(          hCtx )
   _CoreMetrics(         hCtx )
   _CoreError(           hCtx )
   _CoreProtocolDetect(  hCtx )
   _CoreJsonRoundTrip(   hCtx )

   HIX_MetricsClose()
   HIX_LoggerClose()

   RETURN hCtx

// ---------------------------------------------------------------
// Config
// ---------------------------------------------------------------
STATIC PROCEDURE _CoreConfig( hCtx )
   LOCAL hCfg, oCfgSave, nPort, cHost, cMode

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )

   nPort := HIX_GetConfig( "server", "port" )
   cHost := HIX_GetConfig( "server", "host" )
   cMode := HIX_GetConfig( "server", "mode" )

   HixTU_Check( hCtx, nPort > 0,                    "Config: default port > 0",  ">0",                hb_NToS( nPort ) )
   HixTU_Check( hCtx, ValType( cHost ) == "C" .AND. ! Empty( cHost ), "Config: default host no vacio", "non-empty", cHost )
   HixTU_Check( hCtx, cMode == HIX_MODE_STANDALONE, "Config: default mode",      HIX_MODE_STANDALONE, cMode )

   hCfg := HIX_GetConfig()
   hCfg[ "server" ][ "port" ] := 12345
   HixTU_Check( hCtx, HIX_GetConfig( "server", "port" ) == 12345, "Config: set/get port via hash", "12345", hb_NToS( HIX_GetConfig( "server", "port" ) ) )

   hCfg[ "server" ][ "ssl" ]          := .T.
   hCfg[ "server" ][ "cert_private" ] := "no_existe.key"
   hCfg[ "server" ][ "cert_public" ]  := "no_existe.crt"
   HixTU_Check( hCtx, HIX_GetConfig( "server", "ssl" ),                          "Config: ssl=.T. via hash",          ".T.",          ".F." )
   HixTU_Check( hCtx, HIX_GetConfig( "server", "cert_private" ) == "no_existe.key", "Config: cert_private via hash", "no_existe.key", HIX_GetConfig( "server", "cert_private" ) )

   HIX_SetConfig( oCfgSave )
RETURN

// ---------------------------------------------------------------
// Logger
// ---------------------------------------------------------------
STATIC PROCEDURE _CoreLogger( hCtx )
   LOCAL cLog     := "traces/test_core_logger.log"
   LOCAL cContent

   HIX_LoggerInit( cLog, HIX_LOG_WARN, .F. )

   ld( "Este DEBUG no debe aparecer" )
   lw( "Este WARN SI debe aparecer" )
   le( "Este ERROR SI debe aparecer" )

   HIX_LoggerClose()

   HixTU_Check( hCtx, File( cLog ), "Logger: fichero creado", "existe", "no existe" )

   IF File( cLog )
      cContent := hb_MemoRead( cLog )
      HixTU_Check( hCtx, "WARN"  $ cContent, "Logger: WARN en fichero",  "WARN",  "ausente" )
      HixTU_Check( hCtx, "ERROR" $ cContent, "Logger: ERROR en fichero", "ERROR", "ausente" )
      HixTU_Check( hCtx, ! ( "DEBUG" $ cContent ), "Logger: DEBUG NO aparece (nivel WARN)", "sin DEBUG", "DEBUG encontrado" )
   ENDIF

   HIX_LoggerInit( "traces/test_core.log", HIX_LOG_DEBUG, .F. )
RETURN

// ---------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------
STATIC PROCEDURE _CoreMetrics( hCtx )

   HIX_MetricsInit()

   HIX_Metric( HIXM_REQUESTS )
   HIX_Metric( HIXM_REQUESTS )
   HIX_Metric( HIXM_REQUESTS, 3 )
   HixTU_Check( hCtx, HIX_MetricGet( HIXM_REQUESTS ) == 5, "Metrics: Inc x2 + Inc(3) = 5", "5", hb_NToS( HIX_MetricGet( HIXM_REQUESTS ) ) )

   HIX_MetricSet( HIXM_ACTIVE_HTTP, 7 )
   HixTU_Check( hCtx, HIX_MetricGet( HIXM_ACTIVE_HTTP ) == 7, "Metrics: Set(7) -> Get = 7", "7", hb_NToS( HIX_MetricGet( HIXM_ACTIVE_HTTP ) ) )

   HIX_MetricSet( HIXM_ACTIVE_HTTP, 0 )
   HIX_MetricSet( HIXM_ACTIVE_HTTP, Max( 0, HIX_MetricGet( HIXM_ACTIVE_HTTP ) - 1 ) )
   HixTU_Check( hCtx, HIX_MetricGet( HIXM_ACTIVE_HTTP ) == 0, "Metrics: Max(0,0-1) = 0", "0", hb_NToS( HIX_MetricGet( HIXM_ACTIVE_HTTP ) ) )

   HixTU_Check( hCtx, Len( HIX_MetricsJson() ) > 2, "Metrics: ToJson no vacio", "len>2", hb_NToS( Len( HIX_MetricsJson() ) ) )
   HixTU_Check( hCtx, HIXM_REQUESTS $ HIX_MetricsJson(), "Metrics: JSON contiene requests", "requests", "no" )
RETURN

// ---------------------------------------------------------------
// Error
// ---------------------------------------------------------------
STATIC PROCEDURE _CoreError( hCtx )
   LOCAL oErr

   oErr := THixError():New( HIX_ERR_OK, "todo bien", "test" )
   HixTU_Check( hCtx, oErr:IsOk(),            "THixError: IsOk() con ERR_OK",           ".T.", ".F." )
   HixTU_Check( hCtx, "OK" $ oErr:ToString(), "THixError: ToString contiene OK",         "OK",  oErr:ToString() )

   oErr := THixError():New( HIX_ERR_SOCKET, "fallo de red", "test" )
   HixTU_Check( hCtx, ! oErr:IsOk(),                      "THixError: IsOk() con ERR_SOCKET .F.", ".F.", ".T." )
   HixTU_Check( hCtx, "ERR_SOCKET" $ oErr:ToString(),     "THixError: ToString contiene ERR_SOCKET", "ERR_SOCKET", oErr:ToString() )

   HixTU_Check( hCtx, HIX_ErrorName( HIX_ERR_TIMEOUT   ) == "ERR_TIMEOUT",   "HIX_ErrorName TIMEOUT",   "ERR_TIMEOUT",   HIX_ErrorName( HIX_ERR_TIMEOUT   ) )
   HixTU_Check( hCtx, HIX_ErrorName( HIX_ERR_POOL_FULL ) == "ERR_POOL_FULL", "HIX_ErrorName POOL_FULL", "ERR_POOL_FULL", HIX_ErrorName( HIX_ERR_POOL_FULL ) )
   HixTU_Check( hCtx, HIX_ErrorName( 999               ) == "ERR_UNKNOWN",   "HIX_ErrorName desconocido","ERR_UNKNOWN",   HIX_ErrorName( 999               ) )
RETURN

// ---------------------------------------------------------------
// Protocol detect
// ---------------------------------------------------------------
STATIC PROCEDURE _CoreProtocolDetect( hCtx )

   HixTU_Check( hCtx, HIX_DetectProtocol( "GET / HTTP/1.1" + Chr(13)+Chr(10) ) == HIX_CONN_HTTP, ;
           "Detect: GET -> HTTP", HIX_CONN_HTTP, HIX_DetectProtocol( "GET / HTTP/1.1" ) )

   HixTU_Check( hCtx, HIX_DetectProtocol( "POST /api HTTP/1.1" ) == HIX_CONN_HTTP, ;
           "Detect: POST -> HTTP", HIX_CONN_HTTP, HIX_DetectProtocol( "POST /api HTTP/1.1" ) )

   HixTU_Check( hCtx, HIX_DetectProtocol( "GET /ws HTTP/1.1" + Chr(13)+Chr(10) + "Upgrade: websocket" ) == HIX_CONN_WS, ;
           "Detect: Upgrade websocket -> WS", HIX_CONN_WS, "" )

   HixTU_Check( hCtx, HIX_DetectProtocol( "GET /ev HTTP/1.1" + Chr(13)+Chr(10) + "Accept: text/event-stream" ) == HIX_CONN_SSE, ;
           "Detect: text/event-stream -> SSE", HIX_CONN_SSE, "" )

   HixTU_Check( hCtx, HIX_DetectProtocol( "GET /lp HTTP/1.1" + Chr(13)+Chr(10) + "x-hix-longpoll: true" ) == HIX_CONN_LONGPOLL, ;
           "Detect: x-hix-longpoll -> LONGPOLL", HIX_CONN_LONGPOLL, "" )

   HixTU_Check( hCtx, HIX_DetectProtocol( Chr(0) + Chr(255) + "basura" ) == HIX_CONN_UNKNOWN, ;
           "Detect: binario -> UNKNOWN", HIX_CONN_UNKNOWN, "" )

   HixTU_Check( hCtx, HIX_DetectProtocol( "" ) == HIX_CONN_UNKNOWN, ;
           "Detect: vacio -> UNKNOWN", HIX_CONN_UNKNOWN, "" )
RETURN

// ---------------------------------------------------------------
// JSON round-trip
// ---------------------------------------------------------------
STATIC PROCEDURE _CoreJsonRoundTrip( hCtx )
   LOCAL hCfg, oCfgSave, cFile

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )

   cFile := hb_DirTemp() + "hix_tm_core_" + hb_NToS( Int( Seconds() ) ) + ".json"

   hCfg := HIX_GetConfig()
   hCfg[ "server"   ][ "port" ]  := 9999
   hCfg[ "server"   ][ "host" ]  := "192.168.1.1"
   hCfg[ "server"   ][ "name" ]  := "TestServer"
   hCfg[ "app" ][ "debug" ] := .T.

   HIX_SaveConfig( hCfg, cFile )
   HIX_LoadConfig( cFile )

   HixTU_Check( hCtx, HIX_GetConfig( "server",   "port" )  == 9999,          "JSON: port",         "9999",        hb_NToS( HIX_GetConfig( "server", "port" ) ) )
   HixTU_Check( hCtx, HIX_GetConfig( "server",   "host" )  == "192.168.1.1", "JSON: host",         "192.168.1.1", HIX_GetConfig( "server", "host" ) )
   HixTU_Check( hCtx, HIX_GetConfig( "server",   "name" )  == "TestServer",  "JSON: name",         "TestServer",  HIX_GetConfig( "server", "name" ) )
   HixTU_Check( hCtx, HIX_GetConfig( "app", "debug" ),                       "JSON: debug=.T.",    ".T.",         hb_ValToStr( HIX_GetConfig( "app", "debug" ) ) )
   HixTU_Check( hCtx, HIX_GetConfig( "server",   "mode" )  == HIX_MODE_STANDALONE, "JSON: clave ausente -> default", HIX_MODE_STANDALONE, HIX_GetConfig( "server", "mode" ) )

   hb_vfErase( cFile )
   HIX_SetConfig( oCfgSave )
RETURN
