# Middleware - Catalog

Complete catalog of middlewares included in HIX. All follow the standard pattern:
a function `HIX_MwXxx( oCtx )` ready to add to the pipeline, and in most
cases a variant `HIX_MwXxxFactory( params )` that returns a codeblock with
its own configuration for a specific route.

| Legend | |
|---|---|
| **Web** | Recommended use in web applications (HTML, forms, session) |
| **API** | Recommended use in APIs (JSON, JWT, M2M) |
| **Setup** | Function to call before `oSrv:Start()` to configure the statics |
| **Factory** | Variant that returns a codeblock with independent configuration per route |

All pre-built HIX middleware are in the `/src/mw` folder

---

## Infrastructure

### 🚧 `HIX_MwMaintenance`

| | |
|---|---|
| **Description** | Managed maintenance mode: cuts all traffic with `503` and JSON `{ "error": "maintenance" }` during deployments or planned outages. |
| **Function** | Activatable by programmatic flag or by the existence of a lock file on disk (toggle without restart). |
| **Setup** | `HIX_MwMaintenanceSetup( lActive, cFile )` |
| **Factory** | `HIX_MwMaintenanceFactory( lActive )` — flag only, no lock file |
| **Web** | Yes — show friendly 503 page |
| **API** | Yes — clients should retry with backoff |
| **Example** | `HIX_MwMaintenanceSetup( .F., "maintenance.lock" )` → create the file activates the block. |

---

### 📋 `HIX_MwReqLog`

| | |
|---|---|
| **Description** | Logs each incoming request with `METHOD /path IP` in the HIX logger. Never blocks, always `.T.`. |
| **Function** | Writes one line per request before executing the handler. Configurable level (DEBUG/INFO/WARN). |
| **Setup** | `HIX_MwReqLogSetup( nLevel )` |
| **Factory** | `HIX_MwReqLogFactory( nLevel )` |
| **Web** | Yes — useful in dev/staging |
| **API** | Yes — essential for audit in production |
| **Example** | `HIX_MwReqLogSetup( HIX_LOG_INFO )` → writes `"GET /api/users 192.168.1.10"`. |

---

## HTTP Security

### 🔐 `HIX_MwSecHeaders`

| | |
|---|---|
| **Description** | HTTP hardening headers on each response. Never blocks, only enriches. |
| **Function** | Injects `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Strict-Transport-Security: max-age=31536000`, and `Content-Security-Policy`. |
| **Setup** | `HIX_MwSecHeadersSetup( cCSP )` |
| **Factory** | `HIX_MwSecHeadersFactory( cCSP )` |
| **Web** | Critical — include on any production site |
| **API** | Recommended — prevents misuse of responses as web content |
| **Example** | `HIX_MwSecHeadersSetup( "default-src 'self'; script-src 'self' 'nonce-abc'" )` |

---

### 🌐 `HIX_MwCors`

| | |
|---|---|
| **Description** | Complete CORS management for APIs consumed from the browser. |
| **Function** | Injects `Access-Control-*` headers on each response and automatically responds with `204` to preflight `OPTIONS`. |
| **Setup** | `HIX_MwCorsSetup( cOrigin, cMethods, cHeaders )` |
| **Factory** | Not applicable |
| **Web** | Optional — rarely needed in same-origin |
| **API** | Essential — any cross-domain or public API |
| **Example** | `HIX_MwCorsSetup( "https://app.com", "GET,POST,PUT", "Content-Type,Authorization" )` |

---

### 📦 `HIX_MwBodyLimit`

| | |
|---|---|
| **Description** | Protects against abusive uploads by reading `Content-Length` before processing the body. |
| **Function** | Rejects with `413 payload_too_large` if the declared size exceeds the maximum. Default: 1 MB. |
| **Setup** | `HIX_MwBodyLimitSetup( nMax )` (in bytes) |
| **Factory** | `HIX_MwBodyLimitFactory( nMax )` — specific limit per route |
| **Web** | Yes — protects forms and file uploads |
| **API** | Yes — prevents abuse with large payloads |
| **Example** | `HIX_MwBodyLimitSetup( 2 * 1024 * 1024 )` → maximum 2 MB globally. |

---

### 🚦 `HIX_MwRateLimit`

| | |
|---|---|
| **Description** | Request rate limiter per IP in fixed window. Thread-safe with mutex. |
| **Function** | Counts requests per IP in an N-second window. Returns `429` when exceeding the maximum. Exposes the counter in `oCtx:hData["rate_count"]`. |
| **Setup** | `HIX_MwRateLimitSetup( nMax, nWindowSecs )` |
| **Factory** | `HIX_MwRateLimitFactory( nMax, nWindowSecs )` — specific limit per route |
| **Web** | Useful on login/register forms |
| **API** | Essential for public or unauthenticated endpoints |
| **Example** | `HIX_MwRateLimitSetup( 100, 60 )` → 100 req/min per IP. For strict login: `HIX_MwRateLimitFactory( 5, 60 )`. |

---

