/*-----------------------------------------------------------
  File ......: wdo_sqlite3.prg
  Author.....: Charly 9000
  Created....: 2026-10-05
  Modified...: 2026-10-05
  Version....: 1.0.0
  Description: SQLite3 connection class on top of hbsqlit3.
               Standalone (no pool) singleton registered via
               WDO_RegisterConn so WDO_Get(cKey) returns the
               same handle to every worker thread. SQLite3
               serializes concurrent access internally when
               compiled with THREADSAFE=1 and WAL journaling
               keeps readers and writers off each other's path.
  Usage      : oConn := WDO_Sqlite3():New( "data.db", .T. )
               oStmt := oConn:Query( "SELECT * FROM users" )
  Notes      : Shares WDO_RegisterConn registry with any other
               non-pool driver so WDO_Get stays uniform.
 -----------------------------------------------------------*/

#include 'hix_const.ch'
#include 'hix_logger.ch'
#include 'hbclass.ch'
#include 'hbsqlit3.ch'

#define VERSION_WDO_SQLITE3        '1.0'

STATIC snOpen := 0
STATIC soMutex

INIT PROCEDURE _WDO_Sqlite3Init()
   soMutex := hb_mutexCreate()
RETURN


CLASS WDO_Sqlite3 FROM WDO

   DATA cFile
   DATA pDb                                           // native hbsqlit3 handle
   DATA cType                          INIT 'SQLITE3'
   DATA cJournalMode                   INIT 'WAL'
   DATA cSynchronous                   INIT 'NORMAL'
   DATA lForeignKeys                   INIT .T.
   DATA lCreate                        INIT .T.
   DATA lToUtf8                        INIT .T.

   DATA lConnect                       INIT .F.
   DATA lInTrans                       INIT .F.
   DATA tLastUsed
   DATA cPoolKey                       INIT "-"       // registry key for metrics

   //  Serializes access from multiple worker threads sharing the same
   //  singleton connection. SQLite3's own serialized mode would also work,
   //  but a Harbour-level mutex guards against mid-step() interleaving when
   //  the caller stashes partial results on the WDO_Sqlite3Stmt object.
   DATA hMutex

   METHOD New( cFile, lCreate )        CONSTRUCTOR
   METHOD Open()
   METHOD Close()
   METHOD End()                        INLINE ::Close()
   METHOD Destroy()                    INLINE ::Close()
   METHOD Ping()

   METHOD Exec( cSql )
   METHOD Query( cSql )
   METHOD Prepare( cSql )

   METHOD IsTable( cTable )

   METHOD BeginTrans()
   METHOD Commit()
   METHOD Rollback()
   METHOD InTransaction()              INLINE ::lInTrans
   METHOD Transaction( bCode )

   METHOD Last_Insert_Id()             INLINE iif( ::pDb == NIL, -1, sqlite3_last_insert_rowid( ::pDb ) )
   METHOD Changes()                    INLINE iif( ::pDb == NIL, 0, sqlite3_changes( ::pDb ) )
   METHOD Total_Changes()              INLINE iif( ::pDb == NIL, 0, sqlite3_total_changes( ::pDb ) )
   METHOD Affected_Rows()              INLINE ::Changes()

   METHOD ServerInfo()                 INLINE sqlite3_libversion()
   METHOD ClientInfo()                 INLINE sqlite3_libversion()
   METHOD LibVersion()                 INLINE sqlite3_libversion()

   METHOD Lock()                       INLINE hb_mutexLock( ::hMutex )
   METHOD UnLock()                     INLINE hb_mutexUnlock( ::hMutex )

   METHOD CountOpen()                  INLINE WDO_Sqlite3CountOpen()
   METHOD Version()                    INLINE VERSION_WDO_SQLITE3
   METHOD VersionName()                INLINE 'WDO_SQLITE3 ' + VERSION_WDO_SQLITE3

ENDCLASS

//	-------------------------------------------------------  //

METHOD New( cFile, lCreate ) CLASS WDO_Sqlite3

   ::Super:New()

   hb_default( @cFile,   ':memory:' )
   hb_default( @lCreate, .T. )

   ::cFile   := cFile
   ::lCreate := lCreate
   ::hMutex  := hb_mutexCreate()

RETU SELF

//	-------------------------------------------------------  //

