/*-----------------------------------------------------------
  File ......: wdo_mysql_stmt.prg
  Author.....: Charly 9000
  Created....: 2026-09-27
  Modified...: 2026-09-27
  Version....: 2.0.0
  Description: MySQL statement class. Short-lived object created by
               WDO_MySql:Query(). Owns hRes + field metadata for
               a single query, so the parent connection remains
               reusable by other workers without state contamination.
  Usage      : oStmt := oConn:Query( "SELECT ..." )
               aRows := oStmt:FetchAll( .T. )
               oStmt:Free()
  Notes      : Extracted from monolithic wdo_mysql.prg
 -----------------------------------------------------W------*/

#include 'hbclass.ch'
#include "wdo_metrics.ch"

CLASS WDO_MySqlStmt

   DATA oConn
   DATA cSql              INIT ''
   DATA hRes              INIT 0
   DATA aFields           INIT {}
   DATA nFields           INIT 0
   DATA nAffectedRows     INIT 0
   DATA cError            INIT ''
   DATA lError            INIT .F.
   DATA lWeb              INIT .T.
   DATA lFreed            INIT .F.

   //  Prepared statement (Alt B — server-side PREPARE emulation)
   DATA lPrepared         INIT .F.
   DATA cStmtName         INIT ''
   DATA cSqlOriginal      INIT ''
   DATA cSqlServer        INIT ''
   DATA nParamCount       INIT 0
   DATA aParams           INIT {}      //  { [i] => { xValue, cType } }
   DATA hParamMap         INIT {=>}    //  ":name" => index

   METHOD New( oConn, cSql, hRes ) CONSTRUCTOR
   METHOD LoadStruct()
   METHOD Count()
   METHOD FCount()                  INLINE ::nFields
   METHOD DbStruct()                INLINE ::aFields

   METHOD Fetch( aNoEscape )
   METHOD Fetch_Assoc( aNoEscape )
   METHOD FetchAll( lAssoc, aNoEscape )

   METHOD BindParam( xIdxOrName, xValue, cType )
   METHOD BindLong( nIdx, cData )
   METHOD BindParams( aValues )
   METHOD Execute()

   METHOD Row_Count()               INLINE ::nAffectedRows
   METHOD Free()
   METHOD Destroy()                 INLINE ::Free()
   METHOD End()                     INLINE ::Free()

ENDCLASS

//	-------------------------------------------------------  //

METHOD New( oConn, cSql, hRes ) CLASS WDO_MySqlStmt

   ::oConn         := oConn
   ::cSql          := cSql
   ::hRes          := hRes
   ::lWeb          := oConn:lWeb
   ::nAffectedRows := oConn:mysql_affected_rows()

   IF hRes != 0
      ::LoadStruct()
   ENDIF

RETU SELF

//	-------------------------------------------------------  //

METHOD Count() CLASS WDO_MySqlStmt

   IF ::hRes == 0
      RETU 0
   ENDIF

RETU ::oConn:mysql_num_rows( ::hRes )

//	-------------------------------------------------------  //

METHOD LoadStruct() CLASS WDO_MySqlStmt

   LOCAL n, hField, cType, nMysqlLen, nMysqlDec
   LOCAL nTypePos := ::oConn:nTypePos
   // MYSQL_FIELD.length at byte 56 → PtrToUI index 14 on Win64 and Linux64
   LOCAL nLenPos  := 14
   // MYSQL_FIELD.decimals: Win64 byte 96 → index 24; Linux64 byte 104 → index 26
   LOCAL nDecPos  := iif( "Windows" $ OS(), 24, 26 )

   ::nFields := ::oConn:mysql_num_fields( ::hRes )
   ::aFields := Array( ::nFields )

   FOR n := 1 TO ::nFields

      hField := ::oConn:mysql_fetch_field( ::hRes )

      IF hField != 0

         cType      := NIL
         nMysqlLen  := PtrToUI( hField, nLenPos )
         nMysqlDec  := PtrToUI( hField, nDecPos )

         DO CASE
         CASE AScan( { 253, 254, 12 }, PtrToUI( hField, nTypePos ) ) != 0
            cType := "C"
         CASE AScan( { 1, 3, 4, 5, 8, 9, 246 }, PtrToUI( hField, nTypePos ) ) != 0
            cType := "N"
         CASE AScan( { 10 }, PtrToUI( hField, nTypePos ) ) != 0
            cType := "D"
         CASE AScan( { 250, 252 }, PtrToUI( hField, nTypePos ) ) != 0
            cType := "M"
         ENDCASE

         ::aFields[n]    := Array( 4 )
         ::aFields[n][1] := PtrToStr( hField, 0 )
         ::aFields[n][2] := cType
         ::aFields[n][3] := iif( cType == "D", 8, nMysqlLen )
         ::aFields[n][4] := iif( cType == "D", 0, nMysqlDec )

      ENDIF

   NEXT

