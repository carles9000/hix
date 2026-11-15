/*-----------------------------------------------------------
  File ......: wdo_sqlite3_stmt.prg
  Author.....: Charly 9000
  Created....: 2026-10-05
  Modified...: 2026-10-05
  Version....: 1.0.0
  Description: Prepared-statement companion to WDO_Sqlite3.
               Wraps sqlite3_prepare_v2 + step + bind + column.
               Mirrors WDO_MySqlStmt's method surface where it
               makes sense (Fetch/Fetch_Assoc/FetchAll/BindParam)
               so controllers can swap drivers without churn.
  Usage      : oStmt := oConn:Prepare( "SELECT * FROM u WHERE id=:id" )
               oStmt:BindParam( ":id", 42 )
               oStmt:Execute()
               hRow := oStmt:Fetch_Assoc()
  Notes      : SQLite natively supports `?`, `:name`, `@name`, `$name`
               placeholders. :name resolution goes through
               sqlite3_bind_parameter_index -- no SQL rewrite needed.
               Column indices are 1-based in the hbsqlit3 wrapper.
 -----------------------------------------------------------*/

#include 'hix_const.ch'
#include 'hix_logger.ch'
#include 'hbclass.ch'
#include 'hbsqlit3.ch'


CLASS WDO_Sqlite3Stmt

   DATA oConn
   DATA pDb
   DATA pStmt
   DATA cSql
   DATA cTable                                       // optional, enables DbStruct()

   DATA nColumns                       INIT 0
   DATA aColumnNames                   INIT {}

   DATA lEof                           INIT .T.
   DATA lError                         INIT .F.
   DATA cError                         INIT ''
   DATA nAffectedRows                  INIT 0
   DATA lDone                          INIT .F.      // step hit SQLITE_DONE

   METHOD New( oConn, cSql )           CONSTRUCTOR
   METHOD BindParam( xIdx, xVal, cType )
   METHOD BindParams( aValues )
   METHOD BindLong( nIdx, cData )
   METHOD Execute()
   METHOD Fetch()
   METHOD Fetch_Assoc()
   METHOD FetchAll( lAssoc )
   METHOD FCount()                     INLINE ::nColumns
   METHOD Count()                      INLINE -1
   METHOD DbStruct()
   METHOD Reset()
   METHOD Free()

ENDCLASS

//	-------------------------------------------------------  //

METHOD New( oConn, cSql ) CLASS WDO_Sqlite3Stmt

   LOCAL pStmt

   ::oConn := oConn
   ::pDb   := oConn:pDb
   ::cSql  := cSql

   pStmt := sqlite3_prepare( ::pDb, cSql )

   //  hbsqlit3 returns a Harbour pointer item wrapping NULL C pointer on
   //  prepare error (not NIL). Empty() detects both NIL and null-ptr.
   IF Empty( pStmt )
      ::lError := .T.
      ::cError := _( 'WDO_ERR_SQLITE_PREPARE', ;
                     hb_NToS( sqlite3_errcode( ::pDb ) ) + ": " + sqlite3_errmsg( ::pDb ) )
      oConn:SetError( ::cError )
      RETU SELF
   ENDIF

   ::pStmt := pStmt

RETU SELF

