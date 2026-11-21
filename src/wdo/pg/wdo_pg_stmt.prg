/*-----------------------------------------------------------
  File ......: wdo_pg_stmt.prg
  Author.....: Charly 9000
  Created....: 2026-10-18
  Modified...: 2026-10-18
  Version....: 1.0.0
  Description: PostgreSQL statement class. Short-lived object
               created by WDO_PG:Query(). Owns PGresult + field
               metadata for a single query, so the parent
               connection remains reusable by other workers
               without state contamination.
  Usage      : oStmt := oConn:Query( "SELECT ..." )
               aRows := oStmt:FetchAll( .T. )
               oStmt:Free()
  Notes      : PG is random-access (PQgetvalue(hRes, nRow, nCol)),
               so we keep our own ::nCurRow cursor instead of
               the sequential mysql_fetch_row style.
 -----------------------------------------------------------*/

#include "hbclass.ch"
#include "wdo_pg.ch"

CLASS WDO_PgStmt

   DATA oConn
   DATA cSql              INIT ''
   DATA hRes              INIT 0
   DATA aFields           INIT {}
   DATA nFields           INIT 0
   DATA nRows             INIT 0
   DATA nCurRow           INIT 0
   DATA nAffectedRows     INIT 0
   DATA cError            INIT ''
   DATA lError            INIT .F.
   DATA lWeb              INIT .T.
   DATA lFreed            INIT .F.

   //  Prepared statement (Alt A — libpq native, text params)
   DATA lPrepared         INIT .F.
   DATA cStmtName         INIT ''
   DATA cSqlOriginal      INIT ''
   DATA cSqlServer        INIT ''
   DATA nParamCount       INIT 0
   DATA aParams           INIT {}      //  { [i] => { xValue, cType } }
   DATA hParamMap         INIT {=>}    //  ":name" => index

   METHOD New( oConn, cSql, hRes ) CONSTRUCTOR
   METHOD LoadStruct()
   METHOD Count()                   INLINE ::nRows
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

METHOD New( oConn, cSql, hRes ) CLASS WDO_PgStmt

   LOCAL cTuples

   ::oConn   := oConn
   ::cSql    := cSql
   ::hRes    := hRes
   ::lWeb    := oConn:lWeb

   IF hRes != 0

      ::nRows := ::oConn:PQntuples( hRes )

      cTuples := ::oConn:PQcmdTuples( hRes )
      ::nAffectedRows := iif( Empty( cTuples ), ::nRows, Val( cTuples ) )

      ::LoadStruct()
   ENDIF

RETU SELF

//	-------------------------------------------------------  //

METHOD LoadStruct() CLASS WDO_PgStmt

   LOCAL n, nOid, cType, nSize, nMod, nDec

   ::nFields := ::oConn:PQnfields( ::hRes )
   ::aFields := Array( ::nFields )

   FOR n := 1 TO ::nFields

      nOid  := ::oConn:PQftype( ::hRes, n - 1 )
      nSize := ::oConn:PQfsize( ::hRes, n - 1 )
      nMod  := ::oConn:PQfmod(  ::hRes, n - 1 )
      cType := _WdoPgTypeMap( nOid )
      nDec  := 0

      //  Numeric(precision, scale) → PQfmod packs both:
      //  typmod = ((precision << 16) | scale) + VARHDRSZ (=4)
      IF nOid == 1700 .AND. nMod > 4
         nDec := hb_bitAnd( nMod - 4, 0xFFFF )
         nSize := hb_bitShift( nMod - 4, -16 )
         nSize := hb_bitAnd( nSize, 0xFFFF )
      ELSEIF cType == "C" .AND. nMod > 4
         //  varchar(N) → typmod = N + 4
         nSize := nMod - 4
      ELSEIF nSize < 0
         //  Variable-length types (text, bytea): report 0
         nSize := 0
      ENDIF

      ::aFields[n]    := Array( 4 )
      ::aFields[n][1] := ::oConn:PQfname( ::hRes, n - 1 )
      ::aFields[n][2] := cType
      ::aFields[n][3] := iif( cType == "D", 8, nSize )
      ::aFields[n][4] := iif( cType == "D", 0, nDec )

   NEXT

RETU NIL

