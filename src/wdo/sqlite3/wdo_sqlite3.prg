/*-----------------------------------------------------------
  File ......: wdo_sqlite3.prg
  Author.....: Charly 9000
  Created....: 2026-10-05
  Modified...: 2026-11-20
  Version....: 2.0.0
  Description: SQLite3 / SQLCipher connection class via native
               DynCall against sqlcipher.dll (bundled under
               resources/wdo/sqlite3/dll/). Does NOT depend on
               the Harbour hbsqlit3 contrib. Owns pLib + pDb,
               exposes DynCall wrappers for the stable sqlite3
               C API, and supports the SQLCipher PRAGMAs:
                 key, rekey, cipher_kdf_iter, cipher_page_size,
                 cipher_hmac_algorithm, cipher_kdf_algorithm.
               Standalone (no pool): the singleton is registered
               via WDO_RegisterConn so WDO_Get(cKey) returns the
               same handle for every worker thread. SQLite
               serializes concurrent access internally when
               compiled with THREADSAFE=1; a per-conn Harbour
               mutex adds a second layer so step()/column() runs
               on a stmt are not interleaved across threads.
  Usage      : oConn := WDO_Sqlite3():New( "data.db", .T. )
               oConn:cKey := "secret"   //  before Open()
               oConn:Open()
               oStmt := oConn:Query( "SELECT * FROM users" )
  Notes      : Mirrors the WDO_PG/WDO_MySql class layout so
               callers can switch drivers without churn. The
               cipher key is applied via `PRAGMA key` IMMEDIATELY
               after sqlite3_open and BEFORE any other PRAGMA â€”
               that is the SQLCipher contract.
 -----------------------------------------------------------*/

#include 'hix_const.ch'
#include 'hix_logger.ch'
#include 'hbclass.ch'
#include "hbdyn.ch"
#include "fileio.ch"
#include "wdo_metrics.ch"
#include "wdo_sqlite3.ch"

#define VERSION_WDO_SQLITE3        '2.0'

#define NULL                       0

STATIC snOpen := 0
STATIC soMutex

//  Dedupe of the "Cannot load DLL" and "DB corrupt / wrong key" messages
//  so a pool init with N failing conns prints each cause exactly once.
STATIC s_hDownReported := NIL
STATIC s_mtxDown

INIT PROCEDURE _WDO_Sqlite3Init()
   soMutex         := hb_mutexCreate()
   s_mtxDown       := hb_mutexCreate()
   s_hDownReported := {=>}
RETURN


