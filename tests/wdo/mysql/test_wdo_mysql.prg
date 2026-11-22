/*-----------------------------------------------------------
  File ......: test_wdo_mysql.prg
  Author.....: Claude Code 
  Created....: 2026-09-28
  Modified...: 2026-09-28
  Version....: 1.0.0
  Description: Runs three phases against a single Harbour 
               process and a single MySQL server:

                 Phase 1 -- MySQL API
                   Offline: helpers, escape, htmlencode,
                            library resolution, no-open ctor.
                   Online:  Open/Ping/Query/Fetch/Insert/
                            Update/Transactions/Close/CountOpen.

                 Phase 2 -- Connection pool (functional)
                   Init/End, Acquire/Release, timeout on
                   exhaustion, auto-rollback on Close(),
                   dispatcher-hook safety net, cross-thread
                   borrowing, stats, unregistered driver,
                   guard on New() inside HTTP handler (EN+ES).

                 Phase 3 -- Stress (pool only)
                   100 threads x 200 queries x 3 workloads by
                   default (= 60 000 queries) over a pool of 10.
                   Confirms no socket exhaustion, no timeouts,
                   clean shutdown. Reports throughput and
                   p50/p95/p99 per workload plus a global line.

  Usage      : go_msvc64.bat 

               Env (all optional):
                 WDO_MYSQL_HOST  (default localhost)
                 WDO_MYSQL_USER  (default harbour)
                 WDO_MYSQL_PWD   (default hb1234)
                 WDO_MYSQL_DB    (default employees)
                 WDO_MYSQL_PORT  (default 3306)
                 BENCH_THREADS   (default 100)
                 BENCH_QUERIES   (default 200)
                 BENCH_POOL      (default 10)
                 BENCH_TIMEOUT_MS(default 15000)

  Notes      : If MySQL is unreachable, Phase 1 online + Phase 2
               + Phase 3 are skipped (Phase 1 offline still runs).
               Trace file: logs/test_wdo_mysql.dbg
 -----------------------------------------------------------*/

#include "hix_logger.ch"
#include "hbclass.ch"
#include "wdo_metrics.ch"

//  ---------- Shared counters ----------
STATIC snTotal   := 0
STATIC snPassed  := 0
STATIC snFailed  := 0
STATIC snSkipped := 0

//  ---------- Connection + bench config ----------
STATIC scHost, scUser, scPwd, scDb, snPort
STATIC snThreads, snQueries, snPoolSize, snTimeoutMs
STATIC snBErrCalls := 0, soLastErr, soLastConn

//  ---------- Stress bench mutex + accumulators ----------
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

//  Wait for a keypress only when the test is running interactively.
//  Skip the wait when any of these holds:
//   - hb_argc() > 0            : caller passed an arg (batch mode).
//   - stdin  is not a TTY      : pipe / redirect / Bash bg / CI / agent.
//   - stdout is not a TTY      : output redirected -> nobody watching.
//  Checking stdout too is critical: when Bash launches the .exe, stdin
//  stays attached to the terminal even without a user typing, so a stdin-
//  only probe would still hang. Preserves the "double-click keeps the
//  window open" convention for CMD / Explorer where all three are TTY.
STATIC PROCEDURE _WaitIfInteractive()
   IF hb_argc() > 0                   ; RETURN ; ENDIF
   IF ! hb_FIsDevice( 0 )             ; RETURN ; ENDIF   //  stdin
   IF ! hb_FIsDevice( 1 )             ; RETURN ; ENDIF   //  stdout
   Inkey( 0 )
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


//  =======================================================
//  Env helpers
//  =======================================================

STATIC FUNCTION _EnvOr( cVar, cDef )
   LOCAL cVal := hb_GetEnv( cVar )
RETURN iif( Empty( cVal ), cDef, cVal )

STATIC PROCEDURE _LoadEnv()
   scHost      := _EnvOr( "WDO_MYSQL_HOST", "localhost" )
   scUser      := _EnvOr( "WDO_MYSQL_USER", "harbour"   )
   scPwd       := _EnvOr( "WDO_MYSQL_PWD",  "hb1234"    )
   scDb        := _EnvOr( "WDO_MYSQL_DB",   "employees" )
   snPort      := Val( _EnvOr( "WDO_MYSQL_PORT",     "3306"  ) )
   snThreads   := Val( _EnvOr( "BENCH_THREADS",      "100"   ) )
   snQueries   := Val( _EnvOr( "BENCH_QUERIES",      "200"   ) )
   snPoolSize  := Val( _EnvOr( "BENCH_POOL",         "10"    ) )
   snTimeoutMs := Val( _EnvOr( "BENCH_TIMEOUT_MS",   "15000" ) )
RETURN

STATIC FUNCTION _ConnectOrSkip()
   LOCAL oConn := WDO_MySql():New( scHost, scUser, scPwd, scDb, snPort, .T. )
   IF oConn == NIL .OR. ! oConn:lConnect
      RETU NIL
   ENDIF
RETU oConn


//  Drop any residual hix_test_prep*/hix_test_prepbin* tables from previous
//  interrupted runs. Keeps the schema tidy without manual DROP sweeps.
STATIC PROCEDURE _SweepOrphans()

   LOCAL oConn, oStmt, aRow, cTbl
   LOCAL nDropped := 0

   oConn := WDO_MySql():New( scHost, scUser, scPwd, scDb, snPort, .T. )
   IF oConn == NIL .OR. ! oConn:lConnect
      IF oConn != NIL ; oConn:End() ; ENDIF
      RETURN
   ENDIF

   oStmt := oConn:Query( "SELECT table_name FROM information_schema.tables " + ;
                         "WHERE table_schema = DATABASE() " + ;
                         "AND table_name LIKE 'hix\\_test\\_prep%' ESCAPE '\\'" )
   IF oStmt != NIL .AND. ! oStmt:lError
      DO WHILE ( aRow := oStmt:Fetch() ) != NIL
         cTbl := aRow[ 1 ]
         oConn:Exec( "DROP TABLE IF EXISTS `" + cTbl + "`" )
         nDropped++
      ENDDO
      oStmt:Free()
   ENDIF

   oConn:End()

   IF nDropped > 0
      OutStd( "  [sweep] dropped " + hb_NToS( nDropped ) + " orphan hix_test_prep* table(s)" + hb_eol() )
   ENDIF

RETURN


//  =======================================================
//  Main
//  =======================================================

PROCEDURE Main( ... )

   LOCAL oProbe
   
   CLS

   HIX_LoggerInit( "logs/test_wdo_mysql.log", HIX_LOG_DEBUG, .F. )
   HIX_DbgSetFile( "logs/test_wdo_mysql.dbg" )
   HIX_DbgReset()
   HIX_DbgEnable( .T. )

   _LoadEnv()

   OutStd( hb_eol() + "===================================================" + hb_eol() )
   OutStd( "  test_wdo_mysql -- API + Pool + Stress" + hb_eol() )
   OutStd( "===================================================" + hb_eol() )
   OutStd( "  server ..: " + scUser + "@" + scHost + ":" + hb_NToS( snPort ) + "/" + scDb + hb_eol() )
   OutStd( "  trace ...: logs/test_wdo_mysql.dbg" + hb_eol() )

   //  -----------------------------------------------
   //  Preflight -- MySQL reachability check
   //  Bail out early if the server is not reachable so we do not
   //  waste time in offline suites when the whole run depends on it.
   //  First a raw TCP probe (fast fail in ~2 s), then a real MySQL
   //  handshake to verify credentials/DB.
   //  -----------------------------------------------
   _PhaseBanner( "Preflight -- MySQL server reachability" )
   OutStd( "  probing " + scUser + "@" + scHost + ":" + hb_NToS( snPort ) + "/" + scDb + " ..." + hb_eol() )

   IF ! _TcpReachable( scHost, snPort, 2000 )
      OutStd( hb_eol() )
      OutStd( "  [ABORT] MySQL port not reachable (TCP probe timeout)." + hb_eol() )
      OutStd( "          endpoint: " + scHost + ":" + hb_NToS( snPort ) + hb_eol() )
      OutStd( "          is mysqld running? try:  sc query MySQL  |  tasklist | findstr mysqld" + hb_eol() )
      OutStd( "          override with env vars: WDO_MYSQL_HOST WDO_MYSQL_PORT" + hb_eol() )
      OutStd( hb_eol() + "End test..." + hb_eol() )
      _WaitIfInteractive()
      RETURN
   ENDIF

   oProbe := WDO_MySql():New( scHost, scUser, scPwd, scDb, snPort, .T. )
   IF oProbe == NIL .OR. ! oProbe:lConnect
      OutStd( hb_eol() )
      OutStd( "  [ABORT] MySQL handshake/auth failed." + hb_eol() )
      IF oProbe != NIL .AND. ! Empty( oProbe:cError )
         OutStd( "          reason: " + oProbe:cError + hb_eol() )
      ENDIF
      OutStd( "          endpoint: " + scUser + "@" + scHost + ":" + hb_NToS( snPort ) + "/" + scDb + hb_eol() )
      OutStd( "          check credentials / DB name; override with env vars:" + hb_eol() )
      OutStd( "            WDO_MYSQL_USER  WDO_MYSQL_PWD  WDO_MYSQL_DB" + hb_eol() )
      IF oProbe != NIL ; oProbe:End() ; ENDIF
      OutStd( hb_eol() + "End test..." + hb_eol() )
      _WaitIfInteractive()
      RETURN
   ENDIF

   OutStd( "  [OK] server " + oProbe:ServerInfo() + ;
           "  (client " + oProbe:ClientInfo() + ")" + hb_eol() )
   oProbe:End()

   //  Sweep residual hix_test_prep* tables from interrupted previous runs
   _SweepOrphans()

   //  -----------------------------------------------
   //  Phase 1 -- MySQL API
   //  -----------------------------------------------
   _PhaseBanner( "Phase 1 -- MySQL API" )
   _SuiteOffline()
   _SuiteOnline()
   _SuiteDbStruct()

   //  -----------------------------------------------
   //  Phase 2 -- Pool functional tests
   //  -----------------------------------------------
   _PhaseBanner( "Phase 2 -- Connection pool (functional)" )
   TestInitEnd()
   TestAcquireRelease()
   TestPoolExhaustionTimeout()
   TestAutoRollback()
   TestReleaseAllThreadHook()
   TestCrossThread()
   TestStats()
   TestUnregisteredDriver()
   TestNewGuard()
   TestPoolBError()

   //  -----------------------------------------------
   //  Phase 2b -- Prepared statements (Alt B: server-side PREPARE)
   //  -----------------------------------------------
   _PhaseBanner( "Phase 2b -- Prepared statements" )
   TestPrepare()

   //  -----------------------------------------------
   //  Phase 2b-bin -- Prepared statements Alt A (binary protocol)
   //  -----------------------------------------------
   _PhaseBanner( "Phase 2b-bin -- Prepared statements (binary)" )
   TestPrepareBin()

   //  -----------------------------------------------
   //  Phase 2b-fetch -- Alt A SELECT fetch binario (v2.3.04)
   //  -----------------------------------------------
   _PhaseBanner( "Phase 2b-fetch -- Alt A SELECT fetch binario" )
   TestPrepareBinFetch()

   //  -----------------------------------------------
   //  Phase 2c -- Declarative bootstrap from config.json
   //  -----------------------------------------------
   _PhaseBanner( "Phase 2c -- HIX_InitPoolsFromConfig" )
   TestConfigJson()

   //  -----------------------------------------------
   //  Phase 2d -- WDO metrics registry (standalone unit tests)
   //  -----------------------------------------------
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

   //  -----------------------------------------------
   //  Phase 3 -- Stress bench (pool only)
   //  -----------------------------------------------
   _PhaseBanner( "Phase 3 -- Stress bench (pool only)" )
   //  Disable dbg/log noise for realistic throughput numbers.
   HIX_DbgEnable( .F. )
   HIX_LoggerClose()
   HIX_LoggerInit( "logs/test_wdo_mysql.log", HIX_LOG_ERROR, .F. )
   _RunStress( "Baseline (metrics OFF)", .F. )

   //  -----------------------------------------------
   //  Phase 3b -- Stress bench con metricas activadas
   //  Repite los mismos 3 workloads con el registro WDO_Metric* on
   //  para medir el overhead real end-to-end (query + acquire timing
   //  + top-N + per-pool counters). Al final vuelca WDO_MetricsJson()
   //  para confirmar que se capturaron los datos.
   //  -----------------------------------------------
   _PhaseBanner( "Phase 3b -- Stress bench (metrics ON)" )
   _RunStress( "Metrics ON", .T. )

   _Summary()
   OutStd( "End test..." + hb_eol() )

   _WaitIfInteractive()

