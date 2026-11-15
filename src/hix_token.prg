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

STATIC s_nTokCounter := 0
STATIC s_mtxTokCtr   := NIL

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
// HIX_TokenGenRandom -- nLen-char alphanumeric token derived from
// HMAC-SHA256(timestamp:millis:counter:prng, secret). The output
// alphabet and length are preserved; the entropy source is replaced
// with a keyed PRF so the token is unpredictable without the secret
// even if the message inputs are observable (A1.12).
// HMAC gives 32 bytes per round; a new round is started every 32
// output chars so arbitrarily long tokens are supported.
// ============================================================
FUNCTION HIX_TokenGenRandom( nLen )

   LOCAL nCount, cMsg, cHmac, cChars
   LOCAL cResult, nX, nByte, nHi, nLo, nPos

   hb_default( @nLen, 16 )

   IF s_mtxTokCtr == NIL ; s_mtxTokCtr := hb_mutexCreate() ; ENDIF

   hb_mutexLock( s_mtxTokCtr )
   s_nTokCounter++
   nCount := s_nTokCounter
   hb_mutexUnlock( s_mtxTokCtr )

   cMsg := hb_NToS( Int( hb_TToSec( hb_DateTime() ) ) ) + ":" + ;
           hb_NToS( hb_MilliSeconds()                 ) + ":" + ;
           hb_NToS( nCount                            ) + ":" + ;
           hb_NToS( hb_RandomInt( 0, 2147483647 )     )

   cChars  := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
   cResult := ""
   cHmac   := hb_HMAC_SHA256( cMsg, HIX_TokenGetSecret() )

   FOR nX := 1 TO nLen

      // Refresh HMAC every 32 output chars (HMAC-SHA256 = 32 bytes = 64 hex chars)
      IF nX > 1 .AND. ( nX - 1 ) % 32 == 0
         cHmac := hb_HMAC_SHA256( cMsg + ":" + hb_NToS( nX ), HIX_TokenGetSecret() )
      ENDIF

      nPos  := ( ( nX - 1 ) % 32 ) * 2 + 1
      nHi   := At( SubStr( cHmac, nPos,     1 ), "0123456789abcdef" ) - 1
      nLo   := At( SubStr( cHmac, nPos + 1, 1 ), "0123456789abcdef" ) - 1
      nByte := nHi * 16 + nLo
      cResult += SubStr( cChars, 1 + ( nByte % 62 ), 1 )

   NEXT

RETURN cResult

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

   IF ! _HixTokenConstantEq( cSign, hb_HMAC_SHA256( cPayload, cSecret ) )

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

// ---- private helpers ----

// [A4.14] Delegación a HIX_ConstantEq (hix_helpers.prg) — implementación
// compartida con hix_jwt.prg. La función local queda como alias interno.
STATIC FUNCTION _HixTokenConstantEq( cA, cB )
RETURN HIX_ConstantEq( cA, cB )

// Public wrapper — kept for backward-compat and callers (hix_mw_csrf.prg,
// hix_session.prg). Not part of the public API.
FUNCTION HIX_TokenConstantEq( cA, cB )
RETURN HIX_ConstantEq( cA, cB )
