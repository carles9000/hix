/*-----------------------------------------------------------
  File ......: hix_mw_web_auth.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Middleware group for protected web routes.
               Requires the user to be authenticated via session.
               Redirects to /login if not authenticated.
  Usage      : oSrv:AddRouteGet( "dash", "/dashboard", "controllers/dash.prg", "MW_WEB_AUTH" )
  Notes      : Web: yes | API: no
 -----------------------------------------------------------*/

// ============================================================
// MW_WEB_AUTH — protected web pipeline (session required)
//
// Use for:
// Any web route that requires a logged-in user. If the session
// has no authenticated user, the request is redirected to the
// login page (/login) via cOnFail.
//
// Pipeline:
// Maintenance → SecHeaders → BodyLimit → Session → RequireAuth[/login]
//
// Maintenance : returns 503 if server is in maintenance mode
// SecHeaders  : injects HTTP hardening headers
// BodyLimit   : rejects oversized request bodies
// Session     : loads the session from the cookie
// RequireAuth : checks session for a logged-in user;
// if absent → cOnFail="/login" (router redirects)
//
// On success:
// oCtx:hData["user"]  — the authenticated user hash
// UCurrentUser()      — same, accessible from route handlers
//
// On failure:
// Router dispatches cOnFail "/login" instead of the route handler
//
// Typical routes:
// GET /dashboard     → user home page
// GET /profile       → user profile
// POST /settings     → save preferences (user must be logged in)
// ============================================================

#INCLUDE "hix_const.ch"

FUNCTION MW_WEB_AUTH( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HIX_MwMaintenance", "maintenance"            ) )
   o:Add( UMiddleware():New( "HIX_MwSecHeaders",  "sec-headers"            ) )
   o:Add( UMiddleware():New( "HIX_MwBodyLimit",   "body-limit"             ) )
   o:Add( UMiddleware():New( "HIX_MwSession",     "session"                ) )
   o:Add( UMiddleware():New( "HIX_MwRequireAuth", "require-auth", "/login" ) )

RETURN o:Run()