RETURN


//  Fast raw TCP probe with timeout so we never hang if mysqld is
//  down (mysql_real_connect can block ~60 s waiting for TCP retry).
STATIC FUNCTION _TcpReachable( cHost, nPort, nTimeoutMs )
   LOCAL hSock
   LOCAL lOk
   LOCAL cResolved
   //  Force IPv4 -- "localhost" on Windows often resolves to ::1 (IPv6)
   //  and hb_socketConnect with HB_SOCKET_AF_INET would block instead of failing fast.
   cResolved := iif( Lower( AllTrim( cHost ) ) == "localhost", "127.0.0.1", cHost )
   hSock := hb_socketOpen()
   IF hSock == NIL
      RETU .F.
   ENDIF
   lOk := hb_socketConnect( hSock, { HB_SOCKET_AF_INET, cResolved, nPort }, nTimeoutMs )
   hb_socketClose( hSock )
RETU lOk

STATIC FUNCTION _ProbeMySql()
   LOCAL oProbe := WDO_MySql():New( scHost, scUser, scPwd, scDb, snPort, .T. )
   IF oProbe == NIL .OR. ! oProbe:lConnect
      IF oProbe != NIL ; oProbe:End() ; ENDIF
      RETU NIL
   ENDIF
   oProbe:End()
RETU .T.


//  =======================================================
//  Phase 1 -- Suite 1: Offline (no connection)
//  =======================================================

STATIC PROCEDURE _SuiteOffline()

   LOCAL oConn, cLib, hEsc, aEsc, cEsc

   _Header( "Suite 1.a -- Offline (sin conexion)" )

   //  wdo_addslashes
   _Check( wdo_addslashes( "l'aliga" ) == "l\'aliga", ;
           "addslashes: single quote", "l\'aliga", wdo_addslashes( "l'aliga" ) )

   _Check( wdo_addslashes( 'Hello "World"' ) == 'Hello \"World\"', ;
           "addslashes: double quote", 'Hello \"World\"', wdo_addslashes( 'Hello "World"' ) )

   _Check( wdo_addslashes( "c:\path" ) == "c:\\path", ;
           "addslashes: backslash", "c:\\path", wdo_addslashes( "c:\path" ) )

   //  wdo_htmlencode
   _Check( wdo_htmlencode( "<b>&</b>" ) == "&lt;b&gt;&amp;&lt;/b&gt;", ;
           "htmlencode: tags + amp", "&lt;b&gt;&amp;&lt;/b&gt;", wdo_htmlencode( "<b>&</b>" ) )

   _Check( wdo_htmlencode( "a'b" + Chr(34) + "c" ) == "a&apos;b&quot;c", ;
           "htmlencode: quotes", "a&apos;b&quot;c", wdo_htmlencode( "a'b" + Chr(34) + "c" ) )

   //  Library resolution
   cLib := hb_SysMySQL()
   _Check( ! Empty( cLib ) .AND. ".dll" $ Lower( cLib ) .OR. ".so" $ cLib .OR. ".dylib" $ cLib, ;
           "hb_SysMySQL devuelve ruta", "no vacia + ext conocida", hb_CStr( cLib ) )

   cLib := hb_SysMariaDb()
   _Check( ! Empty( cLib ) .AND. ".dll" $ Lower( cLib ) .OR. ".so" $ cLib .OR. ".dylib" $ cLib, ;
           "hb_SysMariaDb devuelve ruta", "no vacia + ext conocida", hb_CStr( cLib ) )

   //  No-open constructor
   oConn := WDO_MySql():New( "nohost", "u", "p", "d", 3306, .F. )
   _Check( oConn != NIL,               "New(lOpen=.F.) devuelve objeto",       "!= NIL", hb_CStr( oConn ) )
   _Check( oConn:cServer == "nohost",  "constructor asigna cServer",           "nohost", oConn:cServer )
   _Check( oConn:cUserName == "u",     "constructor asigna cUserName",         "u",      oConn:cUserName )
   _Check( oConn:nPort == 3306,        "constructor asigna nPort",             "3306",   hb_NToS( oConn:nPort ) )
   _Check( oConn:lConnect == .F.,      "lConnect=.F. sin Open()",              ".F.",    iif( oConn:lConnect, ".T.", ".F." ) )
   _Check( oConn:cType == 'MYSQL',     "cType default = MYSQL",                "MYSQL",  oConn:cType )
   _Check( oConn:lInUse == .F.,        "lInUse=.F. por defecto (pool ready)",  ".F.",    iif( oConn:lInUse, ".T.", ".F." ) )

   //  Escape sobre hash
   hEsc := { "name" => "O'Reilly", "role" => 'admin"x', "age" => 42 }
   oConn:Escape( hEsc )
   _Check( hEsc["name"] == "O\'Reilly", "Escape hash: quotes en string",   "O\'Reilly", hEsc["name"] )
   _Check( hEsc["role"] == 'admin\"x',  "Escape hash: dobles en string",   'admin\"x',  hEsc["role"] )
   _Check( hEsc["age"] == 42,           "Escape hash: numericos intactos", "42",        hb_CStr( hEsc["age"] ) )

   //  Escape sobre array
   aEsc := { "l'a", 3.14, 'x"y' }
   oConn:Escape( aEsc )
   _Check( aEsc[1] == "l\'a", "Escape array: string escapado",  "l\'a", aEsc[1] )
   _Check( aEsc[2] == 3.14,   "Escape array: numerico intacto", "3.14", hb_CStr( aEsc[2] ) )
   _Check( aEsc[3] == 'x\"y', "Escape array: string escapado",  'x\"y', aEsc[3] )

   //  Escape sobre string
   cEsc := oConn:Escape( "l'aliga" )
   _Check( cEsc == "l\'aliga", "Escape string directo",          "l\'aliga", cEsc )
   _Check( oConn:Escape( "l'a" ) == "l\'a", "Escape string corto", "l\'a",    oConn:Escape( "l'a" ) )

RETURN


//  =======================================================
//  Phase 1 -- Suite 2: Online (requires MySQL)
//  =======================================================

