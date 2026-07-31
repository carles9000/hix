/*-----------------------------------------------------------
  File ......: hix_val_rules.prg
  Author.....: Charly 9000
  Created....: 2026-05-26
  Modified...: 2026-05-26
  Version....: 1.0.0
  Description: Validation rules for HIX Validator
  Usage      : HIX_ValCheck( cRole, uValue, cKey, cName, hInput ) -> NIL | error hash
  Notes      : Returns NIL on pass, { "field","message" } on fail,
               { "skip"=>.T. } when optional sentinel fires.
               cRole is the ORIGINAL-case rule token (regex pattern preserved).
               cKey/cName/hInput needed for cross-field rules (confirmed).
 -----------------------------------------------------------*/

// HIX_ValCheck: evaluates a single rule against uValue.
// Returns NIL on pass, error hash on fail, skip hash when optional.
FUNCTION HIX_ValCheck( cRole, uValue, cKey, cName, hInput )

   LOCAL cLow    := Lower( AllTrim( cRole ) )
   LOCAL cParam  := ""
   LOCAL nColon  := At( ":", cLow )
   LOCAL cBase, aParams, nVal, cOther, dVal, dParam

   IF nColon > 0

      cBase  := Left( cLow, nColon - 1 )
      cParam := SubStr( cRole, nColon + 1 )   // original case for regex
   ELSE
      cBase  := cLow

   ENDIF

   DO CASE

         // --- sentinel: stop validation for this field without error ---
      CASE cBase == "optional"

      IF Empty( uValue ) .OR. ( ValType( uValue ) == "C" .AND. Empty( AllTrim( uValue ) ) )

         RETURN { "skip" => .T. }

         ENDIF

         RETURN NIL

         // --- required ---
      CASE cBase == "required"

      IF _ValIsEmpty( uValue )

         RETURN _ValErr( cKey, _( 'VAL_REQUIRED', cName ) )

         ENDIF

         RETURN NIL

         // --- numeric ---
      CASE cBase == "isnumeric" .OR. cBase == "numeric" .OR. cBase == "decimal"

      IF ! _ValIsNumeric( uValue )

         RETURN _ValErr( cKey, _( 'VAL_ISNUMERIC', cName ) )

         ENDIF

         RETURN NIL

         // --- integer ---
      CASE cBase == "integer" .OR. cBase == "isinteger"

      IF ! _ValIsInteger( uValue )

         RETURN _ValErr( cKey, _( 'VAL_INTEGER', cName ) )

         ENDIF

         RETURN NIL

         // --- positive ---
      CASE cBase == "positive"

      IF ValType( uValue ) != "N" .OR. uValue <= 0

         RETURN _ValErr( cKey, _( 'VAL_POSITIVE', cName ) )

         ENDIF

         RETURN NIL

         // --- min:N ---
      CASE cBase == "min"
         nVal := Val( cParam )

      IF ValType( uValue ) == "N"

         IF uValue < nVal

            RETURN _ValErr( cKey, _( 'VAL_MIN_NUM', cName, hb_NToS( nVal ) ) )

         ENDIF

      ELSE

         IF Len( UStr( uValue ) ) < nVal

            RETURN _ValErr( cKey, _( 'VAL_MIN_STR', cName, hb_NToS( Int( nVal ) ) ) )

         ENDIF

         ENDIF

         RETURN NIL

         // --- max:N ---
      CASE cBase == "max"
         nVal := Val( cParam )

      IF ValType( uValue ) == "N"

         IF uValue > nVal

            RETURN _ValErr( cKey, _( 'VAL_MAX_NUM', cName, hb_NToS( nVal ) ) )

         ENDIF

      ELSE

         IF Len( UStr( uValue ) ) > nVal

            RETURN _ValErr( cKey, _( 'VAL_MAX_STR', cName, hb_NToS( Int( nVal ) ) ) )

         ENDIF

         ENDIF

         RETURN NIL

         // --- minlen:N / maxlen:N --- (string length, independent of type)
      CASE cBase == "minlen"
         nVal := Val( cParam )

      IF Len( UStr( uValue ) ) < nVal

         RETURN _ValErr( cKey, _( 'VAL_MIN_STR', cName, hb_NToS( Int( nVal ) ) ) )

         ENDIF

         RETURN NIL

      CASE cBase == "maxlen"
         nVal := Val( cParam )

      IF Len( UStr( uValue ) ) > nVal

         RETURN _ValErr( cKey, _( 'VAL_MAX_STR', cName, hb_NToS( Int( nVal ) ) ) )

         ENDIF

         RETURN NIL

         // --- between:N,M ---
      CASE cBase == "between"
         aParams := hb_ATokens( cParam, "," )

      IF Len( aParams ) >= 2

         IF ValType( uValue ) == "N"

            IF uValue < Val( aParams[ 1 ] ) .OR. uValue > Val( aParams[ 2 ] )

               RETURN _ValErr( cKey, _( 'VAL_BETWEEN', cName, aParams[ 1 ], aParams[ 2 ] ) )

            ENDIF

         ELSE
            nVal := Len( UStr( uValue ) )

            IF nVal < Val( aParams[ 1 ] ) .OR. nVal > Val( aParams[ 2 ] )

               RETURN _ValErr( cKey, _( 'VAL_BETWEEN', cName, aParams[ 1 ], aParams[ 2 ] ) )

            ENDIF

         ENDIF

         ENDIF

         RETURN NIL

         // --- in:a,b,c ---
      CASE cBase == "in"
         aParams := hb_ATokens( cParam, "," )

      IF AScan( aParams, {| s | s == UStr( uValue ) } ) == 0

         RETURN _ValErr( cKey, _( 'VAL_IN', cName ) )

         ENDIF

         RETURN NIL

         // --- notin:a,b,c ---
      CASE cBase == "notin"
         aParams := hb_ATokens( cParam, "," )

      IF AScan( aParams, {| s | s == UStr( uValue ) } ) > 0

         RETURN _ValErr( cKey, _( 'VAL_NOTIN', cName ) )

         ENDIF

         RETURN NIL

         // --- ismail ---
      CASE cBase == "ismail" .OR. cBase == "email"

      IF ! _ValIsMail( UStr( uValue ) )

         RETURN _ValErr( cKey, _( 'VAL_ISMAIL', cName ) )

         ENDIF

         RETURN NIL

         // --- isurl / url ---
      CASE cBase == "isurl" .OR. cBase == "url"

      IF ! _ValIsUrl( UStr( uValue ) )

         RETURN _ValErr( cKey, _( 'VAL_ISURL', cName ) )

         ENDIF

         RETURN NIL

         // --- isip / ip ---
      CASE cBase == "isip" .OR. cBase == "ip"

      IF ! _ValIsIp( UStr( uValue ) )

         RETURN _ValErr( cKey, _( 'VAL_ISIP', cName ) )

         ENDIF

         RETURN NIL

         // --- regex:pattern ---
      CASE cBase == "regex"

      IF ! Empty( cParam )

         IF Empty( hb_regex( cParam, UStr( uValue ) ) )

            RETURN _ValErr( cKey, _( 'VAL_REGEX', cName ) )

         ENDIF

         ENDIF

         RETURN NIL

         // --- mindate:YYYY-MM-DD ---
      CASE cBase == "mindate"
         dVal   := _ValParseDate( UStr( uValue ) )
         dParam := _ValParseDate( cParam )

      IF dVal != NIL .AND. dParam != NIL .AND. dVal < dParam

         RETURN _ValErr( cKey, _( 'VAL_MINDATE', cName, cParam ) )

         ENDIF

         RETURN NIL

         // --- maxdate:YYYY-MM-DD ---
      CASE cBase == "maxdate"
         dVal   := _ValParseDate( UStr( uValue ) )
         dParam := _ValParseDate( cParam )

      IF dVal != NIL .AND. dParam != NIL .AND. dVal > dParam

         RETURN _ValErr( cKey, _( 'VAL_MAXDATE', cName, cParam ) )

         ENDIF

         RETURN NIL

         // --- confirmed (field_confirmation must match) ---
      CASE cBase == "confirmed"
         cOther := hb_HGetDef( hInput, cKey + "_confirmation", NIL )

      IF cOther == NIL .OR. UStr( cOther ) != UStr( uValue )

         RETURN _ValErr( cKey, _( 'VAL_CONFIRMED', cName ) )

         ENDIF

         RETURN NIL

   ENDCASE

