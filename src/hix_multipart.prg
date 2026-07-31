/*-----------------------------------------------------------
  File ......: hix_multipart.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-01
  Description: multipart/form-data parser — returns array of
               { name, filename, mime, data, size }.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_REQUEST

#INCLUDE "hix_logger.ch"

// ============================================================
// HIX_ParseMultipart — punto de entrada publico
// ============================================================
FUNCTION HIX_ParseMultipart( cBody, cBoundary )

   LOCAL aParts  := {}
   LOCAL cDelim  := "--" + cBoundary
   LOCAL nPos    := 1
   LOCAL nNext, cPart, hPart, nSkip

   IF Empty( cBody ) .OR. Empty( cBoundary )

      RETURN aParts

   ENDIF

   // Localizar el primer boundary
   nPos := At( cDelim, cBody )

   IF nPos == 0

      RETURN aParts

   ENDIF

   DO WHILE .T.

      // Avanzar mas alla del boundary
      nPos += Len( cDelim )

      // Fin del multipart: "--" tras el boundary

      IF SubStr( cBody, nPos, 2 ) == "--"

         EXIT

      ENDIF

      // Saltar CRLF obligatorio tras boundary

      IF SubStr( cBody, nPos, 2 ) == Chr( 13 ) + Chr( 10 )

         nPos += 2

      ENDIF

      // Localizar el siguiente boundary
      nNext := _HixMpNextBoundary( cBody, cDelim, nPos )

      IF nNext == 0

         EXIT

      ENDIF

      // Extraer la parte (sin el CRLF previo al boundary)
      nSkip := 0

      IF SubStr( cBody, nNext - 2, 2 ) == Chr( 13 ) + Chr( 10 )

         nSkip := 2

      ENDIF

      cPart := SubStr( cBody, nPos, nNext - nPos - nSkip )

      hPart := _HixMpParsePart( cPart )

      IF hPart != NIL

         AAdd( aParts, hPart )

      ENDIF

      nPos := nNext

   ENDDO

   ld( "Multipart: " + hb_NToS( Len( aParts ) ) + " partes" )

RETURN aParts

// ============================================================
// Parsear una parte individual: cabeceras + cuerpo
// ============================================================
STATIC FUNCTION _HixMpParsePart( cPart )

   LOCAL hPart
   LOCAL nSep, cHeaders, cBody
   LOCAL aLines, cLine, nPos, cKey, cVal
   LOCAL cName, cFilename, cMime

   // Separar cabeceras del cuerpo por doble CRLF
   nSep := At( Chr( 13 ) + Chr( 10 ) + Chr( 13 ) + Chr( 10 ), cPart )

   IF nSep == 0

      RETURN NIL

   ENDIF

   cHeaders := Left( cPart, nSep - 1 )
   cBody    := SubStr( cPart, nSep + 4 )

   cName     := ""
   cFilename := ""
   cMime     := "text/plain"

   aLines := hb_ATokens( cHeaders, Chr( 10 ) )

   FOR EACH cLine IN aLines

      cLine := AllTrim( StrTran( cLine, Chr( 13 ), "" ) )
      nPos  := At( ":", cLine )

      IF nPos > 0

         cKey := Lower( AllTrim( Left( cLine, nPos - 1 ) ) )
         cVal := AllTrim( SubStr( cLine, nPos + 1 ) )

         DO CASE

            CASE cKey == "content-disposition"
               cName     := _HixMpParam( cVal, "name" )
               cFilename := _HixMpParam( cVal, "filename" )
            CASE cKey == "content-type"
               cMime := AllTrim( cVal )

         ENDCASE

      ENDIF

   NEXT

   IF Empty( cName )

      RETURN NIL

   ENDIF

   hPart := { => }
   hPart[ "name"     ] := cName
   hPart[ "filename" ] := cFilename
   hPart[ "mime"     ] := cMime
   hPart[ "data"     ] := cBody
   hPart[ "size"     ] := Len( cBody )

RETURN hPart

// ============================================================
// Extraer valor de parametro: name="valor" o filename="valor"
// Soporta valores sin comillas (raro pero posible)
// ============================================================
STATIC FUNCTION _HixMpParam( cDisp, cParam )

   LOCAL nPos, cRest, nEnd

   // Buscar param="
   nPos := At( Lower( cParam ) + '="', Lower( cDisp ) )

   IF nPos > 0

      nPos  += Len( cParam ) + 2
      cRest := SubStr( cDisp, nPos )
      nEnd  := At( '"', cRest )

      IF nEnd > 0

         RETURN Left( cRest, nEnd - 1 )

      ENDIF

      RETURN AllTrim( cRest )

   ENDIF

   // Buscar param= (sin comillas)
   nPos := At( Lower( cParam ) + "=", Lower( cDisp ) )

   IF nPos > 0

      nPos  += Len( cParam ) + 1
      cRest := SubStr( cDisp, nPos )
      nEnd  := At( ";", cRest )

      IF nEnd > 0

         RETURN AllTrim( Left( cRest, nEnd - 1 ) )

      ENDIF

      RETURN AllTrim( cRest )

   ENDIF

RETURN ""

// ============================================================
// Localizar el siguiente boundary en cBody desde nStart
// Retorna la posicion del "--boundary" o 0 si no existe
// ============================================================
STATIC FUNCTION _HixMpNextBoundary( cBody, cDelim, nStart )

   LOCAL cSub, nRel

   IF nStart > Len( cBody )

      RETURN 0

   ENDIF

   cSub := SubStr( cBody, nStart )
   nRel := At( cDelim, cSub )

   IF nRel == 0

      RETURN 0

   ENDIF

RETURN nStart + nRel - 1