CLASS WDO_Sqlite3 FROM WDO

   DATA cFile
   DATA cType                          INIT 'SQLITE3'
   DATA cDllType                       INIT WDO_SQLITE3_DLL_TYPE

   DATA pLib
   DATA pDb                            INIT NIL      //  sqlite3* as Harbour POINTER

   DATA nSysCallConv
   DATA nSysLong

   DATA cDllPath                       INIT NIL
   DATA cDllSource                     INIT ''

   DATA lConnect                       INIT .F.
   DATA lInUse                         INIT .F.
   DATA lInTrans                       INIT .F.
   DATA tLastUsed
   DATA lPersistent                    INIT .F.
   DATA lLog                           INIT .F.
   DATA lWeb                           INIT .T.

   //  SQLite serializes concurrent access internally. There is no pool
   //  of connections; the singleton is shared by every worker. oPool
   //  stays NIL â€” kept for class parity with WDO_PG/MySql.
   DATA oPool                          INIT NIL
   DATA cPoolKey                       INIT "-"

   //  PRAGMAs
   DATA cJournalMode                   INIT 'WAL'
   DATA cSynchronous                   INIT 'NORMAL'
   DATA lForeignKeys                   INIT .T.
   DATA lCreate                        INIT .T.
   DATA lToUtf8                        INIT .T.      //  reserved â€” kept for parity/opt-in
   DATA nBusyTimeoutMs                 INIT WDO_SQLITE3_DEFAULT_BUSY_MS

   //  SQLCipher. cKey is the plaintext passphrase OR a "x'<hex>'" raw
   //  key. Empty cKey keeps the file unencrypted. cKeyRef is an optional
   //  alias resolved via HIX_KeyGet() right before Open().
   DATA cKey                           INIT ''
   DATA cKeyRef                        INIT ''
   DATA nKdfIter                       INIT 0        //  0 â†’ SQLCipher default
   DATA nCipherPageSize                INIT 0        //  0 â†’ SQLCipher default
   DATA cHmacAlg                       INIT ''
   DATA cKdfAlg                        INIT ''
   DATA lEncrypted                     INIT .F.      //  .T. once PRAGMA key was applied

   //  Per-connection Harbour mutex. Guards call-sites that read partial
   //  state on a shared WDO_Sqlite3Stmt (step followed by column reads)
   //  against mid-call preemption from another worker thread.
   DATA hMutex

   //  Monotonic counter for synthetic stmt names (kept for parity â€” SQLite
   //  prepared stmts don't need a server-side name).
   DATA nStmtSeq                       INIT 0

   METHOD New( cFile, lCreate, cDllPath ) CONSTRUCTOR
   METHOD Open()
   METHOD Close()
   METHOD End()                        INLINE ::Close()
   METHOD Destroy()                    INLINE ::Close()
   METHOD Exit()

   METHOD Ping()
   METHOD Reconnect()
   METHOD IsAlive()

   METHOD Escape( x )

   METHOD Exec( cSql )
   METHOD Query( cSql )
   METHOD Prepare( cSql )

   METHOD BeginTrans()
   METHOD Commit()
   METHOD Rollback()
   METHOD InTransaction()              INLINE ::lInTrans
   METHOD Transaction( bCode )

   METHOD Last_Insert_Id()
   METHOD Changes()
   METHOD Total_Changes()
   METHOD Affected_Rows()              INLINE ::Changes()
   METHOD IsTable( cTable )

   METHOD Rekey( cNewKey )
   METHOD IsEncrypted()                INLINE ::lEncrypted
   METHOD GetCipherInfo()

   METHOD ServerInfo()
   METHOD ClientInfo()                 INLINE ::GetDllVersion()
   METHOD LibVersion()                 INLINE ::GetDllVersion()
   METHOD GetDllVersion()
   METHOD GetClientInfo()
   METHOD GetConnectionInfo()
   METHOD DllPath()                    INLINE iif( ::cDllPath == NIL, '', ::cDllPath )
   METHOD DllSource()                  INLINE ::cDllSource

   METHOD Lock()                       INLINE hb_mutexLock( ::hMutex )
   METHOD UnLock()                     INLINE hb_mutexUnlock( ::hMutex )

   METHOD CountOpen()                  INLINE WDO_Sqlite3CountOpen()
   METHOD Version()                    INLINE VERSION_WDO_SQLITE3
   METHOD VersionName()                INLINE 'WDO_SQLITE3 ' + VERSION_WDO_SQLITE3

   //  DynCall wrappers (sqlite3 C API)
   METHOD SqliteOpen( cFile, pDbOut )
   METHOD SqliteClose()
   METHOD SqliteExec( cSql )
   METHOD SqliteErrcode()
   METHOD SqliteErrmsg()
   METHOD SqliteLibVersion()
   METHOD SqliteChanges()
   METHOD SqliteTotalChanges()
   METHOD SqliteLastInsertRowid()
   METHOD SqliteBusyTimeout( nMs )
   METHOD SqliteKey( cKey )
   METHOD SqliteRekey( cKey )

ENDCLASS

//	-------------------------------------------------------  //

METHOD New( cFile, lCreate, cDllPath ) CLASS WDO_Sqlite3

   ::Super:New()

   hb_default( @cFile,   ':memory:' )
   hb_default( @lCreate, .T. )

   ::cFile   := cFile
   ::lCreate := lCreate
   ::hMutex  := hb_mutexCreate()

   IF cDllPath != NIL .AND. ! Empty( cDllPath )
      ::cDllPath := cDllPath
   ENDIF

RETU SELF

//	-------------------------------------------------------  //

