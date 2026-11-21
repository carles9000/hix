/*-----------------------------------------------------------
  File ......: wdo_pg.prg
  Author.....: Charly 9000
  Created....: 2026-10-18
  Modified...: 2026-10-18
  Version....: 1.0.0
  Description: PostgreSQL connection class (long-lived).
               Owns native handles (pLib, hConnection) and
               exposes DynCall wrappers over libpq. Query()
               returns a WDO_PgStmt with its own hRes + field
               metadata so the connection state is never
               polluted by per-query data. Ready to be
               checked out from a pool serially.
  Usage      : oConn := WDO_PG():New( cHost, cUser, cPwd, cDb )
               oStmt := oConn:Query( "SELECT ..." )
  Notes      : Mirrors the WDO_MySql class layout. libpq is
               thread-safe since PG 7.x but a single PGconn
               must never be shared across threads — pool
               serialization enforces that invariant.
 -----------------------------------------------------------*/

#include 'hix_const.ch'
#include 'hix_logger.ch'
#include 'hbclass.ch'
#include "hbdyn.ch"
#include "fileio.ch"
#include "wdo_metrics.ch"
#include "wdo_pg.ch"

#define VERSION_WDO_PG_CONN        '1.0'

#define HB_VERSION_BITWIDTH        17
#define NULL                       0

STATIC snOpen  := 0
STATIC soMutex
STATIC sl_PoolGuardWarn := .T.

//  Dedupe of the "PostgreSQL not running" console message. Keyed by
//  "host:port" so a pool init with N failing conns prints once.
STATIC s_hDownReported := NIL
STATIC s_mtxDown

INIT PROCEDURE _WDO_PgInit()
   soMutex         := hb_mutexCreate()
   s_mtxDown       := hb_mutexCreate()
   s_hDownReported := {=>}
RETURN

//	-------------------------------------------------------  //
//  Toggles the runtime warning emitted when WDO_PG:New()
//  is called from inside an HTTP request handler. Default ON.
//  Returns the previous value.
//	-------------------------------------------------------  //
FUNCTION WDO_PgNewGuard( lOn )
   LOCAL lOld := sl_PoolGuardWarn
   IF hb_isLogical( lOn )
      sl_PoolGuardWarn := lOn
   ENDIF
RETURN lOld


CLASS WDO_PG FROM WDO

   DATA cServer
   DATA cUserName
   DATA cPassword
   DATA cDatabase
   DATA nPort
   DATA cType                          INIT 'PG'
   DATA cDllType                       INIT 'PostgreSQL'

   DATA pLib
   DATA hConnection

   DATA nSysCallConv
   DATA nSysLong

   DATA lConnect                       INIT .F.
   DATA lInUse                         INIT .F.
   DATA lInTrans                       INIT .F.
   DATA tLastUsed
   DATA lPersistent                    INIT .F.
   DATA lLog                           INIT .F.
   DATA lWeb                           INIT .T.

   DATA oPool                          INIT NIL
   DATA cPoolKey                       INIT "-"

   DATA cDllPath                       INIT NIL
   DATA cDllSource                     INIT ''

   //  Monotonic counter for unique PQprepare statement names.
   //  Scoped per-connection — PG libpq is single-thread per PGconn.
   DATA nStmtSeq                       INIT 0

   //  Socket-level read/write timeout (seconds). libpq doesn't expose a
   //  post-connect read_timeout knob directly (unlike MYSQL_OPT_READ_TIMEOUT),
   //  so this value is appended to the connstring as `options='-c
   //  statement_timeout=NN000'` which bounds every query on the server side.
   //  0 disables.
   DATA nReadTimeout                   INIT 30
   //  Connect-phase socket timeout (seconds). Appended to the connstring
   //  as `connect_timeout=N` which libpq honors natively.
   DATA nConnectTimeout                INIT 10

   //  Extra libpq connstring keys (merged into PQconnectdb). Users with
   //  custom needs (sslcert, krbsrvname, etc.) can poke them in without
   //  needing new DATAs on the class.
   DATA cSslMode                       INIT ''      //  disable|allow|prefer|require|verify-ca|verify-full
   DATA cAppName                       INIT WDO_PG_DEFAULT_APPNAME
   DATA cClientEncoding                INIT ''      //  e.g. UTF8, WIN1252, LATIN1

   METHOD New( cServer, cUser, cPwd, cDb, nPort, lOpen, cDllPath ) CONSTRUCTOR
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

   METHOD BeginTrans()
   METHOD Commit()
   METHOD Rollback()
   METHOD InTransaction()              INLINE ::lInTrans
   METHOD Transaction( bCode )

   METHOD Last_Insert_Id()

   METHOD ServerInfo()
   METHOD ClientInfo()                 INLINE ::GetDllVersion()
   METHOD GetDllVersion()
   METHOD GetClientInfo()
   METHOD GetConnectionInfo()
   METHOD GetEncoding()
   METHOD SetClientEncoding( cEnc )
   METHOD DllPath()                    INLINE iif( ::cDllPath == NIL, '', ::cDllPath )
   METHOD DllSource()                  INLINE ::cDllSource

   METHOD CountOpen()                  INLINE WDO_PgCountOpen()

   METHOD Version()                    INLINE VERSION_WDO_PG_CONN
   METHOD VersionName()                INLINE 'WDO_PG_CONN ' + VERSION_WDO_PG_CONN

   //  DynCall wrappers (libpq)
   METHOD PQconnectdb( cConnInfo )
   METHOD PQstatus()
   METHOD PQerrorMessage()
   METHOD PQfinish()
   METHOD PQexec( cQuery )
   METHOD PQresultStatus( hRes )
   METHOD PQresultErrorMessage( hRes )
   METHOD PQntuples( hRes )
   METHOD PQnfields( hRes )
   METHOD PQfname( hRes, nCol )
   METHOD PQftype( hRes, nCol )
   METHOD PQfsize( hRes, nCol )
   METHOD PQfmod( hRes, nCol )
   METHOD PQgetvalue( hRes, nRow, nCol )
   METHOD PQgetisnull( hRes, nRow, nCol )
   METHOD PQgetlength( hRes, nRow, nCol )
   METHOD PQcmdTuples( hRes )
   METHOD PQclear( hRes )
   METHOD PQlibVersion()
   METHOD PQserverVersion()
   METHOD PQdb()
   METHOD PQhost()
   METHOD PQuser()
   METHOD PQport()
   METHOD PQsetClientEncoding( cEnc )
   METHOD PQclientEncoding()
   METHOD PQfreemem( pPtr )

   //  Prepared statements (Alt A — native libpq protocol, text params)
   METHOD PQprepare( cName, cSql, nParams, pParamTypes )
   METHOD PQexecPrepared( cName, nParams, pParamValues,;
                          pParamLengths, pParamFormats, nResultFormat )
   METHOD PQexecParams( cSql, nParams, pParamTypes, pParamValues,;
                        pParamLengths, pParamFormats, nResultFormat )
   METHOD PQdescribePrepared( cName )
   METHOD PQnparams( hRes )
   METHOD PQparamtype( hRes, nParam )

