# 📨 HTTP Headers

Every HTTP response carries a series of **headers** that the client reads before
the body: content type, cache, redirects, cookies, security,
... HIX manages them in `oReq:hExtraHeaders` and the `U*` helpers allow you
to read and write them without touching the object directly.

```
Browser  ──── GET /api/users ────▶ HIX
                                    │
                                    │  USetHeader( "Cache-Control", "no-store" )
                                    │  USetHeader( "X-Request-Id", "abc123" )
                                    │  USendJson( hData )
                                    ▼
         <──── 200 OK ──────────────┤
            Content-Type: application/json
            Cache-Control: no-store
            X-Request-Id: abc123
            ...
```

---

## Read headers from the request

```clipper
UHeader( cKey, xDef )    // case-insensitive
```

| Call | Returns |
|---|---|
| `UHeader( "user-agent" )` | User agent text or `""` |
| `UHeader( "x-api-key", "" )` | Header value or `""` |
| `UHeader( "authorization" )` | `"Bearer eyJ..."` |
| `UHeader( "accept" )` | `"application/json, text/html;q=0.9"` |

```clipper
FUNCTION _ApiHandler()
   LOCAL cKey := UHeader( "x-api-key", "" )

   IF Empty( cKey )
      RETURN USendError( 401, "Missing API key" )
   ENDIF

   USendJson( { "ok" => .T. } )
RETURN NIL
```

> Header names are **case-insensitive** - `UHeader("X-Api-Key")` and
> `UHeader("x-api-key")` return the same value.

---

## Write headers in the response

```clipper
USetHeader( cKey, cVal )
```

Accumulates the header in `oReq:hExtraHeaders`; when sending the response, HIX
adds them to the output:

```clipper
USetHeader( "Cache-Control", "no-store" )
USetHeader( "X-Request-Id",  "abc123" )
USetHeader( "X-Frame-Options", "DENY" )

USendJson( hData )
```

If you call the same header twice, **the last one wins**:

```clipper
USetHeader( "X-Version", "1" )
USetHeader( "X-Version", "2" )    // "2" wins
```

### Direct access to `hExtraHeaders`

From a middleware with `oCtx:oReq`:

```clipper
oCtx:oReq:hExtraHeaders[ "X-Custom" ] := "value"
```

Equivalent to the helper, but only when you're not in a route action.

---

## Common headers

### Content type and encoding

| Header | Typical value |
|---|---|
| `Content-Type` | `application/json; charset=utf-8` |
| `Content-Type` | `text/html; charset=utf-8` |
| `Content-Type` | `text/plain; charset=utf-8` |
| `Content-Encoding` | `gzip` (managed by the dispatcher) |

HIX sets `Content-Type` automatically based on the helper you use
(`USendJson` → json, `USendHtml` → html, ...). Only override it if
you want something non-standard:

```clipper
USetHeader( "Content-Type", "application/xml; charset=utf-8" )
USendText( cXml )
```

### Cache

| Header | For what |
|---|---|
| `Cache-Control: no-store` | Never cache (login, sensitive data) |
| `Cache-Control: no-cache` | Cache, but always revalidate |
| `Cache-Control: max-age=3600` | Cache for 1 hour |
| `Cache-Control: public, max-age=31536000, immutable` | Versioned assets |
| `ETag` | HIX calculates it automatically for static files |

```clipper
USetHeader( "Cache-Control", "no-store, no-cache, must-revalidate" )
USetHeader( "Pragma", "no-cache" )
USendJson( hUserPrivateData )
```

### Redirects and location

| Header | When |
|---|---|
| `Location: /new-url` | Accompanies 301/302/307 |
| `Refresh: 5; url=/home` | Browser redirect after N seconds |

Better to use `URedirect("/new", 302)` than to set `Location` manually.

### Security