METHOD Open() CLASS WDO_Sqlite3

   LOCAL cDll, nRc
   LOCAL cEffectiveKey
   LOCAL pDbOut := 0

   IF ::lConnect
      RETU NIL
   ENDIF

   IF( ::lLog, _d( 'WDO Sqlite3 log activated' ), NIL )

   //  Resolve full DLL path from override + env vars + exe dir + defaults.
   //  Stores the origin tag in ::cDllSource for diagnostics.
   cDll       := _WdoSqlite3ResolveDll( ::cDllPath, @::cDllSource )
   ::cDllPath := cDll

   //  Skip File() check when the resolver returned a bare name (source
   //  "default"): existence will be re-tried by the OS loader via PATH.
   IF ::cDllSource != "default" .AND. ! File( cDll )
      _WdoSqlite3ReportDllFail( cDll, "not found" )
      ::SetError( _( 'WDO_ERR_LIB_NOT_FOUND', cDll + ' [' + ::cDllSource + ']' ), 'Loading dll' )
      RETU NIL
   ENDIF

   ::pLib := hb_LibLoad( cDll )

   IF ValType( ::pLib ) <> "P"
      _WdoSqlite3ReportDllFail( cDll, "failed to load" )
      ::SetError( _( 'WDO_ERR_LIB_WRONG', Lower( cDll ) + ' [' + ::cDllSource + ']' ) )
      RETU NIL
   ENDIF

   ::nSysCallConv := hb_SysCallConv()
   ::nSysLong     := hb_SysLong()

   //  sqlite3_open(filename, &pDb) â€” returns SQLITE_OK or an error code.
   //  pDb is populated even on failure, so we always close it.
   nRc := ::SqliteOpen( ::cFile, @pDbOut )
   ::pDb := pDbOut

   IF nRc != SQLITE_OK .OR. ValType( ::pDb ) != "P"
      ::SetError( _( 'WDO_ERR_SQLITE_OPEN', ::cFile + " rc=" + hb_NToS( nRc ) ) )
      IF ValType( ::pDb ) == "P"
         ::SqliteClose()
      ENDIF
      ::pDb := NIL
      HB_LibFree( ::pLib )
      ::pLib := NIL
      RETU NIL
   ENDIF

   //  busy_timeout runs BEFORE any PRAGMA â€” otherwise a concurrent writer
   //  can cause SQLITE_BUSY on the very first PRAGMA statement.
   IF ::nBusyTimeoutMs > 0
      ::SqliteBusyTimeout( ::nBusyTimeoutMs )
   ENDIF

   //  SQLCipher: apply the key IMMEDIATELY after open, BEFORE any
   //  other statement. Resolve cKeyRef via HIX_Keys if cKey is empty.
   cEffectiveKey := ::cKey
   IF Empty( cEffectiveKey ) .AND. ! Empty( ::cKeyRef )
      cEffectiveKey := HIX_KeyGet( ::cKeyRef, "" )
   ENDIF

   IF ! Empty( cEffectiveKey )
      //  sqlite3_key copies the key material; our buffer can be freed.
      nRc := ::SqliteKey( cEffectiveKey )
      IF nRc != SQLITE_OK
         ::SetError( _( 'WDO_ERR_SQLITE_OPEN', "sqlite3_key rc=" + hb_NToS( nRc ) ) )
         ::SqliteClose()
         HB_LibFree( ::pLib )
         ::pLib := NIL
         ::pDb := NIL
         RETU NIL
      ENDIF

      //  Cipher PRAGMAs that MUST run before any non-key statement so
      //  the derived key uses the requested iteration count / page size.
      IF ::nKdfIter > 0
         ::SqliteExec( "PRAGMA cipher_kdf_iter = " + hb_NToS( ::nKdfIter ) )
      ENDIF
      IF ::nCipherPageSize > 0
         ::SqliteExec( "PRAGMA cipher_page_size = " + hb_NToS( ::nCipherPageSize ) )
      ENDIF
      IF ! Empty( ::cHmacAlg )
         ::SqliteExec( "PRAGMA cipher_hmac_algorithm = " + ::cHmacAlg )
      ENDIF
      IF ! Empty( ::cKdfAlg )
         ::SqliteExec( "PRAGMA cipher_kdf_algorithm = " + ::cKdfAlg )
      ENDIF

      //  Verify the key by touching sqlite_master. A wrong key or
      //  mismatched cipher params returns SQLITE_NOTADB (26).
      nRc := ::SqliteExec( "SELECT count(*) FROM sqlite_master" )
      IF nRc != SQLITE_OK
         _WdoSqlite3ReportKeyFail( ::cFile, nRc, ::SqliteErrmsg() )
         ::SetError( _( 'WDO_ERR_SQLITE_OPEN', ;
                        "key verification failed rc=" + hb_NToS( nRc ) + ": " + ::SqliteErrmsg() ) )
         ::SqliteClose()
         HB_LibFree( ::pLib )
         ::pLib := NIL
         ::pDb := NIL
         RETU NIL
      ENDIF

      ::lEncrypted := .T.
   ENDIF

   //  Operational PRAGMAs: WAL journal, fsync policy, foreign keys.
   //  Failures here are not fatal â€” they log and continue.
   IF ! Empty( ::cJournalMode )
      ::SqliteExec( "PRAGMA journal_mode = " + ::cJournalMode )
   ENDIF
   IF ! Empty( ::cSynchronous )
      ::SqliteExec( "PRAGMA synchronous = " + ::cSynchronous )
   ENDIF
   IF ::lForeignKeys
      ::SqliteExec( "PRAGMA foreign_keys = ON" )
   ENDIF

   ::lConnect  := .T.
   ::tLastUsed := hb_DateTime()

   hb_mutexLock( soMutex )
   snOpen++
   hb_mutexUnlock( soMutex )

   //  Register driver as successfully loaded so the server banner shows
   //  it in the "WDO Loaded" line. Idempotent across singleton reopens.
   WDO_LoadedRegister( ::cDllType, WDO_Version() )

   //  Publish server/client version and file name in the info registry.
   WDO_InfoRegister( "RDBMS " + ::cDllType + " Server", ::ServerInfo() )
   WDO_InfoRegister( "RDBMS " + ::cDllType + " File",   ::cFile )

RETU NIL

//	-------------------------------------------------------  //