ENDCLASS

//	-------------------------------------------------------  //

METHOD New( cServer, cUserName, cPassword, cDatabase, nPort, lOpen, cDllPath ) CLASS WDO_PG

   hb_default( @cServer,   '127.0.0.1' )
   hb_default( @cUserName, '' )
   hb_default( @cPassword, '' )
   hb_default( @cDatabase, '' )
   hb_default( @nPort,     WDO_PG_DEFAULT_PORT )
   hb_default( @lOpen,     .T. )

   ::Super:New()

   ::cServer   := cServer
   ::cUserName := cUserName
   ::cPassword := cPassword
   ::cDatabase := cDatabase
   ::nPort     := nPort

   IF cDllPath != NIL .AND. ! Empty( cDllPath )
      ::cDllPath := cDllPath
   ENDIF

   IF lOpen
      ::Open()
   ENDIF

   //  Pool guard: warn if New() is used inside an HTTP request handler.
   //  Under load this pattern exhausts the OS ephemeral port range.
   //  Use WDO_Get("PG") instead.
   IF ::lConnect .AND. sl_PoolGuardWarn .AND. HIX_GetRequest() != NIL
      lw( _( 'WDO_WARN_NEW_IN_REQUEST' ) )
   ENDIF

RETU SELF

//	-------------------------------------------------------  //

METHOD Open() CLASS WDO_PG

   LOCAL cDll, cConnStr
   LOCAL nStatus

   IF ::lConnect
      RETU NIL
   ENDIF

   IF( ::lLog, _d( 'WDO log activated' ), NIL )

   //  Fast TCP preflight: avoids ~2 min hang in PQconnectdb when the
   //  server isn't listening. Uses the configured port or 5432.
   IF ! _WdoPgTcpProbe( ::cServer, iif( Empty( ::nPort ), WDO_PG_DEFAULT_PORT, ::nPort ), 2000 )
      _WdoPgReportDown( ::cServer, iif( Empty( ::nPort ), WDO_PG_DEFAULT_PORT, ::nPort ) )
      ::SetError( _( 'WDO_ERR_CONNECT', 'PostgreSQL not reachable (TCP probe failed)' ) )
      RETU SELF
   ENDIF

   //  Resolve full DLL/so path from override + env vars + default. Stores
   //  the origin tag in ::cDllSource for diagnostics (see DllSource()).
   cDll         := _WdoPgResolveDll( ::cDllPath, @::cDllSource )
   ::cDllPath   := cDll

   //  Skip File() check when the resolver returned a bare name (source
   //  "exedir"): existence is already verified against hb_DirBase.
   IF ::cDllSource != "exedir" .AND. ! File( cDll )
      _WdoPgReportDllFail( cDll, "not found" )
      ::SetError( _( 'WDO_ERR_LIB_NOT_FOUND', cDll + ' [' + ::cDllSource + ']' ), 'Loading dll' )
      RETU NIL
   ENDIF

   ::pLib := hb_LibLoad( cDll )

   IF ValType( ::pLib ) <> "P"
      IF( ::lLog, _d( 'WDO ' + ::cError + ' ' + cDll ), NIL )
      _WdoPgReportDllFail( cDll, "failed to load" )
      ::SetError( _( 'WDO_ERR_LIB_WRONG', Lower( cDll ) + ' [' + ::cDllSource + ']' ) )
      RETU NIL
   ENDIF

   ::nSysCallConv := hb_SysCallConv()
   ::nSysLong     := hb_SysLong()

   //  Build connstring. libpq parses key=value pairs separated by
   //  whitespace. Values with spaces/quotes must be single-quoted; the
   //  known params here are safe to pass raw (no spaces in host/user/
   //  password typical). The caller is responsible for sanitizing the
   //  password if it contains quotes — libpq accepts \' as escape.
   cConnStr := "host="     + ::cServer                              + " " + ;
               "port="     + hb_NToS( ::nPort )                     + " " + ;
               "dbname="   + ::cDatabase                            + " " + ;
               "user="     + ::cUserName                            + " " + ;
               "password=" + _WdoPgQuoteConn( ::cPassword )

   IF ::nConnectTimeout > 0
      cConnStr += " connect_timeout=" + hb_NToS( ::nConnectTimeout )
   ENDIF

   IF ::nReadTimeout > 0
      //  statement_timeout is in milliseconds. Set via `options`.
      cConnStr += " options='-c statement_timeout=" + ;
                  hb_NToS( ::nReadTimeout * 1000 ) + "'"
   ENDIF

   IF ! Empty( ::cSslMode )
      cConnStr += " sslmode=" + ::cSslMode
   ENDIF

   IF ! Empty( ::cAppName )
      cConnStr += " application_name=" + _WdoPgQuoteConn( ::cAppName )
   ENDIF

   IF ! Empty( ::cClientEncoding )
      cConnStr += " client_encoding=" + ::cClientEncoding
   ENDIF

   ::hConnection := ::PQconnectdb( cConnStr )

   IF ::hConnection == 0 .OR. ::hConnection == NIL
      ::SetError( _( 'WDO_ERR_CONNECT', 'PQconnectdb returned NULL' ) )
      RETU SELF
   ENDIF

   nStatus := ::PQstatus()

   IF nStatus != CONNECTION_OK
      ::SetError( _( 'WDO_ERR_CONNECT', ::PQerrorMessage() ) )
      ::PQfinish()
      ::hConnection := 0
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

   //  Publish server/client version in the extended info registry.
   WDO_InfoRegister( "RDBMS " + ::cDllType + " Server", ::ServerInfo() )
   WDO_InfoRegister( "RDBMS " + ::cDllType + " Client", ::cDllType + " " + ::GetDllVersion() )

