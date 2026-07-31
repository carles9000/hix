/*-----------------------------------------------------------
  File ......: hix_mw_bodylimit.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Request body size limit middleware for HIX.
               Rejects requests whose Content-Length exceeds the
               configured maximum with HTTP 413 Payload Too Large.
  Usage      : HIX_MwBodyLimitSetup( 2 * 1024 * 1024 )  // 2 MB
               oSrv:Use( "HIX_MwBodyLimit" )
  Notes      : Web: yes | API: yes
 -----------------------------------------------------------*/

// ============================================================
// Body Limit — protect against oversized uploads
//
// Concept:
// Reads the Content-Length header and compares it to the
// configured maximum. If exceeded, responds with 413 and
// { "error": "payload_too_large" } before reading the body.
//
// This is a declarative check, not a streaming limit — it
// relies on Content-Length being present. Clients that send
// chunked Transfer-Encoding without Content-Length bypass
// this check (handle those at the network/proxy layer).
//
// Default limit: 1 MB (1048576 bytes)
//
// Use when:
// - Accepting file uploads or large JSON payloads
// - Preventing memory exhaustion from large request bodies
// - Enforcing per-route upload size policies
//
// Web: yes — protect form uploads and file inputs
// API: yes — prevent abuse from oversized JSON or binary payloads
//
// Example — global 2 MB limit:
// HIX_MwBodyLimitSetup( 2 * 1024 * 1024 )
// oSrv:Use( "HIX_MwBodyLimit" )
//
// Example — strict 10 KB for JSON API routes:
// oSrv:AddRoutePost( "api", "/api/*", {||...}, ;
// { HIX_MwBodyLimitFactory( 10 * 1024 ) } )
//
// Example — generous 50 MB for upload endpoint only:
// oSrv:AddRoutePost( "upload", "/upload", {||...}, ;
// { HIX_MwBodyLimitFactory( 50 * 1024 * 1024 ) } )
// ============================================================

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_nBodyLimitMax := 1048576   // 1 MB default

// ============================================================
// HIX_MwBodyLimitSetup — set the global body size limit (bytes).
// Call before oSrv:Start().
// ============================================================
PROCEDURE HIX_MwBodyLimitSetup( nMax )

   IF ValType( nMax ) == "N" .AND. nMax > 0 ; s_nBodyLimitMax := nMax ; ENDIF

RETURN

// ============================================================
// HIX_MwBodyLimit — checks Content-Length against global limit.
// ============================================================
FUNCTION HIX_MwBodyLimit( oCtx )
RETURN _HixMwBodyLimitRun( oCtx, s_nBodyLimitMax )

// ============================================================
// HIX_MwBodyLimitFactory — per-route codeblock with custom limit.
// ============================================================
FUNCTION HIX_MwBodyLimitFactory( nMax )
RETURN {| oCtx | _HixMwBodyLimitRun( oCtx, nMax ) }

// ---- private helper ----

STATIC FUNCTION _HixMwBodyLimitRun( oCtx, nMax )

   LOCAL nLen := Val( oCtx:oReq:Header( "content-length", "0" ) )

   IF nLen > nMax

      oCtx:oReq:Respond( hb_jsonEncode( { "error" => _( 'ERR_PAYLOAD_TOO_LARGE' ) } ), 413, "json" )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

RETURN .T.