METHOD Close() CLASS WDO_Sqlite3

   LOCAL lWasConnected

   //  SQLite has no pool: always do the real teardown here.
   IF ::oPool != NIL
      ::oPool:Release( SELF )
      RETU NIL
   ENDIF

   lWasConnected := ::lConnect

   IF ValType( ::pLib ) == "P"

      IF( ::lLog, _d( 'WDO Sqlite3 Close proc' ), NIL )

      IF ValType(::pDb) == "P"
         ::SqliteClose()
      ENDIF

      HB_LibFree( ::pLib )

      ::pLib        := NIL
      ::pDb := NIL
      ::lConnect    := .F.
      ::lInTrans    := .F.
      ::lEncrypted  := .F.

   ENDIF

   IF lWasConnected
      hb_mutexLock( soMutex )
      snOpen--
      hb_mutexUnlock( soMutex )
   ENDIF

RETU NIL

//	-------------------------------------------------------  //

METHOD Exit() CLASS WDO_Sqlite3

   IF ::lPersistent
      IF( ::lLog, _d( 'WDO Sqlite3 Persistent' ), NIL )
      RETU NIL
   ENDIF

RETU NIL

//	-------------------------------------------------------  //

METHOD Ping() CLASS WDO_Sqlite3

   IF ! ::lConnect .OR. ValType( ::pDb ) != "P"
      RETU .F.
   ENDIF

RETU ::SqliteExec( "SELECT 1" ) == SQLITE_OK

//	-------------------------------------------------------  //

METHOD Reconnect() CLASS WDO_Sqlite3

   ::Close()
   ::Open()

RETU ::lConnect

//	-------------------------------------------------------  //

METHOD IsAlive() CLASS WDO_Sqlite3

RETU ::lConnect .AND. ::Ping()

//	-------------------------------------------------------  //
//  SQL escaping. SQLite accepts single-quoted literals with '' as the
//  only in-string escape. Mirrors wdo_pg_addslashes.
//	-------------------------------------------------------  //
METHOD Escape( hRow ) CLASS WDO_Sqlite3

   LOCAL n, aPair, nLen
   LOCAL cType := ValType( hRow )

   DO CASE
   CASE cType == 'H'
      nLen := Len( hRow )
      FOR n := 1 TO nLen
         aPair := HB_HPairAt( hRow, n )
         IF ValType( aPair[2] ) == 'C' .OR. ValType( aPair[2] ) == 'M'
            hRow[ aPair[1] ] := wdo_sqlite3_addslashes( aPair[2] )
         ENDIF
      NEXT

   CASE cType == 'A'
      nLen := Len( hRow )
      FOR n := 1 TO nLen
         IF ValType( hRow[n] ) == 'C' .OR. ValType( hRow[n] ) == 'M'
            hRow[n] := wdo_sqlite3_addslashes( hRow[n] )
         ENDIF
      NEXT

   CASE cType == 'C' .OR. cType == 'M'
      hRow := wdo_sqlite3_addslashes( hRow )

   ENDCASE

RETU hRow

//	-------------------------------------------------------  //
//  Exec: fire-and-forget DDL/DML. Returns .T. on success. Lock-protected.
METHOD Exec( cSql ) CLASS WDO_Sqlite3

   LOCAL nRc
   LOCAL nT0

   IF ValType(::pDb) != "P"
      RETU .F.
   ENDIF

   IF( ::lLog, _d( 'WDO ' + cSql ), NIL )

   nT0 := hb_MilliSeconds()

   hb_mutexLock( ::hMutex )
   nRc := ::SqliteExec( cSql )
   hb_mutexUnlock( ::hMutex )

   WDO_MetricQuery( ::cPoolKey, cSql, hb_MilliSeconds() - nT0, NIL )

   ::tLastUsed := hb_DateTime()

   IF nRc != SQLITE_OK
      ::SetError( _( 'WDO_ERR_SQLITE_EXEC', ;
                     hb_NToS( nRc ) + ": " + ::SqliteErrmsg() ) )
      WDO_Metric( WDOM_QUERIES_ERRORS )
      RETU .F.
   ENDIF

RETU .T.

//	-------------------------------------------------------  //
//  Query: Prepare + Execute. Returns a WDO_Sqlite3Stmt stepped once
//  so FCount/Fetch_Assoc work immediately.
METHOD Query( cSql ) CLASS WDO_Sqlite3

   LOCAL oStmt
   LOCAL nT0

   IF ValType(::pDb) != "P"
      RETU NIL
   ENDIF

   nT0  := hb_MilliSeconds()
   oStmt := ::Prepare( cSql )

   IF oStmt == NIL .OR. oStmt:lError
      WDO_MetricQuery( ::cPoolKey, cSql, hb_MilliSeconds() - nT0, NIL )
      RETU oStmt
   ENDIF

   oStmt:Execute()

   //  Auto-finalize on step failure. SQLite keeps the DB in an error
   //  state until the failing stmt is released â€” forgetting Free() on
   //  the error branch would leave the next transaction locked.
   IF oStmt:lError
      oStmt:Free()
   ENDIF

   WDO_MetricQuery( ::cPoolKey, cSql, hb_MilliSeconds() - nT0, NIL )

   ::tLastUsed := hb_DateTime()