RETU NIL

//	-------------------------------------------------------  //

METHOD Close() CLASS WDO_PG

   LOCAL lWasConnected

   //  Pooled instance: Close() releases back to the pool (does NOT tear
   //  down the TCP connection). The pool eventually calls Close() again
   //  after clearing oPool for the real teardown at shutdown.
   IF ::oPool != NIL
      HIX_Dbg( "[WDO_PG] Close (tid=" + hb_NToS( hb_threadId( hb_threadSelf() ) ) + ;
               "): pooled -> Release to pool (no TCP teardown)" )
      ::oPool:Release( SELF )
      RETU NIL
   ENDIF

   HIX_Dbg( "[WDO_PG] Close (tid=" + hb_NToS( hb_threadId( hb_threadSelf() ) ) + ;
            "): TEARDOWN (PQfinish + HB_LibFree)" )

   lWasConnected := ::lConnect

   IF ValType( ::pLib ) == "P"

      IF( ::lLog, _d( 'WDO Close proc' ), NIL )

      IF ::hConnection != NIL .AND. ::hConnection != 0
         ::PQfinish()
      ENDIF

      HB_LibFree( ::pLib )

      ::pLib        := NIL
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

METHOD Exit() CLASS WDO_PG

   IF ::lPersistent
      IF( ::lLog, _d( 'WDO Persistent' ), NIL )
      RETU NIL
   ENDIF

RETU NIL

//	-------------------------------------------------------  //

METHOD Ping() CLASS WDO_PG

   LOCAL oStmt

   IF ! ::lConnect .OR. ::hConnection == 0 .OR. ::hConnection == NIL
      RETU .F.
   ENDIF

   //  Fast-path: PQstatus is a cheap client-side check (does NOT touch
   //  the socket). It only returns CONNECTION_BAD after a prior op has
   //  failed. We still need the SELECT 1 roundtrip to detect servers
   //  that closed the socket without us noticing.
   IF ::PQstatus() != CONNECTION_OK
      RETU .F.
   ENDIF

   oStmt := ::Query( "SELECT 1" )

   IF oStmt == NIL .OR. oStmt:lError .OR. oStmt:hRes == 0
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      RETU .F.
   ENDIF

   oStmt:Free()

RETU .T.

//	-------------------------------------------------------  //

METHOD Reconnect() CLASS WDO_PG

   ::Close()
   ::Open()

RETU ::lConnect

//	-------------------------------------------------------  //

METHOD IsAlive() CLASS WDO_PG

RETU ::lConnect .AND. ::Ping()

//	-------------------------------------------------------  //
//  SQL escaping. PG with standard_conforming_strings=on (default
//  since 9.1) uses doubled single quotes '' and does NOT interpret
//  backslash as escape. StrTran("'" -> "''") is enough.
//	-------------------------------------------------------  //
METHOD Escape( hRow ) CLASS WDO_PG

   LOCAL n, aPair, nLen
   LOCAL cType := ValType( hRow )

   DO CASE
   CASE cType == 'H'
      nLen := Len( hRow )
      FOR n := 1 TO nLen
         aPair := HB_HPairAt( hRow, n )
         IF ValType( aPair[2] ) == 'C' .OR. ValType( aPair[2] ) == 'M'
            hRow[ aPair[1] ] := wdo_pg_addslashes( aPair[2] )
         ENDIF
      NEXT

   CASE cType == 'A'
      nLen := Len( hRow )
      FOR n := 1 TO nLen
         IF ValType( hRow[n] ) == 'C' .OR. ValType( hRow[n] ) == 'M'
            hRow[n] := wdo_pg_addslashes( hRow[n] )
         ENDIF
      NEXT

   CASE cType == 'C' .OR. cType == 'M'
      hRow := wdo_pg_addslashes( hRow )

   ENDCASE

RETU hRow

//	-------------------------------------------------------  //

METHOD Query( cSql ) CLASS WDO_PG

   LOCAL hRes
   LOCAL nStatus
   LOCAL oStmt
   LOCAL nT0

   IF ::hConnection == NIL .OR. ::hConnection == 0
      RETU NIL
   ENDIF

   IF( ::lLog, _d( 'WDO ' + cSql ), NIL )

   nT0  := hb_MilliSeconds()
   hRes := ::PQexec( cSql )

   IF hRes == 0 .OR. hRes == NIL
      ::SetError( ::PQerrorMessage() )
      oStmt         := WDO_PgStmt():New( SELF, cSql, 0 )
      oStmt:lError  := .T.
      oStmt:cError  := ::cError
      WDO_Metric( WDOM_QUERIES_ERRORS )
      WDO_MetricQuery( ::cPoolKey, cSql, hb_MilliSeconds() - nT0, NIL )
      RETU oStmt
   ENDIF

   nStatus := ::PQresultStatus( hRes )

   IF nStatus == PGRES_COMMAND_OK .OR. nStatus == PGRES_TUPLES_OK
      oStmt := WDO_PgStmt():New( SELF, cSql, hRes )
   ELSE
      ::SetError( ::PQresultErrorMessage( hRes ) )
      oStmt         := WDO_PgStmt():New( SELF, cSql, 0 )
      oStmt:lError  := .T.
      oStmt:cError  := ::cError
      ::PQclear( hRes )
      WDO_Metric( WDOM_QUERIES_ERRORS )
   ENDIF

   WDO_MetricQuery( ::cPoolKey, cSql, hb_MilliSeconds() - nT0, NIL )

   ::tLastUsed := hb_DateTime()

RETU oStmt

