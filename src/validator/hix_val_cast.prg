/*-----------------------------------------------------------
  File ......: hix_val_cast.prg
  Author.....: Charly 9000
  Created....: 2026-05-26
  Modified...: 2026-05-26
  Version....: 1.0.0
  Description: Type casting rules for HIX Validator
  Usage      : HIX_ValCast( cRole, @uValue ) -> .T. if cast applied
  Notes      : Called in Phase 1 (cast) of THixValidator:EvalValue()
 -----------------------------------------------------------*/

// HIX_ValCast: applies type cast to uValue based on cRole.
// Returns .T.  when a cast rule matched (value may have changed).
// Returns .F.  when cRole is not a cast rule.
// Returns hash when a cast rule matched but the value format is invalid
//              (cKey/cName needed to build the error hash).
FUNCTION HIX_ValCast( cRole, uValue, cKey, cName )

   LOCAL cLow  := Lower( AllTrim( cRole ) )
   LOCAL nVal, cClean

   hb_default( @cKey,  "" )
   hb_default( @cName, cKey )

   DO CASE

      CASE cLow == "string"
         uValue := AllTrim( UStr( uValue ) )
         RETURN .T.

      CASE cLow == "number" .OR. cLow == "numeric" .OR. cLow == "decimal"

         IF ValType( uValue ) == "C"

            cClean := StrTran( AllTrim( uValue ), ",", "." )

            IF ! _IsNumericStr( cClean )
               RETURN { "field" => cKey, "message" => _( 'VAL_ISNUMERIC', cName ) }
            ENDIF

            nVal   := Val( cClean )
            uValue := nVal

         ENDIF

         RETURN .T.

      CASE cLow == "logic" .OR. cLow == "bool" .OR. cLow == "boolean"

      IF ValType( uValue ) == "C"

         DO CASE

            CASE Lower( AllTrim( uValue ) ) $ "1,true,yes,si,on,.t."  ; uValue := .T.
            CASE Lower( AllTrim( uValue ) ) $ "0,false,no,off,.f."    ; uValue := .F.
            OTHERWISE                                             ; uValue := .F.

         ENDCASE

      ELSEIF ValType( uValue ) == "N"
         uValue := ( uValue != 0 )
      ELSEIF ValType( uValue ) != "L"
         uValue := .F.   // NIL or unknown type (unchecked checkbox) → false

         ENDIF

         RETURN .T.

      CASE cLow == "date"

      IF ValType( uValue ) == "C" .AND. ! Empty( AllTrim( uValue ) )

         uValue := _CastDate( AllTrim( uValue ) )

         ENDIF

         RETURN .T.

   ENDCASE

RETURN .F.


// Validates that a string represents a valid number (integer or decimal, optional leading minus).
// "abc" -> .F.   "1abc" -> .F.   "25" -> .T.   "-3.14" -> .T.   "0" -> .T.
STATIC FUNCTION _IsNumericStr( cStr )

   LOCAL i, c
   LOCAL lDot      := .F.
   LOCAL lHasDigit := .F.

   IF Empty( cStr ) ; RETURN .F. ; ENDIF

   FOR i := 1 TO Len( cStr )
      c := SubStr( cStr, i, 1 )
      DO CASE
         CASE IsDigit( c )           ; lHasDigit := .T.   // 0-9
         CASE c == "." .AND. ! lDot ; lDot := .T.         // decimal point (once)
         CASE c == "-" .AND. i == 1 // leading minus allowed
         OTHERWISE                  ; RETURN .F.
      ENDCASE
   NEXT

RETURN lHasDigit


// Parses ISO "YYYY-MM-DD", "YYYY/MM/DD" or falls back to CToD() for system format
STATIC FUNCTION _CastDate( cDate )

   LOCAL cY, cM, cD

   IF Len( cDate ) == 10 .AND. ( SubStr( cDate, 5, 1 ) == "-" .OR. SubStr( cDate, 5, 1 ) == "/" )

      cY := Left( cDate, 4 )
      cM := SubStr( cDate, 6, 2 )
      cD := Right( cDate, 2 )
      RETURN hb_SToD( cY + cM + cD )

   ENDIF

RETURN CToD( cDate )