RETU oStmt

//	-------------------------------------------------------  //

METHOD Prepare( cSql ) CLASS WDO_Sqlite3

   IF ValType(::pDb) != "P"
      RETU NIL
   ENDIF

   ::nStmtSeq++

RETU WDO_Sqlite3Stmt():New( SELF, cSql )

//	-------------------------------------------------------  //
//  IsTable: cheap sqlite_master lookup.
METHOD IsTable( cTable ) CLASS WDO_Sqlite3

   LOCAL oStmt, lHit := .F.

   IF ValType(::pDb) != "P"
      RETU .F.
   ENDIF

   oStmt := ::Prepare( "SELECT 1 FROM sqlite_master WHERE type='table' AND name=:name" )

   IF oStmt == NIL .OR. oStmt:lError
      RETU .F.
   ENDIF

   oStmt:BindParam( ":name", cTable )
   oStmt:Execute()

   lHit := ! oStmt:lEof
   oStmt:Free()

RETU lHit

//	-------------------------------------------------------  //
//  Transactions
//	-------------------------------------------------------  //

METHOD BeginTrans() CLASS WDO_Sqlite3

   IF ! ::lConnect .OR. ::lInTrans
      RETU .F.
   ENDIF

   IF ! ::Exec( "BEGIN" )
      RETU .F.
   ENDIF

   ::lInTrans  := .T.
   ::tLastUsed := hb_DateTime()

RETU .T.

//	-------------------------------------------------------  //

METHOD Commit() CLASS WDO_Sqlite3

   IF ! ::lInTrans
      RETU .F.
   ENDIF

   IF ! ::Exec( "COMMIT" )
      ::lInTrans := .F.
      RETU .F.
   ENDIF

   ::lInTrans  := .F.
   ::tLastUsed := hb_DateTime()

RETU .T.

//	-------------------------------------------------------  //

METHOD Rollback() CLASS WDO_Sqlite3

   IF ! ::lInTrans
      RETU .F.
   ENDIF

   ::SqliteExec( "ROLLBACK" )
   ::lInTrans  := .F.
   ::tLastUsed := hb_DateTime()

RETU .T.

//	-------------------------------------------------------  //

METHOD Transaction( bCode ) CLASS WDO_Sqlite3

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

METHOD Last_Insert_Id() CLASS WDO_Sqlite3

   IF ValType(::pDb) != "P"
      RETU -1
   ENDIF

RETU ::SqliteLastInsertRowid()

//	-------------------------------------------------------  //

METHOD Changes() CLASS WDO_Sqlite3

   IF ValType(::pDb) != "P"
      RETU 0
   ENDIF

RETU ::SqliteChanges()

//	-------------------------------------------------------  //

METHOD Total_Changes() CLASS WDO_Sqlite3

   IF ValType(::pDb) != "P"
      RETU 0
   ENDIF

RETU ::SqliteTotalChanges()

//	-------------------------------------------------------  //
//  Rekey: re-encrypt the DB with a new passphrase. Pass "" to strip
//  encryption (SQLCipher 4+ supports the empty rekey to decrypt).
//	-------------------------------------------------------  //

METHOD Rekey( cNewKey ) CLASS WDO_Sqlite3

   LOCAL nRc

   IF ValType(::pDb) != "P"
      RETU .F.
   ENDIF

   nRc := ::SqliteRekey( iif( cNewKey == NIL, "", cNewKey ) )

   IF nRc != SQLITE_OK
      ::SetError( _( 'WDO_ERR_SQLITE_EXEC', ;
                     "sqlite3_rekey rc=" + hb_NToS( nRc ) + ": " + ::SqliteErrmsg() ) )
      RETU .F.
   ENDIF

   ::cKey       := iif( cNewKey == NIL, "", cNewKey )
   ::lEncrypted := ! Empty( ::cKey )

RETU .T.

//	-------------------------------------------------------  //
//  GetCipherInfo: reads the active cipher parameters via SQLCipher
//  PRAGMAs. Returns a hash with the four knobs (empty for non-encrypted
//  DBs so callers can branch on ::lEncrypted + Empty(hInfo)).
//	-------------------------------------------------------  //