//	-------------------------------------------------------  //
//  Prepare — libpq native PQprepare + lazy param count discovery.
//
//  Flow:
//    1) Scan cSql: si trae `$N` posicional PG-native → no reescribir.
//       Caso contrario, parser reescribe `?` y `:name` a `$N` y puebla
//       hParamMap / nParamCount.
//    2) Generar nombre único (tid + seq por conexión).
//    3) PQprepare(name, cSqlServer, 0 params) — paramTypes=NULL deja
//       que PG infiera tipos desde el contexto del SQL.
//    4) Si veníamos de SQL PG-native, descubrir nParamCount vía
//       PQdescribePrepared + PQnparams para dimensionar aParams.
//    5) Empaquetar en WDO_PgStmt con lPrepared=.T. — el caller usa
//       BindParam/BindParams y luego Execute (paso 4 §6).
//
//  Errores se propagan al oStmt devuelto (lError/cError) sin excepción.
//	-------------------------------------------------------  //
METHOD Prepare( cSql ) CLASS WDO_PG

   LOCAL oStmt
   LOCAL cSqlServer
   LOCAL nParamCount := 0
   LOCAL hParamMap   := {=>}
   LOCAL cStmtName
   LOCAL hRes
   LOCAL nStatus
   LOCAL nT0

   IF ::hConnection == NIL .OR. ::hConnection == 0
      RETU NIL
   ENDIF

   //  1) Elegir SQL servidor: PG-native o reescrito.
   IF _HixWdoPgHasDollarN( cSql )
      cSqlServer  := cSql
      //  nParamCount será descubierto tras PQprepare (paso 4).
   ELSE
      cSqlServer := _HixWdoPgPrepareScan( cSql, @nParamCount, @hParamMap )
   ENDIF

   //  2) Nombre único (thread-safe: tid + seq por conn).
   ::nStmtSeq++
   cStmtName := "hix_pg_" + hb_NToS( hb_ThreadSelf() ) + "_" + ;
                hb_NToS( ::nStmtSeq )

   IF( ::lLog, _d( 'WDO PG PREPARE ' + cSql ), NIL )

   nT0 := hb_MilliSeconds()

   //  3) PQprepare native. nParams=0 → PG infiere tipos desde el SQL.
   hRes := ::PQprepare( cStmtName, cSqlServer, 0 )

   IF hRes == 0
      oStmt := WDO_PgStmt():New( SELF, cSql, 0 )
      oStmt:lError       := .T.
      oStmt:cError       := ::cError
      oStmt:lPrepared    := .F.
      oStmt:cSqlOriginal := cSql
      oStmt:cSqlServer   := cSqlServer
      WDO_MetricQuery( ::cPoolKey, "PREPARE " + cSql, ;
                       hb_MilliSeconds() - nT0, NIL )
      RETU oStmt
   ENDIF

   nStatus := ::PQresultStatus( hRes )

   IF nStatus != PGRES_COMMAND_OK
      ::SetError( ::PQresultErrorMessage( hRes ) )
      ::PQclear( hRes )
      oStmt := WDO_PgStmt():New( SELF, cSql, 0 )
      oStmt:lError       := .T.
      oStmt:cError       := ::cError
      oStmt:lPrepared    := .F.
      oStmt:cSqlOriginal := cSql
      oStmt:cSqlServer   := cSqlServer
      WDO_MetricQuery( ::cPoolKey, "PREPARE " + cSql, ;
                       hb_MilliSeconds() - nT0, NIL )
      RETU oStmt
   ENDIF

   ::PQclear( hRes )

   //  4) Si entró como PG-native, descubrir nParamCount.
   IF nParamCount == 0 .AND. _HixWdoPgHasDollarN( cSql )
      hRes := ::PQdescribePrepared( cStmtName )
      IF hRes != 0
         IF ::PQresultStatus( hRes ) == PGRES_COMMAND_OK
            nParamCount := ::PQnparams( hRes )
         ENDIF
         ::PQclear( hRes )
      ENDIF
   ENDIF

   WDO_MetricQuery( ::cPoolKey, "PREPARE " + cSql, ;
                    hb_MilliSeconds() - nT0, NIL )

   //  5) Empaquetar stmt listo para BindParam / Execute.
   oStmt := WDO_PgStmt():New( SELF, cSql, 0 )
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
//  Shortcut: run and free the Stmt. Returns affected rows.
METHOD Exec( cSql ) CLASS WDO_PG

   LOCAL oStmt := ::Query( cSql )
   LOCAL nAff  := 0

   IF oStmt != NIL
      nAff := oStmt:nAffectedRows
      oStmt:Free()
   ENDIF

RETU nAff

//	-------------------------------------------------------  //
//  Transactions (connection-level, not Stmt-level)
//	-------------------------------------------------------  //

METHOD BeginTrans() CLASS WDO_PG

   LOCAL hRes

   IF ! ::lConnect .OR. ::hConnection == 0
      RETU .F.
   ENDIF

   IF ::lInTrans
      RETU .F.
   ENDIF

   hRes := ::PQexec( "BEGIN" )
   IF hRes == 0 .OR. ::PQresultStatus( hRes ) != PGRES_COMMAND_OK
      IF hRes != 0 ; ::PQclear( hRes ) ; ENDIF
      ::SetError( ::PQerrorMessage(), "BeginTrans" )
      RETU .F.
   ENDIF
   ::PQclear( hRes )

   ::lInTrans  := .T.
   ::tLastUsed := hb_DateTime()

RETU .T.

//	-------------------------------------------------------  //

METHOD Commit() CLASS WDO_PG

   LOCAL hRes

   IF ! ::lInTrans
      RETU .F.
   ENDIF

   hRes := ::PQexec( "COMMIT" )
   IF hRes == 0 .OR. ::PQresultStatus( hRes ) != PGRES_COMMAND_OK
      IF hRes != 0 ; ::PQclear( hRes ) ; ENDIF
      ::SetError( ::PQerrorMessage(), "Commit" )
      ::lInTrans := .F.
      RETU .F.
   ENDIF
   ::PQclear( hRes )

   ::lInTrans  := .F.
   ::tLastUsed := hb_DateTime()

RETU .T.

//	-------------------------------------------------------  //

METHOD Rollback() CLASS WDO_PG

   LOCAL hRes

   IF ! ::lInTrans
      RETU .F.
   ENDIF

   hRes := ::PQexec( "ROLLBACK" )
   IF hRes == 0 .OR. ::PQresultStatus( hRes ) != PGRES_COMMAND_OK
      IF hRes != 0 ; ::PQclear( hRes ) ; ENDIF
      ::SetError( ::PQerrorMessage(), "Rollback" )
      ::lInTrans := .F.
      RETU .F.
   ENDIF
   ::PQclear( hRes )

   ::lInTrans  := .F.
   ::tLastUsed := hb_DateTime()

RETU .T.

//	-------------------------------------------------------  //

METHOD Transaction( bCode ) CLASS WDO_PG

   LOCAL oErr
   LOCAL lOk := .T.

   IF ! ::BeginTrans()
      RETU .F.
   ENDIF

   TRY
      Eval( bCode, SELF )
      lOk := ::Commit()
   CATCH oErr
      ::Rollback()
      lOk := .F.
   END

