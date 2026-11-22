/*-----------------------------------------------------------
  File ......: test_wdo_pg.prg
  Author.....: Charly 9000
  Created....: 2026-10-18
  Modified...: 2026-10-18
  Version....: 1.0.0
  Description: WDO_PG driver test suite.

                 Phase 1  -- PG API (offline + online)
                 Phase 2  -- Connection pool
                 Phase 2b -- Pool Ex (hash variant)
                 Phase 2c -- HIX_InitPoolsFromConfig (declarative)
                 Phase 2d -- WDO metrics registry (unit tests)
                 Phase 3  -- Stress bench (pool only, metrics OFF)
                 Phase 3b -- Stress bench (metrics ON)

  Usage      : go_pg_msvc64.bat

               Env (all optional):
                 WDO_PG_HOST     (default localhost)
                 WDO_PG_USER     (default postgres)
                 WDO_PG_PWD      (default postgres)
                 WDO_PG_DB       (default postgres)
                 WDO_PG_PORT     (default 5432)
                 BENCH_THREADS   (default 100)
                 BENCH_QUERIES   (default 200)
                 BENCH_POOL      (default 10)
                 BENCH_TIMEOUT_MS(default 15000)

  Notes      : If PostgreSQL is unreachable, phases 1-online, 2, 2b, 2c, 3, 3b
               are skipped. Phase 1 offline + 2d (metrics unit) always run.
               Trace file: logs/test_wdo_pg.dbg
 -----------------------------------------------------------*/

#include "hix_logger.ch"
#include "hbclass.ch"
#include "hbsocket.ch"
#include "wdo_metrics.ch"

//  ---------- Shared counters ----------
STATIC snTotal   := 0
STATIC snPassed  := 0
STATIC snFailed  := 0
STATIC snSkipped := 0

//  ---------- Connection config ----------
STATIC scHost, scUser, scPwd, scDb, snPort
STATIC snBErrCalls := 0

//  ---------- Bench config ----------
STATIC snThreads, snQueries, snPoolSize, snTimeoutMs

//  ---------- Stress state (shared across threads) ----------
STATIC saLatencies
STATIC snErrors
STATIC shMutex


//  =======================================================
//  Reporting helpers
//  =======================================================

STATIC PROCEDURE _Pass( cTest )
   snTotal++ ; snPassed++
   OutStd( "[PASS] " + cTest + hb_eol() )
RETURN

STATIC PROCEDURE _Fail( cTest, cExpected, cGot )
   snTotal++ ; snFailed++
   OutStd( "[FAIL] " + cTest + hb_eol() )
   OutStd( "       Expected: " + cExpected + "  Got: " + cGot + hb_eol() )
RETURN

STATIC PROCEDURE _Skip( cTest, cReason )
   snSkipped++
   OutStd( "[SKIP] " + cTest + "  (" + cReason + ")" + hb_eol() )
RETURN

STATIC PROCEDURE _Check( lCond, cTest, cExpected, cGot )
   IF lCond ; _Pass( cTest ) ; ELSE ; _Fail( cTest, cExpected, cGot ) ; ENDIF
RETURN

STATIC PROCEDURE _Header( cSuite )
   OutStd( hb_eol() + "--- " + cSuite + " ---" + hb_eol() )
   HIX_Dbg( hb_eol() + "========== " + cSuite + " ==========" )
RETURN

STATIC PROCEDURE _PhaseBanner( cLabel )
   OutStd( hb_eol() + "===================================================" + hb_eol() )
   OutStd( "  " + cLabel + hb_eol() )
   OutStd( "===================================================" + hb_eol() )
RETURN

STATIC PROCEDURE _Summary()
   OutStd( hb_eol() + "Tests: " + hb_NToS( snTotal ) + " total | " + ;
           hb_NToS( snPassed ) + " passed | " + hb_NToS( snFailed ) + " failed" + ;
           iif( snSkipped > 0, " | " + hb_NToS( snSkipped ) + " skipped", "" ) + hb_eol() )
RETURN

STATIC PROCEDURE _WaitIfInteractive()
   IF hb_argc() > 0                   ; RETURN ; ENDIF
   IF ! hb_FIsDevice( 0 )             ; RETURN ; ENDIF
   IF ! hb_FIsDevice( 1 )             ; RETURN ; ENDIF
   Inkey( 0 )
RETURN


//  =======================================================
//  Env helpers
//  =======================================================

STATIC FUNCTION _EnvOr( cVar, cDef )
   LOCAL cVal := hb_GetEnv( cVar )
RETURN iif( Empty( cVal ), cDef, cVal )

STATIC PROCEDURE _LoadEnv()
   scHost := _EnvOr( "WDO_PG_HOST", "localhost" )
   scUser := _EnvOr( "WDO_PG_USER", "postgres"  )
   scPwd  := _EnvOr( "WDO_PG_PWD",  "postgres"  )
   scDb   := _EnvOr( "WDO_PG_DB",   "postgres"  )
   snPort := Val( _EnvOr( "WDO_PG_PORT", "5432" ) )

   snThreads   := Val( _EnvOr( "BENCH_THREADS",    "100"   ) )
   snQueries   := Val( _EnvOr( "BENCH_QUERIES",    "200"   ) )
   snPoolSize  := Val( _EnvOr( "BENCH_POOL",       "10"    ) )
   snTimeoutMs := Val( _EnvOr( "BENCH_TIMEOUT_MS", "15000" ) )
RETURN

STATIC FUNCTION _TcpReachable( cHost, nPort, nTimeoutMs )
   LOCAL hSock
   LOCAL lOk
   LOCAL cResolved
   cResolved := iif( Lower( AllTrim( cHost ) ) == "localhost", "127.0.0.1", cHost )
   hSock := hb_socketOpen()
   IF hSock == NIL
      RETU .F.
   ENDIF
   lOk := hb_socketConnect( hSock, { HB_SOCKET_AF_INET, cResolved, nPort }, nTimeoutMs )
   hb_socketClose( hSock )
RETU lOk


//  =======================================================
//  Phase 1 -- Offline API
//  =======================================================

STATIC PROCEDURE _TestOffline()

   LOCAL oConn
   LOCAL cEsc

   _Header( "Phase 1 -- Offline API" )

   //  Ctor without Open -- must not touch libpq nor the network.
   oConn := WDO_PG():New( "nonexistent.host.invalid", "u", "p", "db", 55555, .F. )
   _Check( oConn != NIL, "ctor returns object", "non-NIL", iif( oConn==NIL, "NIL", "obj" ) )
   _Check( ! oConn:lConnect, "ctor lConnect is .F.", ".F.", iif( oConn:lConnect, ".T.", ".F." ) )
   _Check( oConn:cType == "PG", "ctor cType is 'PG'", "PG", oConn:cType )
   _Check( oConn:cDllType == "PostgreSQL", "ctor cDllType is 'PostgreSQL'", ;
           "PostgreSQL", oConn:cDllType )
   _Check( oConn:nPort == 55555, "ctor nPort stored", "55555", hb_NToS( oConn:nPort ) )
   _Check( oConn:cAppName == "hix-worker", "ctor default application_name", ;
           "hix-worker", oConn:cAppName )

   //  Escape helper
   cEsc := wdo_pg_addslashes( "O'Brien" )
   _Check( cEsc == "O''Brien", "wdo_pg_addslashes doubles single-quote", ;
           "O''Brien", cEsc )

   cEsc := wdo_pg_addslashes( "no quotes here" )
   _Check( cEsc == "no quotes here", "wdo_pg_addslashes passthrough", ;
           "no quotes here", cEsc )

   //  Escape method on object (hash form)
   oConn:Escape( ;
      { "name" => "O'Brien", "val" => "safe", "n" => 42 } )
   //  Only strings get touched -- "n" stays numeric. We just verify no crash.
   _Pass( "Escape on hash doesn't crash with mixed types" )

   oConn:Destroy()

RETURN


//  =======================================================
//  Phase 1 -- Online API
//  =======================================================

