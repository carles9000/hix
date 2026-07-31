/*-----------------------------------------------------------
  File ......: hix_mw_web_admin.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Middleware group for the admin panel.
               Requires the "admin" role. Most restrictive web
               group — only administrators pass through.
  Usage      : oSrv:AddRouteGet( "admin", "/admin", "controllers/admin.prg", "MW_WEB_ADMIN" )
  Notes      : Web: yes | API: no
 -----------------------------------------------------------*/

// ============================================================
// MW_WEB_ADMIN — admin panel pipeline (role "admin" required)
//
// Use for:
// The administration area of the application. Only users with
// the "admin" role are allowed through. Unlike MW_WEB_EDIT,
// CSRF is not included here by default — admin actions are
// typically confirmed by other means (or add it if needed).
//
// Pipeline:
// Maintenance → SecHeaders → BodyLimit → Session
// → RequireAuth[/login] → RequireRole("admin")[/403]
//
// Maintenance      : returns 503 if server is in maintenance mode
// SecHeaders       : injects HTTP hardening headers
// BodyLimit        : rejects oversized request bodies
// Session          : loads the session from the cookie
// RequireAuth      : user must be logged in → cOnFail="/login"
// RequireRole      : user must have role "admin" → cOnFail="/403"
//
// On success:
// oCtx:hData["user"]  — authenticated admin user
// UHasRole("admin")   — always .T. at this point
//
// On failure:
// Not logged in  → router dispatches /login
// Not admin      → router dispatches /403
//
// Typical routes:
// GET  /admin           → admin dashboard
// GET  /admin/users     → user management list
// POST /admin/users     → create/modify user
// GET  /admin/settings  → global settings
// ============================================================

#INCLUDE "hix_const.ch"

FUNCTION MW_WEB_ADMIN( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HIX_MwMaintenance",                 "maintenance"            ) )
   o:Add( UMiddleware():New( "HIX_MwSecHeaders",                  "sec-headers"            ) )
   o:Add( UMiddleware():New( "HIX_MwBodyLimit",                   "body-limit"             ) )
   o:Add( UMiddleware():New( "HIX_MwSession",                     "session"                ) )
   o:Add( UMiddleware():New( "HIX_MwRequireAuth",                 "require-auth", "/login" ) )
   o:Add( UMiddleware():New( {| oCtx | ( oCtx:cScope := "admin", HIX_MwHasRole( oCtx ) ) }, "require-role", "/403" ) )

RETURN o:Run()
