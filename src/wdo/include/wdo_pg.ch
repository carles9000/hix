/*-----------------------------------------------------------
  File ......: wdo_pg.ch
  Author.....: Charly 9000
  Created....: 2026-10-18
  Modified...: 2026-10-18
  Version....: 1.0.0
  Description: Constants shared by WDO_PG driver files.
               Mirrors the stable libpq enums (connection
               status + PGresult status) so .prg files
               don't carry magic numbers.
  Usage      : #include "wdo_pg.ch"
  Notes      : Values match libpq-fe.h — stable since PG 7.x.
 -----------------------------------------------------------*/

#ifndef _WDO_PG_CH
#define _WDO_PG_CH

//  Pool registry key (uppercased by WDO_RegisterPool).
#define WDO_PG_POOL_KEY            "PG"

//  Default TCP port.
#define WDO_PG_DEFAULT_PORT        5432

//  Default application_name reported to pg_stat_activity.
#define WDO_PG_DEFAULT_APPNAME     "hix-worker"

//  PGconn status (PQstatus return values — stable, from libpq-fe.h).
#define CONNECTION_OK              0
#define CONNECTION_BAD             1

//  PGresult status (PQresultStatus return values — stable, from libpq-fe.h).
#define PGRES_EMPTY_QUERY          0
#define PGRES_COMMAND_OK           1
#define PGRES_TUPLES_OK            2
#define PGRES_COPY_OUT             3
#define PGRES_COPY_IN              4
#define PGRES_BAD_RESPONSE         5
#define PGRES_NONFATAL_ERROR       6
#define PGRES_FATAL_ERROR          7
#define PGRES_COPY_BOTH            8
#define PGRES_SINGLE_TUPLE         9

#endif