METHOD GetCipherInfo() CLASS WDO_Sqlite3

   LOCAL hInfo := {=>}
   LOCAL oStmt, hRow

   IF ! ::lEncrypted .OR. ValType(::pDb) != "P"
      RETU hInfo
   ENDIF

   //  PRAGMA cipher_version: SQLCipher library version string.
   oStmt := ::Query( "PRAGMA cipher_version" )
   IF oStmt != NIL .AND. ! oStmt:lError
      hRow := oStmt:Fetch()
      IF hRow != NIL .AND. Len( hRow ) >= 1
         hInfo[ "cipher_version" ] := hRow[ 1 ]
      ENDIF
      oStmt:Free()
   ENDIF

   //  SQLCipher 4.x removed `PRAGMA cipher_kdf_iter` as a reader (no rows)
   //  while keeping it as a setter. The portable reader is `PRAGMA kdf_iter`,
   //  which returns the current iteration count regardless of version.
   oStmt := ::Query( "PRAGMA kdf_iter" )
   IF oStmt != NIL .AND. ! oStmt:lError
      hRow := oStmt:Fetch()
      IF hRow != NIL .AND. Len( hRow ) >= 1 .AND. ! Empty( hRow[ 1 ] )
         hInfo[ "kdf_iter" ] := Val( hRow[ 1 ] )
      ENDIF
      oStmt:Free()
   ENDIF

   oStmt := ::Query( "PRAGMA cipher_page_size" )
   IF oStmt != NIL .AND. ! oStmt:lError
      hRow := oStmt:Fetch()
      IF hRow != NIL .AND. Len( hRow ) >= 1
         hInfo[ "page_size" ] := Val( hRow[ 1 ] )
      ENDIF
      oStmt:Free()
   ENDIF

   oStmt := ::Query( "PRAGMA cipher_hmac_algorithm" )
   IF oStmt != NIL .AND. ! oStmt:lError
      hRow := oStmt:Fetch()
      IF hRow != NIL .AND. Len( hRow ) >= 1
         hInfo[ "hmac_algorithm" ] := hRow[ 1 ]
      ENDIF
      oStmt:Free()
   ENDIF

   oStmt := ::Query( "PRAGMA cipher_kdf_algorithm" )
   IF oStmt != NIL .AND. ! oStmt:lError
      hRow := oStmt:Fetch()
      IF hRow != NIL .AND. Len( hRow ) >= 1
         hInfo[ "kdf_algorithm" ] := hRow[ 1 ]
      ENDIF
      oStmt:Free()
   ENDIF

RETU hInfo

//	-------------------------------------------------------  //

METHOD ServerInfo() CLASS WDO_Sqlite3

   IF ::pLib == NIL
      RETU "Unknown"
   ENDIF

RETU ::SqliteLibVersion()

//	-------------------------------------------------------  //

METHOD GetDllVersion() CLASS WDO_Sqlite3

   IF ::pLib == NIL
      RETU "Unknown"
   ENDIF

RETU ::SqliteLibVersion()

//	-------------------------------------------------------  //

METHOD GetClientInfo() CLASS WDO_Sqlite3

   LOCAL hInfo := {=>}

   hInfo[ "dll_version" ]    := ::GetDllVersion()
   hInfo[ "wdo_version" ]    := ::Version()
   hInfo[ "server_version" ] := ::ServerInfo()
   hInfo[ "bits" ]           := If( hb_OSIS64BIT(), "64 bits", "32 bits" )
   hInfo[ "dll_path" ]       := ::DllPath()
   hInfo[ "dll_source" ]     := ::DllSource()
   hInfo[ "encrypted" ]      := ::lEncrypted

RETU hInfo

//	-------------------------------------------------------  //

METHOD GetConnectionInfo() CLASS WDO_Sqlite3

   LOCAL hInfo := {=>}

   IF ValType(::pDb) != "P"
      RETU hInfo
   ENDIF

   hInfo[ "file"         ] := ::cFile
   hInfo[ "journal_mode" ] := ::cJournalMode
   hInfo[ "synchronous"  ] := ::cSynchronous
   hInfo[ "foreign_keys" ] := ::lForeignKeys
   hInfo[ "busy_timeout" ] := ::nBusyTimeoutMs
   hInfo[ "encrypted"    ] := ::lEncrypted

RETU hInfo

//	=======================================================  //
//  DynCall wrappers (sqlite3 / sqlcipher C API)
//	=======================================================  //

//  int sqlite3_open(const char *filename, sqlite3 **ppDb)
//  pDbOut is a Harbour @var bound to HB_DYN_CTYPE_LLONG_PTR so the
//  sqlite3* handle is written back into the caller's variable.
METHOD SqliteOpen( cFile, pDbOut ) CLASS WDO_Sqlite3

RETU hb_DynCall( { "sqlite3_open", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                   HB_DYN_CTYPE_CHAR_PTR, HB_DYN_CTYPE_LLONG_PTR }, cFile, @pDbOut )

//	-------------------------------------------------------  //
//  int sqlite3_close(sqlite3 *db)

METHOD SqliteClose() CLASS WDO_Sqlite3

RETU hb_DynCall( { "sqlite3_close", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR }, ::pDb )

//	-------------------------------------------------------  //
//  int sqlite3_exec(sqlite3*, const char *sql, int(*)(...), void*, char**)
//  We pass the last three args as NULL (no callback, no cookie, no errmsg
//  pickup â€” errors come from sqlite3_errmsg on the connection).