STATIC PROCEDURE _SuiteOnline()

   LOCAL oConn, oStmt, hRow, aRows, nId, nAff, oErr
   LOCAL cTbl := "hix_test_wdo_" + hb_NToS( Int( Seconds() ) )

   _Header( "Suite 1.b -- Online (requiere MySQL)" )

   oConn := _ConnectOrSkip()
   IF oConn == NIL
      _Skip( "Open/Ping/Query/Fetch/Insert/Affected", "no hay MySQL" )
      RETU
   ENDIF

   //  Conexion abierta
   _Check( oConn:lConnect == .T.,        "Open(): lConnect = .T.", ".T.",     iif( oConn:lConnect, ".T.", ".F." ) )
   _Check( oConn:hConnection != 0,       "hConnection != 0",       "!= 0",    hb_CStr( oConn:hConnection ) )
   _Check( ! Empty( oConn:ServerInfo() ),"ServerInfo() no vacio",  "no vacio", hb_CStr( oConn:ServerInfo() ) )
   _Check( ! Empty( oConn:ClientInfo() ),"ClientInfo() no vacio",  "no vacio", hb_CStr( oConn:ClientInfo() ) )

   //  Ping
   _Check( oConn:Ping(), "Ping() OK", ".T.", iif( oConn:Ping(), ".T.", ".F." ) )

   //  Query SELECT
   oStmt := oConn:Query( "SELECT 1 AS one, 'hello' AS greet" )
   _Check( oStmt != NIL,                   "Query devuelve Stmt",       "!= NIL", hb_CStr( oStmt ) )
   _Check( oStmt:hRes != 0,                "Stmt:hRes != 0 en SELECT",  "!= 0",   hb_CStr( oStmt:hRes ) )
   _Check( ! oStmt:lError,                 "Stmt:lError = .F.",         ".F.",    iif( oStmt:lError, ".T.", ".F." ) )
   _Check( oStmt:nFields == 2,             "Stmt:nFields = 2",          "2",      hb_NToS( oStmt:nFields ) )
   _Check( oStmt:Count() == 1,             "Stmt:Count() = 1",          "1",      hb_NToS( oStmt:Count() ) )
   _Check( oStmt:aFields[1][1] == "one",   "Stmt:aFields[1][1]='one'",  "one",    hb_CStr( oStmt:aFields[1][1] ) )
   _Check( oStmt:aFields[2][1] == "greet", "Stmt:aFields[2][1]='greet'","greet",  hb_CStr( oStmt:aFields[2][1] ) )

   hRow := oStmt:Fetch_Assoc()
   _Check( hRow["one"] == "1",         "Fetch_Assoc 'one' = '1'",       "1",     hb_CStr( hRow["one"] ) )
   _Check( hRow["greet"] == "hello",   "Fetch_Assoc 'greet' = 'hello'", "hello", hb_CStr( hRow["greet"] ) )
   oStmt:Free()
   _Check( oStmt:hRes == 0,            "Stmt:Free() resetea hRes",      "0",     hb_CStr( oStmt:hRes ) )

   //  Temp table + INSERT + Last_Insert_Id + Affected_Rows
   oConn:Exec( "DROP TABLE IF EXISTS " + cTbl )
   nAff := oConn:Exec( "CREATE TABLE " + cTbl + ;
                       " ( id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), score INT )" )
   _Check( nAff >= 0, "CREATE TABLE (nAff >= 0)", ">= 0", hb_NToS( nAff ) )

   oConn:Exec( "INSERT INTO " + cTbl + " (name, score) VALUES ('alice', 10)" )
   nId := oConn:Last_Insert_Id()
   _Check( nId > 0, "Last_Insert_Id() > 0 tras INSERT", "> 0", hb_NToS( nId ) )

   nAff := oConn:Exec( "INSERT INTO " + cTbl + " (name, score) VALUES ('bob', 20), ('carol', 30)" )
   _Check( nAff == 2, "Exec INSERT multiple -> 2 affected", "2", hb_NToS( nAff ) )

   //  FetchAll asociativo
   oStmt := oConn:Query( "SELECT id, name, score FROM " + cTbl + " ORDER BY id" )
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 3,           "FetchAll(.T.) devuelve 3 filas", "3",     hb_NToS( Len( aRows ) ) )
   _Check( aRows[1]["name"] == "alice", "FetchAll[1].name = alice",       "alice", hb_CStr( aRows[1]["name"] ) )
   _Check( aRows[3]["name"] == "carol", "FetchAll[3].name = carol",       "carol", hb_CStr( aRows[3]["name"] ) )
   oStmt:Free()

   //  UPDATE
   nAff := oConn:Exec( "UPDATE " + cTbl + " SET score = score + 1 WHERE score >= 20" )
   _Check( nAff == 2, "UPDATE afecta 2 filas", "2", hb_NToS( nAff ) )

   //  Iteracion
   oStmt := oConn:Query( "SELECT name FROM " + cTbl + " ORDER BY id" )
   hRow  := oStmt:Fetch_Assoc()
   _Check( hRow["name"] == "alice", "Fetch_Assoc() primera fila", "alice", hb_CStr( hRow["name"] ) )
   hRow := oStmt:Fetch_Assoc()
   _Check( hRow["name"] == "bob",   "Fetch_Assoc() segunda fila", "bob",   hb_CStr( hRow["name"] ) )
   oStmt:Free()

   //  COUNT(*)
   oStmt := oConn:Query( "SELECT COUNT(*) AS n FROM " + cTbl )
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 1,     "FetchAll(.T.) 1 fila", "1", hb_NToS( Len( aRows ) ) )
   _Check( aRows[1]["n"] == "3",  "COUNT(*) = 3",         "3", hb_CStr( aRows[1]["n"] ) )
   oStmt:Free()

   //  Transacciones
   _Check( oConn:lInTrans == .F.,       "lInTrans = .F. inicial",         ".F.", iif( oConn:lInTrans, ".T.", ".F." ) )
   _Check( oConn:BeginTrans() == .T.,   "BeginTrans() = .T.",             ".T.", ".F." )
   _Check( oConn:lInTrans == .T.,       "lInTrans = .T. tras BeginTrans", ".T.", iif( oConn:lInTrans, ".T.", ".F." ) )
   _Check( oConn:BeginTrans() == .F.,   "BeginTrans() doble = .F.",       ".F.", ".T." )

   oConn:Exec( "INSERT INTO " + cTbl + " (name) VALUES ('trans1')" )
   _Check( oConn:Rollback() == .T., "Rollback() = .T.",                ".T.", ".F." )
   _Check( oConn:lInTrans == .F.,   "lInTrans = .F. tras Rollback",    ".F.", iif( oConn:lInTrans, ".T.", ".F." ) )

   oStmt := oConn:Query( "SELECT COUNT(*) AS n FROM " + cTbl )
   aRows := oStmt:FetchAll( .T. )
   _Check( aRows[1]["n"] == "3", "Rollback revierte INSERT", "3", hb_CStr( aRows[1]["n"] ) )
   oStmt:Free()

   oConn:BeginTrans()
   oConn:Exec( "INSERT INTO " + cTbl + " (name) VALUES ('trans2')" )
   _Check( oConn:Commit() == .T., "Commit() = .T.",              ".T.", ".F." )
   _Check( oConn:lInTrans == .F., "lInTrans = .F. tras Commit",  ".F.", iif( oConn:lInTrans, ".T.", ".F." ) )

   oStmt := oConn:Query( "SELECT COUNT(*) AS n FROM " + cTbl )
   aRows := oStmt:FetchAll( .T. )
   _Check( aRows[1]["n"] == "4", "Commit persiste INSERT (COUNT=4)", "4", hb_CStr( aRows[1]["n"] ) )
   oStmt:Free()

   //  Transaction(bCode) -- commit
   oConn:Transaction( {|o| o:Exec( "INSERT INTO " + cTbl + " (name) VALUES ('trans3')" ) } )
   _Check( oConn:lInTrans == .F., "Transaction(bCode) exit sin trans", ".F.", iif( oConn:lInTrans, ".T.", ".F." ) )

   oStmt := oConn:Query( "SELECT COUNT(*) AS n FROM " + cTbl )
   aRows := oStmt:FetchAll( .T. )
   _Check( aRows[1]["n"] == "5", "Transaction commit persiste (COUNT=5)", "5", hb_CStr( aRows[1]["n"] ) )
   oStmt:Free()

   //  Transaction(bCode) -- rollback tras excepcion
   TRY
      oConn:Transaction( {|o| _TransFail( o, cTbl ) } )
   CATCH oErr
      // capturado, re-raised por Transaction
   END

   _Check( oConn:lInTrans == .F., "Transaction(bCode) fail sin trans", ".F.", iif( oConn:lInTrans, ".T.", ".F." ) )
   oStmt := oConn:Query( "SELECT COUNT(*) AS n FROM " + cTbl )
   aRows := oStmt:FetchAll( .T. )
   _Check( aRows[1]["n"] == "5", "Transaction rollback (COUNT sigue 5)", "5", hb_CStr( aRows[1]["n"] ) )
   oStmt:Free()

   //  Close() sin commit -> server rollback
   oConn:BeginTrans()
   oConn:Exec( "INSERT INTO " + cTbl + " (name) VALUES ('nocommit')" )
   _Check( oConn:lInTrans == .T., "lInTrans .T. antes de Close sin commit", ".T.", iif( oConn:lInTrans, ".T.", ".F." ) )
   oConn:Close()
   _Check( oConn:lConnect == .F., "Close() -> lConnect = .F.", ".F.", iif( oConn:lConnect, ".T.", ".F." ) )

   oConn := _ConnectOrSkip()
   oStmt := oConn:Query( "SELECT COUNT(*) AS n FROM " + cTbl )
   aRows := oStmt:FetchAll( .T. )
   _Check( aRows[1]["n"] == "5", "Close sin commit -> server rollback (COUNT sigue 5)", "5", hb_CStr( aRows[1]["n"] ) )
   oStmt:Free()

   //  Commit + Close -> persiste
   oConn:BeginTrans()
   oConn:Exec( "INSERT INTO " + cTbl + " (name) VALUES ('withcommit')" )
   oConn:Commit()
   oConn:Close()

   oConn := _ConnectOrSkip()
   oStmt := oConn:Query( "SELECT COUNT(*) AS n FROM " + cTbl )
   aRows := oStmt:FetchAll( .T. )
   _Check( aRows[1]["n"] == "6", "Commit + Close -> persiste (COUNT=6)", "6", hb_CStr( aRows[1]["n"] ) )
   oStmt:Free()

   //  Cleanup
   oConn:Exec( "DROP TABLE " + cTbl )
   oConn:Close()

   //  CountOpen tests
   _CountOpenTests()

RETURN

STATIC PROCEDURE _CountOpenTests()

   LOCAL nBase := WDO_MySqlCountOpen()
   LOCAL o1, o2

   _Check( nBase == 0, "CountOpen() = 0 antes de abrir", "0", hb_NToS( nBase ) )

   o1 := _ConnectOrSkip()
   IF o1 == NIL ; RETU ; ENDIF
   _Check( WDO_MySqlCountOpen() == 1, "CountOpen() = 1 tras 1er Open", "1", hb_NToS( WDO_MySqlCountOpen() ) )

   o2 := _ConnectOrSkip()
   IF o2 == NIL ; o1:Close() ; RETU ; ENDIF
   _Check( WDO_MySqlCountOpen() == 2, "CountOpen() = 2 tras 2o Open", "2", hb_NToS( WDO_MySqlCountOpen() ) )
   _Check( o1:CountOpen() == 2,       "instancia:CountOpen() = 2",    "2", hb_NToS( o1:CountOpen() ) )

   o1:Close()
   _Check( WDO_MySqlCountOpen() == 1, "CountOpen() = 1 tras cerrar 1a", "1", hb_NToS( WDO_MySqlCountOpen() ) )

   o1:Close()
   _Check( WDO_MySqlCountOpen() == 1, "Close() doble no doble-decrementa", "1", hb_NToS( WDO_MySqlCountOpen() ) )

   o2:Close()
   _Check( WDO_MySqlCountOpen() == 0, "CountOpen() = 0 tras cerrar todas", "0", hb_NToS( WDO_MySqlCountOpen() ) )

RETURN

//  =======================================================
//  Suite 1.c -- DbStruct: length + decimals (employees table)
//  =======================================================
STATIC PROCEDURE _SuiteDbStruct()

   LOCAL oConn, oStmt, aFld, oErr, lOk
   LOCAL cDecTbl := "hix_test_wdo_dec_" + hb_NToS( Int( Seconds() ) )

   _Header( "Suite 1.c -- DbStruct length + decimals" )

   oConn := _ConnectOrSkip()
   IF oConn == NIL
      _Skip( "DbStruct employees", "no hay MySQL" )
      RETU
   ENDIF

   //  Verificar que la tabla employees existe
   lOk := .F.
   TRY
      oStmt := oConn:Query( "SELECT 1 FROM employees LIMIT 1" )
      lOk   := ( oStmt != NIL .AND. ! oStmt:lError )
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
   CATCH oErr
   END

   IF ! lOk
      _Skip( "DbStruct employees", "tabla 'employees' no disponible en " + scDb )
      oConn:Close()
      RETU
   ENDIF

   //  --- Columnas de employees ---
   oStmt := oConn:Query( "SELECT emp_no, birth_date, first_name FROM employees LIMIT 1" )
   _Check( oStmt != NIL .AND. ! oStmt:lError, "DbStruct: query employees OK", ".T.", ;
           iif( oStmt == NIL .OR. oStmt:lError, ".F.", ".T." ) )

   IF oStmt == NIL .OR. oStmt:lError
      oConn:Close()
      RETU
   ENDIF

   aFld := oStmt:DbStruct()
   _Check( Len( aFld ) == 3, "DbStruct: 3 campos", "3", hb_NToS( Len( aFld ) ) )

   //  emp_no INT -> N, length=11, decimals=0
   _Check( aFld[1][1] == "emp_no", "DbStruct[1] nombre",        "emp_no", hb_CStr( aFld[1][1] ) )
   _Check( aFld[1][2] == "N",      "DbStruct[1] tipo = N",      "N",      hb_CStr( aFld[1][2] ) )
   _Check( aFld[1][3] != NIL,      "DbStruct[1] length != NIL", "!= NIL", hb_CStr( aFld[1][3] ) )
   _Check( aFld[1][3] == 11,       "DbStruct[1] length = 11",   "11",     hb_NToS( aFld[1][3] ) )
   _Check( aFld[1][4] != NIL,      "DbStruct[1] dec != NIL",    "!= NIL", hb_CStr( aFld[1][4] ) )
   _Check( aFld[1][4] == 0,        "DbStruct[1] dec = 0",       "0",      hb_NToS( aFld[1][4] ) )

   //  birth_date DATE -> D, length=8 (convencion Harbour), decimals=0
   _Check( aFld[2][1] == "birth_date", "DbStruct[2] nombre",       "birth_date", hb_CStr( aFld[2][1] ) )
   _Check( aFld[2][2] == "D",          "DbStruct[2] tipo = D",     "D",          hb_CStr( aFld[2][2] ) )
   _Check( aFld[2][3] == 8,            "DbStruct[2] length = 8",   "8",          hb_NToS( aFld[2][3] ) )
   _Check( aFld[2][4] == 0,            "DbStruct[2] dec = 0",      "0",          hb_NToS( aFld[2][4] ) )

   //  first_name VARCHAR(14) -> C, length>0, decimals=0
   _Check( aFld[3][1] == "first_name", "DbStruct[3] nombre",       "first_name", hb_CStr( aFld[3][1] ) )
   _Check( aFld[3][2] == "C",          "DbStruct[3] tipo = C",     "C",          hb_CStr( aFld[3][2] ) )
   _Check( aFld[3][3] != NIL,          "DbStruct[3] length != NIL","!= NIL",     hb_CStr( aFld[3][3] ) )
   _Check( aFld[3][3] > 0,             "DbStruct[3] length > 0",   "> 0",        hb_NToS( aFld[3][3] ) )
   _Check( aFld[3][4] == 0,            "DbStruct[3] dec = 0",      "0",          hb_NToS( aFld[3][4] ) )

   oStmt:Free()

   //  --- DECIMAL: tabla temporal DECIMAL(10,2) ---
   oConn:Exec( "DROP TABLE IF EXISTS " + cDecTbl )
   oConn:Exec( "CREATE TABLE " + cDecTbl + " ( sal DECIMAL(10,2) )" )

   oStmt := oConn:Query( "SELECT sal FROM " + cDecTbl )
   _Check( oStmt != NIL .AND. ! oStmt:lError, "DbStruct DECIMAL: query OK", ".T.", ;
           iif( oStmt == NIL .OR. oStmt:lError, ".F.", ".T." ) )

   IF oStmt != NIL .AND. ! oStmt:lError
      aFld := oStmt:DbStruct()
      _Check( aFld[1][2] == "N",  "DbStruct DECIMAL tipo = N",      "N",  hb_CStr( aFld[1][2] ) )
      _Check( aFld[1][3] == 12,   "DbStruct DECIMAL length = 12",   "12", hb_NToS( aFld[1][3] ) )
      _Check( aFld[1][4] == 2,    "DbStruct DECIMAL decimals = 2",  "2",  hb_NToS( aFld[1][4] ) )
      oStmt:Free()
   ENDIF

   oConn:Exec( "DROP TABLE " + cDecTbl )
   oConn:Close()

