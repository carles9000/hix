/*-----------------------------------------------------------
  File ......: api_mysql_test.prg
  Author.....: Charly 9000
  Created....: 2026-10-01
  Modified...: 2026-10-01
  Version....: 1.0.0
  Description: MySQL smoke-test endpoint for the HI example app.
               Runs a CRUD sequence against a TEMPORARY table and
               reports each step as JSON. Two variants:
                 - test A: plain CRUD, autocommit
                 - test B: same CRUD wrapped in BeginTrans / Commit
                           (Rollback on any step failure)
  Usage      : POST /api/mysql-test  { "test": "A" | "B" }
               Response: { ok, test, took_ms, steps: [...] }
  Notes      : TEMPORARY table lives on the pooled connection; the
               leading DROP IF EXISTS + CREATE guarantees a clean
               slate even if the pool slot was reused.
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL cTest  := Upper( AllTrim( UPost( "test", "" ) ) )
   LOCAL oConn
   LOCAL aSteps := {}
   LOCAL lOk    := .T.
   LOCAL nT0    := hb_MilliSeconds()
   LOCAL lTrans := .F.
   LOCAL i
   LOCAL oError
   LOCAL hStats

   IF cTest != "A" .AND. cTest != "B"
      USendJson( { "ok" => .F., "error" => "test must be 'A' or 'B'" }, 400 )
      RETURN NIL
   ENDIF

   oConn := WDO_Get( "mysql" )

   IF oConn == NIL
      hStats := WDO_PoolStats( "mysql" )
      _l( "[mysql:test] pool unavailable test=" + cTest + ;
         iif( HB_ISHASH( hStats ), ;
              " busy=" + hb_NToS( hStats["busy"] ) + "/" + hb_NToS( hStats["size"] ), "" ), 4, "mysql" )
      USendJson( { "ok"    => .F., ;
                   "error" => "mysql pool unavailable", ;
                   "diag"  => _MysqlDiag() }, 503 )
      RETURN NIL
   ENDIF

   lTrans := ( cTest == "B" )

   TRY

      _RunStep( oConn, aSteps, "DROP",   ;
                "DROP TEMPORARY TABLE IF EXISTS _hix_test" )

      lOk := _RunStep( oConn, aSteps, "CREATE", ;
                "CREATE TEMPORARY TABLE _hix_test ( " + ;
                "id INT AUTO_INCREMENT PRIMARY KEY, " + ;
                "valor VARCHAR(100), " + ;
                "creado DATETIME DEFAULT CURRENT_TIMESTAMP )" )

      IF lOk .AND. lTrans
         lOk := _RunStep( oConn, aSteps, "BEGIN", "START TRANSACTION", ;
                {|| oConn:BeginTrans() } )
      ENDIF

      //  5x INSERT -- distinct `valor` per row
      IF lOk
         FOR i := 1 TO 5
            lOk := _RunStep( oConn, aSteps, "INSERT " + hb_NToS( i ), ;
                   "INSERT INTO _hix_test (valor) VALUES ('prueba_hix_" + ;
                   hb_NToS( i ) + "')" )
            IF ! lOk ; EXIT ; ENDIF
         NEXT
      ENDIF

      IF lOk
         lOk := _RunStep( oConn, aSteps, "SELECT inserted", ;
                "SELECT * FROM _hix_test ORDER BY id" )
      ENDIF

      //  5x UPDATE -- flips each `valor` to its "_up" twin
      IF lOk
         FOR i := 1 TO 5
            lOk := _RunStep( oConn, aSteps, "UPDATE " + hb_NToS( i ), ;
                   "UPDATE _hix_test SET valor = 'prueba_hix_" + hb_NToS( i ) + ;
                   "_up' WHERE valor = 'prueba_hix_" + hb_NToS( i ) + "'" )
            IF ! lOk ; EXIT ; ENDIF
         NEXT
      ENDIF

      IF lOk
         lOk := _RunStep( oConn, aSteps, "SELECT updated", ;
                "SELECT * FROM _hix_test ORDER BY id" )
      ENDIF

      //  5x DELETE -- removes each updated row one by one
      IF lOk
         FOR i := 1 TO 5
            lOk := _RunStep( oConn, aSteps, "DELETE " + hb_NToS( i ), ;
                   "DELETE FROM _hix_test WHERE valor = 'prueba_hix_" + ;
                   hb_NToS( i ) + "_up'" )
            IF ! lOk ; EXIT ; ENDIF
         NEXT
      ENDIF

      IF lOk
         lOk := _RunStep( oConn, aSteps, "SELECT after", ;
                "SELECT * FROM _hix_test" )
      ENDIF

      IF lTrans
         IF lOk
            _RunStep( oConn, aSteps, "COMMIT", "COMMIT", {|| oConn:Commit() } )
         ELSE
            _RunStep( oConn, aSteps, "ROLLBACK", "ROLLBACK", {|| oConn:Rollback() } )
         ENDIF
      ENDIF

      USendJson( { ;
         "ok"       => lOk, ;
         "test"     => cTest, ;
         "trans"    => lTrans, ;
         "took_ms"  => hb_MilliSeconds() - nT0, ;
         "steps"    => aSteps } )

   CATCH oError
      HIX_Dbg( "api_mysql_test error: " + oError:description )
      _l( "[mysql:test] exception test=" + cTest + ": " + oError:description, 4, "mysql" )
      USendError( 500, oError:description )
   FINALLY
      oConn:Close()
   END

RETURN NIL


//  ------------------------------------------------------------
//  Builds a diagnostic hash explaining WHY WDO_Get("mysql") was NIL.
//  Four possibilities and their probes:
//    1. Pool never registered  → bootstrap failed (bad config/DLL).
//    2. Pool exists but closed → shutdown in progress.
//    3. Pool exists, all busy  → size too small for load.
//    4. Pool exists, open slot → next Acquire failed → probe directly.
//
//  Returns a hash safe to JSON-encode. Password is never included.
//  ------------------------------------------------------------

STATIC FUNCTION _MysqlDiag()

   LOCAL hDbs       := HIX_ConfigApp( "databases", {=>} )
   LOCAL hCfg       := iif( HB_ISHASH( hDbs ) .AND. hb_HHasKey( hDbs, "mysql" ), ;
                            hDbs[ "mysql" ], {=>} )
   LOCAL hStats     := WDO_PoolStats( "mysql" )
   LOCAL aPools     := WDO_ListPools()
   LOCAL cProbeErr  := ""
   LOCAL cProbeDll  := ""
   LOCAL cProbeSrc  := ""
   LOCAL lProbeOk   := .F.
   LOCAL oProbe
   LOCAL oError

   TRY
      oProbe := WDO_MySql():New( ;
         hb_HGetDef( hCfg, "host", "localhost" ), ;
         hb_HGetDef( hCfg, "user", "" ), ;
         hb_HGetDef( hCfg, "pwd",  "" ), ;
         hb_HGetDef( hCfg, "db",   "" ), ;
         hb_HGetDef( hCfg, "port", 3306 ) )
      oProbe:cDllPath := hb_HGetDef( hCfg, "dll", "" )
      oProbe:Open()
      cProbeDll := oProbe:cDllPath
      cProbeSrc := oProbe:cDllSource
      IF oProbe:lConnect
         lProbeOk := .T.
         oProbe:Close()
      ELSE
         cProbeErr := oProbe:cError
      ENDIF
   CATCH oError
      cProbeErr := "exception: " + oError:description
   END

RETURN { ;
   "pool_registered"  => ( hStats != NIL ), ;
   "pool_stats"       => hStats, ;
   "pools_registered" => aPools, ;
   "config"           => { ;
      "host" => hb_HGetDef( hCfg, "host", "(missing)" ), ;
      "user" => hb_HGetDef( hCfg, "user", "(missing)" ), ;
      "db"   => hb_HGetDef( hCfg, "db",   "(missing)" ), ;
      "port" => hb_HGetDef( hCfg, "port", 0 ), ;
      "dll"  => hb_HGetDef( hCfg, "dll",  "(auto-resolved)" ), ;
      "pool_size" => hb_HGetDef( hCfg, "pool_size", 0 ) }, ;
   "probe_ok"         => lProbeOk, ;
   "probe_error"      => cProbeErr, ;
   "probe_dll"        => cProbeDll, ;
   "probe_dll_source" => cProbeSrc }


//  ------------------------------------------------------------
//  Runs one step: SQL via oConn:Query() by default, or a custom
//  codeblock (used for BeginTrans/Commit/Rollback that don't go
//  through Query). Appends a hash to aSteps and returns .T./.F.
//  ------------------------------------------------------------

STATIC FUNCTION _RunStep( oConn, aSteps, cLabel, cSql, bCustom )

   LOCAL oStmt
   LOCAL hStep := { ;
      "step"     => cLabel, ;
      "sql"      => cSql,   ;
      "ok"       => .F.,    ;
      "ms"       => 0,      ;
      "info"     => "",     ;
      "affected" => NIL,    ;
      "insert_id"=> NIL,    ;
      "rows"     => NIL }
   LOCAL nT0 := hb_MilliSeconds()
   LOCAL cUp := Upper( AllTrim( cSql ) )

   IF bCustom != NIL
      hStep[ "ok" ]   := Eval( bCustom )
      hStep[ "ms" ]   := hb_MilliSeconds() - nT0
      hStep[ "info" ] := iif( hStep[ "ok" ], "ok", "failed: " + oConn:cError )
   ELSE
      oStmt := oConn:Query( cSql )
      hStep[ "ms" ] := hb_MilliSeconds() - nT0

      IF oStmt == NIL
         hStep[ "info" ] := "query returned NIL (connection lost?)"
         _l( "[mysql:test] step [" + cLabel + "] NIL stmt — connection lost?", 4, "mysql" )
      ELSEIF oStmt:lError
         hStep[ "info" ] := "mysql error: " + oStmt:cError
         _l( "[mysql:test] step [" + cLabel + "] error: " + oStmt:cError, 4, "mysql" )
         oStmt:Free()
      ELSE
         hStep[ "ok" ]       := .T.
         hStep[ "affected" ] := oStmt:nAffectedRows

         DO CASE
         CASE Left( cUp, 6 ) == "SELECT"
            oStmt:lWeb := .F.
            hStep[ "rows" ] := oStmt:FetchAll( .T. )
            hStep[ "info" ] := Str( Len( hStep[ "rows" ] ), 0 ) + " row(s)"
         CASE Left( cUp, 6 ) == "INSERT"
            hStep[ "insert_id" ] := oConn:Last_Insert_Id()
            hStep[ "info" ] := "inserted " + Str( oStmt:nAffectedRows, 0 ) + ;
                               " row(s), id=" + Str( hStep[ "insert_id" ], 0 )
         CASE Left( cUp, 6 ) == "UPDATE" .OR. Left( cUp, 6 ) == "DELETE"
            hStep[ "info" ] := Str( oStmt:nAffectedRows, 0 ) + " row(s) affected"
         OTHERWISE
            hStep[ "info" ] := "ok"
         ENDCASE

         oStmt:Free()
      ENDIF
   ENDIF

   AAdd( aSteps, hStep )

RETURN hStep[ "ok" ]
