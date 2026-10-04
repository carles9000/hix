/*-----------------------------------------------------------
  File ......: wdo_mysql.prg
  Author.....: Charly 9000
  Created....: 2026-09-27
  Modified...: 2026-09-27
  Version....: 2.0.0
  Description: MySQL / MariaDB connection class (long-lived).
               Owns native handles (pLib, hMySql, hConnection) and
               exposes DynCall wrappers. Query() returns a
               WDO_MySqlStmt with its own hRes + field metadata, so
               the connection state is never polluted by per-query
               data. Ready to be checked out from a pool serially.
  Usage      : oConn := WDO_MySql():New( cSrv, cUser, cPwd, cDb )
               oStmt := oConn:Query( "SELECT ..." )
  Notes      : Extracted from monolithic wdo_mysql.prg
 -----------------------------------------------------------*/

#include 'hix_const.ch'
#include 'hix_logger.ch'
#include 'hbclass.ch'
#include "hbdyn.ch"
#include "fileio.ch"
#include "wdo_metrics.ch"

#define VERSION_WDO_MYSQL_CONN     '2.0'

#define HB_VERSION_BITWIDTH        17
#define NULL                       0

//  libmysql option enums (stable since MySQL 4.1 / MariaDB 5.x).
//  See include/mysql.h: enum mysql_option.
#define MYSQL_OPT_CONNECT_TIMEOUT  0
#define MYSQL_OPT_READ_TIMEOUT     11
#define MYSQL_OPT_WRITE_TIMEOUT    12

STATIC snOpen  := 0
STATIC soMutex
STATIC sl_PoolGuardWarn := .T.

//  Dedupe of the "Mysql not running" console message. Keyed by
//  "host:port" so a pool init with N failing conns prints once.
STATIC s_hDownReported := NIL
STATIC s_mtxDown

//  Guard per-OS-thread: libmysql requires mysql_thread_init() on every
//  thread before any mysql_* call. Pool conns are created on main (init
//  implicit in mysql_init); worker threads check out and call mysql_query
//  on a different OS thread -> undefined behavior / hang under concurrency
//  without explicit init. THREAD STATIC = one init per worker lifetime.
THREAD STATIC sl_ThreadInited := .F.

INIT PROCEDURE _WDO_MySqlInit()
   soMutex        := hb_mutexCreate()
   s_mtxDown      := hb_mutexCreate()
   s_hDownReported := {=>}
RETURN

//	-------------------------------------------------------  //
//  Toggles the runtime warning emitted when WDO_MySql:New()
//  is called from inside an HTTP request handler. Default ON.
//  Returns the previous value.
//	-------------------------------------------------------  //
FUNCTION WDO_MySqlNewGuard( lOn )
   LOCAL lOld := sl_PoolGuardWarn
   IF hb_isLogical( lOn )
      sl_PoolGuardWarn := lOn
   ENDIF
RETURN lOld

CLASS WDO_MySql FROM WDO

   DATA cServer
   DATA cUserName
   DATA cPassword
   DATA cDatabase
   DATA nPort
   DATA cType                          INIT 'MYSQL'
   DATA cDllType

   DATA pLib
   DATA hMySql
   DATA hConnection

   DATA nSysCallConv
   DATA nSysLong
   DATA nTypePos

   DATA lConnect                       INIT .F.
   DATA lInUse                         INIT .F.
   DATA lInTrans                       INIT .F.
   DATA tLastUsed
   DATA lPersistent                    INIT .F.
   DATA lLog                           INIT .F.
   DATA lLogFile                       INIT .F.
   DATA lWeb                           INIT .T.
   DATA aLog                           INIT {}

   DATA oPool                          INIT NIL   // set when checked-out from a pool
   DATA cPoolKey                       INIT "-"   // pool registry key ("mysql", "analytics", ...) — "-" if outside pool
   DATA nStmtSeq                       INIT 0     // monotonic counter for unique PREPARE names

   DATA cDllPath                       INIT NIL   // explicit override (New() 7th param)
   DATA cDllSource                     INIT ''    // "override" | "WDO_LIB_MYSQL" | "WDO_PATH_MYSQL" | "default"

   //  Socket-level read/write timeout in seconds, applied via mysql_options
   //  (MYSQL_OPT_READ_TIMEOUT / MYSQL_OPT_WRITE_TIMEOUT) before connect.
   //  0 disables. Protects the pool from zombie child threads stuck forever
   //  in recv() when a controller times out via exec_timeout_ms -- without
   //  this, the FINALLY block in _HixRunHrb never fires and the pool slot
   //  stays busy indefinitely. 30 s is enough headroom for a slow query
   //  under load while bounding the leak window.
   DATA nReadTimeout                   INIT 30
   //  Connect-phase socket timeout (seconds). Separate from the TCP preflight
   //  that already short-circuits "server not running" cases.
   DATA nConnectTimeout                INIT 10

   CLASSDATA lUtf8                     INIT .F.

   METHOD New( cServer, cUser, cPwd, cDb, nPort, lOpen, cDllPath, cType ) CONSTRUCTOR
   METHOD Open()
   METHOD Close()
   METHOD End()                        INLINE ::Close()
   METHOD Destroy()                    INLINE ::Close()
   METHOD Exit()

   METHOD Ping()
   METHOD Reconnect()
   METHOD IsAlive()

   METHOD Escape( x )

   METHOD Query( cSql )
   METHOD Exec( cSql )
   METHOD Prepare( cSql )
   METHOD PrepareBin( cSql, lBinary )

   METHOD BeginTrans()
   METHOD Commit()
   METHOD Rollback()
   METHOD InTransaction()              INLINE ::lInTrans
   METHOD Transaction( bCode )

   METHOD Last_Insert_Id()
   METHOD Affected_Rows()              INLINE ::mysql_affected_rows()

   METHOD ServerInfo()                 INLINE ::mysql_get_server_info()
   METHOD ClientInfo()                 INLINE ::mysql_get_client_info()
   METHOD GetDllVersion()
   METHOD DllPath()                    INLINE iif( ::cDllPath == NIL, '', ::cDllPath )
   METHOD DllSource()                  INLINE ::cDllSource

   METHOD CountOpen()                  INLINE WDO_MySqlCountOpen()

   METHOD Version()                    INLINE VERSION_WDO_MYSQL_CONN
   METHOD VersionName()                INLINE 'WDO_MYSQL_CONN ' + VERSION_WDO_MYSQL_CONN

   //  DynCall wrappers
   METHOD mysql_init()
   METHOD mysql_close()
   METHOD mysql_options( nOption, nValue )
   METHOD mysql_real_connect( cServer, cUser, cPwd, cDb, nPort )
   METHOD mysql_error()
   METHOD mysql_query( cQuery )
   METHOD mysql_store_result()
   METHOD mysql_num_rows( hRes )
   METHOD mysql_num_fields( hRes )
   METHOD mysql_fetch_field( hRes )
   METHOD mysql_fetch_row( hRes )
   METHOD mysql_free_result( hRes )
   METHOD mysql_real_escape_string_quote( cQuery )
   METHOD mysql_get_server_info()
   METHOD mysql_get_client_info()
   METHOD mysql_affected_rows()
   METHOD mysql_insert_id()
   METHOD mysql_thread_init()
   METHOD mysql_thread_end()
   METHOD ThreadInitOnce()

   //  Prepared statements — binary protocol (Alt A)
   METHOD mysql_stmt_init()
   METHOD mysql_stmt_prepare( pStmt, cSql )
   METHOD mysql_stmt_bind_param( pStmt, pBind )
   METHOD mysql_stmt_execute( pStmt )
   METHOD mysql_stmt_affected_rows( pStmt )
   METHOD mysql_stmt_insert_id( pStmt )
   METHOD mysql_stmt_close( pStmt )
   METHOD mysql_stmt_error( pStmt )
   METHOD mysql_stmt_errno( pStmt )
   METHOD mysql_stmt_param_count( pStmt )
   METHOD mysql_stmt_send_long_data( pStmt, nIndex, cData )
   METHOD mysql_stmt_attr_set( pStmt, nAttr, pValue )
   METHOD mysql_stmt_result_metadata( pStmt )
   METHOD mysql_stmt_store_result( pStmt )
   METHOD mysql_stmt_bind_result( pStmt, pBind )
   METHOD mysql_stmt_fetch( pStmt )
   METHOD mysql_stmt_num_rows( pStmt )
   METHOD mysql_stmt_free_result( pStmt )