STATIC PROCEDURE _TestOnline( oConn )

   LOCAL oStmt, aRow, hRow
   LOCAL cName, cPg, cCli
   LOCAL nAff, nId, nMajor, nDot
   LOCAL lOk, lOldShow

   _Header( "Phase 1 -- Online API" )

   //  ----- Open / basic status -----
   _Check( oConn:lConnect, "Open -- lConnect .T.", ".T.", iif( oConn:lConnect, ".T.", ".F." ) )
   _Check( oConn:IsAlive(), "IsAlive after Open", ".T.", iif( oConn:IsAlive(), ".T.", ".F." ) )

   cPg := oConn:ServerInfo()
   _Check( ! Empty( cPg ), "ServerInfo non-empty", "non-empty", cPg )
   OutStd( "       ServerInfo: " + cPg + hb_eol() )

   cCli := oConn:ClientInfo()
   OutStd( "       ClientInfo: " + cCli + hb_eol() )
   OutStd( "       DLL ......: " + oConn:DllPath() + " (" + oConn:DllSource() + ")" + hb_eol() )

   //  Asegura que se carga la libpq nueva (PG 18+, build contra OpenSSL 4),
   //  no una libpq vieja arrastrada por PATH.
   nDot   := At( ".", cCli )
   nMajor := Val( iif( nDot > 0, Left( cCli, nDot - 1 ), cCli ) )
   _Check( nMajor >= 18, "libpq client major >= 18", ">=18", hb_NToS( nMajor ) )

   //  ----- Simple SELECT -----
   oStmt := oConn:Query( "SELECT 1 AS one, 'hello'::text AS greeting" )
   _Check( oStmt != NIL, "Query SELECT returns stmt", "non-NIL", iif( oStmt==NIL, "NIL", "obj" ) )
   _Check( oStmt:Count() == 1, "stmt:Count() == 1", "1", hb_NToS( oStmt:Count() ) )
   _Check( oStmt:FCount() == 2, "stmt:FCount() == 2", "2", hb_NToS( oStmt:FCount() ) )

   aRow := oStmt:Fetch()
   _Check( aRow != NIL, "stmt:Fetch() returns row", "non-NIL", iif( aRow==NIL, "NIL", "row" ) )
   IF aRow != NIL
      _Check( aRow[1] == "1", "Fetch array col 1 == '1'", "1", aRow[1] )
      _Check( aRow[2] == "hello", "Fetch array col 2 == 'hello'", "hello", aRow[2] )
   ENDIF

   //  Cursor exhausted -- second Fetch returns NIL
   _Check( oStmt:Fetch() == NIL, "second Fetch exhausts cursor", "NIL", "value" )
   oStmt:Free()

   //  ----- Fetch_Assoc -----
   oStmt := oConn:Query( "SELECT 42 AS n, 'hi' AS msg" )
   hRow  := oStmt:Fetch_Assoc()
   _Check( hb_HHasKey( hRow, "n" ) .AND. hRow[ "n" ] == "42", ;
           "Fetch_Assoc has key 'n'=='42'", "42", iif( hb_HHasKey(hRow,"n"), hRow["n"], "no-key" ) )
   _Check( hb_HHasKey( hRow, "msg" ) .AND. hRow[ "msg" ] == "hi", ;
           "Fetch_Assoc has key 'msg'=='hi'", "hi", iif( hb_HHasKey(hRow,"msg"), hRow["msg"], "no-key" ) )
   oStmt:Free()

   //  ----- DDL + Insert + Update + Delete -----
   //  Exec returns nAffected (number). DDL yields 0; DML (INSERT) yields rowcount.
   oConn:Exec( "DROP TABLE IF EXISTS hix_test_pg" )
   nAff := oConn:Exec( "CREATE TABLE hix_test_pg ( " + ;
                       "id SERIAL PRIMARY KEY, " + ;
                       "name TEXT NOT NULL, " + ;
                       "n INTEGER )" )
   _Check( nAff >= 0 .AND. Empty( oConn:cError ), ;
           "CREATE TABLE", "nAff>=0 & no error", hb_NToS( nAff ) + "/" + oConn:cError )

   //  Insert via Exec -- expect 1 affected row
   nAff := oConn:Exec( "INSERT INTO hix_test_pg (name, n) VALUES ('alice', 1)" )
   _Check( nAff == 1, "INSERT row 1 affected == 1", "1", hb_NToS( nAff ) )

   //  Insert escaped
   cName := wdo_pg_addslashes( "O'Brien" )
   nAff := oConn:Exec( "INSERT INTO hix_test_pg (name, n) VALUES ('" + cName + "', 2)" )
   _Check( nAff == 1, "INSERT escaped single-quote affected == 1", "1", hb_NToS( nAff ) )

   //  Last_Insert_Id (best-effort via lastval)
   nId := oConn:Last_Insert_Id()
   _Check( nId > 0, "Last_Insert_Id > 0", ">0", hb_NToS( nId ) )

   //  SELECT COUNT
   oStmt := oConn:Query( "SELECT COUNT(*)::int FROM hix_test_pg" )
   aRow := oStmt:Fetch()
   _Check( Val( aRow[1] ) == 2, "COUNT(*) == 2", "2", aRow[1] )
   oStmt:Free()

   //  SELECT with filter -- includes escaped row (bypass htmlencode for the
   //  'name' column so the raw single-quote survives through Fetch)
   oStmt := oConn:Query( "SELECT name, n FROM hix_test_pg WHERE name = 'O''Brien'" )
   aRow := oStmt:Fetch( { "name" } )
   _Check( aRow != NIL .AND. aRow[1] == "O'Brien", ;
           "SELECT finds escaped row", "O'Brien", iif( aRow==NIL, "no row", aRow[1] ) )
   oStmt:Free()

   //  UPDATE returns affected
   oStmt := oConn:Query( "UPDATE hix_test_pg SET n = n * 10 WHERE n > 0" )
   nAff := oStmt:Row_Count()
   _Check( nAff == 2, "UPDATE affected == 2", "2", hb_NToS( nAff ) )
   oStmt:Free()

   //  DELETE
   oStmt := oConn:Query( "DELETE FROM hix_test_pg WHERE name = 'alice'" )
   nAff := oStmt:Row_Count()
   _Check( nAff == 1, "DELETE affected == 1", "1", hb_NToS( nAff ) )
   oStmt:Free()

   //  ----- Transactions -----
   _Check( oConn:BeginTrans(), "BeginTrans() returns .T.", ".T.", "" )
   _Check( oConn:InTransaction(), "InTransaction() .T. after Begin", ".T.", "" )

   oConn:Exec( "INSERT INTO hix_test_pg (name, n) VALUES ('tx-victim', 999)" )

   _Check( oConn:Rollback(), "Rollback() returns .T.", ".T.", "" )
   _Check( ! oConn:InTransaction(), "InTransaction() .F. after Rollback", ".F.", "" )

   //  Verify rollback worked
   oStmt := oConn:Query( "SELECT COUNT(*)::int FROM hix_test_pg WHERE name = 'tx-victim'" )
   aRow := oStmt:Fetch()
   _Check( Val( aRow[1] ) == 0, "Rollback discarded insert", "0", aRow[1] )
   oStmt:Free()

   //  Commit path
   _Check( oConn:BeginTrans(), "BeginTrans() second time", ".T.", "" )
   oConn:Exec( "INSERT INTO hix_test_pg (name, n) VALUES ('tx-keeper', 1234)" )
   _Check( oConn:Commit(), "Commit() returns .T.", ".T.", "" )

   oStmt := oConn:Query( "SELECT COUNT(*)::int FROM hix_test_pg WHERE name = 'tx-keeper'" )
   aRow := oStmt:Fetch()
   _Check( Val( aRow[1] ) == 1, "Commit persisted insert", "1", aRow[1] )
   oStmt:Free()

   //  ----- Transaction block form -----
   lOk := oConn:Transaction( {|o| o:Exec( "INSERT INTO hix_test_pg (name,n) VALUES ('block',1)" ), ;
                                   o:Exec( "INSERT INTO hix_test_pg (name,n) VALUES ('block',2)" ) } )
   _Check( lOk, "Transaction block committed", ".T.", iif( lOk, ".T.", ".F." ) )

   oStmt := oConn:Query( "SELECT COUNT(*)::int FROM hix_test_pg WHERE name = 'block'" )
   aRow := oStmt:Fetch()
   _Check( Val( aRow[1] ) == 2, "Transaction block persisted 2 rows", "2", aRow[1] )
   oStmt:Free()

   //  ----- Fetch types (int + text) -----
   oStmt := oConn:Query( "SELECT 42::int AS v" )
   _Check( oStmt:DbStruct()[1][2] == "N", ;
           "int4 → WDO type 'N'", "N", oStmt:DbStruct()[1][2] )
   oStmt:Free()

   oStmt := oConn:Query( "SELECT 'abc'::text AS v" )
   _Check( oStmt:DbStruct()[1][2] == "C", ;
           "text → WDO type 'C'", "C", oStmt:DbStruct()[1][2] )
   oStmt:Free()

   oStmt := oConn:Query( "SELECT CURRENT_DATE AS v" )
   _Check( oStmt:DbStruct()[1][2] == "D", ;
           "date → WDO type 'D'", "D", oStmt:DbStruct()[1][2] )
   oStmt:Free()

   oStmt := oConn:Query( "SELECT TRUE::bool AS v" )
   _Check( oStmt:DbStruct()[1][2] == "L", ;
           "bool → WDO type 'L'", "L", oStmt:DbStruct()[1][2] )
   oStmt:Free()

   //  ----- GetEncoding -----
   OutStd( "       Encoding ..: " + hb_CStr( oConn:GetEncoding() ) + hb_eol() )

   //  ----- CountOpen / NewGuard -----
   _Check( WDO_PgCountOpen() >= 1, "WDO_PgCountOpen() >= 1", ">=1", hb_NToS( WDO_PgCountOpen() ) )
   _Check( WDO_PgNewGuard() == .T., "WDO_PgNewGuard() default .T.", ".T.", "" )

   //  Cleanup table
   oConn:Exec( "DROP TABLE hix_test_pg" )

   //  Error handling -- invalid SQL. lShowError is .T. by default (triggers
   //  Break on error, propagates to default handler). Disable it while we
   //  deliberately provoke errors so SetError only populates ::cError.
   lOldShow := WDO_PG():lShowError
   WDO_PG():lShowError := .F.

   oStmt := oConn:Query( "SELECT * FROM nope_this_table_does_not_exist_xyz" )
   _Check( oStmt:lError, "stmt:lError after bad SQL", ".T.", "" )
   _Check( ! Empty( oConn:cError ), "cError populated after bad SQL", "non-empty", oConn:cError )
   IF oStmt != NIL ; oStmt:Free() ; ENDIF

   WDO_PG():lShowError := lOldShow

   //  Clear error state
   oConn:cError := ""

   //  Close
   oConn:Close()
   _Check( ! oConn:lConnect, "Close() clears lConnect", ".F.", "" )