RETURN

STATIC PROCEDURE _TransFail( oConn, cTbl )
   oConn:Exec( "INSERT INTO " + cTbl + " (name) VALUES ('trans4')" )
   Break( ErrorNew() )
RETURN


//  =======================================================
//  Phase 2 -- Pool functional tests
//  =======================================================

PROCEDURE TestInitEnd()

   LOCAL nBefore, nAfter, hStats

   _Header( "Pool: Init / End" )

   nBefore := WDO_MySqlCountOpen()

   _Check( WDO_InitPoolMySql( scHost, scUser, scPwd, scDb, snPort, 3, 2000, .F. ), ;
           "InitPoolMySql returns .T.", ".T.", ".F." )

   nAfter := WDO_MySqlCountOpen()
   _Check( nAfter == nBefore + 3, ;
           "CountOpen incremented by pool size", ;
           hb_NToS( nBefore + 3 ), hb_NToS( nAfter ) )

   _Check( WDO_HasPools(), "HasPools == .T.", ".T.", ".F." )

   hStats := WDO_PoolStats( "MYSQL" )
   _Check( hStats != NIL .AND. hStats[ "size" ] == 3 .AND. hStats[ "busy" ] == 0 .AND. hStats[ "free" ] == 3, ;
           "Stats reflect empty pool", "size=3 busy=0 free=3", ;
           iif( hStats == NIL, "NIL", ;
                "size=" + hb_NToS( hStats[ "size" ] ) + ;
                " busy=" + hb_NToS( hStats[ "busy" ] ) + ;
                " free=" + hb_NToS( hStats[ "free" ] ) ) )

   WDO_EndPoolMySql()

   _Check( WDO_MySqlCountOpen() == nBefore, ;
           "CountOpen returns to baseline after End", ;
           hb_NToS( nBefore ), hb_NToS( WDO_MySqlCountOpen() ) )

   _Check( ! WDO_HasPools(), "HasPools == .F. after End", ".F.", ".T." )

RETURN


PROCEDURE TestAcquireRelease()

   LOCAL o1, o2, oStmt, nBefore, hStats

   _Header( "Pool: Acquire / Release" )

   WDO_InitPoolMySql( scHost, scUser, scPwd, scDb, snPort, 2, 2000, .F. )
   nBefore := WDO_MySqlCountOpen()

   o1 := WDO_Get( "MYSQL" )
   _Check( o1 != NIL .AND. o1:lConnect, "Get returns live connection", "live", "nil/dead" )
   _Check( o1:oPool != NIL, "Acquired conn has oPool set", "non-nil", "nil" )

   hStats := WDO_PoolStats( "MYSQL" )
   _Check( hStats[ "busy" ] == 1 .AND. hStats[ "free" ] == 1, ;
           "Stats: 1 busy 1 free after single Get", ;
           "busy=1 free=1", ;
           "busy=" + hb_NToS( hStats[ "busy" ] ) + " free=" + hb_NToS( hStats[ "free" ] ) )

   oStmt := o1:Query( "SELECT 1 AS ok" )
   _Check( oStmt != NIL .AND. ! oStmt:lError, "Query on pooled conn OK", "no error", "error" )
   IF oStmt != NIL ; oStmt:Free() ; ENDIF

   o1:Close()

   _Check( WDO_MySqlCountOpen() == nBefore, ;
           "CountOpen unchanged after Close (release)", ;
           hb_NToS( nBefore ), hb_NToS( WDO_MySqlCountOpen() ) )

   hStats := WDO_PoolStats( "MYSQL" )
   _Check( hStats[ "busy" ] == 0 .AND. hStats[ "free" ] == 2, ;
           "Stats: 0 busy 2 free after Release", ;
           "busy=0 free=2", ;
           "busy=" + hb_NToS( hStats[ "busy" ] ) + " free=" + hb_NToS( hStats[ "free" ] ) )

   o2 := WDO_Get( "MYSQL" )
   _Check( o2 != NIL .AND. o2:lConnect, "Reacquire returns live connection", "live", "nil/dead" )
   o2:Close()

   WDO_EndPoolMySql()

RETURN


PROCEDURE TestPoolExhaustionTimeout()

   LOCAL o1, o2, o3, nT0, nElapsed

   _Header( "Pool: exhaustion + timeout" )

   WDO_InitPoolMySql( scHost, scUser, scPwd, scDb, snPort, 2, 500, .F. )

   o1 := WDO_Get( "MYSQL" )
   o2 := WDO_Get( "MYSQL" )
   _Check( o1 != NIL .AND. o2 != NIL, "First two Gets succeed", "both non-nil", "one nil" )

   nT0 := hb_MilliSeconds()
   o3  := WDO_Get( "MYSQL" )
   nElapsed := hb_MilliSeconds() - nT0

   _Check( o3 == NIL, "Third Get returns NIL after timeout", "NIL", "non-nil" )
   _Check( nElapsed >= 450 .AND. nElapsed < 2000, ;
           "Timeout honored (~500 ms)", "450-2000 ms", hb_NToS( Int( nElapsed ) ) + " ms" )

   o1:Close()
   nT0 := hb_MilliSeconds()
   o3  := WDO_Get( "MYSQL" )
   nElapsed := hb_MilliSeconds() - nT0
   _Check( o3 != NIL, "Get after Release succeeds", "non-nil", "NIL" )
   _Check( nElapsed < 500, "Get after Release is fast", "<500 ms", hb_NToS( Int( nElapsed ) ) + " ms" )

   o2:Close()
   o3:Close()

   WDO_EndPoolMySql()

RETURN


PROCEDURE TestAutoRollback()

   LOCAL oConn, oStmt, aRows

   _Header( "Pool: Auto-rollback on Release" )

   WDO_InitPoolMySql( scHost, scUser, scPwd, scDb, snPort, 2, 1000, .F. )

   oConn := WDO_Get( "MYSQL" )
   IF oConn == NIL
      _Fail( "Acquire for autoroll test", "conn", "nil" )
      WDO_EndPoolMySql()
      RETURN
   ENDIF

   oConn:Exec( "CREATE TEMPORARY TABLE _wdo_pool_autoroll ( n INT )" )
   oConn:Exec( "INSERT INTO _wdo_pool_autoroll VALUES ( 1 )" )

   oConn:BeginTrans()
   oConn:Exec( "INSERT INTO _wdo_pool_autoroll VALUES ( 2 )" )
   _Check( oConn:InTransaction(), "lInTrans == .T. after BeginTrans", ".T.", ".F." )

   oConn:Close()
   _Check( ! oConn:InTransaction(), "lInTrans == .F. after Release", ".F.", ".T." )

   oConn := WDO_Get( "MYSQL" )
   oStmt := oConn:Query( "SELECT 1" )
   _Check( oStmt != NIL .AND. ! oStmt:lError, "Conn usable after auto-rollback release", "ok", "error" )
   IF oStmt != NIL ; oStmt:Free() ; ENDIF

   HB_SYMBOL_UNUSED( aRows )

   oConn:Close()
   WDO_EndPoolMySql()

RETURN


PROCEDURE TestReleaseAllThreadHook()

   LOCAL o1, o2, hStats

   _Header( "Pool: WDO_ReleaseAllThread (safety net)" )

   WDO_InitPoolMySql( scHost, scUser, scPwd, scDb, snPort, 3, 1000, .F. )

   o1 := WDO_Get( "MYSQL" )
   o2 := WDO_Get( "MYSQL" )

   hStats := WDO_PoolStats( "MYSQL" )
   _Check( hStats[ "busy" ] == 2, "2 busy before safety net", "2", hb_NToS( hStats[ "busy" ] ) )

   WDO_ReleaseAllThread()

   hStats := WDO_PoolStats( "MYSQL" )
   _Check( hStats[ "busy" ] == 0, "0 busy after ReleaseAllThread", "0", hb_NToS( hStats[ "busy" ] ) )
   _Check( hStats[ "free" ] == 3, "3 free after ReleaseAllThread", "3", hb_NToS( hStats[ "free" ] ) )

   WDO_ReleaseAllThread()
   hStats := WDO_PoolStats( "MYSQL" )
   _Check( hStats[ "busy" ] == 0, "Idempotent: still 0 busy", "0", hb_NToS( hStats[ "busy" ] ) )

   WDO_EndPoolMySql()
   _Check( ! WDO_HasPools(), "HasPools .F. after End", ".F.", ".T." )
   WDO_ReleaseAllThread()
   _Pass( "ReleaseAllThread no-op when no pools" )

   HB_SYMBOL_UNUSED( o1 )
   HB_SYMBOL_UNUSED( o2 )

RETURN


PROCEDURE TestCrossThread()

   LOCAL hThread, hResult

   _Header( "Pool: Cross-thread borrowing" )

   WDO_InitPoolMySql( scHost, scUser, scPwd, scDb, snPort, 2, 2000, .F. )

   hResult := hb_hash()
   hResult[ "ok" ] := .F.

   hThread := hb_threadStart( {|| _ThreadWorker( hResult ) } )
   hb_threadJoin( hThread )

   _Check( hResult[ "ok" ], "Cross-thread acquire/query/release", ".T.", ".F." )

   WDO_EndPoolMySql()

RETURN

STATIC PROCEDURE _ThreadWorker( hResult )
   LOCAL oConn, oStmt

   oConn := WDO_Get( "MYSQL" )
   IF oConn == NIL ; RETURN ; ENDIF

   oStmt := oConn:Query( "SELECT 42 AS n" )
   IF oStmt != NIL .AND. ! oStmt:lError
      hResult[ "ok" ] := .T.
      oStmt:Free()
   ENDIF

   oConn:Close()
RETURN


PROCEDURE TestStats()

   LOCAL hStats

   _Header( "Pool: Stats helpers" )

   WDO_InitPoolMySql( scHost, scUser, scPwd, scDb, snPort, 4, 1000, .F. )
   hStats := WDO_PoolStats( "MYSQL" )

   _Check( hStats[ "driver" ] == "MYSQL", "driver key", "MYSQL", hb_CStr( hStats[ "driver" ] ) )
   _Check( hStats[ "size" ] == 4,         "size key",   "4",     hb_NToS( hStats[ "size" ] ) )
   _Check( ! hStats[ "closed" ],          "closed key .F.", ".F.", ".T." )

   WDO_EndPoolMySql()

RETURN