ENDCLASS

//	-------------------------------------------------------  //

METHOD New( cServer, cUserName, cPassword, cDatabase, nPort, lOpen, cDllPath, cType ) CLASS WDO_MySql

   hb_default( @cServer,   '' )
   hb_default( @cUserName, '' )
   hb_default( @cPassword, '' )
   hb_default( @cDatabase, '' )
   hb_default( @nPort,     3306 )
   hb_default( @lOpen,     .T. )

   ::Super:New()

   ::cServer   := cServer
   ::cUserName := cUserName
   ::cPassword := cPassword
   ::cDatabase := cDatabase
   ::nPort     := nPort

   //  Driver type override: "MYSQL" (default) or "MARIADB".
   IF ! Empty( cType )
      ::cType := Upper( AllTrim( cType ) )
   ENDIF

   //  Explicit DLL override: NIL means "use env/default cascade".
   //  Empty string is normalized to NIL so callers can pass hParams["dll"]
   //  from a JSON hash without pre-filtering.
   IF cDllPath != NIL .AND. ! Empty( cDllPath )
      ::cDllPath := cDllPath
   ENDIF

   IF lOpen
      ::Open()
   ENDIF

   //  Pool guard: warn if New() is used inside an HTTP request handler.
   //  Under load this pattern exhausts the OS ephemeral port range
   //  (WSAEADDRINUSE 10048 on Windows). Use WDO_Get("MYSQL") instead.
   //  See docs/mysql/pool_vs_open.md.
   IF ::lConnect .AND. sl_PoolGuardWarn .AND. HIX_GetRequest() != NIL
      lw( _( 'WDO_WARN_NEW_IN_REQUEST' ) )
   ENDIF

RETU SELF

//	-------------------------------------------------------  //

METHOD Open() CLASS WDO_MySql

   LOCAL cDll, cType
   LOCAL nTry := 0

   IF ::lConnect
      RETU NIL
   ENDIF

   IF( ::lLog, _d( 'WDO log activated' ), NIL )

   cType := Upper( ::cType )

   DO CASE
   CASE cType == 'MYSQL'
      ::cDllType := 'MySql'
   CASE cType == 'MARIADB'
      ::cDllType := 'MariaDB'
   OTHERWISE
      ::SetError( _( 'WDO_ERR_LIB_TYPE', cType ) )
      RETU SELF
   ENDCASE

   //  Fast TCP preflight: avoids ~2 min hang in mysql_real_connect when
   //  the MySQL server isn't listening. Uses the configured port or 3306.
   //  The "Mysql not running" message is deduped per host:port so a pool
   //  init with N connections prints it once.
   IF ! _WdoMySqlTcpProbe( ::cServer, iif( Empty( ::nPort ), 3306, ::nPort ), 2000 )
      _WdoMySqlReportDown( ::cServer, iif( Empty( ::nPort ), 3306, ::nPort ) )
      ::SetError( _( 'WDO_ERR_CONNECT', 'MySQL not reachable (TCP probe failed)' ) )
      RETU SELF
   ENDIF

   //  Resolve full DLL/so path from override + env vars + default. Stores
   //  the origin tag in ::cDllSource for diagnostics (see DllSource()).
   cDll         := _WdoResolveDll( cType, ::cDllPath, @::cDllSource )
   ::cDllPath   := cDll

   //  Skip File() check when the resolver returned a bare name (source
   //  "exedir"): existence is already verified against hb_DirBase(), and
   //  File() evaluates against CWD which may not match the exe directory.
   IF ::cDllSource != "exedir" .AND. ! File( cDll )
      _WdoMySqlReportDllFail( cDll, "not found", ::cDllType )
      ::SetError( _( 'WDO_ERR_LIB_NOT_FOUND', cDll + ' [' + ::cDllSource + ']' ), 'Loading dll' )
      RETU NIL
   ENDIF

   ::pLib := hb_LibLoad( cDll )

   IF ValType( ::pLib ) <> "P"
      IF( ::lLog, _d( 'WDO ' + ::cError + ' ' + cDll ), NIL )
      _WdoMySqlReportDllFail( cDll, "failed to load", ::cDllType )
      ::SetError( _( 'WDO_ERR_LIB_WRONG', Lower( cDll ) + ' [' + ::cDllSource + ']' ) )
      RETU NIL
   ENDIF

   ::nSysCallConv := hb_SysCallConv()
   ::nSysLong     := hb_SysLong()
   ::nTypePos     := hb_SysMyTypePos()

   ::hMySql := ::mysql_init()

   DO WHILE ::hMySql == 0 .AND. nTry < 3
      nTry++
      IF( ::lLog, _d( 'WDO MySQL library failed to initialize. Try: ' + Str( nTry ) ), NIL )
      Inkey( 0.1 )
      ::hMySql := ::mysql_init()
   ENDDO

   IF ::hMySql == 0
      ::SetError( _( 'WDO_ERR_INIT_FAIL' ) )
      RETU SELF
   ENDIF

   //  Apply socket read/write timeout BEFORE connect so libmysql wires it
   //  into the socket setup. Required to prevent child-thread leaks when
   //  the dispatcher aborts a controller via exec_timeout_ms: without a
   //  recv() timeout on the MySQL socket, a slow query keeps the child
   //  blocked forever and the pool slot never comes back.
   IF ::nReadTimeout > 0
      ::mysql_options( MYSQL_OPT_READ_TIMEOUT,  ::nReadTimeout )
      ::mysql_options( MYSQL_OPT_WRITE_TIMEOUT, ::nReadTimeout )
   ENDIF
   IF ::nConnectTimeout > 0
      ::mysql_options( MYSQL_OPT_CONNECT_TIMEOUT, ::nConnectTimeout )
   ENDIF

   //  On Linux, mysql_real_connect("localhost",...) uses Unix socket instead
   //  of TCP -- same trap the TCP preflight already avoids. Always force TCP
   //  by remapping "localhost" to "127.0.0.1" before the C call.
   ::hConnection := ::mysql_real_connect( ;
      iif( Lower( AllTrim( ::cServer ) ) == "localhost", "127.0.0.1", ::cServer ), ;
      ::cUserName, ::cPassword, ::cDatabase, ::nPort )

   IF ::hConnection != ::hMySql
      ::SetError( _( 'WDO_ERR_CONNECT', ::mysql_error() ) )
      RETU SELF
   ENDIF

   ::lConnect  := .T.
   ::tLastUsed := hb_DateTime()

   hb_mutexLock( soMutex )
   snOpen++
   hb_mutexUnlock( soMutex )

   //  Register driver as successfully loaded so the server banner shows
   //  it in the "WDO Loaded" line. Idempotent across pool connections.
   WDO_LoadedRegister( ::cDllType, WDO_Version() )

   //  Publish server/client version in the extended info registry so the
   //  banner can render "RDBMS <Driver> Server/Client" lines. Overwrites
   //  are idempotent across pool connections.
   WDO_InfoRegister( "RDBMS " + ::cDllType + " Server", ::mysql_get_server_info() )
   WDO_InfoRegister( "RDBMS " + ::cDllType + " Client", ::cDllType + " " + ::mysql_get_client_info() )