METHOD Open() CLASS WDO_Sqlite3

   LOCAL pDb

   IF ::lConnect
      RETU NIL
   ENDIF

   //  sqlite3_open(cFile, lCreate): the second arg controls creation when
   //  the file doesn't exist. ":memory:" works regardless of lCreate.
   pDb := sqlite3_open( ::cFile, ::lCreate )

   IF pDb == NIL
      ::SetError( _( 'WDO_ERR_SQLITE_OPEN', ::cFile ) )
      RETU NIL
   ENDIF

   ::pDb       := pDb
   ::lConnect  := .T.
   ::tLastUsed := hb_DateTime()

   //  PRAGMAs: WAL journal for concurrent readers, NORMAL fsync policy, FKs.
   //  Each PRAGMA goes through sqlite3_exec; failures log but don't abort.
   IF ! Empty( ::cJournalMode )
      sqlite3_exec( ::pDb, "PRAGMA journal_mode=" + ::cJournalMode )
   ENDIF
   IF ! Empty( ::cSynchronous )
      sqlite3_exec( ::pDb, "PRAGMA synchronous=" + ::cSynchronous )
   ENDIF
   IF ::lForeignKeys
      sqlite3_exec( ::pDb, "PRAGMA foreign_keys=ON" )
   ENDIF

   hb_mutexLock( soMutex )
   snOpen++
   hb_mutexUnlock( soMutex )

   WDO_LoadedRegister( "SQLite3", WDO_Version() )
   WDO_InfoRegister( "RDBMS SQLite3 Server", sqlite3_libversion() )
   WDO_InfoRegister( "RDBMS SQLite3 File",   ::cFile )

RETU NIL

//	-------------------------------------------------------  //

METHOD Close() CLASS WDO_Sqlite3

   LOCAL lWas := ::lConnect

   //  hbsqlit3 has no explicit sqlite3_close() wrapper; the GC destructor
   //  invokes sqlite3_close_v2 when the pointer loses its last reference.
   //  Dropping ::pDb here releases that reference so GC can proceed.
   ::pDb      := NIL
   ::lConnect := .F.
   ::lInTrans := .F.

   IF lWas
      hb_mutexLock( soMutex )
      snOpen--
      hb_mutexUnlock( soMutex )
   ENDIF

RETU NIL

//	-------------------------------------------------------  //

METHOD Ping() CLASS WDO_Sqlite3

   IF ! ::lConnect .OR. ::pDb == NIL
      RETU .F.
   ENDIF

RETU sqlite3_exec( ::pDb, "SELECT 1" ) == SQLITE_OK

//	-------------------------------------------------------  //
//  Exec: fire-and-forget DDL/DML. Returns .T. on success. Lock-protected.
METHOD Exec( cSql ) CLASS WDO_Sqlite3

   LOCAL nRc

   IF ::pDb == NIL
      RETU .F.
   ENDIF

   hb_mutexLock( ::hMutex )
   nRc := sqlite3_exec( ::pDb, cSql )
   hb_mutexUnlock( ::hMutex )

   ::tLastUsed := hb_DateTime()

   IF nRc != SQLITE_OK
      ::SetError( _( 'WDO_ERR_SQLITE_EXEC', ;
                     hb_NToS( sqlite3_errcode( ::pDb ) ) + ": " + sqlite3_errmsg( ::pDb ) ) )
      RETU .F.
   ENDIF

RETU .T.

//	-------------------------------------------------------  //
//  Query: Prepare + Execute. Returns a WDO_Sqlite3Stmt that has
//  already stepped once (so FCount/Fetch_Assoc work immediately).
//  Callers typically iterate oStmt:Fetch_Assoc() until it returns NIL.
METHOD Query( cSql ) CLASS WDO_Sqlite3

   LOCAL oStmt

   IF ::pDb == NIL
      RETU NIL
   ENDIF

   oStmt := ::Prepare( cSql )

   IF oStmt == NIL .OR. oStmt:lError
      RETU oStmt
   ENDIF

   oStmt:Execute()

   //  Auto-finalize on step failure. SQLite keeps the DB in an error
   //  state until the failing stmt is released -- forgetting Free() on
   //  the error branch would leave the next transaction locked.
   IF oStmt:lError
      oStmt:Free()
   ENDIF

   ::tLastUsed := hb_DateTime()

RETU oStmt

//	-------------------------------------------------------  //

METHOD Prepare( cSql ) CLASS WDO_Sqlite3

   IF ::pDb == NIL
      RETU NIL
   ENDIF

RETU WDO_Sqlite3Stmt():New( SELF, cSql )

//	-------------------------------------------------------  //
//  IsTable: cheap sqlite_master lookup. Returns .T./.F.
METHOD IsTable( cTable ) CLASS WDO_Sqlite3

   LOCAL oStmt, lHit

   IF ::pDb == NIL
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

   ::lInTrans := .T.

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

   ::lInTrans := .F.

RETU .T.

//	-------------------------------------------------------  //

METHOD Rollback() CLASS WDO_Sqlite3

   IF ! ::lInTrans
      RETU .F.
   ENDIF

   sqlite3_exec( ::pDb, "ROLLBACK" )
   ::lInTrans := .F.

RETU .T.

//	-------------------------------------------------------  //

METHOD Transaction( bCode ) CLASS WDO_Sqlite3

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

//	=======================================================  //
//  Helpers globales
//	=======================================================  //

FUNCTION WDO_Sqlite3CountOpen()

   LOCAL n

   hb_mutexLock( soMutex )
   n := snOpen
   hb_mutexUnlock( soMutex )

RETU n
