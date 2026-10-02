/*-----------------------------------------------------------
  File ......: wdo_mysql_pool.prg
  Author.....: Charly 9000
  Created....: 2026-09-27
  Modified...: 2026-09-29
  Version....: 1.1.0
  Description: MySQL-specific pool initialization helpers.
               Builds a WDO_Pool of pre-opened WDO_MySql
               connections and registers it in the driver
               registry so WDO_Get(<key>) returns pooled
               connections from any worker thread.
  Usage      : WDO_InitPoolMySql( cHost, cUser, cPwd, cDb, ;
                                  nPort, nSize, nTimeoutMs, lPing, ;
                                  bError [, cDllPath] )
               -- OR, the hash variant used by HIX_InitPoolsFromConfig --
               WDO_InitPoolMySqlEx( cKey, hParams )
               ...
               WDO_EndPoolMySql()
  Notes      : Factory captures connection params (incl. optional DLL
               override) and optionally the error handler. When bError
               is passed, every pooled connection gets oConn:bError so
               any SetError() call bubbles up through a single app-wide
               codeblock. Init errors don't abort -- the pool starts
               with whatever connections opened successfully; failures
               log WARN.
 -----------------------------------------------------------*/

#include 'hix_const.ch'
#include 'hix_logger.ch'

#define WDO_MYSQL_POOL_KEY   "MYSQL"


//	=======================================================  //
//  Legacy positional API -- unchanged signature.
//  Wraps WDO_InitPoolMySqlEx registering under "MYSQL" key.
//	=======================================================  //

FUNCTION WDO_InitPoolMySql( cHost, cUser, cPwd, cDb, nPort, nSize, nTimeoutMs, lPing, bError, cDllPath )

   LOCAL hParams := { => }

   hb_default( @cHost,      "localhost" )
   hb_default( @cUser,      "" )
   hb_default( @cPwd,       "" )
   hb_default( @cDb,        "" )
   hb_default( @nPort,      3306 )
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
      hParams[ "berror_block" ] := bError    //  block-typed shortcut
   ENDIF
   IF cDllPath != NIL
      hParams[ "dll" ] := cDllPath
   ENDIF

RETU WDO_InitPoolMySqlEx( WDO_MYSQL_POOL_KEY, hParams )


//	=======================================================  //
//  Hash-based API. Consumed by HIX_InitPoolsFromConfig().
//  Also usable standalone when the caller prefers a hash
//  over the positional signature.
//
//  Recognized hParams keys (case-sensitive, snake_case):
//    host, user, pwd, db, port           -- connection
//    pool_size, timeout_ms, ping         -- pool tuning
//    dll                                 -- explicit DLL path
//    berror                              -- string: name of Harbour
//                                            function to resolve via
//                                            &(name+"()") at init
//    berror_block                        -- codeblock (bypasses berror
//                                            resolution; used by the
//                                            positional wrapper)
//	=======================================================  //