RETU NIL

//	-------------------------------------------------------  //

METHOD Close() CLASS WDO_MySql

   LOCAL lWasConnected

   //  Pooled instance: Close() releases back to the pool (does NOT tear
   //  down the TCP connection). The pool eventually calls Close() again
   //  after clearing oPool for the real teardown at shutdown.
   IF ::oPool != NIL
      HIX_Dbg( "[WDO_MySql] Close (tid=" + hb_NToS( hb_threadId( hb_threadSelf() ) ) + ;
               "): pooled -> Release to pool (no TCP teardown)" )
      ::oPool:Release( SELF )
      RETU NIL
   ENDIF

   HIX_Dbg( "[WDO_MySql] Close (tid=" + hb_NToS( hb_threadId( hb_threadSelf() ) ) + ;
            "): TEARDOWN (mysql_close + HB_LibFree)" )

   lWasConnected := ::lConnect

   IF ValType( ::pLib ) == "P"

      IF( ::lLog, _d( 'WDO Close proc' ), NIL )

      ::mysql_close()

      HB_LibFree( ::pLib )

      ::pLib        := NIL
      ::hMySql      := NIL
      ::hConnection := NIL
      ::lConnect    := .F.

   ENDIF

   IF lWasConnected
      hb_mutexLock( soMutex )
      snOpen--
      hb_mutexUnlock( soMutex )
   ENDIF

RETU NIL

//	-------------------------------------------------------  //

METHOD Exit() CLASS WDO_MySql

   IF ::lPersistent
      IF( ::lLog, _d( 'WDO Persistent' ), NIL )
      RETU NIL
   ENDIF

RETU NIL

//	-------------------------------------------------------  //

METHOD Ping() CLASS WDO_MySql

   LOCAL oStmt

   IF ! ::lConnect .OR. ::hConnection == 0
      RETU .F.
   ENDIF

   oStmt := ::Query( "SELECT 1" )

   IF oStmt == NIL .OR. oStmt:lError .OR. oStmt:hRes == 0
      RETU .F.
   ENDIF

   oStmt:Free()

RETU .T.

//	-------------------------------------------------------  //

METHOD Reconnect() CLASS WDO_MySql

   ::Close()
   ::Open()

RETU ::lConnect

//	-------------------------------------------------------  //

METHOD IsAlive() CLASS WDO_MySql

RETU ::lConnect .AND. ::Ping()

//	-------------------------------------------------------  //
/*	Ejecuta wdo_addslashes sobre las variables a salvar:
	l'aliga -> l\'aliga
	Hello "World" -> Hello \"World\"
*/
METHOD Escape( hRow ) CLASS WDO_MySql

   LOCAL n, aPair, nLen
   LOCAL cType := ValType( hRow )

   DO CASE
   CASE cType == 'H'
      nLen := Len( hRow )
      FOR n := 1 TO nLen
         aPair := HB_HPairAt( hRow, n )
         IF ValType( aPair[2] ) == 'C' .OR. ValType( aPair[2] ) == 'M'
            hRow[ aPair[1] ] := wdo_addslashes( aPair[2] )
         ENDIF
      NEXT

   CASE cType == 'A'
      nLen := Len( hRow )
      FOR n := 1 TO nLen
         IF ValType( hRow[n] ) == 'C' .OR. ValType( hRow[n] ) == 'M'
            hRow[n] := wdo_addslashes( hRow[n] )
         ENDIF
      NEXT

   CASE cType == 'C' .OR. cType == 'M'
      hRow := wdo_addslashes( hRow )

   ENDCASE

RETU hRow

//	-------------------------------------------------------  //

METHOD Query( cSql ) CLASS WDO_MySql

   LOCAL nRet
   LOCAL hRes := 0
   LOCAL oStmt
   LOCAL nT0

   IF ::hConnection == NIL .OR. ::hConnection == 0
      RETU NIL
   ENDIF

   IF( ::lLog, _d( 'WDO ' + cSql ), NIL )

   nT0  := hb_MilliSeconds()
   nRet := ::mysql_query( cSql )

   IF nRet == 0
      //  0 = OK. mysql_store_result devuelve 0 en UPDATE/DELETE/INSERT.
      hRes  := ::mysql_store_result()
      oStmt := WDO_MySqlStmt():New( SELF, cSql, hRes )
   ELSE
      ::SetError( ::mysql_error() )
      oStmt         := WDO_MySqlStmt():New( SELF, cSql, 0 )
      oStmt:lError  := .T.
      oStmt:cError  := ::cError
      WDO_Metric( WDOM_QUERIES_ERRORS )
   ENDIF

   WDO_MetricQuery( ::cPoolKey, cSql, hb_MilliSeconds() - nT0, NIL )

   ::tLastUsed := hb_DateTime()

RETU oStmt

//	-------------------------------------------------------  //
//  Atajo: ejecuta y libera el Stmt. Devuelve filas afectadas.
METHOD Exec( cSql ) CLASS WDO_MySql

   LOCAL oStmt := ::Query( cSql )
   LOCAL nAff  := 0

   IF oStmt != NIL
      nAff := oStmt:nAffectedRows
      oStmt:Free()
   ENDIF

RETU nAff

