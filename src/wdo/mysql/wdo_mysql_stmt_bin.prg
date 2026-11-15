/*-----------------------------------------------------------
  File ......: wdo_mysql_stmt_bin.prg
  Author.....: Charly 9000
  Created....: 2026-09-30
  Modified...: 2026-09-30
  Version....: 1.0.0
  Description: MySQL prepared statement — binary protocol (Alt A).
               Uses mysql_stmt_prepare / bind_param / execute over
               the wire protocol instead of PREPARE/SET/EXECUTE.
               Coexists with WDO_MySqlStmt (Alt B) — user chooses
               via oConn:PrepareBin(cSql, lBinary).
  Usage      : oStmt := oConn:PrepareBin( "INSERT ... VALUES(?, ?)" )
               oStmt:BindParam( 1, 42 )
               oStmt:BindParam( 2, "hello" )
               oStmt:Execute()
               oStmt:Close()
  Notes      : MYSQL_BIND layout is platform-dependent (Windows LLP64
               vs Linux LP64) — offsets resolved once in _InitLayout.
               C helpers live in #pragma BEGINDUMP at the bottom of
               this file — no changes to Harbour core.
 -----------------------------------------------------------*/

#include 'hbclass.ch'
#include 'hbdyn.ch'
#include 'hix_logger.ch'
#include 'wdo_mysql_bind.ch'
#include 'wdo_metrics.ch'

#define VERSION_WDO_MYSQL_STMT_BIN     '1.0'

//  Layout offsets — resolved at runtime by _WdoBindLayoutInit.
//  See docs/mysql/prepared_statements_bin.md §Layout.
STATIC snBindSize           := 0
STATIC snOffLength          := 0
STATIC snOffIsNull          := 0
STATIC snOffBuffer          := 0
STATIC snOffError           := 0        //  v2.5: bool * (fetch truncation flag ptr)
STATIC snOffBufferLength    := 0
STATIC snOffBufferType      := 0
STATIC snOffIsUnsigned      := 0
STATIC snOffIsNullValue     := 0
STATIC snOffErrorValue      := 0        //  v2.5: bool (fetch truncation flag inline)
STATIC snMaxLenPos          := 0        //  v2.5: MYSQL_FIELD.max_length PtrToUI index
STATIC slLayoutOk           := .F.

//  Smoke test guards -- run once per process.
STATIC slSmokeTested        := .F.
STATIC slFetchSmokeTested   := .F.

//	-------------------------------------------------------  //

CLASS WDO_MySqlStmtBin

   DATA oConn
   DATA cSql              INIT ''
   DATA pStmt             INIT NIL     //  MYSQL_STMT *
   DATA pBind             INIT NIL     //  MYSQL_BIND[] buffer (P item, malloc'd)
   DATA pValues           INIT NIL     //  buffer for length_value / is_null_value bytes
   DATA aBuffers          INIT {}      //  per-param Harbour string with the actual data
   DATA aLongData         INIT {}      //  per-param send_long_data pending payload
   DATA nParamCount       INIT 0
   DATA nAffectedRows     INIT 0
   DATA nInsertId         INIT 0
   DATA cError            INIT ''
   DATA lError            INIT .F.
   DATA lPrepared         INIT .F.
   DATA lClosed           INIT .F.
   DATA lWeb              INIT .T.

   //  Resultset side (v2.3.04) ---------------------------------
   DATA hResMeta          INIT 0       //  MYSQL_RES *
   DATA aFields           INIT {}      //  { [i] => { cName, cType, nMysqlType, nBufSize } }
   DATA nFields           INIT 0
   DATA nNumRows          INIT 0       //  mysql_stmt_num_rows after store_result
   DATA pBindOut          INIT NIL     //  MYSQL_BIND[] for fetch
   DATA pDataOut          INIT NIL     //  concatenated per-column buffers
   DATA pMetaOut          INIT NIL     //  per-col { len(8) + is_null(1) + pad(7) + error(8) } blocks (24 bytes)
   DATA aBufOffsets       INIT {}      //  byte offset of each col inside pDataOut
   DATA aBufSizes         INIT {}      //  buffer_length per col
   DATA lStoredResult     INIT .F.
   DATA lHasResultset     INIT .F.

   METHOD New( oConn, cSql ) CONSTRUCTOR
   METHOD BindParam( nIdx, xValue, nType )
   METHOD BindLong( nIdx, cData )
   METHOD Execute()
   METHOD AffectedRows()             INLINE ::nAffectedRows
   METHOD LastInsertId()             INLINE ::nInsertId
   METHOD Row_Count()                INLINE iif( ::lHasResultset, ::nNumRows, ::nAffectedRows )
   METHOD Close()
   METHOD Free()                     INLINE ::Close()
   METHOD Destroy()                  INLINE ::Close()
   METHOD End()                      INLINE ::Close()

   //  Resultset API (v2.3.04) ----------------------------------
   METHOD LoadStruct()
   METHOD FCount()                   INLINE ::nFields
   METHOD DbStruct()                 INLINE ::aFields
   METHOD Count()                    INLINE ::nNumRows
   METHOD Fetch( aNoEscape )
   METHOD Fetch_Assoc( aNoEscape )
   METHOD FetchAll( lAssoc, aNoEscape )

   METHOD Version()                  INLINE VERSION_WDO_MYSQL_STMT_BIN
   METHOD VersionName()              INLINE 'WDO_MYSQL_STMT_BIN ' + VERSION_WDO_MYSQL_STMT_BIN

ENDCLASS

//	-------------------------------------------------------  //
//  Resolve MYSQL_BIND layout constants for the current platform.
//  Called once from the first WDO_MySqlStmtBin:New().
//	-------------------------------------------------------  //
STATIC PROCEDURE _WdoBindLayoutInit()

   IF slLayoutOk ; RETU ; ENDIF

   //  Common offsets — same on Windows LLP64 and Linux LP64.
   snOffLength       := 0     //  unsigned long *
   snOffIsNull       := 8     //  bool *
   snOffBuffer       := 16    //  void *
   snOffError        := 24    //  bool *  (fetch truncation flag ptr)
   snOffBufferLength := 64    //  unsigned long

   IF "Windows" $ OS()
      //  Windows LLP64: sizeof(long) = 4
      snBindSize        := 104
      snOffBufferType   := 84
      snOffErrorValue   := 88
      snOffIsUnsigned   := 89
      snOffIsNullValue  := 91
      snMaxLenPos       := 15    //  MYSQL_FIELD.max_length byte 60 / 4
   ELSE
      //  Linux LP64: sizeof(long) = 8
      snBindSize        := 112
      snOffBufferType   := 96
      snOffErrorValue   := 100
      snOffIsUnsigned   := 101
      snOffIsNullValue  := 103
      snMaxLenPos       := 16    //  MYSQL_FIELD.max_length byte 64 / 4
   ENDIF

   slLayoutOk := .T.

