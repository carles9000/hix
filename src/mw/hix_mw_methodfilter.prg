/*-----------------------------------------------------------
  File ......: hix_mw_methodfilter.prg
  Author.....: Charly 9000
  Created....: 2026-07-17
  Modified...: 2026-07-17
  Version....: 1.0.0
  Description: HTTP method allow-list middleware for HIX.
               Rejects requests whose method is not in the
               configured allow-list with HTTP 405 Method
               Not Allowed before the router runs.
  Usage      : HIX_MwMethodFilterSetup( { "GET", "POST" } )
               oSrv:Use( "HIX_MwMethodFilter" )
  Notes      : Web: yes | API: yes
 -----------------------------------------------------------*/

// ============================================================
// Method Filter — reject dangerous or unwanted HTTP methods
//
// Concept:
// Compares the request method against a global allow-list.
// If the method is not present, responds 405 with
// { "error": "method_not_allowed" } before the router runs.
//
// Default allow-list (if Setup is never called):
//   GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
//
// Common attackers use TRACE / CONNECT / TRACK / DEBUG /
// PROPFIND to probe the server. All are rejected by default.
//
// Use when:
// - Hardening a public-facing HIX server
// - Enforcing a strict method surface for API routes
//
// Web: yes — reject non-standard methods early
// API: yes — narrow the accepted method set per API surface
//
// Example — default allow-list, global:
//   oSrv:Use( "HIX_MwMethodFilter" )
//
// Example — restrict to read-only:
//   HIX_MwMethodFilterSetup( { "GET", "HEAD", "OPTIONS" } )
//   oSrv:Use( "HIX_MwMethodFilter" )
//
// Example — per-route read-only on /health:
//   oSrv:AddRouteGet( "health", "/health", {||...}, ;
//      { HIX_MwMethodFilterFactory( { "GET", "HEAD" } ) } )
// ============================================================

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_aMethodAllowed := { "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS" }

// ============================================================
// HIX_MwMethodFilterSetup — set the global allow-list.
// Call before oSrv:Start().
// ============================================================
PROCEDURE HIX_MwMethodFilterSetup( aAllowed )

   LOCAL i

   IF ValType( aAllowed ) == "A" .AND. Len( aAllowed ) > 0
      s_aMethodAllowed := {}
      FOR i := 1 TO Len( aAllowed )
         IF ValType( aAllowed[ i ] ) == "C"
            AAdd( s_aMethodAllowed, Upper( AllTrim( aAllowed[ i ] ) ) )
         ENDIF
      NEXT
   ENDIF

RETURN

// ============================================================
// HIX_MwMethodFilter — check request method against allow-list.
// ============================================================
FUNCTION HIX_MwMethodFilter( oCtx )
RETURN _HixMwMethodFilterRun( oCtx, s_aMethodAllowed )

// ============================================================
// HIX_MwMethodFilterFactory — per-route codeblock with custom list.
// ============================================================
FUNCTION HIX_MwMethodFilterFactory( aAllowed )

   LOCAL aNorm := {}
   LOCAL i

   FOR i := 1 TO Len( aAllowed )
      IF ValType( aAllowed[ i ] ) == "C"
         AAdd( aNorm, Upper( AllTrim( aAllowed[ i ] ) ) )
      ENDIF
   NEXT

RETURN {| oCtx | _HixMwMethodFilterRun( oCtx, aNorm ) }

// ---- private helper ----

STATIC FUNCTION _HixMwMethodFilterRun( oCtx, aAllowed )

   LOCAL cMethod := Upper( AllTrim( oCtx:oReq:cMethod ) )

   IF AScan( aAllowed, {| c | c == cMethod } ) == 0

      lw( "MethodFilter: rejected " + cMethod + " " + oCtx:oReq:cPath )
      oCtx:oReq:Respond( hb_jsonEncode( { "error" => "method_not_allowed" } ), 405, "json" )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

RETURN .T.

// ============================================================
// HIX_MwMethodFilterConfig -- returns current allow-list.
// Used by tests and diagnostics.
// ============================================================
FUNCTION HIX_MwMethodFilterConfig()
RETURN { "methods" => AClone( s_aMethodAllowed ) }
