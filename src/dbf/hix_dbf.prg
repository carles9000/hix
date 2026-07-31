/* ---------------------------------------------------------
 File.......: HIX_DBF.prg
 Description: Conexión a Dbf      
 Author.....: Carles Aubia Floresvi
 Date:......: 26/07/2019
 Updated:...: 19/01/2026
 --------------------------------------------------------- */
#INCLUDE 'hbclass.ch'
#INCLUDE 'error.ch'
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

#DEFINE VERSION_HIX_DBF   '1.0'

#DEFINE DBS_NAME        1
#DEFINE DBS_TYPE        2
#DEFINE DBS_LEN         3
#DEFINE DBS_DEC         4

#XCOMMAND ? [<explist,...>] => UEcho( '<br>' [,<explist>] )
#XCOMMAND TRY  => BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }
#XCOMMAND CATCH [<!oErr!>] => RECOVER [USING <oErr>] <-oErr->
#XCOMMAND FINALLY => ALWAYS

FUNCTION UDbf()
RETURN HIX_Dbf():New()

CLASS HIX_DBF

   CLASSDATA nTime      INIT 3

   DATA cPath       INIT hb_dirbase()
   DATA cRdd       INIT 'DBFCDX'
   DATA cDbf       INIT ''
   DATA cCdx       INIT ''
   DATA cTag       INIT ''
   DATA lExclusive      INIT .F.
   DATA lRead        INIT .F.
   DATA lConnect      INIT .F.
   DATA cAlias
   DATA hFields      INIT { => }
   DATA aFields      INIT {}
   DATA nFields
   DATA lDoError      INIT .T.
   DATA lToUTF8      INIT .F.
   DATA aYesNo       INIT { 'Yes', 'No' }
   DATA aFields_Select      INIT {}
   DATA cFields_Type        INIT ''
   DATA oError


   METHOD New( cDbf, cCdx, cTag, aFields, lOpen )  CONSTRUCTOR

   METHOD Open()
   METHOD Close()      INLINE ( ::cAlias )->( DbCloseArea() )

   METHOD Count()       INLINE ( ::cAlias )->( RecCount() )
   METHOD CountDeleted()

   METHOD FieldPos( n )      INLINE ( ::cAlias )->( FieldPos( n ) )
   METHOD FieldName( n )     INLINE ( ::cAlias )->( FieldName( n ) )
   METHOD FieldGet( ncField )    INLINE ( ::cAlias )->( FieldGet( If( ValType( ncField ) == "C", ::FieldPos( ncField ), ncField ) ) )
   METHOD FieldPut( ncField, uValue )

   METHOD Next( n )       INLINE ( hb_default( @n, 1 ), ( ::cAlias )->( DbSkip( n ) ) )
   METHOD Prev( n )       INLINE ( hb_default( @n, - 1 ), ( ::cAlias )->( DbSkip( n ) ) )
   METHOD First()      INLINE ( ::cAlias )->( DbGoTop() )
   METHOD Last()       INLINE ( ::cAlias )->( DbGoBottom() )

   METHOD Focus( cTag )    INLINE ( ::cAlias )->( OrdSetFocus( cTag ) )
   METHOD Rlock()
   METHOD Unlock()     INLINE ( ::cAlias )->( DbUnlock() )
   METHOD Zap()      INLINE ( ::cAlias )->( __DbZap() )
   METHOD Pack( cError )

   METHOD NewAlias()
   METHOD Delete( nRecno, lTogglee )
   METHOD Append()
   METHOD Deleted()     INLINE ( ::cAlias )->( Deleted() )
   METHOD Recall()     INLINE ( ::cAlias )->( DbRecall() )


   METHOD Seek( cUser, lSoftSeek  )
   METHOD Insert( hFields, cError )
   METHOD Update( nRecno, hFields, cError )
   METHOD Blank()
   METHOD Row( aFields, lToStringWeb )
   METHOD Normalize( cField, lToStringWeb )

   METHOD RecCount()     INLINE ( ::cAlias )->( RecCount() )
   METHOD Recno()      INLINE ( ::cAlias )->( Recno() )
   METHOD Bof()      INLINE ( ::cAlias )->( Bof() )
   METHOD Eof()      INLINE ( ::cAlias )->( Eof() )
   METHOD Skip( n )     INLINE ( ::cAlias )->( DbSkip( n ) )
   METHOD Goto( nRecno )

   METHOD SetFields( aFields, cType  )
   METHOD Hide( aFields )
   METHOD Visible( aFields )


   METHOD GetRecno( nRecno, hRow, aFields, lToStringWeb )
   METHOD GetId( cId, hRow, aFields, lToStringWeb )
   METHOD LoadAll()

   METHOD Page( nPage, nRows, nTotalPages )

   METHOD Version()     INLINE VERSION_HIX_DBF
   METHOD VersionName()    INLINE 'HIX_DBF ' + VERSION_HIX_DBF

   METHOD ThrowError( oError )

   METHOD SetError( cMsg, cOp )

   METHOD View( aData, cTitle )