RETURN

//	-------------------------------------------------------  //
//  Constructor. Prepares the statement on the server and
//  allocates the MYSQL_BIND buffer sized by param count.
//	-------------------------------------------------------  //
METHOD New( oConn, cSql ) CLASS WDO_MySqlStmtBin

   LOCAL nT0

   _WdoBindLayoutInit()

   ::oConn := oConn
   ::cSql  := cSql
   ::lWeb  := oConn:lWeb

   nT0 := hb_MilliSeconds()

   ::pStmt := oConn:mysql_stmt_init()

   IF ::pStmt == NIL .OR. ::pStmt == 0
      ::lError := .T.
      ::cError := "mysql_stmt_init failed"
      WDO_Metric( WDOM_QUERIES_ERRORS )
      RETU SELF
   ENDIF

   IF oConn:mysql_stmt_prepare( ::pStmt, cSql ) != 0
      ::lError := .T.
      ::cError := oConn:mysql_stmt_error( ::pStmt )
      WDO_Metric( WDOM_QUERIES_ERRORS )
      WDO_MetricQuery( oConn:cPoolKey, "PREPAREBIN " + cSql,;
                       hb_MilliSeconds() - nT0, NIL )
      RETU SELF
   ENDIF

   ::nParamCount := oConn:mysql_stmt_param_count( ::pStmt )
   ::lPrepared   := .T.
   ::aBuffers    := Array( ::nParamCount )
   ::aLongData   := Array( ::nParamCount )

   IF ::nParamCount > 0
      //  MYSQL_BIND array (zeroed by WDO_BindAlloc).
      ::pBind   := WDO_BindAlloc( ::nParamCount * snBindSize )
      //  Per-param length_value (8 bytes) + is_null_value (1 byte, aligned to 8).
      //  Layout: [len0(8)][null0(1)][pad(7)][len1(8)][null1(1)][pad(7)]...
      ::pValues := WDO_BindAlloc( ::nParamCount * 16 )
   ENDIF

   WDO_MetricQuery( oConn:cPoolKey, "PREPAREBIN " + cSql,;
                    hb_MilliSeconds() - nT0, NIL )

RETU SELF

//	-------------------------------------------------------  //
//  BindParam( nIdx, xValue, nType )
//
//  Writes one MYSQL_BIND slot (0-based internally, but nIdx is 1-based
//  to match Alt B). Auto-detects nType from Harbour ValType if omitted:
//     "C" → VAR_STRING       "L" → TINY (1 byte)
//     "N" integer → LONGLONG  "N" float → DOUBLE
//     "D" → STRING "YYYY-MM-DD"
//     "T" → STRING "YYYY-MM-DD HH:MM:SS"
//     "U" / NIL   → NULL
//	-------------------------------------------------------  //
METHOD BindParam( nIdx, xValue, nType ) CLASS WDO_MySqlStmtBin

   LOCAL nOff, nSlot, cValType, cData, nValOff
   LOCAL nBufLen, xInt64

   IF ! ::lPrepared .OR. nIdx < 1 .OR. nIdx > ::nParamCount
      RETU .F.
   ENDIF

   nSlot := nIdx - 1              //  0-based into pBind
   nOff  := nSlot * snBindSize    //  base offset for this slot inside pBind
   nValOff := nSlot * 16          //  base offset inside pValues

   //  Auto-detect type from Harbour ValType if nType is omitted.
   cValType := ValType( xValue )
   IF nType == NIL
      DO CASE
      CASE xValue == NIL         ; nType := WDO_MYSQL_TYPE_NULL
      CASE cValType == "C"       ; nType := WDO_MYSQL_TYPE_VAR_STRING
      CASE cValType == "L"       ; nType := WDO_MYSQL_TYPE_TINY
      CASE cValType == "D"       ; nType := WDO_MYSQL_TYPE_STRING
      CASE cValType == "T"       ; nType := WDO_MYSQL_TYPE_STRING
      CASE cValType == "N"
         IF xValue == Int( xValue ) .AND. Abs( xValue ) < 2147483648
            nType := WDO_MYSQL_TYPE_LONG
         ELSEIF xValue == Int( xValue )
            nType := WDO_MYSQL_TYPE_LONGLONG
         ELSE
            nType := WDO_MYSQL_TYPE_DOUBLE
         ENDIF
      OTHERWISE
         nType := WDO_MYSQL_TYPE_VAR_STRING
      ENDCASE
   ENDIF

   //  Materialize the value into a Harbour string (aBuffers[nIdx]) so its
   //  address stays valid during Execute(). WDO_BindPokePtr captures the
   //  address into MYSQL_BIND.buffer.
   DO CASE

   CASE nType == WDO_MYSQL_TYPE_NULL
      //  NULL: set is_null_value=1 and pointer to it, buffer_type=NULL.
      WDO_BindPokeByte( ::pValues, nValOff + 8, 1 )
      WDO_BindPokePtrOff( ::pBind, nOff + snOffIsNull, ::pValues, nValOff + 8 )
      WDO_BindPokeInt32( ::pBind, nOff + snOffBufferType, WDO_MYSQL_TYPE_NULL )
      ::aBuffers[ nIdx ] := ""
      RETU .T.

   CASE nType == WDO_MYSQL_TYPE_TINY
      cData   := hb_bChar( iif( xValue, 1, 0 ) )
      nBufLen := 1

   CASE nType == WDO_MYSQL_TYPE_LONG
      cData   := L2Bin( Int( xValue ) )
      nBufLen := 4

   CASE nType == WDO_MYSQL_TYPE_LONGLONG
      xInt64  := Int( xValue )
      cData   := _WdoInt64Le( xInt64 )
      nBufLen := 8

   CASE nType == WDO_MYSQL_TYPE_DOUBLE
      cData   := _WdoDoubleLe( xValue )
      nBufLen := 8

   CASE cValType == "D"
      cData   := DToC2( xValue )  //  YYYY-MM-DD via helper below
      nBufLen := Len( cData )

   CASE cValType == "T"
      cData   := hb_TToC( xValue, "YYYY-MM-DD", "HH:MM:SS" )
      IF Len( cData ) == 10 ; cData += " 00:00:00" ; ENDIF
      nBufLen := Len( cData )

   OTHERWISE
      //  Default: pass raw bytes. Assumes UTF-8-safe (mysql_real_connect
      //  charset already set by pool bootstrap).
      cData   := hb_CStr( xValue )
      nBufLen := Len( cData )

   ENDCASE

   ::aBuffers[ nIdx ] := cData

   //  Poke pointer to Harbour string buffer via helper (needs C to read
   //  the internal address of the Harbour string).
   WDO_BindPokeStrPtr( ::pBind, nOff + snOffBuffer, cData )
   WDO_BindPokeInt64( ::pBind, nOff + snOffBufferLength, nBufLen )
   WDO_BindPokeInt32( ::pBind, nOff + snOffBufferType, nType )

   //  Length pointer → per-param length_value slot inside pValues.
   WDO_BindPokeInt64( ::pValues, nValOff, nBufLen )
   WDO_BindPokePtrOff( ::pBind, nOff + snOffLength, ::pValues, nValOff )

   //  Clear is_null_value slot + set is_unsigned=0 explicitly.
   WDO_BindPokeByte( ::pValues, nValOff + 8, 0 )
   WDO_BindPokeByte( ::pBind, nOff + snOffIsUnsigned, 0 )

