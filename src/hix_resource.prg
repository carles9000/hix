/*-----------------------------------------------------------
  File ......: hix_resource.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-29
  Description: Resource ID signing helpers. Signs an opaque ID into an HMAC
               token for safe embedding in HTML forms and validates/extracts
               it on POST.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#INCLUDE "hix_const.ch"

// ============================================================
// _HixResourceSecret -- shared app_key (same as CSRF).
// ============================================================
STATIC FUNCTION _HixResourceSecret()
RETURN HIX_KeyGet( "resource", "H!x@RES@2026" )

// ============================================================
// HIX_ResourceHtml -- signs cId and returns a hidden input.
// ============================================================
FUNCTION HIX_ResourceHtml( cId )

   LOCAL cToken

   IF ValType( cId ) != "C"

      cId := hb_CStr( cId )

   ENDIF

   IF Empty( cId )

      RETURN "<!-- resource_id empty -->"

   ENDIF

   cToken := HIX_TokenMake( cId, _HixResourceSecret() )

RETURN '<input type="hidden" name="_resource_id" value="' + cToken + '">'

// ============================================================
// HIX_GetResource -- validates token and returns the original ID.
// If cToken is omitted, reads _resource_id from POST then GET.
// Returns "" on missing or invalid token.
// ============================================================
FUNCTION HIX_GetResource( cToken )

   LOCAL aParts, cPayload, aInfo, cId, i

   hb_default( @cToken, "" )

   IF Empty( cToken )

      cToken := UPost( "_resource_id", "" )

   ENDIF

   IF Empty( cToken )

      cToken := UGet( "_resource_id", "" )

   ENDIF

   IF Empty( cToken )

      RETURN ""

   ENDIF

   IF ! HIX_TokenValid( cToken, 0, _HixResourceSecret() )

      RETURN ""

   ENDIF

   aParts := hb_ATokens( cToken, "." )

   IF Len( aParts ) != 2

      RETURN ""

   ENDIF

   cPayload := hb_base64Decode( aParts[ 1 ] )
   aInfo    := hb_ATokens( cPayload, "|" )

   IF Len( aInfo ) < 2

      RETURN ""

   ENDIF

   // Reconstruct ID: all segments except the last (unix timestamp)
   cId := ""

   FOR i := 1 TO Len( aInfo ) - 1

      IF i > 1

         cId += "|"

      ENDIF

      cId += aInfo[ i ]

   NEXT

RETURN cId

// ============================================================
// Aliases — UResourceToHtml / UGetResource
// ============================================================
FUNCTION UResourceToHtml( cId )
RETURN HIX_ResourceHtml( cId )

FUNCTION UGetResource( cToken )
RETURN HIX_GetResource( cToken )
