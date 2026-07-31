// ============================================================
// hix_const.ch — Constantes globales HIX
// Sin dependencias. Incluir en todos los módulos.
// ============================================================

#ifndef HIX_CONST_CH
#define HIX_CONST_CH

#include "hbclass.ch"
#include "hbsocket.ch"
#include "hbthread.ch"

// TRY / CATCH / FINALLY (no disponibles como builtin en Harbour 3.x)
#xcommand TRY                    => BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }
#xcommand CATCH [<!oErr!>]       => RECOVER [USING <oErr>] <-oErr->
#xcommand FINALLY                => ALWAYS


// [RAW] keyword: optional marker for hbformat (skip inner reformatting) — invisible at runtime.
#xcommand BLOCK <into:TO,INTO> <o> [RAW] => #pragma __cstream|<o> += %s

#xcommand BLOCK <into:TO,INTO> <o> [RAW] [ PARAMS [<v1>] [,<vn>] ] ;
=> ;
	#pragma __cstream|<o>+= HIX_Block( %s [,<(v1)>][+","+<(vn)>] [, @<v1>][, @<vn>] )


#define HIX_CRLF   ( Chr(13) + Chr(10) )

// Tipos de pool
#define HIX_POOL_DETECTOR   "DETECTOR"
#define HIX_POOL_HTTP       "HTTP"
#define HIX_POOL_WS         "WS"
#define HIX_POOL_REST       "REST"
#define HIX_POOL_HIX        "HIX"

// Tipos de conexión
#define HIX_CONN_HTTP       "HTTP"
#define HIX_CONN_WS         "WS"
#define HIX_CONN_SSE        "SSE"
#define HIX_CONN_LONGPOLL   "LONGPOLL"
#define HIX_CONN_UNKNOWN    "UNKNOWN"

// Modos de servidor
#define HIX_MODE_STANDALONE "standalone"
#define HIX_MODE_PROXIED    "proxied"

// Códigos de error
#define HIX_ERR_OK          0
#define HIX_ERR_SOCKET      1
#define HIX_ERR_TIMEOUT     2
#define HIX_ERR_PROTOCOL    3
#define HIX_ERR_POOL_FULL   4
#define HIX_ERR_CONFIG      5
#define HIX_ERR_SSL         6

// Métricas
#define HIXM_REQUESTS       "requests"
#define HIXM_ERRORS         "errors"
#define HIXM_ACTIVE_HTTP    "activehttp"
#define HIXM_ACTIVE_WS      "activews"
#define HIXM_ACTIVE_OTROS   "activeotros"
#define HIXM_BYTES_IN       "bytesin"
#define HIXM_BYTES_OUT      "bytesout"
#define HIXM_SATURATED      "saturated"
#define HIXM_UPTIME         "uptimesec"
#define HIXM_MEM_USED        "memused"
#define HIXM_MEM_PEAK        "mempeak"
#define HIXM_REQ_MS_MAX      "req_ms_max"
#define HIXM_REQ_MS_AVG      "req_ms_avg"
#define HIXM_REQ_MS_COUNT    "req_ms_count"
#define HIXM_REQ_MS_MAX_AT   "req_ms_max_at"
#define HIXM_REQ_MS_MAX_PATH "req_ms_max_path"
#define HIXM_REQ_SLOWEST_DYN  "req_slowest_dyn"
#define HIXM_REQ_SLOWEST_STAT "req_slowest_stat"
#define HIX_METRICS_TOP_N     10
#define HIXM_VCACHE_ENTRIES   "vcache_entries"
#define HIXM_VCACHE_BYTES     "vcache_bytes"
#define HIXM_VCACHE_HITS      "vcache_hits"
#define HIXM_VCACHE_MISSES    "vcache_misses"

// Tokens de detección de protocolo
#define HIX_TOKEN_WS_UPGRADE  "upgrade: websocket"
#define HIX_TOKEN_SSE_ACCEPT  "text/event-stream"
#define HIX_TOKEN_LONGPOLL    "x-hix-longpoll: true"
#define HIX_HTTP_VERBS        "GETPOSPUTDELPATHEAOPT"

// Defaults de red
#define HIX_DEFAULT_HOST         "0.0.0.0"
#define HIX_DEFAULT_PORT         80
#define HIX_DEFAULT_PEEK_BYTES   512
#define HIX_DEFAULT_PEEK_MS      100
#define HIX_DEFAULT_READ_MS      2000
#define HIX_DEFAULT_PEEK_TIMEOUT HIX_DEFAULT_PEEK_MS
#define HIX_DEFAULT_READ_TIMEOUT HIX_DEFAULT_READ_MS

// Módulos de tracing
#define HIX_MOD_APP          "app"
#define HIX_MOD_SERVER       "server"
#define HIX_MOD_WORKER_HTTP  "worker_http"
#define HIX_MOD_WORKER_WS    "worker_ws"
#define HIX_MOD_WORKER_OTROS "worker_otros"
#define HIX_MOD_POOL         "pool"
#define HIX_MOD_POOL_DETECT  "pool_detector"
#define HIX_MOD_METRICS      "metrics"
#define HIX_MOD_CONFIG       "config"
#define HIX_MOD_SOCKET       "socket"
#define HIX_MOD_MONITOR      "monitor"
#define HIX_MOD_RESPONSE     "response"
#define HIX_MOD_LOGGER       "logger"
#define HIX_MOD_ERROR        "error"
#define HIX_MOD_REQUEST      "request"
#define HIX_MOD_IO           "io"
#define HIX_MOD_ROUTER       "router"
#define HIX_MOD_DISPATCHER   "dispatcher"

// Endpoints internos
#define HIX_PATH_STATUS           "/hix-status"
#define HIX_PATH_PING             "/hix-ping"
#define HIX_PATH_BENCH_START      "/hix-bench-start"
#define HIX_PATH_BENCH_STOP       "/hix-bench-stop"
#define HIX_PATH_STOP             "/hix-stop"
#define HIX_PATH_MONITOR          "/hix-monitor"
#define HIX_PATH_TRACE            "/hix-trace"
#define HIX_PATH_CACHE_CLEAR      "/hix-cache-clear"
// Admin panel
#define HIX_PATH_INDEX            "/hix-index"
#define HIX_PATH_LOGIN            "/hix-login"
#define HIX_PATH_LOGOUT           "/hix-logout"
#define HIX_PATH_SETUP            "/hix-setup"
#define HIX_PATH_ROUTES_ADD       "/hix-routes/add"
#define HIX_PATH_ROUTES_DELETE    "/hix-routes/delete"
#define HIX_PATH_ROUTES_RELOAD    "/hix-routes/reload"
#define HIX_PATH_ROUTES_LIST      "/hix-routes/list"
#define HIX_PATH_ROUTES_LISTALL   "/hix-routes/listall"

// Códigos de error de lectura en THixRequest
#define HIX_REQ_ERR_NONE    0   // sin error
#define HIX_REQ_ERR_CLOSED  1   // socket cerrado o timeout
#define HIX_REQ_ERR_BADREQ  2   // request line inválida

// Límites de seguridad
#define HIX_MAX_HEADER_SIZE    8192
#define HIX_MAX_BODY_SIZE      10485760
#define HIX_WS_MAX_FRAME_SIZE  65536

// Chunked transfer encoding
#define HIX_CHUNK_SIZE         65536    // 64KB por trozo
#define HIX_CHUNK_THRESHOLD    1048576  // 1MB: umbral para auto-chunked

#define CLR_SAY_GET			   'GR+'
#define CLR_SAY_INFO			   'B+'

#endif