## Sessions

### 🍪 `HIX_MwSession`

| | |
|---|---|
| **Description** | Foundation of any stateful web flow. Required before `MwAuth`, `MwIsAuth`, `MwRequireAuth`, and `MwCsrf`. |
| **Function** | Loads the session from the `HIXSID` cookie (configurable), persists it according to backend, exposes the data in `oCtx:hData["session"]` and the SID in `oCtx:hData["_sid"]`. |
| **Setup** | `HIX_MwSessionSetup( cName, nTtl, nGcEvery, cStorage, cPath, cPrefix, lCrypt, cSeed, nLifeDays )` |
| **Backends** | `"memory"` (volatile, default) or `"file"` (persistent on disk) |
| **Apache LB** | `HIX_MwSessionSetRoute( "i1" )` adds suffix to the SID for `stickysession=HIXSID`. |
| **Web** | Essential for any flow with login + cookie |
| **API** | No — use JWT instead |
| **Example** | `HIX_MwSessionSetup( "MISID", 3600, 60, "file", "sessions/" )` |

---

## Authentication

### 🔓 `HIX_MwAuth`

| | |
|---|---|
| **Description** | Manages the complete login and logout flow with session. Requires `HIX_MwSession` before. |
| **Function** | If the request is `POST` to the login route, reads credentials from the body (form or JSON), calls the `bValidate` codeblock, and if it validates, saves the user to session. If it's the logout route, destroys the session. |
| **Setup** | `HIX_MwAuthSetup( hConfig )` with `bValidate`, `cLoginRoute`, `cLogoutRoute`, `cUserField`, `cPassField`, `cRedirectOk`, `cRedirectFail`, `cSessionKey` |
| **Factory** | Not applicable |
| **Web** | Yes — primary pattern |
| **API** | No — for login in API use JWT directly |
| **Example** | `HIX_MwAuthSetup( { "bValidate" => {\|u,p\| MyValidate(u,p)}, "cLoginRoute" => "/login" } )` |

---

### 🪙 `HIX_MwJwt`

| | |
|---|---|
| **Description** | Stateless authentication by Bearer token HS256. Ideal for APIs, mobile, and SPAs. |
| **Function** | Extracts the token from `Authorization: Bearer xxx`, validates HMAC-SHA256 signature and expiration (`exp`), and deposits the complete payload in `oCtx:hData["jwt"]`. Returns `401` if it fails. |
| **Setup** | `HIX_MwJwtSetup( cKey, nExpSecs )` |
| **Factory** | `HIX_MwJwtFactory( cKey )` — different key per route (multi-tenant, partners) |
| **Helpers** | `HIX_JwtEncode( hData )` generates token on login. `HIX_JwtValidate( cToken )` validates outside the pipeline. |
| **Web** | Optional — prefer `MwSession` with CSRF |
| **API** | Yes — preferred stateless mechanism |
| **Example** | `HIX_MwJwtSetup( "mi-clave-secreta", 3600 )` → `Authorization: Bearer eyJ...` |

---

### 🗝️ `HIX_MwApiKey`

| | |
|---|---|
| **Description** | M2M authentication by static key. Simple alternative to JWT for internal services or partners. |
| **Function** | Validates the `X-Api-Key` header against a hash of allowed keys (O(1) lookup). Exposes the accepted key in `oCtx:hData["api_key"]` for downstream logging. |
| **Setup** | `HIX_MwApiKeySetup( aKeys )` |
| **Factory** | `HIX_MwApiKeyFactory( aKeys )` — private set of keys for a specific route |
| **Web** | Not applicable — users don't have API keys |
| **API** | Standard for M2M and partners; combine with `MwRateLimit` for anti-brute-force |
| **Example** | `HIX_MwApiKeySetup( { "svc-key-1", "partner-key-2" } )` |

---

## Authorization (guards)

### 🛡️ `HIX_MwRequireAuth`

| | |
|---|---|
| **Description** | Universal route guard: blocks with `401` if no authenticated user is present. Accepts both session and JWT. |
| **Function** | Searches for the user first in `oCtx:hData["session"]` (key `_auth_user` by default). If not, tries `oCtx:hData["jwt"]` (fallback). If neither is found, responds with `401`. If it passes, exposes the user in `oCtx:hData["user"]` and accessible via `UCurrentUser()`. |
| **Setup** | Not required (uses the session configured by `MwAuthSetup`) |
| **Factory** | Not applicable |
| **Web** | Yes — protect routes that require login (with session) |
| **API** | Yes — protect endpoints that require JWT |
| **Example** | Web pipeline: `"HIX_MwSession,HIX_MwRequireAuth"`. API pipeline: `"HIX_MwJwt,HIX_MwRequireAuth"`. |

---

### 👤 `HIX_MwIsAuth`