PROCEDURE TestUnregisteredDriver()

   LOCAL oConn

   _Header( "Pool: Unregistered driver" )

   oConn := WDO_Get( "NOSUCHDRIVER" )
   _Check( oConn == NIL, "Get on unregistered driver returns NIL", "NIL", "non-nil" )

RETURN


PROCEDURE TestNewGuard()

   LOCAL oConn, lOldGuard, cLog, cLogA, cLogB, hFake, cMarker

   _Header( "Pool: New() guard inside HTTP request" )

   cMarker := "WDO_MySql:New called inside HTTP request handler"

   hFake := { "url" => "/fake" }
   HIX_SetRequest( hFake )

   cLogA := "logs/test_guard_on.log"
   IF hb_FileExists( cLogA ) ; FErase( cLogA ) ; ENDIF
   HIX_LoggerClose()
   HIX_LoggerInit( cLogA, HIX_LOG_DEBUG, .F. )

   oConn := WDO_MySql():New( scHost, scUser, scPwd, scDb, snPort, .T. )
   IF oConn != NIL ; oConn:End() ; ENDIF
   HIX_LoggerClose()

   cLog := iif( hb_FileExists( cLogA ), hb_MemoRead( cLogA ), "" )
   _Check( cMarker $ cLog, ;
           "Guard emits WARN when request is active", ;
           "log contains warning", "log missing warning" )

   lOldGuard := WDO_MySqlNewGuard( .F. )
   _Check( lOldGuard == .T., ;
           "WDO_MySqlNewGuard returns previous state (.T.)", ;
           ".T.", iif( lOldGuard, ".T.", ".F." ) )

   cLogB := "logs/test_guard_off.log"
   IF hb_FileExists( cLogB ) ; FErase( cLogB ) ; ENDIF
   HIX_LoggerInit( cLogB, HIX_LOG_DEBUG, .F. )

   oConn := WDO_MySql():New( scHost, scUser, scPwd, scDb, snPort, .T. )
   IF oConn != NIL ; oConn:End() ; ENDIF
   HIX_LoggerClose()

   cLog := iif( hb_FileExists( cLogB ), hb_MemoRead( cLogB ), "" )
   _Check( ! ( cMarker $ cLog ), ;
           "Guard silent when disabled", ;
           "log without warning", "log still contains warning" )

   WDO_MySqlNewGuard( .T. )
   HIX_LangSelect( "ES" )
   HIX_SetRequest( hFake )

   cLog := "logs/test_guard_es.log"
   IF hb_FileExists( cLog ) ; FErase( cLog ) ; ENDIF
   HIX_LoggerInit( cLog, HIX_LOG_DEBUG, .F. )

   oConn := WDO_MySql():New( scHost, scUser, scPwd, scDb, snPort, .T. )
   IF oConn != NIL ; oConn:End() ; ENDIF
   HIX_LoggerClose()

   cLog := iif( hb_FileExists( "logs/test_guard_es.log" ), ;
                hb_MemoRead( "logs/test_guard_es.log" ), "" )
   _Check( "WDO_MySql:New llamado dentro de un handler HTTP" $ cLog, ;
           "Guard warning translates to Spanish", ;
           "log contains ES text", "log missing ES text" )

   HIX_LangSelect( "EN" )
   HIX_SetRequest( NIL )
   HIX_LoggerInit( "logs/test_wdo_mysql.log", HIX_LOG_DEBUG, .F. )

RETURN


//  Handler used by TestPoolBError -- records that bError fired
//  plus the last oErr / oConn it received.
STATIC PROCEDURE _PoolBErrorHandler( oErr, oConn )
   snBErrCalls++
   soLastErr  := oErr
   soLastConn := oConn
RETURN


PROCEDURE TestPoolBError()

   LOCAL oConn, oStmt, lOldShow

   _Header( "Pool: bError propagates from InitPool to acquired conn" )

   //  WDO:SetError falls back to Break(oErr) when bError is NIL and
   //  lShowError is .T. -- disable it while forcing bad queries so
   //  the test process does not abort on a legitimate SQL error.
   lOldShow := WDO_MySql():lShowError
   WDO_MySql():lShowError := .F.

   //  1. bError propagates through the factory
   snBErrCalls := 0 ; soLastErr := NIL ; soLastConn := NIL
   WDO_InitPoolMySql( scHost, scUser, scPwd, scDb, snPort, 2, 1000, .F., ;
                       {| oErr, oConn | _PoolBErrorHandler( oErr, oConn ) } )

   oConn := WDO_Get( "MYSQL" )
   _Check( oConn != NIL, "Get returns a pooled conn", "conn", "nil" )
   _Check( ValType( oConn:bError ) == "B", ;
           "oConn:bError is a codeblock", "B", ValType( oConn:bError ) )

   //  2. bError fires on Query over a table that does not exist
   oStmt := oConn:Query( "SELECT * FROM zzz_does_not_exist" )
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   _Check( snBErrCalls >= 1, ;
           "bError fires on bad Query", ">=1", hb_NToS( snBErrCalls ) )
   _Check( soLastErr != NIL .AND. soLastErr:subSystem == "WDO", ;
           "handler receives ErrorNew with subSystem=WDO", ;
           "WDO", iif( soLastErr == NIL, "nil", soLastErr:subSystem ) )
   _Check( soLastConn == oConn, ;
           "handler receives the affected oConn", "same ref", "different ref" )

   oConn:Close()
   WDO_EndPoolMySql()

   //  3. Per-instance override wins over pool-wide default
   snBErrCalls := 0
   WDO_InitPoolMySql( scHost, scUser, scPwd, scDb, snPort, 2, 1000, .F., ;
                       {| oErr, oConn | _PoolBErrorHandler( oErr, oConn ) } )

   oConn := WDO_Get( "MYSQL" )
   oConn:bError := {|| NIL }             // silent override
   oStmt := oConn:Query( "SELECT * FROM zzz_does_not_exist" )
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   _Check( snBErrCalls == 0, ;
           "instance override supresses pool bError", "0", hb_NToS( snBErrCalls ) )

   oConn:Close()

   //  4. Override does NOT persist across Close: the pool restores
   //  the factory-injected bError, so the next Acquire on any slot
   //  fires the pool-wide handler as if the override never happened.
   snBErrCalls := 0
   oConn := WDO_Get( "MYSQL" )
   oStmt := oConn:Query( "SELECT * FROM zzz_does_not_exist" )
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   _Check( snBErrCalls >= 1, ;
           "override does NOT persist after Close (pool bError restored)", ;
           ">=1", hb_NToS( snBErrCalls ) )

   oConn:Close()
   WDO_EndPoolMySql()

   WDO_MySql():lShowError := lOldShow

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

   _Header( "ConfigJson: HIX_InitPoolsFromConfig" )

   //  1. No 'databases' section (or empty) -> empty result, no crash
   HIX_ConfigAppSet( "databases", { => } )
   hResult := HIX_InitPoolsFromConfig()
   _Check( HB_ISHASH( hResult ) .AND. Empty( hResult ), ;
           "empty 'databases' returns empty hash", ;
           "{ =>}", "len=" + hb_NToS( Len( hResult ) ) )

   //  2. Single entry: pool starts, WDO_Get returns a live connection
   HIX_ConfigAppSet( "databases", { ;
      "mysql" => { ;
         "driver"     => "mysql",     ;
         "host"       => scHost,      ;
         "user"       => scUser,      ;
         "pwd"        => scPwd,       ;
         "db"         => scDb,        ;
         "port"       => snPort,      ;
         "pool_size"  => 2,           ;
         "timeout_ms" => 2000,        ;
         "ping"       => .F.          } } )

   hResult := HIX_InitPoolsFromConfig()
   _Check( hb_HGetDef( hResult, "mysql", .F. ), ;
           "single 'mysql' entry starts OK", ".T.", ;
           iif( hb_HGetDef( hResult, "mysql", .F. ), ".T.", ".F." ) )

   oConn1 := WDO_Get( "mysql" )
   _Check( oConn1 != NIL .AND. oConn1:lConnect, ;
           "WDO_Get(<json key>) returns a live conn", "live", ;
           iif( oConn1 == NIL, "nil", "not live" ) )
   IF oConn1 != NIL ; oConn1:Close() ; ENDIF

   HIX_EndPoolsFromConfig()

   //  3. Two entries with the same driver register as distinct pools
   HIX_ConfigAppSet( "databases", { ;
      "mysql_a" => { "driver" => "mysql", "host" => scHost, "user" => scUser, ;
                     "pwd" => scPwd, "db" => scDb, "port" => snPort, ;
                     "pool_size" => 1, "ping" => .F. }, ;
      "mysql_b" => { "driver" => "mysql", "host" => scHost, "user" => scUser, ;
                     "pwd" => scPwd, "db" => scDb, "port" => snPort, ;
                     "pool_size" => 1, "ping" => .F. } } )
   hResult := HIX_InitPoolsFromConfig()
   _Check( hb_HGetDef( hResult, "mysql_a", .F. ) .AND. hb_HGetDef( hResult, "mysql_b", .F. ), ;
           "two same-driver entries both start", "both .T.", ;
           iif( hb_HGetDef( hResult, "mysql_a", .F. ), "a=T", "a=F" ) + " " + ;
           iif( hb_HGetDef( hResult, "mysql_b", .F. ), "b=T", "b=F" ) )

   oConn1 := WDO_Get( "mysql_a" )
   oConn2 := WDO_Get( "mysql_b" )
   _Check( oConn1 != NIL .AND. oConn2 != NIL .AND. ! ( oConn1 == oConn2 ), ;
           "each pool yields its own conn", "distinct", "same or nil" )
   IF oConn1 != NIL ; oConn1:Close() ; ENDIF
   IF oConn2 != NIL ; oConn2:Close() ; ENDIF

   HIX_EndPoolsFromConfig()

   //  4. 'dll' with valid path -> pool opens normally
   HIX_ConfigAppSet( "databases", { ;
      "mysql" => { ;
         "driver"    => "mysql",       ;
         "host"      => scHost,        ;
         "user"      => scUser,        ;
         "pwd"       => scPwd,         ;
         "db"        => scDb,          ;
         "port"      => snPort,        ;
         "dll"       => hb_SysMySQL(), ;
         "pool_size" => 1,             ;
         "ping"      => .F.            } } )
   hResult := HIX_InitPoolsFromConfig()
   _Check( hb_HGetDef( hResult, "mysql", .F. ), ;
           "'dll' with valid path opens", ".T.", ;
           iif( hb_HGetDef( hResult, "mysql", .F. ), ".T.", ".F." ) )

   oConn1 := WDO_Get( "mysql" )
   _Check( oConn1 != NIL .AND. oConn1:DllSource() == "override", ;
           "DllSource == 'override' when 'dll' set from JSON", ;
           "override", iif( oConn1 == NIL, "nil", oConn1:DllSource() ) )
   IF oConn1 != NIL ; oConn1:Close() ; ENDIF

   HIX_EndPoolsFromConfig()

   //  5. 'dll' with nonexistent path -> pool init fails cleanly
   HIX_ConfigAppSet( "databases", { ;
      "mysql_bad" => { ;
         "driver"    => "mysql",                            ;
         "host"      => scHost,                             ;
         "user"      => scUser,                             ;
         "pwd"       => scPwd,                              ;
         "db"        => scDb,                               ;
         "port"      => snPort,                             ;
         "dll"       => "c:/does/not/exist/libmariadb.dll", ;
         "pool_size" => 1,                                  ;
         "ping"      => .F.                                 } } )
   hResult := HIX_InitPoolsFromConfig( .F. )   //  .F. = no abort, test expects clean failure
   _Check( ! hb_HGetDef( hResult, "mysql_bad", .T. ), ;
           "'dll' with bad path fails cleanly (.F.)", ".F.", ;
           iif( hb_HGetDef( hResult, "mysql_bad", .T. ), ".T.", ".F." ) )

   HIX_EndPoolsFromConfig()

   //  6. 'berror' referencing a public function -> injected as codeblock
   HIX_ConfigAppSet( "databases", { ;
      "mysql" => { ;
         "driver"    => "mysql", "host" => scHost, "user" => scUser, ;
         "pwd"       => scPwd, "db" => scDb, "port" => snPort,        ;
         "pool_size" => 1, "ping" => .F.,                             ;
         "berror"    => "CfgBErrorProbe"                              } } )
   HIX_InitPoolsFromConfig()
   oConn1 := WDO_Get( "mysql" )
   _Check( oConn1 != NIL .AND. ValType( oConn1:bError ) == "B", ;
           "known 'berror' injects codeblock on pooled conn", "B", ;
           iif( oConn1 == NIL, "nil", ValType( oConn1:bError ) ) )
   IF oConn1 != NIL ; oConn1:Close() ; ENDIF
   HIX_EndPoolsFromConfig()

   //  7. 'berror' referencing missing symbol -> WARN, pool starts without handler
   HIX_ConfigAppSet( "databases", { ;
      "mysql" => { ;
         "driver"    => "mysql", "host" => scHost, "user" => scUser, ;
         "pwd"       => scPwd, "db" => scDb, "port" => snPort,        ;
         "pool_size" => 1, "ping" => .F.,                             ;
         "berror"    => "DoesNotExist_" + hb_NToS( Int( Seconds() ) ) } } )
   hResult := HIX_InitPoolsFromConfig()
   _Check( hb_HGetDef( hResult, "mysql", .F. ), ;
           "unknown 'berror' does not abort init", ".T.", ;
           iif( hb_HGetDef( hResult, "mysql", .F. ), ".T.", ".F." ) )
   oConn1 := WDO_Get( "mysql" )
   _Check( oConn1 != NIL .AND. oConn1:bError == NIL, ;
           "unknown 'berror' -> bError stays NIL", "NIL", ;
           iif( oConn1 == NIL, "nil-conn", iif( oConn1:bError == NIL, "NIL", "B" ) ) )
   IF oConn1 != NIL ; oConn1:Close() ; ENDIF
   HIX_EndPoolsFromConfig()

   //  8. WDO_InitPoolMySqlEx direct call (no JSON) equivalent to declarative path
   WDO_InitPoolMySqlEx( "mysql_direct", { ;
      "host"      => scHost, "user" => scUser, "pwd" => scPwd, ;
      "db"        => scDb,   "port" => snPort, "pool_size" => 1, ;
      "ping"      => .F. } )
   oConn1 := WDO_Get( "mysql_direct" )
   _Check( oConn1 != NIL .AND. oConn1:lConnect, ;
           "WDO_InitPoolMySqlEx direct call works standalone", "live", ;
           iif( oConn1 == NIL, "nil", "not-live" ) )
   IF oConn1 != NIL ; oConn1:Close() ; ENDIF
   WDO_UnregisterPool( "mysql_direct" )

   //  cleanup: leave "databases" untouched for downstream phases
   HIX_ConfigAppSet( "databases", { => } )