//	-------------------------------------------------------  //

METHOD Fetch( aNoEscape ) CLASS WDO_PgStmt

   LOCAL aReg
   LOCAL m
   LOCAL cVal
   LOCAL nRow

   hb_default( @aNoEscape, {} )

   IF ::hRes == 0 .OR. ::nCurRow >= ::nRows
      RETU NIL
   ENDIF

   nRow := ::nCurRow
   ::nCurRow++

   aReg := Array( ::nFields )

   IF Len( aNoEscape ) == 0

      IF ::lWeb
         FOR m := 1 TO ::nFields
            cVal := ::oConn:PQgetvalue( ::hRes, nRow, m - 1 )
            aReg[m] := wdo_htmlencode( cVal )
         NEXT
      ELSE
         FOR m := 1 TO ::nFields
            aReg[m] := ::oConn:PQgetvalue( ::hRes, nRow, m - 1 )
         NEXT
      ENDIF

   ELSE

      IF ::lWeb
         FOR m := 1 TO ::nFields
            cVal := ::oConn:PQgetvalue( ::hRes, nRow, m - 1 )
            IF AScan( aNoEscape, ::aFields[m][1] ) > 0
               aReg[m] := cVal
            ELSE
               aReg[m] := wdo_htmlencode( cVal )
            ENDIF
         NEXT
      ELSE
         FOR m := 1 TO ::nFields
            aReg[m] := ::oConn:PQgetvalue( ::hRes, nRow, m - 1 )
         NEXT
      ENDIF

   ENDIF

RETU aReg

//	-------------------------------------------------------  //

METHOD Fetch_Assoc( aNoEscape ) CLASS WDO_PgStmt

   LOCAL hReg := {=>}
   LOCAL m
   LOCAL cVal
   LOCAL nRow

   hb_default( @aNoEscape, {} )

   IF ::hRes == 0 .OR. ::nCurRow >= ::nRows
      RETU hReg
   ENDIF

   nRow := ::nCurRow
   ::nCurRow++

   IF Len( aNoEscape ) == 0

      IF ::lWeb
         FOR m := 1 TO ::nFields
            cVal := ::oConn:PQgetvalue( ::hRes, nRow, m - 1 )
            hReg[ ::aFields[m][1] ] := wdo_htmlencode( cVal )
         NEXT
      ELSE
         FOR m := 1 TO ::nFields
            hReg[ ::aFields[m][1] ] := ::oConn:PQgetvalue( ::hRes, nRow, m - 1 )
         NEXT
      ENDIF

   ELSE

      IF ::lWeb
         FOR m := 1 TO ::nFields
            cVal := ::oConn:PQgetvalue( ::hRes, nRow, m - 1 )
            IF AScan( aNoEscape, ::aFields[m][1] ) > 0
               hReg[ ::aFields[m][1] ] := cVal
            ELSE
               hReg[ ::aFields[m][1] ] := wdo_htmlencode( cVal )
            ENDIF
         NEXT
      ELSE
         FOR m := 1 TO ::nFields
            IF AScan( aNoEscape, ::aFields[m][1] ) > 0
               hReg[ ::aFields[m][1] ] := ::oConn:PQgetvalue( ::hRes, nRow, m - 1 )
            ENDIF
         NEXT
      ENDIF

   ENDIF

RETU hReg

//	-------------------------------------------------------  //

METHOD FetchAll( lAssoc, aNoEscape ) CLASS WDO_PgStmt

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

METHOD Free() CLASS WDO_PgStmt

   LOCAL hRes

   IF ::lFreed
      RETU NIL
   ENDIF

   IF ::hRes != 0 .AND. ::oConn != NIL
      ::oConn:PQclear( ::hRes )
      ::hRes := 0
   ENDIF

   //  Prepared stmt → DEALLOCATE server-side (releases plan + name).
   //  Alt A: no PQ-level deallocate wrapper, use PQexec("DEALLOCATE …").
   IF ::lPrepared .AND. ! Empty( ::cStmtName ) .AND. ::oConn != NIL .AND.;
      ::oConn:hConnection != NIL .AND. ::oConn:hConnection != 0
      hRes := ::oConn:PQexec( "DEALLOCATE " + ::cStmtName )
      IF hRes != 0
         ::oConn:PQclear( hRes )
      ENDIF
      ::lPrepared := .F.
   ENDIF

   ::lFreed := .T.