RETU NIL

//	-------------------------------------------------------  //

METHOD Fetch( aNoEscape ) CLASS WDO_MySqlStmt

   LOCAL hRow
   LOCAL aReg
   LOCAL m

   hb_default( @aNoEscape, {} )

   IF ::hRes == 0
      RETU NIL
   ENDIF

   IF ( hRow := ::oConn:mysql_fetch_row( ::hRes ) ) != 0

      aReg := Array( ::nFields )

      IF Len( aNoEscape ) == 0

         IF ::lWeb
            FOR m := 1 TO ::nFields
               aReg[m] := wdo_htmlencode( PtrToStr( hRow, m - 1 ) )
            NEXT
         ELSE
            FOR m := 1 TO ::nFields
               aReg[m] := PtrToStr( hRow, m - 1 )
            NEXT
         ENDIF

      ELSE

         IF ::lWeb
            FOR m := 1 TO ::nFields
               IF AScan( aNoEscape, ::aFields[m][1] ) > 0
                  aReg[m] := PtrToStr( hRow, m - 1 )
               ELSE
                  aReg[m] := wdo_htmlencode( PtrToStr( hRow, m - 1 ) )
               ENDIF
            NEXT
         ELSE
            FOR m := 1 TO ::nFields
               aReg[m] := PtrToStr( hRow, m - 1 )
            NEXT
         ENDIF

      ENDIF

   ENDIF

RETU aReg

//	-------------------------------------------------------  //

METHOD Fetch_Assoc( aNoEscape ) CLASS WDO_MySqlStmt

   LOCAL hRow
   LOCAL hReg := {=>}
   LOCAL m

   hb_default( @aNoEscape, {} )

   IF ::hRes == 0
      RETU hReg
   ENDIF

   IF ( hRow := ::oConn:mysql_fetch_row( ::hRes ) ) != 0

      IF Len( aNoEscape ) == 0

         IF ::lWeb
            FOR m := 1 TO ::nFields
               hReg[ ::aFields[m][1] ] := wdo_htmlencode( PtrToStr( hRow, m - 1 ) )
            NEXT
         ELSE
            FOR m := 1 TO ::nFields
               hReg[ ::aFields[m][1] ] := PtrToStr( hRow, m - 1 )
            NEXT
         ENDIF

      ELSE

         IF ::lWeb
            FOR m := 1 TO ::nFields
               IF AScan( aNoEscape, ::aFields[m][1] ) > 0
                  hReg[ ::aFields[m][1] ] := PtrToStr( hRow, m - 1 )
               ELSE
                  hReg[ ::aFields[m][1] ] := wdo_htmlencode( PtrToStr( hRow, m - 1 ) )
               ENDIF
            NEXT
         ELSE
            FOR m := 1 TO ::nFields
               IF AScan( aNoEscape, ::aFields[m][1] ) > 0
                  hReg[ ::aFields[m][1] ] := PtrToStr( hRow, m - 1 )
               ENDIF
            NEXT
         ENDIF

      ENDIF

   ENDIF

RETU hReg

//	-------------------------------------------------------  //

METHOD FetchAll( lAssoc, aNoEscape ) CLASS WDO_MySqlStmt

   LOCAL oRs
   LOCAL aData := {}

   __defaultNIL( @lAssoc,    .F. )
   __defaultNIL( @aNoEscape, {}  )

   IF lAssoc
      DO WHILE ( ! Empty( oRs := ::Fetch_Assoc( aNoEscape ) ) )
         AAdd( aData, oRs )
      ENDDO
   ELSE
      DO WHILE ( ! Empty( oRs := ::Fetch( aNoEscape ) ) )
         AAdd( aData, oRs )
      ENDDO
   ENDIF

RETU aData

//	-------------------------------------------------------  //

