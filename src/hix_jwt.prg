/*-----------------------------------------------------------
  File ......: hix_jwt.prg
  Author.....: Charly 9000
  Created....: 2026-07-14
  Modified...: 2026-07-14
  Version....: 1.0.0
  Description: JWT HS256 engine — token encode/validate and shared
               config (signing key + default expiry). Pure functions,
               no router or middleware dependencies.
  Usage      : HIX_MwJwtSetup( "my-secret", 3600 )
               cToken := HIX_JwtEncode( { "user_id" => "42" } )
               hPayload := HIX_JwtValidate( cToken )
  Notes      : The MW layer (src/mw/hix_mw_jwt.prg) consumes this
               engine. Getters HIX_JwtDefaultKey/Exp expose the
               STATIC config to callers outside this file.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_APP

#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_nJwtExpSec := 3600

// ============================================================
// HIX_MwJwtSetup — set signing key and default expiry seconds.
// Call before oSrv:Start(). Key goes through the shared HIX_Keys
// store ("jwt") so any deployment style (hixstyle / standalone)
// can override it.
// ============================================================
PROCEDURE HIX_MwJwtSetup( cKey, nExpSecs )

   IF ValType( cKey     ) == "C" .AND. ! Empty( cKey     ) ; HIX_KeySet( "jwt", cKey ) ; ENDIF

   IF ValType( nExpSecs ) == "N" .AND. nExpSecs > 0        ; s_nJwtExpSec := nExpSecs  ; ENDIF

RETURN

// ============================================================
// HIX_JwtDefaultKey / HIX_JwtDefaultExp — used by the MW layer.
// Key is delegated to the shared store; expiry stays module-local.
// ============================================================
FUNCTION HIX_JwtDefaultKey()
RETURN HIX_KeyGet( "jwt", "H!x@JWT@2026" )

FUNCTION HIX_JwtDefaultExp()
RETURN s_nJwtExpSec

// ============================================================
// HIX_MwJwtConfig -- returns current JWT configuration hash.
// Used by tests and diagnostics.
// ============================================================
FUNCTION HIX_MwJwtConfig()
RETURN { ;
   "exp" => s_nJwtExpSec, ;
   "key" => HIX_JwtDefaultKey() }

// ============================================================
// HIX_JwtEncode — builds a signed JWT from a data hash.
// hData   : payload fields (will be merged with iss/iat/exp)
// cKey    : signing key (default: global key from Setup)
// nExpSecs: expiry in seconds (default: global from Setup)
// ============================================================
FUNCTION HIX_JwtEncode( hData, cKey, nExpSecs )

   LOCAL cHeader, cPayload, cSign, nNow, hPayload

   hb_default( @cKey,     HIX_JwtDefaultKey() )
   hb_default( @nExpSecs, s_nJwtExpSec        )

   nNow    := Int( hb_TToSec( hb_DateTime() ) )
   cHeader := _HixB64Url( hb_jsonEncode( { "typ" => "JWT", "alg" => "HS256" } ) )

   hPayload        := iif( ValType( hData ) == "H", hb_HClone( hData ), { => } )
   hPayload[ "iss" ] := "HIX"
   hPayload[ "iat" ] := nNow
   hPayload[ "exp" ] := iif( nExpSecs > 0, nNow + nExpSecs, nNow - 1 )

   cPayload := _HixB64Url( hb_jsonEncode( hPayload ) )
   cSign    := _HixJwtSign( cHeader, cPayload, cKey )

RETURN cHeader + "." + cPayload + "." + cSign

// ============================================================
// HIX_JwtValidate — parses and verifies a JWT string.
// Returns the payload hash on success, NIL if invalid/expired.
// ============================================================
FUNCTION HIX_JwtValidate( cToken, cKey )

   LOCAL aPartes, cHeader, cPayload, cSign, cNewSign
   LOCAL hPayload, nExp

   hb_default( @cKey, HIX_JwtDefaultKey() )

   IF ValType( cToken ) <> "C" .OR. Empty( cToken )

      RETURN NIL

   ENDIF

   aPartes := hb_ATokens( cToken, "." )

   IF Len( aPartes ) <> 3

      RETURN NIL

   ENDIF

   cHeader  := aPartes[ 1 ]
   cPayload := aPartes[ 2 ]
   cSign    := aPartes[ 3 ]

   cNewSign := _HixJwtSign( cHeader, cPayload, cKey )

   IF cSign <> cNewSign

      RETURN NIL

   ENDIF

   hPayload := hb_jsonDecode( _HixB64UrlDecode( cPayload ) )

   IF ValType( hPayload ) <> "H"

      RETURN NIL

   ENDIF

   nExp := hb_HGetDef( hPayload, "exp", 0 )

   IF nExp > 0 .AND. Int( hb_TToSec( hb_DateTime() ) ) > nExp

      RETURN NIL

   ENDIF

RETURN hPayload

// ---- private helpers ----

STATIC FUNCTION _HixB64Url( cStr )

   LOCAL c := hb_base64Encode( cStr )

RETURN hb_StrReplace( c, "+/=", { "-", "_", "" } )

STATIC FUNCTION _HixB64UrlDecode( cStr )

   LOCAL c := hb_StrReplace( cStr, "-_", "+/" )

   DO CASE

      CASE Len( c ) % 4 == 2 ; c += "=="
      CASE Len( c ) % 4 == 3 ; c += "="

   ENDCASE

RETURN hb_base64Decode( c )

STATIC FUNCTION _HixJwtSign( cHeader, cPayload, cKey )

   LOCAL cHex, cRaw, nX, nN

   cHex := Upper( hb_HMAC_SHA256( cHeader + "." + cPayload, cKey ) )
   cRaw := ""

   FOR nX := 1 TO Len( cHex ) STEP 2

      nN   := ( At( SubStr( cHex, nX, 1 ), "0123456789ABCDEF" ) - 1 ) * 16
      nN   += At( SubStr( cHex, nX + 1, 1 ), "0123456789ABCDEF" ) - 1
      cRaw += Chr( nN )

   NEXT

RETURN _HixB64Url( cRaw )