RETU lOk

//	-------------------------------------------------------  //
//  PG has no equivalent to mysql_insert_id. The idiomatic approach
//  is `INSERT ... RETURNING id` or `SELECT lastval()` after the
//  insert (if the table has a sequence and nextval was called in
//  the same session). This method returns the result of lastval()
//  as a best-effort shortcut; -1 on failure.
//	-------------------------------------------------------  //
METHOD Last_Insert_Id() CLASS WDO_PG

   LOCAL oStmt
   LOCAL nId := -1

   IF ::hConnection == NIL .OR. ::hConnection == 0
      RETU -1
   ENDIF

   oStmt := ::Query( "SELECT lastval()" )

   IF oStmt != NIL .AND. ! oStmt:lError .AND. oStmt:hRes != 0 .AND. oStmt:Count() > 0
      nId := Val( ::PQgetvalue( oStmt:hRes, 0, 0 ) )
   ENDIF

   IF oStmt != NIL ; oStmt:Free() ; ENDIF

RETU nId

//	-------------------------------------------------------  //

METHOD ServerInfo() CLASS WDO_PG

   LOCAL nVer

   IF ::hConnection == NIL .OR. ::hConnection == 0
      RETU "Unknown"
   ENDIF

   //  PQserverVersion returns int like 160003 → 16.0.3
   nVer := ::PQserverVersion()
   IF nVer <= 0
      RETU "Unknown"
   ENDIF

RETU hb_NToS( Int( nVer / 10000 ) ) + "." + ;
     hb_NToS( Int( ( nVer % 10000 ) / 100 ) ) + "." + ;
     hb_NToS( nVer % 100 )

//	-------------------------------------------------------  //

METHOD GetDllVersion() CLASS WDO_PG

   LOCAL nLibVer, cVersion := "Unknown"

   IF ::pLib == NIL
      RETU cVersion
   ENDIF

   nLibVer := ::PQlibVersion()
   //  Format: major * 10000 + minor * 100 + patch (PG 10+)
   //  e.g. 160003 → "16.0.3"
   IF nLibVer > 0
      cVersion := hb_NToS( Int( nLibVer / 10000 ) ) + "." + ;
                  hb_NToS( Int( ( nLibVer % 10000 ) / 100 ) ) + "." + ;
                  hb_NToS( nLibVer % 100 )
   ENDIF

RETU cVersion

//	-------------------------------------------------------  //

METHOD GetClientInfo() CLASS WDO_PG

   LOCAL hInfo := {=>}

   hInfo[ "dll_version" ]       := ::GetDllVersion()
   hInfo[ "wdo_version" ]       := ::Version()
   hInfo[ "server_version" ]    := ::ServerInfo()
   hInfo[ "client_encoding" ]   := ::GetEncoding()
   hInfo[ "bits" ]              := If( hb_OSIS64BIT(), "64 bits", "32 bits" )
   hInfo[ "dll_path" ]          := ::DllPath()
   hInfo[ "dll_source" ]        := ::DllSource()

RETU hInfo

//	-------------------------------------------------------  //

METHOD GetConnectionInfo() CLASS WDO_PG

   LOCAL hInfo := {=>}

   IF ::hConnection == NIL .OR. ::hConnection == 0
      RETU hInfo
   ENDIF

   hInfo[ "db"       ] := ::PQdb()
   hInfo[ "user"     ] := ::PQuser()
   hInfo[ "host"     ] := ::PQhost()
   hInfo[ "port"     ] := ::PQport()
   hInfo[ "encoding" ] := ::GetEncoding()

RETU hInfo

//	-------------------------------------------------------  //

METHOD GetEncoding() CLASS WDO_PG

   LOCAL oStmt, cEnc := "unknown"

   IF ::hConnection == NIL .OR. ::hConnection == 0
      RETU cEnc
   ENDIF

   oStmt := ::Query( "SHOW client_encoding" )
   IF oStmt != NIL .AND. ! oStmt:lError .AND. oStmt:hRes != 0 .AND. oStmt:Count() > 0
      cEnc := ::PQgetvalue( oStmt:hRes, 0, 0 )
   ENDIF
   IF oStmt != NIL ; oStmt:Free() ; ENDIF

RETU cEnc

//	-------------------------------------------------------  //

METHOD SetClientEncoding( cEnc ) CLASS WDO_PG

   IF ::hConnection == NIL .OR. ::hConnection == 0 .OR. Empty( cEnc )
      RETU .F.
   ENDIF

RETU ::PQsetClientEncoding( cEnc ) == 0

//	=======================================================  //
//  DynCall wrappers (libpq)
//	=======================================================  //

METHOD PQconnectdb( cConnInfo ) CLASS WDO_PG

RETU hb_DynCall( { "PQconnectdb", ::pLib, hb_bitOr( ::nSysLong, ::nSysCallConv ),;
                    HB_DYN_CTYPE_CHAR_PTR }, cConnInfo )

//	-------------------------------------------------------  //

METHOD PQstatus() CLASS WDO_PG

RETU hb_DynCall( { "PQstatus", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                    ::nSysLong }, ::hConnection )

//	-------------------------------------------------------  //

METHOD PQerrorMessage() CLASS WDO_PG

RETU hb_DynCall( { "PQerrorMessage", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR,;
                    ::nSysCallConv ), ::nSysLong }, ::hConnection )

//	-------------------------------------------------------  //

METHOD PQfinish() CLASS WDO_PG

RETU hb_DynCall( { "PQfinish", ::pLib, hb_bitOr( HB_DYN_CTYPE_VOID,;
                    ::nSysCallConv ), ::nSysLong }, ::hConnection )

//	-------------------------------------------------------  //

METHOD PQexec( cQuery ) CLASS WDO_PG

   LOCAL u
   LOCAL bNewError := {| oError | Break( oError ) }
   LOCAL bOldError := ErrorBlock( bNewError )

   BEGIN SEQUENCE
      u := hb_DynCall( { "PQexec", ::pLib, hb_bitOr( ::nSysLong, ::nSysCallConv ),;
                          ::nSysLong, HB_DYN_CTYPE_CHAR_PTR },;
                          ::hConnection, cQuery )
   RECOVER
      ::SetError( ::PQerrorMessage() )
      ErrorBlock( bOldError )
      RETU 0
   END SEQUENCE

   ErrorBlock( bOldError )

RETU u

//	-------------------------------------------------------  //

