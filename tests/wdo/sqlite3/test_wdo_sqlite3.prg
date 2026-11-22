/*-----------------------------------------------------------
  File ......: test_wdo_sqlite3.prg
  Author.....: Charly 9000
  Created....: 2026-10-05
  Modified...: 2026-11-22
  Version....: 1.1.0
  Description: Smoke + contract + isolation suite for the WDO
               SQLite3 driver. All in one binary.

                 01-13  Smoke  (CRUD, prepare, UTF-8, concurrency)
                 14     Standalone registry round-trip
                 15-19  SQLCipher (open, wrong key, rekey, info)
                 20-25  Contract (Claim 1 — Close/Register, Bind,
                        Transaction error preservation)
                 26-29  Isolation (Claim 2 — real pool per file,
                        tx isolation across threads)

               No external dependencies, no network, no fixtures.
  Usage      : go_sqlite3_msvc64.bat
 -----------------------------------------------------------*/

#include "hbclass.ch"
#include "hix_const.ch"


STATIC snTotal   := 0
STATIC snPassed  := 0
STATIC snFailed  := 0

STATIC s_cDbFile := ""

#define TX_KEY   "SQ_ISOLATION"


//	=======================================================  //
//  Reporting
//	=======================================================  //

STATIC PROCEDURE _Pass( cTest )
   snTotal++ ; snPassed++
   OutStd( "[PASS] " + cTest + hb_eol() )
RETURN

STATIC PROCEDURE _Fail( cTest, cExpected, cGot )
   snTotal++ ; snFailed++
   OutStd( "[FAIL] " + cTest + hb_eol() )
   OutStd( "       Expected: " + cExpected + "  Got: " + cGot + hb_eol() )
RETURN

STATIC PROCEDURE _Check( lCond, cTest, cExpected, cGot )
   IF lCond ; _Pass( cTest ) ; ELSE ; _Fail( cTest, cExpected, cGot ) ; ENDIF
RETURN

STATIC PROCEDURE _Header( cSuite )
   OutStd( hb_eol() + "--- " + cSuite + " ---" + hb_eol() )
RETURN


//	=======================================================  //
//  Main
//	=======================================================  //

PROCEDURE Main( ... )

   LOCAL oErr

   _Header( "WDO SQLite3 driver" )

   _Test01_OpenClose()
   _Test02_Crud()
   _Test03_PreparePositional()
   _Test04_PrepareNamed()
   _Test05_BindNameInvalid()
   _Test06_TransactionCommit()
   _Test07_TransactionRollback()
   _Test08_DbStructWithTable()
   _Test09_DbStructEmpty()
   _Test10_IsTable()
   _Test11_ChangesAndLastId()
   _Test12_Utf8Roundtrip()
   _Test13_Concurrency()
   _Test14_StandaloneRegistry()
   _Test15_CipherOpenReopen()
   _Test16_CipherWrongKey()
   _Test17_CipherRekey()
   _Test18_CipherDecrypt()
   _Test19_CipherInfo()

   _Header( "WDO SQLite3 driver contract (Claim 1)" )

   TRY ; _Test20_CloseNoOpOnSingleton()     ; CATCH oErr ; _Fail( "T20", "no raise", oErr:description ) ; END
   TRY ; _Test21_CloseRealAfterUnregister() ; CATCH oErr ; _Fail( "T21", "no raise", oErr:description ) ; END
   TRY ; _Test22_BindParamLowercaseAliases(); CATCH oErr ; _Fail( "T22", "no raise", oErr:description ) ; END
   TRY ; _Test23_BindParamUnknownTypeFails(); CATCH oErr ; _Fail( "T23", "no raise", oErr:description ) ; END
   TRY ; _Test24_TransactionPreservesError(); CATCH oErr ; _Fail( "T24", "no raise", oErr:description ) ; END
   TRY ; _Test25_TransactionCommitOk()      ; CATCH oErr ; _Fail( "T25", "no raise", oErr:description ) ; END

   _Header( "WDO SQLite3 transaction isolation (Claim 2)" )

   s_cDbFile := hb_DirTemp() + "hix_sqlite3_iso_" + hb_NToS( hb_MilliSeconds() ) + ".db"

   TRY
      _SetupIsolationPool()
      TRY ; _Test26_RollbackContamination()  ; CATCH oErr ; _Fail( "T26", "no raise", oErr:description ) ; END
      TRY ; _Test27_ConcurrentTransactions() ; CATCH oErr ; _Fail( "T27", "no raise", oErr:description ) ; END
      TRY ; _Test28_StressNoDeadlock()       ; CATCH oErr ; _Fail( "T28", "no raise", oErr:description ) ; END
      TRY ; _Test29_UncommittedVisibility()  ; CATCH oErr ; _Fail( "T29", "no raise", oErr:description ) ; END
      _CleanupIsolationPool()
   CATCH oErr
      _Fail( "Isolation Setup", "pool open", oErr:description )
      _CleanupIsolationPool()
   END

   OutStd( hb_eol() + "Tests: " + hb_NToS( snTotal ) + " total | " + ;
           hb_NToS( snPassed ) + " passed | " + hb_NToS( snFailed ) + " failed" + hb_eol() )
   OutStd( "End test..." + hb_eol() )
   ErrorLevel( iif( snFailed == 0, 0, 1 ) )

   IF pcount() == 0 ; Inkey( 0 ) ; ENDIF

RETURN


//	=======================================================  //
//  Test 01 -- Open / Close  (:memory:)
//	=======================================================  //

STATIC FUNCTION _NewMemConn()
   LOCAL oConn := WDO_Sqlite3():New( ":memory:", .T. )
   oConn:Open()
RETURN oConn


