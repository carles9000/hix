/*-----------------------------------------------------------
  File ......: api_mysql_demo.prg
  Author.....: Charly 9000
  Created....: 2026-10-01
  Modified...: 2026-10-01
  Version....: 1.1.0
  Description: MySQL showcase endpoint. Runs ONE analytical query
               against the `employees` sample DB with randomised
               inputs on every call. The client fires 6 sequential
               AJAX requests (one per query id) so each result lands
               on its own card as soon as the server replies.
                 q=1  PK lookup        — 1 row out of 300k
                 q=2  Range + count    — year-cohort scan on 300k rows
                 q=3  4-table join     — top earners in a random dept
                 q=4  PK history scan  — salary trail from 2.8M rows
                 q=5  Snapshot agg     — avg salary per dept for a year
                 q=6  Title snapshot   — current titles for a year
  Usage      : POST /api/mysql-demo   { "q": 1..6 }
               Response: { ok, q, label, desc, volume, sql, ms,
                           rows, row_count, error }
  Notes      : Each call uses a fresh random seed so repeated hits
               show different data and timings. Reads only.
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL oConn
   LOCAL nQ      := Int( UPost( "q", 0 ) )
   LOCAL hResult
   LOCAL cLabel, cDesc, cVolume, cSql
   LOCAL nYear, cDept, nOffset
   LOCAL aDepts  := { "d001", "d002", "d003", "d004", "d005", ;
                      "d006", "d007", "d008", "d009" }

   IF nQ < 1 .OR. nQ > 6
      USendJson( { "ok" => .F., "error" => "q must be in 1..6" }, 400 )
      RETURN NIL
   ENDIF

   oConn := WDO_Get( "mysql" )

   IF oConn == NIL
      USendJson( { "ok"    => .F., ;
                   "q"     => nQ, ;
                   "error" => "mysql pool unavailable", ;
                   "diag"  => _MysqlDiag() }, 503 )
      RETURN NIL
   ENDIF

   DO CASE

   //  Q1 — Primary-key lookup. Random existing employee picked via
   //  OFFSET on the employees table (300,024 rows) so every call hits.
   CASE nQ == 1
      nOffset := hb_RandomInt( 0, 300023 )
      cLabel  := "Q1 — Primary key lookup"
      cDesc   := "Fetch a single employee by random emp_no. " + ;
                 "Classic B-tree seek: cost grows with log(N), not N."
      cVolume := "1 row out of 300,024 employees"
      cSql    := "SELECT emp_no, first_name, last_name, birth_date, " + ;
                 "hire_date, gender " + ;
                 "FROM employees WHERE emp_no = " + ;
                 "(SELECT emp_no FROM employees LIMIT 1 OFFSET " + ;
                 hb_NToS( nOffset ) + ")"

   //  Q2 — Range + aggregate on hire_date. No index on the column,
   //  so this is a full-table scan + COUNT/MIN/MAX.
   CASE nQ == 2
      nYear   := hb_RandomInt( 1985, 2000 )
      cLabel  := "Q2 — Year cohort scan"
      cDesc   := "Count employees hired in a random year. Full scan " + ;
                 "on hire_date (no index) plus aggregate — raw " + ;
                 "sequential-read speed test."
      cVolume := "scans 300,024 rows, matches ~15k-30k"
      cSql    := "SELECT COUNT(*) AS hired, " + ;
                 "MIN(hire_date) AS first_hire, " + ;
                 "MAX(hire_date) AS last_hire " + ;
                 "FROM employees " + ;
                 "WHERE hire_date BETWEEN '" + hb_NToS( nYear ) + ;
                 "-01-01' AND '" + hb_NToS( nYear ) + "-12-31'"

   //  Q3 — Four-table join: employees × dept_emp × departments ×
   //  salaries. Current snapshot + TOP 10 by salary.
   CASE nQ == 3
      cDept   := aDepts[ hb_RandomInt( 1, 9 ) ]
      cLabel  := "Q3 — Top 10 earners in a random department"
      cDesc   := "Four-table join (employees, dept_emp, departments, " + ;
                 "salaries) with current-snapshot filter and ORDER BY " + ;
                 "salary DESC LIMIT 10."
      cVolume := "joins ~3.3M rows across 4 tables → 10 rows"
      cSql    := "SELECT e.emp_no, e.first_name, e.last_name, " + ;
                 "s.salary, d.dept_name " + ;
                 "FROM employees e " + ;
                 "JOIN dept_emp de ON de.emp_no = e.emp_no " + ;
                 "AND de.to_date = '9999-01-01' " + ;
                 "JOIN departments d ON d.dept_no = de.dept_no " + ;
                 "JOIN salaries s ON s.emp_no = e.emp_no " + ;
                 "AND s.to_date = '9999-01-01' " + ;
                 "WHERE d.dept_no = '" + cDept + "' " + ;
                 "ORDER BY s.salary DESC LIMIT 10"

   //  Q4 — PK-indexed history lookup inside salaries (2.8M rows).
   //  Scalar subquery picks a real emp_no via OFFSET on employees so
   //  every call returns the full 5-18 row trail.
   CASE nQ == 4
      nOffset := hb_RandomInt( 0, 300023 )
      cLabel  := "Q4 — Salary history for a random employee"
      cDesc   := "Fetch every salary change for one employee. Index " + ;
                 "range scan on (emp_no, from_date) inside a 2.8M-row " + ;
                 "table."
      cVolume := "~5-18 rows pulled from 2,844,047"
      cSql    := "SELECT from_date, to_date, salary " + ;
                 "FROM salaries WHERE emp_no = " + ;
                 "(SELECT emp_no FROM employees LIMIT 1 OFFSET " + ;
                 hb_NToS( nOffset ) + ") " + ;
                 "ORDER BY from_date"

   //  Q5 — Snapshot aggregate: avg salary per department at a random
   //  point in time.
   CASE nQ == 5
      nYear   := hb_RandomInt( 1990, 2000 )
      cLabel  := "Q5 — Department snapshot aggregate"
      cDesc   := "Average salary and headcount per department at a " + ;
                 "random point in time. Heavy join on dept_emp × " + ;
                 "salaries with validity-window filtering, then GROUP BY."
      cVolume := "aggregates ~300k active rows → 9 department rows"
      cSql    := "SELECT d.dept_name, COUNT(*) AS headcount, " + ;
                 "ROUND(AVG(s.salary)) AS avg_salary " + ;
                 "FROM departments d " + ;
                 "JOIN dept_emp de ON de.dept_no = d.dept_no " + ;
                 "JOIN salaries s ON s.emp_no = de.emp_no " + ;
                 "AND s.from_date <= '" + hb_NToS( nYear ) + "-12-31' " + ;
                 "AND s.to_date   >= '" + hb_NToS( nYear ) + "-01-01' " + ;
                 "WHERE de.from_date <= '" + hb_NToS( nYear ) + "-12-31' " + ;
                 "AND de.to_date   >= '" + hb_NToS( nYear ) + "-01-01' " + ;
                 "GROUP BY d.dept_name ORDER BY avg_salary DESC"

   //  Q6 — Title distribution snapshot: how many people held each
   //  title at a random point in time + their average tenure in it.
   //  Aggregates ~250k active title rows into 7 title types.
   CASE nQ == 6
      nYear   := hb_RandomInt( 1990, 2000 )
      cLabel  := "Q6 — Title distribution snapshot"
      cDesc   := "Headcount per job title at a random point in time, " + ;
                 "plus average tenure (years) in that title. Validity-" + ;
                 "window filter on from_date/to_date + GROUP BY."
      cVolume := "scans ~250k active title rows → 7 title types"
      cSql    := "SELECT title, COUNT(*) AS headcount, " + ;
                 "ROUND(AVG(DATEDIFF('" + hb_NToS( nYear ) + "-12-31', " + ;
                 "from_date) / 365), 1) AS avg_years " + ;
                 "FROM titles " + ;
                 "WHERE from_date <= '" + hb_NToS( nYear ) + "-12-31' " + ;
                 "AND to_date   >= '" + hb_NToS( nYear ) + "-01-01' " + ;
                 "GROUP BY title ORDER BY headcount DESC"

   ENDCASE

   hResult := _RunQuery( oConn, nQ, cLabel, cDesc, cVolume, cSql )
   oConn:Close()

   USendJson( hResult )

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
//  Runs one SELECT, times it, captures all rows and returns the
//  response hash ready for USendJson.
//  ------------------------------------------------------------

STATIC FUNCTION _RunQuery( oConn, nQ, cLabel, cDesc, cVolume, cSql )

   LOCAL oStmt
   LOCAL hStep := { ;
      "ok"        => .F.,    ;
      "q"         => nQ,     ;
      "label"     => cLabel, ;
      "desc"      => cDesc,  ;
      "volume"    => cVolume,;
      "sql"       => cSql,   ;
      "ms"        => 0,      ;
      "rows"      => {},     ;
      "row_count" => 0,      ;
      "error"     => "" }
   LOCAL nT0 := hb_MilliSeconds()

   oStmt := oConn:Query( cSql )
   hStep[ "ms" ] := hb_MilliSeconds() - nT0

   IF oStmt == NIL
      hStep[ "error" ] := "query returned NIL (connection lost?)"
   ELSEIF oStmt:lError
      hStep[ "error" ] := oStmt:cError
      oStmt:Free()
   ELSE
      oStmt:lWeb := .F.
      hStep[ "rows" ]      := oStmt:FetchAll( .T. )
      hStep[ "row_count" ] := Len( hStep[ "rows" ] )
      hStep[ "ok" ]        := .T.
      oStmt:Free()
   ENDIF

RETURN hStep