//	-------------------------------------------------------  //
//  Prepared statement (Alt B — server-side PREPARE emulation).
//  Traduce el SQL de usuario (con `?` o `:name`) a un
//  PREPARE + placeholders numerados y devuelve un WDO_MySqlStmt
//  en modo lPrepared. La ejecución real ocurre en oStmt:Execute()
//  tras BindParam.
//	-------------------------------------------------------  //
METHOD Prepare( cSql ) CLASS WDO_MySql

   LOCAL oStmt
   LOCAL cSqlServer
   LOCAL nParamCount := 0
   LOCAL hParamMap   := {=>}
   LOCAL cStmtName
   LOCAL cPrepSql
   LOCAL nT0

   IF ::hConnection == NIL .OR. ::hConnection == 0
      RETU NIL
   ENDIF

   //  1) Escanear cSql: reemplazar :name por ? y contar totales.
   cSqlServer := _HixWdoPrepareScan( cSql, @nParamCount, @hParamMap )

   //  2) Nombre único de statement (thread-safe: seq por conexión + tid).
   ::nStmtSeq++
   cStmtName := "hix_stmt_" + hb_NToS( hb_ThreadSelf() ) + "_" + ;
                hb_NToS( ::nStmtSeq )

   //  3) PREPARE en el servidor.
   cPrepSql := "PREPARE " + cStmtName + " FROM '" + ;
               wdo_addslashes( cSqlServer ) + "'"

   IF( ::lLog, _d( 'WDO PREPARE ' + cSql ), NIL )

   nT0 := hb_MilliSeconds()

   IF ::mysql_query( cPrepSql ) != 0
      ::SetError( ::mysql_error(), "Prepare" )
      oStmt              := WDO_MySqlStmt():New( SELF, cSql, 0 )
      oStmt:lError       := .T.
      oStmt:cError       := ::cError
      oStmt:lPrepared    := .F.
      WDO_Metric( WDOM_QUERIES_ERRORS )
      WDO_MetricQuery( ::cPoolKey, "PREPARE " + cSql, ;
                       hb_MilliSeconds() - nT0, NIL )
      RETU oStmt
   ENDIF

   WDO_MetricQuery( ::cPoolKey, "PREPARE " + cSql, ;
                    hb_MilliSeconds() - nT0, NIL )

   oStmt := WDO_MySqlStmt():New( SELF, cSql, 0 )
   oStmt:lPrepared    := .T.
   oStmt:cStmtName    := cStmtName
   oStmt:cSqlOriginal := cSql
   oStmt:cSqlServer   := cSqlServer
   oStmt:nParamCount  := nParamCount
   oStmt:hParamMap    := hParamMap
   oStmt:aParams      := Array( nParamCount )

   ::tLastUsed := hb_DateTime()

RETU oStmt

//	-------------------------------------------------------  //
//  PrepareBin( cSql, lBinary := .T. )
//
//  Entry point unificado para prepared statements. Con lBinary=.T.
//  (default) devuelve WDO_MySqlStmtBin (Alt A, protocolo binario
//  nativo mysql_stmt_*). Con lBinary=.F. delega en ::Prepare( cSql )
//  y devuelve WDO_MySqlStmt (Alt B, protocolo texto emulado).
//
//  Ambos implementan BindParam / BindLong / Execute / Close, así
//  el caller puede intercambiar modo sin cambiar el resto del código.
//	-------------------------------------------------------  //
METHOD PrepareBin( cSql, lBinary ) CLASS WDO_MySql

   hb_default( @lBinary, .T. )

   IF ! lBinary
      RETU ::Prepare( cSql )
   ENDIF

RETU WDO_MySqlStmtBin():New( SELF, cSql )

//	-------------------------------------------------------  //
//  Scanner de placeholders para Prepare. Convierte `:name`
//  en `?` respetando literales/comments SQL y devuelve el mapa
//  nombre → índice + el contador total (incluye `?` literales).
//	-------------------------------------------------------  //
STATIC FUNCTION _HixWdoPrepareScan( cSql, /*@*/ nParamCount, /*@*/ hParamMap )

   LOCAL cOut    := ""
   LOCAL nLen    := Len( cSql )
   LOCAL i       := 1
   LOCAL cCh, cNext, cName, j

   DO WHILE i <= nLen

      cCh := SubStr( cSql, i, 1 )

      DO CASE

      CASE cCh == "'"                  //  literal single-quote
         cOut += cCh
         i++
         DO WHILE i <= nLen
            cNext := SubStr( cSql, i, 1 )
            cOut  += cNext
            IF cNext == "\"
               //  escape: consume el siguiente si lo hay
               IF i + 1 <= nLen
                  cOut += SubStr( cSql, i + 1, 1 )
                  i += 2
                  LOOP
               ENDIF
            ELSEIF cNext == "'"
               //  '' → escape doblado
               IF i + 1 <= nLen .AND. SubStr( cSql, i + 1, 1 ) == "'"
                  cOut += "'"
                  i += 2
                  LOOP
               ENDIF
               i++
               EXIT
            ENDIF
            i++
         ENDDO

      CASE cCh == '"'                  //  literal double-quote
         cOut += cCh
         i++
         DO WHILE i <= nLen
            cNext := SubStr( cSql, i, 1 )
            cOut  += cNext
            IF cNext == "\"
               IF i + 1 <= nLen
                  cOut += SubStr( cSql, i + 1, 1 )
                  i += 2
                  LOOP
               ENDIF
            ELSEIF cNext == '"'
               IF i + 1 <= nLen .AND. SubStr( cSql, i + 1, 1 ) == '"'
                  cOut += '"'
                  i += 2
                  LOOP
               ENDIF
               i++
               EXIT
            ENDIF
            i++
         ENDDO

      CASE cCh == "`"                  //  identifier quote
         cOut += cCh
         i++
         DO WHILE i <= nLen
            cNext := SubStr( cSql, i, 1 )
            cOut  += cNext
            i++
            IF cNext == "`" ; EXIT ; ENDIF
         ENDDO

      CASE cCh == "-" .AND. i + 1 <= nLen .AND. ;
           SubStr( cSql, i + 1, 1 ) == "-"        //  -- comment to EOL
         DO WHILE i <= nLen
            cNext := SubStr( cSql, i, 1 )
            cOut  += cNext
            i++
            IF cNext == Chr( 10 ) ; EXIT ; ENDIF
         ENDDO

      CASE cCh == "/" .AND. i + 1 <= nLen .AND. ;
           SubStr( cSql, i + 1, 1 ) == "*"        //  /* ... */ block
         cOut += "/*"
         i += 2
         DO WHILE i <= nLen
            cNext := SubStr( cSql, i, 1 )
            cOut  += cNext
            i++
            IF cNext == "*" .AND. i <= nLen .AND. ;
               SubStr( cSql, i, 1 ) == "/"
               cOut += "/"
               i++
               EXIT
            ENDIF
         ENDDO

      CASE cCh == "?"                  //  positional placeholder
         nParamCount++
         cOut += "?"
         i++

      CASE cCh == ":"                  //  named placeholder or default
         //  :name → placeholder si el siguiente char es letra/_
         IF i + 1 <= nLen
            cNext := SubStr( cSql, i + 1, 1 )
            IF ( cNext >= "A" .AND. cNext <= "Z" ) .OR. ;
               ( cNext >= "a" .AND. cNext <= "z" ) .OR. cNext == "_"
               cName := ""
               j := i + 1
               DO WHILE j <= nLen
                  cNext := SubStr( cSql, j, 1 )
                  IF ( cNext >= "A" .AND. cNext <= "Z" ) .OR. ;
                     ( cNext >= "a" .AND. cNext <= "z" ) .OR. ;
                     ( cNext >= "0" .AND. cNext <= "9" ) .OR. ;
                     cNext == "_"
                     cName += cNext
                     j++
                  ELSE
                     EXIT
                  ENDIF
               ENDDO
               nParamCount++
               hParamMap[ ":" + cName ] := nParamCount
               cOut += "?"
               i := j
               LOOP
            ENDIF
         ENDIF
         cOut += ":"
         i++

      OTHERWISE
         cOut += cCh
         i++

      ENDCASE

   ENDDO

RETU cOut