STATIC PROCEDURE _Test01_OpenClose()

   LOCAL oConn := _NewMemConn()

   _Check( oConn:lConnect, "01.1 Open :memory:", "lConnect=.T.", "lConnect=.F." )
   _Check( oConn:Ping(),   "01.2 Ping",           "ping=.T.",     "ping=.F." )

   oConn:Close()
   _Check( ! oConn:lConnect, "01.3 Close", "lConnect=.F.", "lConnect=.T." )

RETURN


//	=======================================================  //
//  Test 02 -- CRUD
//	=======================================================  //

STATIC PROCEDURE _Test02_Crud()

   LOCAL oConn := _NewMemConn()
   LOCAL oStmt, hRow, nCount := 0

   _Check( oConn:Exec( "CREATE TABLE t( id INTEGER PRIMARY KEY, name TEXT )" ), ;
           "02.1 Create table", "T", "F" )

   _Check( oConn:Exec( "INSERT INTO t(name) VALUES('alice')" ), ;
           "02.2 Insert row 1",  "T", "F" )
   _Check( oConn:Exec( "INSERT INTO t(name) VALUES('bob')" ),   ;
           "02.3 Insert row 2",  "T", "F" )

   oStmt := oConn:Query( "SELECT COUNT(*) AS n FROM t" )
   IF oStmt != NIL .AND. ! oStmt:lEof
      hRow := oStmt:Fetch_Assoc()
      IF hRow != NIL ; nCount := hRow[ "n" ] ; ENDIF
   ENDIF
   oStmt:Free()
   _Check( nCount == 2, "02.4 Count=2", "2", hb_NToS( nCount ) )

   _Check( oConn:Exec( "UPDATE t SET name='carol' WHERE id=1" ), ;
           "02.5 Update", "T", "F" )
   _Check( oConn:Exec( "DELETE FROM t WHERE id=2" ), ;
           "02.6 Delete", "T", "F" )

   oConn:Close()

RETURN


//	=======================================================  //
//  Test 03 -- Prepare positional ?
//	=======================================================  //

STATIC PROCEDURE _Test03_PreparePositional()

   LOCAL oConn := _NewMemConn()
   LOCAL oStmt, hRow, cName := ""

   oConn:Exec( "CREATE TABLE u( id INTEGER, name TEXT )" )

   oStmt := oConn:Prepare( "INSERT INTO u(id,name) VALUES(?, ?)" )
   oStmt:BindParams( { 1, "alpha" } )
   oStmt:Execute()
   oStmt:Free()

   oStmt := oConn:Prepare( "SELECT name FROM u WHERE id=?" )
   oStmt:BindParam( 1, 1 )
   oStmt:Execute()
   hRow := oStmt:Fetch_Assoc()
   IF hRow != NIL ; cName := hRow[ "name" ] ; ENDIF
   oStmt:Free()

   _Check( cName == "alpha", "03.1 Positional ?", "alpha", cName )

   oConn:Close()

RETURN


//	=======================================================  //
//  Test 04 -- Prepare named :name
//	=======================================================  //

STATIC PROCEDURE _Test04_PrepareNamed()

   LOCAL oConn := _NewMemConn()
   LOCAL oStmt, hRow, cName := ""

   oConn:Exec( "CREATE TABLE u( id INTEGER, name TEXT )" )

   oStmt := oConn:Prepare( "INSERT INTO u(id,name) VALUES(:id, :name)" )
   oStmt:BindParam( ":id",   7 )
   oStmt:BindParam( "name",  "beta" )   //  no leading ':' -> auto-prefixed
   oStmt:Execute()
   oStmt:Free()

   oStmt := oConn:Prepare( "SELECT name FROM u WHERE id=:id" )
   oStmt:BindParam( ":id", 7 )
   oStmt:Execute()
   hRow := oStmt:Fetch_Assoc()
   IF hRow != NIL ; cName := hRow[ "name" ] ; ENDIF
   oStmt:Free()

   _Check( cName == "beta", "04.1 Named :name", "beta", cName )

   oConn:Close()

RETURN


//	=======================================================  //
//  Test 05 -- BindParam invalid name
//	=======================================================  //

STATIC PROCEDURE _Test05_BindNameInvalid()

   LOCAL oConn := _NewMemConn()
   LOCAL oStmt, lOk

   //  Silence SetError's default ErrorBlock -- we expect the bind to fail
   //  and don't want the global error path to fire.
   oConn:bError := {|| NIL }

   oStmt := oConn:Prepare( "SELECT :a AS v" )
   lOk := oStmt:BindParam( ":missing", 42 )

   _Check( ! lOk .AND. oStmt:lError, "05.1 Unknown :name errors", "lError=.T.", "lError=.F." )

   oStmt:Free()
   oConn:Close()

RETURN


//	=======================================================  //
//  Test 06 -- Transaction OK (commit)
//	=======================================================  //

STATIC PROCEDURE _Test06_TransactionCommit()

   LOCAL oConn := _NewMemConn()
   LOCAL oStmt, hRow, nCount := 0

   oConn:Exec( "CREATE TABLE t( id INTEGER )" )

   _Check( oConn:BeginTrans(), "06.1 BeginTrans", "T", "F" )
   oConn:Exec( "INSERT INTO t VALUES(1)" )
   oConn:Exec( "INSERT INTO t VALUES(2)" )
   _Check( oConn:Commit(), "06.2 Commit", "T", "F" )

   oStmt := oConn:Query( "SELECT COUNT(*) AS n FROM t" )
   hRow := oStmt:Fetch_Assoc()
   IF hRow != NIL ; nCount := hRow[ "n" ] ; ENDIF
   oStmt:Free()

   _Check( nCount == 2, "06.3 Rows persisted", "2", hb_NToS( nCount ) )

   oConn:Close()

RETURN


//	=======================================================  //
//  Test 07 -- Transaction FAIL (rollback)
//	=======================================================  //

