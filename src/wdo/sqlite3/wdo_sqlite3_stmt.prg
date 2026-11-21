/*-----------------------------------------------------------
  File ......: wdo_sqlite3_stmt.prg
  Author.....: Charly 9000
  Created....: 2026-10-05
  Modified...: 2026-11-20
  Version....: 2.0.0
  Description: Prepared-statement companion to WDO_Sqlite3.
               Wraps sqlite3_prepare_v2 + step + bind + column
               via native DynCall against sqlcipher.dll. Mirrors
               WDO_PgStmt / WDO_MySqlStmt's method surface so
               controllers can swap drivers without churn.
  Usage      : oStmt := oConn:Prepare( "SELECT * FROM u WHERE id=:id" )
               oStmt:BindParam( ":id", 42 )
               oStmt:Execute()
               hRow := oStmt:Fetch_Assoc()
  Notes      : SQLite natively supports `?`, `:name`, `@name`, `$name`
               placeholders. :name resolution goes through
               sqlite3_bind_parameter_index â€” no SQL rewrite needed.
               Parameter indices are 1-based (SQLite native).
 -----------------------------------------------------------*/

#include 'hix_const.ch'
#include 'hix_logger.ch'
#include 'hbclass.ch'
#include "hbdyn.ch"
#include "wdo_sqlite3.ch"


CLASS WDO_Sqlite3Stmt

   DATA oConn
   DATA pDb                            INIT NIL      //  sqlite3* (copy of oConn:pDb)
   DATA pStmt                          INIT NIL      //  sqlite3_stmt*
   DATA cSql
   DATA cTable                                       //  optional, enables DbStruct()

   DATA nColumns                       INIT 0
   DATA aColumnNames                   INIT {}

   DATA lEof                           INIT .T.
   DATA lError                         INIT .F.
   DATA cError                         INIT ''
   DATA nAffectedRows                  INIT 0
   DATA lDone                          INIT .F.     //  step hit SQLITE_DONE
   DATA lFreed                         INIT .F.
   DATA lWeb                           INIT .T.
   DATA aFields                        INIT {}

   METHOD New( oConn, cSql )           CONSTRUCTOR
   METHOD BindParam( xIdx, xVal, cType )
   METHOD BindParams( aValues )
   METHOD BindLong( nIdx, cData )
   METHOD Execute()
   METHOD Fetch()
   METHOD Fetch_Assoc()
   METHOD FetchAll( lAssoc )
   METHOD FCount()                     INLINE ::nColumns
   METHOD Count()                      INLINE -1    //  unknown until done
   METHOD Row_Count()                  INLINE ::nAffectedRows
   METHOD DbStruct()
   METHOD Reset()
   METHOD Free()
   METHOD Destroy()                    INLINE ::Free()
   METHOD End()                        INLINE ::Free()

   //  DynCall wrappers (sqlite3 C API â€” stmt-level)
   METHOD SqlitePrepare( cSql, pStmtOut )
   METHOD SqliteStep()
   METHOD SqliteFinalize()
   METHOD SqliteReset()
   METHOD SqliteClearBindings()
   METHOD SqliteColumnCount()
   METHOD SqliteColumnName( nCol )
   METHOD SqliteColumnType( nCol )
   METHOD SqliteColumnInt64( nCol )
   METHOD SqliteColumnDouble( nCol )
   METHOD SqliteColumnText( nCol )
   METHOD SqliteColumnBytes( nCol )
   METHOD SqliteBindNull( nIdx )
   METHOD SqliteBindInt64( nIdx, nVal )
   METHOD SqliteBindDouble( nIdx, nVal )
   METHOD SqliteBindText( nIdx, cVal )
   METHOD SqliteBindBlob( nIdx, cVal )
   METHOD SqliteBindParameterIndex( cName )

ENDCLASS

//	-------------------------------------------------------  //

METHOD New( oConn, cSql ) CLASS WDO_Sqlite3Stmt

   LOCAL nRc
   LOCAL pStmtOut := 0

   ::oConn := oConn
   ::pDb   := oConn:pDb
   ::cSql  := cSql
   ::lWeb  := oConn:lWeb

   IF ValType(::pDb) != "P"
      ::lError := .T.
      ::cError := _( 'WDO_ERR_SQLITE_PREPARE', "connection not open" )
      RETU SELF
   ENDIF

   nRc := ::SqlitePrepare( cSql, @pStmtOut )

   IF nRc != SQLITE_OK .OR. ValType( pStmtOut ) != "P"
      ::lError := .T.
      ::cError := _( 'WDO_ERR_SQLITE_PREPARE', ;
                     hb_NToS( nRc ) + ": " + oConn:SqliteErrmsg() )
      oConn:SetError( ::cError )
      RETU SELF
   ENDIF

   ::pStmt := pStmtOut

