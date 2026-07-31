/*-----------------------------------------------------------
  File ......: hix_csrf.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-27
  Description: CSRF token helpers built on top of hix_token.prg.
               Uses HIX_KeyGet("app_key") as the HMAC secret, loaded
               from config.json via HIX_ConfigAppLoad().
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

// ============================================================
// _HixCsrfSecret -- returns the HMAC secret from HIX_Keys("app_key").
// Falls back to a built-in default if app_key is not configured.
// ============================================================
STATIC FUNCTION _HixCsrfSecret()
RETURN HIX_KeyGet( "csrf", "H!x@CSRF@2026" )

// ============================================================
// HIX_CsrfGenRandom -- delegates to HIX_TokenGenRandom.
// ============================================================
FUNCTION HIX_CsrfGenRandom( nLen )
RETURN HIX_TokenGenRandom( nLen )

// ============================================================
// HIX_CsrfMakeToken -- signed token using the app_key.
// ============================================================
FUNCTION HIX_CsrfMakeToken( cData )
RETURN HIX_TokenMake( cData, _HixCsrfSecret() )

// ============================================================
// HIX_CsrfValidToken -- validates with the app_key.
// ============================================================
FUNCTION HIX_CsrfValidToken( cToken, nLapsus )
RETURN HIX_TokenValid( cToken, nLapsus, _HixCsrfSecret() )

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