RETURN


//  =======================================================
//  Phase 2 -- Pool
//  =======================================================

STATIC PROCEDURE _TestPool()

   LOCAL hStats, oConn1, oConn2, oConn3, lOk
   LOCAL oStmt, aRow

   _Header( "Phase 2 -- Pool" )

   //  Init pool size 2 (hash variant so we can pass sslmode=disable)
   lOk := WDO_InitPoolPgEx( "PG", { ;
      "host"       => scHost, "user" => scUser, "pwd" => scPwd, ;
      "db"         => scDb,   "port" => snPort, ;
      "pool_size"  => 2,      "timeout_ms" => 3000, "ping" => .T., ;
      "sslmode"    => "disable" } )
   _Check( lOk, "WDO_InitPoolPg returns .T.", ".T.", iif( lOk, ".T.", ".F." ) )

   hStats := WDO_PoolStats( "PG" )
   _Check( hStats != NIL, "WDO_PoolStats('PG') non-NIL", "non-NIL", "" )
   IF hStats != NIL
      _Check( hStats[ "size" ] == 2, "pool size == 2", "2", hb_NToS( hStats[ "size" ] ) )
      _Check( hStats[ "busy" ] == 0, "initial busy == 0", "0", hb_NToS( hStats[ "busy" ] ) )
      _Check( hStats[ "free" ] == 2, "initial free == 2", "2", hb_NToS( hStats[ "free" ] ) )
   ENDIF

   //  Acquire
   oConn1 := WDO_Get( "PG" )
   _Check( oConn1 != NIL, "WDO_Get('PG') #1 returns conn", "non-NIL", "" )
   _Check( oConn1:lConnect, "acquired conn is live", ".T.", "" )

   oConn2 := WDO_Get( "PG" )
   _Check( oConn2 != NIL, "WDO_Get('PG') #2 returns conn", "non-NIL", "" )

   hStats := WDO_PoolStats( "PG" )
   _Check( hStats[ "busy" ] == 2, "busy == 2 after 2 acquires", "2", hb_NToS( hStats[ "busy" ] ) )
   _Check( hStats[ "free" ] == 0, "free == 0 after 2 acquires", "0", hb_NToS( hStats[ "free" ] ) )

   //  Exhaustion -- 3rd acquire times out
   oConn3 := WDO_Get( "PG" )
   _Check( oConn3 == NIL, "3rd WDO_Get times out → NIL", "NIL", iif( oConn3==NIL, "NIL", "obj" ) )

   //  Release all borrowed by this thread (both conns)
   WDO_ReleaseAllThread()
   hStats := WDO_PoolStats( "PG" )
   _Check( hStats[ "busy" ] == 0, "busy == 0 after ReleaseAllThread", "0", hb_NToS( hStats[ "busy" ] ) )

   //  Now re-acquire -- gets a released slot (same obj instance)
   oConn3 := WDO_Get( "PG" )
   _Check( oConn3 != NIL, "re-acquire after release", "non-NIL", "" )

   //  Query from pooled conn
   oStmt := oConn3:Query( "SELECT 2+2 AS v" )
   aRow  := oStmt:Fetch()
   _Check( aRow[1] == "4", "pooled conn: SELECT 2+2 == 4", "4", aRow[1] )
   oStmt:Free()

   //  Thread-local release-all
   WDO_ReleaseAllThread()
   hStats := WDO_PoolStats( "PG" )
   _Check( hStats[ "busy" ] == 0, "ReleaseAllThread leaves busy == 0", "0", hb_NToS( hStats[ "busy" ] ) )

   //  Unregister
   WDO_EndPoolPg()
   hStats := WDO_PoolStats( "PG" )
   _Check( hStats == NIL, "pool unregistered → stats NIL", "NIL", iif( hStats==NIL, "NIL", "obj" ) )

   //  WDO_Get after unregister
   oConn1 := WDO_Get( "PG" )
   _Check( oConn1 == NIL, "WDO_Get('PG') after End → NIL", "NIL", iif( oConn1==NIL, "NIL", "obj" ) )

RETURN


//  =======================================================
//  Pool Ex -- hash variant with extras
//  =======================================================

STATIC PROCEDURE _TestPoolEx()

   LOCAL hParams, lOk, oConn, oStmt, aRow

   _Header( "Phase 2b -- Pool Ex (hash variant)" )

   hParams := { ;
      "host"              => scHost, ;
      "user"              => scUser, ;
      "pwd"               => scPwd,  ;
      "db"                => scDb,   ;
      "port"              => snPort, ;
      "pool_size"         => 2,      ;
      "timeout_ms"        => 3000,   ;
      "ping"              => .T.,    ;
      "application_name"  => "hix-test-pg", ;
      "client_encoding"   => "UTF8", ;
      "sslmode"           => "disable" ;
   }

   lOk := WDO_InitPoolPgEx( "PG_EX", hParams )
   _Check( lOk, "WDO_InitPoolPgEx with hash", ".T.", iif( lOk, ".T.", ".F." ) )

   oConn := WDO_Get( "PG_EX" )
   _Check( oConn != NIL, "WDO_Get('PG_EX') returns conn", "non-NIL", "" )

   IF oConn != NIL
      _Check( oConn:cAppName == "hix-test-pg", "custom application_name honored", ;
              "hix-test-pg", oConn:cAppName )

      oStmt := oConn:Query( "SELECT current_setting('application_name') AS app" )
      aRow := oStmt:Fetch()
      _Check( aRow[1] == "hix-test-pg", "pg_stat_activity sees app name", ;
              "hix-test-pg", aRow[1] )
      oStmt:Free()
   ENDIF

   WDO_ReleaseAllThread()
   WDO_UnregisterPool( "PG_EX" )

RETURN


//  =======================================================
//  Phase 2c -- HIX_InitPoolsFromConfig (declarative bootstrap)
//  =======================================================

//  Handler resolved by name from JSON "berror" -- must be public
//  (not STATIC) because HIX_InitPoolsFromConfig uses macro eval &()
//  to build the codeblock and needs the symbol in the global table.
PROCEDURE CfgBErrorProbe( oErr, oConn )
   HB_SYMBOL_UNUSED( oErr )
   HB_SYMBOL_UNUSED( oConn )
   snBErrCalls++
RETURN


