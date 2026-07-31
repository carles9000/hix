/*-----------------------------------------------------------
  File ......: hix_val_helpers.prg
  Author.....: Charly 9000
  Created....: 2026-05-26
  Modified...: 2026-07-23
  Version....: 3.0.0
  Description: U* helper functions for HIX Validator
  Usage      : UValidatePost(), UValidateGet(), UValidateJson(),
               UValidateOrFail(), UValidateParams() (alias UValidateGet)
               UIsMail(), UIsNumeric(), UIsUrl(), UIsIp(), UIsInteger()
  Notes      : All helpers merge route params (:vars) into hInput after
               the primary source. A key present in both throws 500.
               UValidateParams is kept as an alias for UValidateGet.
               UValidateOrFail() runs Make(), sends 422 and returns NIL on failure.
 -----------------------------------------------------------*/

// UValidatePost: POST body (form-urlencoded or JSON, auto-detected) + route params
FUNCTION UValidatePost( hRules, hSanitate )

   LOCAL hData := _HixValBuildInput( "post" )
   LOCAL oVal  := THixValidator():New( hRules, hSanitate, HIX_GetRequest() )

   oVal:hInput := hData

RETURN oVal

// UValidateGet: query string + route params
FUNCTION UValidateGet( hRules, hSanitate )

   LOCAL hData := _HixValBuildInput( "get" )
   LOCAL oVal  := THixValidator():New( hRules, hSanitate, HIX_GetRequest() )

   oVal:hInput := hData

RETURN oVal

// UValidateParams: alias for UValidateGet (backward compatibility)
FUNCTION UValidateParams( hRules, hSanitate )
RETURN UValidateGet( hRules, hSanitate )

// UValidateJson: JSON body + route params
FUNCTION UValidateJson( hRules, hSanitate )

   LOCAL hData := _HixValBuildInput( "json" )
   LOCAL oVal  := THixValidator():New( hRules, hSanitate, HIX_GetRequest() )

   oVal:hInput := hData

RETURN oVal

// UValidateOrFail: runs Make() — on fail sends 422 and returns NIL
FUNCTION UValidateOrFail( hRules, hSanitate )

   LOCAL hData := _HixValBuildInput( "post" )
   LOCAL oVal  := THixValidator():New( hRules, hSanitate, HIX_GetRequest() )

   oVal:hInput := hData

   IF ! oVal:Make()

      oVal:SendErrors( 422 )
      RETURN NIL

   ENDIF

RETURN oVal


// --- standalone predicate helpers ---

FUNCTION UIsMail( cStr )

   LOCAL n := At( "@", cStr )

RETURN n > 1 .AND. n < Len( cStr ) .AND. "." $ SubStr( cStr, n )

FUNCTION UIsNumeric( uValue )

   IF ValType( uValue ) == "N" ; RETURN .T. ; ENDIF

   IF ValType( uValue ) == "C"

      RETURN Val( AllTrim( StrTran( uValue, ",", "." ) ) ) != 0 .OR. AllTrim( uValue ) == "0"

   ENDIF

RETURN .F.

FUNCTION UIsUrl( cStr )

   LOCAL cLow := Lower( AllTrim( cStr ) )

RETURN Left( cLow, 7 ) == "http://" .OR. Left( cLow, 8 ) == "https://"

FUNCTION UIsIp( cStr )

   LOCAL aP := hb_ATokens( AllTrim( cStr ), "." )
   LOCAL i, n

   IF Len( aP ) != 4 ; RETURN .F. ; ENDIF

   FOR i := 1 TO 4

      IF ! UIsInteger( aP[ i ] ) ; RETURN .F. ; ENDIF

      n := Val( aP[ i ] )

      IF n < 0 .OR. n > 255 ; RETURN .F. ; ENDIF

   NEXT

RETURN .T.

FUNCTION UIsInteger( uValue )

   LOCAL n

   IF ValType( uValue ) == "N" ; RETURN ( Int( uValue ) == uValue ) ; ENDIF

   IF ValType( uValue ) == "C"

      n := Val( AllTrim( uValue ) )
      RETURN ( Int( n ) == n ) .AND. ;
         ( UStr( Int( n ) ) == AllTrim( uValue ) .OR. AllTrim( uValue ) == "0" )

   ENDIF

RETURN .F.


// --- private ---

STATIC FUNCTION _HixValBuildInput( cSource )

   LOCAL oReq  := HIX_GetRequest()
   LOCAL hData := { => }
   LOCAL hTmp, cKey

   IF oReq == NIL ; RETURN hData ; ENDIF

   DO CASE

      CASE cSource == "get"
         hData := oReq:QueryParamsAll()

      CASE cSource == "json"
         hTmp := oReq:JsonBody()

         IF ValType( hTmp ) == "H"
            hData := hb_HClone( hTmp )
         ENDIF

      OTHERWISE  // post — form-urlencoded or JSON body (auto-detect, no CT required)
         hTmp := oReq:FormBody()

         IF ValType( hTmp ) != "H" .OR. Len( hTmp ) == 0
            hTmp := oReq:JsonBody()
         ENDIF

         IF ValType( hTmp ) == "H"
            hData := hb_HClone( hTmp )
         ENDIF

   ENDCASE

   // Merge route params (:vars) — added after primary source; collision throws 500.
   FOR EACH cKey IN hb_HKeys( oReq:hParam )

      IF hb_HHasKey( hData, cKey )
         HIX_Throw( HIX_NewError( "Key collision '" + cKey + "': exists in both input and route params", "Validator", 500, "_HixValBuildInput" ) )
      ENDIF

      hData[ cKey ] := oReq:hParam[ cKey ]

   NEXT

RETURN hData
