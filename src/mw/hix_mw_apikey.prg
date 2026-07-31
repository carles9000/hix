/*-----------------------------------------------------------
  File ......: hix_mw_apikey.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: API Key authentication middleware for HIX.
               Validates the X-Api-Key request header against a
               pre-configured list of allowed keys. Rejects with
               401 if missing or unknown. Sets hData["api_key"].
  Usage      : HIX_MwApiKeySetup( { "key-abc", "key-xyz" } )
               oSrv:Use( "HIX_MwApiKey" )
  Notes      : Web: no | API: yes (service-to-service auth)
 -----------------------------------------------------------*/

// ============================================================
// API Key — simple service-to-service authentication
//
// Concept:
// Each API consumer is issued a secret key. The key is sent
// in the X-Api-Key header on every request. The middleware
// validates it against a hash set (O(1) lookup).
//
// On success, oCtx:hData["api_key"] contains the accepted key
// (useful for per-key logging or rate-limiting downstream).
//
// Security notes:
// - Always use over TLS (keys are visible in plaintext otherwise)
// - Rotate keys by calling HIX_MwApiKeySetup() again at runtime
// - Combine with HIX_MwRateLimit for brute-force protection
//
// Use when:
// - Backend-to-backend API calls (no user session involved)
// - Simple partner/integration auth without OAuth overhead
//
// Web: not applicable (users don't have API keys)
// API: standard pattern for M2M and partner integrations
//
// Example — global key list:
// HIX_MwApiKeySetup( { "svc-key-1", "partner-key-2" } )
// oSrv:Use( "HIX_MwApiKey" )
//
// Example — per-route factory with different keys:
// oSrv:AddRouteGet( "internal", "/internal/stats", {||...}, ;
// { HIX_MwApiKeyFactory( { "internal-only-key" } ) } )
// ============================================================

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_hApiKeys := { => }

// ============================================================
// HIX_MwApiKeySetup — set allowed keys from an array.
// Replaces the current key set. Call before oSrv:Start().
// ============================================================
PROCEDURE HIX_MwApiKeySetup( aKeys )

   LOCAL cKey

   s_hApiKeys := { => }

   IF ValType( aKeys ) == "A"

      FOR EACH cKey IN aKeys

         s_hApiKeys[ cKey ] := .T.

      NEXT

   ENDIF

RETURN

// ============================================================
// HIX_MwApiKey — validates X-Api-Key against the global key set.
// ============================================================
FUNCTION HIX_MwApiKey( oCtx )
RETURN _HixMwApiKeyRun( oCtx, s_hApiKeys )

// ============================================================
// HIX_MwApiKeyFactory — per-route codeblock with a private key set.
// ============================================================
FUNCTION HIX_MwApiKeyFactory( aKeys )

   LOCAL hKeys := { => }
   LOCAL cKey

   IF ValType( aKeys ) == "A"

      FOR EACH cKey IN aKeys

         hKeys[ cKey ] := .T.

      NEXT

   ENDIF

RETURN {| oCtx | _HixMwApiKeyRun( oCtx, hKeys ) }

// ---- private helper ----

STATIC FUNCTION _HixMwApiKeyRun( oCtx, hKeys )

   LOCAL cKey := oCtx:oReq:Header( "x-api-key", "" )

   IF Empty( cKey ) .OR. ! hb_HHasKey( hKeys, cKey )

      HIX_HttpError( oCtx:oReq, 401 )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

   oCtx:hData[ "api_key" ] := cKey

RETURN .T.