PROCEDURE TestConfigJson()

   LOCAL hResult, oConn1, oConn2
   LOCAL cValidDll
   LOCAL hBase

   _Header( "ConfigJson: HIX_InitPoolsFromConfig" )

   //  Shared base for every valid 'pg' entry below. sslmode=disable because
   //  the bundled libpq.dll is compiled against OpenSSL 4 but the default
   //  (sslmode=prefer) would still try SSL negotiation on servers accepting
   //  it, which hangs in test contexts without certs.
   hBase := { ;
      "driver"     => "pg",    ;
      "host"       => scHost,  ;
      "user"       => scUser,  ;
      "pwd"        => scPwd,   ;
      "db"         => scDb,    ;
      "port"       => snPort,  ;
      "pool_size"  => 2,       ;
      "timeout_ms" => 2000,    ;
      "ping"       => .F.,     ;
      "sslmode"    => "disable" }

   //  1. No 'databases' section (or empty) -> empty result, no crash
   HIX_ConfigAppSet( "databases", { => } )
   hResult := HIX_InitPoolsFromConfig()
   _Check( HB_ISHASH( hResult ) .AND. Empty( hResult ), ;
           "empty 'databases' returns empty hash", ;
           "{ =>}", "len=" + hb_NToS( Len( hResult ) ) )

   //  2. Single entry: pool starts, WDO_Get returns a live connection
   HIX_ConfigAppSet( "databases", { "pg" => hb_HClone( hBase ) } )

   hResult := HIX_InitPoolsFromConfig()
   _Check( hb_HGetDef( hResult, "pg", .F. ), ;
           "single 'pg' entry starts OK", ".T.", ;
           iif( hb_HGetDef( hResult, "pg", .F. ), ".T.", ".F." ) )

   oConn1 := WDO_Get( "pg" )
   _Check( oConn1 != NIL .AND. oConn1:lConnect, ;
           "WDO_Get(<json key>) returns a live conn", "live", ;
           iif( oConn1 == NIL, "nil", "not live" ) )
   IF oConn1 != NIL ; oConn1:Close() ; ENDIF

   HIX_EndPoolsFromConfig()

   //  3. Two entries with the same driver register as distinct pools
   HIX_ConfigAppSet( "databases", { ;
      "pg_a" => hb_HMerge( hb_HClone( hBase ), { "pool_size" => 1 } ), ;
      "pg_b" => hb_HMerge( hb_HClone( hBase ), { "pool_size" => 1 } ) } )
   hResult := HIX_InitPoolsFromConfig()
   _Check( hb_HGetDef( hResult, "pg_a", .F. ) .AND. hb_HGetDef( hResult, "pg_b", .F. ), ;
           "two same-driver entries both start", "both .T.", ;
           iif( hb_HGetDef( hResult, "pg_a", .F. ), "a=T", "a=F" ) + " " + ;
           iif( hb_HGetDef( hResult, "pg_b", .F. ), "b=T", "b=F" ) )

   oConn1 := WDO_Get( "pg_a" )
   oConn2 := WDO_Get( "pg_b" )
   _Check( oConn1 != NIL .AND. oConn2 != NIL .AND. ! ( oConn1 == oConn2 ), ;
           "each pool yields its own conn", "distinct", "same or nil" )
   IF oConn1 != NIL ; oConn1:Close() ; ENDIF
   IF oConn2 != NIL ; oConn2:Close() ; ENDIF

   HIX_EndPoolsFromConfig()

   //  4. 'dll' with valid path -> pool opens normally. tests/wdo/pg/ ships
   //  a local libpq.dll next to the exe for the stress phase; reuse it here.
   cValidDll := hb_DirBase() + "libpq.dll"
   HIX_ConfigAppSet( "databases", { ;
      "pg" => hb_HMerge( hb_HClone( hBase ), ;
              { "pool_size" => 1, "dll" => cValidDll } ) } )
   hResult := HIX_InitPoolsFromConfig()
   _Check( hb_HGetDef( hResult, "pg", .F. ), ;
           "'dll' with valid path opens", ".T.", ;
           iif( hb_HGetDef( hResult, "pg", .F. ), ".T.", ".F." ) )

   oConn1 := WDO_Get( "pg" )
   _Check( oConn1 != NIL .AND. oConn1:DllSource() == "override", ;
           "DllSource == 'override' when 'dll' set from JSON", ;
           "override", iif( oConn1 == NIL, "nil", oConn1:DllSource() ) )
   IF oConn1 != NIL ; oConn1:Close() ; ENDIF

   HIX_EndPoolsFromConfig()

   //  5. 'dll' with nonexistent path -> pool init fails cleanly
   HIX_ConfigAppSet( "databases", { ;
      "pg_bad" => hb_HMerge( hb_HClone( hBase ), ;
                  { "pool_size" => 1, "dll" => "c:/does/not/exist/libpq.dll" } ) } )
   hResult := HIX_InitPoolsFromConfig( .F. )   //  .F. = no abort, expect clean failure
   _Check( ! hb_HGetDef( hResult, "pg_bad", .T. ), ;
           "'dll' with bad path fails cleanly (.F.)", ".F.", ;
           iif( hb_HGetDef( hResult, "pg_bad", .T. ), ".T.", ".F." ) )

   HIX_EndPoolsFromConfig()

   //  6. 'berror' referencing a public function -> injected as codeblock
   HIX_ConfigAppSet( "databases", { ;
      "pg" => hb_HMerge( hb_HClone( hBase ), ;
              { "pool_size" => 1, "berror" => "CfgBErrorProbe" } ) } )
   HIX_InitPoolsFromConfig()
   oConn1 := WDO_Get( "pg" )
   _Check( oConn1 != NIL .AND. ValType( oConn1:bError ) == "B", ;
           "known 'berror' injects codeblock on pooled conn", "B", ;
           iif( oConn1 == NIL, "nil", ValType( oConn1:bError ) ) )
   IF oConn1 != NIL ; oConn1:Close() ; ENDIF
   HIX_EndPoolsFromConfig()

   //  7. 'berror' referencing missing symbol -> WARN, pool starts without handler
   HIX_ConfigAppSet( "databases", { ;
      "pg" => hb_HMerge( hb_HClone( hBase ), ;
              { "pool_size" => 1, ;
                "berror"    => "DoesNotExist_" + hb_NToS( Int( Seconds() ) ) } ) } )
   hResult := HIX_InitPoolsFromConfig()
   _Check( hb_HGetDef( hResult, "pg", .F. ), ;
           "unknown 'berror' does not abort init", ".T.", ;
           iif( hb_HGetDef( hResult, "pg", .F. ), ".T.", ".F." ) )
   oConn1 := WDO_Get( "pg" )
   _Check( oConn1 != NIL .AND. oConn1:bError == NIL, ;
           "unknown 'berror' -> bError stays NIL", "NIL", ;
           iif( oConn1 == NIL, "nil-conn", iif( oConn1:bError == NIL, "NIL", "B" ) ) )
   IF oConn1 != NIL ; oConn1:Close() ; ENDIF
   HIX_EndPoolsFromConfig()

   //  8. WDO_InitPoolPgEx direct call (no JSON) equivalent to declarative path
   WDO_InitPoolPgEx( "pg_direct", { ;
      "host"      => scHost, "user" => scUser, "pwd" => scPwd, ;
      "db"        => scDb,   "port" => snPort, "pool_size" => 1, ;
      "sslmode"   => "disable", "ping" => .F. } )
   oConn1 := WDO_Get( "pg_direct" )
   _Check( oConn1 != NIL .AND. oConn1:lConnect, ;
           "WDO_InitPoolPgEx direct call works standalone", "live", ;
           iif( oConn1 == NIL, "nil", "not-live" ) )
   IF oConn1 != NIL ; oConn1:Close() ; ENDIF
   WDO_UnregisterPool( "pg_direct" )

   //  cleanup: leave "databases" untouched for downstream phases
   HIX_ConfigAppSet( "databases", { => } )

RETURN


//  =======================================================
//  Phase 2d -- WDO metrics registry (unit tests, no PG)
//  Each Test_Metric_* isolates state via Init/Close pairs so
//  the phase can run standalone. Assertions use the shared
//  _Check/_Pass/_Fail helpers, so they add to the global tally.
//  =======================================================

//  1. Init / Close / IsActive
STATIC PROCEDURE Test_Metric_InitClose()

   _Header( "Metric 1. Init / Close / IsActive" )

   _Check( ! WDO_MetricsIsActive(), "IsActive false before init", ".F.", "unexpected" )

   WDO_MetricsInit( 5 )
   _Check( WDO_MetricsIsActive(), "IsActive true after init", ".T.", "unexpected" )

   WDO_MetricsClose()
   _Check( ! WDO_MetricsIsActive(), "IsActive false after close", ".F.", "unexpected" )

RETURN


//  2. Increment / Set / Dec
STATIC PROCEDURE Test_Metric_IncrementSetDec()

   _Header( "Metric 2. Increment / Set / Dec" )

   WDO_MetricsInit( 5 )

   WDO_Metric( WDOM_QUERIES_TOTAL )
   WDO_Metric( WDOM_QUERIES_TOTAL )
   WDO_Metric( WDOM_QUERIES_TOTAL, 3 )
   _Check( WDO_MetricGet( WDOM_QUERIES_TOTAL ) == 5, "Inc +1 +1 +3 = 5", "5", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_TOTAL ) ) )

   WDO_MetricSet( WDOM_ACTIVE_CONN, 7 )
   _Check( WDO_MetricGet( WDOM_ACTIVE_CONN ) == 7, "Set active_conn=7", "7", ;
      hb_NToS( WDO_MetricGet( WDOM_ACTIVE_CONN ) ) )

   WDO_MetricDec( WDOM_ACTIVE_CONN )
   _Check( WDO_MetricGet( WDOM_ACTIVE_CONN ) == 6, "Dec active_conn -> 6", "6", ;
      hb_NToS( WDO_MetricGet( WDOM_ACTIVE_CONN ) ) )

   WDO_MetricSet( WDOM_ACTIVE_CONN, 0 )
   WDO_MetricDec( WDOM_ACTIVE_CONN )
   _Check( WDO_MetricGet( WDOM_ACTIVE_CONN ) == 0, "Dec floors at 0", "0", ;
      hb_NToS( WDO_MetricGet( WDOM_ACTIVE_CONN ) ) )

   WDO_MetricsClose()

RETURN


//  3. Reset
STATIC PROCEDURE Test_Metric_ResetCounters()

   _Header( "Metric 3. Reset" )

   WDO_MetricsInit( 5 )

   WDO_MetricSet( WDOM_QUERIES_TOTAL,  100 )
   WDO_MetricSet( WDOM_QUERIES_ERRORS, 3   )
   WDO_MetricQuery( "pg", "SELECT 1", 12, "test.prg:1" )

   WDO_MetricsReset()

   _Check( WDO_MetricGet( WDOM_QUERIES_TOTAL  ) == 0, "queries_total reset",  "0", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_TOTAL ) ) )
   _Check( WDO_MetricGet( WDOM_QUERIES_ERRORS ) == 0, "queries_errors reset", "0", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_ERRORS ) ) )

   WDO_MetricsClose()

RETURN


//  4. SQL classification
STATIC PROCEDURE Test_Metric_SqlClassification()

   _Header( "Metric 4. SQL classification" )

   WDO_MetricsInit( 5 )

   WDO_MetricQuery( "pg", "SELECT * FROM t",         5, "-" )
   WDO_MetricQuery( "pg", "  select * from t",       5, "-" )
   WDO_MetricQuery( "pg", "INSERT INTO t VALUES (1)",5, "-" )
   WDO_MetricQuery( "pg", "UPDATE t SET x=1",        5, "-" )
   WDO_MetricQuery( "pg", "DELETE FROM t",           5, "-" )
   WDO_MetricQuery( "pg", "PREPARE stmt FROM ?",     5, "-" )
   WDO_MetricQuery( "pg", "EXECUTE stmt",            5, "-" )
   WDO_MetricQuery( "pg", "SHOW TABLES",             5, "-" )
   WDO_MetricQuery( "pg", "/* c */ SELECT 1",        5, "-" )
   WDO_MetricQuery( "pg", "-- c" + hb_eol() + "SELECT 2", 5, "-" )

   _Check( WDO_MetricGet( WDOM_QUERIES_SELECT  ) == 4, "select classified x4", "4", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_SELECT ) ) )
   _Check( WDO_MetricGet( WDOM_QUERIES_INSERT  ) == 1, "insert classified",    "1", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_INSERT ) ) )
   _Check( WDO_MetricGet( WDOM_QUERIES_UPDATE  ) == 1, "update classified",    "1", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_UPDATE ) ) )
   _Check( WDO_MetricGet( WDOM_QUERIES_DELETE  ) == 1, "delete classified",    "1", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_DELETE ) ) )
   _Check( WDO_MetricGet( WDOM_QUERIES_PREPARE ) == 1, "prepare classified",   "1", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_PREPARE ) ) )
   _Check( WDO_MetricGet( WDOM_QUERIES_EXECUTE ) == 1, "execute classified",   "1", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_EXECUTE ) ) )
   _Check( WDO_MetricGet( WDOM_QUERIES_OTHER   ) == 1, "SHOW -> other",        "1", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_OTHER ) ) )
   _Check( WDO_MetricGet( WDOM_QUERIES_TOTAL   ) == 10,"total = 10",           "10",;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_TOTAL ) ) )

   WDO_MetricsClose()

