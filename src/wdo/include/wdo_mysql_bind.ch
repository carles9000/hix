/*-----------------------------------------------------------
  File ......: wdo_mysql_bind.ch
  Author.....: Charly 9000
  Created....: 2026-09-30
  Modified...: 2026-09-30
  Version....: 1.0.0
  Description: MYSQL_BIND enum_field_types constants for the
               binary prepared-statements protocol (Alt A).
  Usage      : #include "wdo_mysql_bind.ch"
  Notes      : struct MYSQL_BIND has a platform-dependent
               layout (Windows LLP64 vs Linux LP64); offsets
               are resolved at runtime in WDO_MySqlStmtBin,
               not via #define.
 -----------------------------------------------------------*/

#ifndef _WDO_MYSQL_BIND_CH
#define _WDO_MYSQL_BIND_CH

//  enum enum_field_types (mysql.h) ------------------------------
#define WDO_MYSQL_TYPE_DECIMAL       0
#define WDO_MYSQL_TYPE_TINY          1
#define WDO_MYSQL_TYPE_SHORT         2
#define WDO_MYSQL_TYPE_LONG          3
#define WDO_MYSQL_TYPE_FLOAT         4
#define WDO_MYSQL_TYPE_DOUBLE        5
#define WDO_MYSQL_TYPE_NULL          6
#define WDO_MYSQL_TYPE_TIMESTAMP     7
#define WDO_MYSQL_TYPE_LONGLONG      8
#define WDO_MYSQL_TYPE_INT24         9
#define WDO_MYSQL_TYPE_DATE         10
#define WDO_MYSQL_TYPE_TIME         11
#define WDO_MYSQL_TYPE_DATETIME     12
#define WDO_MYSQL_TYPE_YEAR         13
#define WDO_MYSQL_TYPE_NEWDATE      14
#define WDO_MYSQL_TYPE_VARCHAR      15
#define WDO_MYSQL_TYPE_BIT          16
#define WDO_MYSQL_TYPE_TINY_BLOB   249
#define WDO_MYSQL_TYPE_MEDIUM_BLOB 250
#define WDO_MYSQL_TYPE_LONG_BLOB   251
#define WDO_MYSQL_TYPE_NEWDECIMAL  246
#define WDO_MYSQL_TYPE_BLOB        252
#define WDO_MYSQL_TYPE_VAR_STRING  253
#define WDO_MYSQL_TYPE_STRING      254

//  mysql_stmt_fetch return codes --------------------------------
#define WDO_STMT_FETCH_OK              0
#define WDO_STMT_FETCH_ERROR           1
#define WDO_STMT_FETCH_NO_DATA       100
#define WDO_STMT_FETCH_DATA_TRUNCATED 101

//  Layout note (v2.3.04): MYSQL_BIND.error pointer sits at
//  offset 24 on both ABIs (same slab as length/is_null/buffer,
//  all pointers of 8 bytes). MYSQL_BIND.error_value byte flag
//  sits at offset 88 on Windows LLP64 and 100 on Linux LP64,
//  following the same divergence pattern as is_unsigned /
//  is_null_value (resolved at runtime by _WdoBindLayoutInit).

//  enum enum_stmt_attr_type -------------------------------------
#define WDO_STMT_ATTR_UPDATE_MAX_LENGTH   0
#define WDO_STMT_ATTR_CURSOR_TYPE         1
#define WDO_STMT_ATTR_PREFETCH_ROWS       2

#endif
