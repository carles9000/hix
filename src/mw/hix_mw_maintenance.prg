/*-----------------------------------------------------------
  File ......: hix_mw_maintenance.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Maintenance mode middleware for HIX.
               Returns HTTP 503 with a JSON error when the server
               is in maintenance mode (flag or lock file).
  Usage      : HIX_MwMaintenanceSetup( .T., "maintenance.lock" )
               oSrv:Use( "HIX_MwMaintenance" )
  Notes      : Web: yes | API: yes
 -----------------------------------------------------------*/

// ============================================================
// Maintenance Mode — graceful 503 during downtime
//
// Concept:
// When active, every request receives a 503 Service Unavailable
// response with { "error": "maintenance" } JSON body. Useful
// during deployments, DB migrations, or planned outages.
//
// Two activation mechanisms:
// 1. Flag (lActive .T.) — set programmatically at startup or
// toggled via an admin endpoint.
// 2. Lock file (cFile) — creates/deletes a file on disk to
// toggle maintenance without restarting the server.
// Useful for ops scripts: `touch maintenance.lock` to enable,
// `del maintenance.lock` to disable.
//
// Both can be combined: either condition activates maintenance.
//
// Use when:
// - Deploying a new version that requires downtime
// - Running database migrations
// - Temporarily disabling a service
//
// Web: yes — show a friendly 503 page (customize the response body)
// API: yes — clients should check for 503 and retry with backoff
//
// Example — flag-based:
// HIX_MwMaintenanceSetup( .T. )
// oSrv:Use( "HIX_MwMaintenance" )
//
// Example — lock file (ops-friendly):
// HIX_MwMaintenanceSetup( .F., "c:\hix.pro\maintenance.lock" )
// oSrv:Use( "HIX_MwMaintenance" )
// // to enable:  create the file
// // to disable: delete the file
//
// Example — per-route factory:
// oSrv:AddRouteGet( "admin", "/admin/*", {||...}, ;
// { HIX_MwMaintenanceFactory( lAdminDown ) } )
// ============================================================

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

STATIC s_lMaintenance     := .F.
STATIC s_cMaintenanceFile := ""

// ============================================================
// HIX_MwMaintenanceSetup — set the flag and/or lock file path.
// Call before oSrv:Start(). Can be called again at runtime.
// ============================================================
PROCEDURE HIX_MwMaintenanceSetup( lActive, cFile )

   IF ValType( lActive ) == "L" ; s_lMaintenance     := lActive ; ENDIF

   IF ValType( cFile   ) == "C" ; s_cMaintenanceFile := cFile   ; ENDIF

RETURN

// ============================================================
// HIX_MwMaintenance — checks global flag + lock file.
// ============================================================
FUNCTION HIX_MwMaintenance( oCtx )
RETURN _HixMwMaintenanceRun( oCtx, s_lMaintenance, s_cMaintenanceFile )

// ============================================================
// HIX_MwMaintenanceFactory — per-route factory with fixed flag.
// Note: lock file not supported in factory mode.
// ============================================================
FUNCTION HIX_MwMaintenanceFactory( lActive )
RETURN {| oCtx | _HixMwMaintenanceRun( oCtx, lActive, "" ) }

// ---- private helper ----

STATIC FUNCTION _HixMwMaintenanceRun( oCtx, lActive, cFile )

   LOCAL lOn := lActive .OR. ( ! Empty( cFile ) .AND. File( cFile ) )

   IF lOn

      oCtx:oReq:Respond( hb_jsonEncode( { "error" => _( 'ERR_MAINTENANCE' ) } ), 503, "json" )
      oCtx:lHandled := .T.
      RETURN .F.

   ENDIF

RETURN .T.