RETURN


//  5. Timing running average
STATIC PROCEDURE Test_Metric_TimingRunningAvg()

   _Header( "Metric 5. Timing running avg" )

   WDO_MetricsInit( 5 )

   WDO_MetricQuery( "pg", "SELECT 1", 10, "-" )
   WDO_MetricQuery( "pg", "SELECT 2", 20, "-" )
   WDO_MetricQuery( "pg", "SELECT 3", 30, "-" )

   _Check( WDO_MetricGet( WDOM_QUERY_MS_COUNT ) == 3, "count=3", "3", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERY_MS_COUNT ) ) )
   _Check( WDO_MetricGet( WDOM_QUERY_MS_MAX ) == 30, "max=30", "30", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERY_MS_MAX ) ) )
   _Check( WDO_MetricGet( WDOM_QUERY_MS_AVG ) == 20, "avg=20", "20", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERY_MS_AVG ) ) )

   WDO_MetricsClose()

RETURN


//  6. Top-N cap
STATIC PROCEDURE Test_Metric_TopNCap()

   LOCAL i
   LOCAL cJson, hJson, aTop

   _Header( "Metric 6. Top-N cap" )

   WDO_MetricsInit( 3 )   //  cap at 3

   FOR i := 1 TO 10
      WDO_MetricQuery( "pg", "SELECT " + hb_NToS( i ), i * 10, "src.prg:" + hb_NToS( i ) )
   NEXT

   cJson := WDO_MetricsJson()
   hJson := hb_JsonDecode( cJson )
   aTop  := hJson[ "slowest" ]

   _Check( Len( aTop ) == 3, "Top-N capped at 3", "3", hb_NToS( Len( aTop ) ) )
   _Check( aTop[ 1 ][ "ms" ] == 100, "Slowest = 100ms", "100", ;
      hb_NToS( aTop[ 1 ][ "ms" ] ) )
   _Check( aTop[ 3 ][ "ms" ] == 80, "Third = 80ms", "80", ;
      hb_NToS( aTop[ 3 ][ "ms" ] ) )

   WDO_MetricsClose()

RETURN


//  7. Per-pool counter
STATIC PROCEDURE Test_Metric_QueryPerPool()

   _Header( "Metric 7. Per-pool counter" )

   WDO_MetricsInit( 5 )

   WDO_MetricQuery( "pg",        "SELECT 1", 5, "-" )
   WDO_MetricQuery( "pg",        "SELECT 2", 5, "-" )
   WDO_MetricQuery( "analytics", "SELECT 3", 5, "-" )

   _Check( WDO_MetricGet( "queries_by_pool_pg"        ) == 2, "pg=2",        "2", ;
      hb_NToS( WDO_MetricGet( "queries_by_pool_pg" ) ) )
   _Check( WDO_MetricGet( "queries_by_pool_analytics" ) == 1, "analytics=1", "1", ;
      hb_NToS( WDO_MetricGet( "queries_by_pool_analytics" ) ) )

   WDO_MetricsClose()

RETURN


//  8. JSON valid
STATIC PROCEDURE Test_Metric_JsonValid()

   LOCAL cJson, hJson

   _Header( "Metric 8. JSON valid" )

   WDO_MetricsInit( 5 )
   WDO_MetricQuery( "pg", "SELECT 1", 42, "src.prg:10" )

   cJson := WDO_MetricsJson()
   hJson := hb_JsonDecode( cJson )

   _Check( HB_ISHASH( hJson ), "hb_JsonDecode returns hash", "hash", ValType( hJson ) )
   _Check( hb_HHasKey( hJson, WDOM_QUERIES_TOTAL ), ;
      "hash has queries_total", "T", "F" )
   _Check( hJson[ WDOM_QUERIES_TOTAL ] == 1, "queries_total=1 in json", "1", ;
      hb_NToS( hJson[ WDOM_QUERIES_TOTAL ] ) )
   _Check( hb_HHasKey( hJson, "uptime_sec" ), "hash has uptime_sec", "T", "F" )

   WDO_MetricsClose()

RETURN


//  9. Acquire timing
STATIC PROCEDURE Test_Metric_AcquireTiming()

   _Header( "Metric 9. Acquire timing" )

   WDO_MetricsInit( 5 )

   WDO_MetricAcquire( 5  )
   WDO_MetricAcquire( 15 )
   WDO_MetricAcquire( 25 )

   _Check( WDO_MetricGet( WDOM_ACQUIRE_MS_COUNT ) == 3,  "acquire count=3",  "3",  ;
      hb_NToS( WDO_MetricGet( WDOM_ACQUIRE_MS_COUNT ) ) )
   _Check( WDO_MetricGet( WDOM_ACQUIRE_MS_MAX   ) == 25, "acquire max=25",   "25", ;
      hb_NToS( WDO_MetricGet( WDOM_ACQUIRE_MS_MAX ) ) )
   _Check( WDO_MetricGet( WDOM_ACQUIRE_MS_AVG   ) == 15, "acquire avg=15",   "15", ;
      hb_NToS( WDO_MetricGet( WDOM_ACQUIRE_MS_AVG ) ) )

   WDO_MetricsClose()

RETURN


//  10. Fast-path zero-cost when disabled
STATIC PROCEDURE Test_Metric_FastPathZeroCost()

   _Header( "Metric 10. Fast-path opt-out" )

   WDO_MetricsClose()   //  ensure disabled
   _Check( ! WDO_MetricsIsActive(), "disabled", ".F.", "unexpected" )

   WDO_Metric( WDOM_QUERIES_TOTAL, 999 )
   WDO_MetricSet( WDOM_ACTIVE_CONN, 42 )
   WDO_MetricDec( WDOM_ACTIVE_CONN )
   WDO_MetricQuery( "pg", "SELECT 1", 12, "-" )
   WDO_MetricAcquire( 10 )
   WDO_MetricsReset()

   _Check( WDO_MetricGet( WDOM_QUERIES_TOTAL ) == 0, "Get=0 when disabled", "0", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_TOTAL ) ) )
   _Check( WDO_MetricsJson() == "{}", "Json='{}' when disabled", "{}", WDO_MetricsJson() )

RETURN


//  11. Multi-thread increment
STATIC PROCEDURE Test_Metric_MultiThreadIncrement()

   LOCAL aThreads := {}
   LOCAL i

   _Header( "Metric 11. Multi-thread increment" )

   WDO_MetricsInit( 5 )

   FOR i := 1 TO 10
      AAdd( aThreads, hb_threadStart( @_MetricThreadBumper() ) )
   NEXT

   AEval( aThreads, {| h | hb_threadJoin( h ) } )

   _Check( WDO_MetricGet( WDOM_QUERIES_TOTAL ) == 1000, ;
      "10 threads x 100 increments = 1000", "1000", ;
      hb_NToS( WDO_MetricGet( WDOM_QUERIES_TOTAL ) ) )

   WDO_MetricsClose()

RETURN

STATIC PROCEDURE _MetricThreadBumper()
   LOCAL j
   FOR j := 1 TO 100
      WDO_Metric( WDOM_QUERIES_TOTAL )
   NEXT
RETURN


//  12. HIX_MetricsJson injection
STATIC PROCEDURE Test_Metric_HixMetricsJsonInjection()

   LOCAL cJson, hJson

   _Header( "Metric 12. HIX_MetricsJson embeds wdo block" )

   HIX_MetricsInit()
   WDO_MetricsInit( 5 )

   WDO_MetricQuery( "pg", "SELECT 1", 7, "src.prg:1" )

   cJson := HIX_MetricsJson()
   hJson := hb_JsonDecode( cJson )

   _Check( HB_ISHASH( hJson ), "HIX_MetricsJson decodes", "hash", ValType( hJson ) )
   _Check( hb_HHasKey( hJson, "wdo" ), "top-level 'wdo' key present", "T", "F" )
   _Check( HB_ISHASH( hJson[ "wdo" ] ), "'wdo' value is hash", "hash", ;
      ValType( hJson[ "wdo" ] ) )
   _Check( hJson[ "wdo" ][ WDOM_QUERIES_TOTAL ] == 1, ;
      "wdo.queries_total = 1", "1", ;
      hb_NToS( hJson[ "wdo" ][ WDOM_QUERIES_TOTAL ] ) )

   WDO_MetricsClose()

   //  Con metricas cerradas, HIX_MetricsJson no debe llevar 'wdo'
   cJson := HIX_MetricsJson()
   hJson := hb_JsonDecode( cJson )
   _Check( ! hb_HHasKey( hJson, "wdo" ), ;
      "no 'wdo' key when metrics disabled", "F", "T" )

   HIX_MetricsClose()