METHOD PQresultStatus( hRes ) CLASS WDO_PG

RETU hb_DynCall( { "PQresultStatus", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong }, hRes )

//	-------------------------------------------------------  //

METHOD PQresultErrorMessage( hRes ) CLASS WDO_PG

RETU hb_DynCall( { "PQresultErrorMessage", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR,;
                    ::nSysCallConv ), ::nSysLong }, hRes )

//	-------------------------------------------------------  //

METHOD PQntuples( hRes ) CLASS WDO_PG

RETU hb_DynCall( { "PQntuples", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong }, hRes )

//	-------------------------------------------------------  //

METHOD PQnfields( hRes ) CLASS WDO_PG

RETU hb_DynCall( { "PQnfields", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong }, hRes )

//	-------------------------------------------------------  //

METHOD PQfname( hRes, nCol ) CLASS WDO_PG

RETU hb_DynCall( { "PQfname", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR,;
                    ::nSysCallConv ), ::nSysLong, HB_DYN_CTYPE_INT }, hRes, nCol )

//	-------------------------------------------------------  //

METHOD PQftype( hRes, nCol ) CLASS WDO_PG

RETU hb_DynCall( { "PQftype", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT_UNSIGNED,;
                    ::nSysCallConv ), ::nSysLong, HB_DYN_CTYPE_INT }, hRes, nCol )

//	-------------------------------------------------------  //

METHOD PQfsize( hRes, nCol ) CLASS WDO_PG

RETU hb_DynCall( { "PQfsize", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong, HB_DYN_CTYPE_INT }, hRes, nCol )

//	-------------------------------------------------------  //

METHOD PQfmod( hRes, nCol ) CLASS WDO_PG

RETU hb_DynCall( { "PQfmod", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong, HB_DYN_CTYPE_INT }, hRes, nCol )

//	-------------------------------------------------------  //

METHOD PQgetvalue( hRes, nRow, nCol ) CLASS WDO_PG

RETU hb_DynCall( { "PQgetvalue", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR,;
                    ::nSysCallConv ), ::nSysLong, HB_DYN_CTYPE_INT, HB_DYN_CTYPE_INT },;
                  hRes, nRow, nCol )

//	-------------------------------------------------------  //

METHOD PQgetisnull( hRes, nRow, nCol ) CLASS WDO_PG

RETU hb_DynCall( { "PQgetisnull", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong, HB_DYN_CTYPE_INT, HB_DYN_CTYPE_INT },;
                  hRes, nRow, nCol )

//	-------------------------------------------------------  //

METHOD PQgetlength( hRes, nRow, nCol ) CLASS WDO_PG

RETU hb_DynCall( { "PQgetlength", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong, HB_DYN_CTYPE_INT, HB_DYN_CTYPE_INT },;
                  hRes, nRow, nCol )

//	-------------------------------------------------------  //

METHOD PQcmdTuples( hRes ) CLASS WDO_PG

RETU hb_DynCall( { "PQcmdTuples", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR,;
                    ::nSysCallConv ), ::nSysLong }, hRes )

//	-------------------------------------------------------  //

METHOD PQclear( hRes ) CLASS WDO_PG

RETU hb_DynCall( { "PQclear", ::pLib, hb_bitOr( HB_DYN_CTYPE_VOID,;
                    ::nSysCallConv ), ::nSysLong }, hRes )

//	-------------------------------------------------------  //

METHOD PQlibVersion() CLASS WDO_PG

RETU hb_DynCall( { "PQlibVersion", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ) } )

//	-------------------------------------------------------  //

METHOD PQserverVersion() CLASS WDO_PG

RETU hb_DynCall( { "PQserverVersion", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong }, ::hConnection )

//	-------------------------------------------------------  //

METHOD PQdb() CLASS WDO_PG

RETU hb_DynCall( { "PQdb", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR,;
                    ::nSysCallConv ), ::nSysLong }, ::hConnection )

//	-------------------------------------------------------  //

METHOD PQhost() CLASS WDO_PG

RETU hb_DynCall( { "PQhost", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR,;
                    ::nSysCallConv ), ::nSysLong }, ::hConnection )

//	-------------------------------------------------------  //

METHOD PQuser() CLASS WDO_PG

RETU hb_DynCall( { "PQuser", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR,;
                    ::nSysCallConv ), ::nSysLong }, ::hConnection )

//	-------------------------------------------------------  //

METHOD PQport() CLASS WDO_PG

RETU hb_DynCall( { "PQport", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR,;
                    ::nSysCallConv ), ::nSysLong }, ::hConnection )

//	-------------------------------------------------------  //

METHOD PQsetClientEncoding( cEnc ) CLASS WDO_PG

RETU hb_DynCall( { "PQsetClientEncoding", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong, HB_DYN_CTYPE_CHAR_PTR },;
                  ::hConnection, cEnc )

//	-------------------------------------------------------  //

METHOD PQclientEncoding() CLASS WDO_PG

RETU hb_DynCall( { "PQclientEncoding", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong }, ::hConnection )

//	-------------------------------------------------------  //

METHOD PQfreemem( pPtr ) CLASS WDO_PG

RETU hb_DynCall( { "PQfreemem", ::pLib, hb_bitOr( HB_DYN_CTYPE_VOID,;
                    ::nSysCallConv ), ::nSysLong }, pPtr )

//	=======================================================  //
//  Prepared statements — libpq native protocol (text params)
//
//  Pointer parameters (paramTypes, paramValues, paramLengths,
//  paramFormats) accept 0 (NULL) when not needed. Non-zero must be
//  a native pointer previously built with WDO_BindAlloc + friends
//  (see wdo_mysql_stmt_bin.prg #pragma BEGINDUMP helpers).
//	=======================================================  //

METHOD PQprepare( cName, cSql, nParams, pParamTypes ) CLASS WDO_PG

   LOCAL u
   LOCAL bNewError := {| oError | Break( oError ) }
   LOCAL bOldError := ErrorBlock( bNewError )

   hb_default( @nParams,     0 )
   hb_default( @pParamTypes, WDO_PtrNull() )

   BEGIN SEQUENCE
      u := hb_DynCall( { "PQprepare", ::pLib,;
                          hb_bitOr( ::nSysLong, ::nSysCallConv ),;
                          ::nSysLong,;
                          HB_DYN_CTYPE_CHAR_PTR,;
                          HB_DYN_CTYPE_CHAR_PTR,;
                          HB_DYN_CTYPE_INT,;
                          HB_DYN_CTYPE_VOID_PTR },;
                          ::hConnection, cName, cSql, nParams, pParamTypes )
   RECOVER
      ::SetError( ::PQerrorMessage() )
      ErrorBlock( bOldError )
      RETU 0
   END SEQUENCE

   ErrorBlock( bOldError )