METHOD Free() CLASS WDO_MySqlStmt

   LOCAL cDealloc

   IF ::lFreed
      RETU NIL
   ENDIF

   IF ::hRes != 0
      ::oConn:mysql_free_result( ::hRes )
      ::hRes := 0
   ENDIF

   IF ::lPrepared .AND. ! Empty( ::cStmtName ) .AND. ;
      ::oConn:hConnection != NIL .AND. ::oConn:hConnection != 0

      cDealloc := "DEALLOCATE PREPARE " + ::cStmtName
      ::oConn:mysql_query( cDealloc )        //  best-effort
      ::cStmtName := ''
      ::lPrepared := .F.
   ENDIF

   ::lFreed := .T.

RETU NIL

//	-------------------------------------------------------  //

METHOD BindParam( xIdxOrName, xValue, cType ) CLASS WDO_MySqlStmt

   LOCAL nIdx
   LOCAL cKey

   IF ! ::lPrepared
      RETU SELF
   ENDIF

   DO CASE
   CASE ValType( xIdxOrName ) == "N"
      nIdx := xIdxOrName
   CASE ValType( xIdxOrName ) == "C"
      cKey := xIdxOrName
      IF Left( cKey, 1 ) != ":"
         cKey := ":" + cKey
      ENDIF
      IF hb_HHasKey( ::hParamMap, cKey )
         nIdx := ::hParamMap[ cKey ]
      ENDIF
   ENDCASE

   IF nIdx == NIL .OR. nIdx < 1 .OR. nIdx > ::nParamCount
      ::lError := .T.
      ::cError := "BindParam: index/name out of range"
      RETU SELF
   ENDIF

   IF cType == NIL
      cType := _WdoInferType( xValue )
   ENDIF

   ::aParams[ nIdx ] := { xValue, cType }

RETU SELF

//	-------------------------------------------------------  //
//  BindLong( nIdx, cData ) — parity with WDO_MySqlStmtBin API.
//  Alt B has no wire-level send_long_data; we just delegate to
//  BindParam with the string appended. Multiple calls concat.
//	-------------------------------------------------------  //
METHOD BindLong( nIdx, cData ) CLASS WDO_MySqlStmt

   LOCAL cPrev

   IF ! ::lPrepared .OR. nIdx < 1 .OR. nIdx > ::nParamCount
      RETU SELF
   ENDIF

   //  Concatenate against any previous chunk. aParams slot holds
   //  { xValue, cType } after BindParam.
   IF ::aParams[ nIdx ] != NIL .AND. HB_ISARRAY( ::aParams[ nIdx ] ) .AND.;
      HB_ISSTRING( ::aParams[ nIdx, 1 ] )
      cPrev := ::aParams[ nIdx, 1 ]
   ELSE
      cPrev := ""
   ENDIF

   ::BindParam( nIdx, cPrev + cData )

RETU SELF

//	-------------------------------------------------------  //

METHOD BindParams( aValues ) CLASS WDO_MySqlStmt

   LOCAL n

   IF ! ::lPrepared .OR. aValues == NIL
      RETU SELF
   ENDIF

   FOR n := 1 TO Min( Len( aValues ), ::nParamCount )
      ::BindParam( n, aValues[ n ] )
   NEXT

RETU SELF

//	-------------------------------------------------------  //