RETU .T.

//	-------------------------------------------------------  //
//  BindLong( nIdx, cData )
//
//  Queues a chunk to be sent via mysql_stmt_send_long_data at
//  Execute() time. buffer_type is set to BLOB, buffer_length=0.
//  Call multiple times to send BLOB in chunks — chunks accumulate.
//	-------------------------------------------------------  //
METHOD BindLong( nIdx, cData ) CLASS WDO_MySqlStmtBin

   LOCAL nOff

   IF ! ::lPrepared .OR. nIdx < 1 .OR. nIdx > ::nParamCount
      RETU .F.
   ENDIF

   nOff := ( nIdx - 1 ) * snBindSize

   IF ::aLongData[ nIdx ] == NIL
      ::aLongData[ nIdx ] := ""
      //  buffer_type=BLOB, buffer_length=0, buffer=NULL. Server assembles.
      WDO_BindPokeInt32( ::pBind, nOff + snOffBufferType, WDO_MYSQL_TYPE_BLOB )
      WDO_BindPokeInt64( ::pBind, nOff + snOffBufferLength, 0 )
   ENDIF

   ::aLongData[ nIdx ] += cData

RETU .T.

//	-------------------------------------------------------  //
//  Execute()
//
//  Runs mysql_stmt_bind_param (if any params) + optional
//  send_long_data loop + mysql_stmt_execute. Captures
//  affected_rows and insert_id.
//	-------------------------------------------------------  //
METHOD Execute() CLASS WDO_MySqlStmtBin

   LOCAL nT0
   LOCAL nRc
   LOCAL i, cChunk
   LOCAL nChunkSize := 65536

   IF ! ::lPrepared
      ::lError := .T.
      ::cError := "stmt not prepared"
      RETU .F.
   ENDIF

   nT0 := hb_MilliSeconds()

   //  Smoke test on very first Execute of the process — validates that
   //  the hardcoded MYSQL_BIND layout matches the actual libmysql ABI.
   IF ! slSmokeTested
      _WdoBindSmokeTest( ::oConn )
      //  slSmokeTested is flipped inside _WdoBindSmokeTest regardless
      //  of outcome — we never run it twice.
   ENDIF

   IF ::nParamCount > 0
      IF ::oConn:mysql_stmt_bind_param( ::pStmt, ::pBind )
         ::lError := .T.
         ::cError := ::oConn:mysql_stmt_error( ::pStmt )
         WDO_Metric( WDOM_QUERIES_ERRORS )
         WDO_MetricQuery( ::oConn:cPoolKey, "EXECBIN " + ::cSql,;
                          hb_MilliSeconds() - nT0, NIL )
         RETU .F.
      ENDIF

      //  Flush any pending send_long_data payloads.
      FOR i := 1 TO ::nParamCount
         IF ::aLongData[ i ] != NIL .AND. Len( ::aLongData[ i ] ) > 0
            //  Chunk in 64 KB slices to be safe with max_allowed_packet.
            DO WHILE Len( ::aLongData[ i ] ) > 0
               cChunk := hb_BSubStr( ::aLongData[ i ], 1, nChunkSize )
               ::aLongData[ i ] := hb_BSubStr( ::aLongData[ i ], nChunkSize + 1 )
               IF ::oConn:mysql_stmt_send_long_data( ::pStmt, i - 1, cChunk )
                  ::lError := .T.
                  ::cError := ::oConn:mysql_stmt_error( ::pStmt )
                  WDO_Metric( WDOM_QUERIES_ERRORS )
                  RETU .F.
               ENDIF
            ENDDO
         ENDIF
      NEXT
   ENDIF

   nRc := ::oConn:mysql_stmt_execute( ::pStmt )

   IF nRc != 0
      ::lError := .T.
      ::cError := ::oConn:mysql_stmt_error( ::pStmt )
      WDO_Metric( WDOM_QUERIES_ERRORS )
      WDO_MetricQuery( ::oConn:cPoolKey, "EXECBIN " + ::cSql,;
                       hb_MilliSeconds() - nT0, NIL )
      RETU .F.
   ENDIF

   ::nAffectedRows := ::oConn:mysql_stmt_affected_rows( ::pStmt )
   ::nInsertId     := ::oConn:mysql_stmt_insert_id( ::pStmt )
   ::oConn:tLastUsed := hb_DateTime()

   //  Detect SELECT (or CALL with resultset) and prepare fetch infra.
   //  mysql_stmt_result_metadata returns NULL for non-SELECT statements.
   IF ::hResMeta != 0
      //  Re-Execute path: free previous metadata/buffers before rebuilding.
      ::oConn:mysql_free_result( ::hResMeta )
      ::hResMeta := 0
      _FreeOutputBuffers( SELF )
      ::lStoredResult := .F.
      ::lHasResultset := .F.
   ENDIF

   ::hResMeta := ::oConn:mysql_stmt_result_metadata( ::pStmt )

   IF ::hResMeta != 0 .AND. ::hResMeta != NIL
      ::lHasResultset := .T.
      ::LoadStruct()                            //  reads max_length and types

      //  Enable max_length tracking BEFORE store_result -- otherwise
      //  MYSQL_FIELD.max_length stays 0 and buffers end up sized to 1.
      _EnableMaxLength( ::oConn, ::pStmt )

      //  store_result pulls all rows client-side -- needed for max_length
      //  to reflect actual data, not schema. Must happen BEFORE _Alloc.
      IF ::oConn:mysql_stmt_store_result( ::pStmt ) != 0
         ::lError := .T.
         ::cError := "store_result failed: " + ::oConn:mysql_stmt_error( ::pStmt )
         WDO_Metric( WDOM_QUERIES_ERRORS )
         WDO_MetricQuery( ::oConn:cPoolKey, "EXECBIN " + ::cSql,;
                          hb_MilliSeconds() - nT0, NIL )
         RETU .F.
      ENDIF
      ::lStoredResult := .T.
      ::nNumRows      := ::oConn:mysql_stmt_num_rows( ::pStmt )

      //  Now max_length is populated. Re-read it to size the output buffers.
      _RefreshMaxLengths( SELF )
      _AllocOutputBuffers( SELF )

      IF ::oConn:mysql_stmt_bind_result( ::pStmt, ::pBindOut )
         ::lError := .T.
         ::cError := "bind_result failed: " + ::oConn:mysql_stmt_error( ::pStmt )
         WDO_Metric( WDOM_QUERIES_ERRORS )
         WDO_MetricQuery( ::oConn:cPoolKey, "EXECBIN " + ::cSql,;
                          hb_MilliSeconds() - nT0, NIL )
         RETU .F.
      ENDIF

      //  First-call smoke test for output layout -- cheap sanity check
      //  against future libmysql ABI changes.
      IF ! slFetchSmokeTested
         _WdoFetchSmokeTest( ::oConn )
      ENDIF
   ENDIF

   WDO_MetricQuery( ::oConn:cPoolKey, "EXECBIN " + ::cSql,;
                    hb_MilliSeconds() - nT0, NIL )

