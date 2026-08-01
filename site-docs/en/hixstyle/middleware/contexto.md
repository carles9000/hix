# 📦 Context - `oCtx`

When **HIX** executes a middleware, it always passes a single parameter: **`oCtx`**.
It's the **request context** - an instance of `THixContext` that groups everything
a middleware needs to inspect the request, communicate with other middleware links in the chain,
and decide what should happen next.

```clipper
FUNCTION MW_ApiKey( oCtx )
   // oCtx is the context - it lives throughout the entire middleware chain
   // and disappears when the request ends
RETURN .T.
```

---

## Why does `oCtx` exist instead of just `oReq`?

A middleware rarely acts alone. In a typical chain (rate limit → JWT →
roles → action), each middleware needs to **share information** with the
next ones: the JWT payload, the user's session, an audit flag…

`oCtx` is that "shared space". It's the tray that gets passed hand to hand
throughout the chain, and when it reaches the route action it remains available.

---

## Main properties

| Property | Type | Description |
|----------|------|-------------|
| `oCtx:oReq` | `THixRequest` | Request object of the current request. |
| `oCtx:hData` | Hash | Free dictionary to share data between middlewares. |
| `oCtx:lHandled` | Logical | Mark it `.T.` when the middleware has already responded. |
| `oCtx:cScope` | String | Free metadata assigned to the route (accessible from MW). |
| `oCtx:cOnFail` | String | Redirect URL if the middleware returns `.F.` (optional). |

---

## `oCtx:oReq` - the request

It's the `THixRequest` object of the current request. We can read headers,
cookies, body, query params, etc. from there:

```clipper
LOCAL cKey := oCtx:oReq:Header( "X-Api-Key", "" )
LOCAL cSid := oCtx:oReq:Cookie( "hix_sess", "" )
LOCAL cIp  := oCtx:oReq:IP()
```

### Recommended alternative - `U*` helpers

HIX automatically links the request to the current thread before executing each
middleware, so **the `U*` helpers also work** inside the middleware,
which are usually shorter and more consistent with action code:

```clipper
FUNCTION MW_ApiKey( oCtx )

   // Both lines are equivalent:
   LOCAL cKey := oCtx:oReq:Header( "X-Api-Key", "" )
   LOCAL cKey := UHeader( "X-Api-Key", "" )    // shorter and more readable

   IF cKey != "clave-secreta-123"
      USendError( 401, "Invalid API Key" )
      RETURN .F.
   ENDIF

RETURN .T.
```

| Style with `oCtx:oReq` | Style with `U*` |
|------------------------|-----------------|
| `oCtx:oReq:Header( c, x )` | `UHeader( c, x )` |
| `oCtx:oReq:Cookie( c, x )` | `UCookie( c, x )` |
| `oCtx:oReq:Body()` | `UBody()` |
| `oCtx:oReq:IP()` | `UIP()` |
| `oCtx:oReq:Method()` | `UMethod()` |

Choose the style you prefer - HIX doesn't impose any one. The current convention is
to use `U*` inside actions and middlewares to keep the code concise.

---

## `oCtx:hData` - sharing data between middlewares

`hData` is a free hash that **propagates through the entire** middleware chain and
arrives intact at the route action. It's the official channel for passing
information between links.

Conventional keys already used by system middlewares:

| Key | Set by | Content |
|-----|--------|---------|
| `oCtx:hData["jwt"]` | `HixMwJwt` | Hash with the payload of the verified JWT token. |
| `oCtx:hData["session"]` | `HixMwSession` | Hash with the active session data. |
| `oCtx:hData["_sid"]` | `HixMwSession` | ID of the active session. |
| `oCtx:hData["user"]` | Auth middleware | Object/hash of the authenticated user. |

Example - a roles middleware that reads what `HixMwJwt` already left:

```clipper
FUNCTION MW_RequireAdmin( oCtx )

   LOCAL hJwt := hb_HGetDef( oCtx:hData, "jwt", NIL )

   IF hJwt == NIL .OR. hb_HGetDef( hJwt, "role", "" ) != "admin"
      USendError( 403, "Admins only" )
      RETURN .F.
   ENDIF

RETURN .T.
```

You can add your own keys without touching anything in the system:

```clipper
oCtx:hData["mi_flag"]   := .T.
oCtx:hData["tenant_id"] := 42
```

---

## `oCtx:lHandled` - "I already responded, don't execute the action"

When a middleware decides to **break the chain** (reject the request) it must:

1. Send the response to the client.
2. Mark `oCtx:lHandled := .T.` so the dispatcher knows the response has already
   been sent and doesn't execute anything else.
3. Return `.F.`.

If you use the `USendError` / `USendJson` / `URedirect` helpers, **they already mark
`lHandled` internally** - you don't need to do it manually.

```clipper
FUNCTION MW_ApiKey( oCtx )

   IF UHeader( "X-Api-Key", "" ) != "clave-secreta-123"
      USendError( 401, "Invalid API Key" )   // marks lHandled
      RETURN .F.
   ENDIF

RETURN .T.
```

---

## `oCtx:cScope` - route metadata

When you register a route you can attach it a free string as `scope`. That
value reaches the middleware via `oCtx:cScope` and serves to vary the behavior
according to the "logical group" to which the route belongs.

```clipper
oSrv:AddRouteGet( "admin.users", "/admin/users", 'users.prg', "MW_Log", "admin" )
oSrv:AddRouteGet( "api.stats",   "/api/stats",   'stats.prg', "MW_Log", "public" )
```

```clipper
FUNCTION MW_Log( oCtx )

   IF oCtx:cScope == "admin"
      l( "[AUDIT] " + UMethod() + " " + UPath() + " by " + UIP() )
   ENDIF

RETURN .T.
```

---

## `oCtx:cOnFail` - fallback redirect

Route to redirect to automatically when the middleware returns `.F.`
(optional). Useful, for example, to send to `/login` any route that fails
authentication without repeating the logic in each middleware.

---

## Summary

- `oCtx` is the **request context**, the single parameter received by every middleware.
- `oCtx:oReq` provides access to the request; alternatively you can use the `U*` helpers.
- `oCtx:hData` is the hash **shared** between middlewares and the action.
- `oCtx:lHandled := .T.` when you break the chain; the `USend*` helpers already do it.
- `oCtx:cScope` is free metadata of the route.
- `oCtx:cOnFail` defines the redirect URL if the middleware rejects.
