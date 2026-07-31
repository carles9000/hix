/*-----------------------------------------------------------
  File ......: hix_validator.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-26
  Description: Core validator class THixValidator — validation, casting and
               sanitization pipeline for HTTP input.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#INCLUDE "hbclass.ch"
#INCLUDE "hix_const.ch"

CLASS THixValidator

   VAR hRules        // { "field" => "rule1|rule2|field" }
   VAR hSanitate     // { "field" => "lower|trim" }
   VAR hInput        // raw input hash (set via Make() or pre-stored)
   VAR hValidated    // cast + validated values
   VAR aErrors       // array of { "field", "message" }
   VAR hDataFields   // fields marked with "field"/"escapedfield" — only if Passes()
   VAR oReq          // THixRequest for SendErrors
   VAR xResume       // resume value: validated scalar (1 field) or hash (multi), NIL if fails

   METHOD New( hRules, hSanitate, oReq )
   METHOD Add( hRule, xValue )
   METHOD Make( hInput )
   METHOD MakeParameter( cKey, uValue )
   METHOD EvalValue( cKey, uValue, cName, aTokens )
   METHOD Formatter()

   // Status
   METHOD Passes()   INLINE ( Len( ::aErrors ) == 0 )
   METHOD Fails()    INLINE ( Len( ::aErrors ) > 0 )
   METHOD IsValid()  INLINE ( Len( ::aErrors ) == 0 )

   // Output
   METHOD GetErrors()
   METHOD GetFirstError()
   METHOD GetErrorsJson()
   METHOD GetErrorsTxt()
   METHOD GetErrorsHtml()
   METHOD SendErrors( nStatus )

   // Data access
   METHOD DataFields()
   METHOD Validated( aFields )
   METHOD Get( cKey, xDefault )
   METHOD Resume()

ENDCLASS


METHOD New( hRules, hSanitate, oReq ) CLASS THixValidator

   ::hRules      := hRules
   ::hSanitate   := hb_defaultValue( hSanitate, { => } )
   ::hInput      := { => }
   ::hValidated  := { => }
   ::aErrors     := {}
   ::hDataFields := { => }
   ::oReq        := oReq
   ::xResume     := NIL

RETURN Self


METHOD Add( hRule, xValue ) CLASS THixValidator

   LOCAL cKey := hb_HKeys( hRule )[ 1 ]

   hb_HMerge( ::hRules, hRule )
   ::hInput[ cKey ] := xValue

RETURN Self

METHOD Make( hInput ) CLASS THixValidator

   LOCAL cKey, xDef, cName, cRulesStr
   LOCAL uValue, aTokens, hMsg
   LOCAL hFieldMarkers  := { => }
   LOCAL hResumeMarkers := { => }
   LOCAL cSanTokens, aSanParts, i, xSanVal

   // Accept input from param or use stored ::hInput

   IF hInput != NIL

      ::hInput := hInput

   ENDIF

   ::hValidated  := { => }
   hb_HCaseMatch( ::hValidated, .F. )
   ::aErrors     := {}
   ::hDataFields := { => }
   ::xResume     := NIL

   // Phase 1+2: cast + validate

   FOR EACH cKey IN hb_HKeys( ::hRules )

      xDef      := NIL
      cName     := cKey
      cRulesStr := ::hRules[ cKey ]

      IF ValType( cRulesStr ) == "A"

         IF Len( cRulesStr ) >= 2 .AND. ! Empty( cRulesStr[ 2 ] ) ; cName := cRulesStr[ 2 ] ; ENDIF

         IF Len( cRulesStr ) >= 3 ; xDef := cRulesStr[ 3 ] ; ENDIF

         cRulesStr := cRulesStr[ 1 ]

      ENDIF

      uValue := hb_HGetDef( ::hInput, cKey, xDef )

      IF ValType( cRulesStr ) == "C"

         aTokens := hb_ATokens( cRulesStr, "|" )
      ELSE
         aTokens := { cRulesStr }

      ENDIF

      // Register field/escapedfield/resume as metadata (do not skip validation)
      _ValScanFieldMarker( aTokens, cKey, hFieldMarkers )
      _ValScanResumeMarker( aTokens, cKey, hResumeMarkers )

      hMsg := ::EvalValue( cKey, @uValue, cName, aTokens )

      ::hValidated[ cKey ] := uValue   // always store so Validated() never has missing keys

      IF ValType( hMsg ) == "H" .AND. hb_HGetDef( hMsg, "skip", .F. )

         LOOP

      ENDIF

      IF ValType( hMsg ) == "H" .AND. hb_HHasKey( hMsg, "field" )

         AAdd( ::aErrors, hMsg )

      ENDIF

   NEXT

   // Phase 3: sanitize + DataFields — only when all validations passed

   IF Len( ::aErrors ) == 0

      // Apply hSanitate transforms (supports "lower|trim" per field)

      FOR EACH cKey IN hb_HKeys( ::hSanitate )

         IF hb_HHasKey( ::hValidated, cKey )

            xSanVal := ::hValidated[ cKey ]
         ELSEIF hb_HHasKey( ::hInput, cKey )
            xSanVal := ::hInput[ cKey ]
         ELSE
            LOOP

         ENDIF

         cSanTokens := ::hSanitate[ cKey ]
         aSanParts  := hb_ATokens( cSanTokens, "|" )

         FOR i := 1 TO Len( aSanParts )

            xSanVal := HIX_ValSanitize( AllTrim( aSanParts[ i ] ), xSanVal )

         NEXT

         ::hValidated[ cKey ] := xSanVal

      NEXT

      // Build hDataFields from markers using post-sanitize values

      FOR EACH cKey IN hb_HKeys( hFieldMarkers )

         IF hFieldMarkers[ cKey ] == "escapedfield"

            ::hDataFields[ cKey ] := UHtmlEncode( UStr( ::hValidated[ cKey ] ) )
         ELSE
            ::hDataFields[ cKey ] := ::hValidated[ cKey ]

         ENDIF

      NEXT

   ENDIF

   // resume markers: build hash (hInput + cast values). Without markers,
   // Resume() falls back to ::hInput via the iif in the method declaration.

   IF Len( hResumeMarkers ) > 0

      ::xResume := hb_HClone( ::hInput )

      FOR EACH cKey IN hb_HKeys( hResumeMarkers )

         IF hb_HHasKey( ::hValidated, cKey )

            ::xResume[ cKey ] := ::hValidated[ cKey ]

         ENDIF

      NEXT

   ENDIF

RETURN ( Len( ::aErrors ) == 0 )


METHOD Resume() CLASS THixValidator

   IF ::xResume != NIL

      RETURN ::xResume

   ENDIF

RETURN ::hInput


METHOD MakeParameter( cKey, uValue ) CLASS THixValidator

   LOCAL cName, cRulesStr, aTokens, hMsg

   cName     := cKey
   cRulesStr := hb_HGetDef( ::hRules, cKey, "" )

   IF ValType( cRulesStr ) == "A"

      IF Len( cRulesStr ) >= 2 .AND. ! Empty( cRulesStr[ 2 ] ) ; cName := cRulesStr[ 2 ] ; ENDIF

      cRulesStr := cRulesStr[ 1 ]

   ENDIF

   aTokens := hb_ATokens( cRulesStr, "|" )
   hMsg    := ::EvalValue( cKey, @uValue, cName, aTokens )

   IF ValType( hMsg ) == "H" .AND. hb_HGetDef( hMsg, "skip", .F. )

      RETURN .T.

   ENDIF

   IF ValType( hMsg ) == "H" .AND. hb_HHasKey( hMsg, "field" )

      AAdd( ::aErrors, hMsg )
      RETURN .F.

   ENDIF

   ::hValidated[ cKey ] := uValue

RETURN .T.


METHOD EvalValue( cKey, uValue, cName, aTokens ) CLASS THixValidator

   LOCAL cToken, cLow, hResult, xCast, i
   LOCAL aTokensOrig := AClone( aTokens )

   // Phase 1: cast

   FOR i := 1 TO Len( aTokens )

      cToken := AllTrim( UStr( aTokens[ i ] ) )

      xCast := HIX_ValCast( cToken, @uValue, cKey, cName )

      IF ValType( xCast ) == "H"
         RETURN xCast        // cast format error (e.g. "abc" for a number field)
      ELSEIF xCast == .T.
         aTokens[ i ] := ""  // token consumed by cast
      ENDIF

   NEXT

   // Between phases: if field is optional and value is empty after cast, skip validation
   IF ( uValue == NIL .OR. ( ValType( uValue ) == "C" .AND. Empty( uValue ) ) )
      IF AScan( aTokens, {| t | Lower( AllTrim( UStr( t ) ) ) == "required" } ) == 0
         RETURN NIL
      ENDIF
   ENDIF

   // Phase 2: validate

   FOR i := 1 TO Len( aTokens )

      // Codeblock rule

      IF ValType( aTokensOrig[ i ] ) == "B"

         hResult := _ValEvalCodeblock( aTokensOrig[ i ], uValue, cKey, cName )

         IF ValType( hResult ) == "H"

            RETURN hResult

         ENDIF

         LOOP

      ENDIF

      cToken := AllTrim( UStr( aTokens[ i ] ) )

      IF Empty( cToken ) ; LOOP ; ENDIF

      cLow := Lower( cToken )

      // Skip non-validation tokens

      IF _ValIsSanitizeToken( cLow ) .OR. _ValIsFieldMarkerToken( cLow ) ; LOOP ; ENDIF

      hResult := HIX_ValCheck( aTokensOrig[ i ], uValue, cKey, cName, ::hInput )

      IF hResult != NIL

         RETURN hResult

      ENDIF

   NEXT

RETURN NIL


METHOD GetErrors() CLASS THixValidator

   LOCAL hOut := { => }
   LOCAL aE

   FOR EACH aE IN ::aErrors

      hOut[ aE[ "field" ] ] := aE[ "message" ]

   NEXT

RETURN hOut


METHOD GetFirstError() CLASS THixValidator

   IF Len( ::aErrors ) == 0 ; RETURN "" ; ENDIF

RETURN ::aErrors[ 1 ][ "message" ]


METHOD GetErrorsJson() CLASS THixValidator
RETURN hb_jsonEncode( ::GetErrors() )


METHOD GetErrorsTxt() CLASS THixValidator

   LOCAL cOut := ""
   LOCAL aE
   LOCAL i := 0

   FOR EACH aE IN ::aErrors

      i++

      IF i > 1 ; cOut += hb_eol() ; ENDIF

      cOut += aE[ "field" ] + ": " + aE[ "message" ]

   NEXT

RETURN cOut


METHOD GetErrorsHtml() CLASS THixValidator

   LOCAL cHtml := "<table class='hix-errors'>" + hb_eol()
   LOCAL aE

   FOR EACH aE IN ::aErrors

      cHtml += "  <tr><td class='field'>" + aE[ "field" ] + "</td>" + ;
         "<td class='msg'>" + aE[ "message" ] + "</td></tr>" + hb_eol()

   NEXT

   cHtml += "</table>"

RETURN cHtml


METHOD Formatter() CLASS THixValidator

   LOCAL hOut := { => }

   hOut[ "success" ] := ( Len( ::aErrors ) == 0 )
   hOut[ "errors"  ] := ::GetErrors()

RETURN hOut


METHOD SendErrors( nStatus ) CLASS THixValidator

   LOCAL hOut, oReq

   hb_default( @nStatus, 422 )

   hOut := { "success" => .F., "errors" => ::GetErrors() }
   oReq := ::oReq

   IF oReq == NIL

      oReq := HIX_GetRequest()

   ENDIF

   IF oReq != NIL

      oReq:Respond( hb_jsonEncode( hOut ), nStatus, "application/json" )

   ENDIF

RETURN NIL


METHOD DataFields() CLASS THixValidator
RETURN ::hDataFields


METHOD Validated( aFields ) CLASS THixValidator

   LOCAL hOut := { => }
   LOCAL cKey

   IF aFields == NIL

      RETURN hb_HClone( ::hValidated )

   ENDIF

   FOR EACH cKey IN aFields

      IF hb_HHasKey( ::hValidated, cKey )

         hOut[ cKey ] := ::hValidated[ cKey ]

      ENDIF

   NEXT

RETURN hOut


METHOD Get( cKey, xDefault ) CLASS THixValidator

   hb_default( @xDefault, NIL )

   IF cKey == NIL .OR. Empty( cKey )

      RETURN iif( ! Empty( ::hValidated ), ::hValidated[ hb_HKeys( ::hValidated )[ 1 ] ], xDefault )

   ENDIF

RETURN hb_HGetDef( ::hValidated, cKey, xDefault )


FUNCTION UValidator( hRules, hSanitate, oReq )
RETURN THixValidator():New( hRules, hSanitate, oReq )

FUNCTION UValidatorOne( cLabel, xValue, xRules )

   LOCAL cKey, aRule, oVal

   hb_default( @cLabel, "value" )
   cKey  := Lower( cLabel )
   aRule := { xRules, cLabel, "" }
   oVal  := UValidator( { cKey => aRule } )
   oVal:Make( { cKey => xValue } )

RETURN oVal


// --- private helpers ---

STATIC FUNCTION _ValIsSanitizeToken( cLow )

   LOCAL aS := { "upper", "lower", "trim", "ltrim", "rtrim", "strip_tags", ;
      "slug", "nl2br", "escape", "abs" }

RETURN AScan( aS, {| s | s == cLow } ) > 0 .OR. Left( cLow, 6 ) == "round:"


STATIC FUNCTION _ValIsFieldMarkerToken( cLow )
RETURN cLow == "field" .OR. cLow == "escapedfield" .OR. cLow == "resume"


STATIC FUNCTION _ValScanFieldMarker( aTokens, cKey, hFieldMarkers )

   LOCAL cLow, i

   FOR i := 1 TO Len( aTokens )

      cLow := Lower( AllTrim( UStr( aTokens[ i ] ) ) )

      IF cLow == "field" .OR. cLow == "escapedfield"

         hFieldMarkers[ cKey ] := cLow

      ENDIF

   NEXT

RETURN NIL


STATIC FUNCTION _ValScanResumeMarker( aTokens, cKey, hResumeMarkers )

   LOCAL cLow, i

   FOR i := 1 TO Len( aTokens )

      cLow := Lower( AllTrim( UStr( aTokens[ i ] ) ) )

      IF cLow == "resume"

         hResumeMarkers[ cKey ] := .T.

      ENDIF

   NEXT

RETURN NIL


STATIC FUNCTION _ValEvalCodeblock( bRule, uValue, cKey, cName )

   LOCAL xResult

   TRY

      xResult := Eval( bRule, uValue )
   CATCH
      RETURN { "field" => cKey, "message" => _( 'VAL_CODEBLOCK_ERR', cName ) }

   END

   IF ValType( xResult ) == "L" .AND. ! xResult

      RETURN { "field" => cKey, "message" => _( 'VAL_CODEBLOCK_ERR', cName ) }

   ENDIF

   IF ValType( xResult ) == "C" .AND. ! Empty( xResult )

      RETURN { "field" => cKey, "message" => xResult }

   ENDIF

RETURN NIL
