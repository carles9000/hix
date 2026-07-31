/*-----------------------------------------------------------
  File ......: hix_mw_csrf.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: CSRF token protection middleware for HIX.
               Generates a random token per session and validates
               it on unsafe methods (POST/PUT/DELETE/PATCH).
               Token exposed as oCtx:hData["csrf_token"].
  Usage      : oSrv:Use( { "HIX_MwSession", "HIX_MwCsrf" } )
  Notes      : Web: yes (essential) | API: no (use JWT instead)
 -----------------------------------------------------------*/

// ============================================================
// CSRF — Cross-Site Request Forgery protection
//
// Concept:
// An attacker can trick a logged-in user's browser into sending
// a forged request to your site. CSRF tokens prevent this by
// requiring every unsafe request (POST/PUT/DELETE/PATCH) to
// include a secret token that only the real page knows.
//
// How it works:
// 1. On the first GET request, a random token is generated and
// stored in the session under "_csrf_token".
// 2. The token is exposed as oCtx:hData["csrf_token"] so that
// templates can embed it in forms or AJAX headers.
// 3. On POST/PUT/DELETE/PATCH, the middleware reads the token
// from the X-CSRF-Token header (AJAX) or the _csrf form
// field (HTML forms) and compares it to the session token.
// 4. Mismatch -> 403 Forbidden.
//
// Token delivery options:
// HTML form:  <input type="hidden" name="_csrf" value="<token>">
// AJAX:       headers: { "X-CSRF-Token": token }
//
// Requires HIX_MwSession earlier in the same pipeline.
//
// Use when:
// - Any web app with session-based auth and HTML forms
// - SPA with cookie auth (send token via header)
//
// Web: ESSENTIAL — always include for session-based web apps
// API: NOT needed — stateless APIs should use JWT (Bearer tokens
// are not sent automatically by browsers, so CSRF is N/A)
//
// Example:
// oSrv:Use( { "HIX_MwSession", "HIX_MwCsrf" } )
// // In your template: embed oCtx:hData["csrf_token"] in forms
//
// Example — redirect on fail + custom header/field names:
// HIX_MwCsrfSetup( "/login", "x-my-csrf", "my_csrf_field" )
// ============================================================

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_cCsrfHeader   := "x-csrf-token"
STATIC s_cCsrfField    := "_csrf"
STATIC s_cCsrfKey      := "_csrf_token"
STATIC s_nLapsus       := 0    // token TTL in seconds; 0 = no expiry
STATIC s_cCsrfRedirect := ""   // HIX_MwCsrfCheck: redirect here on fail ("" = JSON 403)

// ============================================================
// HIX_MwCsrfSetup — override redirect URL and optionally header/field names, secret and TTL.
// cRedirect: URL to redirect to on CSRF failure ("" = JSON 403).
// cHeader:   request header name carrying the token (default "x-csrf-token").
// cField:    form field name carrying the token (default "_csrf").
// cSecret:   HMAC signing secret (stored via HIX_KeySet("csrf")).
// nLapsus:   token lifetime in seconds; 0 = no expiry.
// Call before oSrv:Start().
// ============================================================
PROCEDURE HIX_MwCsrfSetup( cRedirect, cHeader, cField, cSecret, nLapsus )

   IF ValType( cRedirect ) == "C"                            ; s_cCsrfRedirect := cRedirect         ; ENDIF

   IF ValType( cHeader   ) == "C" .AND. ! Empty( cHeader   ) ; s_cCsrfHeader   := Lower( cHeader ) ; ENDIF

   IF ValType( cField    ) == "C" .AND. ! Empty( cField    ) ; s_cCsrfField    := cField           ; ENDIF

   IF ValType( cSecret   ) == "C" .AND. ! Empty( cSecret   ) ; HIX_KeySet( "csrf", cSecret ) ; ENDIF

   IF ValType( nLapsus   ) == "N"                            ; s_nLapsus       := nLapsus           ; ENDIF

RETURN

