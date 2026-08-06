# Security and Middlewares

The example separates security into two layers:

1. **HIX native middlewares** (`HIX_Mw*`) — generic building blocks: session, authentication, role-based authorization, CSRF, rate-limit.
2. **Project middleware groups** (`MyApp*`) — combine the building blocks into reusable chains that routes reference by name.

Routes never declare loose native MWs; they always invoke a group (`MyAppAuth`, `MyAppAuthRole`, `MyAppAuthRoleEdit`, `MyAppLogin`). This way, changing the security policy of a zone is done in a single place.

---

## The Four Project Groups

Defined in `www/middlewares/*.prg` — all follow the same pattern `UBaseMiddleware` + `Add()` + `Run()`.

### `MyAppAuth` — Basic Authenticated Zone

File: `myappauth.prg`

```harbour
FUNCTION MyAppAuth( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession" ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"  ) )
RETURN o:Run()
```

**Chain**: `Session → IsAuth`
**Purpose**: protect any page that requires "being logged in", regardless of role.
**Rejection**: if no valid session → **302 → /login**.
**Routes that use it**: `/main`, `/logout`, `/module_a`, `/module_b`, `/module_c`.

---

### `MyAppAuthRole` — Authenticated Zone + Scope Control (GET)

File: `myappauthrole.prg`

```harbour
FUNCTION MyAppAuthRole( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession" ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"  ) )
   o:Add( UMiddleware():New( "HIX_MwHasRole" ) )
RETURN o:Run()
```

**Chain**: `Session → IsAuth → HasRole`
**Purpose**: authenticated GETs with scope-based permission (`customers:show`, `customers:edit`, …).
**Rejection**:
- No session → **302 → /login**.
- Session present but missing the scope → **403 Forbidden**.

**Routes that use it**: `GET /customer/search`, `GET /customer/create`, `GET /customer/:id`, `GET /customer/:id/edit`.

Because these are GETs, CSRF is not checked (GETs do not modify state).

---

### `MyAppAuthRoleEdit` — Authenticated Zone + Scope + CSRF (POST)

File: `myappauthedit.prg`

```harbour
FUNCTION MyAppAuthRoleEdit( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession"   ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"    ) )
   o:Add( UMiddleware():New( "HIX_MwHasRole"   ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
RETURN o:Run()
```

**Chain**: `Session → IsAuth → HasRole → CsrfCheck`
**Purpose**: POSTs that modify state in the customers module.
**Rejection** (in evaluation order):
- No session → **302 → /login**.
- Session present but missing the scope → **403 Forbidden**.
- Session and scope present but no valid CSRF token → **302 → /login** (configurable redirect).

**Routes that use it**: `POST /customer/store`, `POST /customer/:id/update`, `POST /customer/:id/delete`.

Important detail about order: `HasRole` runs **before** `CsrfCheck`. Observable consequence in the test suite (test 23): a `POST /customer/store` as `carles` (without `customers:create`) returns **403** even though there is no CSRF token either, because `HasRole` cuts the chain first.

---

### `MyAppLogin` — Hardened Login (POST)

File: `myapplogin.prg`

```harbour
FUNCTION MyAppLogin( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession"   ) )
   o:Add( UMiddleware():New( "HIX_MwRateLimit" ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
RETURN o:Run()
```

**Chain**: `Session → RateLimit → CsrfCheck`
**Purpose**: protect `POST /auth` against brute force and against submissions from third-party forms.
**Rejection**:
- Rate-limit exceeded → **429 Too Many Requests**.
- No valid CSRF token → **302 → /login**.

