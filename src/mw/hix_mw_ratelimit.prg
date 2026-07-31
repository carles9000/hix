/*-----------------------------------------------------------
  File ......: hix_mw_ratelimit.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Fixed-window rate limiter middleware for HIX.
               Counts requests per IP within a time window and
               rejects excess requests with HTTP 429.
  Usage      : HIX_MwRateLimitSetup( 60, 60 )   // 60 req/min
               oSrv:Use( "HIX_MwRateLimit" )
  Notes      : Web: yes | API: yes (essential for public endpoints)
 -----------------------------------------------------------*/

// ============================================================
// Rate Limiting — fixed window per IP
//
// Concept:
// Each IP gets a counter that resets every N seconds (window).
// If the counter exceeds the maximum, the request is rejected
// immediately with 429 Too Many Requests.
//
// This is a fixed-window algorithm: the window resets hard at
// the boundary (not a sliding average). Simple and fast, but
// allows a burst of 2x max at window boundaries.
//
// Thread safety:
// A single mutex (s_mtxRate) protects the shared counter hash.
// Lock/unlock is per-request, so keep nMax reasonable.
//
// oCtx:hData["rate_count"] — current count for this IP/window
//
// Use when:
// - Public API that must be protected from abuse
// - Login endpoints to slow brute-force attempts
//
// Web: useful for login/register forms
// API: essential for any unauthenticated or public endpoint
//
// Example — global limit:
// HIX_MwRateLimitSetup( 100, 60 )   // 100 req per 60 sec
// oSrv:Use( "HIX_MwRateLimit" )
//
// Example — strict per-route via factory:
// oSrv:AddRoutePost( "login", "/login", {||...}, ;
// { HIX_MwRateLimitFactory( 5, 60 ) } )  // 5 attempts/min
// ============================================================

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_nRateMax    := 60
STATIC s_nRateWindow := 60
STATIC s_hRateData   := NIL
STATIC s_mtxRate     := NIL

// ============================================================
// HIX_MwRateLimitSetup — set global max requests and window.
// Call before oSrv:Start().
// ============================================================
PROCEDURE HIX_MwRateLimitSetup( nMax, nWindowSecs )

   IF ValType( nMax        ) == "N" .AND. nMax        > 0 ; s_nRateMax    := nMax        ; ENDIF

   IF ValType( nWindowSecs ) == "N" .AND. nWindowSecs > 0 ; s_nRateWindow := nWindowSecs ; ENDIF

   IF s_mtxRate == NIL

      s_mtxRate := hb_mutexCreate()

   ENDIF

   s_hRateData := { => }

RETURN

// ============================================================
// HIX_MwRateLimit — applies the global rate limit.
// ============================================================
FUNCTION HIX_MwRateLimit( oCtx )

   IF s_hRateData == NIL

      s_hRateData := { => }
      s_mtxRate   := hb_mutexCreate()

   ENDIF

RETURN _HixMwRateLimitRun( oCtx, s_nRateMax, s_nRateWindow )

// ============================================================
// HIX_MwRateLimitFactory — per-route rate limit codeblock.
// ============================================================
FUNCTION HIX_MwRateLimitFactory( nMax, nWindowSecs )

   IF s_hRateData == NIL

      s_hRateData := { => }
      s_mtxRate   := hb_mutexCreate()

   ENDIF

RETURN {| oCtx | _HixMwRateLimitRun( oCtx, nMax, nWindowSecs ) }

// ---- private helper ----

STATIC FUNCTION _HixMwRateLimitRun( oCtx, nMax, nWindowSecs )

   LOCAL cIP, nNow, aEntry, nCount, nStart, lAllow

   cIP  := oCtx:oReq:cIP
   nNow := Int( hb_TToSec( hb_DateTime() ) )

   hb_mutexLock( s_mtxRate )

   IF hb_HHasKey( s_hRateData, cIP )

      aEntry := s_hRateData[ cIP ]
      nCount := aEntry[ 1 ]
      nStart := aEntry[ 2 ]

      IF ( nNow - nStart ) >= nWindowSecs

         nCount := 1
         nStart := nNow
      ELSE
         nCount++

      ENDIF

   ELSE
      nCount := 1
      nStart := nNow

   ENDIF

   s_hRateData[ cIP ] := { nCount, nStart }
   lAllow := ( nCount <= nMax )

   hb_mutexUnlock( s_mtxRate )

   IF ! lAllow

      HIX_HttpError( oCtx:oReq, 429 )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

   oCtx:hData[ "rate_count" ] := nCount

RETURN .T.

// ============================================================
// HIX_MwRateLimitConfig -- returns current rate-limit configuration.
// Used by tests and diagnostics.
// ============================================================
FUNCTION HIX_MwRateLimitConfig()
RETURN { ;
   "max"      => s_nRateMax,   ;
   "window_s" => s_nRateWindow }
