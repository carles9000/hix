/*-----------------------------------------------------------
  File ......: hix_token.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-27
  Description: Generic HMAC-SHA256 signed token functions. Tokens are
               stateless and self-verifiable. Suitable for CSRF, email
               verification, password reset, short-lived signed URLs.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

// ============================================================
// HIX_TokenSetSecret -- publica el secret al store compartido.
// ============================================================
FUNCTION HIX_TokenSetSecret( cSecret )

   IF ValType( cSecret ) == "C" .AND. ! Empty( cSecret )

      HIX_KeySet( "token", cSecret )

   ENDIF

RETURN NIL

// ============================================================
FUNCTION HIX_TokenGetSecret()
RETURN HIX_KeyGet( "token", "H!x@TOKEN@2026" )

// ============================================================
// HIX_TokenGenRandom -- alphanumeric random string (nLen chars).
// ============================================================
FUNCTION HIX_TokenGenRandom( nLen )

   LOCAL cChars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
   LOCAL cToken := "", i

   hb_default( @nLen, 16 )

   FOR i := 1 TO nLen

      cToken += SubStr( cChars, hb_RandomInt( 1, Len( cChars ) ), 1 )

   NEXT

RETURN cToken

// ============================================================
// HIX_TokenMake -- build a signed token.
// Format: base64(data|unix_ts) + "." + HMAC_SHA256(payload, secret)
// cData:   seed string; default = 16-char random.
// cSecret: HMAC key; default = module-level secret.
// ============================================================
FUNCTION HIX_TokenMake( cData, cSecret )

   LOCAL cPayload

   hb_default( @cData,   HIX_TokenGenRandom( 16 ) )
   hb_default( @cSecret, HIX_TokenGetSecret()      )
   cPayload := cData + "|" + hb_NToS( Int( hb_TToSec( hb_DateTime() ) ) )

RETURN hb_base64Encode( cPayload ) + "." + hb_HMAC_SHA256( cPayload, cSecret )

// ============================================================
// HIX_TokenValid -- verify HMAC signature and optional expiry.
// nLapsus = 0 (default) -> no expiry check.
// cSecret: HMAC key; default = module-level secret.
// Returns .T. if valid.
// ============================================================
FUNCTION HIX_TokenValid( cToken, nLapsus, cSecret )

   LOCAL cPayload, cSign, aParts, aInfo, nIssued

   hb_default( @cToken,  ""              )
   hb_default( @nLapsus, 0               )
   hb_default( @cSecret, HIX_TokenGetSecret() )

   aParts := hb_ATokens( cToken, "." )

   IF Len( aParts ) != 2

      RETURN .F.

   ENDIF

   cPayload := hb_base64Decode( aParts[ 1 ] )
   cSign    := aParts[ 2 ]

   IF !( cSign == hb_HMAC_SHA256( cPayload, cSecret ) )

      RETURN .F.

   ENDIF

   IF nLapsus > 0

      aInfo := hb_ATokens( cPayload, "|" )

      IF Len( aInfo ) < 2

         RETURN .F.

      ENDIF

      nIssued := Val( aInfo[ Len( aInfo ) ] )

      IF Int( hb_TToSec( hb_DateTime() ) ) > ( nIssued + nLapsus )

         RETURN .F.

      ENDIF

   ENDIF

RETURN .T.