RETU SELF

//	-------------------------------------------------------  //
//  BindParam( xIdx, xVal, cType )
//
//  xIdx: numeric 1-based index OR character ":name" / "@name" / "$name".
//        Bare "name" is auto-prefixed with ":".
//  cType optional: "T" text, "I" int, "D" double, "B" blob, "N" null.
//        Default: inferred from ValType(xVal). NIL always binds NULL.
METHOD BindParam( xIdx, xVal, cType ) CLASS WDO_Sqlite3Stmt

   LOCAL nIdx, cVt, cName, nRc

   IF ValType(::pStmt) != "P"
      RETU .F.
   ENDIF

   //  Resolve named -> numeric via sqlite3_bind_parameter_index.
   IF HB_ISCHAR( xIdx )
      cName := xIdx
      IF Left( cName, 1 ) != ":" .AND. Left( cName, 1 ) != "@" .AND. Left( cName, 1 ) != "$"
         cName := ":" + cName
      ENDIF
      nIdx := ::SqliteBindParameterIndex( cName )
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
      nRc := ::SqliteBindNull( nIdx )
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
         //  Harbour date â†’ ISO text (YYYY-MM-DD).
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
      nRc := ::SqliteBindText( nIdx, hb_CStr( xVal ) )
   CASE cType == "I"
      nRc := ::SqliteBindInt64( nIdx, xVal )
   CASE cType == "D"
      nRc := ::SqliteBindDouble( nIdx, xVal )
   CASE cType == "B"
      nRc := ::SqliteBindBlob( nIdx, xVal )
   OTHERWISE
      nRc := ::SqliteBindNull( nIdx )
   ENDCASE

   IF nRc != SQLITE_OK
      ::lError := .T.
      ::cError := _( 'WDO_ERR_SQLITE_BIND', ;
                     hb_NToS( nRc ) + ": " + ::oConn:SqliteErrmsg() )
      ::oConn:SetError( ::cError )
      RETU .F.
   ENDIF

RETU .T.

//	-------------------------------------------------------  //
//  BindParams( {v1, v2, v3} ) â€” positional shortcut.
METHOD BindParams( aValues ) CLASS WDO_Sqlite3Stmt

   LOCAL i, nLen := Len( aValues )

   FOR i := 1 TO nLen
      IF ! ::BindParam( i, aValues[ i ] )
         RETU .F.
      ENDIF
   NEXT

RETU .T.

//	-------------------------------------------------------  //
//  BindLong: alias to BindParam type "B". SQLite doesn't need chunking
//  (sqlite3_bind_blob takes a full buffer with SQLITE_TRANSIENT), so
//  this exists only for API parity with WDO_MySqlStmtBin.
METHOD BindLong( nIdx, cData ) CLASS WDO_Sqlite3Stmt
RETU ::BindParam( nIdx, cData, "B" )

//	-------------------------------------------------------  //
//  Execute: step once. For SELECT this positions on the first row (if
//  any). For DML it drives the statement to SQLITE_DONE. Sets lEof
//  when no more rows are available.
METHOD Execute() CLASS WDO_Sqlite3Stmt

   LOCAL nRc, i, cName

   IF ValType(::pStmt) != "P"
      RETU .F.
   ENDIF

   hb_mutexLock( ::oConn:hMutex )
   nRc := ::SqliteStep()
   hb_mutexUnlock( ::oConn:hMutex )

   ::lDone := ( nRc == SQLITE_DONE )
   ::lEof  := ::lDone

   IF nRc == SQLITE_ROW
      ::nColumns     := ::SqliteColumnCount()
      ::aColumnNames := Array( ::nColumns )
      FOR i := 1 TO ::nColumns
         cName := ::SqliteColumnName( i - 1 )
         ::aColumnNames[ i ] := iif( cName == NIL .OR. Empty( cName ), ;
                                     "col" + hb_NToS( i ), cName )
      NEXT
   ELSEIF nRc == SQLITE_DONE
      ::nAffectedRows := ::oConn:SqliteChanges()
   ELSE
      ::lError := .T.
      ::cError := _( 'WDO_ERR_SQLITE_STEP', ;
                     hb_NToS( nRc ) + ": " + ::oConn:SqliteErrmsg() )
      ::oConn:SetError( ::cError )
      RETU .F.
   ENDIF

