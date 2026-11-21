/*-----------------------------------------------------------
  File ......: wdo_pg_pool.prg
  Author.....: Charly 9000
  Created....: 2026-10-18
  Modified...: 2026-10-18
  Version....: 1.0.0
  Description: PostgreSQL pool initialization helpers. Builds a
               WDO_Pool of pre-opened WDO_PG connections and
               registers it under the "PG" key so WDO_Get("PG")
               returns pooled connections from any worker thread.
  Usage      : WDO_InitPoolPg( cHost, cUser, cPwd, cDb, nPort, ;
                               nSize, nTimeoutMs, lPing, bError ;
                               [, cDllPath] )
               -- OR, the hash variant used by HIX_InitPoolsFromConfig --
               WDO_InitPoolPgEx( cKey, hParams )
               ...
               WDO_EndPoolPg()
  Notes      : Hash variant accepts extra libpq keys that the
               positional API does not expose: sslmode,
               application_name, client_encoding. Default
               application_name is "hix-worker" so pg_stat_activity
               makes the HIX origin obvious.
 -----------------------------------------------------------*/

#include "hix_const.ch"
#include "hix_logger.ch"
#include "wdo_pg.ch"


//	=======================================================  //
//  Positional API — mirrors WDO_InitPoolMySql signature.
//	=======================================================  //

FUNCTION WDO_InitPoolPg( cHost, cUser, cPwd, cDb, nPort, nSize, nTimeoutMs, lPing, bError, cDllPath )

   LOCAL hParams := { => }

   hb_default( @cHost,      "localhost" )
   hb_default( @cUser,      "" )
   hb_default( @cPwd,       "" )
   hb_default( @cDb,        "" )
   hb_default( @nPort,      WDO_PG_DEFAULT_PORT )
   hb_default( @nSize,      5 )
   hb_default( @nTimeoutMs, 5000 )
   hb_default( @lPing,      .T. )

   hParams[ "host"       ] := cHost
   hParams[ "user"       ] := cUser
   hParams[ "pwd"        ] := cPwd
   hParams[ "db"         ] := cDb
   hParams[ "port"       ] := nPort
   hParams[ "pool_size"  ] := nSize
   hParams[ "timeout_ms" ] := nTimeoutMs
   hParams[ "ping"       ] := lPing

   IF bError != NIL
      hParams[ "berror_block" ] := bError
   ENDIF
   IF cDllPath != NIL
      hParams[ "dll" ] := cDllPath
   ENDIF

RETU WDO_InitPoolPgEx( WDO_PG_POOL_KEY, hParams )


//	=======================================================  //
//  Hash-based API. Consumed by HIX_InitPoolsFromConfig().
//
//  Recognized hParams keys (case-sensitive, snake_case):
//    host, user, pwd, db, port           -- connection
//    pool_size, timeout_ms, ping         -- pool tuning
//    dll                                 -- explicit libpq.dll path
//    read_timeout_s                      -- maps to statement_timeout
//    connect_timeout_s                   -- maps to connect_timeout
//    sslmode                             -- libpq sslmode (disable|...)
//    application_name                    -- pg_stat_activity label
//    client_encoding                     -- UTF8 | WIN1252 | ...
//    berror / berror_block               -- app-wide error handler
//	=======================================================  //