**Note** (from the file's own comment): the rate-limit is global, applied only to `/auth` in this example. If `MyAppLogin` were reused on another route, both would share the same counter; in that case, use a factory (`HIX_MwRateLimitFactory( ... )`) to instantiate independent counters per route.

---

## The Building Blocks: HIX Native Middlewares Used Here

| Native MW | What it does | Config | Setup |
|-----------|--------------|--------|-------|
| `HIX_MwSession`   | Retrieves/creates session, reads `FENIXSID` cookie, puts the session hash in `oCtx:hData["session"]`. | cookie name, TTL, GC, storage | `www/middlewares/config.json > setup.session` |
| `HIX_MwIsAuth`    | Checks that `session["_auth_user"]` exists. If not, redirects to `/login`. | user key, redirect | `setup.auth` |
| `HIX_MwHasRole`   | Checks the route's `scope` against the user's `roles` (format `resource:action`). See [3-users.en.md](3-users.en.md). | uses `setup.auth.roles_key` | `setup.auth` |
| `HIX_MwCsrfCheck` | Verifies CSRF token (stateless HMAC). Tied to the session + `keys.csrf` from `www/config.json`. | redirect, TTL | `setup.csrf` |
| `HIX_MwRateLimit` | Per-IP counter in a sliding window. Always active — global configuration. | `ip_per_min`, `window_s` | `setup.ratelimit` |

`HIX_MwSession` is first in every chain because the rest depend on the context having a session available.

---

## Declarative Setup — `www/middlewares/config.json`

A single JSON file manages which `.prg` files to load and with which parameters to initialize the native MWs:

```json
{
  "load": [
    "myappauth.prg",
    "myappauthrole.prg",
    "myappauthedit.prg",
    "myapplogin.prg"
  ],
  "setup": {
    "auth": {
      "session_user_key": "_auth_user",
      "roles_key":        "roles",
      "redirect_login":   "/login",
      "redirect_accept":  "/main"
    },
    "session": {
      "cookie":   "FENIXSID",
      "ttl":      3600,
      "max":      100,
      "storage":  "memory"
    },
    "csrf": {
      "redirect": "/login",
      "ttl":      3600
    },
    "ratelimit": {
      "ip_per_min": 300,
      "window_s":   60
    }
  }
}
```

Startup behavior:

1. `load` — each `.prg` is compiled to HRB and kept resident. Its functions (`MyAppAuth`, `MyAppLogin`, …) become available for the router to invoke when `web.json` specifies `"middleware": "MyAppAuth"`.
2. `setup.auth` — exposes the keys via `UMwConfig("auth", ...)`. Used in `controllers/auth.prg` to avoid hardcoding the session key and the redirect route.
3. `setup.session` — calls `HIX_MwSessionSetup( "FENIXSID", 3600, 100, "memory", ... )`.
4. `setup.csrf` — calls `HIX_MwCsrfSetup( "/login", NIL, NIL, NIL, 3600 )` (TTL of 1 hour — token expires even if the session is still alive).
5. `setup.ratelimit` — calls `HIX_MwRateLimitSetup( 300, 60 )` (300 requests/IP/minute).

**Advantage**: you can change any security parameter without recompiling `app.exe`. Just restart.

---

## Session: Cookie and Storage

- Cookie: `FENIXSID` — HttpOnly, SameSite=Lax, Path=/.
- TTL: **3600 s** (1 hour).
- Storage: **in-memory** (lost when the server restarts).
- Switch to file storage: `www/middlewares/config.json > setup.session.storage = "file"` + add `path`.

---

## CSRF: How It Is Issued and Verified

**Issuing** — in every form in the app, the template uses the `@csrf` directive:

```html
<form method="post" action="/auth">
  @csrf
  <input name="username">
  <input name="password" type="password">
  <button>Enter</button>
</form>
```

`@csrf` (or `UCsrfToHtml()` in a renderer) inserts:

```html
<input type="hidden" name="_csrf" value="TOKEN_HMAC_STATELESS">
```

The token is an HMAC of the current SID + secret (`keys.csrf` from `www/config.json`) + timestamp. It is **not** stored in the session — it is recomputed on each verification.

**Verification** — `HIX_MwCsrfCheck` recomputes the HMAC and compares. If:
- No token present → 302 → `/login`.
- Valid token but too old (exceeded TTL 3600 s) → 302 → `/login`.
- Valid and fresh token → continues the chain.

In the test suite (tests 15b, 07), a POST without `_csrf` gives **302** — not 403. This is the typical rejection from `CsrfCheck`.

---

## Rate Limit

- Global per-IP counter, sliding window of 60 s.
- 300 requests per IP in 60 s → **429**.
- In this example it only applies to `POST /auth`. If you were to reuse `MyAppLogin` for another route or recycle the rate-limit in `MyAppAuthRoleEdit`, all routes would share the same counter; for independent counters use `HIX_MwRateLimitFactory()`.
- The value was initially `5/60` (hardened against brute force); it was raised to `300/60` so the test suite can be re-run many times without being blocked. In production, lower it (`5/60` or `10/60`).

---

## Adding a New Group

Example: protect an "internal API" zone with IP whitelist + JWT + rate-limit:

1. Create `www/middlewares/myapiinternal.prg`:

```harbour
FUNCTION MyApiInternal( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwIpWhitelist" ) )
   o:Add( UMiddleware():New( "HIX_MwJwt"         ) )
   o:Add( UMiddleware():New( "HIX_MwRateLimit"   ) )
RETURN o:Run()
```

2. Add it to `www/middlewares/config.json > load`.
3. If setup is needed: add a `jwt` / `ipwhitelist` section under `setup`.
4. Reference it in `web.json`: `"middleware": "MyApiInternal"`.

No changes to `src/app.prg` or recompilation required.
