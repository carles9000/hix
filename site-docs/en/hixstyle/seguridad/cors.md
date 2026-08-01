# 🌐 CORS — Cross-Origin Resource Sharing


By default, the browser **blocks** JavaScript on `https://app.com` from
`fetch()`-ing against `https://api.anotherdomain.com`. That's the **Same-Origin
Policy**, a basic defense against cross-site attacks.

**CORS** is the mechanism by which the server tells the browser
"yes, I accept requests from this origin, with these methods and these
headers". It does so with a handful of `Access-Control-*` headers.

```
Browser (app.com)                     Server (api.com)
   │                                       │
   │ OPTIONS /v1/users  (preflight)        │
   │ Origin: https://app.com               │
   │ Access-Control-Request-Method: PUT    │
   ├──────────────────────────────────────>│  HIX_MwCors detects OPTIONS
   │                                       │  Responds 204 with CORS headers
   │ 204 No Content                        │
   │ Access-Control-Allow-Origin: app.com  │
   │ Access-Control-Allow-Methods: PUT,... │
   │<──────────────────────────────────────┤
   │                                       │
   │ PUT /v1/users/42  (actual)            │
   │ Origin: https://app.com               │
   ├──────────────────────────────────────>│  HIX_MwCors injects headers
   │ 200 OK + data                         │  Rest of pipeline processes
   │<──────────────────────────────────────┤
```

> The **preflight OPTIONS** is launched by the browser automatically every
> time a cross-origin request uses a "non-simple" method (PUT, DELETE,
> PATCH) or custom headers (`Authorization`, `Content-Type: application/json`).

---

## When to use it

| Case | CORS |
|---|---|
| API consumed by SPA on another domain | ✅ Yes — essential |
| Public API for integrations | ✅ Yes |
| Mobile consuming the API | ❌ No — no browser, doesn't apply |
| Backend same domain as frontend | ❌ No — same-origin |
| Webhook receiving POSTs from external services | ❌ No — servers don't respect CORS |

> CORS protects the **user**, not the server. An attacker with `curl` or
> their own server doesn't suffer CORS — the rule is enforced only by the browser.

---

## Setup

```clipper
HIX_MwCorsSetup( ;
   "https://app.com",                                 ;   // cOrigin
   "GET,POST,PUT,DELETE,OPTIONS,PATCH",               ;   // cMethods
   "Content-Type,Authorization,X-Requested-With" )        // cHeaders
```

Default values if you don't call `HIX_MwCorsSetup`:

| Parameter | Default |
|---|---|
| `cOrigin` | `"*"` (any origin — permissive, development only) |
| `cMethods` | `"GET,POST,PUT,DELETE,OPTIONS,PATCH"` |
| `cHeaders` | `"Content-Type,Authorization,X-Requested-With"` |

Call **before** `oSrv:Start()`.

---

## Activation

`HIX_MwCors` is a **global** middleware — normally you apply it to the entire
server with `oSrv:Use()` so each response includes the headers:

```clipper
oSrv:Use( "HIX_MwCors" )
```

Or on a specific route:

```clipper
oSrv:AddRouteGet( "api", "/api/users", bAction, "HIX_MwCors" )
```

```json
{ "name": "api.users", "url": "/api/users", "method": "GET",
  "action": "controllers/api/users.prg",
  "middleware": "HIX_MwCors" }
```

---

## How it works

```clipper
FUNCTION HIX_MwCors( oCtx )
   LOCAL hCors := { ;
      "Access-Control-Allow-Origin"  => s_cCorsOrigin,  ;
      "Access-Control-Allow-Methods" => s_cCorsMethods, ;
      "Access-Control-Allow-Headers" => s_cCorsHeaders, ;
      "Access-Control-Max-Age"       => "86400"          ;
   }

   IF oCtx:oReq:cMethod == "OPTIONS"
      oCtx:oReq:Respond( "", 204, "text", hCors )   // preflight
      oCtx:lHandled := .T.
      RETURN .F.                                     // cuts the chain
   ENDIF

   hb_HMerge( oCtx:oReq:hExtraHeaders, hCors )      // injects in response
RETURN .T.
```

| Method | Behavior |
|---|---|
| `OPTIONS` | Responds **204 No Content** with CORS headers — preflight resolved |
| Any other | Injects the `Access-Control-*` headers in the final response |

`Access-Control-Max-Age: 86400` tells the browser to cache the
preflight response for 24 hours, avoiding an extra OPTIONS per request.

---

## Combining with other middlewares

CORS usually goes **first** in the stack, before auth, so the
preflight resolves without hitting a 401:

```clipper
oSrv:Use( { "HIX_MwCors", "HIX_MwSession" } )

oSrv:AddRouteGet( "api.me", "/api/me", bAction, ;
   "HIX_MwCors,HIX_MwJwt" )
```

> If `HIX_MwJwt` ran before CORS, the OPTIONS without Bearer would receive
> a 401 and the browser would never make the real request.

---

## Useful patterns

### CORS open only in development

```clipper
IF HIX_Config( "env" ) == "dev"
   HIX_MwCorsSetup( "*" )
ELSE
   HIX_MwCorsSetup( "https://app.com" )
ENDIF
```

### Multiple origins (not natively supported)

`HIX_MwCorsSetup` accepts **only one** `cOrigin`. For multiple, write your own
middleware that looks at the `Origin` header and returns the appropriate header:

```clipper
FUNCTION MyAppCors( oCtx )
   LOCAL aAllowed := { "https://app.com", "https://admin.app.com" }
   LOCAL cOrigin  := oCtx:oReq:Header( "origin", "" )

   IF AScan( aAllowed, cOrigin ) > 0
      oCtx:oReq:hExtraHeaders[ "Access-Control-Allow-Origin" ] := cOrigin
   ENDIF

RETURN HIX_MwCors( oCtx )   // delegates the rest to the standard middleware
```

### Cross-origin cookies

If the API sends cookies (session) and the frontend is on another domain,
add `Access-Control-Allow-Credentials: true` and specify a concrete origin
(`*` is not compatible with credentials):

```clipper
oReq:hExtraHeaders[ "Access-Control-Allow-Credentials" ] := "true"
```

---

## Common errors

| Symptom | Cause |
|---|---|
| `CORS policy: No 'Access-Control-Allow-Origin'` | Missing `HIX_MwCors` on the route — or not applied to OPTIONS |
| `Origin not allowed` | `s_cCorsOrigin` doesn't match the client's `Origin` |
| `Method PUT is not allowed` | `s_cCorsMethods` doesn't include PUT |
| `Header authorization is not allowed` | `s_cCorsHeaders` doesn't include Authorization |
| Preflight returns 401 | CORS configured **after** auth middleware |

---

## Best practices

1. **`"*"` only in development.** In production, list the concrete origins
   that can consume your API.
2. **CORS is not authentication.** It only tells the browser which requests
   can complete — it authenticates nothing. Always combine it with
   [JWT](jwt.md) or [Sessions](sesiones.md).
3. **Apply with `oSrv:Use`.** The preflight OPTIONS reaches any URL,
   even nonexistent ones — registering it globally avoids
   surprises with 405/404 on OPTIONS.
4. **Put CORS before auth in the pipeline.** OPTIONS doesn't carry
   credentials and an auth middleware would reject it.
5. **Limit methods and headers.** Don't expose everything if you don't use it.

