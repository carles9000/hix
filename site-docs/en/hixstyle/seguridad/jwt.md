# 🎫 JWT - JSON Web Token

## What is it?

A **JWT** is a self-contained and signed token that the server issues when logging in and the client sends with each subsequent request.

- **Self-contained**: carries all user information inside (`user_id`, `role`, etc.). The server **stores nothing** between requests.
- **Signed**: HIX uses **HMAC-SHA256** with a secret key. If the client alters even one byte, the signature no longer matches and the token is rejected.
- **Stateless**: two servers with the same key validate the same token → scales horizontally without shared storage.

```
header.payload.signature

eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9   {"typ":"JWT","alg":"HS256"}
.eyJ1c2VyX2lkIjoiNDIiLCJyb2xlIjoi...    {"user_id":"42","role":"admin","exp":...}
.aBcD3f9eGgHhIi...                      HMAC-SHA256(header.payload, secret)
```

---

## When to use it

| Use case | JWT |
|---|---|
| Stateless REST API | ✅ Yes—canonical pattern |
| Mobile app calling an API | ✅ Yes |
| Microservices with shared tokens | ✅ Yes |
| SPA calling a separate backend | ✅ Yes |
| Traditional web app with login form | ❌ Use [Sessions](sesiones.md) |
| Single-use tokens (download, password reset) | ⚠️ Yes, with short `exp` |

> JWT vs Session: JWT doesn't require server storage but **cannot be invalidated** before expiration. Session is the opposite: it requires storage but you can destroy the SID and log the client out instantly.

---

## Setup

```clipper
HIX_MwJwtSetup( ;
   "super_secret_and_long_key",  ;   // cKey - HMAC secret
   3600 )                             // nExpSecs - token TTL (1h)
```

Call it **before** `oSrv:Start()`. If you don't configure it, HIX uses
`hix-secret-key` by default (⚠️ **insecure**).

---

## Issue a token in /login

```clipper
// POST /api/login
FUNCTION Main()
   LOCAL oVal, hUser, cToken

   oVal := UValidateOrFail( { ;
      "username" => "required|string", ;
      "password" => "required|string"  ;
   } )
   IF oVal == NIL ; RETURN ; ENDIF

   hUser := ModelUser( oVal:Get( "username" ), oVal:Get( "password" ) )

   IF ValType( hUser ) != "H"
      USendJson( { "error" => "invalid_credentials" }, 401 )
      RETURN
   ENDIF

   cToken := HIX_JwtEncode( { ;
      "user_id" => hUser[ "id"   ], ;
      "name"    => hUser[ "name" ], ;
      "scope"   => "read:products write:orders" ;
   } )

   USendJson( { "token" => cToken, "expires_in" => 3600 } )
RETURN
```

`HIX_JwtEncode` automatically adds standard claims:

| Claim | Value |
|---|---|
| `iss` | `"HIX"` |
| `iat` | Unix timestamp of issue |
| `exp` | `iat + nExpSecs` |

What you add (`user_id`, `scope`, `role`, ...) travels alongside.

---

## Protect a route

```clipper
// Pipeline: JWT validation -> handler
oSrv:AddRouteGet( "me", "/api/me", ;
   {|| USendJson( UContext():hData["jwt"] ) }, ;
   "HIX_MwJwt" )
```

```json
{ "name": "me", "url": "/api/me", "method": "GET",
  "action": "controllers/me.prg",
  "middleware": "HIX_MwJwt" }
```

The client must send:

```http
GET /api/me HTTP/1.1
Authorization: Bearer eyJ0eXAiOiJKV1Qi...aBcD3f
```

`HIX_MwJwt` validates the signature + `exp`, leaves the payload in
`oCtx:hData["jwt"]`, and continues. If the token is missing or invalid →
**401**.

---

## Read the payload in the controller

```clipper
PROCEDURE Main(...)
   LOCAL oCtx  := UContext()
   LOCAL hJwt  := oCtx:hData[ "jwt" ]
   LOCAL cUser := hJwt[ "user_id" ]
   LOCAL cRole := hb_HGetDef( hJwt, "role", "" )

   USendJson( { "user_id" => cUser, "role" => cRole } )
RETURN
```

---

## Scopes—authorization by operation

`HIX_MwJwtScope` requires that the `scope` claim of the token contains all the tokens (separated by space) that the route declares as necessary:

```json
{ "name": "products.list",   "url": "/api/products",        "method": "GET",
  "middleware": "HIX_MwJwt,HIX_MwJwtScope", "scope": "read:products" }

{ "name": "products.delete", "url": "/api/products/:id",    "method": "DELETE",
  "middleware": "HIX_MwJwt,HIX_MwJwtScope", "scope": "delete:products" }
```

With a token that carries `"scope" => "read:products write:orders"`:

| Route | Result |
|---|---|
| `GET /api/products` (`read:products`) | ✅ allows |
| `POST /api/orders` (`write:orders`) | ✅ allows |
| `DELETE /api/products/42` (`delete:products`) | ❌ 403—missing scope |