RETU NIL

//	=======================================================  //
//  Prepared statement API — BindParam / BindParams / BindLong
//	=======================================================  //

METHOD BindParam( xIdxOrName, xValue, cType ) CLASS WDO_PgStmt

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
      cType := _WdoPgInferType( xValue )
   ENDIF

   ::aParams[ nIdx ] := { xValue, cType }

RETU SELF

//	-------------------------------------------------------  //
//  BindLong( nIdx, cData ) — paridad con WDO_MySqlStmt.
//  PG texto no tiene wire send_long_data; concat en cliente.
//	-------------------------------------------------------  //
METHOD BindLong( nIdx, cData ) CLASS WDO_PgStmt

   LOCAL cPrev

   IF ! ::lPrepared .OR. nIdx < 1 .OR. nIdx > ::nParamCount
      RETU SELF
   ENDIF

   IF ::aParams[ nIdx ] != NIL .AND. HB_ISARRAY( ::aParams[ nIdx ] ) .AND.;
      HB_ISSTRING( ::aParams[ nIdx, 1 ] )
      cPrev := ::aParams[ nIdx, 1 ]
   ELSE
      cPrev := ""
   ENDIF

   ::BindParam( nIdx, cPrev + cData )

RETU SELF

//	-------------------------------------------------------  //

METHOD BindParams( aValues ) CLASS WDO_PgStmt

   LOCAL n

   IF ! ::lPrepared .OR. aValues == NIL
      RETU SELF
   ENDIF

   FOR n := 1 TO Min( Len( aValues ), ::nParamCount )
      ::BindParam( n, aValues[ n ] )
   NEXT

RETU SELF

//	-------------------------------------------------------  //
//  Execute — construye const char * paramValues[] desde aParams,
//  invoca PQexecPrepared, puebla hRes / nRows / aFields / cError.
//
//  Marshalling: WDO_BindAlloc(8 * nParams) devuelve buffer de
//  punteros zeroed. Para cada slot:
//     aParams[i] == NIL          → slot queda en 0 → SQL NULL
//     aParams[i][1] == NIL       → idem
//     otro                       → serializar a texto según cType,
//                                  conservar HB_ITEM vivo en
//                                  aBuffers (array local) y
//                                  WDO_BindPokeStrPtr del cstring.
//
//  Devuelve .T. si PGRES_COMMAND_OK / PGRES_TUPLES_OK, .F. si no.
//	-------------------------------------------------------  //
METHOD Execute() CLASS WDO_PgStmt

   LOCAL n
   LOCAL xVal, cType, cText
   LOCAL aBuffers := {}             //  HB_ITEMs vivos durante la call
   LOCAL pValues
   LOCAL hRes
   LOCAL nStatus
   LOCAL cTuples

   ::lError := .F.
   ::cError := ""

   IF ! ::lPrepared
      ::lError := .T.
      ::cError := "Execute: stmt not prepared"
      RETU .F.
   ENDIF

   IF ::oConn == NIL .OR. ::oConn:hConnection == NIL .OR. ;
      ::oConn:hConnection == 0
      ::lError := .T.
      ::cError := "Execute: connection lost"
      RETU .F.
   ENDIF

   //  Reset de resultado anterior (Execute reinvocable).
   IF ::hRes != 0
      ::oConn:PQclear( ::hRes )
      ::hRes          := 0
      ::nRows         := 0
      ::nCurRow       := 0
      ::nAffectedRows := 0
      ::aFields       := {}
      ::nFields       := 0
   ENDIF

   //  Construir paramValues[] nativo.
   IF ::nParamCount > 0
      pValues := WDO_BindAlloc( 8 * ::nParamCount )
      FOR n := 1 TO ::nParamCount
         IF ::aParams[ n ] == NIL
            LOOP                     //  slot ya en 0 → NULL
         ENDIF
         xVal  := ::aParams[ n, 1 ]
         cType := ::aParams[ n, 2 ]
         IF xVal == NIL
            LOOP                     //  idem NULL
         ENDIF
         cText := _WdoPgSerialize( xVal, cType )
         AAdd( aBuffers, cText )     //  mantener HB_ITEM vivo
         WDO_BindPokeStrPtr( pValues, ( n - 1 ) * 8, cText )
      NEXT
   ELSE
      pValues := WDO_PtrNull()
   ENDIF

   //  nResultFormat=0 → text (v1). Binary lo deja para v2.
   hRes := ::oConn:PQexecPrepared( ::cStmtName, ::nParamCount,;
                                    pValues,;
                                    WDO_PtrNull(),;
                                    WDO_PtrNull(), 0 )

   IF ::nParamCount > 0
      WDO_BindFree( pValues )
   ENDIF

   IF hRes == 0
      ::lError := .T.
      ::cError := ::oConn:cError
      RETU .F.
   ENDIF

   nStatus := ::oConn:PQresultStatus( hRes )

   DO CASE
   CASE nStatus == PGRES_COMMAND_OK
      ::hRes          := hRes
      cTuples         := ::oConn:PQcmdTuples( hRes )
      ::nAffectedRows := iif( Empty( cTuples ), 0, Val( cTuples ) )
      ::nRows         := 0
      ::nCurRow       := 0

   CASE nStatus == PGRES_TUPLES_OK
      ::hRes    := hRes
      ::nRows   := ::oConn:PQntuples( hRes )
      ::nCurRow := 0
      cTuples   := ::oConn:PQcmdTuples( hRes )
      ::nAffectedRows := iif( Empty( cTuples ), ::nRows, Val( cTuples ) )
      ::LoadStruct()

   OTHERWISE
      ::lError := .T.
      ::cError := ::oConn:PQresultErrorMessage( hRes )
      ::oConn:PQclear( hRes )
      RETU .F.
   ENDCASE