STATIC PROCEDURE _Test07_TransactionRollback()

   LOCAL oConn := _NewMemConn()
   LOCAL oStmt, hRow, nCount := 999

   oConn:Exec( "CREATE TABLE t( id INTEGER )" )

   oConn:BeginTrans()
   oConn:Exec( "INSERT INTO t VALUES(1)" )
   oConn:Exec( "INSERT INTO t VALUES(2)" )
   _Check( oConn:Rollback(), "07.1 Rollback", "T", "F" )

   oStmt := oConn:Query( "SELECT COUNT(*) AS n FROM t" )
   hRow := oStmt:Fetch_Assoc()
   IF hRow != NIL ; nCount := hRow[ "n" ] ; ENDIF
   oStmt:Free()

   _Check( nCount == 0, "07.2 Rows discarded", "0", hb_NToS( nCount ) )

   oConn:Close()

RETURN


//	=======================================================  //
//  Test 08 -- DbStruct with cTable
//	=======================================================  //

STATIC PROCEDURE _Test08_DbStructWithTable()

   LOCAL oConn := _NewMemConn()
   LOCAL oStmt, aStruct, lHasId, lHasName

   oConn:Exec( "CREATE TABLE users( id INTEGER PRIMARY KEY, name VARCHAR(50) NOT NULL )" )

   oStmt := oConn:Prepare( "SELECT * FROM users" )
   oStmt:cTable := "users"
   aStruct := oStmt:DbStruct()
   oStmt:Free()

   _Check( Len( aStruct ) == 2, "08.1 DbStruct size", "2", hb_NToS( Len( aStruct ) ) )

   lHasId := Len( aStruct ) >= 1 .AND. aStruct[ 1 ][ 1 ] == "id" .AND. aStruct[ 1 ][ 6 ]
   _Check( lHasId, "08.2 PK id INTEGER", "name=id,pk=.T.", ;
           iif( Len( aStruct ) >= 1, aStruct[ 1 ][ 1 ] + ",pk=" + iif( aStruct[ 1 ][ 6 ], "T", "F" ), "<empty>" ) )

   lHasName := Len( aStruct ) >= 2 .AND. aStruct[ 2 ][ 1 ] == "name" .AND. ;
               aStruct[ 2 ][ 2 ] == "VARCHAR" .AND. aStruct[ 2 ][ 3 ] == 50 .AND. aStruct[ 2 ][ 5 ]
   _Check( lHasName, "08.3 VARCHAR(50) parsed", "VARCHAR,50,notnull=.T.", ;
           iif( Len( aStruct ) >= 2, aStruct[ 2 ][ 2 ] + "," + hb_NToS( aStruct[ 2 ][ 3 ] ) + ",nn=" + iif( aStruct[ 2 ][ 5 ], "T", "F" ), "<empty>" ) )

   oConn:Close()

RETURN


//	=======================================================  //
//  Test 09 -- DbStruct without cTable -> empty
//	=======================================================  //

STATIC PROCEDURE _Test09_DbStructEmpty()

   LOCAL oConn := _NewMemConn()
   LOCAL oStmt, aStruct

   oConn:Exec( "CREATE TABLE t( id INTEGER )" )

   oStmt := oConn:Prepare( "SELECT * FROM t" )
   //  Deliberately omit cTable assignment.
   aStruct := oStmt:DbStruct()
   oStmt:Free()

   _Check( Len( aStruct ) == 0, "09.1 DbStruct no cTable -> empty", "0", hb_NToS( Len( aStruct ) ) )

   oConn:Close()

RETURN


//	=======================================================  //
//  Test 10 -- IsTable
//	=======================================================  //

STATIC PROCEDURE _Test10_IsTable()

   LOCAL oConn := _NewMemConn()

   oConn:Exec( "CREATE TABLE here( id INTEGER )" )

   _Check(   oConn:IsTable( "here" ),      "10.1 IsTable existing", "T", "F" )
   _Check( ! oConn:IsTable( "nowhere" ),   "10.2 IsTable missing",  "F", "T" )

   oConn:Close()

RETURN


//	=======================================================  //
//  Test 11 -- Changes / Last_Insert_Id
//	=======================================================  //

STATIC PROCEDURE _Test11_ChangesAndLastId()

   LOCAL oConn := _NewMemConn()
   LOCAL nLast, nCh

   oConn:Exec( "CREATE TABLE t( id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT )" )

   oConn:Exec( "INSERT INTO t(v) VALUES('a')" )
   oConn:Exec( "INSERT INTO t(v) VALUES('b')" )
   nLast := oConn:Last_Insert_Id()
   _Check( nLast == 2, "11.1 Last_Insert_Id=2", "2", hb_NToS( nLast ) )

   oConn:Exec( "UPDATE t SET v='x'" )
   nCh := oConn:Changes()
   _Check( nCh == 2, "11.2 Changes=2 after UPDATE", "2", hb_NToS( nCh ) )

   oConn:Close()

RETURN


//	=======================================================  //
//  Test 12 -- UTF-8 roundtrip
//	=======================================================  //

STATIC PROCEDURE _Test12_Utf8Roundtrip()

   LOCAL oConn := _NewMemConn()
   LOCAL oStmt, hRow, cGot := ""
   LOCAL cPayload := "Año €uro ∑ 测试"

   oConn:Exec( "CREATE TABLE u( v TEXT )" )

   oStmt := oConn:Prepare( "INSERT INTO u(v) VALUES(:v)" )
   oStmt:BindParam( ":v", cPayload )
   oStmt:Execute()
   oStmt:Free()

   oStmt := oConn:Query( "SELECT v FROM u" )
   hRow := oStmt:Fetch_Assoc()
   IF hRow != NIL ; cGot := hRow[ "v" ] ; ENDIF
   oStmt:Free()

   _Check( cGot == cPayload, "12.1 UTF-8 roundtrip", "equal", "diff (len " + hb_NToS( Len( cGot ) ) + ")" )

   oConn:Close()