FUNCTION WDO_InitPoolMySqlEx( cKey, hParams )

   LOCAL oPool, bFactory, nOk
   LOCAL cHost, cUser, cPwd, cDb, cDllPath, cBErrorName, cDriver
   LOCAL nPort, nSize, nTimeoutMs
   LOCAL lPing
   LOCAL bError

   IF Empty( cKey )
      cKey := WDO_MYSQL_POOL_KEY
   ENDIF

   IF ! HB_ISHASH( hParams )
      hParams := { => }
   ENDIF

   cHost       := hb_HGetDef( hParams, "host",       "localhost" )
   cUser       := hb_HGetDef( hParams, "user",       "" )
   cPwd        := hb_HGetDef( hParams, "pwd",        "" )
   cDb         := hb_HGetDef( hParams, "db",         "" )
   nPort       := hb_HGetDef( hParams, "port",       3306 )
   nSize       := hb_HGetDef( hParams, "pool_size",  5 )
   nTimeoutMs  := hb_HGetDef( hParams, "timeout_ms", 5000 )
   lPing       := hb_HGetDef( hParams, "ping",       .T. )
   cDllPath    := hb_HGetDef( hParams, "dll",        NIL )
   cBErrorName := hb_HGetDef( hParams, "berror",     "" )
   cDriver     := Upper( AllTrim( hb_HGetDef( hParams, "driver", "MYSQL" ) ) )

   //  bError: codeblock takes precedence over string name (positional
   //  wrapper uses the block-shortcut; config-json path uses the name).
   IF hb_HHasKey( hParams, "berror_block" )
      bError := hParams[ "berror_block" ]
   ELSEIF ! Empty( cBErrorName )
      bError := _WdoResolveBErrorFromName( cBErrorName )
   ENDIF

   bFactory := {| nIdx | ;
      HB_SYMBOL_UNUSED( nIdx ), ;
      _WdoMySqlPoolNew( cHost, cUser, cPwd, cDb, nPort, bError, cDllPath, cKey, cDriver ) }

   HIX_Dbg( "[WDO_MySqlPool] InitPoolMySqlEx[" + cKey + "]: BEGIN " + cUser + "@" + cHost + ":" + ;
            hb_NToS( nPort ) + "/" + cDb + " size=" + hb_NToS( nSize ) + ;
            " timeout=" + hb_NToS( nTimeoutMs ) + "ms ping=" + iif( lPing, "T", "F" ) + ;
            iif( cDllPath != NIL, " dll=" + cDllPath, "" ) )

   oPool := WDO_Pool():New( cKey, nSize, nTimeoutMs, lPing, bFactory )

   nOk := oPool:Init()

   l( _( 'WDO_LOG_MYSQL_POOL_INIT', nOk, nSize, cUser, cHost, nPort, cDb ) )

   IF nOk == 0
      le( _( 'WDO_LOG_MYSQL_POOL_INIT_FAIL' ) )
      HIX_Dbg( "[WDO_MySqlPool] InitPoolMySqlEx[" + cKey + "]: FAILED, no connections opened" )
      RETU .F.
   ENDIF

   WDO_RegisterPool( cKey, oPool )

   HIX_Dbg( "[WDO_MySqlPool] InitPoolMySqlEx[" + cKey + "]: END OK (" + hb_NToS( nOk ) + "/" + ;
            hb_NToS( nSize ) + " connections)" )

RETU .T.


FUNCTION WDO_EndPoolMySql()

   LOCAL hStats := WDO_PoolStats( WDO_MYSQL_POOL_KEY )

   HIX_Dbg( "[WDO_MySqlPool] EndPoolMySql: BEGIN" + ;
            iif( hStats != NIL, ;
                 " (size=" + hb_NToS( hStats[ "size" ] ) + ;
                 " busy=" + hb_NToS( hStats[ "busy" ] ) + ;
                 " free=" + hb_NToS( hStats[ "free" ] ) + ")", ;
                 " (no pool registered)" ) )

   IF hStats != NIL
      l( _( 'WDO_LOG_MYSQL_POOL_END', hStats[ "size" ], hStats[ "busy" ] ) )
   ENDIF

   WDO_UnregisterPool( WDO_MYSQL_POOL_KEY )

   HIX_Dbg( "[WDO_MySqlPool] EndPoolMySql: END" )

RETU NIL


FUNCTION WDO_GetMySql()
RETU WDO_Get( WDO_MYSQL_POOL_KEY )


STATIC FUNCTION _WdoMySqlPoolNew( cHost, cUser, cPwd, cDb, nPort, bError, cDllPath, cKey, cDriver )
   LOCAL oConn := WDO_MySql():New( cHost, cUser, cPwd, cDb, nPort, .T., cDllPath, cDriver )
   IF oConn != NIL
      IF bError != NIL
         oConn:bError := bError
      ENDIF
      IF cKey != NIL .AND. ! Empty( cKey )
         oConn:cPoolKey := Lower( cKey )
      ENDIF
   ENDIF
RETU oConn