RETU .T.

//	-------------------------------------------------------  //
//  Serializa un valor Harbour a la forma textual que PG espera
//  en `paramValues[]`. Mantiene paridad semántica con MySQL Alt B
//  pero sin escapes (los parámetros viajan fuera del SQL).
//	-------------------------------------------------------  //
STATIC FUNCTION _WdoPgSerialize( xValue, cType )

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
         RETU StrZero( Year( xValue ),  4 ) + "-" + ;
              StrZero( Month( xValue ), 2 ) + "-" + ;
              StrZero( Day( xValue ),   2 )
      ENDIF
      RETU hb_CStr( xValue )

   CASE cType == "t"
      IF ValType( xValue ) == "T"
         RETU hb_TSToStr( xValue )
      ENDIF
      RETU hb_CStr( xValue )

   CASE cType == "b"
      IF ValType( xValue ) == "L"
         RETU iif( xValue, "t", "f" )
      ENDIF
      RETU hb_CStr( xValue )
   ENDCASE

   //  default: string
RETU hb_CStr( xValue )

//	=======================================================  //
//  Helpers
//	=======================================================  //

//  Map PG type OID → WDO type letter.
//  OIDs from catalog/pg_type.h — stable across PG versions.
STATIC FUNCTION _WdoPgTypeMap( nOid )

   DO CASE
   //  Character types
   CASE AScan( { 18, 25, 1042, 1043, 1560, 1562 }, nOid ) != 0
      RETU "C"
   //  Integer / numeric / float
   CASE AScan( { 20, 21, 23, 26, 700, 701, 790, 1700 }, nOid ) != 0
      RETU "N"
   //  Boolean
   CASE nOid == 16
      RETU "L"
   //  Date
   CASE nOid == 1082
      RETU "D"
   //  Time / timestamp / timetz / timestamptz / interval
   CASE AScan( { 1083, 1114, 1184, 1266, 1186 }, nOid ) != 0
      RETU "T"
   //  Binary (bytea)
   CASE nOid == 17
      RETU "M"
   //  JSON / JSONB / XML / UUID — treat as text
   CASE AScan( { 114, 142, 2950, 3802 }, nOid ) != 0
      RETU "C"
   ENDCASE

RETU "C"

