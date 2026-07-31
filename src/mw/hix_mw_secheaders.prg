/*-----------------------------------------------------------
  File ......: hix_mw_secheaders.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Security hardening headers middleware for HIX.
               Injects X-Frame-Options, X-Content-Type-Options,
               Strict-Transport-Security, and Content-Security-Policy
               on every response. Always passes (returns .T.).
  Usage      : HIX_MwSecHeadersSetup( "default-src 'self'" )
               oSrv:Use( "HIX_MwSecHeaders" )
  Notes      : Web: yes (critical) | API: yes (recommended)
 -----------------------------------------------------------*/

// ============================================================
// Security Headers — HTTP hardening
//
// Concept:
// Modern browsers enforce a set of HTTP response headers that
// protect users from common attacks like clickjacking, MIME
// sniffing, and protocol downgrade. This middleware sets them
// automatically on every response.
//
// Headers injected:
// X-Frame-Options: DENY
// Prevents the page from being embedded in an <iframe>.
// Blocks clickjacking attacks.
//
// X-Content-Type-Options: nosniff
// Prevents the browser from guessing the MIME type.
// Stops MIME-confusion attacks on uploaded files.
//
// Strict-Transport-Security: max-age=31536000
// Forces HTTPS for 1 year (HSTS). Only effective over TLS.
//
// Content-Security-Policy: <cCSP>
// Controls which resources the browser may load.
// "default-src 'self'" blocks all external content.
//
// This middleware always returns .T. (never blocks a request).
//
// Web: critical — include in every production site
// API: recommended — prevents misuse of API responses as web content
//
// Example — strict CSP for a web app:
// HIX_MwSecHeadersSetup( "default-src 'self'; " + ;
// "script-src 'self' 'nonce-abc123'" )
// oSrv:Use( "HIX_MwSecHeaders" )
//
// Example — per-route factory with relaxed CSP for an API:
// oSrv:AddRouteGet( "api", "/api/*", {||...}, ;
// { HIX_MwSecHeadersFactory( "default-src 'none'" ) } )
// ============================================================

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_cSecCSP := "default-src 'self'"

// ============================================================
// HIX_MwSecHeadersSetup — set the Content-Security-Policy value.
// Call before oSrv:Start().
// ============================================================
PROCEDURE HIX_MwSecHeadersSetup( cCSP )

   IF ValType( cCSP ) == "C" .AND. ! Empty( cCSP ) ; s_cSecCSP := cCSP ; ENDIF

RETURN

// ============================================================
// HIX_MwSecHeaders — injects security headers using global CSP.
// ============================================================
FUNCTION HIX_MwSecHeaders( oCtx )
RETURN _HixMwSecHeadersRun( oCtx, s_cSecCSP )

// ============================================================
// HIX_MwSecHeadersFactory — per-route codeblock with custom CSP.
// ============================================================
FUNCTION HIX_MwSecHeadersFactory( cCSP )
RETURN {| oCtx | _HixMwSecHeadersRun( oCtx, cCSP ) }

// ---- private helper ----

STATIC FUNCTION _HixMwSecHeadersRun( oCtx, cCSP )

   hb_HMerge( oCtx:oReq:hExtraHeaders, { ;
      "X-Frame-Options"           => "DENY",             ;
      "X-Content-Type-Options"    => "nosniff",          ;
      "Strict-Transport-Security" => "max-age=31536000", ;
      "Content-Security-Policy"   => cCSP                ;
      } )

RETURN .T.