RETU .T.

//	-------------------------------------------------------  //
//  Fetch: array with current row. NIL on EOF. Advances to the next row.
METHOD Fetch() CLASS WDO_Sqlite3Stmt

   LOCAL aRow, i, nRc

   IF ValType(::pStmt) != "P" .OR. ::lEof
      RETU NIL
   ENDIF

   aRow := Array( ::nColumns )

   FOR i := 1 TO ::nColumns
      aRow[ i ] := _Sqlite3CellValue( SELF, i - 1 )
   NEXT

   hb_mutexLock( ::oConn:hMutex )
   nRc := ::SqliteStep()
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
         Val( hb_CStr( hb_HGetDef( hRow, "notnull", 0 ) ) ) == 1, ;
         Val( hb_CStr( hb_HGetDef( hRow, "pk",      0 ) ) ) == 1, ;
         hb_HGetDef( hRow, "dflt_value", NIL ) } )
   ENDDO

   oInfo:Free()

RETU aOut

//	-------------------------------------------------------  //

METHOD Reset() CLASS WDO_Sqlite3Stmt

   IF ValType(::pStmt) != "P"
      RETU .F.
   ENDIF

   ::SqliteReset()
   ::SqliteClearBindings()
   ::lEof   := .T.
   ::lError := .F.
   ::cError := ''

RETU .T.

//	-------------------------------------------------------  //

METHOD Free() CLASS WDO_Sqlite3Stmt

   IF ValType(::pStmt) == "P" .AND. ! ::lFreed
      ::SqliteFinalize()
      ::pStmt := NIL
      ::lFreed := .T.
   ENDIF

   ::lEof := .T.

RETU NIL

//	=======================================================  //
//  DynCall wrappers (sqlite3 C API â€” stmt-level)
//	=======================================================  //

//  int sqlite3_prepare_v2(sqlite3*, const char *zSql, int nByte,
//                         sqlite3_stmt **ppStmt, const char **pzTail)
//  nByte=-1 â†’ zSql is NUL-terminated.
//  pzTail=NULL â†’ we ignore remainder (SQL must be a single statement).
METHOD SqlitePrepare( cSql, pStmtOut ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_prepare_v2", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_CHAR_PTR, HB_DYN_CTYPE_INT,;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_VOID_PTR },;
                   ::pDb, cSql, -1, @pStmtOut, NIL )

//	-------------------------------------------------------  //
//  int sqlite3_step(sqlite3_stmt*)

METHOD SqliteStep() CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_step", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR }, ::pStmt )

//	-------------------------------------------------------  //
//  int sqlite3_finalize(sqlite3_stmt*)

METHOD SqliteFinalize() CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_finalize", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR }, ::pStmt )

//	-------------------------------------------------------  //
//  int sqlite3_reset(sqlite3_stmt*)

METHOD SqliteReset() CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_reset", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR }, ::pStmt )

//	-------------------------------------------------------  //
//  int sqlite3_clear_bindings(sqlite3_stmt*)

METHOD SqliteClearBindings() CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_clear_bindings", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR }, ::pStmt )

//	-------------------------------------------------------  //
//  int sqlite3_column_count(sqlite3_stmt*)

METHOD SqliteColumnCount() CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_column_count", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR }, ::pStmt )

//	-------------------------------------------------------  //
//  const char *sqlite3_column_name(sqlite3_stmt*, int N)
//  N is 0-based.

METHOD SqliteColumnName( nCol ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_column_name", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_CHAR_PTR, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT },;
                   ::pStmt, nCol )

//	-------------------------------------------------------  //
//  int sqlite3_column_type(sqlite3_stmt*, int)

METHOD SqliteColumnType( nCol ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_column_type", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT },;
                   ::pStmt, nCol )

//	-------------------------------------------------------  //
//  sqlite3_int64 sqlite3_column_int64(sqlite3_stmt*, int)

METHOD SqliteColumnInt64( nCol ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_column_int64", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_LLONG, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT },;
                   ::pStmt, nCol )

//	-------------------------------------------------------  //
//  double sqlite3_column_double(sqlite3_stmt*, int)

METHOD SqliteColumnDouble( nCol ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_column_double", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_DOUBLE, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT },;
                   ::pStmt, nCol )