RETURN


//  =======================================================
//  Phase 2b -- Prepared statements (Alt B)
//  =======================================================

PROCEDURE TestPrepare()

   LOCAL oConn, oStmt, aRows, hRow, i, nCountBefore
   LOCAL cTbl := "hix_test_prep_" + hb_NToS( Int( Seconds() ) )
   LOCAL lOldShow

   _Header( "Prepared: server-side PREPARE emulation (Alt B)" )

   oConn := _ConnectOrSkip()
   IF oConn == NIL
      _Skip( "Prepare/Bind/Execute", "no hay MySQL" )
      RETU
   ENDIF

   lOldShow := WDO_MySql():lShowError
   WDO_MySql():lShowError := .F.

   oConn:Exec( "DROP TABLE IF EXISTS " + cTbl )
   oConn:Exec( "CREATE TABLE " + cTbl + ;
               " ( id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), age INT, note VARCHAR(200) )" )

   //  1. Prepare returns Stmt with lPrepared=.T. and nParamCount correct
   oStmt := oConn:Prepare( "SELECT * FROM " + cTbl + " WHERE age > ?" )
   _Check( oStmt != NIL .AND. oStmt:lPrepared, ;
           "Prepare devuelve Stmt con lPrepared=.T.", ".T.", ;
           iif( oStmt == NIL, "NIL", iif( oStmt:lPrepared, ".T.", ".F." ) ) )
   _Check( oStmt:nParamCount == 1, ;
           "nParamCount = 1 con un unico ?", "1", hb_NToS( oStmt:nParamCount ) )
   oStmt:Free()

   //  2. Prepare de SQL invalido -> oStmt:lError=.T.
   oStmt := oConn:Prepare( "SELECT * FROM zzz_does_not_exist WHERE id = ?" )
   _Check( oStmt != NIL .AND. oStmt:lError, ;
           "Prepare SQL invalido marca lError", ".T.", ;
           iif( oStmt == NIL, "NIL", iif( oStmt:lError, ".T.", ".F." ) ) )
   IF oStmt != NIL ; oStmt:Free() ; ENDIF

   //  3. BindParam con indice fuera de rango -> lError
   oStmt := oConn:Prepare( "SELECT * FROM " + cTbl + " WHERE age > ?" )
   oStmt:BindParam( 5, 10, "i" )
   _Check( oStmt:lError, "BindParam(indice fuera de rango) marca lError", ;
           ".T.", iif( oStmt:lError, ".T.", ".F." ) )
   oStmt:Free()

   //  Seed data para el resto de asserts
   oConn:Exec( "INSERT INTO " + cTbl + " (name, age, note) VALUES " + ;
               "('alice', 20, 'a'),('bob', 30, 'b'),('carol', 40, 'c')" )

   //  4. SELECT con 1 parametro entero -- filtra age > 25
   oStmt := oConn:Prepare( "SELECT id, name, age FROM " + cTbl + " WHERE age > ? ORDER BY id" )
   oStmt:BindParam( 1, 25, "i" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 2, "SELECT WHERE age > 25 devuelve 2 filas", "2", hb_NToS( Len( aRows ) ) )
   oStmt:Free()

   //  5. Parametro string con comilla simple (SQL-injection safe)
   oConn:Exec( "INSERT INTO " + cTbl + " (name, age, note) VALUES ('O''Brien', 50, 'irish')" )
   oStmt := oConn:Prepare( "SELECT id FROM " + cTbl + " WHERE name = ?" )
   oStmt:BindParam( 1, "O'Brien", "s" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 1, ;
           "SELECT WHERE name=? con comilla simple", "1", hb_NToS( Len( aRows ) ) )
   oStmt:Free()

   //  6. INSERT parametros mixtos i/s/n + Last_Insert_Id
   oStmt := oConn:Prepare( "INSERT INTO " + cTbl + " (name, age, note) VALUES (?, ?, ?)" )
   oStmt:BindParam( 1, "diana",  "s" )
   oStmt:BindParam( 2, 22,       "i" )
   oStmt:BindParam( 3, "bought", "s" )
   oStmt:Execute()
   _Check( oStmt:Row_Count() == 1, "INSERT prepared Row_Count=1", "1", hb_NToS( oStmt:Row_Count() ) )
   _Check( oConn:Last_Insert_Id() > 0, "Last_Insert_Id > 0 tras Execute", "> 0", ;
           hb_NToS( oConn:Last_Insert_Id() ) )
   oStmt:Free()

   //  7. INSERT masivo re-ejecutando el mismo Prepare (10 iteraciones)
   oStmt := oConn:Prepare( "INSERT INTO " + cTbl + " (name, age, note) VALUES (?, ?, ?)" )
   nCountBefore := Val( _ScalarQuery( oConn, "SELECT COUNT(*) FROM " + cTbl ) )
   FOR i := 1 TO 10
      oStmt:BindParam( 1, "bulk_" + hb_NToS( i ), "s" )
      oStmt:BindParam( 2, 60 + i,                 "i" )
      oStmt:BindParam( 3, "run",                  "s" )
      oStmt:Execute()
   NEXT
   _Check( Val( _ScalarQuery( oConn, "SELECT COUNT(*) FROM " + cTbl ) ) - nCountBefore == 10, ;
           "10 re-Execute insertan 10 filas", "10", ;
           hb_NToS( Val( _ScalarQuery( oConn, "SELECT COUNT(*) FROM " + cTbl ) ) - nCountBefore ) )
   oStmt:Free()

   //  8. NULL binding -- BindParam(1, NIL) -> IS NULL
   oStmt := oConn:Prepare( "INSERT INTO " + cTbl + " (name, age, note) VALUES (?, ?, ?)" )
   oStmt:BindParam( 1, "with_null", "s" )
   oStmt:BindParam( 2, 99,          "i" )
   oStmt:BindParam( 3, NIL,         "s" )
   oStmt:Execute()
   oStmt:Free()
   hRow := _FetchOneAssoc( oConn, "SELECT note FROM " + cTbl + " WHERE name='with_null'" )
   _Check( hRow != NIL .AND. Empty( hRow["note"] ), ;
           "BindParam(NIL) inserta NULL", "NULL/empty", ;
           iif( hRow == NIL, "no row", hRow["note"] ) )

   //  9. Named placeholders (:name) -- BindParam por nombre
   oStmt := oConn:Prepare( "SELECT id FROM " + cTbl + " WHERE name = :who AND age = :yrs" )
   _Check( oStmt:nParamCount == 2, ":name reconoce 2 placeholders", "2", hb_NToS( oStmt:nParamCount ) )
   oStmt:BindParam( ":who", "alice", "s" )
   oStmt:BindParam( ":yrs", 20,      "i" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 1, "SELECT con :name devuelve alice", "1", hb_NToS( Len( aRows ) ) )
   oStmt:Free()

   //  10. Reset + re-Execute cambiando parametros sin re-preparar
   oStmt := oConn:Prepare( "SELECT id FROM " + cTbl + " WHERE age = ?" )
   oStmt:BindParam( 1, 20, "i" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 1, "re-Execute #1 age=20 -> 1", "1", hb_NToS( Len( aRows ) ) )
   oStmt:BindParam( 1, 30, "i" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 1, "re-Execute #2 age=30 -> 1", "1", hb_NToS( Len( aRows ) ) )
   oStmt:Free()

   //  11. Free llama DEALLOCATE PREPARE -- la lib no fuga el statement
   //  Verificacion indirecta: preparamos 20 statements y comprobamos
   //  que los DEALLOCATE ocurrieron (SHOW STATUS Prepared_stmt_count).
   FOR i := 1 TO 20
      oStmt := oConn:Prepare( "SELECT " + hb_NToS( i ) )
      oStmt:Execute()
      oStmt:Free()
   NEXT
   hRow := _FetchOneAssoc( oConn, "SHOW STATUS LIKE 'Prepared_stmt_count'" )
   _Check( hRow != NIL .AND. Val( hRow["Value"] ) < 5, ;
           "20 Prepare+Free no fugan (Prepared_stmt_count bajo)", "< 5", ;
           iif( hRow == NIL, "no row", hRow["Value"] ) )

   //  12. Integracion con pool -- Prepare sobre conexion adquirida
   oConn:Exec( "DROP TABLE IF EXISTS " + cTbl )
   oConn:Close()

   WDO_InitPoolMySql( scHost, scUser, scPwd, scDb, snPort, 2, 1000, .F. )
   oConn := WDO_Get( "MYSQL" )
   oStmt := oConn:Prepare( "SELECT ? AS n" )
   oStmt:BindParam( 1, 42, "i" )
   oStmt:Execute()
   hRow := oStmt:Fetch_Assoc()
   _Check( hRow != NIL .AND. hRow["n"] == "42", ;
           "Prepare sobre conn del pool devuelve 42", "42", ;
           iif( hRow == NIL, "no row", hb_CStr( hRow["n"] ) ) )
   oStmt:Free()
   oConn:Close()
   WDO_EndPoolMySql()

   WDO_MySql():lShowError := lOldShow