RETU .T.

//	-------------------------------------------------------  //
//  LoadStruct()
//
//  Reads field metadata (name, mysql type, max_length) from
//  the MYSQL_RES* returned by mysql_stmt_result_metadata.
//  Reuses PtrToStr/PtrToUI from the Alt B driver.
//	-------------------------------------------------------  //
METHOD LoadStruct() CLASS WDO_MySqlStmtBin

   LOCAL n, hField, nMysqlType, nMaxLen, cHarbourType
   LOCAL nTypePos := ::oConn:nTypePos

   IF ::hResMeta == 0 ; RETU NIL ; ENDIF

   ::nFields := ::oConn:mysql_num_fields( ::hResMeta )
   ::aFields := Array( ::nFields )

   FOR n := 1 TO ::nFields
      hField := ::oConn:mysql_fetch_field( ::hResMeta )
      IF hField == 0 ; LOOP ; ENDIF

      nMysqlType := PtrToUI( hField, nTypePos )
      nMaxLen    := PtrToUI( hField, snMaxLenPos )
      cHarbourType := _WdoHbTypeOf( nMysqlType )

      ::aFields[n] := { PtrToStr( hField, 0 ), cHarbourType, nMysqlType, nMaxLen }
   NEXT

RETU NIL

//	-------------------------------------------------------  //
//  Fetch( aNoEscape ) -> array or NIL
//
//  Pulls one row from the stored result. Returns NIL when no
//  more rows (MYSQL_NO_DATA = 100).
//	-------------------------------------------------------  //
METHOD Fetch( aNoEscape ) CLASS WDO_MySqlStmtBin

   LOCAL nRc, aReg, i, nLen, lNull, xVal, nMetaBase

   hb_default( @aNoEscape, {} )

   IF ! ::lHasResultset ; RETU NIL ; ENDIF

   nRc := ::oConn:mysql_stmt_fetch( ::pStmt )

   DO CASE
   CASE nRc == 100         //  MYSQL_NO_DATA
      RETU NIL
   CASE nRc == 1           //  error
      ::lError := .T.
      ::cError := ::oConn:mysql_stmt_error( ::pStmt )
      RETU NIL
   ENDCASE
   //  nRc == 0 OK  or  nRc == 101 DATA_TRUNCATED -- treat as OK since
   //  our buffers are sized from max_length (post store_result).

   aReg := Array( ::nFields )
   FOR i := 1 TO ::nFields
      nMetaBase := (i - 1) * 24
      lNull     := ( WDO_BindPeekByte( ::pMetaOut, nMetaBase + 8 ) != 0 )
      IF lNull
         aReg[i] := NIL
         LOOP
      ENDIF
      nLen := WDO_BindPeekInt64( ::pMetaOut, nMetaBase )
      xVal := _WdoDecodeCol( SELF, i, nLen )
      IF HB_ISSTRING( xVal ) .AND. ::lWeb .AND.;
         AScan( aNoEscape, ::aFields[i, 1] ) == 0
         xVal := wdo_htmlencode( xVal )
      ENDIF
      aReg[i] := xVal
   NEXT

RETU aReg

//	-------------------------------------------------------  //

METHOD Fetch_Assoc( aNoEscape ) CLASS WDO_MySqlStmtBin

   LOCAL aRow, hReg, i

   aRow := ::Fetch( aNoEscape )
   IF aRow == NIL ; RETU NIL ; ENDIF

   hReg := {=>}
   FOR i := 1 TO ::nFields
      hReg[ ::aFields[i, 1] ] := aRow[i]
   NEXT

RETU hReg

//	-------------------------------------------------------  //

METHOD FetchAll( lAssoc, aNoEscape ) CLASS WDO_MySqlStmtBin

   LOCAL aData := {}
   LOCAL xRow

   __defaultNIL( @lAssoc,    .F. )
   __defaultNIL( @aNoEscape, {}  )

   IF lAssoc
      DO WHILE ( xRow := ::Fetch_Assoc( aNoEscape ) ) != NIL
         AAdd( aData, xRow )
      ENDDO
   ELSE
      DO WHILE ( xRow := ::Fetch( aNoEscape ) ) != NIL
         AAdd( aData, xRow )
      ENDDO
   ENDIF

RETU aData