> Order matters: **`HIX_MwJwt` first** (leaves payload in hData), **`HIX_MwJwtScope` second** (reads it).

---

## Multiple keys—`HIX_MwJwtFactory`

If different routes use different signing keys (for example, one set for public API and another for internal API):

```clipper
LOCAL bMwApi    := HIX_MwJwtFactory( "public_key"  )
LOCAL bMwIntern := HIX_MwJwtFactory( "internal_key"  )

oSrv:AddRouteGet( "pub",     "/api/pub",     bAction, bMwApi    )
oSrv:AddRouteGet( "intern",  "/admin/data",  bAction, bMwIntern )
```

---

## Validate / decode manually

Useful for tokens outside the pipeline (for example, validating one received via WebSocket):

```clipper
LOCAL hPayload := HIX_JwtValidate( cToken )

IF hPayload == NIL
   // invalid signature or expired
   RETURN .F.
ENDIF

? hPayload[ "user_id" ], hPayload[ "exp" ]
```

---

## Refresh tokens—basic pattern

JWT cannot be invalidated before `exp`. For long-duration tokens without losing security, use **two tokens**:

| Token | TTL | Use |
|---|---|---|
| Access token | short (15 min) | Goes in every request `Authorization: Bearer ...` |
| Refresh token | long (7-30 days) | Only travels to `/refresh` endpoint to issue a new access token |

```clipper
// POST /api/refresh
FUNCTION Main()
   LOCAL cRefresh := UPost( "refresh_token", "" )
   LOCAL hPayload := HIX_JwtValidate( cRefresh, "refresh_key" )

   IF hPayload == NIL
      RETURN USendJson( { "error" => "invalid_refresh" }, 401 )
   ENDIF

   USendJson( { ;
      "token" => HIX_JwtEncode( { "user_id" => hPayload["user_id"] } ) ;
   } )
RETURN
```

---

## JWT vs Session—quick table

| | JWT | Session |
|---|---|---|
| Server storage | ❌ No | ✅ Yes (memory/file) |
| Immediate invalidation | ❌ Wait for `exp` or blacklist | ✅ `Destroy()` |
| Horizontal scaling | ✅ No shared state | ⚠️ Needs storage or session affinity |
| Cross-domain / mobile | ✅ Bearer header | ❌ Cookie tied to domain |
| CSRF | ❌ Not applicable (not a cookie) | ⚠️ Mandatory |
| Size per request | ~500-1000 bytes | ~50 bytes (only SID) |
| Revoke issued tokens | ❌ Difficult without blacklist | ✅ Easy |

---

## Best practices

1. **Long and rotatable secret key.** Minimum 32 random bytes.
   Change it across environments (`dev` / `prod`).
2. **Short expiration.** 15-60 min for access, refresh token separately.
   Eternal JWTs are a security hole.
3. **Don't put sensitive data in the payload.** The payload is base64,
   **not encrypted**—anyone can read it. It's only tamper-proof.
4. **HTTPS always.** The Bearer travels in every request—without [SSL](ssl.md) anyone can intercept it.
5. **Don't mix JWT with cookies.** If you go JWT, use only the `Authorization` header—putting the token in a cookie brings back the CSRF problems JWT avoids.
6. **Blacklist for logout.** If you need to invalidate before `exp`, save the revoked `jti` (JWT ID) in Redis and check them in the middleware.

---

## Internal architecture

Since version 2026-07-14, JWT code is split into two files with well-defined responsibilities:

| File | Layer | Content |
|---|---|---|
| `src/hix_jwt.prg` | **Engine** (pure) | `HIX_JwtEncode`, `HIX_JwtValidate`, `HIX_MwJwtSetup`, `HIX_JwtDefaultKey`, `HIX_JwtDefaultExp`, and private helpers for HMAC-SHA256 and Base64Url signing. No router dependencies. |
| `src/mw/hix_mw_jwt.prg` | **Middleware** | `HIX_MwJwt`, `HIX_MwJwtFactory`, `HIX_MwJwtScope`. Pipeline only: extracts Bearer, invokes the engine, and writes `oCtx:hData["jwt"]`. |

Advantages of the split:

- The engine can be reused outside the pipeline (CLI, workers, validating
  tokens received via WebSocket) without loading the middleware.
- Configuration STATICs (`s_cJwtKey`, `s_nJwtExpSec`) live in the engine.
  The middleware consults them via `HIX_JwtDefaultKey()` / `HIX_JwtDefaultExp()`
  (STATICs in Harbour are file-scoped).
- Changes to the pipeline (403/401 handling, telemetry) don't force
  recompiling the engine, and vice versa.

> The public API is unchanged: `HIX_MwJwtSetup`, `HIX_JwtEncode`,
> `HIX_JwtValidate`, `HIX_MwJwt`, `HIX_MwJwtFactory`, and `HIX_MwJwtScope`
> keep the same name and signature as before the split.