RETURN


//	=======================================================  //
//  Test 13 -- Two threads sharing the same singleton
//	=======================================================  //

STATIC PROCEDURE _Test13_Concurrency()

   LOCAL oConn := _NewMemConn()
   LOCAL aThreads := {}, h, i
   LOCAL oStmt, hRow, nCount := 0

   oConn:Exec( "CREATE TABLE c( v INTEGER )" )

   //  2 threads x 50 inserts each -> 100 rows
   FOR i := 1 TO 2
      h := hb_threadStart( {|| _ConcurrentInserter( oConn, 50 ) } )
      AAdd( aThreads, h )
   NEXT

   FOR EACH h IN aThreads
      hb_threadJoin( h )
   NEXT

   oStmt := oConn:Query( "SELECT COUNT(*) AS n FROM c" )
   hRow := oStmt:Fetch_Assoc()
   IF hRow != NIL ; nCount := hRow[ "n" ] ; ENDIF
   oStmt:Free()

   _Check( nCount == 100, "13.1 Two threads x 50 inserts", "100", hb_NToS( nCount ) )

   oConn:Close()

RETURN


STATIC PROCEDURE _ConcurrentInserter( oConn, nRows )

   LOCAL i, oStmt

   FOR i := 1 TO nRows
      oStmt := oConn:Prepare( "INSERT INTO c(v) VALUES(:v)" )
      oStmt:BindParam( ":v", i )
      oStmt:Execute()
      oStmt:Free()
   NEXT

RETURN


//	=======================================================  //
//  Test 14 -- Standalone registry (WDO_RegisterConn / WDO_Get)
//	=======================================================  //

STATIC PROCEDURE _Test14_StandaloneRegistry()

   LOCAL cKey := "T_SQLITE_TMP"
   LOCAL hParams, lOk, oGot, aConns, lListed

   hParams := { ;
      "driver"       => "sqlite3", ;
      "file"         => ":memory:", ;
      "create"       => .T.,        ;
      "journal_mode" => "MEMORY",   ;
      "synchronous"  => "OFF"       ;
   }

   lOk := WDO_InitSqlite3Ex( cKey, hParams )
   _Check( lOk, "14.1 WDO_InitSqlite3Ex ok", "T", "F" )

   oGot := WDO_Get( cKey )
   _Check( oGot != NIL .AND. oGot:lConnect, "14.2 WDO_Get returns conn", "T", "F" )

   aConns := WDO_ListStandaloneConns()
   lListed := AScan( aConns, {|c| Upper( c ) == Upper( cKey ) } ) > 0
   _Check( lListed, "14.3 Listed in standalone registry", "T", "F" )

   WDO_EndSqlite3( cKey )

   oGot := WDO_Get( cKey )
   _Check( oGot == NIL, "14.4 Unregistered after End", "NIL", "<obj>" )

RETURN


//	=======================================================  //
//  Cipher helpers
//	=======================================================  //

STATIC FUNCTION _TempDbPath( cTag )
   LOCAL cTmp := hb_DirTemp() + "wdo_sqlite3_" + cTag + "_" + ;
                 hb_NToS( hb_Random( 1, 999999 ) ) + ".db"
   FErase( cTmp )
RETU cTmp


STATIC FUNCTION _NewCipherConn( cFile, cKey )
   LOCAL oConn := WDO_Sqlite3():New( cFile, .T. )
   //  Install a no-op bError so SetError does not Break() out of Open /
   //  Rekey / Exec when the test deliberately drives a failure path.
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }
   oConn:cKey   := cKey
   oConn:Open()
RETU oConn


//	=======================================================  //
//  Test 15 -- Cipher open, write, close, reopen with same key
//	=======================================================  //

STATIC PROCEDURE _Test15_CipherOpenReopen()

   LOCAL cDb   := _TempDbPath( "cipher_rt" )
   LOCAL cKey  := "secret-cipher-key-15"
   LOCAL oConn, oStmt, hRow, cName := ""

   oConn := _NewCipherConn( cDb, cKey )
   _Check( oConn:lConnect,  "15.1 Open encrypted DB",  "T", "F" )
   _Check( oConn:lEncrypted, "15.2 lEncrypted=.T.",     "T", "F" )

   oConn:Exec( "CREATE TABLE s( id INTEGER PRIMARY KEY, name TEXT )" )
   oConn:Exec( "INSERT INTO s(name) VALUES('cipherdata')" )
   oConn:Close()

   //  Reopen with same key — must read the row back.
   oConn := _NewCipherConn( cDb, cKey )
   _Check( oConn:lConnect, "15.3 Reopen with same key", "T", "F" )

   oStmt := oConn:Query( "SELECT name FROM s WHERE id = 1" )
   IF oStmt != NIL .AND. ! oStmt:lEof
      hRow := oStmt:Fetch_Assoc()
      IF hRow != NIL ; cName := hRow[ "name" ] ; ENDIF
   ENDIF
   IF oStmt != NIL ; oStmt:Free() ; ENDIF

   _Check( cName == "cipherdata", "15.4 Row survives roundtrip", "cipherdata", cName )

   oConn:Close()
   FErase( cDb )

RETURN


//	=======================================================  //
//  Test 16 -- Reopen with wrong key must fail
//	=======================================================  //

STATIC PROCEDURE _Test16_CipherWrongKey()

   LOCAL cDb  := _TempDbPath( "cipher_wrong" )
   LOCAL oConn

   //  Create encrypted DB
   oConn := _NewCipherConn( cDb, "right-key-16" )
   oConn:Exec( "CREATE TABLE s( v TEXT )" )
   oConn:Exec( "INSERT INTO s VALUES('x')" )
   oConn:Close()

   //  Reopen with wrong key — Open() must leave lConnect=.F.
   oConn := _NewCipherConn( cDb, "WRONG-KEY-16" )
   _Check( ! oConn:lConnect, "16.1 Wrong key rejected", ;
           "lConnect=.F.", "lConnect=.T." )

   FErase( cDb )