//	-------------------------------------------------------  //
//  Transacciones (a nivel de conexión, no de Stmt)
//	-------------------------------------------------------  //

METHOD BeginTrans() CLASS WDO_MySql

   IF ! ::lConnect .OR. ::hConnection == 0
      RETU .F.
   ENDIF

   IF ::lInTrans
      RETU .F.
   ENDIF

   IF ::mysql_query( "START TRANSACTION" ) != 0
      ::SetError( ::mysql_error(), "BeginTrans" )
      RETU .F.
   ENDIF

   ::lInTrans  := .T.
   ::tLastUsed := hb_DateTime()

RETU .T.

//	-------------------------------------------------------  //

METHOD Commit() CLASS WDO_MySql

   IF ! ::lInTrans
      RETU .F.
   ENDIF

   IF ::mysql_query( "COMMIT" ) != 0
      ::SetError( ::mysql_error(), "Commit" )
      ::lInTrans := .F.
      RETU .F.
   ENDIF

   ::lInTrans  := .F.
   ::tLastUsed := hb_DateTime()

RETU .T.

//	-------------------------------------------------------  //

METHOD Rollback() CLASS WDO_MySql

   IF ! ::lInTrans
      RETU .F.
   ENDIF

   IF ::mysql_query( "ROLLBACK" ) != 0
      ::SetError( ::mysql_error(), "Rollback" )
      ::lInTrans := .F.
      RETU .F.
   ENDIF

   ::lInTrans  := .F.
   ::tLastUsed := hb_DateTime()

RETU .T.

//	-------------------------------------------------------  //
//  Azucar: begin + eval + commit / rollback + re-raise
METHOD Transaction( bCode ) CLASS WDO_MySql

   LOCAL uRet, oErr

   IF ! ::BeginTrans()
      RETU NIL
   ENDIF

   TRY
      uRet := Eval( bCode, SELF )
      ::Commit()
   CATCH oErr
      ::Rollback()
      Break( oErr )
   END

RETU uRet

//	-------------------------------------------------------  //

METHOD Last_Insert_Id() CLASS WDO_MySql

   IF ::hConnection == NIL .OR. ::hConnection == 0
      RETU -1
   ENDIF

RETU ::mysql_insert_id()

//	-------------------------------------------------------  //

METHOD GetDllVersion() CLASS WDO_MySql

   LOCAL cVer := "Unknown"

   IF ::pLib != NIL
      cVer := ::mysql_get_client_info()
   ENDIF

RETU "Library Type: " + ::cDllType + " | Client Version: " + cVer

//	=======================================================  //
//  DynCall wrappers
//	=======================================================  //

METHOD mysql_init() CLASS WDO_MySql

   LOCAL u, n, oError
   LOCAL cInfo := ''

   TRY

      u := hb_DynCall( { "mysql_init", ::pLib, hb_bitOr( ::nSysLong, ::nSysCallConv ) }, NULL )

   CATCH oError

      cInfo := 'Error mysql init' + Chr(10) + Chr(13)
      cInfo += 'Description: ' + oError:description + Chr(10) + Chr(13)

      IF ! Empty( oError:operation )
         cInfo += 'Operation: ' + oError:operation + Chr(10) + Chr(13)
      ENDIF

      IF ValType( oError:Args ) == "A"
         cInfo += 'Args:' + Chr(10) + Chr(13)
         FOR n := 1 TO Len( oError:Args )
            cInfo += "[" + Str( n, 4 ) + "] = " + ValType( oError:Args[n] ) + ;
                     "   " + hb_CStr( oError:Args[n] ) + ;
                     If( ValType( oError:Args[n] ) == "A", " Len: " + ;
                     AllTrim( Str( Len( oError:Args[n] ) ) ), "" ) + Chr(10) + Chr(13)
         NEXT
      ENDIF

      _d( cInfo )

   END

RETU u

//	-------------------------------------------------------  //

METHOD mysql_close() CLASS WDO_MySql

RETU hb_DynCall( { "mysql_close", ::pLib, ::nSysCallConv, ::nSysLong }, ::hMySql )

//	-------------------------------------------------------  //
//  int mysql_options( MYSQL *, enum mysql_option, const void *arg )
//  Numeric options (READ/WRITE/CONNECT_TIMEOUT) expect arg to point at
//  an unsigned int. Marshal the value LE into a 4-byte raw buffer and
//  pass as CHAR_UNSIGNED_PTR -- that path memcpy's the string verbatim
//  into a native buffer (no CDP translation; see hb_dyn.c:198) which is
//  what libmysql dereferences as const unsigned int *.
METHOD mysql_options( nOption, nValue ) CLASS WDO_MySql

   LOCAL cBuf

   cBuf := Chr( hb_bitAnd( nValue, 0xFF ) ) + ;
           Chr( hb_bitAnd( hb_bitShift( nValue,  -8 ), 0xFF ) ) + ;
           Chr( hb_bitAnd( hb_bitShift( nValue, -16 ), 0xFF ) ) + ;
           Chr( hb_bitAnd( hb_bitShift( nValue, -24 ), 0xFF ) )

RETU hb_DynCall( { "mysql_options", ::pLib, ;
                    hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ), ::nSysLong, ;
                    HB_DYN_CTYPE_INT, HB_DYN_CTYPE_CHAR_UNSIGNED_PTR }, ;
                  ::hMySql, nOption, cBuf )

//	-------------------------------------------------------  //

METHOD mysql_real_connect( cServer, cUserName, cPassword, cDataBaseName, nPort ) CLASS WDO_MySql

   IF nPort == NIL
      nPort := 3306
   ENDIF

RETU hb_DynCall( { "mysql_real_connect", ::pLib, hb_bitOr( ::nSysLong,;
                    ::nSysCallConv ), ::nSysLong,;
                    HB_DYN_CTYPE_CHAR_PTR, HB_DYN_CTYPE_CHAR_PTR, HB_DYN_CTYPE_CHAR_PTR, HB_DYN_CTYPE_CHAR_PTR,;
                    HB_DYN_CTYPE_LONG, HB_DYN_CTYPE_LONG, HB_DYN_CTYPE_LONG },;
                    ::hMySql, cServer, cUserName, cPassword, cDataBaseName, nPort, 0, 0 )

//	-------------------------------------------------------  //

METHOD mysql_error() CLASS WDO_MySql

RETU hb_DynCall( { "mysql_error", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR,;
                    ::nSysCallConv ), ::nSysLong }, ::hMySql )

//	-------------------------------------------------------  //

METHOD mysql_query( cQuery ) CLASS WDO_MySql

   LOCAL u
   LOCAL bNewError := {| oError | Break( oError ) }
   LOCAL bOldError := ErrorBlock( bNewError )

   ::ThreadInitOnce()

   BEGIN SEQUENCE
      u := hb_DynCall( { "mysql_query", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                          ::nSysCallConv ), ::nSysLong, HB_DYN_CTYPE_CHAR_PTR },;
                          ::hConnection, cQuery )
   RECOVER
      ::SetError( ::mysql_error() )
      ErrorBlock( bOldError )
      RETU NIL
   END SEQUENCE

   ErrorBlock( bOldError )

RETU u

//	-------------------------------------------------------  //