| Header | Recommended value |
|---|---|
| `X-Frame-Options` | `DENY` or `SAMEORIGIN` - anti-clickjacking |
| `X-Content-Type-Options` | `nosniff` - disables MIME sniffing |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` (HTTPS only) |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Content-Security-Policy` | `default-src 'self'` (CSP - requires per-app tuning) |
| `Permissions-Policy` | `geolocation=(), camera=()` (disables APIs) |

```clipper
PROCEDURE _ApplySecurityHeaders()
   USetHeader( "X-Frame-Options",        "DENY" )
   USetHeader( "X-Content-Type-Options", "nosniff" )
   USetHeader( "Referrer-Policy",        "strict-origin-when-cross-origin" )

   IF UIsHttps()
      USetHeader( "Strict-Transport-Security", "max-age=31536000; includeSubDomains" )
   ENDIF
RETURN
```

Better to convert it into a global middleware:

```clipper
FUNCTION MyAppSecurityHeaders( oCtx )
   _ApplySecurityHeaders()
RETURN .T.

oSrv:Use( "MyAppSecurityHeaders" )
```

### CORS

The `Access-Control-*` headers are managed by the
[`HIX_MwCors`](../seguridad/cors.md) middleware. Don't set them manually:

```clipper
oSrv:Use( "HIX_MwCors" )    // injects Allow-Origin / Allow-Methods / etc.
```

### Cookies

`Set-Cookie` is special: it can appear **multiple times** in the same
response (one per cookie). Use `USetCookie` instead of `USetHeader`:

```clipper
USetCookie( "session", cSid, 3600 )
USetCookie( "lang",    "es",  86400 * 30 )
// → two Set-Cookie in the response
```

See [Cookies](cookies.md).

### Application custom

| Convention | Use |
|---|---|
| `X-Request-Id: abc123` | Request identifier - useful for logs |
| `X-RateLimit-Remaining: 42` | How many requests remain in the window |
| `X-RateLimit-Reset: 1735689600` | When the window resets |
| `X-Powered-By: HIX` | Optional seal (better not to expose) |

```clipper
LOCAL nCount := UContext():hData[ "rate_count" ]
USetHeader( "X-RateLimit-Limit",     "100" )
USetHeader( "X-RateLimit-Remaining", hb_NToS( 100 - nCount ) )
```

---

## Useful patterns

### Force file download

```clipper
USetHeader( "Content-Type",        "application/octet-stream" )
USetHeader( "Content-Disposition", 'attachment; filename="export.csv"' )
USendText( cCsv )
```

### SSE stream - disable buffering

```clipper
USendStreamStart( "text/event-stream", 200, { ;
   "Cache-Control"     => "no-cache",    ;
   "X-Accel-Buffering" => "no"           ;   // nginx won't buffer
} )
```

### Pass request-id between frontend and backend

```clipper
FUNCTION MyAppRequestId( oCtx )
   LOCAL cId := UHeader( "X-Request-Id", "" )

   IF Empty( cId )
      cId := hb_MD5( hb_NToS( Int( hb_TToSec( hb_DateTime() ) ) ) + ;
                     hb_NToS( hb_Random() ) )
      cId := Left( cId, 16 )
   ENDIF

   oCtx:hData[ "request_id" ] := cId
   USetHeader( "X-Request-Id", cId )
RETURN .T.
```

---

## Best practices

1. **Don't expose sensitive information.** No `Server: HIX 1.2.3` or
   `X-Powered-By` or stack traces in headers. The less an attacker knows,
   the better.
2. **Security by default.** `X-Frame-Options`, `nosniff`, `Referrer-Policy`
   and CSP should go in a global middleware across your entire app.
3. **Don't put data in headers.** Headers are for metadata; the body
   is for data. Headers > 8KB can be rejected by proxies.
4. **Case-insensitive when reading, canonical when writing.** HTTP defines
   headers as case-insensitive, but proxies prefer the canonical form:
   `Content-Type`, not `content-type`.
5. **Don't duplicate `Set-Cookie` manually.** Always use `USetCookie` - it knows
   how to manage the cookie list without overwriting them.