| | |
|---|---|
| **Description** | Simple session guard — alternative to `RequireAuth` when you only work with sessions (without JWT). Redirects to `/login` (302) instead of responding with JSON 401. |
| **Function** | Reads the user from `oCtx:hData["session"]` with the configured key (default `_auth_user`). If it doesn't exist, redirects to the URL of `redirect_login` (configurable in `config.json` section `auth`). |
| **Setup** | Via `config.json`: section `auth` → `session_user_key`, `redirect_login` |
| **Factory** | Not applicable |
| **Web** | Yes — preferable when you want redirect instead of JSON 401 |
| **API** | No — use `RequireAuth` |
| **Example** | `o:Add( UMiddleware():New( "HIX_MwIsAuth" ) )` after `HIX_MwSession`. |

---

### 🎭 `HIX_MwHasRole`

| | |
|---|---|
| **Description** | Role guard and granular operations. Reads the required role from the route's `cScope`. Must come after a middleware that has loaded the user (`MwIsAuth` or `MwRequireAuth`). |
| **Function** | Compares `oCtx:cScope` (format `"role"` or `"role:operation"`) against the user's roles hash. Full access if the role value is empty; granular if it lists operations separated by `;`. Responds with `403` if it fails. |
| **Setup** | Via `config.json`: section `auth` → `roles_key` (default `"roles"`) |
| **Factory** | Not applicable — the difference between routes is made with the `cScope` parameter of the route |
| **Web** | Yes |
| **API** | Yes |
| **Example** | `oSrv:AddRouteGet( "del", "/users/:id", action, "MyAuth", "admin:delete" )` → requires role `admin` with operation `delete`. |

---

### 🎯 `HIX_MwJwtScope`

| | |
|---|---|
| **Description** | Scope guard for JWT (OAuth 2.0 style). Reads the required scope from the route's `cScope` and compares it with the `scope` claim of the token. |
| **Function** | If `cScope` is empty, it passes. If not, verifies that each token (separated by space) in `cScope` is present in the JWT's `scope` claim. Responds with `403` if any is missing. |
| **Setup** | Not required |
| **Factory** | Not applicable |
| **Web** | Not common |
| **API** | Yes — scope control in JWT APIs |
| **Example** | Token with `"scope" => "read:products write:orders"`. Route `"read:products"` → passes. Route `"delete:products"` → 403. |

---

## CSRF

### 🔏 `HIX_MwCsrf`

| | |
|---|---|
| **Description** | Session-based CSRF protection. Generates a random token per session and validates it on unsafe methods (POST/PUT/DELETE/PATCH). Requires `HIX_MwSession` before. |
| **Function** | On GET/HEAD/OPTIONS methods, generates the token if it doesn't exist and exposes it as `oCtx:hData["csrf_token"]` (to embed in forms). On unsafe methods, reads it from the `X-CSRF-Token` header or from the `_csrf` form field and compares it with the one in the session. Returns `403` if it doesn't match. |
| **Setup** | `HIX_MwCsrfSetup( cRedirect, cHeader, cField, cSecret, nLapsus )` |
| **Factory** | Not applicable |
| **Web** | Essential — always include in webs with session and forms |
| **API** | Not applicable — use JWT (not automatically sent by the browser) |
| **Example** | Template embeds `{{ oCtx:hData["csrf_token"] }}` in `<input name="_csrf">`. POST without token → `403`. |

---

### 🔐 `HIX_MwCsrfCheck`

| | |
|---|---|
| **Description** | Stateless variant of CSRF based on HMAC. Validates signed tokens without needing a session. |
| **Function** | Safe methods (GET/HEAD/OPTIONS) pass. On unsafe methods, reads the token from the header or field and verifies the HMAC signature with the application key. Doesn't require a session. |
| **Setup** | Shares the HMAC key and configuration with `MwCsrf` |
| **Factory** | Not applicable |
| **Web** | Yes — alternative to `MwCsrf` when you don't want to maintain state in session |
| **API** | Not common |
| **Example** | `oSrv:AddRoutePost( "auth", "/auth", "controllers/auth.prg", "HIX_MwCsrfCheck" )` with token generated by `@csrf` / `UCsrfToHtml()` in the form. |

---

## Quick summary by scenario

| Scenario | Typical stack |
|---|---|
| **Public static web** | `HIX_MwReqLog`, `HIX_MwSecHeaders`, `HIX_MwBodyLimit` |
| **Web with login + session** | + `HIX_MwSession`, `HIX_MwCsrf`, `HIX_MwAuth`, `HIX_MwRequireAuth` (or `HIX_MwIsAuth`) |
| **Web with roles** | + `HIX_MwHasRole` (declare `cScope` on the route) |
| **Public API** | `HIX_MwReqLog`, `HIX_MwSecHeaders`, `HIX_MwCors`, `HIX_MwRateLimit`, `HIX_MwBodyLimit` |
| **Authenticated API (JWT)** | + `HIX_MwJwt`, `HIX_MwRequireAuth`, `HIX_MwJwtScope` |
| **API M2M / partners** | + `HIX_MwApiKey`, `HIX_MwRequireAuth` |
| **Deployment/outage mode** | `HIX_MwMaintenance` global (at the start of the pipeline) |
