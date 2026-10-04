/*-----------------------------------------------------------
  File ......: wdo_config.prg
  Author.....: Charly 9000
  Created....: 2026-09-29
  Modified...: 2026-09-29
  Version....: 1.0.0
  Description: Declarative bootstrap for WDO connection pools
               declared under "databases" in www/config.json.
               HIX_InitPoolsFromConfig() reads the section,
               dispatches each entry to its driver-specific
               initializer (WDO_InitPoolMySqlEx for mysql/mariadb)
               and registers the pool under the JSON key.
  Usage      : FUNCTION Main()
                  LOCAL oServer := THixServer():New()
                  HIX_InitPoolsFromConfig()   //  reads databases; aborts if any pool fails
                  oServer:Start()
                  ...
                  HIX_EndPoolsFromConfig()    //  closes them all
               RETU NIL
  Notes      : Driver name (case-insensitive) resolves to a Harbour
               function name via lookup table:
                  mysql   / mariadb  -> WDO_InitPoolMySqlEx
                  postgres / sqlite / mssql -> reserved (WARN)
               Fully backward compatible: WDO_InitPoolMySql(...)
               and manual WDO_RegisterPool sit alongside untouched.
 -----------------------------------------------------------*/

#include 'hix_const.ch'
#include 'hix_logger.ch'


//	=======================================================  //
//  HIX_InitPoolsFromConfig -- reads "databases" from
//  www/config.json and levants each declared pool.
//  Returns a hash { <cKey> => .T./.F. } indicating outcome.
//	=======================================================  //

FUNCTION HIX_InitPoolsFromConfig( lAbortOnFail )

   LOCAL hDatabases, hResult := { => }
   LOCAL cKey, hEntry, cDriver, lOk
   LOCAL lDebug := .F.

   hb_default( @lAbortOnFail, .T. )

   hDatabases := HIX_ConfigApp( "databases", NIL )

   IF ! HB_ISHASH( hDatabases ) .OR. Empty( hDatabases )
      l( _( 'WDO_LOG_POOLS_INIT_NONE' ) )
      HIX_Dbg( "[WDO_Config] InitPoolsFromConfig: no 'databases' section (or empty)" )
      RETU hResult
   ENDIF

   //  Debug opt-in: any pool entry with "debug": true flips the global
   //  HIX_Dbg flag so WDO Acquire/Release and HIX_Dbg() instrumentation
   //  in controllers start writing to dbg.log. First match wins (global
   //  switch); dbg.log is wiped so each run starts clean.
   FOR EACH cKey IN hb_HKeys( hDatabases )
      hEntry := hDatabases[ cKey ]
      IF HB_ISHASH( hEntry ) .AND. hb_HGetDef( hEntry, "debug", .F. )
         lDebug := .T.
         EXIT
      ENDIF
   NEXT
   IF lDebug
      HIX_DbgReset()
      HIX_DbgEnable( .T. )
      l( "[WDO_Config] databases.debug=true -> HIX_Dbg tracing enabled (dbg.log)" )
   ENDIF

   HIX_Dbg( "[WDO_Config] InitPoolsFromConfig: " + hb_NToS( Len( hDatabases ) ) + " entries" )

   FOR EACH cKey IN hb_HKeys( hDatabases )

      hEntry := hDatabases[ cKey ]

      IF ! HB_ISHASH( hEntry )
         lw( _( 'WDO_LOG_POOLS_INIT_BAD_ENTRY', cKey ) )
         hResult[ cKey ] := .F.
         LOOP
      ENDIF

      cDriver := Lower( AllTrim( hb_HGetDef( hEntry, "driver", "" ) ) )

      IF Empty( cDriver )
         lw( _( 'WDO_LOG_POOLS_INIT_NO_DRIVER', cKey ) )
         hResult[ cKey ] := .F.
         LOOP
      ENDIF

      HIX_Dbg( "[WDO_Config] InitPoolsFromConfig: '" + cKey + "' driver=" + cDriver )

      DO CASE
      CASE cDriver == "mysql" .OR. cDriver == "mariadb"
         lOk := WDO_InitPoolMySqlEx( cKey, hEntry )

      OTHERWISE
         lw( _( 'WDO_ERR_DRIVER_UNKNOWN', cDriver, cKey ) )
         HIX_Dbg( "[WDO_Config] InitPoolsFromConfig: driver '" + cDriver + ;
                  "' unknown for key '" + cKey + "'" )
         lOk := .F.
      ENDCASE

      hResult[ cKey ] := lOk

      IF ! lOk .AND. lAbortOnFail
         OutStd( "==> Fatal: database pool '" + cKey + "' (driver=" + cDriver + ;
                 ") failed to initialize. Server cannot start." + hb_eol() )
         OutStd( "Press any key to exit..." + hb_eol() )
         Inkey( 0 )
         ErrorLevel( 1 )
         QUIT
      ENDIF

   NEXT

   l( _( 'WDO_LOG_POOLS_INIT', _CountTrue( hResult ), Len( hResult ) ) )

RETU hResult


//	=======================================================  //
//  HIX_EndPoolsFromConfig -- unregisters every pool currently
//  in the driver registry (regardless of who registered it).
//	=======================================================  //

FUNCTION HIX_EndPoolsFromConfig()

   LOCAL aKeys, cKey, nCount

   aKeys  := WDO_ListPools()
   nCount := Len( aKeys )

   HIX_Dbg( "[WDO_Config] EndPoolsFromConfig: closing " + hb_NToS( nCount ) + " pool(s)" )

   FOR EACH cKey IN aKeys
      WDO_UnregisterPool( cKey )
   NEXT

   l( _( 'WDO_LOG_POOLS_END', nCount ) )

RETU NIL


//	=======================================================  //
//  _WdoResolveBErrorFromName -- resolves a Harbour function
//  name (string) to a codeblock via macro evaluation. Returns
//  NIL and logs WARN when the symbol is not statically linked.
//  Public (not STATIC) so wdo_mysql_pool.prg can share it.
//	=======================================================  //

FUNCTION _WdoResolveBErrorFromName( cName )

   LOCAL bBlock, oErr
   LOCAL cExpr := "{|oErr, oConn| " + cName + "( oErr, oConn ) }"

   //  hb_isFunction probes the symbol table without invoking. Skip the
   //  macro build for missing symbols -- otherwise &() succeeds and the
   //  block would only fail when eventually called, silently attaching
   //  a poisonous handler to every pooled conn.
   IF ! hb_isFunction( cName )
      lw( _( 'WDO_WARN_BERROR_NOT_FOUND', cName ) )
      RETU NIL
   ENDIF

   TRY
      bBlock := &( cExpr )
   CATCH oErr
      HB_SYMBOL_UNUSED( oErr )
      lw( _( 'WDO_WARN_BERROR_NOT_FOUND', cName ) )
      bBlock := NIL
   END

RETU bBlock


STATIC FUNCTION _CountTrue( hResult )

   LOCAL cKey, nOk := 0

   FOR EACH cKey IN hb_HKeys( hResult )
      IF hResult[ cKey ]
         nOk++
      ENDIF
   NEXT

RETU nOk