RETURN


//  =======================================================
//  Phase 2bp -- Prepared statements (Alt A libpq native)
//  =======================================================

PROCEDURE TestPreparePg()

   LOCAL oConn, oStmt, aRows, hRow, i, nCountBefore
   LOCAL cTbl := "hix_test_prep_" + hb_NToS( Int( Seconds() ) )
   LOCAL lOldShow

   _Header( "Prepared: PQprepare/PQexecPrepared (Alt A)" )

   oConn := WDO_PG():New( scHost, scUser, scPwd, scDb, snPort, .F. )
   oConn:cSslMode := "disable"
   oConn:Open()
   IF ! oConn:lConnect
      _Skip( "Prepare/Bind/Execute", "no hay PostgreSQL" )
      RETU
   ENDIF

   lOldShow := WDO_PG():lShowError
   WDO_PG():lShowError := .F.

   oConn:Exec( "DROP TABLE IF EXISTS " + cTbl )
   oConn:Exec( "CREATE TABLE " + cTbl + ;
               " ( id SERIAL PRIMARY KEY, name TEXT, age INT, note TEXT )" )

   //  1. Prepare returns Stmt with lPrepared=.T. and nParamCount correct
   oStmt := oConn:Prepare( "SELECT * FROM " + cTbl + " WHERE age > ?" )
   _Check( oStmt != NIL .AND. oStmt:lPrepared, ;
           "Prepare devuelve Stmt con lPrepared=.T.", ".T.", ;
           iif( oStmt == NIL, "NIL", iif( oStmt:lPrepared, ".T.", ".F." ) ) )
   _Check( oStmt:nParamCount == 1, ;
           "nParamCount = 1 con un unico ?", "1", hb_NToS( oStmt:nParamCount ) )
   oStmt:Free()

   //  2. Prepare de SQL invalido -> oStmt:lError=.T.
   oStmt := oConn:Prepare( "SELECT * FROM zzz_does_not_exist WHERE id = $1" )
   _Check( oStmt != NIL .AND. oStmt:lError, ;
           "Prepare SQL invalido marca lError", ".T.", ;
           iif( oStmt == NIL, "NIL", iif( oStmt:lError, ".T.", ".F." ) ) )
   IF oStmt != NIL ; oStmt:Free() ; ENDIF

   //  3. BindParam con indice fuera de rango -> lError
   oStmt := oConn:Prepare( "SELECT * FROM " + cTbl + " WHERE age > $1::int" )
   oStmt:BindParam( 5, 10, "i" )
   _Check( oStmt:lError, "BindParam(indice fuera de rango) marca lError", ;
           ".T.", iif( oStmt:lError, ".T.", ".F." ) )
   oStmt:Free()

   //  Seed data para el resto de asserts
   oConn:Exec( "INSERT INTO " + cTbl + " (name, age, note) VALUES " + ;
               "('alice', 20, 'a'),('bob', 30, 'b'),('carol', 40, 'c')" )

   //  4. SELECT con 1 parametro entero -- filtra age > 25
   oStmt := oConn:Prepare( "SELECT id, name, age FROM " + cTbl + " WHERE age > $1::int ORDER BY id" )
   oStmt:BindParam( 1, 25, "i" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 2, "SELECT WHERE age > 25 devuelve 2 filas", "2", hb_NToS( Len( aRows ) ) )
   oStmt:Free()

   //  5. Parametro string con comilla simple (SQL-injection safe)
   oConn:Exec( "INSERT INTO " + cTbl + " (name, age, note) VALUES ('O''Brien', 50, 'irish')" )
   oStmt := oConn:Prepare( "SELECT id FROM " + cTbl + " WHERE name = $1" )
   oStmt:BindParam( 1, "O'Brien", "s" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 1, ;
           "SELECT WHERE name=$1 con comilla simple", "1", hb_NToS( Len( aRows ) ) )
   oStmt:Free()

   //  6. INSERT parametros mixtos + Last_Insert_Id (PG: lastval())
   oStmt := oConn:Prepare( "INSERT INTO " + cTbl + " (name, age, note) VALUES ($1, $2::int, $3)" )
   oStmt:BindParam( 1, "diana",  "s" )
   oStmt:BindParam( 2, 22,       "i" )
   oStmt:BindParam( 3, "bought", "s" )
   oStmt:Execute()
   _Check( oStmt:Row_Count() == 1, "INSERT prepared Row_Count=1", "1", hb_NToS( oStmt:Row_Count() ) )
   _Check( oConn:Last_Insert_Id() > 0, "Last_Insert_Id > 0 tras Execute", "> 0", ;
           hb_NToS( oConn:Last_Insert_Id() ) )
   oStmt:Free()

   //  7. INSERT masivo re-ejecutando el mismo Prepare (10 iteraciones)
   oStmt := oConn:Prepare( "INSERT INTO " + cTbl + " (name, age, note) VALUES ($1, $2::int, $3)" )
   nCountBefore := Val( _ScalarQueryPg( oConn, "SELECT COUNT(*) FROM " + cTbl ) )
   FOR i := 1 TO 10
      oStmt:BindParam( 1, "bulk_" + hb_NToS( i ), "s" )
      oStmt:BindParam( 2, 60 + i,                 "i" )
      oStmt:BindParam( 3, "run",                  "s" )
      oStmt:Execute()
   NEXT
   _Check( Val( _ScalarQueryPg( oConn, "SELECT COUNT(*) FROM " + cTbl ) ) - nCountBefore == 10, ;
           "10 re-Execute insertan 10 filas", "10", ;
           hb_NToS( Val( _ScalarQueryPg( oConn, "SELECT COUNT(*) FROM " + cTbl ) ) - nCountBefore ) )
   oStmt:Free()

   //  8. NULL binding -- BindParam(1, NIL) -> IS NULL
   oStmt := oConn:Prepare( "INSERT INTO " + cTbl + " (name, age, note) VALUES ($1, $2::int, $3)" )
   oStmt:BindParam( 1, "with_null", "s" )
   oStmt:BindParam( 2, 99,          "i" )
   oStmt:BindParam( 3, NIL,         "s" )
   oStmt:Execute()
   oStmt:Free()
   hRow := _FetchOneAssocPg( oConn, "SELECT note FROM " + cTbl + " WHERE name='with_null'" )
   _Check( hRow != NIL .AND. Empty( hRow["note"] ), ;
           "BindParam(NIL) inserta NULL", "NULL/empty", ;
           iif( hRow == NIL, "no row", hRow["note"] ) )

   //  9. Named placeholders (:name) -- BindParam por nombre
   oStmt := oConn:Prepare( "SELECT id FROM " + cTbl + " WHERE name = :who AND age = :yrs::int" )
   _Check( oStmt:nParamCount == 2, ":name reconoce 2 placeholders", "2", hb_NToS( oStmt:nParamCount ) )
   oStmt:BindParam( ":who", "alice", "s" )
   oStmt:BindParam( ":yrs", 20,      "i" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 1, "SELECT con :name devuelve alice", "1", hb_NToS( Len( aRows ) ) )
   oStmt:Free()

   //  10. Reset + re-Execute cambiando parametros sin re-preparar
   oStmt := oConn:Prepare( "SELECT id FROM " + cTbl + " WHERE age = $1::int" )
   oStmt:BindParam( 1, 20, "i" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 1, "re-Execute #1 age=20 -> 1", "1", hb_NToS( Len( aRows ) ) )
   oStmt:BindParam( 1, 30, "i" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 1, "re-Execute #2 age=30 -> 1", "1", hb_NToS( Len( aRows ) ) )
   oStmt:Free()

   //  11. Free llama DEALLOCATE -- la lib no fuga el statement.
   //  Verificacion directa: preparamos 20 statements y comprobamos
   //  que no quedan vivos en pg_prepared_statements (de la sesion actual).
   FOR i := 1 TO 20
      oStmt := oConn:Prepare( "SELECT " + hb_NToS( i ) )
      oStmt:Execute()
      oStmt:Free()
   NEXT
   hRow := _FetchOneAssocPg( oConn, "SELECT count(*) AS n FROM pg_prepared_statements" )
   _Check( hRow != NIL .AND. Val( hRow["n"] ) < 5, ;
           "20 Prepare+Free no fugan (pg_prepared_statements bajo)", "< 5", ;
           iif( hRow == NIL, "no row", hRow["n"] ) )

   //  12. Integracion con pool -- Prepare sobre conexion adquirida
   oConn:Exec( "DROP TABLE IF EXISTS " + cTbl )
   oConn:Close()

   WDO_InitPoolPg( scHost, scUser, scPwd, scDb, snPort, 2, 1000, .F. )
   oConn := WDO_Get( "PG" )
   oStmt := oConn:Prepare( "SELECT $1::int AS n" )
   oStmt:BindParam( 1, 42, "i" )
   oStmt:Execute()
   hRow := oStmt:Fetch_Assoc()
   _Check( hRow != NIL .AND. hRow["n"] == "42", ;
           "Prepare sobre conn del pool devuelve 42", "42", ;
           iif( hRow == NIL, "no row", hb_CStr( hRow["n"] ) ) )
   oStmt:Free()
   oConn:Close()
   WDO_EndPoolPg()

   WDO_PG():lShowError := lOldShow