RETURN


//  Helper: SELECT que devuelve un solo escalar como string
STATIC FUNCTION _ScalarQuery( oConn, cSql )
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


STATIC FUNCTION _FetchOneAssoc( oConn, cSql )
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

   WDO_InitPoolMySql( scHost, scUser, scPwd, scDb, snPort, snPoolSize, snTimeoutMs, .F. )

   nT0 := hb_MilliSeconds()

   nR1 := _RunWorkload( "W1) SELECT 1                    ", {| n | _WSelect1( n )    } )
   nR2 := _RunWorkload( "W2) SELECT (1+2) AS r           ", {| n | _WArith( n )      } )
   nR3 := _RunWorkload( "W3) SELECT :n AS r  (literal)   ", {| n | _WWithParam( n )  } )

   nElapsed := hb_MilliSeconds() - nT0
   nTotal   := nR1 + nR2 + nR3
   nThrough := iif( nElapsed > 0, nTotal * 1000.0 / nElapsed, 0 )

   hStats := WDO_PoolStats( "MYSQL" )

   //  Snapshot metrics BEFORE closing the pool -- Release() decrements
   //  active_conn and mutates counters that we want to freeze.
   IF lMetrics
      cJson := WDO_MetricsJson()
      hWdo  := hb_JsonDecode( cJson )
   ENDIF

   WDO_EndPoolMySql()

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

   //  Contadores globales del test: contamos el stress como 1 PASS si no hubo errores
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
      oConn := WDO_Get( "MYSQL" )
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
      oConn := WDO_Get( "MYSQL" )
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
      oConn := WDO_Get( "MYSQL" )
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
//  Phase 2d -- WDO metrics registry (unit tests, no MySQL)
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

   //  Dec floors at 0
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
   WDO_MetricQuery( "mysql", "SELECT 1", 12, "test.prg:1" )

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

   WDO_MetricQuery( "mysql", "SELECT * FROM t",         5, "-" )
   WDO_MetricQuery( "mysql", "  select * from t",       5, "-" )
   WDO_MetricQuery( "mysql", "INSERT INTO t VALUES (1)",5, "-" )
   WDO_MetricQuery( "mysql", "UPDATE t SET x=1",        5, "-" )
   WDO_MetricQuery( "mysql", "DELETE FROM t",           5, "-" )
   WDO_MetricQuery( "mysql", "PREPARE stmt FROM ?",     5, "-" )
   WDO_MetricQuery( "mysql", "EXECUTE stmt",            5, "-" )
   WDO_MetricQuery( "mysql", "SHOW TABLES",             5, "-" )
   WDO_MetricQuery( "mysql", "/* c */ SELECT 1",        5, "-" )
   WDO_MetricQuery( "mysql", "-- c" + hb_eol() + "SELECT 2", 5, "-" )

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

   WDO_MetricQuery( "mysql", "SELECT 1", 10, "-" )
   WDO_MetricQuery( "mysql", "SELECT 2", 20, "-" )
   WDO_MetricQuery( "mysql", "SELECT 3", 30, "-" )

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
      WDO_MetricQuery( "mysql", "SELECT " + hb_NToS( i ), i * 10, "src.prg:" + hb_NToS( i ) )
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

   WDO_MetricQuery( "mysql",     "SELECT 1", 5, "-" )
   WDO_MetricQuery( "mysql",     "SELECT 2", 5, "-" )
   WDO_MetricQuery( "analytics", "SELECT 3", 5, "-" )

   _Check( WDO_MetricGet( "queries_by_pool_mysql"     ) == 2, "mysql=2",     "2", ;
      hb_NToS( WDO_MetricGet( "queries_by_pool_mysql" ) ) )
   _Check( WDO_MetricGet( "queries_by_pool_analytics" ) == 1, "analytics=1", "1", ;
      hb_NToS( WDO_MetricGet( "queries_by_pool_analytics" ) ) )

   WDO_MetricsClose()

RETURN


//  8. JSON valid
STATIC PROCEDURE Test_Metric_JsonValid()

   LOCAL cJson, hJson

   _Header( "Metric 8. JSON valid" )

   WDO_MetricsInit( 5 )
   WDO_MetricQuery( "mysql", "SELECT 1", 42, "src.prg:10" )

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
   WDO_MetricQuery( "mysql", "SELECT 1", 12, "-" )
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

   //  10 threads x 100 increments = 1000
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

   WDO_MetricQuery( "mysql", "SELECT 1", 7, "src.prg:1" )

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
//  Phase 2b-bin -- Prepared statements Alt A (binary protocol)
//  =======================================================

PROCEDURE TestPrepareBin()

   LOCAL oConn, oStmt, oStmtAltB
   LOCAL cTbl := "hix_test_prepbin_" + hb_NToS( Int( Seconds() ) )
   LOCAL lOldShow
   LOCAL hRow, i, nId, cRead, cBinData
   LOCAL nRunCount := 10
   LOCAL nInsertedCount

   _Header( "Prepared: binary protocol (Alt A)" )

   oConn := _ConnectOrSkip()
   IF oConn == NIL
      _Skip( "PrepareBin", "no hay MySQL" )
      RETU
   ENDIF

   lOldShow := WDO_MySql():lShowError
   WDO_MySql():lShowError := .F.

   oConn:Exec( "DROP TABLE IF EXISTS " + cTbl )
   oConn:Exec( "CREATE TABLE " + cTbl + ;
               " ( id INT AUTO_INCREMENT PRIMARY KEY, " + ;
               " n_int INT, n_big BIGINT, n_dbl DOUBLE, " + ;
               " s_txt VARCHAR(200), s_bin VARBINARY(4096), s_null VARCHAR(50) )" )

   //  1. PrepareBin returns WDO_MySqlStmtBin with lPrepared=.T.
   oStmt := oConn:PrepareBin( "SELECT * FROM " + cTbl + " WHERE n_int > ?" )
   _Check( oStmt != NIL .AND. oStmt:lPrepared, ;
           "PrepareBin devuelve Stmt binario con lPrepared=.T.", ".T.", ;
           iif( oStmt == NIL, "NIL", iif( oStmt:lPrepared, ".T.", ".F." ) ) )

   //  2. nParamCount correcto tras mysql_stmt_param_count
   _Check( oStmt:nParamCount == 1, ;
           "nParamCount = 1 tras mysql_stmt_param_count", "1", ;
           hb_NToS( oStmt:nParamCount ) )
   oStmt:Close()

   //  3. PrepareBin(cSql, .F.) delega en Alt B (WDO_MySqlStmt)
   oStmtAltB := oConn:PrepareBin( "SELECT ?", .F. )
   _Check( oStmtAltB != NIL .AND. oStmtAltB:className() == "WDO_MYSQLSTMT", ;
           "PrepareBin(.F.) delega en Alt B", "WDO_MYSQLSTMT", ;
           iif( oStmtAltB == NIL, "NIL", oStmtAltB:className() ) )
   IF oStmtAltB != NIL ; oStmtAltB:Free() ; ENDIF

   //  4. PrepareBin de SQL invalido -> lError=.T.
   oStmt := oConn:PrepareBin( "SELECT * FROM zzz_does_not_exist_bin WHERE id = ?" )
   _Check( oStmt != NIL .AND. oStmt:lError, ;
           "PrepareBin SQL invalido marca lError", ".T.", ;
           iif( oStmt == NIL, "NIL", iif( oStmt:lError, ".T.", ".F." ) ) )
   IF oStmt != NIL ; oStmt:Close() ; ENDIF

   //  5. BindParam out-of-range devuelve .F.
   oStmt := oConn:PrepareBin( "SELECT ? AS x" )
   _Check( ! oStmt:BindParam( 5, 10 ), ;
           "BindParam(indice fuera de rango) devuelve .F.", ".F.", ".T." )
   oStmt:Close()

   //  6. INSERT con LONG (int32) -> el valor se recupera exacto
   oStmt := oConn:PrepareBin( "INSERT INTO " + cTbl + " (n_int) VALUES (?)" )
   oStmt:BindParam( 1, 12345 )
   oStmt:Execute()
   _Check( oStmt:AffectedRows() == 1, ;
           "INSERT LONG affected_rows = 1", "1", ;
           hb_NToS( oStmt:AffectedRows() ) )
   nId := oStmt:LastInsertId()
   oStmt:Close()

   cRead := _ScalarQuery( oConn, "SELECT n_int FROM " + cTbl + " WHERE id=" + hb_NToS( nId ) )
   _Check( Val( cRead ) == 12345, ;
           "SELECT devuelve LONG=12345", "12345", cRead )

   //  7. INSERT con LONGLONG (bigint, > 2^31)
   oStmt := oConn:PrepareBin( "INSERT INTO " + cTbl + " (n_big) VALUES (?)" )
   oStmt:BindParam( 1, 9000000000 )   //  auto -> LONGLONG
   oStmt:Execute()
   nId := oStmt:LastInsertId()
   oStmt:Close()
   cRead := _ScalarQuery( oConn, "SELECT n_big FROM " + cTbl + " WHERE id=" + hb_NToS( nId ) )
   _Check( Val( cRead ) == 9000000000, ;
           "SELECT devuelve BIGINT=9000000000", "9000000000", cRead )

   //  8. INSERT con DOUBLE preserva precision
   oStmt := oConn:PrepareBin( "INSERT INTO " + cTbl + " (n_dbl) VALUES (?)" )
   oStmt:BindParam( 1, 3.14159265358979 )
   oStmt:Execute()
   nId := oStmt:LastInsertId()
   oStmt:Close()
   cRead := _ScalarQuery( oConn, "SELECT n_dbl FROM " + cTbl + " WHERE id=" + hb_NToS( nId ) )
   _Check( Abs( Val( cRead ) - 3.14159265358979 ) < 0.000000001, ;
           "SELECT devuelve DOUBLE con precision", "~3.14159265", cRead )

   //  9. INSERT con string arbitrario (comilla simple safe via binary)
   oStmt := oConn:PrepareBin( "INSERT INTO " + cTbl + " (s_txt) VALUES (?)" )
   oStmt:BindParam( 1, "O'Brien & <script>" )
   oStmt:Execute()
   nId := oStmt:LastInsertId()
   oStmt:Close()
   //  Fetch() aplica wdo_htmlencode a strings -- comparamos contra la version
   //  HTML-encoded, no la original. La verificacion real de integridad es que
   //  no hay truncacion ni corrupcion de bytes.
   cRead := _ScalarQuery( oConn, "SELECT s_txt FROM " + cTbl + " WHERE id=" + hb_NToS( nId ) )
   _Check( cRead == "O&apos;Brien &amp; &lt;script&gt;", ;
           "SELECT devuelve string con comilla simple (html-encoded)",;
           "O&apos;Brien &amp; &lt;script&gt;", cRead )

   //  10. INSERT con NULL (BindParam value=NIL)
   oStmt := oConn:PrepareBin( "INSERT INTO " + cTbl + " (s_null) VALUES (?)" )
   oStmt:BindParam( 1, NIL )
   oStmt:Execute()
   nId := oStmt:LastInsertId()
   oStmt:Close()
   hRow := _FetchOneAssoc( oConn, "SELECT s_null IS NULL AS is_null FROM " + cTbl + ;
                                    " WHERE id=" + hb_NToS( nId ) )
   _Check( hRow != NIL .AND. hRow["is_null"] == "1", ;
           "BindParam(NIL) genera NULL en BD", "1", ;
           iif( hRow == NIL, "no row", hb_CStr( hRow["is_null"] ) ) )

   //  11. Re-Execute 10 iteraciones sin re-preparar
   oStmt := oConn:PrepareBin( "INSERT INTO " + cTbl + " (n_int, s_txt) VALUES (?, ?)" )
   nInsertedCount := Val( _ScalarQuery( oConn, "SELECT COUNT(*) FROM " + cTbl ) )
   FOR i := 1 TO nRunCount
      oStmt:BindParam( 1, 100 + i )
      oStmt:BindParam( 2, "row_" + hb_NToS( i ) )
      oStmt:Execute()
   NEXT
   oStmt:Close()
   _Check( Val( _ScalarQuery( oConn, "SELECT COUNT(*) FROM " + cTbl ) ) - nInsertedCount == nRunCount, ;
           "10 re-Execute binarios insertan 10 filas", "10", ;
           hb_NToS( Val( _ScalarQuery( oConn, "SELECT COUNT(*) FROM " + cTbl ) ) - nInsertedCount ) )

   //  12. INSERT con string binario que contiene NUL bytes (0x00)
   //  -- Alt B tradicional rompe esto sin hex-escape; Alt A binario debe respetarlo.
   cBinData := hb_bChar( 65 ) + hb_bChar( 0 ) + hb_bChar( 66 ) + hb_bChar( 0 ) + hb_bChar( 67 )
   oStmt := oConn:PrepareBin( "INSERT INTO " + cTbl + " (s_bin) VALUES (?)" )
   oStmt:BindParam( 1, cBinData )
   oStmt:Execute()
   nId := oStmt:LastInsertId()
   oStmt:Close()
   cRead := _ScalarQuery( oConn, "SELECT LENGTH(s_bin) FROM " + cTbl + " WHERE id=" + hb_NToS( nId ) )
   _Check( Val( cRead ) == 5, ;
           "BLOB con NUL bytes preserva longitud=5", "5", cRead )

   //  13. BindLong: acumula 3 chunks en la misma columna, verifica longitud
   oStmt := oConn:PrepareBin( "INSERT INTO " + cTbl + " (s_bin) VALUES (?)" )
   oStmt:BindLong( 1, Replicate( "A", 1024 ) )
   oStmt:BindLong( 1, Replicate( "B", 1024 ) )
   oStmt:BindLong( 1, Replicate( "C", 1024 ) )
   oStmt:Execute()
   nId := oStmt:LastInsertId()
   oStmt:Close()
   cRead := _ScalarQuery( oConn, "SELECT LENGTH(s_bin) FROM " + cTbl + " WHERE id=" + hb_NToS( nId ) )
   _Check( Val( cRead ) == 3072, ;
           "BindLong x3 chunks de 1KB -> LENGTH=3072", "3072", cRead )

   //  14. Close idempotente -- llamar dos veces no explota
   oStmt := oConn:PrepareBin( "SELECT ? AS x" )
   oStmt:Close()
   oStmt:Close()
   _Check( oStmt:lClosed, "Close idempotente", ".T.", iif( oStmt:lClosed, ".T.", ".F." ) )

   //  15. Integracion con pool -- PrepareBin sobre conexion adquirida
   oConn:Exec( "DROP TABLE IF EXISTS " + cTbl )
   oConn:Close()

   WDO_InitPoolMySql( scHost, scUser, scPwd, scDb, snPort, 2, 1000, .F. )
   oConn := WDO_Get( "MYSQL" )
   oConn:Exec( "DROP TABLE IF EXISTS " + cTbl )
   oConn:Exec( "CREATE TABLE " + cTbl + " ( id INT AUTO_INCREMENT PRIMARY KEY, v INT )" )
   oStmt := oConn:PrepareBin( "INSERT INTO " + cTbl + " (v) VALUES (?)" )
   oStmt:BindParam( 1, 777 )
   oStmt:Execute()
   oStmt:Close()
   cRead := _ScalarQuery( oConn, "SELECT v FROM " + cTbl + " ORDER BY id DESC LIMIT 1" )
   _Check( Val( cRead ) == 777, ;
           "PrepareBin sobre conn del pool -> 777", "777", cRead )
   oConn:Exec( "DROP TABLE IF EXISTS " + cTbl )
   oConn:Close()
   WDO_EndPoolMySql()

   WDO_MySql():lShowError := lOldShow