RETURN


//	=======================================================  //
//  Test 17 -- Rekey (change passphrase) and reopen with new key
//	=======================================================  //

STATIC PROCEDURE _Test17_CipherRekey()

   LOCAL cDb      := _TempDbPath( "cipher_rekey" )
   LOCAL cOldKey  := "old-key-17"
   LOCAL cNewKey  := "new-key-17-renewed"
   LOCAL oConn, oStmt, hRow, cName := ""

   oConn := _NewCipherConn( cDb, cOldKey )
   oConn:Exec( "CREATE TABLE r( id INTEGER PRIMARY KEY, name TEXT )" )
   oConn:Exec( "INSERT INTO r(name) VALUES('rekeytest')" )

   _Check( oConn:Rekey( cNewKey ), "17.1 Rekey OK", "T", "F" )
   _Check( oConn:cKey == cNewKey,  "17.2 cKey updated", cNewKey, oConn:cKey )

   oConn:Close()

   //  Old key must fail
   oConn := _NewCipherConn( cDb, cOldKey )
   _Check( ! oConn:lConnect, "17.3 Old key rejected after rekey", ;
           "lConnect=.F.", "lConnect=.T." )

   //  New key must succeed and data survives
   oConn := _NewCipherConn( cDb, cNewKey )
   _Check( oConn:lConnect, "17.4 Reopen with new key", "T", "F" )

   oStmt := oConn:Query( "SELECT name FROM r WHERE id = 1" )
   IF oStmt != NIL .AND. ! oStmt:lEof
      hRow := oStmt:Fetch_Assoc()
      IF hRow != NIL ; cName := hRow[ "name" ] ; ENDIF
   ENDIF
   IF oStmt != NIL ; oStmt:Free() ; ENDIF

   _Check( cName == "rekeytest", "17.5 Data survives rekey", "rekeytest", cName )

   oConn:Close()
   FErase( cDb )

RETURN


//	=======================================================  //
//  Test 18 -- Rekey to "" is not supported by SQLCipher
//	=======================================================  //

STATIC PROCEDURE _Test18_CipherDecrypt()

   LOCAL cDb   := _TempDbPath( "cipher_decrypt" )
   LOCAL cKey  := "throwaway-key-18"
   LOCAL oConn

   oConn := _NewCipherConn( cDb, cKey )
   oConn:Exec( "CREATE TABLE d( id INTEGER PRIMARY KEY, name TEXT )" )
   oConn:Exec( "INSERT INTO d(name) VALUES('plaintext')" )

   _Check( ! oConn:Rekey( "" ),  "18.1 Rekey to '' refused",   "F", "T" )
   _Check( oConn:lEncrypted,     "18.2 lEncrypted stays .T.",  "T", "F" )

   oConn:Close()
   FErase( cDb )

RETURN


//	=======================================================  //
//  Test 19 -- GetCipherInfo() reports cipher params
//	=======================================================  //

STATIC PROCEDURE _Test19_CipherInfo()

   LOCAL cDb   := _TempDbPath( "cipher_info" )
   LOCAL oConn := _NewCipherConn( cDb, "info-key-19" )
   LOCAL hInfo

   hInfo := oConn:GetCipherInfo()

   _Check( ValType( hInfo ) == "H",            "19.1 Info is hash", "H", ValType( hInfo ) )
   _Check( "cipher_version" $ hInfo,           "19.2 cipher_version present", "T", "F" )
   _Check( ! Empty( hInfo[ "cipher_version" ] ), ;
           "19.3 cipher_version non-empty", "<string>", "<empty>" )
   _Check( oConn:IsEncrypted(),                "19.4 IsEncrypted()=.T.", "T", "F" )

   oConn:Close()
   FErase( cDb )

RETURN


//	=======================================================  //
//  Test 20 -- Close() on a singleton registered via WDO_RegisterConn
//              must be a no-op. WDO_Get(cKey) must still return a
//              live connection afterwards.  (Contract — Claim 1)
//	=======================================================  //

STATIC PROCEDURE _Test20_CloseNoOpOnSingleton()

   LOCAL cKey := "SQ_CONTRACT1"
   LOCAL oConn, oStmt, aRow, lOk1, lOk2, lStillConn

   oConn := WDO_Sqlite3():New( ":memory:", .T. )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }
   oConn:Open()
   WDO_RegisterConn( cKey, oConn )

   oConn := WDO_Get( cKey )
   _Check( oConn != NIL, "20.1 WDO_Get returns singleton", "T", hb_CStr( oConn != NIL ) )

   _Check( oConn:lStandalone, "20.2 lStandalone flag ON after Register", "T", ;
           hb_CStr( oConn:lStandalone ) )

   oConn:Close()
   lStillConn := oConn:lConnect
   _Check( lStillConn, "20.3 Close() is a no-op on singleton (lConnect)", "T", ;
           hb_CStr( lStillConn ) )

   oConn := WDO_Get( cKey )
   lOk1  := oConn != NIL .AND. oConn:lConnect

   oStmt := oConn:Query( "SELECT 1 AS n" )
   lOk2  := oStmt != NIL .AND. ! oStmt:lError

   IF lOk2
      aRow := oStmt:Fetch_Assoc()
      oStmt:Free()
   ENDIF

   _Check( lOk1 .AND. lOk2, "20.4 WDO_Get after Close still usable", "T", ;
           hb_CStr( lOk1 .AND. lOk2 ) )

   HB_SYMBOL_UNUSED( aRow )
   WDO_UnregisterConn( cKey )

RETURN