ENDCLASS

// -------------------------------------------------- //

METHOD New( cDbf, cCdx, cTag, aFields, lOpen ) CLASS HIX_DBF

   hb_default( @cDbf, '' )
   hb_default( @cCdx, '' )
   hb_default( @cTag, '' )
   hb_default( @aFields, {} )
   hb_default( @lOpen, .F. )

   ::cDbf  := cDbf
   ::cCdx  := cCdx
   ::cTag  := cTag
   ::aFields := aFields

   IF lOpen

      ::Open()

   ENDIF

   RETU SELF

// -------------------------------------------------- //

METHOD Open() CLASS HIX_DBF

   LOCAL cFileDbf, cAlias, cFileCdx, oError, n, aSt, nPos, cField
   LOCAL lOpen := .F.

   IF Right( ::cPath, 1 ) != '/' .AND. Right( ::cPath, 1 ) != '\'

      ::cPath += hb_ps()

   ENDIF

   cFileDbf  := ::cPath + ::cDbf

   IF !file( cFileDbf )

      ::SetError( _( 'DBF_ERR_NO_FILE' ), 'Open' )
      RETURN .F.

   ENDIF

   TRY

      ::cAlias := ::NewAlias()

      IF ::lExclusive

         USE ( cFileDbf ) ALIAS ( ::cAlias ) VIA ::cRdd EXCLUSIVE
      ELSE

         USE ( cFileDbf ) SHARED NEW ALIAS ( ::cAlias ) VIA ::cRdd

      ENDIF

      ::lConnect := .T.


   CATCH oError

      ::ThrowError( oError )

      RETU .F.

   END

   ::hFields := { => }

   aSt := ( ::cAlias )->( DbStruct() )


   IF empty( ::aFields_Select )

      ::nFields := len( aSt )   // (::cAlias)->( FCount() )

      FOR n := 1 TO ::nFields

         ::hFields[ aSt[ n ][ 1 ] ] := aSt[ n ]

      NEXT

   ELSE

      ::nFields := 0

      FOR n := 1 TO len( aSt  )

         cField := aSt[ n ][ 1 ]

         nPos := Ascan( ::aFields_Select, {| u | u == cField } )

         DO CASE

            CASE ::cFields_Type == 'V'          // Visible

            IF nPos > 0

               ::hFields[ cField ] := aSt[ n ]
               ::nFields++

               ENDIF

            CASE ::cFields_Type == 'H'         // Hidden

            IF nPos == 0   // If not exist

               ::hFields[ cField ] := aSt[ n ]
               ::nFields++

               ENDIF

         ENDCASE

      NEXT

      IF ::nFields == 0

         ::SetError( _( 'DBF_ERR_NO_FIELDS' ), 'Open' )
         RETURN .F.

      ENDIF

   ENDIF

   IF !empty( ::cCdx )

      cFileCdx  := ::cPath + ::cCdx

      IF file( cFileCdx )

// SET INDEX TO ( cFileCdx )
         ( ::cAlias )->( OrdListAdd( cFileCdx ) )

         IF !empty( ::cTag )

            ( ::cAlias )->( OrdSetFocus( ::cTag ) )

            IF ( ::cAlias )->( IndexOrd() ) == 0


               ::SetError( _( 'DBF_ERR_TAG_NOT_FOUND', ::cTag ), 'Open' )
               RETURN .F.

            ENDIF

         ENDIF

      ELSE

         ::SetError( _( 'DBF_ERR_CDX_NOT_FOUND', ::cCdx ), 'Open' )
         RETURN .F.

      ENDIF

   ENDIF

   RETU ::lConnect

// -------------------------------------------------- //

