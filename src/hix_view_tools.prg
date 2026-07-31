/*-----------------------------------------------------------
  File ......: hix_view_tools.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-07
  Description: View utility functions — file path normalization
               (UOsFileName, etc.).
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
// --------------------------------------------------------- //
FUNCTION UOsFileName( cFileName )

   IF hb_osPathSeparator() != "/"

      RETURN StrTran( cFileName, "/", hb_osPathSeparator() )

   ENDIF

RETURN cFileName

// --------------------------------------------------------- //

FUNCTION HIX_GetRoot()
RETURN UConfig( "paths", "root", "www" )

// --------------------------------------------------------- //

FUNCTION HIX_GetRootAbsolute()

   LOCAL cPath := UOsFileName( hb_dirbase() + HIX_GetRoot() )

   IF right( cPath, 1 ) != hb_ps()

      cPath += hb_ps()

   ENDIF

RETURN cPath

// --------------------------------------------------------- //

// --------------------------------------------------------- //

FUNCTION UStr( u )

   LOCAL cType := valtype( u )

   DO CASE

      CASE cType == 'C' ; RETU u
      CASE cType == 'L' ; RETU if( u, '.T.', '.F.' )
      CASE cType == 'N' ; RETU hb_NToS( u )
      CASE cType == 'D' ; RETU dtoc( u )
      CASE cType == 'M' ; RETU u
      CASE cType == 'A' ; RETU hb_jsonEncode( u )
      CASE cType == 'H' ; RETU hb_jsonEncode( u )
      CASE cType == 'O' ; RETU '** object **'
      CASE cType == 'U' ; RETU ''
      OTHERWISE
         RETU ''

   ENDCASE

   RETU ''

// --------------------------------------------------------- //

FUNCTION UDateToHtml( dFecha )

   LOCAL cFecha

   IF valtype( dFecha ) == 'D'

      cFecha := DToS( dFecha ) // Retorna "20260207"

   ENDIF

   IF valtype( cFecha ) == 'C' .AND. len( cFecha ) == 8

// Retornamos "2026-02-07"
      RETURN Left( cFecha, 4 ) + "-" + SubStr( cFecha, 5, 2 ) + "-" + Right( cFecha, 2 )

   ENDIF

RETURN ''

// ------------------------------------------------------ //

FUNCTION ULogicToHtmlChecked( lValue )

   hb_default( @lValue, .F. )

RETURN iif( lValue, "checked", "" )

// ------------------------------------------------------ //
// Default {  { key => value }, ...  }

FUNCTION UHashToHtmlSelect( aHash, cSelect, cKey, cValue )

   LOCAL cHtml := ""
   LOCAL nI, aPair, cValueKey, cValueValue

   hb_default( @aHash, {} )
   hb_default( @cSelect, '' )
   hb_default( @cKey, 'key' )
   hb_default( @cValue, 'value' )

   // El valor por defecto vacío
   cHtml += '<option value="" ' + iif( Empty( cSelect ), "selected", "" ) + '></option>'

   // Recorremos el array

   FOR nI := 1 TO Len( aHash )

// aPair := HB_HPairAt( aHash[nI],
      cValueKey   := aHash[ nI ][ cKey ]
      cValueValue  := aHash[ nI ][ cValue ]

      cHtml += '<option value="' + cValueKey + '"'

      // Si el valor actual coincide con el seleccionado, añadimos 'selected'

      IF cValueKey == cSelect

         cHtml += ' selected'

      ENDIF

      cHtml += '>' + cValueValue + '</option>'

   NEXT

RETURN cHtml

// --------------------------------------------------------- //