//	=======================================================  //
//  Test 21 -- WDO_UnregisterConn() runs real Close.
//	=======================================================  //

STATIC PROCEDURE _Test21_CloseRealAfterUnregister()

   LOCAL cKey := "SQ_CONTRACT2"
   LOCAL oConn

   oConn := WDO_Sqlite3():New( ":memory:", .T. )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }
   oConn:Open()
   WDO_RegisterConn( cKey, oConn )

   oConn := WDO_Get( cKey )
   WDO_UnregisterConn( cKey )

   _Check( ! oConn:lConnect, "21.1 Unregister runs real Close (lConnect=.F.)", ;
           "F", hb_CStr( oConn:lConnect ) )

   _Check( oConn:pDb == NIL, "21.2 pDb is NIL after Unregister", "NIL", ;
           iif( oConn:pDb == NIL, "NIL", "ptr" ) )

RETURN


//	=======================================================  //
//  Test 22 -- BindParam accepts lowercase doc aliases: "i","n","s".
//	=======================================================  //

STATIC PROCEDURE _Test22_BindParamLowercaseAliases()

   LOCAL oConn, oStmt, hRow
   LOCAL xId, xNote, xTotal

   oConn := WDO_Sqlite3():New( ":memory:", .T. )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }
   oConn:Open()

   oConn:Exec( "CREATE TABLE t_alias ( id INTEGER, note TEXT, total REAL )" )

   oStmt := oConn:Prepare( "INSERT INTO t_alias ( id, note, total ) VALUES ( ?, ?, ? )" )
   oStmt:BindParam( 1, 42,      "i" )
   oStmt:BindParam( 2, "hello", "s" )
   oStmt:BindParam( 3, 3.14,    "n" )
   oStmt:Execute()
   oStmt:Free()

   oStmt := oConn:Query( "SELECT id, note, total FROM t_alias" )
   hRow  := oStmt:Fetch_Assoc()
   oStmt:Free()

   xId    := hb_HGetDef( hRow, "id",    0 )
   xNote  := hb_HGetDef( hRow, "note",  "" )
   xTotal := hb_HGetDef( hRow, "total", 0 )

   _Check( hb_isNumeric( xId ) .AND. xId == 42, ;
      "22.1 bind 'i' int round-trip", "42", hb_CStr( xId ) )

   _Check( xNote == "hello", ;
      "22.2 bind 's' text round-trip", "hello", hb_CStr( xNote ) )

   _Check( hb_isNumeric( xTotal ) .AND. xTotal > 3.13 .AND. xTotal < 3.15, ;
      "22.3 bind 'n' numeric round-trip", "3.14", hb_CStr( xTotal ) )

   oConn:Close()

RETURN


//	=======================================================  //
//  Test 23 -- BindParam with unknown cType returns .F. (no silent NULL).
//	=======================================================  //

STATIC PROCEDURE _Test23_BindParamUnknownTypeFails()

   LOCAL oConn, oStmt, lRc

   oConn := WDO_Sqlite3():New( ":memory:", .T. )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }
   oConn:Open()

   oConn:cError := ""
   oConn:Exec( "CREATE TABLE t_unknown ( id INTEGER )" )

   oStmt := oConn:Prepare( "INSERT INTO t_unknown ( id ) VALUES ( ? )" )

   lRc := oStmt:BindParam( 1, 1, "z" )

   _Check( ! lRc, "23.1 BindParam unknown type returns .F.", "F", hb_CStr( lRc ) )

   _Check( ! Empty( oConn:cError ), "23.2 BindParam unknown type sets cError", ;
      "non-empty", iif( Empty( oConn:cError ), "<empty>", oConn:cError ) )

   oStmt:Free()
   oConn:Close()

RETURN


//	=======================================================  //
//  Test 24 -- Transaction() preserves the error description in
//              oConn:cError when the codeblock raises.
//	=======================================================  //

STATIC PROCEDURE _Test24_TransactionPreservesError()

   LOCAL oConn, lOk, cErr, oStmt, hRow

   oConn := WDO_Sqlite3():New( ":memory:", .T. )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }
   oConn:Open()

   oConn:cError := ""
   oConn:Exec( "CREATE TABLE t_rollback ( id INTEGER )" )

   lOk := oConn:Transaction( {| o | ;
      o:Exec( "INSERT INTO t_rollback ( id ) VALUES ( 1 )" ), ;
      _RaiseError( "intentional-boom" ) ;
   } )

   cErr := oConn:cError

   _Check( ! lOk, "24.1 Transaction returns .F. on raise", "F", hb_CStr( lOk ) )

   _Check( "intentional-boom" $ cErr, ;
      "24.2 cError preserves original description", "intentional-boom", cErr )

   oStmt := oConn:Query( "SELECT COUNT(*) AS c FROM t_rollback" )
   hRow  := oStmt:Fetch_Assoc()
   oStmt:Free()

   _Check( hb_HGetDef( hRow, "c", -1 ) == 0, ;
      "24.3 rollback executed, 0 rows persist", "0", ;
      hb_CStr( hb_HGetDef( hRow, "c", "?" ) ) )

   oConn:Close()

RETURN


//	=======================================================  //
//  Test 25 -- Transaction() with no error must commit.
//	=======================================================  //

STATIC PROCEDURE _Test25_TransactionCommitOk()

   LOCAL oConn, lOk, oStmt, hRow

   oConn := WDO_Sqlite3():New( ":memory:", .T. )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }
   oConn:Open()

   oConn:Exec( "CREATE TABLE t_commit ( id INTEGER )" )

   lOk := oConn:Transaction( {| o | ;
      o:Exec( "INSERT INTO t_commit ( id ) VALUES ( 1 )" ), ;
      o:Exec( "INSERT INTO t_commit ( id ) VALUES ( 2 )" ) ;
   } )

   _Check( lOk, "25.1 Transaction returns .T. on success", "T", hb_CStr( lOk ) )

   oStmt := oConn:Query( "SELECT COUNT(*) AS c FROM t_commit" )
   hRow  := oStmt:Fetch_Assoc()
   oStmt:Free()

   _Check( hb_HGetDef( hRow, "c", -1 ) == 2, ;
      "25.2 commit persisted 2 rows", "2", ;
      hb_CStr( hb_HGetDef( hRow, "c", "?" ) ) )

   oConn:Close()