// ============================================================
// HIX_MwCsrf — generates/validates CSRF token.
// Safe methods (GET/HEAD/OPTIONS): generate token if absent.
// Unsafe methods: validate token from header or form field.
// Requires HIX_MwSession earlier in the pipeline.
// ============================================================
FUNCTION HIX_MwCsrf( oCtx )

   LOCAL cToken, cMethod

   IF ! hb_HHasKey( oCtx:hData, "session" )

      _HixCsrfSend( oCtx:oReq, 500, _( 'ERR_CSRF_REQUIRES_SESSION' ) )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

   cToken := hb_HGetDef( oCtx:hData[ "session" ], s_cCsrfKey, "" )

   IF Empty( cToken ) .OR. ! HIX_CsrfValidToken( cToken, s_nLapsus )

      cToken := HIX_CsrfMakeToken()
      HIX_SessionSet( oCtx, s_cCsrfKey, cToken )
      HIX_SessionSave( oCtx )

   ENDIF

   oCtx:hData[ "csrf_token" ] := cToken

   cMethod := Upper( oCtx:oReq:cMethod )

   IF cMethod == "GET" .OR. cMethod == "HEAD" .OR. cMethod == "OPTIONS"

      RETURN .T.

   ENDIF

RETURN _HixCsrfValidate( oCtx, cToken )

// ============================================================
// HIX_MwCsrfCheck — stateless CSRF middleware.
// Validates the HMAC-signed token from the request (header or
// form field) without requiring a session. Safe methods pass
// through unchanged. Use this for routes where @csrf / UCsrfToHtml()
// embeds the token directly in the form (no session needed).
//
// Example:
// oSrv:AddRoutePost( "auth", "/auth", "controllers/auth.prg", "HIX_MwCsrfCheck" )
// oSrv:AddRoutePost( "save", "/save", "controllers/save.prg", { "AppAuth", "HIX_MwCsrfCheck" } )
// ============================================================
FUNCTION HIX_MwCsrfCheck( oCtx )

   LOCAL cMethod, cGot, hForm, oFlash

   cMethod := Upper( oCtx:oReq:cMethod )

   IF cMethod == "GET" .OR. cMethod == "HEAD" .OR. cMethod == "OPTIONS"

      RETURN .T.

   ENDIF

   cGot := oCtx:oReq:Header( s_cCsrfHeader, "" )

   IF Empty( cGot )

      hForm := oCtx:oReq:FormBody()

      IF ValType( hForm ) == "H"

         cGot := hb_HGetDef( hForm, s_cCsrfField, "" )

      ENDIF

   ENDIF

   IF Empty( cGot ) .OR. ! HIX_CsrfValidToken( cGot, s_nLapsus )

      oCtx:lHandled := .T.

      IF ! Empty( s_cCsrfRedirect )

         IF hb_HHasKey( oCtx:hData, "session" )

            oFlash := UFlash( "csrf" )
            oFlash:Set( "error", _( 'ERR_CSRF_MSG' ) )
            oFlash:Save()

         ENDIF

         URedirect( s_cCsrfRedirect )
      ELSE
         _HixCsrfSend( oCtx:oReq, 403, _( 'ERR_CSRF_INVALID' ) )

      ENDIF

      RETURN .F.

   ENDIF

RETURN .T.

// ---- private helpers ----

STATIC FUNCTION _HixCsrfValidate( oCtx, cExpected )

   LOCAL cGot, hForm

   cGot := oCtx:oReq:Header( s_cCsrfHeader, "" )

   IF Empty( cGot )

      hForm := oCtx:oReq:FormBody()

      IF ValType( hForm ) == "H"

         cGot := hb_HGetDef( hForm, s_cCsrfField, "" )

      ENDIF

   ENDIF

   IF Empty( cGot ) .OR. !( cGot == cExpected ) .OR. ! HIX_CsrfValidToken( cGot, s_nLapsus )

      _HixCsrfSend( oCtx:oReq, 403, _( 'ERR_CSRF_INVALID' ) )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

RETURN .T.

STATIC PROCEDURE _HixCsrfSend( oReq, nStatus, cError )

   oReq:Respond( hb_jsonEncode( { "error" => cError } ), nStatus, "json" )

RETURN