METHOD SqliteExec( cSql ) CLASS WDO_Sqlite3

   LOCAL u
   LOCAL bNewError := {| oError | Break( oError ) }
   LOCAL bOldError := ErrorBlock( bNewError )

   BEGIN SEQUENCE
      u := hb_DynCall( { "sqlite3_exec", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                         HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_CHAR_PTR,;
                         HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_VOID_PTR },;
                         ::pDb, cSql, NIL, NIL, NIL )
   RECOVER
      ErrorBlock( bOldError )
      RETU SQLITE_ERROR
   END SEQUENCE

   ErrorBlock( bOldError )

RETU u

//	-------------------------------------------------------  //
//  int sqlite3_errcode(sqlite3*)

METHOD SqliteErrcode() CLASS WDO_Sqlite3

RETU hb_DynCall( { "sqlite3_errcode", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR }, ::pDb )

//	-------------------------------------------------------  //
//  const char *sqlite3_errmsg(sqlite3*)

METHOD SqliteErrmsg() CLASS WDO_Sqlite3

RETU hb_DynCall( { "sqlite3_errmsg", ::pLib, hb_bitOr( HB_DYN_CTYPE_CHAR_PTR, ::nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR }, ::pDb )

//	-------------------------------------------------------  //
//  const char *sqlite3_libversion(void)

METHOD SqliteLibVersion() CLASS WDO_Sqlite3

RETU hb_DynCall( { "sqlite3_libversion", ::pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_CHAR_PTR, ::nSysCallConv ) } )

//	-------------------------------------------------------  //
//  int sqlite3_changes(sqlite3*)

METHOD SqliteChanges() CLASS WDO_Sqlite3

RETU hb_DynCall( { "sqlite3_changes", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR }, ::pDb )

//	-------------------------------------------------------  //
//  int sqlite3_total_changes(sqlite3*)

METHOD SqliteTotalChanges() CLASS WDO_Sqlite3

RETU hb_DynCall( { "sqlite3_total_changes", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR }, ::pDb )

//	-------------------------------------------------------  //
//  sqlite3_int64 sqlite3_last_insert_rowid(sqlite3*)

METHOD SqliteLastInsertRowid() CLASS WDO_Sqlite3

RETU hb_DynCall( { "sqlite3_last_insert_rowid", ::pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_LLONG, ::nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR }, ::pDb )

//	-------------------------------------------------------  //
//  int sqlite3_busy_timeout(sqlite3*, int ms)

METHOD SqliteBusyTimeout( nMs ) CLASS WDO_Sqlite3

RETU hb_DynCall( { "sqlite3_busy_timeout", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT }, ::pDb, nMs )

//	-------------------------------------------------------  //
//  int sqlite3_key(sqlite3*, const void *pKey, int nKey)
//  Present in SQLCipher, absent in stock SQLite â€” the call will fail
//  with "symbol not found" if the loaded DLL isn't SQLCipher.

METHOD SqliteKey( cKey ) CLASS WDO_Sqlite3

   LOCAL u
   LOCAL bNewError := {| oError | Break( oError ) }
   LOCAL bOldError := ErrorBlock( bNewError )

   BEGIN SEQUENCE
      u := hb_DynCall( { "sqlite3_key", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                         HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_CHAR_PTR, HB_DYN_CTYPE_INT },;
                         ::pDb, cKey, Len( cKey ) )
   RECOVER
      ErrorBlock( bOldError )
      RETU SQLITE_ERROR
   END SEQUENCE

   ErrorBlock( bOldError )

RETU u

//	-------------------------------------------------------  //
//  int sqlite3_rekey(sqlite3*, const void *pKey, int nKey)

METHOD SqliteRekey( cKey ) CLASS WDO_Sqlite3

   LOCAL u
   LOCAL bNewError := {| oError | Break( oError ) }
   LOCAL bOldError := ErrorBlock( bNewError )

   BEGIN SEQUENCE
      u := hb_DynCall( { "sqlite3_rekey", ::pLib, hb_bitOr( HB_DYN_CTYPE_INT, ::nSysCallConv ),;
                         HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_CHAR_PTR, HB_DYN_CTYPE_INT },;
                         ::pDb, cKey, Len( cKey ) )
   RECOVER
      ErrorBlock( bOldError )
      RETU SQLITE_ERROR
   END SEQUENCE

   ErrorBlock( bOldError )

RETU u

//	=======================================================  //
//  Global helpers
//	=======================================================  //

FUNCTION WDO_Sqlite3CountOpen()

   LOCAL n

   hb_mutexLock( soMutex )
   n := snOpen
   hb_mutexUnlock( soMutex )

RETU n