METHOD mysql_real_escape_string_quote( cQuery ) CLASS WDO_MySql

   cQuery := StrTran( cQuery, "'", "\'" )

RETU cQuery

//	-------------------------------------------------------  //

METHOD mysql_store_result() CLASS WDO_MySql

RETU hb_DynCall( { "mysql_store_result", ::pLib, hb_bitOr( ::nSysLong,;
                    ::nSysCallConv ), ::nSysLong }, ::hMySql )

//	-------------------------------------------------------  //

METHOD mysql_num_rows( hRes ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_num_rows", ::pLib, hb_bitOr( ::nSysLong,;
                    ::nSysCallConv ), ::nSysLong }, hRes )

//	-------------------------------------------------------  //

METHOD mysql_num_fields( hRes ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_num_fields", ::pLib, hb_bitOr( HB_DYN_CTYPE_LONG_UNSIGNED,;
                    ::nSysCallConv ), ::nSysLong }, hRes )

//	-------------------------------------------------------  //

METHOD mysql_fetch_field( hRes ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_fetch_field", ::pLib, hb_bitOr( ::nSysLong,;
                    ::nSysCallConv ), ::nSysLong }, hRes )

//	-------------------------------------------------------  //

METHOD mysql_fetch_row( hRes ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_fetch_row", ::pLib, hb_bitOr( ::nSysLong,;
                    ::nSysCallConv ), ::nSysLong }, hRes )

//	-------------------------------------------------------  //

METHOD mysql_free_result( hRes ) CLASS WDO_MySql

   LOCAL u, n, oError
   LOCAL cInfo := ''

   TRY

      u := hb_DynCall( { "mysql_free_result", ::pLib, ::nSysCallConv, ::nSysLong }, hRes )

   CATCH oError

      cInfo := 'Error mysql_free_result' + Chr(10) + Chr(13)
      cInfo += 'Description: ' + oError:description + Chr(10) + Chr(13)

      IF ! Empty( oError:operation )
         cInfo += 'Operation: ' + oError:operation + Chr(10) + Chr(13)
      ENDIF

      IF ValType( oError:Args ) == "A"
         cInfo += 'Args:' + Chr(10) + Chr(13)
         FOR n := 1 TO Len( oError:Args )
            cInfo += "[" + Str( n, 4 ) + "] = " + ValType( oError:Args[n] ) + ;
                     "   " + hb_CStr( oError:Args[n] ) + ;
                     If( ValType( oError:Args[n] ) == "A", " Len: " + ;
                     AllTrim( Str( Len( oError:Args[n] ) ) ), "" ) + Chr(10) + Chr(13)
         NEXT
      ENDIF

      _d( cInfo )

   END

RETU u

//	-------------------------------------------------------  //

METHOD mysql_get_server_info() CLASS WDO_MySql

RETU hb_DynCall( { "mysql_get_server_info", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR,;
                    ::nSysCallConv ), ::nSysLong }, ::hMySql )

//	-------------------------------------------------------  //

METHOD mysql_get_client_info() CLASS WDO_MySql

RETU hb_DynCall( { "mysql_get_client_info", ::pLib,;
                    hb_bitOr( HB_DYN_CTYPE_CHAR_PTR, ::nSysCallConv ) } )

//	-------------------------------------------------------  //
//  NUEVO: my_ulonglong mysql_affected_rows( MYSQL * )
METHOD mysql_affected_rows() CLASS WDO_MySql

RETU hb_DynCall( { "mysql_affected_rows", ::pLib, hb_bitOr( ::nSysLong,;
                    ::nSysCallConv ), ::nSysLong }, ::hConnection )

//	-------------------------------------------------------  //
//  NUEVO: my_ulonglong mysql_insert_id( MYSQL * )
METHOD mysql_insert_id() CLASS WDO_MySql

RETU hb_DynCall( { "mysql_insert_id", ::pLib, hb_bitOr( ::nSysLong,;
                    ::nSysCallConv ), ::nSysLong }, ::hConnection )

//	-------------------------------------------------------  //
//  my_bool mysql_thread_init( void )
//  Returns 0 on success. Must be called once per OS thread before any
//  mysql_* call. my_bool is 1 byte on Win64 -> read as INT and mask.
METHOD mysql_thread_init() CLASS WDO_MySql

   LOCAL nRc := hb_DynCall( { "mysql_thread_init", ::pLib, ;
                              hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ) } )

RETU hb_bitAnd( nRc, 0xFF )

//	-------------------------------------------------------  //
//  void mysql_thread_end( void )
//  Releases per-thread TLS. HIX does not expose a worker-exit hook, so
//  this is provided for completeness; not auto-called.
METHOD mysql_thread_end() CLASS WDO_MySql

   hb_DynCall( { "mysql_thread_end", ::pLib, ;
                 hb_bitOr( HB_DYN_CTYPE_VOID, ::nSysCallConv ) } )

RETU NIL

//	-------------------------------------------------------  //
//  Idempotent per-OS-thread init guard. Called from the top of every
//  method that issues libmysql commands (mysql_query, mysql_stmt_execute).
//  Cost after first call per thread: one THREAD STATIC compare.
METHOD ThreadInitOnce() CLASS WDO_MySql

   IF ! sl_ThreadInited
      ::mysql_thread_init()
      sl_ThreadInited := .T.
   ENDIF

RETU NIL

//	=======================================================  //
//  Prepared statements — binary protocol (Alt A)
//	=======================================================  //

METHOD mysql_stmt_init() CLASS WDO_MySql

RETU hb_DynCall( { "mysql_stmt_init", ::pLib, hb_bitOr( ::nSysLong,;
                    ::nSysCallConv ), ::nSysLong }, ::hConnection )

//	-------------------------------------------------------  //

METHOD mysql_stmt_prepare( pStmt, cSql ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_stmt_prepare", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong, HB_DYN_CTYPE_CHAR_PTR,;
                    HB_DYN_CTYPE_LONG_UNSIGNED },;
                    pStmt, cSql, Len( cSql ) )

//	-------------------------------------------------------  //

METHOD mysql_stmt_bind_param( pStmt, pBind ) CLASS WDO_MySql

   //  Returns my_bool (1 byte). Read as INT and mask low byte -- HB_DYN_CTYPE_BOOL
   //  can misread garbage in high bytes of RAX on Win64.
   LOCAL nRc := hb_DynCall( { "mysql_stmt_bind_param", ::pLib,;
                              hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                              ::nSysLong, HB_DYN_CTYPE_VOID_PTR },;
                              pStmt, pBind )

RETU hb_bitAnd( nRc, 0xFF ) != 0

//	-------------------------------------------------------  //

METHOD mysql_stmt_execute( pStmt ) CLASS WDO_MySql

   ::ThreadInitOnce()

RETU hb_DynCall( { "mysql_stmt_execute", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong }, pStmt )

//	-------------------------------------------------------  //

METHOD mysql_stmt_affected_rows( pStmt ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_stmt_affected_rows", ::pLib, hb_bitOr( ::nSysLong,;
                    ::nSysCallConv ), ::nSysLong }, pStmt )

//	-------------------------------------------------------  //

METHOD mysql_stmt_insert_id( pStmt ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_stmt_insert_id", ::pLib, hb_bitOr( ::nSysLong,;
                    ::nSysCallConv ), ::nSysLong }, pStmt )

