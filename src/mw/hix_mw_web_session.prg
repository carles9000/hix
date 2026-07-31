/*-----------------------------------------------------------
  File ......: hix_mw_web_session.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Middleware group for web routes that need a session
               but do not require the user to be authenticated.
               Typical use: login form, registration, public pages
               that need CSRF protection.
  Usage      : oSrv:AddRoutePost( "login", "/login", "controllers/login.prg", "MW_WEB_SESSION" )
  Notes      : Web: yes | API: no
 -----------------------------------------------------------*/

// ============================================================
// MW_WEB_SESSION — web pipeline with session + CSRF + auth handler
//
// Use for:
// Routes that are publicly accessible but need a session
// (login form, registration, password reset). The pipeline
// runs CSRF protection and hands off login/logout processing
// to HIX_MwAuth without enforcing that a user is present.
//
// Pipeline:
// Maintenance → SecHeaders → BodyLimit → Session → CSRF → Auth
//
// Maintenance : returns 503 if server is in maintenance mode
// SecHeaders  : injects HTTP hardening headers
// BodyLimit   : rejects oversized request bodies
// Session     : loads/creates the user session (cookie)
// CSRF        : generates token on GET, validates on POST/PUT/DELETE
// Auth        : processes login (POST /login) and logout
//
// What it does NOT do:
// Does NOT require the user to be logged in. If you need that,
// use MW_WEB_AUTH instead.
//
// Typical routes:
// GET  /login      → shows login form (CSRF token in context)
// POST /login      → Auth handles credentials, redirects or JSON
// GET  /logout     → Auth destroys session
// GET  /register   → public registration form with CSRF
// ============================================================

#INCLUDE "hix_const.ch"

FUNCTION MW_WEB_SESSION( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HIX_MwMaintenance", "maintenance" ) )
   o:Add( UMiddleware():New( "HIX_MwSecHeaders",  "sec-headers" ) )
   o:Add( UMiddleware():New( "HIX_MwBodyLimit",   "body-limit"  ) )
   o:Add( UMiddleware():New( "HIX_MwSession",     "session"     ) )
   o:Add( UMiddleware():New( "HIX_MwCsrf",        "csrf"        ) )
   o:Add( UMiddleware():New( "HIX_MwAuth",        "auth-login"  ) )

RETURN o:Run()
