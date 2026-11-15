/*-----------------------------------------------------------
  File ......: hix_csrf.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-27
  Modified...: 2026-10-18
  Description: CSRF token helpers built on top of hix_token.prg.
               Uses HIX_KeyGet("csrf") as the HMAC secret.

               v2.4.3 — tokens are bound to the active session id
               so a token minted in session A cannot be replayed
               by session B (CSRF-replay regression). Call sites
               that mint tokens outside a session (anonymous forms)
               fall back to a random seed and skip the bind check.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

// ============================================================
// _HixCsrfSecret -- returns the HMAC secret from HIX_Keys("csrf").
// Falls back to a built-in default if csrf is not configured.
// ============================================================
STATIC FUNCTION _HixCsrfSecret()
RETURN HIX_KeyGet( "csrf", "H!x@CSRF@2026" )

// ============================================================
// _HixCsrfCtx -- resolve the active THixContext for binding.
// Prefer the context stashed by the dispatcher on oReq:hData;
// fall back to the thread-local context (HIX_GetContext).
// ============================================================
STATIC FUNCTION _HixCsrfCtx()

   LOCAL oReq := HIX_GetRequest()
   LOCAL oCtx

   IF oReq != NIL

      oCtx := hb_HGetDef( oReq:hData, "_ctx", NIL )

      IF oCtx != NIL

         RETURN oCtx

      ENDIF

   ENDIF

RETURN HIX_GetContext()

// ============================================================
// _HixCsrfBind -- current session id, or "" when no session.
// Empty string means "stateless" — HIX_CsrfBound will skip the
// check so that anonymous forms keep working.
// ============================================================
STATIC FUNCTION _HixCsrfBind()

   LOCAL oCtx := _HixCsrfCtx()

   IF oCtx == NIL

      RETURN ""

   ENDIF

RETURN hb_HGetDef( oCtx:hData, "_sid", "" )

// ============================================================
// HIX_CsrfGenRandom -- delegates to HIX_TokenGenRandom.
// ============================================================
FUNCTION HIX_CsrfGenRandom( nLen )
RETURN HIX_TokenGenRandom( nLen )

// ============================================================
// HIX_CsrfMakeToken -- signed token using the csrf key.
// v2.4.3: when cData is omitted, bind to the current session id.
// If no session is active, fall back to the historical random seed
// so stateless flows (public forms) remain supported.
// ============================================================
FUNCTION HIX_CsrfMakeToken( cData )

   IF cData == NIL

      cData := _HixCsrfBind()

      IF Empty( cData )

         cData := HIX_TokenGenRandom( 16 )

      ENDIF

   ENDIF

RETURN HIX_TokenMake( cData, _HixCsrfSecret() )

// ============================================================
// HIX_CsrfValidToken -- validates with the csrf key (signature + TTL).
// ============================================================
FUNCTION HIX_CsrfValidToken( cToken, nLapsus )
RETURN HIX_TokenValid( cToken, nLapsus, _HixCsrfSecret() )

// ============================================================
// HIX_CsrfBound -- v2.4.3. Returns .T. when the token's embedded
// data matches the current session id, or .T. (skip) when no
// session is active. Returns .F. only when a session is present
// but the token was minted for a different session (replay attack).
//
// Token payload format from HIX_TokenMake:
//    base64( cData + "|" + unix_ts ) + "." + HMAC
// We rebuild cData by joining every "|"-split field except the
// last one, since cData itself may legally contain "|" characters.
// ============================================================
FUNCTION HIX_CsrfBound( cToken )

   LOCAL cSid, cPayload, cData, aParts, nLast, nI

   cSid := _HixCsrfBind()

   IF Empty( cSid )

      RETURN .T.

   ENDIF

   hb_default( @cToken, "" )
   aParts := hb_ATokens( cToken, "." )

   IF Len( aParts ) != 2

      RETURN .F.

   ENDIF

   cPayload := hb_base64Decode( aParts[ 1 ] )
   aParts   := hb_ATokens( cPayload, "|" )
   nLast    := Len( aParts )

   IF nLast < 2

      RETURN .F.

   ENDIF

   cData := ""

   FOR nI := 1 TO nLast - 1

      cData += aParts[ nI ]

      IF nI < nLast - 1

         cData += "|"

      ENDIF

   NEXT

RETURN HIX_ConstantEq( cData, cSid )

// ============================================================
// UCsrfToHtml -- hidden <input> ready to embed in forms.
// ============================================================
FUNCTION UCsrfToHtml( cToken )
   LOCAL cHtml

   hb_default( @cToken, HIX_CsrfMakeToken() )

// @format:off
   cHtml := '<input type="hidden" name="_csrf" value="' + cToken + '">'
// @format:on

RETURN cHtml