//	-------------------------------------------------------  //
//  Close()
//
//  Idempotent. Releases mysql_stmt handle and frees the two
//  malloc'd C buffers. Safe to call twice.
//	-------------------------------------------------------  //
METHOD Close() CLASS WDO_MySqlStmtBin

   IF ::lClosed ; RETU NIL ; ENDIF

   //  Release stored resultset first (if any) -- frees server-side cursor
   //  buffers before stmt_close.
   IF ::lStoredResult .AND. ::pStmt != NIL .AND. ::pStmt != 0 .AND. ::oConn != NIL
      ::oConn:mysql_stmt_free_result( ::pStmt )
      ::lStoredResult := .F.
   ENDIF

   //  Free metadata handle (independent of store_result).
   IF ::hResMeta != 0 .AND. ::oConn != NIL
      ::oConn:mysql_free_result( ::hResMeta )
      ::hResMeta := 0
   ENDIF

   _FreeOutputBuffers( SELF )

   IF ::pStmt != NIL .AND. ::pStmt != 0 .AND. ::oConn != NIL
      ::oConn:mysql_stmt_close( ::pStmt )
   ENDIF

   IF ::pBind != NIL
      WDO_BindFree( ::pBind )
      ::pBind := NIL
   ENDIF

   IF ::pValues != NIL
      WDO_BindFree( ::pValues )
      ::pValues := NIL
   ENDIF

   ::lClosed := .T.

RETU NIL

//	=======================================================  //
//  Helpers (STATIC — file scope)
//	=======================================================  //

//  _EnableMaxLength -- toggles STMT_ATTR_UPDATE_MAX_LENGTH on so that
//  mysql_stmt_store_result populates MYSQL_FIELD.max_length with the
//  real byte-length of each column. Without this, max_length stays 0
//  and our buffers end up sized to 1 -- strings get truncated.
STATIC PROCEDURE _EnableMaxLength( oConn, pStmt )

   LOCAL pFlag := WDO_BindAlloc( 1 )
   WDO_BindPokeByte( pFlag, 0, 1 )
   oConn:mysql_stmt_attr_set( pStmt, WDO_STMT_ATTR_UPDATE_MAX_LENGTH, pFlag )
   WDO_BindFree( pFlag )

RETURN

//	-------------------------------------------------------  //
//  _WdoHbTypeOf -- single-letter Harbour type tag for a MySQL field.
STATIC FUNCTION _WdoHbTypeOf( nMysqlType )

   DO CASE
   CASE AScan( { 253, 254, 15 }, nMysqlType ) != 0
      RETU "C"
   CASE AScan( { 1, 2, 3, 4, 5, 8, 9, 246 }, nMysqlType ) != 0
      RETU "N"
   CASE AScan( { 10, 12, 7, 14 }, nMysqlType ) != 0
      RETU "D"
   CASE AScan( { 249, 250, 251, 252 }, nMysqlType ) != 0
      RETU "M"
   ENDCASE
RETU "C"

//	-------------------------------------------------------  //
//  _WdoBufSizeFor -- bytes needed for the output buffer of a column.
//  nMaxLen comes from MYSQL_FIELD.max_length after store_result; for
//  fixed-size numeric types we override with the native size.
STATIC FUNCTION _WdoBufSizeFor( nMysqlType, nMaxLen )

   DO CASE
   CASE nMysqlType == WDO_MYSQL_TYPE_TINY      ; RETU 1
   CASE nMysqlType == WDO_MYSQL_TYPE_SHORT     ; RETU 2
   CASE nMysqlType == WDO_MYSQL_TYPE_LONG      ; RETU 4
   CASE nMysqlType == WDO_MYSQL_TYPE_INT24     ; RETU 4
   CASE nMysqlType == WDO_MYSQL_TYPE_LONGLONG  ; RETU 8
   CASE nMysqlType == WDO_MYSQL_TYPE_FLOAT     ; RETU 4
   CASE nMysqlType == WDO_MYSQL_TYPE_DOUBLE    ; RETU 8
   CASE nMysqlType == WDO_MYSQL_TYPE_NULL      ; RETU 0
   ENDCASE
   //  String/blob/datetime -- use max_length, fallback 1 if empty col.
RETU Max( nMaxLen, 1 )

//	-------------------------------------------------------  //
//  _WdoBufTypeFor -- buffer_type to request from MySQL. We ask strings
//  for anything variable-width (easier to decode on the Harbour side);
//  fixed numerics stay native.
STATIC FUNCTION _WdoBufTypeFor( nMysqlType )

   DO CASE
   CASE nMysqlType == WDO_MYSQL_TYPE_TINY      ; RETU WDO_MYSQL_TYPE_TINY
   CASE nMysqlType == WDO_MYSQL_TYPE_SHORT     ; RETU WDO_MYSQL_TYPE_SHORT
   CASE nMysqlType == WDO_MYSQL_TYPE_LONG      ; RETU WDO_MYSQL_TYPE_LONG
   CASE nMysqlType == WDO_MYSQL_TYPE_INT24     ; RETU WDO_MYSQL_TYPE_LONG
   CASE nMysqlType == WDO_MYSQL_TYPE_LONGLONG  ; RETU WDO_MYSQL_TYPE_LONGLONG
   CASE nMysqlType == WDO_MYSQL_TYPE_FLOAT     ; RETU WDO_MYSQL_TYPE_FLOAT
   CASE nMysqlType == WDO_MYSQL_TYPE_DOUBLE    ; RETU WDO_MYSQL_TYPE_DOUBLE
   CASE AScan( { 249, 250, 251, 252 }, nMysqlType ) != 0
      RETU WDO_MYSQL_TYPE_BLOB
   ENDCASE
   //  DECIMAL/NEWDECIMAL/DATE/DATETIME/TIME/TIMESTAMP/VAR_STRING/STRING
   //  -- always ask for STRING, decoded on Harbour side.
RETU WDO_MYSQL_TYPE_STRING

//	-------------------------------------------------------  //
//  _RefreshMaxLengths -- re-reads max_length from MYSQL_FIELD after
//  store_result. mysql_fetch_field iterates per-call, so we rewind
//  the metadata cursor by re-asking metadata for the stmt.
STATIC PROCEDURE _RefreshMaxLengths( oStmt )

   LOCAL n, hField
   LOCAL oConn := oStmt:oConn

   //  mysql_fetch_field has an internal cursor; the easiest rewind is
   //  mysql_fetch_field_direct. We don't have that wrapped, so instead
   //  we free + reacquire the metadata handle. Cheap -- server-side it
   //  is a plain lookup, no network.
   IF oStmt:hResMeta != 0
      oConn:mysql_free_result( oStmt:hResMeta )
   ENDIF
   oStmt:hResMeta := oConn:mysql_stmt_result_metadata( oStmt:pStmt )

   FOR n := 1 TO oStmt:nFields
      hField := oConn:mysql_fetch_field( oStmt:hResMeta )
      IF hField != 0
         oStmt:aFields[n, 4] := PtrToUI( hField, snMaxLenPos )
      ENDIF
   NEXT