METHOD SetFields( aFields, cType ) CLASS HIX_DBF

   hb_default( @cType, '' )

   IF Valtype( aFields ) == 'C'

      aFields := { aFields }

   ENDIF

   IF Valtype( aFields ) == 'A'

      AEval( aFields, {| u, n | aFields[ n ] := upper( u ) } )
      ::aFields_Select := aFields
      ::cFields_Type := cType       // H=Hidden, V=Visible

   ENDIF

   RETU NIL


// -------------------------------------------------- //

METHOD Visible( aFields ) CLASS HIX_DBF

   RETU ::SetFields( aFields, 'V' )

// -------------------------------------------------- //

METHOD Hide( aFields ) CLASS HIX_DBF

   RETU ::SetFields( aFields, 'H' )

// -------------------------------------------------- //

METHOD GoTo( nRecno ) CLASS HIX_DBF

   hb_default( @nRecno, 0 )

   ( ::cAlias )->( DbGoTo( nRecno ) )

   RETU NIL

// -------------------------------------------------- //
// @hRow by reference

METHOD GetRecno( nRecno, hRow, aFields, lToStringWeb )  CLASS HIX_DBF

   LOCAL lEof

   hb_default( @nRecno, 0 )
   hb_default( @lToStringWeb, .F. )

   hRow := { => }

   ( ::cAlias )->( dbGoTo( nRecno ) )

   lEof := ( ::cAlias )->( Eof() )

   IF ! lEof

      hRow := ::Row( aFields, lToStringWeb )

   ENDIF


   RETU !lEof

// -------------------------------------------------- //
// @hRow by reference
// Need index for id

METHOD GetId( cId, hRow, aFields, lToStringWeb ) CLASS HIX_DBF

   LOCAL lFound

   hb_default( @aFields, {} )
   hb_default( @lToStringWeb, .F. )

   hRow := { => }

   ( ::cAlias )->( dbGoTop() )

   lFound := ::Seek( cId )

   IF lFound

      hRow := ::Row( aFields, lToStringWeb )

   ENDIF

   RETU lFound

// ----------------------------------------------- //

METHOD Delete( nRecno, lTogglee, lIsDeleted ) CLASS HIX_DBF

   LOCAL lDelete := .F.

   hb_default( @nRecno, ( ::cAlias )->( Recno() ) )
   hb_default( @lTogglee, .F. )
   hb_default( @lIsDeleted, .F. )

   ( ::cAlias )->( DbGoto(  nRecno ) )

   IF ( ::cAlias )->( Eof() )

      RETU .F.

   ENDIF

   IF ::Rlock()

      IF lTogglee

         IF ( ::cAlias )->( deleted() )

            ( ::cAlias )->( DbRecall() )
         ELSE
            ( ::cAlias )->( DbDelete() )

         ENDIF

      ELSE
         ( ::cAlias )->( DbDelete() )

      ENDIF

      ( ::cAlias )->( DbUnlock() )

      lDelete := .T.

   ELSE
      ::SetError( _( 'DBF_ERR_LOCK' ), 'RDD' )
      RETU .F.

   ENDIF

   lIsDeleted := ::Deleted()


   RETU lDelete

// ----------------------------------------------- //

METHOD Append() CLASS HIX_DBF

   LOCAL nlapsus       := 0
   LOCAL nIni

   IF ! ::lConnect

      RETU .F.

   ENDIF

   nIni := Seconds()

   WHILE nLapsus >= 0

      ( ::cAlias )->( DbAppend() )

      IF !Neterr() .OR. ( nLapsus == 0 )

         EXIT

      ENDIF

      nLapsus := ::nTime - ( seconds() - nIni )

   END

   RETU IF( !Neterr(), .T., .F. )

// ----------------------------------------------- //

METHOD Seek( uValue, lSoftSeek, cTag  ) CLASS HIX_DBF

   LOCAL cOld_Focus, lSeek

   hb_default( @lSoftSeek, .F. )
   hb_default( @cTag, '' )

   IF !empty( @cTag )

      cOld_Focus := ( ::cAlias )->( OrdSetFocus() )
      ( ::cAlias )->( OrdSetFocus( cTag ) )

   ENDIF

   lSeek := ( ::cAlias )->( DbSeek( uValue, lSoftSeek ) )

   IF !empty( @cTag )

      ( ::cAlias )->( OrdSetFocus( cOld_Focus ) )

   ENDIF

   RETU lSeek

// ----------------------------------------------- //