//	-------------------------------------------------------  //

METHOD mysql_stmt_close( pStmt ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_stmt_close", ::pLib, hb_bitOr( HB_DYN_CTYPE_BOOL,;
                    ::nSysCallConv ), ::nSysLong }, pStmt )

//	-------------------------------------------------------  //

METHOD mysql_stmt_error( pStmt ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_stmt_error", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR,;
                    ::nSysCallConv ), ::nSysLong }, pStmt )

//	-------------------------------------------------------  //

METHOD mysql_stmt_errno( pStmt ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_stmt_errno", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT_UNSIGNED,;
                    ::nSysCallConv ), ::nSysLong }, pStmt )

//	-------------------------------------------------------  //

METHOD mysql_stmt_param_count( pStmt ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_stmt_param_count", ::pLib, hb_bitOr( HB_DYN_CTYPE_LONG_UNSIGNED,;
                    ::nSysCallConv ), ::nSysLong }, pStmt )

//	-------------------------------------------------------  //

METHOD mysql_stmt_send_long_data( pStmt, nIndex, cData ) CLASS WDO_MySql

   //  Returns my_bool -- read as INT + mask (see mysql_stmt_bind_param note).
   LOCAL nRc := hb_DynCall( { "mysql_stmt_send_long_data", ::pLib,;
                              hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                              ::nSysLong, HB_DYN_CTYPE_INT_UNSIGNED,;
                              HB_DYN_CTYPE_CHAR_PTR, HB_DYN_CTYPE_LONG_UNSIGNED },;
                              pStmt, nIndex, cData, Len( cData ) )

RETU hb_bitAnd( nRc, 0xFF ) != 0

//	-------------------------------------------------------  //

METHOD mysql_stmt_attr_set( pStmt, nAttr, pValue ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_stmt_attr_set", ::pLib, hb_bitOr( HB_DYN_CTYPE_BOOL,;
                    ::nSysCallConv ), ::nSysLong, HB_DYN_CTYPE_INT,;
                    HB_DYN_CTYPE_VOID_PTR },;
                    pStmt, nAttr, pValue )

//	=======================================================  //
//  Prepared statements -- read-side (Alt A, v2.3.04)
//	=======================================================  //

METHOD mysql_stmt_result_metadata( pStmt ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_stmt_result_metadata", ::pLib, hb_bitOr( ::nSysLong,;
                    ::nSysCallConv ), ::nSysLong }, pStmt )

//	-------------------------------------------------------  //