//	-------------------------------------------------------  //
//  Infer WDO type letter from Harbour value (parity con MySQL).
//	-------------------------------------------------------  //
STATIC FUNCTION _WdoPgInferType( xValue )

   DO CASE
   CASE xValue == NIL             ; RETU "s"
   CASE ValType( xValue ) == "N"  ; RETU iif( xValue == Int( xValue ), "i", "n" )
   CASE ValType( xValue ) == "D"  ; RETU "d"
   CASE ValType( xValue ) == "T"  ; RETU "t"
   CASE ValType( xValue ) == "L"  ; RETU "b"
   ENDCASE

RETU "s"

//	=======================================================  //
//  Prepared statement helpers
//	=======================================================  //

//  Scanner de placeholders para WDO_PG:Prepare.
//
//  Convierte:
//     ?        → $N     (positional, orden de aparición)
//     :name    → $N     (named, registra ":name" → N en hParamMap)
//
//  Respeta:
//     '…'      literal single-quote, con '' doblado como escape
//     "…"      identifier quote (PG — no es literal pero no se toca)
//     $tag$…$tag$  dollar-quoted string (tag vacío $$…$$ incluido)
//     --       comentario a fin de línea
//     /* … */  comentario de bloque (sin anidamiento)
//     ::       operador cast PG (NO confundir con :name)
//     $N       parámetros posicionales pre-existentes se emiten tal
//              cual (la detección "ya es PG nativo" se hace fuera,
//              en Prepare(); aquí solo garantizamos que $1, $2, …
//              se pasan intactos y no se cuentan de nuevo)
//
//  Devuelve el SQL reescrito. nParamCount y hParamMap vienen por
//  referencia; el caller los inicializa a 0 / {=>} .
//
//  El contador avanza con cada ? y cada :name nuevo. $N literales
//  presentes en el SQL se emiten sin tocarlos ni sumarlos.
//	-------------------------------------------------------  //
FUNCTION _HixWdoPgPrepareScan( cSql, /*@*/ nParamCount, /*@*/ hParamMap )

   LOCAL cOut    := ""
   LOCAL nLen    := Len( cSql )
   LOCAL i       := 1
   LOCAL cCh, cNext, cName, cTag, j, nTagLen

   DO WHILE i <= nLen

      cCh := SubStr( cSql, i, 1 )

      DO CASE

      CASE cCh == "'"                  //  literal single-quote
         cOut += cCh
         i++
         DO WHILE i <= nLen
            cNext := SubStr( cSql, i, 1 )
            cOut  += cNext
            IF cNext == "'"
               //  '' → escape doblado (PG estándar)
               IF i + 1 <= nLen .AND. SubStr( cSql, i + 1, 1 ) == "'"
                  cOut += "'"
                  i += 2
                  LOOP
               ENDIF
               i++
               EXIT
            ENDIF
            i++
         ENDDO

      CASE cCh == '"'                  //  identifier quote (PG)
         cOut += cCh
         i++
         DO WHILE i <= nLen
            cNext := SubStr( cSql, i, 1 )
            cOut  += cNext
            IF cNext == '"'
               IF i + 1 <= nLen .AND. SubStr( cSql, i + 1, 1 ) == '"'
                  cOut += '"'
                  i += 2
                  LOOP
               ENDIF
               i++
               EXIT
            ENDIF
            i++
         ENDDO

      CASE cCh == "-" .AND. i + 1 <= nLen .AND. ;
           SubStr( cSql, i + 1, 1 ) == "-"        //  -- comment to EOL
         DO WHILE i <= nLen
            cNext := SubStr( cSql, i, 1 )
            cOut  += cNext
            i++
            IF cNext == Chr( 10 ) ; EXIT ; ENDIF
         ENDDO

      CASE cCh == "/" .AND. i + 1 <= nLen .AND. ;
           SubStr( cSql, i + 1, 1 ) == "*"        //  /* ... */ block
         cOut += "/*"
         i += 2
         DO WHILE i <= nLen
            cNext := SubStr( cSql, i, 1 )
            cOut  += cNext
            i++
            IF cNext == "*" .AND. i <= nLen .AND. ;
               SubStr( cSql, i, 1 ) == "/"
               cOut += "/"
               i++
               EXIT
            ENDIF
         ENDDO

      CASE cCh == "$"                  //  dollar-quote o $N posicional
         //  $$...$$ (tag vacío)
         IF i + 1 <= nLen .AND. SubStr( cSql, i + 1, 1 ) == "$"
            cTag    := "$$"
            nTagLen := 2
            cOut    += cTag
            i       += 2
            DO WHILE i <= nLen
               IF i + nTagLen - 1 <= nLen .AND. ;
                  SubStr( cSql, i, nTagLen ) == cTag
                  cOut += cTag
                  i    += nTagLen
                  EXIT
               ENDIF
               cOut += SubStr( cSql, i, 1 )
               i++
            ENDDO
            LOOP
         ENDIF
         //  $tag$...$tag$ (tag debe empezar por letra/_ según PG)
         IF i + 1 <= nLen
            cNext := SubStr( cSql, i + 1, 1 )
            IF ( cNext >= "A" .AND. cNext <= "Z" ) .OR. ;
               ( cNext >= "a" .AND. cNext <= "z" ) .OR. cNext == "_"
               j := i + 1
               DO WHILE j <= nLen
                  cNext := SubStr( cSql, j, 1 )
                  IF ( cNext >= "A" .AND. cNext <= "Z" ) .OR. ;
                     ( cNext >= "a" .AND. cNext <= "z" ) .OR. ;
                     ( cNext >= "0" .AND. cNext <= "9" ) .OR. ;
                     cNext == "_"
                     j++
                  ELSE
                     EXIT
                  ENDIF
               ENDDO
               IF j <= nLen .AND. SubStr( cSql, j, 1 ) == "$"
                  cTag    := SubStr( cSql, i, j - i + 1 )
                  nTagLen := Len( cTag )
                  cOut    += cTag
                  i       := j + 1
                  DO WHILE i <= nLen
                     IF i + nTagLen - 1 <= nLen .AND. ;
                        SubStr( cSql, i, nTagLen ) == cTag
                        cOut += cTag
                        i    += nTagLen
                        EXIT
                     ENDIF
                     cOut += SubStr( cSql, i, 1 )
                     i++
                  ENDDO
                  LOOP
               ENDIF
            ENDIF
         ENDIF
         //  No es dollar-quote: será $N posicional o $ suelto. Emitir
         //  tal cual; si sigue un dígito, no incrementar nParamCount
         //  (son placeholders PG pre-existentes).
         cOut += "$"
         i++

      CASE cCh == "?"                  //  positional placeholder MySQL-style
         nParamCount++
         cOut += "$" + hb_NToS( nParamCount )
         i++

      CASE cCh == ":"                  //  :name  ó  :: cast
         //  :: operador cast PG — emitir ambos y seguir
         IF i + 1 <= nLen .AND. SubStr( cSql, i + 1, 1 ) == ":"
            cOut += "::"
            i    += 2
            LOOP
         ENDIF
         //  :name → $N  (y registrar en hParamMap)
         IF i + 1 <= nLen
            cNext := SubStr( cSql, i + 1, 1 )
            IF ( cNext >= "A" .AND. cNext <= "Z" ) .OR. ;
               ( cNext >= "a" .AND. cNext <= "z" ) .OR. cNext == "_"
               cName := ""
               j     := i + 1
               DO WHILE j <= nLen
                  cNext := SubStr( cSql, j, 1 )
                  IF ( cNext >= "A" .AND. cNext <= "Z" ) .OR. ;
                     ( cNext >= "a" .AND. cNext <= "z" ) .OR. ;
                     ( cNext >= "0" .AND. cNext <= "9" ) .OR. ;
                     cNext == "_"
                     cName += cNext
                     j++
                  ELSE
                     EXIT
                  ENDIF
               ENDDO
               //  Si el nombre ya estaba mapeado, reutilizar su índice
               IF hb_HHasKey( hParamMap, ":" + cName )
                  cOut += "$" + hb_NToS( hParamMap[ ":" + cName ] )
               ELSE
                  nParamCount++
                  hParamMap[ ":" + cName ] := nParamCount
                  cOut += "$" + hb_NToS( nParamCount )
               ENDIF
               i := j
               LOOP
            ENDIF
         ENDIF
         cOut += ":"
         i++

      OTHERWISE
         cOut += cCh
         i++

      ENDCASE

   ENDDO

