/*-----------------------------------------------------------
  File ......: wdo_metrics.ch
  Author.....: Charly 9000
  Created....: 2026-09-30
  Modified...: 2026-09-30
  Version....: 1.0.0
  Description: WDO metrics constants. Counter keys used by
               WDO_Metric* API + top-N size.
  Usage      : #include "wdo_metrics.ch"
  Notes      : Names are snake_case, lower-case, mirror the
               style used by HIXM_* in hix_const.ch.
 -----------------------------------------------------------*/

#ifndef _WDO_METRICS_CH
#define _WDO_METRICS_CH

//  Query counters ------------------------------------------------
#define WDOM_QUERIES_TOTAL       "queries_total"
#define WDOM_QUERIES_SELECT      "queries_select"
#define WDOM_QUERIES_INSERT      "queries_insert"
#define WDOM_QUERIES_UPDATE      "queries_update"
#define WDOM_QUERIES_DELETE      "queries_delete"
#define WDOM_QUERIES_PREPARE     "queries_prepare"
#define WDOM_QUERIES_EXECUTE     "queries_execute"
#define WDOM_QUERIES_OTHER       "queries_other"
#define WDOM_QUERIES_ERRORS      "queries_errors"

//  Query timing (running avg / max / count) ---------------------
#define WDOM_QUERY_MS_MAX        "query_ms_max"
#define WDOM_QUERY_MS_AVG        "query_ms_avg"
#define WDOM_QUERY_MS_COUNT      "query_ms_count"

//  Pool counters ------------------------------------------------
#define WDOM_ACQUIRES_TOTAL      "acquires_total"
#define WDOM_ACQUIRES_TIMEOUT    "acquires_timeout"
#define WDOM_RELEASES_TOTAL      "releases_total"
#define WDOM_RELEASES_RECLAIMED  "releases_reclaimed"
#define WDOM_ACTIVE_CONN         "active_conn"

//  Acquire timing -----------------------------------------------
#define WDOM_ACQUIRE_MS_MAX      "acquire_ms_max"
#define WDOM_ACQUIRE_MS_AVG      "acquire_ms_avg"
#define WDOM_ACQUIRE_MS_COUNT    "acquire_ms_count"

//  Top-N slowest list key ---------------------------------------
#define WDOM_SLOWEST             "slowest"

//  Configuration ------------------------------------------------
#define WDO_METRICS_TOP_N        10
#define WDO_METRICS_SQL_CROP     200

#endif