//	-------------------------------------------------------  //
//  const unsigned char *sqlite3_column_text(sqlite3_stmt*, int)
//  SQLite stores TEXT as UTF-8; CHAR_PTR reads until the first NUL.

METHOD SqliteColumnText( nCol ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_column_text", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_CHAR_PTR, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT },;
                   ::pStmt, nCol )

//	-------------------------------------------------------  //
//  int sqlite3_column_bytes(sqlite3_stmt*, int)

METHOD SqliteColumnBytes( nCol ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_column_bytes", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT },;
                   ::pStmt, nCol )

//	-------------------------------------------------------  //
//  int sqlite3_bind_null(sqlite3_stmt*, int)

METHOD SqliteBindNull( nIdx ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_bind_null", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT },;
                   ::pStmt, nIdx )

//	-------------------------------------------------------  //
//  int sqlite3_bind_int64(sqlite3_stmt*, int, sqlite3_int64)

METHOD SqliteBindInt64( nIdx, nVal ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_bind_int64", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT, HB_DYN_CTYPE_LLONG },;
                   ::pStmt, nIdx, nVal )

//	-------------------------------------------------------  //
//  int sqlite3_bind_double(sqlite3_stmt*, int, double)

METHOD SqliteBindDouble( nIdx, nVal ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_bind_double", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT, HB_DYN_CTYPE_DOUBLE },;
                   ::pStmt, nIdx, nVal )

//	-------------------------------------------------------  //
//  int sqlite3_bind_text(sqlite3_stmt*, int, const char*, int, void(*)(void*))
//
//  Last arg is the destructor pointer. We pass SQLITE_TRANSIENT (-1
//  cast to pointer) so SQLite makes its own copy of the string, since
//  we can't guarantee the Harbour string's lifetime past the call.

METHOD SqliteBindText( nIdx, cVal ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_bind_text", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT, HB_DYN_CTYPE_CHAR_PTR,;
                   HB_DYN_CTYPE_INT, HB_DYN_CTYPE_LLONG },;
                   ::pStmt, nIdx, cVal, Len( cVal ), SQLITE_TRANSIENT )

//	-------------------------------------------------------  //
//  int sqlite3_bind_blob(sqlite3_stmt*, int, const void*, int, void(*)(void*))

METHOD SqliteBindBlob( nIdx, cVal ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_bind_blob", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_INT, HB_DYN_CTYPE_CHAR_PTR,;
                   HB_DYN_CTYPE_INT, HB_DYN_CTYPE_LLONG },;
                   ::pStmt, nIdx, cVal, Len( cVal ), SQLITE_TRANSIENT )

//	-------------------------------------------------------  //
//  int sqlite3_bind_parameter_index(sqlite3_stmt*, const char *zName)

METHOD SqliteBindParameterIndex( cName ) CLASS WDO_Sqlite3Stmt

RETU hb_DynCall( { "sqlite3_bind_parameter_index", ::oConn:pLib, ;
                   hb_bitOr( HB_DYN_CTYPE_INT, ::oConn:nSysCallConv ),;
                   HB_DYN_CTYPE_VOID_PTR, HB_DYN_CTYPE_CHAR_PTR },;
                   ::pStmt, cName )

//	=======================================================  //
//  Helpers
//	=======================================================  //

//  Reads column value by native SQLite datatype. nIdx is 0-based (the
//  raw sqlite3_column_* API). Returns NIL for SQLITE_NULL.
STATIC FUNCTION _Sqlite3CellValue( oStmt, nIdx )

   LOCAL nType := oStmt:SqliteColumnType( nIdx )

   DO CASE
   CASE nType == SQLITE_INTEGER
      RETU oStmt:SqliteColumnInt64( nIdx )
   CASE nType == SQLITE_FLOAT
      RETU oStmt:SqliteColumnDouble( nIdx )
   CASE nType == SQLITE_TEXT
      RETU oStmt:SqliteColumnText( nIdx )
   CASE nType == SQLITE_BLOB
      //  Blobs can contain embedded NULs; CHAR_PTR truncates at the
      //  first NUL. Returning the TEXT representation is a safe default
      //  for now â€” proper blob support needs a dedicated hb_DynCall
      //  reading `sqlite3_column_bytes` + an allocated buffer, which
      //  hb_DynCall doesn't expose directly. Callers that need raw
      //  blobs should extend this helper.
      RETU oStmt:SqliteColumnText( nIdx )
   ENDCASE

RETU NIL
