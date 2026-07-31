/*-----------------------------------------------------------
  File ......: hix_mw_anomaly.prg
  Author.....: Charly 9000
  Created....: 2026-07-17
  Modified...: 2026-07-17
  Version....: 1.0.0
  Description: Anomaly detector middleware for HIX.
               Counts "suspicious" response codes (default
               401/403/404) per client IP inside a moving
               window. When the count crosses a threshold,
               the IP is banned for a configurable TTL and
               further requests get HTTP 429 with Retry-After.
  Usage      : HIX_MwAnomalySetup( 20, 60, 300 )
               oSrv:AddRouteGet( "priv", "/api/*", bAct, "HIX_MwAnomaly" )
  Notes      : Web: yes | API: yes
 -----------------------------------------------------------*/

// ============================================================
// Anomaly Detector — fail2ban-style temporary ban per IP
//
// Concept:
// A pre-request check middleware consults an in-memory ban list.
// If the request IP is banned, it responds 429 with
// { "error": "temporarily_blocked" } and a Retry-After header.
// A companion post-hook (HIX_AnomalyRecord) is called from the
// HTTP worker AFTER the dispatch: when the response status is
// in the tracked set (default 401/403/404), it increments the
// per-IP counter. When the counter crosses the threshold inside
// the moving window, the IP is added to the ban list with a TTL.
//
// State is in-process memory. In a multi-instance deployment
// each HIX keeps its own counter (same limitation as RateLimit).
//
// Defaults (if Setup is never called):
//   threshold = 20 bad responses
//   window    = 60 seconds
//   ban       = 300 seconds (5 min)
//   tracked   = { 401, 403, 404 }
//
// Use when:
// - Hardening endpoints against credential stuffing
// - Discouraging path/token enumeration
// - Slowing down bots that probe protected surfaces
//
// Web: yes — protect login pages and admin areas
// API: yes — protect authenticated API endpoints
//
// Example — defaults, on protected API surface:
//   oSrv:AddRouteGet( "priv", "/api/*", bAct, "HIX_MwAnomaly" )
//
// Example — strict: 5 bad responses in 30s => ban 10 min:
//   HIX_MwAnomalySetup( 5, 30, 600 )
// ============================================================

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_lEnabled    := .F.
STATIC s_nThreshold  := 20
STATIC s_nWindowSec  := 60
STATIC s_nBanSec     := 300
STATIC s_aTracked    := { 401, 403, 404 }
STATIC s_hCounter    := {=>}       // hCounter[ cIP ] = { count, window_start_ts }
STATIC s_hBans       := {=>}       // hBans[ cIP ] = expires_ts
STATIC s_mtxAnomaly  := NIL

// ============================================================
// HIX_MwAnomalySetup — configure global parameters.
// All args optional (NIL keeps current value).
// Calling Setup enables the detector.
// ============================================================
PROCEDURE HIX_MwAnomalySetup( nThr, nWinSec, nBanSec, aTracked )

   LOCAL i

   IF s_mtxAnomaly == NIL ; s_mtxAnomaly := hb_mutexCreate() ; ENDIF

   IF ValType( nThr    ) == "N" .AND. nThr    > 0 ; s_nThreshold := nThr    ; ENDIF
   IF ValType( nWinSec ) == "N" .AND. nWinSec > 0 ; s_nWindowSec := nWinSec ; ENDIF
   IF ValType( nBanSec ) == "N" .AND. nBanSec > 0 ; s_nBanSec    := nBanSec ; ENDIF

   IF ValType( aTracked ) == "A" .AND. Len( aTracked ) > 0
      s_aTracked := {}
      FOR i := 1 TO Len( aTracked )
         IF ValType( aTracked[ i ] ) == "N"
            AAdd( s_aTracked, aTracked[ i ] )
         ENDIF
      NEXT
   ENDIF

   // Reset counters so Setup always starts from a clean slate.
   // Prevents phantom records from pre-enable requests that race
   // between the response flush and this Setup call.
   hb_mutexLock( s_mtxAnomaly )
   s_hCounter := { => }
   s_hBans    := { => }
   hb_mutexUnlock( s_mtxAnomaly )

   s_lEnabled := .T.

RETURN