//	-------------------------------------------------------  //
//  BindParam( xIdx, xVal, cType )
//
//  xIdx: numeric 1-based index OR character ":name" / "name" (auto-prefixed).
//  cType optional: "T" text, "I" int, "D" double, "B" blob, "N" null.
//        Default: inferred from ValType(xVal). NIL always binds NULL.
METHOD BindParam( xIdx, xVal, cType ) CLASS WDO_Sqlite3Stmt

   LOCAL nIdx, cVt, cName, nRc

   IF ::pStmt == NIL
      RETU .F.
   ENDIF

   //  Resolve named -> numeric via sqlite3_bind_parameter_index.
   IF HB_ISCHAR( xIdx )
      cName := xIdx
      IF Left( cName, 1 ) != ":" .AND. Left( cName, 1 ) != "@" .AND. Left( cName, 1 ) != "$"
         cName := ":" + cName
      ENDIF
      nIdx := sqlite3_bind_parameter_index( ::pStmt, cName )
      IF nIdx == 0
         ::lError := .T.
         ::cError := _( 'WDO_ERR_SQLITE_BIND', cName + " (not found)" )
         ::oConn:SetError( ::cError )
         RETU .F.
      ENDIF
   ELSE
      nIdx := xIdx
   ENDIF

   //  Explicit NIL -> NULL regardless of cType.
   IF xVal == NIL
      nRc := sqlite3_bind_null( ::pStmt, nIdx )
      RETU nRc == SQLITE_OK
   ENDIF

   IF Empty( cType )
      cVt := ValType( xVal )
      DO CASE
      CASE cVt == "N"
         cType := iif( xVal == Int( xVal ), "I", "D" )
      CASE cVt == "L"
         cType := "I"
         xVal  := iif( xVal, 1, 0 )
      CASE cVt == "D"
         //  Harbour date -> ISO text (YYYY-MM-DD).
         cType := "T"
         xVal  := hb_DToC( xVal, "YYYY-MM-DD" )
      CASE cVt == "T"
         cType := "T"
         xVal  := hb_TToC( xVal, "YYYY-MM-DD", "HH:MM:SS" )
      OTHERWISE
         cType := "T"
      ENDCASE
   ENDIF

   DO CASE
   CASE cType == "T"
      nRc := sqlite3_bind_text( ::pStmt, nIdx, hb_CStr( xVal ) )
   CASE cType == "I"
      nRc := sqlite3_bind_int64( ::pStmt, nIdx, xVal )
   CASE cType == "D"
      nRc := sqlite3_bind_double( ::pStmt, nIdx, xVal )
   CASE cType == "B"
      nRc := sqlite3_bind_blob( ::pStmt, nIdx, xVal )
   OTHERWISE
      nRc := sqlite3_bind_null( ::pStmt, nIdx )
   ENDCASE

   IF nRc != SQLITE_OK
      ::lError := .T.
      ::cError := _( 'WDO_ERR_SQLITE_BIND', hb_NToS( nRc ) + ": " + sqlite3_errmsg( ::pDb ) )
      ::oConn:SetError( ::cError )
      RETU .F.
   ENDIF

RETU .T.

//	-------------------------------------------------------  //
//  BindParams( {v1, v2, v3} ) — positional shortcut.
METHOD BindParams( aValues ) CLASS WDO_Sqlite3Stmt

   LOCAL i, nLen := Len( aValues )

   FOR i := 1 TO nLen
      IF ! ::BindParam( i, aValues[ i ] )
         RETU .F.
      ENDIF
   NEXT

RETU .T.

//	-------------------------------------------------------  //
//  BindLong: alias to BindParam text/blob. SQLite doesn't need chunking
//  (sqlite3_bind_text takes a full buffer with SQLITE_TRANSIENT), so this
//  is kept only for API parity with WDO_MySqlStmtBin.
METHOD BindLong( nIdx, cData ) CLASS WDO_Sqlite3Stmt
RETU ::BindParam( nIdx, cData, "B" )

//	-------------------------------------------------------  //
//  Execute: step once. For SELECT this positions on the first row (if
//  any). For DML it drives the statement to SQLITE_DONE. Sets lEof when
//  no more rows are available.
METHOD Execute() CLASS WDO_Sqlite3Stmt

   LOCAL nRc, i, cName

   IF ::pStmt == NIL
      RETU .F.
   ENDIF

   hb_mutexLock( ::oConn:hMutex )
   nRc := sqlite3_step( ::pStmt )
   hb_mutexUnlock( ::oConn:hMutex )

   ::lDone := ( nRc == SQLITE_DONE )
   ::lEof  := ::lDone

   IF nRc == SQLITE_ROW
      ::nColumns     := sqlite3_column_count( ::pStmt )
      ::aColumnNames := Array( ::nColumns )
      FOR i := 1 TO ::nColumns
         cName := sqlite3_column_name( ::pStmt, i )
         ::aColumnNames[ i ] := iif( cName == NIL, "col" + hb_NToS( i ), cName )
      NEXT
   ELSEIF nRc == SQLITE_DONE
      ::nAffectedRows := sqlite3_changes( ::pDb )
   ELSE
      ::lError := .T.
      ::cError := _( 'WDO_ERR_SQLITE_STEP', hb_NToS( nRc ) + ": " + sqlite3_errmsg( ::pDb ) )
      ::oConn:SetError( ::cError )
      RETU .F.
   ENDIF

RETU .T.

//	-------------------------------------------------------  //
//  Fetch: array with current row. NIL on EOF. Advances to the next row.
METHOD Fetch() CLASS WDO_Sqlite3Stmt

   LOCAL aRow, i, nRc

   IF ::pStmt == NIL .OR. ::lEof
      RETU NIL
   ENDIF

   aRow := Array( ::nColumns )

   FOR i := 1 TO ::nColumns
      aRow[ i ] := _SqliteCellValue( ::pStmt, i )
   NEXT

   hb_mutexLock( ::oConn:hMutex )
   nRc := sqlite3_step( ::pStmt )
   hb_mutexUnlock( ::oConn:hMutex )

   IF nRc != SQLITE_ROW
      ::lEof := .T.
   ENDIF

