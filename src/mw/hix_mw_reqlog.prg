/*-----------------------------------------------------------
  File ......: hix_mw_reqlog.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Request logger middleware for HIX.
               Logs METHOD + path + client IP at the configured
               log level. Always passes (returns .T.).
  Usage      : HIX_MwReqLogSetup( HIX_LOG_INFO )
               oSrv:Use( "HIX_MwReqLog" )
  Notes      : Web: yes | API: yes
 -----------------------------------------------------------*/

// ============================================================
// Request Logger — per-request audit trail
//
// Concept:
// Logs a one-line entry for every incoming request before any
// route handler runs. Useful for debugging, access auditing,
// and traffic analysis without modifying route code.
//
// Uses the HIX logger (hix_logger.ch macros), so output goes
// to the same log file/console as the rest of the server.
//
// Log format:
// METHOD /path clientIP
// e.g.: GET /api/users 192.168.1.10
//
// Log levels (use HIX_LOG_* constants from hix_const.ch):
// HIX_LOG_DEBUG  — verbose, dev only
// HIX_LOG_INFO   — normal production logging (default)
// HIX_LOG_WARN   — log only unusual paths
//
// This middleware always returns .T. (never blocks a request).
//
// Web: yes — especially useful in dev/staging
// API: yes — essential for access logging in production
//
// Example — global INFO logging:
// HIX_MwReqLogSetup( HIX_LOG_INFO )
// oSrv:Use( "HIX_MwReqLog" )
//
// Example — debug-only logging for a specific route group:
// oSrv:AddRouteGet( "debug", "/debug/*", {||...}, ;
// { HIX_MwReqLogFactory( HIX_LOG_DEBUG ) } )
// ============================================================

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_nReqLogLevel := HIX_LOG_INFO

// ============================================================
// HIX_MwReqLogSetup — set the global log level for requests.
// Call before oSrv:Start().
// ============================================================
PROCEDURE HIX_MwReqLogSetup( nLevel )

   IF ValType( nLevel ) == "N" .AND. nLevel >= HIX_LOG_DEBUG .AND. nLevel <= HIX_LOG_FATAL

      s_nReqLogLevel := nLevel

   ENDIF

RETURN

// ============================================================
// HIX_MwReqLog — logs the request at the global level.
// ============================================================
FUNCTION HIX_MwReqLog( oCtx )
RETURN _HixMwReqLogRun( oCtx, s_nReqLogLevel )

// ============================================================
// HIX_MwReqLogFactory — per-route codeblock with custom level.
// ============================================================
FUNCTION HIX_MwReqLogFactory( nLevel )
RETURN {| oCtx | _HixMwReqLogRun( oCtx, nLevel ) }

// ---- private helper ----

STATIC FUNCTION _HixMwReqLogRun( oCtx, nLevel )

   _l( oCtx:oReq:cMethod + " " + oCtx:oReq:cPath + " " + oCtx:oReq:cIP, nLevel, "request" )

RETURN .T.