//	-------------------------------------------------------  //
//  _WdoSqlite3ResolveDll( cOverride, @cSourceOut )
//
//  Precedence chain (highest wins):
//    1. cOverride                                  â€” explicit path from New()
//    2. hb_DirBase() + sqlcipher.dll               â€” DLL next to exe
//    3. env HIX_SQLITE3_DLL                        â€” full path override
//    4. env WDO_LIB_SQLITE3                        â€” full path override (legacy)
//    5. hb_DirBase() + resources/wdo/sqlite3/dll/  â€” repo-relative
//    6. hb_DirBase() + ../../resources/...         â€” tests/wdo/ layout
//    7. hb_DirBase() + ../../../resources/...      â€” tests/wdo/sqlite3/ layout
//    8. "sqlcipher.dll"                            â€” platform default
//
//  "sqlcipher.dll" is the canonical name produced by hix.sqlite3/scripts/
//  02_build_sqlcipher.sh. We never try "sqlite3.dll" â€” mixing the two
//  loaders would corrupt the DB file.
//	-------------------------------------------------------  //

STATIC FUNCTION _WdoSqlite3ResolveDll( cOverride, cSourceOut )

   LOCAL cCanonical, cEnv, cExeDll, cRepoDll

   IF cOverride != NIL .AND. ! Empty( cOverride )
      IF cSourceOut != NIL ; cSourceOut := "override" ; ENDIF
      RETU cOverride
   ENDIF

   IF "Windows" $ OS()
      cCanonical := "sqlcipher.dll"
   ELSEIF "Darwin" $ OS()
      cCanonical := "libsqlcipher.dylib"
   ELSE
      cCanonical := "libsqlcipher.so"
   ENDIF

   cExeDll := hb_DirBase() + cCanonical
   IF hb_FileExists( cExeDll )
      IF cSourceOut != NIL ; cSourceOut := "exedir" ; ENDIF
      RETU cExeDll
   ENDIF

   cEnv := HB_GetEnv( 'HIX_SQLITE3_DLL' )
   IF ! Empty( cEnv )
      IF cSourceOut != NIL ; cSourceOut := "HIX_SQLITE3_DLL" ; ENDIF
      RETU cEnv
   ENDIF

   cEnv := HB_GetEnv( 'WDO_LIB_SQLITE3' )
   IF ! Empty( cEnv )
      IF cSourceOut != NIL ; cSourceOut := "WDO_LIB_SQLITE3" ; ENDIF
      RETU cEnv
   ENDIF

   cRepoDll := hb_DirBase() + "resources/wdo/sqlite3/dll/" + cCanonical
   IF hb_FileExists( cRepoDll )
      IF cSourceOut != NIL ; cSourceOut := "repo" ; ENDIF
      RETU cRepoDll
   ENDIF

   cRepoDll := hb_DirBase() + "../../resources/wdo/sqlite3/dll/" + cCanonical
   IF hb_FileExists( cRepoDll )
      IF cSourceOut != NIL ; cSourceOut := "repo-rel" ; ENDIF
      RETU cRepoDll
   ENDIF

   cRepoDll := hb_DirBase() + "../../../resources/wdo/sqlite3/dll/" + cCanonical
   IF hb_FileExists( cRepoDll )
      IF cSourceOut != NIL ; cSourceOut := "repo-rel3" ; ENDIF
      RETU cRepoDll
   ENDIF

   IF cSourceOut != NIL ; cSourceOut := "default" ; ENDIF

RETU cCanonical

//	-------------------------------------------------------  //

STATIC FUNCTION _WdoSqlite3ReportDllFail( cDll, cReason )

   LOCAL cKey   := "DLL:" + cDll
   LOCAL lFirst := .F.

   hb_mutexLock( s_mtxDown )
   IF ! hb_HHasKey( s_hDownReported, cKey )
      s_hDownReported[ cKey ] := .T.
      lFirst := .T.
   ENDIF
   hb_mutexUnlock( s_mtxDown )

   IF lFirst
      OutStd( "==> Error: Cannot load SQLite3/SQLCipher DLL (" + cDll + ": " + cReason + ")" + hb_eol() )
   ENDIF

RETU NIL

//	-------------------------------------------------------  //
//  Deduped "wrong key / DB corrupt" message. Keyed by file name so a
//  pool init with N workers prints once.

STATIC FUNCTION _WdoSqlite3ReportKeyFail( cFile, nRc, cMsg )

   LOCAL cKey   := "KEY:" + cFile
   LOCAL lFirst := .F.

   hb_mutexLock( s_mtxDown )
   IF ! hb_HHasKey( s_hDownReported, cKey )
      s_hDownReported[ cKey ] := .T.
      lFirst := .T.
   ENDIF
   hb_mutexUnlock( s_mtxDown )

   IF lFirst
      OutStd( "==> Error: SQLCipher key verification failed for " + cFile + ;
              " (rc=" + hb_NToS( nRc ) + ": " + cMsg + ")" + hb_eol() )
   ENDIF

RETU NIL

//	-------------------------------------------------------  //
//  SQL escape for SQLite. Doubles single quotes; backslash is NOT
//  an escape character in SQLite.

FUNCTION wdo_sqlite3_addslashes( c )
RETU StrTran( c, "'", "''" )