RETURN NIL


// --- private helpers ---

STATIC FUNCTION _ValErr( cKey, cMsg )
RETURN { "field" => cKey, "message" => cMsg }

STATIC FUNCTION _ValIsEmpty( uValue )

   IF uValue == NIL                                  ; RETURN .T. ; ENDIF

   IF ValType( uValue ) == "C" .AND. Empty( AllTrim( uValue ) ) ; RETURN .T. ; ENDIF

RETURN .F.

STATIC FUNCTION _ValIsNumeric( uValue )

   IF ValType( uValue ) == "N" ; RETURN .T. ; ENDIF

   IF ValType( uValue ) == "C"

      RETURN Val( AllTrim( StrTran( uValue, ",", "." ) ) ) != 0 .OR. AllTrim( uValue ) == "0"

   ENDIF

RETURN .F.

STATIC FUNCTION _ValIsInteger( uValue )

   LOCAL n

   IF ValType( uValue ) == "N" ; RETURN ( Int( uValue ) == uValue ) ; ENDIF

   IF ValType( uValue ) == "C"

      n := Val( AllTrim( uValue ) )
      RETURN ( Int( n ) == n ) .AND. ( UStr( Int( n ) ) == AllTrim( uValue ) .OR. AllTrim( uValue ) == "0" )

   ENDIF

RETURN .F.

STATIC FUNCTION _ValIsMail( cStr )

   LOCAL n := At( "@", cStr )

RETURN n > 1 .AND. n < Len( cStr ) .AND. "." $ SubStr( cStr, n )

STATIC FUNCTION _ValIsUrl( cStr )

   LOCAL cLow := Lower( AllTrim( cStr ) )

RETURN Left( cLow, 7 ) == "http://" .OR. Left( cLow, 8 ) == "https://"

STATIC FUNCTION _ValIsIp( cStr )

   LOCAL aP := hb_ATokens( AllTrim( cStr ), "." )
   LOCAL i, n

   IF Len( aP ) != 4 ; RETURN .F. ; ENDIF

   FOR i := 1 TO 4

      IF ! _ValIsInteger( aP[ i ] ) ; RETURN .F. ; ENDIF

      n := Val( aP[ i ] )

      IF n < 0 .OR. n > 255 ; RETURN .F. ; ENDIF

   NEXT

RETURN .T.

STATIC FUNCTION _ValParseDate( cStr )

   LOCAL aP, dRet

   aP := hb_ATokens( AllTrim( cStr ), "-" )

   IF Len( aP ) == 3

      dRet := hb_SToD( aP[ 1 ] + aP[ 2 ] + aP[ 3 ] )

      IF ! Empty( dRet ) ; RETURN dRet ; ENDIF

   ENDIF

RETURN NIL
