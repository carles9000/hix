/*-----------------------------------------------------------
  File ......: hix_mw_api_admin.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Middleware group for admin-only API routes.
               Extends MW_API_JWT with a role check for "admin".
               All failures respond with JSON (no redirects).
  Usage      : oSrv:AddRouteGet( "admin_stats", "/api/admin/stats", "controllers/stats.prg", "MW_API_ADMIN" )
  Notes      : Web: no | API: yes (admin only)
 -----------------------------------------------------------*/

// ============================================================
// MW_API_ADMIN — admin REST API pipeline (role "admin" required)
//
// Use for:
// API endpoints that must be restricted to administrators.
// Extends MW_API_JWT with an additional role guard. All
// failures return JSON — suitable for backend or dashboard
// clients that consume an admin API.
//
// Pipeline:
// Maintenance → CORS → SecHeaders → RateLimit → BodyLimit
// → ReqLog → Jwt[401 JSON] → RequireAuth[401 JSON]
// → RequireRole("admin")[403 JSON]
//
// Maintenance      : returns 503 if server is in maintenance mode
// CORS             : handles preflight and injects CORS headers
// SecHeaders       : HTTP hardening headers
// RateLimit        : rejects excess requests with 429
// BodyLimit        : rejects oversized bodies with 413
// ReqLog           : logs every admin API request
// Jwt              : validates Bearer token; 401 JSON if invalid
// RequireAuth      : user must be authenticated; 401 JSON if not
// RequireRole      : user must have role "admin"; 403 JSON if not
//
// On success:
// oCtx:hData["user"]  — authenticated admin user
// UHasRole("admin")   — always .T. at this point
//
// On failure (all return JSON, no redirects):
// Missing/invalid token  → 401 { "error": "unauthorized" }
// No user in context     → 401 { "error": "unauthorized" }
// Missing "admin" role   → 403 { "error": "forbidden" }
//
// Typical routes:
// GET  /api/admin/stats       → server statistics
// GET  /api/admin/users       → user list
// POST /api/admin/users       → create user
// DELETE /api/admin/users/:id → delete user
// ============================================================

#INCLUDE "hix_const.ch"

FUNCTION MW_API_ADMIN( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HIX_MwMaintenance",                 "maintenance"  ) )
   o:Add( UMiddleware():New( "HIX_MwCors",                        "cors"         ) )
   o:Add( UMiddleware():New( "HIX_MwSecHeaders",                  "sec-headers"  ) )
   o:Add( UMiddleware():New( "HIX_MwRateLimit",                   "rate-limit"   ) )
   o:Add( UMiddleware():New( "HIX_MwBodyLimit",                   "body-limit"   ) )
   o:Add( UMiddleware():New( "HIX_MwReqLog",                      "req-log"      ) )
   o:Add( UMiddleware():New( "HIX_MwJwt",                         "jwt"          ) )
   o:Add( UMiddleware():New( "HIX_MwJwtScope",                    "jwt-scope"    ) )
   o:Add( UMiddleware():New( "HIX_MwRequireAuth",                 "require-auth" ) )
   o:Add( UMiddleware():New( {| oCtx | ( oCtx:cScope := "admin", HIX_MwHasRole( oCtx ) ) }, "require-role" ) )

RETURN o:Run()
