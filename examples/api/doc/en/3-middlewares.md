# Middlewares — Strategy and architecture

## General philosophy

These examples are pure APIs (no HTML, no sessions). All endpoints return JSON,
all clients send `Authorization: Bearer`. The middleware strategy reflects that:
**a single file** with atomic pieces that combine into **composite guards**, and
each route declares only one guard.

This solves a limitation of the HIX router: the `middleware` field in `api.json`
accepts **a single function name**. Instead of inventing list syntax, guards
compose internally everything needed for that level of access.

---

## System layers

```
┌──────────────────────────────────────────────────────────────┐
│  HIX (library)                                               │
│  HIX_MwRateLimit   — throttle per IP (fixed window)         │
│  HIX_MwCors        — CORS preflight + headers               │
│  HIX_MwJwt         — JWT validation (used internally)       │
├──────────────────────────────────────────────────────────────┤
│  myws_guards.prg  (app)                                      │
│  MyWsSecHeaders    — HTTP hardening headers                  │
│  MyWsEnforceJson   — rejects POST/PUT/PATCH without JSON    │
│  MyWsBearer        — extracts and validates JWT Bearer       │
│  MyWsRequireScope  — checks OAuth2 scope declared on route  │
│  MyWsRateLimitUser — throttle per user (JWT sub)            │
├──────────────────────────────────────────────────────────────┤
│  Composite guards (= access "profiles")                      │
│  MyWsGuardPublic   — unauthenticated endpoints              │
│  MyWsGuardAuth     — authenticated endpoints, no scope      │
│  MyWsGuardScope    — authenticated + specific scope         │
└──────────────────────────────────────────────────────────────┘
```

---

## Atomic middlewares

### HIX built-in (configured in `config.json > setup`)

| Middleware          | What it does                                          |
|---------------------|-------------------------------------------------------|
| `HIX_MwRateLimit`   | Global throttle per IP. Default: 300 req/min          |
| `HIX_MwCors`        | OPTIONS preflight + CORS headers on every response    |

### Application layer (`myws_guards.prg`)

| Middleware            | What it does                                              |
|-----------------------|-----------------------------------------------------------|
| `MyWsSecHeaders`      | Adds `X-Content-Type-Options`, `X-Frame-Options`,         |
|                       | `Referrer-Policy`, `Permissions-Policy`, `HSTS`           |
| `MyWsEnforceJson`     | If the method has a body (POST/PUT/PATCH), requires       |
|                       | `Content-Type: application/json`. Returns 415             |
| `MyWsBearer`          | Reads `Authorization: Bearer <token>`, validates with     |
|                       | `HIX_JwtValidate`. Populates `oCtx:hData["user"]`         |
| `MyWsRequireScope`    | Reads `oCtx:cScope` (declared on the route) and checks    |
|                       | that the JWT `scope` claim includes it. → 403             |
| `MyWsRateLimitUser`   | Fixed throttle per JWT `sub` (specific user).             |
|                       | Adds `X-RateLimit-*` headers. Default: 600 req/min        |

### Cross-cutting helper

| Function         | What it does                                                    |
|------------------|-----------------------------------------------------------------|
| `AuditLog(e, h)` | Writes a JSON line to `logs/audit.log`. Thread-safe.            |
|                  | Includes timestamp, IP, path, method, and JWT sub if present    |

---

## Composite guards

Guards are functions that chain the atomic middlewares in strict order.
If one fails, the chain stops and the response has already been sent.

### `MyWsGuardPublic` — anonymous endpoints

```
HIX_MwRateLimit → HIX_MwCors → MyWsSecHeaders → MyWsEnforceJson
```

Used on: `GET /health`, `GET /time`, `POST /login`, `POST /refresh`.

No authentication required. Still protects against IP flooding,
CORS issues, and misconfigured clients.

### `MyWsGuardAuth` — authenticated endpoints

```
HIX_MwRateLimit → HIX_MwCors → MyWsSecHeaders → MyWsEnforceJson
→ MyWsBearer → MyWsRateLimitUser
```

Used on: `POST /logout`.

Requires a valid JWT. Applies additional per-user throttle.
No scope check: any authenticated user can access.

### `MyWsGuardScope` — authenticated + required scope

```
HIX_MwRateLimit → HIX_MwCors → MyWsSecHeaders → MyWsEnforceJson
→ MyWsBearer → MyWsRequireScope → MyWsRateLimitUser
```

Used on: `/me`, `/customers/*`.

The required scope is declared on the route (`api.json`), not in the guard.
This allows a single guard to serve multiple resources with different scopes.

---

## Route and scope declaration (`api.json`)

```json
{ "name": "customer.list",
  "url":        "/customers",
  "action":     "controllers/list@customer.prg",
  "method":     "GET",
  "middleware": "MyWsGuardScope",
  "scope":      "customers:read" }
```

The scope convention follows OAuth2 style: `resource:action`.
Current scopes:

| Scope               | Access                       |
|---------------------|------------------------------|
| `me:read`           | Own user profile             |
| `customers:read`    | List and view customers      |
| `customers:write`   | Create and update customers  |
| `customers:delete`  | Delete customers             |

---

## Configuration (`middlewares/config.json`)

HIX middlewares are configured via `setup`. Application middlewares
(`myws_guards.prg`) read their config at runtime via `UMwConfig(section, key, default)`.

```json
{
  "load":  [ "myws_guards.prg" ],
  "setup": {
    "jwt":        { "exp": 900, "key_ref": "jwt", "issuer": "fenix.ws" },
    "cors":       { "origin": "*", "methods": "GET,POST,OPTIONS,HEAD",
                    "headers": "Authorization,Content-Type,X-Request-Id" },
    "ratelimit":  { "ip_per_min": 300, "window_s": 60 },
    "secheaders": { "hsts": "max-age=31536000; includeSubDomains",
                    "x_content_type": "nosniff", "x_frame": "DENY",
                    "referrer_policy": "no-referrer",
                    "permissions": "geolocation=(), camera=(), microphone=()" }
  }
}
```