RETU u

//	-------------------------------------------------------  //

METHOD PQexecPrepared( cName, nParams, pParamValues,;
                       pParamLengths, pParamFormats, nResultFormat ) CLASS WDO_PG

   LOCAL u
   LOCAL bNewError := {| oError | Break( oError ) }
   LOCAL bOldError := ErrorBlock( bNewError )

   hb_default( @nParams,        0 )
   hb_default( @pParamValues,   WDO_PtrNull() )
   hb_default( @pParamLengths,  WDO_PtrNull() )
   hb_default( @pParamFormats,  WDO_PtrNull() )
   hb_default( @nResultFormat,  0 )   //  0 = text, 1 = binary (v2)

   BEGIN SEQUENCE
      u := hb_DynCall( { "PQexecPrepared", ::pLib,;
                          hb_bitOr( ::nSysLong, ::nSysCallConv ),;
                          ::nSysLong,;
                          HB_DYN_CTYPE_CHAR_PTR,;
                          HB_DYN_CTYPE_INT,;
                          HB_DYN_CTYPE_VOID_PTR,;
                          HB_DYN_CTYPE_VOID_PTR,;
                          HB_DYN_CTYPE_VOID_PTR,;
                          HB_DYN_CTYPE_INT },;
                          ::hConnection, cName, nParams,;
                          pParamValues, pParamLengths, pParamFormats,;
                          nResultFormat )
   RECOVER
      ::SetError( ::PQerrorMessage() )
      ErrorBlock( bOldError )
      RETU 0
   END SEQUENCE

   ErrorBlock( bOldError )

RETU u

//	-------------------------------------------------------  //

METHOD PQexecParams( cSql, nParams, pParamTypes, pParamValues,;
                     pParamLengths, pParamFormats, nResultFormat ) CLASS WDO_PG

   LOCAL u
   LOCAL bNewError := {| oError | Break( oError ) }
   LOCAL bOldError := ErrorBlock( bNewError )

   hb_default( @nParams,        0 )
   hb_default( @pParamTypes,    WDO_PtrNull() )
   hb_default( @pParamValues,   WDO_PtrNull() )
   hb_default( @pParamLengths,  WDO_PtrNull() )
   hb_default( @pParamFormats,  WDO_PtrNull() )
   hb_default( @nResultFormat,  0 )

   BEGIN SEQUENCE
      u := hb_DynCall( { "PQexecParams", ::pLib,;
                          hb_bitOr( ::nSysLong, ::nSysCallConv ),;
                          ::nSysLong,;
                          HB_DYN_CTYPE_CHAR_PTR,;
                          HB_DYN_CTYPE_INT,;
                          HB_DYN_CTYPE_VOID_PTR,;
                          HB_DYN_CTYPE_VOID_PTR,;
                          HB_DYN_CTYPE_VOID_PTR,;
                          HB_DYN_CTYPE_VOID_PTR,;
                          HB_DYN_CTYPE_INT },;
                          ::hConnection, cSql, nParams,;
                          pParamTypes, pParamValues,;
                          pParamLengths, pParamFormats,;
                          nResultFormat )
   RECOVER
      ::SetError( ::PQerrorMessage() )
      ErrorBlock( bOldError )
      RETU 0
   END SEQUENCE

   ErrorBlock( bOldError )

RETU u

//	-------------------------------------------------------  //

METHOD PQdescribePrepared( cName ) CLASS WDO_PG

RETU hb_DynCall( { "PQdescribePrepared", ::pLib,;
                    hb_bitOr( ::nSysLong, ::nSysCallConv ),;
                    ::nSysLong, HB_DYN_CTYPE_CHAR_PTR },;
                    ::hConnection, cName )

//	-------------------------------------------------------  //

METHOD PQnparams( hRes ) CLASS WDO_PG

RETU hb_DynCall( { "PQnparams", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT,;
                    ::nSysCallConv ), ::nSysLong }, hRes )

//	-------------------------------------------------------  //

METHOD PQparamtype( hRes, nParam ) CLASS WDO_PG

RETU hb_DynCall( { "PQparamtype", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT_UNSIGNED,;
                    ::nSysCallConv ), ::nSysLong, HB_DYN_CTYPE_INT }, hRes, nParam )


//	=======================================================  //
//  Global helpers
//	=======================================================  //

FUNCTION WDO_PgCountOpen()

   LOCAL n

   hb_mutexLock( soMutex )
   n := snOpen
   hb_mutexUnlock( soMutex )

RETU n

//	-------------------------------------------------------  //
//  _WdoPgResolveDll( cOverride, @cSourceOut )
//
//  Precedence chain (highest wins):
//    1. cOverride                       -- explicit path from New()/InitPoolEx
//    2. hb_DirBase() + libpq.dll        -- DLL dropped next to the running exe
//    3. env WDO_LIB_PG                  -- full path, all platforms
//    4. env WDO_PATH_PG                 -- folder + libpq.dll (Windows)
//    5. resources/wdo/pg/dll/libpq.dll  -- repo-relative, resolved from exe dir
//    6. platform default                -- /usr/lib or hardcoded fallback
//	-------------------------------------------------------  //