RETU aRow

//	-------------------------------------------------------  //

METHOD Fetch_Assoc() CLASS WDO_Sqlite3Stmt

   LOCAL hRow, i, aRow

   aRow := ::Fetch()

   IF aRow == NIL
      RETU NIL
   ENDIF

   hRow := { => }

   FOR i := 1 TO ::nColumns
      hRow[ ::aColumnNames[ i ] ] := aRow[ i ]
   NEXT

RETU hRow

//	-------------------------------------------------------  //
//  FetchAll( .T. ) -> array of hashes.
//  FetchAll( .F. ) -> array of arrays.
METHOD FetchAll( lAssoc ) CLASS WDO_Sqlite3Stmt

   LOCAL aOut := {}
   LOCAL xRow

   hb_default( @lAssoc, .T. )

   DO WHILE ! ::lEof
      xRow := iif( lAssoc, ::Fetch_Assoc(), ::Fetch() )
      IF xRow == NIL
         EXIT
      ENDIF
      AAdd( aOut, xRow )
   ENDDO

RETU aOut

//	-------------------------------------------------------  //
//  DbStruct: PRAGMA table_info(cTable) -> array of
//    { cFieldName, cType, nLen, nDec, lNotNull, lPk, uDefault }
//  Empty array if cTable is not set or doesn't exist.
METHOD DbStruct() CLASS WDO_Sqlite3Stmt

   LOCAL aOut := {}
   LOCAL oInfo, hRow, cType, nLen, nDec, nParen

   IF Empty( ::cTable )
      RETU aOut
   ENDIF

   oInfo := ::oConn:Query( "PRAGMA table_info(" + ::cTable + ")" )

   IF oInfo == NIL .OR. oInfo:lError
      RETU aOut
   ENDIF

   DO WHILE ! oInfo:lEof
      hRow := oInfo:Fetch_Assoc()
      IF hRow == NIL
         EXIT
      ENDIF
      //  table_info columns: cid, name, type, notnull, dflt_value, pk
      cType := Upper( AllTrim( hb_HGetDef( hRow, "type", "" ) ) )
      nLen  := 0
      nDec  := 0
      nParen := At( "(", cType )
      IF nParen > 0
         //  e.g. "VARCHAR(100)" or "NUMERIC(10,2)"
         nLen := Val( SubStr( cType, nParen + 1 ) )
         IF "," $ cType
            nDec := Val( SubStr( cType, At( ",", cType ) + 1 ) )
         ENDIF
         cType := Left( cType, nParen - 1 )
      ENDIF
      AAdd( aOut, { ;
         hb_HGetDef( hRow, "name", "" ), ;
         cType,                           ;
         nLen,                            ;
         nDec,                            ;
         hb_HGetDef( hRow, "notnull", 0 ) == 1, ;
         hb_HGetDef( hRow, "pk",      0 ) == 1, ;
         hb_HGetDef( hRow, "dflt_value", NIL ) } )
   ENDDO

   oInfo:Free()

RETU aOut

//	-------------------------------------------------------  //

METHOD Reset() CLASS WDO_Sqlite3Stmt

   IF ::pStmt == NIL
      RETU .F.
   ENDIF

   sqlite3_reset( ::pStmt )
   sqlite3_clear_bindings( ::pStmt )
   ::lEof   := .T.
   ::lError := .F.
   ::cError := ''

RETU .T.

//	-------------------------------------------------------  //

METHOD Free() CLASS WDO_Sqlite3Stmt

   IF ::pStmt != NIL
      sqlite3_finalize( ::pStmt )
      ::pStmt := NIL
   ENDIF

   ::lEof := .T.

RETU NIL

//	=======================================================  //
//  Helpers
//	=======================================================  //

STATIC FUNCTION _SqliteCellValue( pStmt, nIdx )

   LOCAL nType := sqlite3_column_type( pStmt, nIdx )

   DO CASE
   CASE nType == SQLITE_INTEGER
      RETU sqlite3_column_int64( pStmt, nIdx )
   CASE nType == SQLITE_FLOAT
      RETU sqlite3_column_double( pStmt, nIdx )
   CASE nType == SQLITE_TEXT
      RETU sqlite3_column_text( pStmt, nIdx )
   CASE nType == SQLITE_BLOB
      RETU sqlite3_column_blob( pStmt, nIdx )
   ENDCASE

RETU NIL
