/*-----------------------------------------------------------
  File ......: hix_mw_api_jwt.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Middleware group for JWT-authenticated API routes.
               Validates the Bearer token, applies rate limiting,
               CORS, and request logging. All failures respond
               with JSON (no redirects).
  Usage      : oSrv:AddRouteGet( "list", "/api/products", "controllers/api_list.prg", "MW_API_JWT" )
  Notes      : Web: no | API: yes
 -----------------------------------------------------------*/

// ============================================================
// MW_API_JWT — authenticated REST API pipeline (Bearer token)
//
// Use for:
// Any API endpoint that requires a valid JWT in the
// Authorization: Bearer header. Designed for stateless
// authentication — no cookies, no sessions.
//
// Pipeline:
// Maintenance → CORS → SecHeaders → RateLimit → BodyLimit
// → ReqLog → Jwt[401 JSON] → RequireAuth[401 JSON]
//
// Maintenance : returns 503 if server is in maintenance mode
// CORS        : injects Access-Control-* headers; handles OPTIONS preflight
// SecHeaders  : injects HTTP hardening headers
// RateLimit   : rejects excess requests with 429
// BodyLimit   : rejects oversized request bodies with 413
// ReqLog      : logs METHOD + path + IP
// Jwt         : validates Bearer token; 401 JSON if missing/invalid
// RequireAuth : checks hData["jwt"] was set; 401 JSON if absent
//
// All failures return JSON errors — no redirects. Suitable for
// consumption by mobile apps, SPAs, and backend services.
//
// On success:
// oCtx:hData["jwt"]   — the decoded JWT payload
// oCtx:hData["user"]  — same (set by RequireAuth)
// UCurrentUser()      — same, accessible in route handlers
//
// Typical routes:
// GET  /api/products         → list products
// POST /api/products         → create product
// PUT  /api/products/:id     → update product
// DELETE /api/products/:id   → delete product
// ============================================================

#INCLUDE "hix_const.ch"

FUNCTION MW_API_JWT( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HIX_MwMaintenance", "maintenance"  ) )
   o:Add( UMiddleware():New( "HIX_MwCors",        "cors"         ) )
   o:Add( UMiddleware():New( "HIX_MwSecHeaders",  "sec-headers"  ) )
   o:Add( UMiddleware():New( "HIX_MwRateLimit",   "rate-limit"   ) )
   o:Add( UMiddleware():New( "HIX_MwBodyLimit",   "body-limit"   ) )
   o:Add( UMiddleware():New( "HIX_MwReqLog",      "req-log"      ) )
   o:Add( UMiddleware():New( "HIX_MwJwt",          "jwt"          ) )
   o:Add( UMiddleware():New( "HIX_MwJwtScope",    "jwt-scope"    ) )
   o:Add( UMiddleware():New( "HIX_MwRequireAuth", "require-auth" ) )

RETURN o:Run()