STATIC FUNCTION _WdoPgResolveDll( cOverride, cSourceOut )

   LOCAL cLibName, cEnv, cCanonical, cExeDll, cRepoDll

   //  1) Explicit override
   IF cOverride != NIL .AND. ! Empty( cOverride )
      IF cSourceOut != NIL ; cSourceOut := "override" ; ENDIF
      RETU cOverride
   ENDIF

   //  Canonical name per platform. libpq keeps the same name across
   //  32/64 bit on Windows (unlike libmysql64.dll).
   IF "Windows" $ OS()
      cCanonical := "libpq.dll"
   ELSEIF "Darwin" $ OS()
      cCanonical := "libpq.5.dylib"
   ELSE
      cCanonical := "libpq.so.5"
   ENDIF

   //  2) Same directory as the running executable (hb_DirBase)
   cExeDll := hb_DirBase() + cCanonical
   IF hb_FileExists( cExeDll )
      //  Return the full path. Returning the bare name delegates
      //  resolution to the OS loader, which on systems with a stale
      //  libpq.dll elsewhere in PATH (e.g. 32-bit PostgreSQL clients
      //  under Program Files) picks the wrong one and fails with
      //  "LoadLibrary failed" / arch mismatch.
      IF cSourceOut != NIL ; cSourceOut := "exedir" ; ENDIF
      RETU cExeDll
   ENDIF

   //  3) Full-path env (all platforms)
   cEnv := HB_GetEnv( 'WDO_LIB_PG' )
   IF ! Empty( cEnv )
      IF cSourceOut != NIL ; cSourceOut := "WDO_LIB_PG" ; ENDIF
      RETU cEnv
   ENDIF

   //  4) Folder env (Windows & Linux) + canonical filename
   cEnv := HB_GetEnv( 'WDO_PATH_PG' )
   IF ! Empty( cEnv )
      IF Right( cEnv, 1 ) != '/' .AND. Right( cEnv, 1 ) != '\'
         cEnv += '/'
      ENDIF
      IF cSourceOut != NIL ; cSourceOut := "WDO_PATH_PG" ; ENDIF
      RETU cEnv + cCanonical
   ENDIF

   //  5) Repo-relative: resources/wdo/pg/dll/ next to the exe directory
   //  (hb_DirBase ends in /; walk up to find the repo root if the exe
   //  lives in tests/wdo/ or similar).
   cRepoDll := hb_DirBase() + "resources/wdo/pg/dll/" + cCanonical
   IF hb_FileExists( cRepoDll )
      IF cSourceOut != NIL ; cSourceOut := "repo" ; ENDIF
      RETU cRepoDll
   ENDIF

   //  Also try two levels up (typical tests layout tests/wdo/ -> repo root)
   cRepoDll := hb_DirBase() + "../../resources/wdo/pg/dll/" + cCanonical
   IF hb_FileExists( cRepoDll )
      IF cSourceOut != NIL ; cSourceOut := "repo-rel" ; ENDIF
      RETU cRepoDll
   ENDIF

   //  Three levels up (tests/wdo/pg/ -> repo root)
   cRepoDll := hb_DirBase() + "../../../resources/wdo/pg/dll/" + cCanonical
   IF hb_FileExists( cRepoDll )
      IF cSourceOut != NIL ; cSourceOut := "repo-rel3" ; ENDIF
      RETU cRepoDll
   ENDIF

   //  6) Platform default
   IF cSourceOut != NIL ; cSourceOut := "default" ; ENDIF

   IF "Windows" $ OS()
      cLibName := "libpq.dll"
   ELSEIF "Darwin" $ OS()
      cLibName := "/usr/local/lib/libpq.5.dylib"
   ELSE
      cLibName := "/usr/lib/x86_64-linux-gnu/libpq.so.5"
   ENDIF

RETU cLibName

//	-------------------------------------------------------  //
//  _WdoPgTcpProbe( cHost, nPort, nTimeoutMs )
//
//  Raw TCP probe (IPv4). Avoids ~2 min hangs in PQconnectdb when
//  the server is down. 'localhost' is remapped to 127.0.0.1 because
//  on Windows it often resolves to ::1 (IPv6) which would block.
//	-------------------------------------------------------  //

STATIC FUNCTION _WdoPgTcpProbe( cHost, nPort, nTimeoutMs )

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
//  _WdoPgReportDown( cHost, nPort )
//
//  Prints "==> Error: PostgreSQL not running" to stdout once per
//  host:port. Protected by s_mtxDown. Aborts the process so a pool
//  init with N failing connections prints the message exactly once.
//	-------------------------------------------------------  //

STATIC FUNCTION _WdoPgReportDown( cHost, nPort )

   LOCAL cKey := cHost + ":" + hb_NToS( nPort )
   LOCAL lFirst := .F.

   hb_mutexLock( s_mtxDown )
   IF ! hb_HHasKey( s_hDownReported, cKey )
      s_hDownReported[ cKey ] := .T.
      lFirst := .T.
   ENDIF
   hb_mutexUnlock( s_mtxDown )

   IF lFirst
      OutStd( "==> Error: PostgreSQL not running (" + cKey + ")" + hb_eol() )
   ENDIF

RETU NIL

//	-------------------------------------------------------  //
//  _WdoPgReportDllFail( cDll, cReason )
//
//  Prints a "Cannot load DLL" message once (deduped by DLL name
//  using the same s_hDownReported hash with a "DLL:" prefix).
//	-------------------------------------------------------  //

STATIC FUNCTION _WdoPgReportDllFail( cDll, cReason )

   LOCAL cKey   := "DLL:" + cDll
   LOCAL lFirst := .F.

   hb_mutexLock( s_mtxDown )
   IF ! hb_HHasKey( s_hDownReported, cKey )
      s_hDownReported[ cKey ] := .T.
      lFirst := .T.
   ENDIF
   hb_mutexUnlock( s_mtxDown )

   IF lFirst
      OutStd( "==> Error: Cannot load PostgreSQL DLL (" + cDll + ": " + cReason + ")" + hb_eol() )
      OutStd( "Press any key to continue..." + hb_eol() )
   ENDIF

RETU NIL

//	-------------------------------------------------------  //
//  SQL escape for PG (standard_conforming_strings=on default).
//  Doubles single quotes; backslash is NOT escaped. Callers can
//  rely on this across PG 9.1+. For PG with the legacy mode
//  enabled, use PQescapeStringConn (not yet wrapped).
//	-------------------------------------------------------  //

FUNCTION wdo_pg_addslashes( c )
RETU StrTran( c, "'", "''" )

//	-------------------------------------------------------  //
//  Quote a value for a libpq connstring key=value. If it has
//  spaces, quotes or backslashes we wrap it in single quotes and
//  escape embedded quotes/backslashes with '\' per libpq rules.
//	-------------------------------------------------------  //

STATIC FUNCTION _WdoPgQuoteConn( cVal )

   LOCAL cOut

   IF Empty( cVal )
      RETU "''"
   ENDIF

   IF "'" $ cVal .OR. "\" $ cVal .OR. " " $ cVal
      cOut := StrTran( cVal, "\", "\\" )
      cOut := StrTran( cOut, "'", "\'" )
      RETU "'" + cOut + "'"
   ENDIF

RETU cVal