RETURN


//	=======================================================  //
//  Helper for Test 24.
//	=======================================================  //

STATIC PROCEDURE _RaiseError( cMsg )
   LOCAL oErr
   oErr := ErrorNew()
   oErr:description := cMsg
   Break( oErr )
RETURN


//	=======================================================  //
//  Isolation setup / teardown (Claim 2)
//
//  pool_size:4 is the knob Ruta B introduces. On master it is
//  ignored silently -> singleton -> tests 26-29 fail. After
//  Ruta B the init builds a WDO_Pool of 4 real SQLite conns.
//	=======================================================  //

STATIC PROCEDURE _SetupIsolationPool()

   LOCAL oConn, lOk

   FErase( s_cDbFile )
   FErase( s_cDbFile + "-wal" )
   FErase( s_cDbFile + "-shm" )

   lOk := WDO_InitSqlite3Ex( TX_KEY, { ;
      "file"            => s_cDbFile, ;
      "create"          => .T., ;
      "journal_mode"    => "WAL", ;
      "synchronous"     => "NORMAL", ;
      "busy_timeout_ms" => 5000, ;
      "pool_size"       => 4 } )

   _Check( lOk, "Setup: WDO_InitSqlite3Ex(pool_size:4)", "T", hb_CStr( lOk ) )

   IF ! lOk
      RETURN
   ENDIF

   oConn := WDO_Get( TX_KEY )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }
   oConn:Exec( "CREATE TABLE IF NOT EXISTS t ( n INTEGER )" )
   oConn:Exec( "DELETE FROM t" )
   oConn:Close()

RETURN


STATIC PROCEDURE _CleanupIsolationPool()

   WDO_EndSqlite3( TX_KEY )
   FErase( s_cDbFile )
   FErase( s_cDbFile + "-wal" )
   FErase( s_cDbFile + "-shm" )

RETURN


//	=======================================================  //
//  Test 26 -- Rollback cross-thread contamination
//
//  Thread A opens a transaction, sleeps, then rolls back.
//  Thread B (concurrent) runs a standalone INSERT.
//
//  With a real pool, A and B get different conns -> B's INSERT
//  auto-commits independently -> survives A's rollback.
//  With singleton + per-call mutex, B's INSERT lands inside A's
//  transaction (lInTrans is still .T.) -> A's ROLLBACK drops both
//  rows -> final count 0 instead of 1.
//	=======================================================  //

STATIC PROCEDURE _Test26_RollbackContamination()

   LOCAL hA := { "started" => .F. }
   LOCAL hB := { "done" => .F. }
   LOCAL hThA, hThB
   LOCAL oConn, oStmt, nCount

   _TruncateTable()

   hThA := hb_threadStart( {|| _ThreadRollbackA( hA ) } )
   _WaitFlag( hA, "started", 2000 )

   hThB := hb_threadStart( {|| _ThreadStandaloneInsert( 2, hB ) } )

   hb_threadJoin( hThB )
   hb_threadJoin( hThA )

   oConn := WDO_Get( TX_KEY )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }
   oStmt  := oConn:Query( "SELECT count(*) AS c FROM t" )
   nCount := _AsNum( oStmt:Fetch_Assoc()[ "c" ] )
   oStmt:Free()
   oConn:Close()

   _Check( nCount == 1, ;
      "26.1 B's insert survives A's rollback (pool isolates tx)", ;
      "1", hb_NToS( nCount ) )

RETURN


STATIC PROCEDURE _ThreadRollbackA( hFlag )

   LOCAL oConn := WDO_Get( TX_KEY )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }

   oConn:BeginTrans()
   hFlag[ "started" ] := .T.

   hb_idleSleep( 0.4 )

   oConn:Exec( "INSERT INTO t ( n ) VALUES ( 1 )" )
   oConn:Rollback()

   oConn:Close()

RETURN


STATIC PROCEDURE _ThreadStandaloneInsert( nVal, hFlag )

   LOCAL oConn := WDO_Get( TX_KEY )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }

   oConn:Exec( "INSERT INTO t ( n ) VALUES ( " + hb_NToS( nVal ) + " )" )
   oConn:Close()

   hFlag[ "done" ] := .T.

RETURN


//	=======================================================  //
//  Test 27 -- Two concurrent Transaction() calls both commit.
//	=======================================================  //

STATIC PROCEDURE _Test27_ConcurrentTransactions()

   LOCAL aResults := { "a" => .F., "b" => .F. }
   LOCAL hThA, hThB
   LOCAL oConn, oStmt, nCount

   _TruncateTable()

   hThA := hb_threadStart( {|| aResults[ "a" ] := _ThreadTxn( 11, 250 ) } )
   hThB := hb_threadStart( {|| aResults[ "b" ] := _ThreadTxn( 12, 50 ) } )

   hb_threadJoin( hThA )
   hb_threadJoin( hThB )

   oConn := WDO_Get( TX_KEY )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }
   oStmt  := oConn:Query( "SELECT count(*) AS c FROM t" )
   nCount := _AsNum( oStmt:Fetch_Assoc()[ "c" ] )
   oStmt:Free()
   oConn:Close()

   _Check( aResults[ "a" ] .AND. aResults[ "b" ], ;
      "27.1 both concurrent Transaction() commit", ;
      "T/T", hb_CStr( aResults[ "a" ] ) + "/" + hb_CStr( aResults[ "b" ] ) )

   _Check( nCount == 2, ;
      "27.2 table has both rows after concurrent commits", ;
      "2", hb_NToS( nCount ) )