RETU cOut

//	-------------------------------------------------------  //
//  Quick detect: ¿el SQL ya trae `$N` posicional PG-nativo?
//  Escanea respetando literales y comentarios. Si encuentra
//  un `$` seguido de dígito fuera de contexto literal → .T.
//  Usar en Prepare() antes de invocar _HixWdoPgPrepareScan para
//  decidir "ya es PG nativo, no reescribir".
//	-------------------------------------------------------  //
FUNCTION _HixWdoPgHasDollarN( cSql )

   LOCAL nLen := Len( cSql )
   LOCAL i    := 1
   LOCAL cCh, cNext, cTag, j, nTagLen

   DO WHILE i <= nLen

      cCh := SubStr( cSql, i, 1 )

      DO CASE

      CASE cCh == "'"
         i++
         DO WHILE i <= nLen
            cNext := SubStr( cSql, i, 1 )
            IF cNext == "'"
               IF i + 1 <= nLen .AND. SubStr( cSql, i + 1, 1 ) == "'"
                  i += 2
                  LOOP
               ENDIF
               i++
               EXIT
            ENDIF
            i++
         ENDDO

      CASE cCh == '"'
         i++
         DO WHILE i <= nLen
            cNext := SubStr( cSql, i, 1 )
            IF cNext == '"'
               i++
               EXIT
            ENDIF
            i++
         ENDDO

      CASE cCh == "-" .AND. i + 1 <= nLen .AND. ;
           SubStr( cSql, i + 1, 1 ) == "-"
         DO WHILE i <= nLen
            IF SubStr( cSql, i, 1 ) == Chr( 10 ) ; i++ ; EXIT ; ENDIF
            i++
         ENDDO

      CASE cCh == "/" .AND. i + 1 <= nLen .AND. ;
           SubStr( cSql, i + 1, 1 ) == "*"
         i += 2
         DO WHILE i <= nLen
            IF SubStr( cSql, i, 1 ) == "*" .AND. i + 1 <= nLen .AND. ;
               SubStr( cSql, i + 1, 1 ) == "/"
               i += 2
               EXIT
            ENDIF
            i++
         ENDDO

      CASE cCh == "$"
         //  Dollar-quote $$...$$ — saltar entero sin inspeccionar body
         IF i + 1 <= nLen .AND. SubStr( cSql, i + 1, 1 ) == "$"
            cTag    := "$$"
            nTagLen := 2
            i       += 2
            DO WHILE i <= nLen
               IF i + nTagLen - 1 <= nLen .AND. ;
                  SubStr( cSql, i, nTagLen ) == cTag
                  i += nTagLen
                  EXIT
               ENDIF
               i++
            ENDDO
            LOOP
         ENDIF
         //  Dollar-quote $tag$...$tag$ (tag empieza por letra/_)
         IF i + 1 <= nLen
            cNext := SubStr( cSql, i + 1, 1 )
            IF ( cNext >= "A" .AND. cNext <= "Z" ) .OR. ;
               ( cNext >= "a" .AND. cNext <= "z" ) .OR. cNext == "_"
               j := i + 1
               DO WHILE j <= nLen
                  cNext := SubStr( cSql, j, 1 )
                  IF ( cNext >= "A" .AND. cNext <= "Z" ) .OR. ;
                     ( cNext >= "a" .AND. cNext <= "z" ) .OR. ;
                     ( cNext >= "0" .AND. cNext <= "9" ) .OR. ;
                     cNext == "_"
                     j++
                  ELSE
                     EXIT
                  ENDIF
               ENDDO
               IF j <= nLen .AND. SubStr( cSql, j, 1 ) == "$"
                  cTag    := SubStr( cSql, i, j - i + 1 )
                  nTagLen := Len( cTag )
                  i       := j + 1
                  DO WHILE i <= nLen
                     IF i + nTagLen - 1 <= nLen .AND. ;
                        SubStr( cSql, i, nTagLen ) == cTag
                        i += nTagLen
                        EXIT
                     ENDIF
                     i++
                  ENDDO
                  LOOP
               ENDIF
            ENDIF
            //  $<digit> → $N posicional PG-native
            IF cNext >= "0" .AND. cNext <= "9"
               RETU .T.
            ENDIF
         ENDIF
         i++

      OTHERWISE
         i++

      ENDCASE

   ENDDO

RETU .F.