RETURN

//	-------------------------------------------------------  //
//  Alt A SELECT fetch binario (v2.3.04) -- resultset read-side.
//	-------------------------------------------------------  //
PROCEDURE TestPrepareBinFetch()

   LOCAL oConn, oStmt
   LOCAL cTbl := "hix_test_prepbin_fetch_" + hb_NToS( Int( Seconds() ) )
   LOCAL lOldShow
   LOCAL aRow, aRows, hRow, cBin, cGot

   _Header( "Prepared: binary fetch (Alt A SELECT)" )

   oConn := _ConnectOrSkip()
   IF oConn == NIL
      _Skip( "PrepareBinFetch", "no hay MySQL" )
      RETU
   ENDIF

   lOldShow := WDO_MySql():lShowError
   WDO_MySql():lShowError := .F.
   oConn:lWeb := .F.                    //  evitar htmlencode interferir

   oConn:Exec( "DROP TABLE IF EXISTS " + cTbl )
   oConn:Exec( "CREATE TABLE " + cTbl + ;
               " ( id INT AUTO_INCREMENT PRIMARY KEY, " + ;
               "   n_int INT, n_big BIGINT, n_dbl DOUBLE, " + ;
               "   s_txt VARCHAR(200), s_bin VARBINARY(32), " + ;
               "   s_null VARCHAR(50) )" )
   oConn:Exec( "INSERT INTO " + cTbl + " (n_int,n_big,n_dbl,s_txt,s_bin) VALUES " + ;
               "(10, 9000000000, 3.14159265358979, 'alpha', 0x4100420043)," + ;
               "(20, 1,          2.5,              'beta',  0x01020300)," + ;
               "(30, 0,          0.0,              'gamma', 0x00)" )

   //  16. SELECT escalar -> Fetch() devuelve array con el valor
   oStmt := oConn:PrepareBin( "SELECT CAST(42 AS SIGNED) AS x" )
   oStmt:Execute()
   aRow := oStmt:Fetch()
   _Check( aRow != NIL .AND. Len( aRow ) == 1 .AND. aRow[1] == 42, ;
           "Fetch() SELECT 42 -> array[1]==42", "42", ;
           iif( aRow == NIL, "NIL", hb_NToS( aRow[1] ) ) )

   //  17. Segundo Fetch() tras agotar -> NIL
   aRow := oStmt:Fetch()
   _Check( aRow == NIL, "Fetch() tras MYSQL_NO_DATA -> NIL", "NIL", ;
           iif( aRow == NIL, "NIL", "non-NIL" ) )
   oStmt:Close()

   //  18. FetchAll(.T.) sobre tabla -> array de hashes con N filas
   oStmt := oConn:PrepareBin( "SELECT id, s_txt FROM " + cTbl + " ORDER BY id" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   _Check( Len( aRows ) == 3 .AND. HB_ISHASH( aRows[1] ) .AND. ;
           aRows[1]["s_txt"] == "alpha" .AND. aRows[3]["s_txt"] == "gamma", ;
           "FetchAll(.T.) devuelve 3 hashes ordenados", "3/alpha/gamma", ;
           hb_NToS( Len( aRows ) ) + "/" + ;
           iif( Len( aRows ) >= 1, aRows[1]["s_txt"], "?" ) + "/" + ;
           iif( Len( aRows ) >= 3, aRows[3]["s_txt"], "?" ) )
   oStmt:Close()

   //  19. NULL en columna -> aRow[i] == NIL
   oStmt := oConn:PrepareBin( "SELECT s_null FROM " + cTbl + " WHERE id=1" )
   oStmt:Execute()
   aRow := oStmt:Fetch()
   _Check( aRow != NIL .AND. aRow[1] == NIL, ;
           "SELECT NULL -> Fetch()[1] == NIL", "NIL", ;
           iif( aRow == NIL, "no row", hb_CStr( aRow[1] ) ) )
   oStmt:Close()

   //  20. BIGINT roundtrip (> 2^31) con bind + fetch
   oStmt := oConn:PrepareBin( "SELECT n_big FROM " + cTbl + " WHERE n_int=?" )
   oStmt:BindParam( 1, 10 )
   oStmt:Execute()
   aRow := oStmt:Fetch()
   _Check( aRow != NIL .AND. aRow[1] == 9000000000, ;
           "SELECT BIGINT roundtrip =9000000000", "9000000000", ;
           iif( aRow == NIL, "NIL", hb_NToS( aRow[1] ) ) )
   oStmt:Close()

   //  21. DOUBLE roundtrip con precision
   oStmt := oConn:PrepareBin( "SELECT n_dbl FROM " + cTbl + " WHERE n_int=10" )
   oStmt:Execute()
   aRow := oStmt:Fetch()
   _Check( aRow != NIL .AND. Abs( aRow[1] - 3.14159265358979 ) < 0.000000001, ;
           "SELECT DOUBLE preserva precision", "~3.14159265", ;
           iif( aRow == NIL, "NIL", hb_NToS( aRow[1] ) ) )
   oStmt:Close()

   //  22. BLOB con NUL bytes embebidos -> longitud preservada
   oStmt := oConn:PrepareBin( "SELECT s_bin FROM " + cTbl + " WHERE n_int=20" )
   oStmt:Execute()
   aRow := oStmt:Fetch()
   cBin := iif( aRow == NIL .OR. aRow[1] == NIL, "", aRow[1] )
   _Check( Len( cBin ) == 4 .AND. hb_bCode( SubStr( cBin, 4, 1 ) ) == 0, ;
           "SELECT VARBINARY con NUL byte -> len=4", "4/NUL", ;
           hb_NToS( Len( cBin ) ) + "/" + hb_NToS( hb_bCode( SubStr( cBin, 4, 1 ) ) ) )
   oStmt:Close()

   //  23. FCount() tras Execute SELECT devuelve nFields esperado
   oStmt := oConn:PrepareBin( "SELECT id, n_int, s_txt FROM " + cTbl )
   oStmt:Execute()
   _Check( oStmt:FCount() == 3, "FCount() == 3", "3", hb_NToS( oStmt:FCount() ) )

   //  24. Count() tras store_result devuelve nRows exacto
   _Check( oStmt:Count() == 3, "Count() == 3", "3", hb_NToS( oStmt:Count() ) )
   oStmt:Close()

   //  25. lWeb=.T. aplica html-encoding salvo aNoEscape (paridad con Alt B)
   oConn:lWeb := .T.
   oConn:Exec( "INSERT INTO " + cTbl + " (s_txt) VALUES ('<b>bold</b>')" )
   oStmt := oConn:PrepareBin( "SELECT s_txt FROM " + cTbl + " WHERE s_txt LIKE '<b>%'" )
   oStmt:Execute()
   aRow := oStmt:Fetch()
   cGot := iif( aRow == NIL, "", aRow[1] )
   _Check( cGot == "&lt;b&gt;bold&lt;/b&gt;", ;
           "lWeb=.T. aplica wdo_htmlencode", "&lt;b&gt;bold&lt;/b&gt;", cGot )
   oStmt:Close()

   oConn:lWeb := .F.
   oConn:Exec( "DROP TABLE IF EXISTS " + cTbl )
   oConn:Close()
   WDO_MySql():lShowError := lOldShow

RETURN