RETURN


STATIC FUNCTION _ThreadTxn( nVal, nSleepMs )

   LOCAL oConn := WDO_Get( TX_KEY )
   LOCAL lOk

   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }

   lOk := oConn:Transaction( {| o | ;
      o:Exec( "INSERT INTO t ( n ) VALUES ( " + hb_NToS( nVal ) + " )" ), ;
      hb_idleSleep( nSleepMs / 1000 ) } )

   oConn:Close()

RETURN lOk


//	=======================================================  //
//  Test 28 -- Stress: 8 threads x 5 inserts each in own Transaction().
//	=======================================================  //

STATIC PROCEDURE _Test28_StressNoDeadlock()

   LOCAL aThreads := {}, aFlags := {}
   LOCAL i, oConn, oStmt, nCount, nOk

   _TruncateTable()

   FOR i := 1 TO 8
      AAdd( aFlags, { "ok" => .F. } )
   NEXT

   FOR i := 1 TO 8
      AAdd( aThreads, hb_threadStart( {| hF, nIdx | _ThreadBulkTx( hF, nIdx ) }, ;
                                      aFlags[ i ], i ) )
   NEXT

   AEval( aThreads, {| hTh | hb_threadJoin( hTh ) } )

   nOk := 0
   AEval( aFlags, {| hF | iif( hF[ "ok" ], nOk++, NIL ) } )

   _Check( nOk == 8, "28.1 all 8 threads completed", "8", hb_NToS( nOk ) )

   oConn := WDO_Get( TX_KEY )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }
   oStmt  := oConn:Query( "SELECT count(*) AS c FROM t" )
   nCount := _AsNum( oStmt:Fetch_Assoc()[ "c" ] )
   oStmt:Free()
   oConn:Close()

   _Check( nCount == 40, ;
      "28.2 8x5=40 rows committed under concurrent Transaction()", ;
      "40", hb_NToS( nCount ) )

RETURN


STATIC PROCEDURE _ThreadBulkTx( hFlag, nBase )

   LOCAL oConn := WDO_Get( TX_KEY )
   LOCAL i, lOk := .T.

   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }

   FOR i := 1 TO 5
      lOk := oConn:Transaction( {| o | ;
         o:Exec( "INSERT INTO t ( n ) VALUES ( " + hb_NToS( nBase * 100 + i ) + " )" ) } )
      IF ! lOk ; EXIT ; ENDIF
   NEXT

   oConn:Close()
   hFlag[ "ok" ] := lOk

RETURN


//	=======================================================  //
//  Test 29 -- Uncommitted writes invisible across threads.
//
//  Thread A: BEGIN; INSERT 99; sleep; COMMIT.
//  Thread B (fires mid-sleep): SELECT count.
//  Pool: B sees 0 (snapshot before A commits).
//  Singleton: B sees 1 (shared conn, dirty read).
//	=======================================================  //

STATIC PROCEDURE _Test29_UncommittedVisibility()

   LOCAL hA := { "started" => .F., "count_seen_by_b" => -1 }
   LOCAL hThA, hThB

   _TruncateTable()

   hThA := hb_threadStart( {|| _ThreadSlowCommitA( hA ) } )
   _WaitFlag( hA, "started", 2000 )

   hb_idleSleep( 0.1 )

   hThB := hb_threadStart( {|| _ThreadCountB( hA ) } )

   hb_threadJoin( hThB )
   hb_threadJoin( hThA )

   _Check( hA[ "count_seen_by_b" ] == 0, ;
      "29.1 B does not see A's uncommitted insert", ;
      "0", hb_NToS( hA[ "count_seen_by_b" ] ) )

RETURN


STATIC PROCEDURE _ThreadSlowCommitA( hFlag )

   LOCAL oConn := WDO_Get( TX_KEY )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }

   oConn:BeginTrans()
   oConn:Exec( "INSERT INTO t ( n ) VALUES ( 99 )" )
   hFlag[ "started" ] := .T.

   hb_idleSleep( 0.3 )

   oConn:Commit()
   oConn:Close()

RETURN


STATIC PROCEDURE _ThreadCountB( hFlag )

   LOCAL oConn := WDO_Get( TX_KEY )
   LOCAL oStmt, nCount

   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }

   oStmt  := oConn:Query( "SELECT count(*) AS c FROM t" )
   nCount := _AsNum( oStmt:Fetch_Assoc()[ "c" ] )
   oStmt:Free()
   oConn:Close()

   hFlag[ "count_seen_by_b" ] := nCount

RETURN


//	=======================================================  //
//  Isolation helpers
//	=======================================================  //

STATIC PROCEDURE _TruncateTable()

   LOCAL oConn := WDO_Get( TX_KEY )
   oConn:bError := {| oErr | HB_SYMBOL_UNUSED( oErr ), .T. }
   oConn:Exec( "DELETE FROM t" )
   oConn:Close()

RETURN


//  COUNT(*) devuelve numérico (lWeb-safe) o string (si Fetch_Assoc lo
//  escapó como HTML). Normaliza ambos a numérico sin lanzar.
STATIC FUNCTION _AsNum( x )
   IF HB_ISNUMERIC( x ) ; RETU x ; ENDIF
   IF HB_ISSTRING( x )  ; RETU Val( x ) ; ENDIF
RETU 0


STATIC PROCEDURE _WaitFlag( hFlag, cKey, nTimeoutMs )

   LOCAL nDeadline := hb_MilliSeconds() + nTimeoutMs

   DO WHILE ! hFlag[ cKey ] .AND. hb_MilliSeconds() < nDeadline
      hb_idleSleep( 0.01 )
   ENDDO

RETURN