RETURN

//	-------------------------------------------------------  //
//  _AllocOutputBuffers -- malloc pBindOut + pDataOut + pMetaOut and
//  wire every MYSQL_BIND slot to the right spot inside the three
//  slabs. Called once per Execute() over a resultset.
STATIC PROCEDURE _AllocOutputBuffers( oStmt )

   LOCAL n, nTotal, nBufSize, nBufType, nOff, nMetaBase

   oStmt:pBindOut   := WDO_BindAlloc( oStmt:nFields * snBindSize )
   //  Per-col: 8 bytes length + 1 byte is_null + 7 pad + 8 bytes error = 24
   oStmt:pMetaOut   := WDO_BindAlloc( oStmt:nFields * 24 )
   oStmt:aBufOffsets := Array( oStmt:nFields )
   oStmt:aBufSizes   := Array( oStmt:nFields )

   nTotal := 0
   FOR n := 1 TO oStmt:nFields
      nBufSize := _WdoBufSizeFor( oStmt:aFields[n, 3], oStmt:aFields[n, 4] )
      oStmt:aBufOffsets[n] := nTotal
      oStmt:aBufSizes[n]   := nBufSize
      nTotal += nBufSize
   NEXT

   oStmt:pDataOut := WDO_BindAlloc( Max( nTotal, 1 ) )

   FOR n := 1 TO oStmt:nFields
      nOff      := (n - 1) * snBindSize
      nMetaBase := (n - 1) * 24
      nBufType  := _WdoBufTypeFor( oStmt:aFields[n, 3] )

      //  buffer -> pDataOut + offset
      WDO_BindPokePtrOff( oStmt:pBindOut, nOff + snOffBuffer,;
                          oStmt:pDataOut, oStmt:aBufOffsets[n] )
      //  buffer_length
      WDO_BindPokeInt64( oStmt:pBindOut, nOff + snOffBufferLength, oStmt:aBufSizes[n] )
      //  buffer_type
      WDO_BindPokeInt32( oStmt:pBindOut, nOff + snOffBufferType, nBufType )
      //  length ptr -> pMetaOut + base + 0
      WDO_BindPokePtrOff( oStmt:pBindOut, nOff + snOffLength,;
                          oStmt:pMetaOut, nMetaBase )
      //  is_null ptr -> pMetaOut + base + 8
      WDO_BindPokePtrOff( oStmt:pBindOut, nOff + snOffIsNull,;
                          oStmt:pMetaOut, nMetaBase + 8 )
      //  error ptr -> pMetaOut + base + 16
      WDO_BindPokePtrOff( oStmt:pBindOut, nOff + snOffError,;
                          oStmt:pMetaOut, nMetaBase + 16 )
   NEXT

RETURN

//	-------------------------------------------------------  //
//  _FreeOutputBuffers -- idempotent free of fetch slabs.
STATIC PROCEDURE _FreeOutputBuffers( oStmt )

   IF oStmt:pBindOut != NIL
      WDO_BindFree( oStmt:pBindOut )
      oStmt:pBindOut := NIL
   ENDIF
   IF oStmt:pDataOut != NIL
      WDO_BindFree( oStmt:pDataOut )
      oStmt:pDataOut := NIL
   ENDIF
   IF oStmt:pMetaOut != NIL
      WDO_BindFree( oStmt:pMetaOut )
      oStmt:pMetaOut := NIL
   ENDIF
   oStmt:aBufOffsets := {}
   oStmt:aBufSizes   := {}

RETURN

//	-------------------------------------------------------  //
//  _WdoDecodeCol -- extract a Harbour value for column i given the
//  real length nLen (from pMetaOut).
STATIC FUNCTION _WdoDecodeCol( oStmt, i, nLen )

   LOCAL nMysqlType := oStmt:aFields[i, 3]
   LOCAL nOff       := oStmt:aBufOffsets[i]
   LOCAL cStr

   DO CASE
   CASE nMysqlType == WDO_MYSQL_TYPE_TINY
      RETU WDO_BindPeekByte( oStmt:pDataOut, nOff )
   CASE nMysqlType == WDO_MYSQL_TYPE_SHORT
      //  Signed short -- read 2 bytes LE, sign-extend.
      RETU _I16( WDO_BindPeekInt32( oStmt:pDataOut, nOff ) )
   CASE nMysqlType == WDO_MYSQL_TYPE_LONG .OR. nMysqlType == WDO_MYSQL_TYPE_INT24
      RETU WDO_BindPeekInt32( oStmt:pDataOut, nOff )
   CASE nMysqlType == WDO_MYSQL_TYPE_LONGLONG
      RETU WDO_BindPeekInt64( oStmt:pDataOut, nOff )
   CASE nMysqlType == WDO_MYSQL_TYPE_FLOAT
      //  Read as 4-byte float -- helper returns double already.
      RETU WDO_BindPeekFloat( oStmt:pDataOut, nOff )
   CASE nMysqlType == WDO_MYSQL_TYPE_DOUBLE
      RETU WDO_BindPeekDouble( oStmt:pDataOut, nOff )
   ENDCASE

   //  Default: string of length nLen (clamped to buffer size).
   cStr := WDO_BindPeekStr( oStmt:pDataOut, nOff, Min( nLen, oStmt:aBufSizes[i] ) )

RETU cStr

//	-------------------------------------------------------  //
//  _I16 -- sign-extend low 16 bits of an unsigned int.
STATIC FUNCTION _I16( n )
   LOCAL nLow := hb_bitAnd( n, 0xFFFF )
   IF nLow >= 0x8000 ; nLow -= 0x10000 ; ENDIF
RETU nLow

//	-------------------------------------------------------  //

STATIC FUNCTION DToC2( d )
   //  YYYY-MM-DD regardless of user's SET DATE
   RETU StrZero( Year( d ), 4 ) + "-" + StrZero( Month( d ), 2 ) + "-" +;
        StrZero( Day( d ), 2 )

//	-------------------------------------------------------  //

STATIC FUNCTION _WdoInt64Le( n )

   LOCAL cLo, cHi
   LOCAL nLo, nHi

   //  Split 64-bit signed into two 32-bit halves. Harbour Int() handles
   //  the full 64-bit range on 64-bit builds; we mask via bit ops.
   IF n < 0
      //  Two's complement: negate and subtract from 2^64.
      n := hb_bitOr( 0, n )    //  no-op cast; keep semantic
   ENDIF

   nLo := hb_bitAnd( n, 0xFFFFFFFF )
   nHi := Int( n / 4294967296 )
   IF nHi < 0 ; nHi += 4294967296 ; ENDIF
   nHi := hb_bitAnd( nHi, 0xFFFFFFFF )

   cLo := L2Bin( nLo )
   cHi := L2Bin( nHi )

