/*-----------------------------------------------------------
  File ......: hix_config_data.prg
  Author.....: Carles Aubia (Charly 9000)
  Created....: 2026-06-30
  Modified...: 2026-06-30
  Version....: 1.0.0
  Description: Master defaults for HIX server configuration.
               Holds DEFAULT_* defines, HIX_InitDefault() seed
               hash and HIX_ValidConfig() type-coerce / fill-in.
  Usage      : Called by hix_config.prg HIX_LoadConfig().
  Notes      : All booleans are real .T./.F. (Harbour logical),
               not strings.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

// --------------------------------------------------------------------------
// SERVER
// --------------------------------------------------------------------------
#DEFINE DEFAULT_SERVER_HOST     'localhost'
#DEFINE DEFAULT_SERVER_PORT     80
#DEFINE DEFAULT_SERVER_MAXCONN    1024
#DEFINE DEFAULT_SERVER_TIMEOUT    30
#DEFINE DEFAULT_SERVER_NAME     'HIX'
#DEFINE DEFAULT_SERVER_MODE     'standalone'
#DEFINE DEFAULT_SERVER_TRUSTED_PROXIES  '127.0.0.1 ::1'
#DEFINE DEFAULT_SERVER_ALLOWED_HOSTS  ''
#DEFINE DEFAULT_SERVER_SSL     .F.
#DEFINE DEFAULT_SERVER_CERT_PRIVATE   ''
#DEFINE DEFAULT_SERVER_CERT_PUBLIC   ''
#DEFINE DEFAULT_SERVER_GZIP     .T.
#DEFINE DEFAULT_SERVER_GZIP_MIN_SIZE  2048
#DEFINE DEFAULT_SERVER_AUTOSTART   .T.
#DEFINE DEFAULT_SERVER_EXEC_TIMEOUT_MS  30000

// --------------------------------------------------------------------------
// PATHS
// --------------------------------------------------------------------------
#DEFINE DEFAULT_PATHS_ROOT     'www'
#DEFINE DEFAULT_PATHS_LOG     '.logs'
#DEFINE DEFAULT_PATHS_TMP     'tmp'
#DEFINE DEFAULT_PATHS_ERRORS    '.logs'
#DEFINE DEFAULT_PATHS_SESSION    '.sessions'
#DEFINE DEFAULT_PATHS_CERTS     'certs'

// --------------------------------------------------------------------------
// APP
// --------------------------------------------------------------------------
#DEFINE DEFAULT_APP_ERRORSYS    ''
#DEFINE DEFAULT_APP_DEFAULT_PAGE   'index.html'
#DEFINE DEFAULT_APP_DISPATCH_MODE   'full'
#DEFINE DEFAULT_APP_AUTO_CLOSE_DBF   .T.
#DEFINE DEFAULT_APP_AUTO_CLOSE_DBF_LOG  .F.
#DEFINE DEFAULT_APP_ENV      'dev'
#DEFINE DEFAULT_APP_DEBUG     .F.

// --------------------------------------------------------------------------
// ADMIN
// --------------------------------------------------------------------------
#DEFINE DEFAULT_ADMIN_ENABLED    .T.
#DEFINE DEFAULT_ADMIN_USER     ''
#DEFINE DEFAULT_ADMIN_PASSWORD    ''
#DEFINE DEFAULT_ADMIN_SECRET    ''

// --------------------------------------------------------------------------
// DETECTOR
// --------------------------------------------------------------------------
#DEFINE DEFAULT_DETECTOR_WORKERS   4
#DEFINE DEFAULT_DETECTOR_QUEUE_SIZE   256
#DEFINE DEFAULT_DETECTOR_PEEK_TIMEOUT_MS 10
#DEFINE DEFAULT_DETECTOR_PEEK_BYTES   512

// --------------------------------------------------------------------------
// POOL HTTP
// --------------------------------------------------------------------------
#DEFINE DEFAULT_POOL_HTTP_WORKERS   64
#DEFINE DEFAULT_POOL_HTTP_QUEUE_SIZE  256
#DEFINE DEFAULT_POOL_HTTP_READ_TIMEOUT_MS 2000
#DEFINE DEFAULT_POOL_HTTP_KEEP_ALIVE  .T.
#DEFINE DEFAULT_POOL_HTTP_KEEP_ALIVE_MAX 100

// --------------------------------------------------------------------------
// POOL WS
// --------------------------------------------------------------------------
#DEFINE DEFAULT_POOL_WS_WORKERS    100
#DEFINE DEFAULT_POOL_WS_QUEUE_SIZE   256
#DEFINE DEFAULT_POOL_WS_PING_INTERVAL_S  30
#DEFINE DEFAULT_POOL_WS_PING_TIMEOUT_S  10

// --------------------------------------------------------------------------
// POOL REST
// --------------------------------------------------------------------------
#DEFINE DEFAULT_POOL_REST_WORKERS_SSE  20
#DEFINE DEFAULT_POOL_REST_WORKERS_LONGPOLL 10
#DEFINE DEFAULT_POOL_REST_QUEUE_SIZE  128
#DEFINE DEFAULT_POOL_REST_STREAM_TIMEOUT_S 3600

// --------------------------------------------------------------------------
// POOL HIX  (rutas /hix-* — monitor + endpoints externos/IA)
// --------------------------------------------------------------------------
#DEFINE DEFAULT_POOL_HIX_WORKERS   4
#DEFINE DEFAULT_POOL_HIX_QUEUE_SIZE   64
#DEFINE DEFAULT_POOL_HIX_READ_TIMEOUT_MS 2000

// --------------------------------------------------------------------------
// SESSION
// --------------------------------------------------------------------------
#DEFINE DEFAULT_SESSION_STORAGE    'memory'
#DEFINE DEFAULT_SESSION_PREFIX    'sess_'
#DEFINE DEFAULT_SESSION_CRYPT    .F.
#DEFINE DEFAULT_SESSION_SEED    ''
#DEFINE DEFAULT_SESSION_LIFETIME   60
#DEFINE DEFAULT_SESSION_GC_DAYS    3

// --------------------------------------------------------------------------
// MONITOR
// --------------------------------------------------------------------------
#DEFINE DEFAULT_MONITOR_ENABLED    .T.
#DEFINE DEFAULT_MONITOR_INTERVAL_S   5
#DEFINE DEFAULT_MONITOR_ALERT_PCT   75

// --------------------------------------------------------------------------
// LOG
// --------------------------------------------------------------------------
#DEFINE DEFAULT_LOG_FILE     'hix.log'
#DEFINE DEFAULT_LOG_LEVEL     'info'
#DEFINE DEFAULT_LOG_CONSOLE     .T.
#DEFINE DEFAULT_LOG_MAX_SIZE_MB    10
#DEFINE DEFAULT_LOG_MAX_FILES    0

// --------------------------------------------------------------------------
// ACCESS LOG
// --------------------------------------------------------------------------
#DEFINE DEFAULT_ACCESS_LOG_ENABLED   .T.
#DEFINE DEFAULT_ACCESS_LOG_FILE    'access.log'

// --------------------------------------------------------------------------
// FIREWALL
// --------------------------------------------------------------------------
#DEFINE DEFAULT_FIREWALL_MODE    'blacklist'
#DEFINE DEFAULT_FIREWALL_FILTER    ''

// --------------------------------------------------------------------------
// HIXSTYLE
// --------------------------------------------------------------------------
#DEFINE DEFAULT_HIXSTYLE_ENABLED   .F.
#DEFINE DEFAULT_HIXSTYLE_CACHE_DISK   .T.
#DEFINE DEFAULT_HIXSTYLE_TRACE    .F.
#DEFINE DEFAULT_HIXSTYLE_CACHE_RAM   .F.

// --------------------------------------------------------------------------
// TRACE
// --------------------------------------------------------------------------
#DEFINE DEFAULT_TRACE_APP     .T.
#DEFINE DEFAULT_TRACE_SERVER    .T.
#DEFINE DEFAULT_TRACE_WORKER_HTTP   .F.
#DEFINE DEFAULT_TRACE_WORKER_WS    .F.
#DEFINE DEFAULT_TRACE_WORKER_OTROS   .F.
#DEFINE DEFAULT_TRACE_POOL     .F.
#DEFINE DEFAULT_TRACE_POOL_DETECTOR   .F.
#DEFINE DEFAULT_TRACE_METRICS    .F.
#DEFINE DEFAULT_TRACE_CONFIG    .F.
#DEFINE DEFAULT_TRACE_SOCKET    .F.
#DEFINE DEFAULT_TRACE_MONITOR    .F.
#DEFINE DEFAULT_TRACE_RESPONSE    .F.
#DEFINE DEFAULT_TRACE_LOGGER    .F.
#DEFINE DEFAULT_TRACE_ERROR     .F.


// ------------------------------------------------------------------ //
// HIX_InitDefault — build a fully populated config hash from defaults
// ------------------------------------------------------------------ //
FUNCTION HIX_InitDefault()

   LOCAL hCfg := { => }

   HB_HCaseMatch( hCfg, .F. )

// SERVER
   hCfg[ 'server' ]        := { => }
   hCfg[ 'server' ][ 'host' ]      := DEFAULT_SERVER_HOST
   hCfg[ 'server' ][ 'port' ]      := DEFAULT_SERVER_PORT
   hCfg[ 'server' ][ 'maxconn' ]     := DEFAULT_SERVER_MAXCONN
   hCfg[ 'server' ][ 'timeout' ]     := DEFAULT_SERVER_TIMEOUT
   hCfg[ 'server' ][ 'name' ]      := DEFAULT_SERVER_NAME
   hCfg[ 'server' ][ 'mode' ]      := DEFAULT_SERVER_MODE
   hCfg[ 'server' ][ 'trusted_proxies' ]   := DEFAULT_SERVER_TRUSTED_PROXIES
   hCfg[ 'server' ][ 'allowed_hosts' ]    := DEFAULT_SERVER_ALLOWED_HOSTS
   hCfg[ 'server' ][ 'ssl' ]      := DEFAULT_SERVER_SSL
   hCfg[ 'server' ][ 'cert_private' ]    := DEFAULT_SERVER_CERT_PRIVATE
   hCfg[ 'server' ][ 'cert_public' ]    := DEFAULT_SERVER_CERT_PUBLIC
   hCfg[ 'server' ][ 'gzip' ]      := DEFAULT_SERVER_GZIP
   hCfg[ 'server' ][ 'gzip_min_size' ]    := DEFAULT_SERVER_GZIP_MIN_SIZE
   hCfg[ 'server' ][ 'autostart' ]     := DEFAULT_SERVER_AUTOSTART
   hCfg[ 'server' ][ 'exec_timeout_ms' ]   := DEFAULT_SERVER_EXEC_TIMEOUT_MS

// PATHS
   hCfg[ 'paths' ]         := { => }
   hCfg[ 'paths' ][ 'root' ]      := DEFAULT_PATHS_ROOT
   hCfg[ 'paths' ][ 'log' ]      := DEFAULT_PATHS_LOG
   hCfg[ 'paths' ][ 'tmp' ]      := DEFAULT_PATHS_TMP
   hCfg[ 'paths' ][ 'errors' ]      := DEFAULT_PATHS_ERRORS
   hCfg[ 'paths' ][ 'session' ]     := DEFAULT_PATHS_SESSION
   hCfg[ 'paths' ][ 'certs' ]      := DEFAULT_PATHS_CERTS

// APP
   hCfg[ 'app' ]         := { => }
   hCfg[ 'app' ][ 'errorsys' ]      := DEFAULT_APP_ERRORSYS
   hCfg[ 'app' ][ 'default_page' ]     := DEFAULT_APP_DEFAULT_PAGE
   hCfg[ 'app' ][ 'dispatch_mode' ]    := DEFAULT_APP_DISPATCH_MODE
   hCfg[ 'app' ][ 'auto_close_dbf' ]    := DEFAULT_APP_AUTO_CLOSE_DBF
   hCfg[ 'app' ][ 'auto_close_dbf_log' ]   := DEFAULT_APP_AUTO_CLOSE_DBF_LOG
   hCfg[ 'app' ][ 'env' ]       := DEFAULT_APP_ENV
   hCfg[ 'app' ][ 'debug' ]      := DEFAULT_APP_DEBUG

// ADMIN
   hCfg[ 'admin' ]         := { => }
   hCfg[ 'admin' ][ 'enabled' ]     := DEFAULT_ADMIN_ENABLED
   hCfg[ 'admin' ][ 'user' ]      := DEFAULT_ADMIN_USER
   hCfg[ 'admin' ][ 'password' ]     := DEFAULT_ADMIN_PASSWORD
   hCfg[ 'admin' ][ 'secret' ]      := DEFAULT_ADMIN_SECRET

// DETECTOR
   hCfg[ 'detector' ]        := { => }
   hCfg[ 'detector' ][ 'workers' ]     := DEFAULT_DETECTOR_WORKERS
   hCfg[ 'detector' ][ 'queue_size' ]    := DEFAULT_DETECTOR_QUEUE_SIZE
   hCfg[ 'detector' ][ 'peek_timeout_ms' ]   := DEFAULT_DETECTOR_PEEK_TIMEOUT_MS
   hCfg[ 'detector' ][ 'peek_bytes' ]    := DEFAULT_DETECTOR_PEEK_BYTES

// POOL HTTP
   hCfg[ 'pool_http' ]        := { => }
   hCfg[ 'pool_http' ][ 'workers' ]    := DEFAULT_POOL_HTTP_WORKERS
   hCfg[ 'pool_http' ][ 'queue_size' ]    := DEFAULT_POOL_HTTP_QUEUE_SIZE
   hCfg[ 'pool_http' ][ 'read_timeout_ms' ]  := DEFAULT_POOL_HTTP_READ_TIMEOUT_MS
   hCfg[ 'pool_http' ][ 'keep_alive' ]    := DEFAULT_POOL_HTTP_KEEP_ALIVE
   hCfg[ 'pool_http' ][ 'keep_alive_max' ]   := DEFAULT_POOL_HTTP_KEEP_ALIVE_MAX

// POOL WS
   hCfg[ 'pool_ws' ]        := { => }
   hCfg[ 'pool_ws' ][ 'workers' ]     := DEFAULT_POOL_WS_WORKERS
   hCfg[ 'pool_ws' ][ 'queue_size' ]    := DEFAULT_POOL_WS_QUEUE_SIZE
   hCfg[ 'pool_ws' ][ 'ping_interval_s' ]   := DEFAULT_POOL_WS_PING_INTERVAL_S
   hCfg[ 'pool_ws' ][ 'ping_timeout_s' ]   := DEFAULT_POOL_WS_PING_TIMEOUT_S

// POOL REST
   hCfg[ 'pool_rest' ]        := { => }
   hCfg[ 'pool_rest' ][ 'workers_sse' ]   := DEFAULT_POOL_REST_WORKERS_SSE
   hCfg[ 'pool_rest' ][ 'workers_longpoll' ]  := DEFAULT_POOL_REST_WORKERS_LONGPOLL
   hCfg[ 'pool_rest' ][ 'queue_size' ]    := DEFAULT_POOL_REST_QUEUE_SIZE
   hCfg[ 'pool_rest' ][ 'stream_timeout_s' ]  := DEFAULT_POOL_REST_STREAM_TIMEOUT_S

// POOL HIX
   hCfg[ 'pool_hix' ]        := { => }
   hCfg[ 'pool_hix' ][ 'workers' ]     := DEFAULT_POOL_HIX_WORKERS
   hCfg[ 'pool_hix' ][ 'queue_size' ]    := DEFAULT_POOL_HIX_QUEUE_SIZE
   hCfg[ 'pool_hix' ][ 'read_timeout_ms' ]   := DEFAULT_POOL_HIX_READ_TIMEOUT_MS

// SESSION
   hCfg[ 'session' ]        := { => }
   hCfg[ 'session' ][ 'storage' ]     := DEFAULT_SESSION_STORAGE
   hCfg[ 'session' ][ 'prefix' ]     := DEFAULT_SESSION_PREFIX
   hCfg[ 'session' ][ 'crypt' ]     := DEFAULT_SESSION_CRYPT
   hCfg[ 'session' ][ 'seed' ]      := DEFAULT_SESSION_SEED
   hCfg[ 'session' ][ 'lifetime' ]     := DEFAULT_SESSION_LIFETIME
   hCfg[ 'session' ][ 'gc_days' ]     := DEFAULT_SESSION_GC_DAYS

// MONITOR
   hCfg[ 'monitor' ]        := { => }
   hCfg[ 'monitor' ][ 'enabled' ]     := DEFAULT_MONITOR_ENABLED
   hCfg[ 'monitor' ][ 'interval_s' ]    := DEFAULT_MONITOR_INTERVAL_S
   hCfg[ 'monitor' ][ 'alert_pct' ]    := DEFAULT_MONITOR_ALERT_PCT

// LOG
   hCfg[ 'log' ]         := { => }
   hCfg[ 'log' ][ 'file' ]       := DEFAULT_LOG_FILE
   hCfg[ 'log' ][ 'level' ]      := DEFAULT_LOG_LEVEL
   hCfg[ 'log' ][ 'console' ]      := DEFAULT_LOG_CONSOLE
   hCfg[ 'log' ][ 'max_size_mb' ]     := DEFAULT_LOG_MAX_SIZE_MB
   hCfg[ 'log' ][ 'max_files' ]     := DEFAULT_LOG_MAX_FILES

// ACCESS LOG
   hCfg[ 'access_log' ]       := { => }
   hCfg[ 'access_log' ][ 'enabled' ]    := DEFAULT_ACCESS_LOG_ENABLED
   hCfg[ 'access_log' ][ 'file' ]     := DEFAULT_ACCESS_LOG_FILE

// FIREWALL
   hCfg[ 'firewall' ]        := { => }
   hCfg[ 'firewall' ][ 'mode' ]     := DEFAULT_FIREWALL_MODE
   hCfg[ 'firewall' ][ 'filter' ]     := DEFAULT_FIREWALL_FILTER

// HIXSTYLE
   hCfg[ 'hixstyle' ]        := { => }
   hCfg[ 'hixstyle' ][ 'enabled' ]     := DEFAULT_HIXSTYLE_ENABLED
   hCfg[ 'hixstyle' ][ 'cache_disk' ]    := DEFAULT_HIXSTYLE_CACHE_DISK
   hCfg[ 'hixstyle' ][ 'trace' ]     := DEFAULT_HIXSTYLE_TRACE
   hCfg[ 'hixstyle' ][ 'cache_ram' ]    := DEFAULT_HIXSTYLE_CACHE_RAM

// TRACE
   hCfg[ 'trace' ]         := { => }
   hCfg[ 'trace' ][ 'app' ]      := DEFAULT_TRACE_APP
   hCfg[ 'trace' ][ 'server' ]      := DEFAULT_TRACE_SERVER
   hCfg[ 'trace' ][ 'worker_http' ]    := DEFAULT_TRACE_WORKER_HTTP
   hCfg[ 'trace' ][ 'worker_ws' ]     := DEFAULT_TRACE_WORKER_WS
   hCfg[ 'trace' ][ 'worker_otros' ]    := DEFAULT_TRACE_WORKER_OTROS
   hCfg[ 'trace' ][ 'pool' ]      := DEFAULT_TRACE_POOL
   hCfg[ 'trace' ][ 'pool_detector' ]    := DEFAULT_TRACE_POOL_DETECTOR
   hCfg[ 'trace' ][ 'metrics' ]     := DEFAULT_TRACE_METRICS
   hCfg[ 'trace' ][ 'config' ]      := DEFAULT_TRACE_CONFIG
   hCfg[ 'trace' ][ 'socket' ]      := DEFAULT_TRACE_SOCKET
   hCfg[ 'trace' ][ 'monitor' ]     := DEFAULT_TRACE_MONITOR
   hCfg[ 'trace' ][ 'response' ]     := DEFAULT_TRACE_RESPONSE
   hCfg[ 'trace' ][ 'logger' ]      := DEFAULT_TRACE_LOGGER
   hCfg[ 'trace' ][ 'error' ]      := DEFAULT_TRACE_ERROR

RETURN hCfg

// ------------------------------------------------------------------ //
// HIX_ValidConfig — merge user config over defaults, coerce types.
// Receives raw hash from JSON (may miss sections/keys).
// Returns a complete hash with every expected key present and typed.
// ------------------------------------------------------------------ //
FUNCTION HIX_ValidConfig( hConfig )

   LOCAL hCfg, hSec, hSrc

   IF ! hb_IsHash( hConfig )

      hConfig := { => }

   ENDIF

   HB_HCaseMatch( hConfig, .F. )

// Start from full defaults and overlay user values
   hCfg := HIX_InitDefault()

// SERVER
   hSec := hCfg[ 'server' ]
   hSrc := _Section( hConfig, 'server' )
   hSec[ 'host' ]    := _GetString( hSrc, 'host', hSec[ 'host' ] )
   hSec[ 'port' ]    := _GetNumber( hSrc, 'port', hSec[ 'port' ] )
   hSec[ 'maxconn' ]   := _GetNumber( hSrc, 'maxconn', hSec[ 'maxconn' ] )
   hSec[ 'timeout' ]   := _GetNumber( hSrc, 'timeout', hSec[ 'timeout' ] )
   hSec[ 'name' ]    := _GetString( hSrc, 'name', hSec[ 'name' ] )
   hSec[ 'mode' ]    := _GetString( hSrc, 'mode', hSec[ 'mode' ] )
   hSec[ 'trusted_proxies' ] := _GetString( hSrc, 'trusted_proxies', hSec[ 'trusted_proxies' ] )
   hSec[ 'allowed_hosts' ]  := _GetString( hSrc, 'allowed_hosts', hSec[ 'allowed_hosts' ] )
   hSec[ 'ssl' ]    := _GetLogic ( hSrc, 'ssl', hSec[ 'ssl' ] )
   hSec[ 'cert_private' ]  := _GetString( hSrc, 'cert_private', hSec[ 'cert_private' ] )
   hSec[ 'cert_public' ]  := _GetString( hSrc, 'cert_public', hSec[ 'cert_public' ] )
   hSec[ 'gzip' ]    := _GetLogic ( hSrc, 'gzip', hSec[ 'gzip' ] )
   hSec[ 'gzip_min_size' ]  := _GetNumber( hSrc, 'gzip_min_size', hSec[ 'gzip_min_size' ] )
   hSec[ 'autostart' ]   := _GetLogic ( hSrc, 'autostart', hSec[ 'autostart' ] )
   hSec[ 'exec_timeout_ms' ] := _GetNumber( hSrc, 'exec_timeout_ms', hSec[ 'exec_timeout_ms' ] )

// PATHS
   hSec := hCfg[ 'paths' ]
   hSrc := _Section( hConfig, 'paths' )
   hSec[ 'root' ]    := _GetString( hSrc, 'root', hSec[ 'root' ] )
   hSec[ 'log' ]    := _GetString( hSrc, 'log', hSec[ 'log' ] )
   hSec[ 'tmp' ]    := _GetString( hSrc, 'tmp', hSec[ 'tmp' ] )
   hSec[ 'errors' ]   := _GetString( hSrc, 'errors', hSec[ 'errors' ] )
   hSec[ 'session' ]   := _GetString( hSrc, 'session', hSec[ 'session' ] )
   hSec[ 'certs' ]    := _GetString( hSrc, 'certs', hSec[ 'certs' ] )

// APP
   hSec := hCfg[ 'app' ]
   hSrc := _Section( hConfig, 'app' )
   hSec[ 'errorsys' ]    := _GetString( hSrc, 'errorsys', hSec[ 'errorsys' ] )
   hSec[ 'default_page' ]   := _GetString( hSrc, 'default_page', hSec[ 'default_page' ] )
   hSec[ 'dispatch_mode' ]   := _GetString( hSrc, 'dispatch_mode', hSec[ 'dispatch_mode' ] )
   hSec[ 'auto_close_dbf' ]  := _GetLogic ( hSrc, 'auto_close_dbf', hSec[ 'auto_close_dbf' ] )
   hSec[ 'auto_close_dbf_log' ] := _GetLogic ( hSrc, 'auto_close_dbf_log', hSec[ 'auto_close_dbf_log' ] )
   hSec[ 'env' ]     := _GetString( hSrc, 'env', hSec[ 'env' ] )
   hSec[ 'debug' ]     := _GetLogic ( hSrc, 'debug', hSec[ 'debug' ] )

// ADMIN
   hSec := hCfg[ 'admin' ]
   hSrc := _Section( hConfig, 'admin' )
   hSec[ 'enabled' ]   := _GetLogic ( hSrc, 'enabled', hSec[ 'enabled' ] )
   hSec[ 'user' ]    := _GetString( hSrc, 'user', hSec[ 'user' ] )
   hSec[ 'password' ]   := _GetString( hSrc, 'password', hSec[ 'password' ] )
   hSec[ 'secret' ]   := _GetString( hSrc, 'secret', hSec[ 'secret' ] )

// DETECTOR
   hSec := hCfg[ 'detector' ]
   hSrc := _Section( hConfig, 'detector' )
   hSec[ 'workers' ]   := _GetNumber( hSrc, 'workers', hSec[ 'workers' ] )
   hSec[ 'queue_size' ]  := _GetNumber( hSrc, 'queue_size', hSec[ 'queue_size' ] )
   hSec[ 'peek_timeout_ms' ] := _GetNumber( hSrc, 'peek_timeout_ms', hSec[ 'peek_timeout_ms' ] )
   hSec[ 'peek_bytes' ]  := _GetNumber( hSrc, 'peek_bytes', hSec[ 'peek_bytes' ] )

// POOL HTTP
   hSec := hCfg[ 'pool_http' ]
   hSrc := _Section( hConfig, 'pool_http' )
   hSec[ 'workers' ]   := _GetNumber( hSrc, 'workers', hSec[ 'workers' ] )
   hSec[ 'queue_size' ]  := _GetNumber( hSrc, 'queue_size', hSec[ 'queue_size' ] )
   hSec[ 'read_timeout_ms' ] := _GetNumber( hSrc, 'read_timeout_ms', hSec[ 'read_timeout_ms' ] )
   hSec[ 'keep_alive' ]  := _GetLogic ( hSrc, 'keep_alive', hSec[ 'keep_alive' ] )
   hSec[ 'keep_alive_max' ] := _GetNumber( hSrc, 'keep_alive_max', hSec[ 'keep_alive_max' ] )

// POOL WS
   hSec := hCfg[ 'pool_ws' ]
   hSrc := _Section( hConfig, 'pool_ws' )
   hSec[ 'workers' ]   := _GetNumber( hSrc, 'workers', hSec[ 'workers' ] )
   hSec[ 'queue_size' ]  := _GetNumber( hSrc, 'queue_size', hSec[ 'queue_size' ] )
   hSec[ 'ping_interval_s' ] := _GetNumber( hSrc, 'ping_interval_s', hSec[ 'ping_interval_s' ] )
   hSec[ 'ping_timeout_s' ] := _GetNumber( hSrc, 'ping_timeout_s', hSec[ 'ping_timeout_s' ] )

// POOL REST
   hSec := hCfg[ 'pool_rest' ]
   hSrc := _Section( hConfig, 'pool_rest' )
   hSec[ 'workers_sse' ]  := _GetNumber( hSrc, 'workers_sse', hSec[ 'workers_sse' ] )
   hSec[ 'workers_longpoll' ] := _GetNumber( hSrc, 'workers_longpoll', hSec[ 'workers_longpoll' ] )
   hSec[ 'queue_size' ]  := _GetNumber( hSrc, 'queue_size', hSec[ 'queue_size' ] )
   hSec[ 'stream_timeout_s' ] := _GetNumber( hSrc, 'stream_timeout_s', hSec[ 'stream_timeout_s' ] )

// POOL HIX
   hSec := hCfg[ 'pool_hix' ]
   hSrc := _Section( hConfig, 'pool_hix' )
   hSec[ 'workers' ]   := _GetNumber( hSrc, 'workers', hSec[ 'workers' ] )
   hSec[ 'queue_size' ]  := _GetNumber( hSrc, 'queue_size', hSec[ 'queue_size' ] )
   hSec[ 'read_timeout_ms' ] := _GetNumber( hSrc, 'read_timeout_ms', hSec[ 'read_timeout_ms' ] )

// SESSION
   hSec := hCfg[ 'session' ]
   hSrc := _Section( hConfig, 'session' )
   hSec[ 'storage' ]   := _GetString( hSrc, 'storage', hSec[ 'storage' ] )
   hSec[ 'prefix' ]   := _GetString( hSrc, 'prefix', hSec[ 'prefix' ] )
   hSec[ 'crypt' ]    := _GetLogic ( hSrc, 'crypt', hSec[ 'crypt' ] )
   hSec[ 'seed' ]    := _GetString( hSrc, 'seed', hSec[ 'seed' ] )
   hSec[ 'lifetime' ]   := _GetNumber( hSrc, 'lifetime', hSec[ 'lifetime' ] )
   hSec[ 'gc_days' ]   := _GetNumber( hSrc, 'gc_days', hSec[ 'gc_days' ] )

// MONITOR
   hSec := hCfg[ 'monitor' ]
   hSrc := _Section( hConfig, 'monitor' )
   hSec[ 'enabled' ]   := _GetLogic ( hSrc, 'enabled', hSec[ 'enabled' ] )
   hSec[ 'interval_s' ]  := _GetNumber( hSrc, 'interval_s', hSec[ 'interval_s' ] )
   hSec[ 'alert_pct' ]   := _GetNumber( hSrc, 'alert_pct', hSec[ 'alert_pct' ] )

// LOG
   hSec := hCfg[ 'log' ]
   hSrc := _Section( hConfig, 'log' )
   hSec[ 'file' ]    := _GetString( hSrc, 'file', hSec[ 'file' ] )
   hSec[ 'level' ]    := _GetString( hSrc, 'level', hSec[ 'level' ] )
   hSec[ 'console' ]   := _GetLogic ( hSrc, 'console', hSec[ 'console' ] )
   hSec[ 'max_size_mb' ]  := _GetNumber( hSrc, 'max_size_mb', hSec[ 'max_size_mb' ] )
   hSec[ 'max_files' ]   := _GetNumber( hSrc, 'max_files', hSec[ 'max_files' ] )

// ACCESS LOG
   hSec := hCfg[ 'access_log' ]
   hSrc := _Section( hConfig, 'access_log' )
   hSec[ 'enabled' ]   := _GetLogic ( hSrc, 'enabled', hSec[ 'enabled' ] )
   hSec[ 'file' ]    := _GetString( hSrc, 'file', hSec[ 'file' ] )

// FIREWALL
   hSec := hCfg[ 'firewall' ]
   hSrc := _Section( hConfig, 'firewall' )
   hSec[ 'mode' ]    := _GetString( hSrc, 'mode', hSec[ 'mode' ] )
   hSec[ 'filter' ]   := _GetString( hSrc, 'filter', hSec[ 'filter' ] )

// HIXSTYLE
   hSec := hCfg[ 'hixstyle' ]
   hSrc := _Section( hConfig, 'hixstyle' )
   hSec[ 'enabled' ]   := _GetLogic ( hSrc, 'enabled', hSec[ 'enabled' ] )
   hSec[ 'cache_disk' ]  := _GetLogic ( hSrc, 'cache_disk', hSec[ 'cache_disk' ] )
   hSec[ 'trace' ]    := _GetLogic ( hSrc, 'trace', hSec[ 'trace' ] )
   hSec[ 'cache_ram' ]   := _GetLogic ( hSrc, 'cache_ram', hSec[ 'cache_ram' ] )

// TRACE
   hSec := hCfg[ 'trace' ]
   hSrc := _Section( hConfig, 'trace' )
   hSec[ 'app' ]    := _GetLogic( hSrc, 'app', hSec[ 'app' ] )
   hSec[ 'server' ]   := _GetLogic( hSrc, 'server', hSec[ 'server' ] )
   hSec[ 'worker_http' ]  := _GetLogic( hSrc, 'worker_http', hSec[ 'worker_http' ] )
   hSec[ 'worker_ws' ]   := _GetLogic( hSrc, 'worker_ws', hSec[ 'worker_ws' ] )
   hSec[ 'worker_otros' ]  := _GetLogic( hSrc, 'worker_otros', hSec[ 'worker_otros' ] )
   hSec[ 'pool' ]    := _GetLogic( hSrc, 'pool', hSec[ 'pool' ] )
   hSec[ 'pool_detector' ]  := _GetLogic( hSrc, 'pool_detector', hSec[ 'pool_detector' ] )
   hSec[ 'metrics' ]   := _GetLogic( hSrc, 'metrics', hSec[ 'metrics' ] )
   hSec[ 'config' ]   := _GetLogic( hSrc, 'config', hSec[ 'config' ] )
   hSec[ 'socket' ]   := _GetLogic( hSrc, 'socket', hSec[ 'socket' ] )
   hSec[ 'monitor' ]   := _GetLogic( hSrc, 'monitor', hSec[ 'monitor' ] )
   hSec[ 'response' ]   := _GetLogic( hSrc, 'response', hSec[ 'response' ] )
   hSec[ 'logger' ]   := _GetLogic( hSrc, 'logger', hSec[ 'logger' ] )
   hSec[ 'error' ]    := _GetLogic( hSrc, 'error', hSec[ 'error' ] )

RETURN hCfg


// ------------------------------------------------------------------ //
// Section helpers
// ------------------------------------------------------------------ //
STATIC FUNCTION _Section( hConfig, cName )

   IF hb_IsHash( hConfig ) .AND. hb_HHasKey( hConfig, cName ) .AND. hb_IsHash( hConfig[ cName ] )

      RETURN hConfig[ cName ]

   ENDIF

RETURN { => }

STATIC FUNCTION _GetString( hSection, cKey, uDefault )

   LOCAL xValue

   hb_default( @uDefault, '' )

   IF ! hb_IsHash( hSection ) .OR. ! hb_HHasKey( hSection, cKey )

      RETURN uDefault

   ENDIF

   xValue := hSection[ cKey ]

   IF hb_IsString( xValue )

      RETURN AllTrim( xValue )
   ELSEIF hb_IsNumeric( xValue )
      RETURN hb_NToS( xValue )
   ELSEIF hb_IsLogical( xValue )
      RETURN iif( xValue, 'true', 'false' )

   ENDIF

RETURN uDefault

STATIC FUNCTION _GetLogic( hSection, cKey, uDefault )

   LOCAL xValue

   hb_default( @uDefault, .F. )

   IF ! hb_IsHash( hSection ) .OR. ! hb_HHasKey( hSection, cKey )

      RETURN uDefault

   ENDIF

   xValue := hSection[ cKey ]

   IF hb_IsLogical( xValue )

      RETURN xValue
   ELSEIF hb_IsNumeric( xValue )
      RETURN xValue != 0
   ELSEIF hb_IsString( xValue )
      RETURN Lower( AllTrim( xValue ) ) $ 'true,1,yes,on,.t.'

   ENDIF

RETURN uDefault

STATIC FUNCTION _GetNumber( hSection, cKey, uDefault )

   LOCAL xValue

   hb_default( @uDefault, 0 )

   IF ! hb_IsHash( hSection ) .OR. ! hb_HHasKey( hSection, cKey )

      RETURN uDefault

   ENDIF

   xValue := hSection[ cKey ]

   IF hb_IsNumeric( xValue )
      RETURN xValue
   ELSEIF hb_IsString( xValue )
      RETURN Val( xValue )
   ELSEIF hb_IsLogical( xValue )
      RETURN iif( xValue, 1, 0 )

   ENDIF

RETURN uDefault