METHOD Blank( lToStringWeb ) CLASS HIX_DBF

   LOCAL nRecno  :=  ( ::cAlias )->( recno() )
   LOCAL hRow   := { => }

   hb_default( @lToStringWeb, .F. )

   ( ::cAlias )->( DbGobottom() )
   ( ::cAlias )->( DbSkip( 1 ) )

   hRow := ::Row( NIL, lToStringWeb )

   hRow[ '_recno' ]  := 0
   hRow[ '_deleted' ] := .F.

   ( ::cAlias )->( DbGoTo( nRecno ) )

   RETU hRow

// ---------------------------------------------------- //
// Load register. If lToString, convert value to string

METHOD Row( aFields, lToStringWeb ) CLASS HIX_DBF

   LOCAL hRow    := { => }
   LOCAL n, cType, uValue, cField, aPair, aDef, nPos
   LOCAL nFields

   hb_default( @lToStringWeb, .F. )

   hRow[ '_recno' ]  := ( ::cAlias )->( Recno() )
   hRow[ '_deleted' ]  := ( ::cAlias )->( deleted()  )

   HB_HCaseMatch( ::hFields, .F. )


   IF HB_IsArray( aFields ) .AND. len( aFields ) > 0

      nFields := len( aFields )

      FOR n := 1 TO nFields

         cField := aFields[ n ]

         IF HB_HHasKey( ::hFields, cField )

            hRow[ cField ] := ::Normalize( cField, lToStringWeb )

         ENDIF

      NEXT

   ELSE

      nFields := len( ::hFields )

      FOR n := 1 TO nFields

         aPair := HB_HPairAt( ::hFields, n )  // uValue := (::cAlias)->( FieldGet( n ) )

         cField  := aPair[ 1 ]

         hRow[ cField ] := ::Normalize( cField, lToStringWeb )

      NEXT

   ENDIF


   HB_HCaseMatch( hRow, .F. )  // Default all

   RETU hRow

// -------------------------------------------------- //

METHOD Normalize( cField, lToStringWeb ) CLASS HIX_DBF

   LOCAL nPos  := ( ::cAlias )->( FieldPos( cField ) )
   LOCAL uValue  := ( ::cAlias )->( FieldGet( nPos ) )
   LOCAL cType   := valtype( uValue )
   LOCAL aDef

   IF lToStringWeb

      DO CASE

         CASE cType == 'C' .OR. cType == 'M'
            uValue := if( ::lToUtf8, hb_StrToUtf8( alltrim( uValue ) ), alltrim( uValue ) )
         CASE cType == 'D'
// uValue := DToC( uValue )
            uValue := UDateToHtml( uValue )
         CASE cType == 'N'
            aDef  := ::hFields[ cField ]
            uValue := Str( uValue, aDef[ DBS_LEN ], aDef[ DBS_DEC ] )
         CASE cType == 'L'
            uValue := ULogicToHtmlChecked( uValue )
         OTHERWISE
            uValue := if( ::lToUtf8, hb_StrToUtf8( alltrim( hb_CStr( uValue ) ) ), alltrim( hb_Cstr( uValue ) ) )

      ENDCASE

   ELSE

      DO CASE

         CASE cType == 'C' .OR. cType == 'M'

// try
            uValue := if( ::lToUtf8, hb_StrToUtf8( alltrim( uValue ) ), alltrim( uValue ) )
// catch oError

// end

      ENDCASE

   ENDIF

   RETU uValue

// ----------------------------------------------- //
// @cError by reference

METHOD Update( nRecno, hFields, cError ) CLASS HIX_DBF

   LOCAL lUpdate := .F.
   LOCAL n, j, h, nPos, oError

   hb_default( @nRecno, ( ::cAlias )->( Recno() ) )
   hb_default( @hFields, { => } )

   ( ::cAlias )->( DbGoTo( nRecno ) )

   IF ::Rlock()


      lUpdate := .T.

      HB_HCaseMatch( hFields, .F. )

      FOR n :=  1 TO len( hFields )


         h := HB_HPairAt( hFields, n )

         nPos := ( ::cAlias )->( FieldPos( h[ 1 ] ) )


         try

            ( ::cAlias )->( Fieldput( nPos, h[ 2 ] ) )

         catch oError

            ::THROWERROR( oError )

         END

      NEXT

      ( ::cAlias )->( DbCommit() )
      ( ::cAlias )->( DbUnlock() )

   ELSE
      cError := _( 'DBF_ERR_LOCK' )

   ENDIF

   RETU lUpdate