METHOD Execute() CLASS WDO_MySqlStmt

   LOCAL n
   LOCAL cSetSql
   LOCAL cExecSql
   LOCAL cUsing := ''
   LOCAL xValue, cType, cLiteral
   LOCAL nT0

   IF ! ::lPrepared
      RETU .F.
   ENDIF

   //  Re-execute: release previous result set before re-binding.
   IF ::hRes != 0
      ::oConn:mysql_free_result( ::hRes )
      ::hRes := 0
   ENDIF

   nT0 := hb_MilliSeconds()

   FOR n := 1 TO ::nParamCount

      IF ::aParams[ n ] == NIL
         xValue := NIL
         cType  := "s"
      ELSE
         xValue := ::aParams[ n ][ 1 ]
         cType  := ::aParams[ n ][ 2 ]
      ENDIF

      cLiteral := _WdoLiteral( xValue, cType )
      cSetSql  := "SET @p" + hb_NToS( n ) + " := " + cLiteral

      IF ::oConn:mysql_query( cSetSql ) != 0
         ::oConn:SetError( ::oConn:mysql_error(), "Execute/SET" )
         WDO_Metric( WDOM_QUERIES_ERRORS )
         WDO_MetricQuery( ::oConn:cPoolKey, ;
                          "EXECUTE " + ::cSqlOriginal, ;
                          hb_MilliSeconds() - nT0, NIL )
         RETU .F.
      ENDIF

      IF Len( cUsing ) > 0
         cUsing += ", "
      ENDIF
      cUsing += "@p" + hb_NToS( n )
   NEXT

   cExecSql := "EXECUTE " + ::cStmtName
   IF Len( cUsing ) > 0
      cExecSql += " USING " + cUsing
   ENDIF

   IF ::oConn:mysql_query( cExecSql ) != 0
      ::oConn:SetError( ::oConn:mysql_error(), "Execute" )
      WDO_Metric( WDOM_QUERIES_ERRORS )
      WDO_MetricQuery( ::oConn:cPoolKey, ;
                       "EXECUTE " + ::cSqlOriginal, ;
                       hb_MilliSeconds() - nT0, NIL )
      RETU .F.
   ENDIF

   ::hRes           := ::oConn:mysql_store_result()
   ::nAffectedRows  := ::oConn:mysql_affected_rows()

   IF ::hRes != 0
      ::LoadStruct()
   ENDIF

   WDO_MetricQuery( ::oConn:cPoolKey, ;
                    "EXECUTE " + ::cSqlOriginal, ;
                    hb_MilliSeconds() - nT0, NIL )

RETU .T.

//	=======================================================  //
//  Helpers globales
//	=======================================================  //

FUNCTION wdo_htmlencode( cString )

   LOCAL cChar
   LOCAL cRet := ""

   FOR EACH cChar IN cString
      DO CASE
      CASE cChar == "<"  ; cChar := "&lt;"
      CASE cChar == ">"  ; cChar := "&gt;"
      CASE cChar == "&"  ; cChar := "&amp;"
      CASE cChar == '"'  ; cChar := "&quot;"
      CASE cChar == "'"  ; cChar := "&apos;"
      ENDCASE
      cRet += cChar
   NEXT

RETU cRet

//	=======================================================  //
//  Prepared statement helpers (Alt B)
//	=======================================================  //

STATIC FUNCTION _WdoInferType( xValue )

   DO CASE
   CASE xValue == NIL          ; RETU "s"
   CASE ValType( xValue ) == "N" ; RETU iif( xValue == Int( xValue ), "i", "n" )
   CASE ValType( xValue ) == "D" ; RETU "d"
   CASE ValType( xValue ) == "T" ; RETU "t"
   CASE ValType( xValue ) == "L" ; RETU "i"
   ENDCASE

RETU "s"

//	-------------------------------------------------------  //

STATIC FUNCTION _WdoLiteral( xValue, cType )

   IF xValue == NIL
      RETU "NULL"
   ENDIF

   DO CASE
   CASE cType == "i"
      IF ValType( xValue ) == "L"
         RETU iif( xValue, "1", "0" )
      ENDIF
      RETU hb_NToS( Int( xValue ) )

   CASE cType == "n"
      RETU StrTran( hb_NToS( xValue ), ",", "." )

   CASE cType == "d"
      IF ValType( xValue ) == "D"
         RETU "'" + StrZero( Year( xValue ), 4 ) + "-" + ;
                     StrZero( Month( xValue ), 2 ) + "-" + ;
                     StrZero( Day( xValue ),   2 ) + "'"
      ENDIF
      RETU "'" + wdo_addslashes( hb_CStr( xValue ) ) + "'"

   CASE cType == "t"
      IF ValType( xValue ) == "T"
         RETU "'" + hb_TSToStr( xValue ) + "'"
      ENDIF
      RETU "'" + wdo_addslashes( hb_CStr( xValue ) ) + "'"

   CASE cType == "b"
      RETU "x'" + StrToHex( hb_CStr( xValue ) ) + "'"

   ENDCASE

   //  default: string
RETU "'" + wdo_addslashes( hb_CStr( xValue ) ) + "'"

//	-------------------------------------------------------  //

STATIC FUNCTION StrToHex( cData )

   LOCAL cRet := ""
   LOCAL n

   FOR n := 1 TO Len( cData )
      cRet += hb_NumToHex( Asc( SubStr( cData, n, 1 ) ), 2 )
   NEXT

RETU cRet