RETU cLo + cHi

//	-------------------------------------------------------  //

STATIC FUNCTION _WdoDoubleLe( d )
   //  IEEE 754 little-endian representation of a double.
RETU WDO_DoubleToLe( d )

//	-------------------------------------------------------  //
//  Smoke test — first PrepareBin runs SELECT ? binding LONG 42
//  and verifies libmysql agrees. On failure logs a loud error
//  with client version + platform info. Non-fatal: caller sees
//  the actual error from Execute().
//	-------------------------------------------------------  //
STATIC PROCEDURE _WdoBindSmokeTest( oConn )

   LOCAL pStmt, pBind, pValues
   LOCAL nOff := 0
   LOCAL nRc

   slSmokeTested := .T.   //  guard first — run once even on failure

   pStmt := oConn:mysql_stmt_init()
   IF pStmt == NIL .OR. pStmt == 0
      lw( "[WDO_StmtBin] smoke test: mysql_stmt_init failed" )
      RETU
   ENDIF

   IF oConn:mysql_stmt_prepare( pStmt, "SELECT ?" ) != 0
      lw( "[WDO_StmtBin] smoke test: prepare failed -- " +;
           oConn:mysql_stmt_error( pStmt ) )
      oConn:mysql_stmt_close( pStmt )
      RETU
   ENDIF

   pBind   := WDO_BindAlloc( snBindSize )
   pValues := WDO_BindAlloc( 16 )

   //  One LONG param = 42
   WDO_BindPokeStrPtr( pBind, nOff + snOffBuffer, L2Bin( 42 ) )
   WDO_BindPokeInt64( pBind, nOff + snOffBufferLength, 4 )
   WDO_BindPokeInt32( pBind, nOff + snOffBufferType, WDO_MYSQL_TYPE_LONG )
   WDO_BindPokeInt64( pValues, 0, 4 )
   WDO_BindPokePtrOff( pBind, nOff + snOffLength, pValues, 0 )

   IF oConn:mysql_stmt_bind_param( pStmt, pBind )
      lw( "[WDO_StmtBin] smoke test: bind_param FAILED -- ABI mismatch? " +;
           "client=" + oConn:mysql_get_client_info() + ", " +;
           "err=" + oConn:mysql_stmt_error( pStmt ) )
   ELSE
      nRc := oConn:mysql_stmt_execute( pStmt )
      IF nRc != 0
         lw( "[WDO_StmtBin] smoke test: execute FAILED -- " +;
              oConn:mysql_stmt_error( pStmt ) )
      ELSE
         l( "[WDO_StmtBin] smoke test OK (client=" +;
             oConn:mysql_get_client_info() + ", sizeof=" +;
             hb_NToS( snBindSize ) + ")" )
      ENDIF
   ENDIF

   WDO_BindFree( pBind )
   WDO_BindFree( pValues )
   oConn:mysql_stmt_close( pStmt )

RETURN

//	-------------------------------------------------------  //
//  Smoke test for fetch output layout (v2.3.04) -- SELECT 42 LONG,
//  bind_result + store_result + fetch, check that peek returns 42
//  and error_value flag is clean. Non-fatal: logs loud on mismatch.
//	-------------------------------------------------------  //
STATIC PROCEDURE _WdoFetchSmokeTest( oConn )

   LOCAL pStmt, pBind, pMeta, pData
   LOCAL nRc, nGot, nErrFlag

   slFetchSmokeTested := .T.

   pStmt := oConn:mysql_stmt_init()
   IF pStmt == NIL .OR. pStmt == 0 ; RETU ; ENDIF

   IF oConn:mysql_stmt_prepare( pStmt, "SELECT CAST(42 AS SIGNED) AS x" ) != 0
      lw( "[WDO_StmtBin] fetch smoke: prepare failed -- " +;
           oConn:mysql_stmt_error( pStmt ) )
      oConn:mysql_stmt_close( pStmt )
      RETU
   ENDIF

   IF oConn:mysql_stmt_execute( pStmt ) != 0
      lw( "[WDO_StmtBin] fetch smoke: execute failed -- " +;
           oConn:mysql_stmt_error( pStmt ) )
      oConn:mysql_stmt_close( pStmt )
      RETU
   ENDIF

   pBind := WDO_BindAlloc( snBindSize )
   pMeta := WDO_BindAlloc( 24 )
   pData := WDO_BindAlloc( 8 )

   //  One LONGLONG output slot
   WDO_BindPokePtrOff( pBind, snOffBuffer,       pData, 0 )
   WDO_BindPokeInt64(  pBind, snOffBufferLength, 8 )
   WDO_BindPokeInt32(  pBind, snOffBufferType,   WDO_MYSQL_TYPE_LONGLONG )
   WDO_BindPokePtrOff( pBind, snOffLength,       pMeta, 0 )
   WDO_BindPokePtrOff( pBind, snOffIsNull,       pMeta, 8 )
   WDO_BindPokePtrOff( pBind, snOffError,        pMeta, 16 )

   IF oConn:mysql_stmt_bind_result( pStmt, pBind )
      lw( "[WDO_StmtBin] fetch smoke: bind_result FAILED -- ABI mismatch? " +;
           "client=" + oConn:mysql_get_client_info() + ", " +;
           "err=" + oConn:mysql_stmt_error( pStmt ) )
   ELSEIF oConn:mysql_stmt_store_result( pStmt ) != 0
      lw( "[WDO_StmtBin] fetch smoke: store_result FAILED -- " +;
           oConn:mysql_stmt_error( pStmt ) )
   ELSE
      nRc := oConn:mysql_stmt_fetch( pStmt )
      IF nRc != 0 .AND. nRc != 101
         lw( "[WDO_StmtBin] fetch smoke: fetch FAILED rc=" + hb_NToS( nRc ) +;
              " err=" + oConn:mysql_stmt_error( pStmt ) )
      ELSE
         nGot     := WDO_BindPeekInt64( pData, 0 )
         nErrFlag := WDO_BindPeekByte( pMeta, 16 )
         IF nGot != 42 .OR. nErrFlag != 0
            lw( "[WDO_StmtBin] fetch smoke MISMATCH -- got=" + hb_NToS( nGot ) +;
                 " err_flag=" + hb_NToS( nErrFlag ) +;
                 " (expected 42 / 0). client=" + oConn:mysql_get_client_info() )
         ELSE
            l( "[WDO_StmtBin] fetch smoke OK (client=" +;
                oConn:mysql_get_client_info() + ", sizeof=" +;
                hb_NToS( snBindSize ) + ")" )
         ENDIF
      ENDIF
      oConn:mysql_stmt_free_result( pStmt )
   ENDIF

   WDO_BindFree( pBind )
   WDO_BindFree( pMeta )
   WDO_BindFree( pData )
   oConn:mysql_stmt_close( pStmt )