FUNCTION WDO_InitPoolPgEx( cKey, hParams )

   LOCAL oPool, bFactory, nOk
   LOCAL cHost, cUser, cPwd, cDb, cDllPath, cBErrorName
   LOCAL cSslMode, cAppName, cClientEnc
   LOCAL nPort, nSize, nTimeoutMs, nReadTimeout, nConnectTimeout
   LOCAL lPing
   LOCAL bError

   IF Empty( cKey )
      cKey := WDO_PG_POOL_KEY
   ENDIF

   IF ! HB_ISHASH( hParams )
      hParams := { => }
   ENDIF

   cHost           := hb_HGetDef( hParams, "host",             "localhost" )
   cUser           := hb_HGetDef( hParams, "user",             "" )
   cPwd            := hb_HGetDef( hParams, "pwd",              "" )
   cDb             := hb_HGetDef( hParams, "db",               "" )
   nPort           := hb_HGetDef( hParams, "port",             WDO_PG_DEFAULT_PORT )
   nSize           := hb_HGetDef( hParams, "pool_size",        5 )
   nTimeoutMs      := hb_HGetDef( hParams, "timeout_ms",       5000 )
   lPing           := hb_HGetDef( hParams, "ping",             .T. )
   cDllPath        := hb_HGetDef( hParams, "dll",              NIL )
   cBErrorName     := hb_HGetDef( hParams, "berror",           "" )
   //  statement_timeout (server-side bound on every query).
   nReadTimeout    := hb_HGetDef( hParams, "read_timeout_s",   30 )
   //  libpq connect_timeout.
   nConnectTimeout := hb_HGetDef( hParams, "connect_timeout_s", 10 )
   //  PG-specific extras.
   cSslMode        := hb_HGetDef( hParams, "sslmode",          "" )
   cAppName        := hb_HGetDef( hParams, "application_name", WDO_PG_DEFAULT_APPNAME )
   cClientEnc      := hb_HGetDef( hParams, "client_encoding",  "" )

   IF hb_HHasKey( hParams, "berror_block" )
      bError := hParams[ "berror_block" ]
   ELSEIF ! Empty( cBErrorName )
      bError := _WdoResolveBErrorFromName( cBErrorName )
   ENDIF

   bFactory := {| nIdx | ;
      HB_SYMBOL_UNUSED( nIdx ), ;
      _WdoPgPoolNew( cHost, cUser, cPwd, cDb, nPort, bError, cDllPath, cKey, ;
                     nReadTimeout, nConnectTimeout, ;
                     cSslMode, cAppName, cClientEnc ) }

   HIX_Dbg( "[WDO_PgPool] InitPoolPgEx[" + cKey + "]: BEGIN " + cUser + "@" + cHost + ":" + ;
            hb_NToS( nPort ) + "/" + cDb + " size=" + hb_NToS( nSize ) + ;
            " timeout=" + hb_NToS( nTimeoutMs ) + "ms ping=" + iif( lPing, "T", "F" ) + ;
            " stmt_to=" + hb_NToS( nReadTimeout ) + "s" + ;
            " conn_to=" + hb_NToS( nConnectTimeout ) + "s" + ;
            iif( ! Empty( cSslMode ),   " sslmode=" + cSslMode, "" ) + ;
            iif( ! Empty( cAppName ),   " app=" + cAppName, "" ) + ;
            iif( ! Empty( cClientEnc ), " enc=" + cClientEnc, "" ) + ;
            iif( cDllPath != NIL,       " dll=" + cDllPath, "" ) )

   oPool := WDO_Pool():New( cKey, nSize, nTimeoutMs, lPing, bFactory )

   nOk := oPool:Init()

   l( "WDO PG pool init: " + hb_NToS( nOk ) + "/" + hb_NToS( nSize ) + ;
      " " + cUser + "@" + cHost + ":" + hb_NToS( nPort ) + "/" + cDb )

   IF nOk == 0
      le( "WDO PG pool init failed — no connections opened" )
      HIX_Dbg( "[WDO_PgPool] InitPoolPgEx[" + cKey + "]: FAILED, no connections opened" )
      RETU .F.
   ENDIF

   WDO_RegisterPool( cKey, oPool )

   HIX_Dbg( "[WDO_PgPool] InitPoolPgEx[" + cKey + "]: END OK (" + hb_NToS( nOk ) + "/" + ;
            hb_NToS( nSize ) + " connections)" )

RETU .T.


FUNCTION WDO_EndPoolPg()

   LOCAL hStats := WDO_PoolStats( WDO_PG_POOL_KEY )

   HIX_Dbg( "[WDO_PgPool] EndPoolPg: BEGIN" + ;
            iif( hStats != NIL, ;
                 " (size=" + hb_NToS( hStats[ "size" ] ) + ;
                 " busy=" + hb_NToS( hStats[ "busy" ] ) + ;
                 " free=" + hb_NToS( hStats[ "free" ] ) + ")", ;
                 " (no pool registered)" ) )

   IF hStats != NIL
      l( "WDO PG pool end: size=" + hb_NToS( hStats[ "size" ] ) + ;
         " busy=" + hb_NToS( hStats[ "busy" ] ) )
   ENDIF

   WDO_UnregisterPool( WDO_PG_POOL_KEY )

   HIX_Dbg( "[WDO_PgPool] EndPoolPg: END" )

RETU NIL


FUNCTION WDO_GetPg()
RETU WDO_Get( WDO_PG_POOL_KEY )


STATIC FUNCTION _WdoPgPoolNew( cHost, cUser, cPwd, cDb, nPort, bError, cDllPath, cKey, ;
                               nReadTimeout, nConnectTimeout, ;
                               cSslMode, cAppName, cClientEnc )

   //  Defer Open() so we can set the DATAs that drive the connstring
   //  (statement_timeout, connect_timeout, sslmode, application_name,
   //  client_encoding) BEFORE PQconnectdb is invoked.
   LOCAL oConn := WDO_PG():New( cHost, cUser, cPwd, cDb, nPort, .F., cDllPath )

   IF oConn != NIL
      IF HB_ISNUMERIC( nReadTimeout )
         oConn:nReadTimeout := nReadTimeout
      ENDIF
      IF HB_ISNUMERIC( nConnectTimeout )
         oConn:nConnectTimeout := nConnectTimeout
      ENDIF
      IF HB_ISSTRING( cSslMode )   .AND. ! Empty( cSslMode )
         oConn:cSslMode := cSslMode
      ENDIF
      IF HB_ISSTRING( cAppName )   .AND. ! Empty( cAppName )
         oConn:cAppName := cAppName
      ENDIF
      IF HB_ISSTRING( cClientEnc ) .AND. ! Empty( cClientEnc )
         oConn:cClientEncoding := cClientEnc
      ENDIF
      IF bError != NIL
         oConn:bError := bError
      ENDIF
      IF cKey != NIL .AND. ! Empty( cKey )
         oConn:cPoolKey := Lower( cKey )
      ENDIF
      oConn:Open()
   ENDIF

RETU oConn
