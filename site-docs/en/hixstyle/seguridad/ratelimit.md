# 🚦 Rate Limit

A **rate limiter** counts how many requests arrive from each IP in a
time window. If an IP exceeds the limit → **429 Too Many Requests**.

It helps with:

- **Cutting brute force** on `/login` (attacker trying passwords).
- **Protecting public APIs** from scrapers / bots.
- **Stabilizing the server** when a client misbehaves.

```
IP 1.2.3.4    100 req in 60s   -> counter <= 100  -> ✅ passes
IP 1.2.3.4    101 req in 60s   -> counter > 100   -> ❌ 429 Too Many Requests
                 ⏱ window resets after 60s
```

---

## Algorithm

HIX uses **fixed window per IP** - the counter resets completely when
the window expires:

```
00:00 ─────────────── 01:00 ─────────────── 02:00 ─────
  IP X = 0              IP X reset            IP X reset
  ↓ requests ↑          ↓ requests ↑          ↓ requests ↑
  count 1..100          back to 1..100        back to 1..100
```

| Characteristic | Detail |
|---|---|
| Grouped by | IP (`oReq:cIP`) |
| Counts | Any request, regardless of route |
| Resets when | `nWindowSecs` expires from first request of that IP |
| Penalty | **429** immediately, no waiting |

> ⚠️ Fixed window limitation: right at window change, an IP can squeeze
> `2 × nMax` requests (end of window N and start of N+1). For normal traffic
> it's irrelevant; if you need exact precision, implement sliding window separately.

---

## Setup

```clipper
HIX_MwRateLimitSetup( ;
   100,    ;   // nMax - maximum requests
   60 )        // nWindowSecs - window seconds
```

Defaults: **60 req / 60 s** (1 req/second average).

Call before `oSrv:Start()`. The call initializes the shared hash
and the mutex protecting it.

---

## Activation

### Global - entire app

```clipper
HIX_MwRateLimitSetup( 100, 60 )
oSrv:Use( "HIX_MwRateLimit" )
```

Every request goes through here, whatever route.

### Per route

```clipper
oSrv:AddRouteGet( "api", "/api/data", bAction, "HIX_MwRateLimit" )
```

```json
{ "name": "api.data", "url": "/api/data", "method": "GET",
  "action": "controllers/api/data.prg",
  "middleware": "HIX_MwRateLimit" }
```

> In "global + per route" mode, the **same counter** increments in both
> places. If you want separate counters (e.g. global 100/min but
> login 5/min) use the factory.

---

## Factory - independent limit per route

`HIX_MwRateLimitFactory( nMax, nWindowSecs )` returns a codeblock with
its own configuration:

```clipper
LOCAL bMwLogin := HIX_MwRateLimitFactory( 5, 60 )    // 5 attempts/min

oSrv:AddRoutePost( "login", "/login", bActionLogin, bMwLogin )
```

> ⚠️ Internally all factories and the global **share** the counter hash.
> What changes is `nMax`/`nWindowSecs` per call. Each increment from any
> middleware adds to the same IP counter. For completely independent counters
> you need to write your own middleware.

---

## Behavior when rejecting

When an IP exceeds the limit:

```clipper
HIX_HttpError( oCtx:oReq, 429 )      // 429 Too Many Requests
oCtx:lHandled := .T.
RETURN .F.                            // cuts the pipeline
```

The controller **never executes**.

---

## Read the counter in the controller

`HIX_MwRateLimit` leaves the current count in `oCtx:hData["rate_count"]`,
useful to return it in informative headers:

```clipper
LOCAL nCount := UContext():hData[ "rate_count" ]
USetHeader( "X-RateLimit-Remaining", hb_NToS( 100 - nCount ) )
```

---

## Usage patterns

### Login endpoint - anti-bruteforce protection

```clipper
HIX_MwSessionSetup( "HIXSID", 3600, 60, "memory" )

LOCAL bMwLogin := HIX_MwRateLimitFactory( 5, 60 )    // 5 attempts/min

oSrv:AddRoutePost( "login", "/login", ;
   {|| _LoginAction() }, ;
   { "HIX_MwSession", "HIX_MwCsrfCheck", bMwLogin } )
```

After 5 failed POSTs in 1 minute from the same IP → 429 for ~60s.

### Public API

```clipper
HIX_MwRateLimitSetup( 1000, 60 )    // 1000 req/min generous
oSrv:Use( { "HIX_MwCors", "HIX_MwRateLimit" } )
```

### Different tiers by header

For "premium" clients identified by a header you can skip the
rate limit with a middleware that runs first:

```clipper
FUNCTION MyAppSkipRateLimit( oCtx )
   IF oCtx:oReq:Header( "x-premium-key", "" ) == "SECRET"
      oCtx:lHandled := .T.        // mark handled... no, better:
      RETURN .T.                  // just continue, next MW won't apply
   ENDIF
RETURN .T.
```

> For real tiers the cleanest approach is a custom MW that uses a different
> key per tier in the counter hash.

---

## Best practices

1. **Combine with CORS and auth.** Rate limit is the **first line**, not
   a substitute for authentication.
2. **Strict limits on critical endpoints.** `/login`, `/password-reset`,
   `/2fa-verify` - 5-10 attempts per minute suffice.
3. **Return `Retry-After`.** Accompany the 429 with a header saying how many
   seconds left to retry. Useful for well-behaved clients.
4. **Watch out behind proxies.** If your HIX is behind a load balancer,
   `oReq:cIP` might be the proxy's IP (all the same). Configure `proxied`
   mode so it respects `X-Forwarded-For`.
5. **Memory proportional to traffic.** The counter hash grows with unique IPs
   seen in the window. For very high volumes, add periodic GC that cleans expired entries.
6. **Don't rely on this alone.** An attacker with many IPs (botnet) bypasses
   any per-IP rate limit. Combine with
   [Firewall](firewall.md) and CAPTCHA where needed.