METHOD mysql_stmt_store_result( pStmt ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_stmt_store_result", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong }, pStmt )

//	-------------------------------------------------------  //

METHOD mysql_stmt_bind_result( pStmt, pBind ) CLASS WDO_MySql

   //  Returns my_bool (1 byte). Same Win64 ABI caveat as bind_param --
   //  read as INT and mask low byte.
   LOCAL nRc := hb_DynCall( { "mysql_stmt_bind_result", ::pLib,;
                              hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                              ::nSysLong, HB_DYN_CTYPE_VOID_PTR },;
                              pStmt, pBind )

RETU hb_bitAnd( nRc, 0xFF ) != 0

//	-------------------------------------------------------  //

METHOD mysql_stmt_fetch( pStmt ) CLASS WDO_MySql

   //  Returns int: 0 OK, 1 ERROR, 100 MYSQL_NO_DATA, 101 MYSQL_DATA_TRUNCATED.
RETU hb_DynCall( { "mysql_stmt_fetch", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong }, pStmt )

//	-------------------------------------------------------  //

METHOD mysql_stmt_num_rows( pStmt ) CLASS WDO_MySql

RETU hb_DynCall( { "mysql_stmt_num_rows", ::pLib, hb_bitOr( ::nSysLong,;
                    ::nSysCallConv ), ::nSysLong }, pStmt )

//	-------------------------------------------------------  //

METHOD mysql_stmt_free_result( pStmt ) CLASS WDO_MySql

   //  Returns my_bool -- INT + mask (my_bool Win64 bug).
   LOCAL nRc := hb_DynCall( { "mysql_stmt_free_result", ::pLib,;
                              hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                              ::nSysLong }, pStmt )

RETU hb_bitAnd( nRc, 0xFF ) != 0

//	=======================================================  //
//  Helpers globales
//	=======================================================  //

FUNCTION WDO_MySqlCountOpen()

   LOCAL n

   hb_mutexLock( soMutex )
   n := snOpen
   hb_mutexUnlock( soMutex )

RETU n

//	-------------------------------------------------------  //

FUNCTION hb_SysLong()

RETU If( hb_OSIS64BIT(), HB_DYN_CTYPE_LLONG_UNSIGNED, HB_DYN_CTYPE_LONG_UNSIGNED )

//	-------------------------------------------------------  //

FUNCTION hb_SysCallConv()

RETU If( ! "Windows" $ OS(), HB_DYN_CALLCONV_CDECL, HB_DYN_CALLCONV_STDCALL )

//	-------------------------------------------------------  //

FUNCTION hb_SysMyTypePos()

RETU If( hb_version( HB_VERSION_BITWIDTH ) == 64,;
         If( "Windows" $ OS(), 26, 28 ), 19 )

//	-------------------------------------------------------  //

//  Public wrappers preserved for backwards compatibility. Any external
//  caller doing hb_SysMySQL() / hb_SysMariaDb() keeps working; internally
//  we always go through _WdoResolveDll so precedence and diagnostics stay
//  consistent between the class Open() path and any legacy call site.
FUNCTION hb_SysMySQL()
RETU _WdoResolveDll( 'MYSQL', NIL, NIL )

FUNCTION hb_SysMariaDb()
RETU _WdoResolveDll( 'MARIADB', NIL, NIL )

//	-------------------------------------------------------  //
//  _WdoResolveDll( cType, cOverride, @cSourceOut )
//
//  Precedence chain (highest wins):
//    1. cOverride              -- explicit path from New()/InitPoolEx
//    2. hb_DirBase() + name    -- DLL dropped next to the running exe
//    3. env WDO_LIB_MYSQL      -- full path, all platforms
//    4. env WDO_PATH_MYSQL     -- folder + canonical filename (Windows)
//    5. platform default       -- hardcoded fallback
//
//  cSourceOut (optional @) receives the origin tag: "override" |
//  "exedir" | "WDO_LIB_MYSQL" | "WDO_PATH_MYSQL" | "default". Callers
//  pass NIL when they don't care.
//	-------------------------------------------------------  //

STATIC FUNCTION _WdoResolveDll( cType, cOverride, cSourceOut )

   LOCAL cLibName, cEnv, cCanonical, cExeDll
   LOCAL lWin64 := hb_version( HB_VERSION_BITWIDTH ) == 64

   //  1) Explicit override
   IF cOverride != NIL .AND. ! Empty( cOverride )
      IF cSourceOut != NIL ; cSourceOut := "override" ; ENDIF
      RETU cOverride
   ENDIF

   //  2) Same directory as the running executable (hb_DirBase)
   IF "Windows" $ OS()
      cCanonical := iif( cType == 'MYSQL', ;
                         iif( lWin64, 'libmysql64.dll',  'libmysql.dll'  ), ;
                         iif( lWin64, 'libmariadb64.dll','libmariadb.dll' ) )
   ELSEIF "Darwin" $ OS()
      cCanonical := iif( cType == 'MYSQL', 'libmysqlclient.dylib', 'libmariadbclient.dylib' )
   ELSE
      cCanonical := iif( cType == 'MYSQL', 'libmysqlclient.so', 'libmariadbclient.so' )
   ENDIF
   cExeDll := hb_DirBase() + cCanonical
   IF hb_FileExists( cExeDll )
      //  Return just the canonical name — let the OS loader resolve it.
      //  On Windows LoadLibrary("libmysql64.dll") uses the standard search
      //  order (AppDir first), avoiding the DLL-dependency anomalies that
      //  can hang LoadLibraryEx when an absolute path is passed and the
      //  exe-dir contains conflicting support DLLs (libssl/libcrypto).
      IF cSourceOut != NIL ; cSourceOut := "exedir" ; ENDIF
      RETU cCanonical
   ENDIF

   //  3) Full-path env (all platforms)
   cEnv := HB_GetEnv( 'WDO_LIB_MYSQL' )
   IF ! Empty( cEnv )
      IF cSourceOut != NIL ; cSourceOut := "WDO_LIB_MYSQL" ; ENDIF
      RETU cEnv
   ENDIF

   //  3) Legacy folder env (Windows only) + canonical filename
   IF "Windows" $ OS() .AND. ! Empty( HB_GetEnv( 'WDO_PATH_MYSQL' ) )
      cEnv := HB_GetEnv( 'WDO_PATH_MYSQL' )
      DO CASE
      CASE cType == 'MYSQL'
         cCanonical := iif( lWin64, 'libmysql64.dll', 'libmysql.dll' )
      OTHERWISE
         cCanonical := iif( lWin64, 'libmariadb64.dll', 'libmariadb.dll' )
      ENDCASE
      //  Idempotent slash normalization: append '/' if the env value
      //  doesn't end in a separator. Avoids the historic silent-corruption
      //  bug where a missing trailing slash produced e.g. 'c:\dirlibmysql64.dll'.
      IF Right( cEnv, 1 ) != '/' .AND. Right( cEnv, 1 ) != '\'
         cEnv += '/'
      ENDIF
      IF cSourceOut != NIL ; cSourceOut := "WDO_PATH_MYSQL" ; ENDIF
      RETU cEnv + cCanonical
   ENDIF

   //  4) Platform default
   IF cSourceOut != NIL ; cSourceOut := "default" ; ENDIF

   IF "Windows" $ OS()
      DO CASE
      CASE cType == 'MYSQL'
         cLibName := iif( lWin64, "c:/Apache24/htdocs/libmysql64.dll", "c:/Apache24/htdocs/libmysql.dll" )
      OTHERWISE
         cLibName := iif( lWin64, "c:/Apache24/htdocs/libmariadb64.dll", "c:/Apache24/htdocs/libmariadb.dll" )
      ENDCASE
   ELSEIF "Darwin" $ OS()
      cLibName := "/usr/local/Cellar/mysql/8.0.16/lib/libmysqlclient.dylib"
   ELSE
      DO CASE
      CASE cType == 'MYSQL'
         cLibName := iif( lWin64, ;
                          "/usr/lib/x86_64-linux-gnu/libmysqlclient.so", ;
                          "/usr/lib/x86-linux-gnu/libmysqlclient.so" )
      OTHERWISE
         cLibName := iif( lWin64, ;
                          "/usr/lib/x86_64-linux-gnu/libmariadbclient.so", ;
                          "/usr/lib/x86-linux-gnu/libmariadbclient.so" )
      ENDCASE
   ENDIF

RETU cLibName

//	-------------------------------------------------------  //
//  _WdoMySqlTcpProbe( cHost, nPort, nTimeoutMs )
//
//  Raw TCP probe (IPv4) with timeout — mirrors the test harness
//  pattern. Avoids ~2 min hangs in mysql_real_connect when the server
//  is down. 'localhost' is remapped to 127.0.0.1 because on Windows it
//  often resolves to ::1 (IPv6) and hb_socketConnect/AF_INET would
//  block instead of failing fast.
//	-------------------------------------------------------  //

STATIC FUNCTION _WdoMySqlTcpProbe( cHost, nPort, nTimeoutMs )

   LOCAL hSock, lOk, cResolved

   IF Empty( cHost )
      RETU .F.
   ENDIF
   cResolved := iif( Lower( AllTrim( cHost ) ) == "localhost", "127.0.0.1", cHost )
   hSock     := hb_socketOpen()
   IF hSock == NIL
      RETU .F.
   ENDIF
   lOk := hb_socketConnect( hSock, { HB_SOCKET_AF_INET, cResolved, nPort }, nTimeoutMs )
   hb_socketClose( hSock )

RETU lOk

//	-------------------------------------------------------  //
//  _WdoMySqlReportDown( cHost, nPort )
//
//  Prints "==> Error: Mysql not running" to stdout once per host:port.
//  Protected by s_mtxDown. Reset externally if the pool needs to re-arm
//  the warning (not exposed yet — add a WDO_MySqlReportReset() if ever
//  needed).
//	-------------------------------------------------------  //

STATIC FUNCTION _WdoMySqlReportDown( cHost, nPort )

   LOCAL cKey := cHost + ":" + hb_NToS( nPort )
   LOCAL lFirst := .F.

   hb_mutexLock( s_mtxDown )
   IF ! hb_HHasKey( s_hDownReported, cKey )
      s_hDownReported[ cKey ] := .T.
      lFirst := .T.
   ENDIF
   hb_mutexUnlock( s_mtxDown )

   IF lFirst
      OutStd( "==> Error: Mysql not running (" + cKey + ")" + hb_eol() )
      OutStd( "Press any key to exit..." + hb_eol() )
      Inkey( 0 )
      ErrorLevel( 1 )
      QUIT
   ENDIF

RETU NIL

//	-------------------------------------------------------  //
//  _WdoMySqlReportDllFail( cDll, cReason )
//
//  Prints a "Cannot load DLL" message once (deduped by DLL name
//  using the same s_hDownReported hash with a "DLL:" prefix key).
//  Aborts the process identical to _WdoMySqlReportDown so a pool
//  init with N failing connections prints the message exactly once.
//	-------------------------------------------------------  //

STATIC FUNCTION _WdoMySqlReportDllFail( cDll, cReason, cDllType )

   LOCAL cKey   := "DLL:" + cDll
   LOCAL lFirst := .F.

   hb_default( @cDllType, "MySQL" )

   hb_mutexLock( s_mtxDown )
   IF ! hb_HHasKey( s_hDownReported, cKey )
      s_hDownReported[ cKey ] := .T.
      lFirst := .T.
   ENDIF
   hb_mutexUnlock( s_mtxDown )

   IF lFirst
      OutStd( "==> Error: Cannot load " + cDllType + " DLL" + hb_eol() )
      OutStd( "Press any key to continue..." + hb_eol() )
   ENDIF

RETU NIL

//	-------------------------------------------------------  //

FUNCTION wdo_addslashes( c )

   c := StrTran( c, '\', '\\' )
   c := StrTran( c, "'", "\'" )
   c := StrTran( c, '"', '\"' )

RETU c
