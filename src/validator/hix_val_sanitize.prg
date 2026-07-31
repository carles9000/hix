/*-----------------------------------------------------------
  File ......: hix_val_sanitize.prg
  Author.....: Charly 9000
  Created....: 2026-05-26
  Modified...: 2026-05-26
  Version....: 1.0.0
  Description: Sanitization rules for HIX Validator
  Usage      : HIX_ValSanitize( cFormat, uValue ) -> sanitized value
  Notes      : Called in Phase 3 (sanitize) of THixValidator:EvalValue()
 -----------------------------------------------------------*/

// HIX_ValSanitize: applies a sanitization transform to uValue.
// Returns the (possibly modified) value.
FUNCTION HIX_ValSanitize( cFormat, uValue )

   LOCAL cLow   := Lower( AllTrim( cFormat ) )
   LOCAL cVal
   LOCAL nDec, cInt, cFrac

   IF ValType( uValue ) == "C"

      cVal := uValue
   ELSE
      cVal := UStr( uValue )

   ENDIF

   DO CASE

      CASE cLow == "upper"
         RETURN Upper( cVal )

      CASE cLow == "lower"
         RETURN Lower( cVal )

      CASE cLow == "trim"
         RETURN AllTrim( cVal )

      CASE cLow == "ltrim"
         RETURN LTrim( cVal )

      CASE cLow == "rtrim"
         RETURN RTrim( cVal )

      CASE cLow == "strip_tags"
         RETURN _ValStripTags( cVal )

      CASE cLow == "slug"
         RETURN _ValSlug( cVal )

      CASE cLow == "nl2br"
         RETURN StrTran( StrTran( cVal, Chr( 13 ) + Chr( 10 ), "<br>" ), Chr( 10 ), "<br>" )

      CASE cLow == "escape"
         RETURN UHtmlEncode( cVal )

      CASE cLow == "abs"

      IF ValType( uValue ) == "N"

         RETURN Abs( uValue )

         ENDIF

         RETURN uValue

      CASE Left( cLow, 6 ) == "round:"

      IF ValType( uValue ) == "N"

         nDec := Val( SubStr( cFormat, 7 ) )
         RETURN Round( uValue, nDec )

         ENDIF

         RETURN uValue

   ENDCASE

RETURN uValue


STATIC FUNCTION _ValStripTags( cStr )

   LOCAL cOut  := ""
   LOCAL lTag  := .F.
   LOCAL i, c

   FOR i := 1 TO Len( cStr )

      c := SubStr( cStr, i, 1 )

      IF c == "<"

         lTag := .T.
      ELSEIF c == ">"
         lTag := .F.
      ELSEIF ! lTag
         cOut += c

      ENDIF

   NEXT

RETURN cOut


STATIC FUNCTION _ValSlug( cStr )

   LOCAL cOut := Lower( AllTrim( cStr ) )
   LOCAL i, c, cNew := ""

   FOR i := 1 TO Len( cOut )

      c := SubStr( cOut, i, 1 )

      IF ( c >= "a" .AND. c <= "z" ) .OR. ( c >= "0" .AND. c <= "9" )

         cNew += c
      ELSEIF c == " " .OR. c == "_"
         cNew += "-"

      ENDIF

   NEXT

   // collapse multiple dashes

   DO WHILE "--" $ cNew

      cNew := StrTran( cNew, "--", "-" )

   ENDDO

RETURN AllTrim( cNew )
