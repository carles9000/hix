/*-----------------------------------------------------------
  File ......: hix_mw_web_edit.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Middleware group for web routes that require
               the "editor" role. Extends MW_WEB_AUTH with CSRF
               and a role check. Redirects to /403 if the user
               lacks the required role.
  Usage      : oSrv:AddRouteGet( "edit", "/content/edit", "controllers/edit.prg", "MW_WEB_EDIT" )
  Notes      : Web: yes | API: no
 -----------------------------------------------------------*/

// ============================================================
// MW_WEB_EDIT — protected web pipeline with role "editor"
//
// Use for:
// Web routes that modify data and require the user to hold
// the "editor" role. CSRF protection is included because
// these routes typically accept form submissions.
//
// Pipeline:
// Maintenance → SecHeaders → BodyLimit → Session → CSRF
// → RequireAuth[/login] → RequireRole("editor")[/403]
//
// Maintenance      : returns 503 if server is in maintenance mode
// SecHeaders       : injects HTTP hardening headers
// BodyLimit        : rejects oversized request bodies
// Session          : loads the session from the cookie
// CSRF             : token validation for unsafe methods
// RequireAuth      : user must be logged in → cOnFail="/login"
// RequireRole      : user must have role "editor" → cOnFail="/403"
//
// On success:
// oCtx:hData["user"]  — authenticated user with editor role
//
// On failure:
// Not logged in  → router dispatches /login
// Wrong role     → router dispatches /403
//
// Typical routes:
// GET  /content/edit    → edit form (CSRF token injected)
// POST /content/save    → save action (CSRF validated)
// POST /content/delete  → delete action (CSRF validated)
// ============================================================

#INCLUDE "hix_const.ch"

FUNCTION MW_WEB_EDIT( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HIX_MwMaintenance",                  "maintenance"            ) )
   o:Add( UMiddleware():New( "HIX_MwSecHeaders",                   "sec-headers"            ) )
   o:Add( UMiddleware():New( "HIX_MwBodyLimit",                    "body-limit"             ) )
   o:Add( UMiddleware():New( "HIX_MwSession",                      "session"                ) )
   o:Add( UMiddleware():New( "HIX_MwCsrf",                         "csrf"                   ) )
   o:Add( UMiddleware():New( "HIX_MwRequireAuth",                  "require-auth", "/login" ) )
   o:Add( UMiddleware():New( {| oCtx | ( oCtx:cScope := "editor", HIX_MwHasRole( oCtx ) ) }, "require-role", "/403" ) )

RETURN o:Run()