RETURN


//  Helper: SELECT que devuelve un solo escalar como string
STATIC FUNCTION _ScalarQueryPg( oConn, cSql )
   LOCAL oStmt := oConn:Query( cSql )
   LOCAL aRow, cRet := ""
   IF oStmt != NIL .AND. ! oStmt:lError
      aRow := oStmt:Fetch()
      IF aRow != NIL .AND. Len( aRow ) > 0
         cRet := hb_CStr( aRow[ 1 ] )
      ENDIF
      oStmt:Free()
   ENDIF
RETU cRet


STATIC FUNCTION _FetchOneAssocPg( oConn, cSql )
   LOCAL oStmt := oConn:Query( cSql )
   LOCAL hRow  := NIL
   IF oStmt != NIL .AND. ! oStmt:lError
      hRow := oStmt:Fetch_Assoc()
      oStmt:Free()
   ENDIF
RETU hRow


//  =======================================================
//  Phase 3 -- Stress bench (pool only)
//  =======================================================

STATIC PROCEDURE _RunStress( cLabel, lMetrics )

   LOCAL nT0, nElapsed
   LOCAL nR1, nR2, nR3, nTotal, nThrough
   LOCAL hStats
   LOCAL cJson, hWdo

   hb_default( @cLabel, "Baseline" )
   hb_default( @lMetrics, .F. )

   _Header( "Stress: pool-only load -- " + cLabel )

   OutStd( "  threads .: " + hb_NToS( snThreads ) + " per workload (x3 workloads)" + hb_eol() )
   OutStd( "  queries .: " + hb_NToS( snQueries ) + " per thread" + hb_eol() )
   OutStd( "  pool size: " + hb_NToS( snPoolSize ) + hb_eol() )
   OutStd( "  timeout .: " + hb_NToS( snTimeoutMs ) + " ms" + hb_eol() )
   OutStd( "  metrics .: " + iif( lMetrics, "ON", "OFF" ) + hb_eol() )
   OutStd( "  total ...: " + hb_NToS( snThreads * snQueries * 3 ) + " queries" + hb_eol() )

   shMutex := hb_mutexCreate()

   IF lMetrics
      WDO_MetricsInit( 10 )
   ENDIF

   //  WDO_InitPoolPgEx -- need sslmode=disable (see Phase 2c rationale).
   WDO_InitPoolPgEx( "PG", { ;
      "host"       => scHost,     "user"       => scUser,  ;
      "pwd"        => scPwd,      "db"         => scDb,    ;
      "port"       => snPort,     "pool_size"  => snPoolSize, ;
      "timeout_ms" => snTimeoutMs, "ping"      => .F.,     ;
      "sslmode"    => "disable" } )

   nT0 := hb_MilliSeconds()

   nR1 := _RunWorkload( "W1) SELECT 1                    ", {| n | _WSelect1( n )    } )
   nR2 := _RunWorkload( "W2) SELECT (1+2) AS r           ", {| n | _WArith( n )      } )
   nR3 := _RunWorkload( "W3) SELECT :n AS r  (literal)   ", {| n | _WWithParam( n )  } )

   nElapsed := hb_MilliSeconds() - nT0
   nTotal   := nR1 + nR2 + nR3
   nThrough := iif( nElapsed > 0, nTotal * 1000.0 / nElapsed, 0 )

   hStats := WDO_PoolStats( "PG" )

   //  Snapshot metrics BEFORE closing the pool -- Release() decrements
   //  active_conn and mutates counters that we want to freeze.
   IF lMetrics
      cJson := WDO_MetricsJson()
      hWdo  := hb_JsonDecode( cJson )
   ENDIF

   WDO_EndPoolPg()

   OutStd( hb_eol() + "=== Stress: Global (" + cLabel + ") ===" + hb_eol() )
   OutStd( "  queries ...: " + hb_NToS( nTotal ) + hb_eol() )
   OutStd( "  wall time .: " + Str( nElapsed / 1000.0, 8, 3 ) + " s" + hb_eol() )
   OutStd( "  throughput : " + Str( nThrough, 10, 1 ) + " q/s" + hb_eol() )
   IF hb_isHash( hStats )
      OutStd( "  pool size .: " + hb_NToS( hb_HGetDef( hStats, "size", 0 ) ) + hb_eol() )
      OutStd( "  busy end ..: " + hb_NToS( hb_HGetDef( hStats, "busy", 0 ) ) + hb_eol() )
      OutStd( "  free end ..: " + hb_NToS( hb_HGetDef( hStats, "free", 0 ) ) + hb_eol() )
   ENDIF

   IF lMetrics .AND. HB_ISHASH( hWdo )
      OutStd( hb_eol() + "  --- WDO metrics snapshot ---" + hb_eol() )
      OutStd( "  queries_total ....: " + hb_NToS( hb_HGetDef( hWdo, WDOM_QUERIES_TOTAL,   0 ) ) + hb_eol() )
      OutStd( "  queries_select ...: " + hb_NToS( hb_HGetDef( hWdo, WDOM_QUERIES_SELECT,  0 ) ) + hb_eol() )
      OutStd( "  queries_errors ...: " + hb_NToS( hb_HGetDef( hWdo, WDOM_QUERIES_ERRORS,  0 ) ) + hb_eol() )
      OutStd( "  query_ms_avg .....: " + hb_CStr( hb_HGetDef( hWdo, WDOM_QUERY_MS_AVG,    0 ) ) + hb_eol() )
      OutStd( "  query_ms_max .....: " + hb_NToS( hb_HGetDef( hWdo, WDOM_QUERY_MS_MAX,    0 ) ) + hb_eol() )
      OutStd( "  acquires_total ...: " + hb_NToS( hb_HGetDef( hWdo, WDOM_ACQUIRES_TOTAL,  0 ) ) + hb_eol() )
      OutStd( "  acquire_ms_avg ...: " + hb_CStr( hb_HGetDef( hWdo, WDOM_ACQUIRE_MS_AVG,  0 ) ) + hb_eol() )
      OutStd( "  acquire_ms_max ...: " + hb_NToS( hb_HGetDef( hWdo, WDOM_ACQUIRE_MS_MAX,  0 ) ) + hb_eol() )
      _Check( hb_HGetDef( hWdo, WDOM_QUERIES_TOTAL, 0 ) >= nTotal, ;
              "metrics captured >= " + hb_NToS( nTotal ) + " queries", ;
              ">= " + hb_NToS( nTotal ), ;
              hb_NToS( hb_HGetDef( hWdo, WDOM_QUERIES_TOTAL, 0 ) ) )
      WDO_MetricsClose()
   ENDIF

   _Check( nTotal > 0, "Stress produced queries (" + cLabel + ")", ">0", hb_NToS( nTotal ) )

RETURN


STATIC FUNCTION _RunWorkload( cLabel, bWorker )

   LOCAL aThreads := {}
   LOCAL i, hThr
   LOCAL nT0, nElapsed
   LOCAL nTotalQ, aAll, nThrough
   LOCAL nP50, nP95, nP99
   LOCAL aInner, nMs
   LOCAL nErrors

   OutStd( hb_eol() + "=== " + cLabel + " ===" + hb_eol() )

   saLatencies := {}
   FOR i := 1 TO snThreads
      AAdd( saLatencies, {} )
   NEXT
   snErrors := 0

   nT0 := hb_MilliSeconds()

   FOR i := 1 TO snThreads
      hThr := hb_threadStart( bWorker, i )
      AAdd( aThreads, hThr )
   NEXT

   FOR EACH hThr IN aThreads
      hb_threadJoin( hThr )
   NEXT

   nElapsed := hb_MilliSeconds() - nT0

   aAll := {}
   FOR EACH aInner IN saLatencies
      FOR EACH nMs IN aInner
         AAdd( aAll, nMs )
      NEXT
   NEXT

   nTotalQ  := Len( aAll )
   nThrough := iif( nElapsed > 0, nTotalQ * 1000.0 / nElapsed, 0 )
   nErrors  := snErrors

   ASort( aAll )
   nP50 := _Percentile( aAll, 0.50 )
   nP95 := _Percentile( aAll, 0.95 )
   nP99 := _Percentile( aAll, 0.99 )

   OutStd( "  queries ...: " + hb_NToS( nTotalQ ) + hb_eol() )
   OutStd( "  errors ....: " + hb_NToS( nErrors ) + hb_eol() )
   OutStd( "  wall time .: " + Str( nElapsed / 1000.0, 8, 3 ) + " s" + hb_eol() )
   OutStd( "  throughput : " + Str( nThrough, 10, 1 ) + " q/s" + hb_eol() )
   OutStd( "  latency p50: " + Str( nP50, 8, 3 ) + " ms" + hb_eol() )
   OutStd( "  latency p95: " + Str( nP95, 8, 3 ) + " ms" + hb_eol() )
   OutStd( "  latency p99: " + Str( nP99, 8, 3 ) + " ms" + hb_eol() )

RETU nTotalQ

STATIC FUNCTION _Percentile( aSorted, nPct )
   LOCAL nLen := Len( aSorted )
   LOCAL nIdx
   IF nLen == 0
      RETU 0
   ENDIF
   nIdx := Max( 1, Min( nLen, Int( nLen * nPct + 0.5 ) ) )
RETU aSorted[ nIdx ]


//  ---------- Stress workers (pool-only) ----------