// -------------------------------------------------- //
// @cError, @nRecno  by reference

METHOD Insert( hFields, cError, nRecno  ) CLASS HIX_DBF

   LOCAL lInsert  := .F.

   nRecno   := 0

   IF ::Append()

      nRecno := ::Recno()

      lInsert := ::Update( nRecno, hFields, @cError )

   ENDIF


   RETU lInsert

// -------------------------------------------------- //

METHOD NewAlias( cAlias ) CLASS HIX_DBF

   LOCAL cNewAlias, nArea := 1

   IF Empty( cAlias )

      cAlias   := "DBF"

   ENDIF

   WHILE Select( cNewAlias := ( cAlias + ;
         StrZero( nArea++, 3 ) ) ) != 0

   END

RETURN cNewAlias

// -------------------------------------------------- //

METHOD LoadAll( aFields, cScopeTop, cScopeBottom, bCondition ) CLASS HIX_DBF

   LOCAL aRows := {}

   hb_default( @aFields, {} )
   hb_default( @cScopeTop, '' )
   hb_default( @cScopeBottom, '' )


   IF !empty( cScopetop )

      ( ::cAlias )->( OrdScope( 0, cScopeTop ) )

   ENDIF

   IF !empty( cScopeBottom )

      ( ::cAlias )->( OrdScope( 1, cScopeBottom ) )

   ENDIF

   ( ::cAlias )->( dbGoTop() )

   IF HB_IsBlock( bCondition )

      WHILE ( ::cAlias )->( !Eof() )

         IF eval( bCondition, ::cAlias )

            Aadd( aRows, ::Row( aFields ) )

         ENDIF

         ( ::cAlias )->( DbSkip() )

      END

   ELSE

      WHILE ( ::cAlias )->( !Eof() )

         Aadd( aRows, ::Row( aFields ) )

         ( ::cAlias )->( DbSkip() )

      END

   ENDIF


   IF !empty( cScopetop )

      ( ::cAlias )->( OrdScope( 0, NIL ) )

   ENDIF

   IF !empty( cScopeBottom )

      ( ::cAlias )->( OrdScope( 1, NIL ) )

   ENDIF

   RETU aRows

// -------------------------------------------------- //

METHOD SetError( cMsg, cOpe ) CLASS HIX_DBF

   ::THROWERROR( cMsg, cOpe )

   RETU NIL

// -------------------------------------------------- //

METHOD CountDeleted() CLASS HIX_DBF

   LOCAL nTotal := 0
   LOCAL lSet  := Set( _SET_DELETED, .F. )
   LOCAL nRecno

   IF ! ::lConnect

      RETU 0

   ENDIF

   nRecno := ( ::cAlias )->( Recno() )


   ( ::cAlias )->( DbGoTop() )

   COUNT TO nTotal FOR ( ::cAlias )->( Deleted() )

   Set( _SET_DELETED, lSet )

   ( ::cAlias )->( DbGoTo( nRecno ) )

   RETU nTotal

// -------------------------------------------------- //

METHOD FieldPut( ncField, uValue ) CLASS HIX_DBF

   LOCAL lUpdated := .F.
   LOCAL cField

   IF !::lConnect

      RETU .F.

   ENDIF


   IF ValType( ncField ) == "C"

// cField := ::FieldPos( ncField )
      cField := ( ::cAlias )->( FieldPos( ncField ) )
   ELSE

      cField := ncField

   ENDIF

   ( ::cAlias )->( FieldPut( cField, uValue ) )

   lUpdated := .T.

   RETU lUpdated

// -------------------------------------------------- //

METHOD RLock( xIdentidad ) CLASS HIX_DBF

   LOCAL nlapsus := 0
   LOCAL lRlock  := .F.
   LOCAL nIni

   IF ! ::lConnect

      RETU .F.

   ENDIF

   nIni := Seconds()

   WHILE nLapsus >= 0

      lRlock := ( ::cAlias )->( DbRlock( xIdentidad ) )

      IF !Neterr() .OR. ( nLapsus == 0 )

         EXIT

      ENDIF

      nLapsus := ::nTime - ( seconds() - nIni )

   END

   RETU lRlock

// ------------------------------------------------------- //