RETURN

//	=======================================================  //
//  Embedded C helpers — MYSQL_BIND poke/peek. Live in HIX, NOT
//  in Harbour core. All functions take a Harbour "P" pointer
//  (returned by WDO_BindAlloc) + byte offset.
//	=======================================================  //

#pragma BEGINDUMP

#include "hbapi.h"
#include "hbapiitm.h"
#include <string.h>
#include <stdlib.h>

HB_FUNC( WDO_BINDALLOC )
{
   HB_ISIZ nSize = hb_parns( 1 );
   void * p = malloc( ( size_t ) nSize );
   if( p ) memset( p, 0, ( size_t ) nSize );
   hb_retptr( p );
}

HB_FUNC( WDO_BINDFREE )
{
   void * p = hb_parptr( 1 );
   if( p ) free( p );
}

HB_FUNC( WDO_BINDPOKEBYTE )
{
   char * p = ( char * ) hb_parptr( 1 );
   HB_ISIZ nOff = hb_parns( 2 );
   int v = hb_parni( 3 );
   if( p ) p[ nOff ] = ( char ) ( v & 0xFF );
}

HB_FUNC( WDO_BINDPOKEINT32 )
{
   char * p = ( char * ) hb_parptr( 1 );
   HB_ISIZ nOff = hb_parns( 2 );
   HB_I32 v = ( HB_I32 ) hb_parnl( 3 );
   if( p ) memcpy( p + nOff, &v, 4 );
}

HB_FUNC( WDO_BINDPOKEINT64 )
{
   char * p = ( char * ) hb_parptr( 1 );
   HB_ISIZ nOff = hb_parns( 2 );
   HB_MAXINT v = hb_parnint( 3 );
   HB_I64 v64 = ( HB_I64 ) v;
   if( p ) memcpy( p + nOff, &v64, 8 );
}

HB_FUNC( WDO_BINDPOKEDOUBLE )
{
   char * p = ( char * ) hb_parptr( 1 );
   HB_ISIZ nOff = hb_parns( 2 );
   double d = hb_parnd( 3 );
   if( p ) memcpy( p + nOff, &d, 8 );
}

/*
 * Store the address of Harbour string s inside p at offset nOff.
 * Caller must keep the Harbour string alive for as long as p is
 * read — WDO_MySqlStmtBin does this via ::aBuffers.
 */
HB_FUNC( WDO_BINDPOKESTRPTR )
{
   char * p = ( char * ) hb_parptr( 1 );
   HB_ISIZ nOff = hb_parns( 2 );
   const char * s = hb_parc( 3 );
   if( p ) memcpy( p + nOff, &s, sizeof( void * ) );
}

/*
 * Store the address of ( pOther + nOffOther ) inside p at offset nOff.
 * Used to point MYSQL_BIND.length / .is_null at slots inside the
 * pValues buffer.
 */
HB_FUNC( WDO_BINDPOKEPTROFF )
{
   char * p = ( char * ) hb_parptr( 1 );
   HB_ISIZ nOff = hb_parns( 2 );
   char * pOther = ( char * ) hb_parptr( 3 );
   HB_ISIZ nOffOther = hb_parns( 4 );
   char * target;
   if( p && pOther )
   {
      target = pOther + nOffOther;
      memcpy( p + nOff, &target, sizeof( void * ) );
   }
}

/*
 * IEEE 754 double → 8-byte little-endian Harbour string. Independent
 * of host endianness (poke via memcpy respects native layout; x86_64
 * is LE on all our targets).
 */
HB_FUNC( WDO_DOUBLETOLE )
{
   double d = hb_parnd( 1 );
   char buf[ 8 ];
   memcpy( buf, &d, 8 );
   hb_retclen( buf, 8 );
}

/* -------- Peek helpers (v2.3.04) -- fetch output decoding --------
 * Each takes ( p, nOff ) and reads a native type at offset nOff.
 * No bounds checking -- caller is Harbour code that only pokes/peeks
 * within the slabs it has itself allocated via WDO_BindAlloc.
 */

HB_FUNC( WDO_BINDPEEKBYTE )
{
   unsigned char * p = ( unsigned char * ) hb_parptr( 1 );
   HB_ISIZ nOff = hb_parns( 2 );
   if( p ) hb_retni( ( int ) p[ nOff ] );
   else    hb_retni( 0 );
}

HB_FUNC( WDO_BINDPEEKINT32 )
{
   char * p = ( char * ) hb_parptr( 1 );
   HB_ISIZ nOff = hb_parns( 2 );
   HB_I32 v = 0;
   if( p ) memcpy( &v, p + nOff, 4 );
   hb_retnl( ( long ) v );
}

HB_FUNC( WDO_BINDPEEKINT64 )
{
   char * p = ( char * ) hb_parptr( 1 );
   HB_ISIZ nOff = hb_parns( 2 );
   HB_I64 v = 0;
   if( p ) memcpy( &v, p + nOff, 8 );
   hb_retnint( ( HB_MAXINT ) v );
}

HB_FUNC( WDO_BINDPEEKDOUBLE )
{
   char * p = ( char * ) hb_parptr( 1 );
   HB_ISIZ nOff = hb_parns( 2 );
   double d = 0.0;
   if( p ) memcpy( &d, p + nOff, 8 );
   hb_retnd( d );
}

HB_FUNC( WDO_BINDPEEKFLOAT )
{
   char * p = ( char * ) hb_parptr( 1 );
   HB_ISIZ nOff = hb_parns( 2 );
   float f = 0.0f;
   if( p ) memcpy( &f, p + nOff, 4 );
   hb_retnd( ( double ) f );
}

HB_FUNC( WDO_BINDPEEKSTR )
{
   char * p = ( char * ) hb_parptr( 1 );
   HB_ISIZ nOff = hb_parns( 2 );
   HB_ISIZ nLen = hb_parns( 3 );
   if( p && nLen > 0 ) hb_retclen( p + nOff, nLen );
   else                hb_retc( "" );
}

#pragma ENDDUMP