STATIC PROCEDURE _WSelect1( nId )
   LOCAL i, oConn, oStmt, nT0
   FOR i := 1 TO snQueries
      nT0 := hb_MilliSeconds()
      oConn := WDO_Get( "PG" )
      IF oConn == NIL
         hb_mutexLock( shMutex ) ; snErrors++ ; hb_mutexUnlock( shMutex )
         LOOP
      ENDIF
      oStmt := oConn:Query( "SELECT 1" )
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      oConn:Close()
      hb_mutexLock( shMutex ) ; AAdd( saLatencies[ nId ], hb_MilliSeconds() - nT0 ) ; hb_mutexUnlock( shMutex )
   NEXT
RETURN

STATIC PROCEDURE _WArith( nId )
   LOCAL i, oConn, oStmt, nT0
   FOR i := 1 TO snQueries
      nT0 := hb_MilliSeconds()
      oConn := WDO_Get( "PG" )
      IF oConn == NIL
         hb_mutexLock( shMutex ) ; snErrors++ ; hb_mutexUnlock( shMutex )
         LOOP
      ENDIF
      oStmt := oConn:Query( "SELECT (1+2) AS r" )
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      oConn:Close()
      hb_mutexLock( shMutex ) ; AAdd( saLatencies[ nId ], hb_MilliSeconds() - nT0 ) ; hb_mutexUnlock( shMutex )
   NEXT
RETURN

STATIC PROCEDURE _WWithParam( nId )
   LOCAL i, oConn, oStmt, nT0, cSql
   FOR i := 1 TO snQueries
      nT0 := hb_MilliSeconds()
      oConn := WDO_Get( "PG" )
      IF oConn == NIL
         hb_mutexLock( shMutex ) ; snErrors++ ; hb_mutexUnlock( shMutex )
         LOOP
      ENDIF
      cSql  := "SELECT " + hb_NToS( i ) + " AS r"
      oStmt := oConn:Query( cSql )
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      oConn:Close()
      hb_mutexLock( shMutex ) ; AAdd( saLatencies[ nId ], hb_MilliSeconds() - nT0 ) ; hb_mutexUnlock( shMutex )
   NEXT
RETURN


//  =======================================================
//  Main
//  =======================================================

PROCEDURE Main( ... )

   LOCAL oProbe

   CLS

   HIX_LoggerInit( "logs/test_wdo_pg.log", HIX_LOG_DEBUG, .F. )
   HIX_DbgSetFile( "logs/test_wdo_pg.dbg" )
   HIX_DbgReset()
   HIX_DbgEnable( .T. )

   _LoadEnv()

   OutStd( hb_eol() + "===================================================" + hb_eol() )
   OutStd( "  test_wdo_pg -- API + Pool" + hb_eol() )
   OutStd( "===================================================" + hb_eol() )
   OutStd( "  server ..: " + scUser + "@" + scHost + ":" + hb_NToS( snPort ) + "/" + scDb + hb_eol() )
   OutStd( "  trace ...: logs/test_wdo_pg.dbg" + hb_eol() )

   //  Phase 1 offline always runs
   _PhaseBanner( "Phase 1 -- Offline API" )
   _TestOffline()

   //  Preflight -- PG reachability
   _PhaseBanner( "Preflight -- PostgreSQL reachability" )
   OutStd( "  probing " + scUser + "@" + scHost + ":" + hb_NToS( snPort ) + "/" + scDb + " ..." + hb_eol() )

   IF ! _TcpReachable( scHost, snPort, 2000 )
      OutStd( hb_eol() )
      OutStd( "  [SKIP] PostgreSQL port not reachable (TCP probe timeout)." + hb_eol() )
      OutStd( "         endpoint: " + scHost + ":" + hb_NToS( snPort ) + hb_eol() )
      OutStd( "         override with env vars: WDO_PG_HOST WDO_PG_PORT" + hb_eol() )
      _Skip( "Phase 1 online",   "PG unreachable" )
      _Skip( "Phase 2 pool",     "PG unreachable" )
      _Skip( "Phase 2b pool-ex", "PG unreachable" )
      _Skip( "Phase 2c config",  "PG unreachable" )
      _Skip( "Phase 3 stress",   "PG unreachable" )
      _Skip( "Phase 3b stress",  "PG unreachable" )

      //  Phase 2d runs standalone -- no PG needed.
      _PhaseBanner( "Phase 2d -- WDO metrics registry" )
      Test_Metric_InitClose()
      Test_Metric_IncrementSetDec()
      Test_Metric_ResetCounters()
      Test_Metric_SqlClassification()
      Test_Metric_TimingRunningAvg()
      Test_Metric_TopNCap()
      Test_Metric_QueryPerPool()
      Test_Metric_JsonValid()
      Test_Metric_AcquireTiming()
      Test_Metric_FastPathZeroCost()
      Test_Metric_MultiThreadIncrement()
      Test_Metric_HixMetricsJsonInjection()

      _Summary()
      OutStd( "End test..." + hb_eol() )
      _WaitIfInteractive()
      RETURN
   ENDIF

   //  Force sslmode=disable: bundled libpq.dll has no OpenSSL runtime deps.
   //  Default (sslmode=prefer) would try SSL negotiation and hang.
   oProbe := WDO_PG():New( scHost, scUser, scPwd, scDb, snPort, .F. )
   oProbe:cSslMode := "disable"
   oProbe:Open()
   IF oProbe == NIL .OR. ! oProbe:lConnect
      OutStd( hb_eol() )
      OutStd( "  [SKIP] PostgreSQL handshake/auth failed." + hb_eol() )
      IF oProbe != NIL .AND. ! Empty( oProbe:cError )
         OutStd( "         reason: " + oProbe:cError + hb_eol() )
      ENDIF
      OutStd( "         endpoint: " + scUser + "@" + scHost + ":" + hb_NToS( snPort ) + "/" + scDb + hb_eol() )
      OutStd( "         override with env vars: WDO_PG_USER WDO_PG_PWD WDO_PG_DB" + hb_eol() )
      IF oProbe != NIL ; oProbe:End() ; ENDIF
      _Skip( "Phase 1 online",   "handshake/auth failed" )
      _Skip( "Phase 2 pool",     "handshake/auth failed" )
      _Skip( "Phase 2b pool-ex", "handshake/auth failed" )
      _Skip( "Phase 2c config",  "handshake/auth failed" )
      _Skip( "Phase 3 stress",   "handshake/auth failed" )
      _Skip( "Phase 3b stress",  "handshake/auth failed" )

      _PhaseBanner( "Phase 2d -- WDO metrics registry" )
      Test_Metric_InitClose()
      Test_Metric_IncrementSetDec()
      Test_Metric_ResetCounters()
      Test_Metric_SqlClassification()
      Test_Metric_TimingRunningAvg()
      Test_Metric_TopNCap()
      Test_Metric_QueryPerPool()
      Test_Metric_JsonValid()
      Test_Metric_AcquireTiming()
      Test_Metric_FastPathZeroCost()
      Test_Metric_MultiThreadIncrement()
      Test_Metric_HixMetricsJsonInjection()

      _Summary()
      OutStd( "End test..." + hb_eol() )
      _WaitIfInteractive()
      RETURN
   ENDIF

   OutStd( "  [OK] server " + oProbe:ServerInfo() + ;
           " (client " + oProbe:ClientInfo() + ")" + hb_eol() )

   //  Phase 1 online -- reuse probe conn
   _PhaseBanner( "Phase 1 -- Online API" )
   _TestOnline( oProbe )

   //  Phase 2 pool
   _PhaseBanner( "Phase 2 -- Pool" )
   _TestPool()

   //  Phase 2b pool ex
   _PhaseBanner( "Phase 2b -- Pool Ex (hash variant)" )
   _TestPoolEx()

   //  Phase 2bp -- Prepared statements (Alt A libpq)
   _PhaseBanner( "Phase 2bp -- Prepared statements (libpq native)" )
   TestPreparePg()

   //  Phase 2c -- declarative bootstrap from config.json
   _PhaseBanner( "Phase 2c -- HIX_InitPoolsFromConfig" )
   TestConfigJson()

   //  Phase 2d -- WDO metrics registry (standalone unit tests)
   _PhaseBanner( "Phase 2d -- WDO metrics registry" )
   Test_Metric_InitClose()
   Test_Metric_IncrementSetDec()
   Test_Metric_ResetCounters()
   Test_Metric_SqlClassification()
   Test_Metric_TimingRunningAvg()
   Test_Metric_TopNCap()
   Test_Metric_QueryPerPool()
   Test_Metric_JsonValid()
   Test_Metric_AcquireTiming()
   Test_Metric_FastPathZeroCost()
   Test_Metric_MultiThreadIncrement()
   Test_Metric_HixMetricsJsonInjection()

   //  Phase 3 -- stress bench (pool only, metrics OFF)
   _PhaseBanner( "Phase 3 -- Stress bench (pool only)" )
   //  Disable dbg/log noise for realistic throughput numbers.
   HIX_DbgEnable( .F. )
   HIX_LoggerClose()
   HIX_LoggerInit( "logs/test_wdo_pg.log", HIX_LOG_ERROR, .F. )
   _RunStress( "Baseline (metrics OFF)", .F. )

   //  Phase 3b -- same workloads with WDO_Metric* registry active
   _PhaseBanner( "Phase 3b -- Stress bench (metrics ON)" )
   _RunStress( "Metrics ON", .T. )

   _Summary()
   OutStd( "End test..." + hb_eol() )

   _WaitIfInteractive()

RETURN