METHOD View( aData, cTitle, lAll ) CLASS HIX_DBF

   LOCAL cHtml  := ''
   LOCAL n, j, nLen, aPair, hRow, nFields, nStart

   hb_default( @aData, {} )
   hb_default( @cTitle, '' )
   hb_default( @lAll, .F. )

   IF empty( aData )

      RETU NIL

   ENDIF


   cHtml += '<style>'
   cHtml += '.wdo_mytable_title { border: 1px solid black;padding: 5px;text-align: center;background-color: #425ecf;color: white;}'
   cHtml += '#wdo_mytable tr:hover {background-color: #ddd;}'
   cHtml += "#wdo_mytable thead tr:hover {background-color: #425ecf !important;}"
   cHtml += '#wdo_mytable tr:nth-child(even){background-color: #e0e6ff;}'
   cHtml += '#wdo_mytable { font-family: "Trebuchet MS", Arial, Helvetica, sans-serif;border-collapse: collapse; width: 100%; }'
   cHtml += '#wdo_mytable thead { background-color: #425ecf;color: white;}'
   cHtml += '</style>'



   IF !empty( cTitle )

      cHtml += '<div class="wdo_mytable_title">' + cTitle + '</div>'

   ENDIF


   hRow    := aData[ 1 ]     // First Row
   nFields   := len( hRow )
   nStart  := if( lAll, 1, 3 )   // 2 primers camps _recno, _ddeleted


   cHtml += '<table id="wdo_mytable" border="1" cellpadding="3" >'


   cHtml += '<thead>'


   cHtml += '<tr>'

   FOR n := nStart TO nFields

      aPair := HB_HPairAt( hRow, n )

      cHtml += '<td>' + Upper( aPair[ 1 ] ) + '</td>'

   NEXT

   cHtml += '</tr></thead>'

   nLen := len( aData )


   cHtml += '<tbody>'

// ? cHtml

   FOR n := 1 TO nLen

      cHtml += '<tr>'

      FOR j := nStart TO nFields  // 2 primers camps _recno, _ddeleted

         cHtml += '<td>' + hb_CStr( HB_HValueAt( aData[ n ], j ) ) + '</td>'

      NEXT

      cHtml += '</tr>'

// ?? cHtml

   NEXT

// ?? '</tbody></table><hr>'
   cHtml += '</tbody></table><hr>'

   ? cHtml

   RETU cHtml

// ------------------------------------------------------- //

METHOD Pack( cError )  CLASS HIX_DBF

   LOCAL lPacked := .F.
   LOCAL oError

   cError := ''

   TRY

      ( ::cAlias )->( __DbPack() )

      lPacked := .T.

   CATCH oError

      ::THROWERROR( oError )

   END

   RETU lPacked

// ------------------------------------------------------- //

METHOD Page( nPage, nRows, aFields, nTotalPages )  CLASS HIX_DBF

   LOCAL nTotal  := ( ::cAlias )->( RecCount() )
   LOCAL aRows  := {}
   LOCAL n   := 1
   LOCAL nStart

   hb_default( @nPage, 1 )
   hb_default( @nRows, 10 )
   hb_default( @aFields, {} )

// nTotalPages := Int( nTotal / nRows )
   nTotalPages := Int( ( nTotal + nRows - 1 ) / nRows )

   IF nPage > nTotalPages

      nPage := nTotalPages

   ENDIF

   nStart := ( ( nPage - 1 ) * nRows ) + 1

   IF empty( ( ::cAlias )->( ordSetFocus() ) )

      ( ::cAlias )->( DbGoto( nStart ) )
   ELSE
      ( ::cAlias )->( OrdKeyGoto( nStart ) )

   ENDIF

   WHILE n <= nRows .AND. ( ::cAlias )->( !eof() )

      Aadd( aRows, ::Row( aFields ) )

      ( ::cAlias )->( DbSkip() )

      n++

   END

   RETU aRows

// ------------------------------------------------------- //

METHOD ThrowError( oError, cOpe ) CLASS HIX_DBF

   LOCAL oErr   := ErrorNew()

   hb_default( @cOpe, '' )

   oErr:severity     := ES_ERROR
   oErr:genCode      := EG_OPEN
   oErr:filename     := ::cDbf

   IF Valtype( oError ) == 'O'

      oErr:description  := oError:description
      oErr:operation    := 'HIX_DBF:' + oError:operation
   ELSE
      oErr:description  := oError
      oErr:operation    := 'HIX_DBF ' + cOpe

   ENDIF

   HIX_Throw( oErr )

RETURN NIL


// ------------------------------------------------------- //