// ============================================================
// HIX_MwAnomaly — pre-check MW: reject banned IPs with 429.
// ============================================================
FUNCTION HIX_MwAnomaly( oCtx )

   LOCAL cIP     := oCtx:oReq:cIP
   LOCAL nNow    := _AnomalyNow()
   LOCAL nExpires
   LOCAL nRemain

   IF ! s_lEnabled ; RETURN .T. ; ENDIF
   IF s_mtxAnomaly == NIL ; s_mtxAnomaly := hb_mutexCreate() ; ENDIF

   hb_mutexLock( s_mtxAnomaly )

   IF hb_HHasKey( s_hBans, cIP )
      nExpires := s_hBans[ cIP ]
      IF nNow >= nExpires
         hb_HDel( s_hBans, cIP )
      ELSE
         nRemain := nExpires - nNow
         hb_mutexUnlock( s_mtxAnomaly )
         lw( "Anomaly: banned IP " + cIP + " -> 429 (" + hb_NToS( nRemain ) + "s left)" )
         oCtx:oReq:Respond( ;
            hb_jsonEncode( { "error" => "temporarily_blocked" } ), ;
            429, "json", ;
            { "Retry-After" => hb_NToS( nRemain ) } )
         oCtx:lHandled := .T.
         RETURN .F.
      ENDIF
   ENDIF

   hb_mutexUnlock( s_mtxAnomaly )

RETURN .T.

// ============================================================
// HIX_AnomalyRecord — called by the HTTP worker after dispatch.
// If the status is tracked, increment the per-IP counter and,
// if it crosses the threshold inside the window, ban the IP.
// No-op when the detector was never configured.
// ============================================================
PROCEDURE HIX_AnomalyRecord( cIP, nStatus )

   LOCAL aEntry
   LOCAL nNow

   IF ! s_lEnabled ; RETURN ; ENDIF
   IF Empty( cIP ) ; RETURN ; ENDIF
   IF AScan( s_aTracked, {| n | n == nStatus } ) == 0 ; RETURN ; ENDIF

   IF s_mtxAnomaly == NIL ; s_mtxAnomaly := hb_mutexCreate() ; ENDIF

   nNow := _AnomalyNow()

   hb_mutexLock( s_mtxAnomaly )

   IF hb_HHasKey( s_hCounter, cIP )
      aEntry := s_hCounter[ cIP ]
      IF ( nNow - aEntry[ 2 ] ) >= s_nWindowSec
         aEntry := { 1, nNow }
      ELSE
         aEntry[ 1 ]++
      ENDIF
   ELSE
      aEntry := { 1, nNow }
   ENDIF

   s_hCounter[ cIP ] := aEntry

   IF aEntry[ 1 ] >= s_nThreshold
      s_hBans[ cIP ] := nNow + s_nBanSec
      hb_HDel( s_hCounter, cIP )
      lw( "Anomaly: IP " + cIP + " banned for " + hb_NToS( s_nBanSec ) + "s " + ;
          "(" + hb_NToS( aEntry[ 1 ] ) + " bad responses in " + ;
          hb_NToS( s_nWindowSec ) + "s)" )
   ENDIF

   hb_mutexUnlock( s_mtxAnomaly )

RETURN

// ============================================================
// HIX_AnomalyStats — debug/admin snapshot.
// ============================================================
FUNCTION HIX_AnomalyStats()

   LOCAL hStats

   IF s_mtxAnomaly == NIL ; s_mtxAnomaly := hb_mutexCreate() ; ENDIF

   hb_mutexLock( s_mtxAnomaly )
   hStats := { ;
      "enabled"     => s_lEnabled, ;
      "threshold"   => s_nThreshold, ;
      "window_sec"  => s_nWindowSec, ;
      "ban_sec"     => s_nBanSec, ;
      "tracked"     => AClone( s_aTracked ), ;
      "banned"      => Len( s_hBans ), ;
      "tracked_ips" => Len( s_hCounter ) ;
   }
   hb_mutexUnlock( s_mtxAnomaly )

RETURN hStats

// ---- private helper ----

STATIC FUNCTION _AnomalyNow()
RETURN Int( hb_TToSec( hb_DateTime() ) )
