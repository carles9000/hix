/*-----------------------------------------------------------
  File ......: hix_mw_cors.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Cross-Origin Resource Sharing (CORS) middleware for HIX.
               Injects Access-Control-* headers on every response and
               short-circuits OPTIONS preflight requests with 204.
  Usage      : HIX_MwCorsSetup( "*", "GET,POST", "Content-Type" )
               oSrv:Use( "HIX_MwCors" )
  Notes      : Web: yes | API: yes
 -----------------------------------------------------------*/

// ============================================================
// CORS — Cross-Origin Resource Sharing
//
// Concept:
// Browsers send a preflight OPTIONS request before any
// cross-origin request with a non-simple method or header.
// This middleware answers that preflight (204 No Content)
// and injects the CORS headers on every subsequent response.
//
// Use when:
// - Your API is consumed from a different domain/port (SPA, mobile)
// - You need to control which origins/methods/headers are allowed
//
// Web: fine to use, but rarely needed (same-origin)
// API: essential for any public or cross-domain API
//
// Example:
// HIX_MwCorsSetup( "https://myapp.com", "GET,POST,PUT", ;
// "Content-Type,Authorization" )
// oSrv:Use( "HIX_MwCors" )
// ============================================================

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_cCorsOrigin  := "*"
STATIC s_cCorsMethods := "GET,POST,PUT,DELETE,OPTIONS,PATCH"
STATIC s_cCorsHeaders := "Content-Type,Authorization,X-Requested-With"

// ============================================================
// HIX_MwCorsSetup — configure allowed origin, methods, headers.
// Call before oSrv:Start().
// ============================================================
PROCEDURE HIX_MwCorsSetup( cOrigin, cMethods, cHeaders )

   IF ValType( cOrigin  ) == "C" .AND. ! Empty( cOrigin  ) ; s_cCorsOrigin  := cOrigin  ; ENDIF

   IF ValType( cMethods ) == "C" .AND. ! Empty( cMethods ) ; s_cCorsMethods := cMethods ; ENDIF

   IF ValType( cHeaders ) == "C" .AND. ! Empty( cHeaders ) ; s_cCorsHeaders := cHeaders ; ENDIF

RETURN

// ============================================================
// HIX_MwCors — injects CORS headers; answers OPTIONS preflight.
// Returns .F. only for OPTIONS (handled), .T. otherwise.
// ============================================================
FUNCTION HIX_MwCors( oCtx )

   LOCAL hCors := { ;
      "Access-Control-Allow-Origin"  => s_cCorsOrigin,  ;
      "Access-Control-Allow-Methods" => s_cCorsMethods, ;
      "Access-Control-Allow-Headers" => s_cCorsHeaders, ;
      "Access-Control-Max-Age"       => "86400"          ;
      }

   IF oCtx:oReq:cMethod == "OPTIONS"

      oCtx:oReq:Respond( "", 204, "text", hCors )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

   hb_HMerge( oCtx:oReq:hExtraHeaders, hCors )

RETURN .T.

// ============================================================
// HIX_MwCorsConfig -- returns current CORS configuration hash.
// Used by tests and diagnostics.
// ============================================================
FUNCTION HIX_MwCorsConfig()
RETURN { ;
   "origin"  => s_cCorsOrigin,  ;
   "methods" => s_cCorsMethods, ;
   "headers" => s_cCorsHeaders  }
