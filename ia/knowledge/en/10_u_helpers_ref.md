# `U*` Helpers — Full Reference

Helpers available in any route action / controller. All read the thread-local request set by the router.

## Reading input

| Helper | Returns |
|--------|---------|
| `UGet( cKey, xDef )` | Query string param. No args → hash of all. |
| `UPost( cKey, xDef )` | POST form or JSON body key. No args → hash of all. |
| `UParam( cKey )` | Route `:var`. No default → 400 error. |
| `UParam( cKey, xDef )` | Route `:var` with fallback. |
| `UHeader( cKey, xDef )` | HTTP header (case-insensitive). |
| `UCookie( cName, xDef )` | Cookie from request. |
| `UBody()` | Raw body string. |
| `UJson()` | Body parsed as JSON → hash/array/NIL. |
| `UFiles()` | Uploaded files: array of `{ "name", "data", "mime", "size" }`. |

## Introspection

| Helper | Returns |
|--------|---------|
| `UMethod()` | `"GET"`, `"POST"`, ... |
| `UPath()` | `"/api/users/42"` |
| `UQuery()` | `"page=1&limit=10"` |
| `UIsGet()` | `.T.` / `.F.` |
| `UIsPost()` | `.T.` / `.F.` |
| `UIsAjax()` | `.T.` if `X-Requested-With: XMLHttpRequest` |
| `UIsJson()` | `.T.` if `Content-Type: application/json` |
| `UWantsJson()` | `.T.` if `Accept: application/json` |
| `UIsForm()` | `.T.` if `application/x-www-form-urlencoded` |
| `UIsMultipart()` | `.T.` if `multipart/form-data` |
| `UIsHttps()` | `.T.` if TLS |
| `UScheme()` | `"http"` / `"https"` |
| `UIP()` | Real client IP (honours `X-Forwarded-For` if `mode=proxied`) |
| `UHost()` | Requested host |
| `UPort()` | TCP port |

## Sending responses

| Helper | Effect |
|--------|--------|
| `USendJson( xData [, nStatus] )` | JSON. `xData` = hash/array/string. Default 200. |
| `USendHtml( cHtml [, nStatus] )` | HTML. Default 200. |
| `USendText( cText [, nStatus] )` | text/plain. Default 200. |
| `USendEmpty()` | 204 No Content. |
| `USendError( nStatus, cMsg )` | HTTP error with message. |
| `URedirect( cUrl [, nStatus] )` | 302 (or 301 with `nStatus`). |
| `USendView( cView [, hVars] )` | Render template + send HTML. |
| `USendStreamStart( cMime, nStatus [, hExtra] )` | Begin chunked streaming (SSE). |
| `USendChunk( cData )` | Send one chunk. |
| `USendEnd()` / `USendStreamEnd()` | Close stream. |

## Buffered response (fine-grained)

| Helper | Effect |
|--------|--------|
| `USetStatus( nStatus )` | Response status. |
| `USetMime( cType )` | Content-Type (short name: `"json"`, `"html"`, `"text"`, or full mime). |
| `USetHeader( cName, cValue )` | Response header. |
| `UWrite( cData )` | Append to response buffer (dispatcher flushes when action returns). |

## Cookies (response)

    USetCookie( cName, cValue, nMaxAge )
    // nMaxAge  0  → session cookie
    //         -1  → expire immediately
    //        > 0  → seconds

Flags applied automatically: `HttpOnly; SameSite=Lax; Path=/`.

## Views

| Helper | Effect |
|--------|--------|
| `USendView( cView [, hVars] )` | Render + send. |
| `UView( cView [, hVars] )` | Render, return string (no send). |

## Sessions (short forms)

| Helper | Effect |
|--------|--------|
| `USession( cKey )` | Read session value. |
| `USession():Set( cKey, xValue )` | Write. |
| `USession():Save()` | Persist + refresh cookie. |
| `USession():Destroy()` | Wipe + expire cookie. |

## Validation

| Helper | Effect |
|--------|--------|
| `UValidatePost( hRules )` | Validate POST body → returns validator. |
| `UValidateGet( hRules )` | Validate query. |
| `UValidateParams( hRules )` | Validate query + route params. |
| `UValidateJson( hRules )` | Validate JSON body. |
| `UValidateOrFail( hRules )` | Validate POST; auto 422 on failure (returns NIL). |

## URL generation

| Helper | Returns |
|--------|---------|
| `URoute( cName [, xArgs...] )` | Named URL with substituted `:var`s. |

## When to use `U*` vs `oReq:`

**Always** use `U*` in route/controller code. `oReq:Respond()` is called BY `U*` under the hood — using it directly bypasses buffering and can lead to double-response bugs.

The only exception is when you have `oCtx` in a middleware and want to respond from there: `oCtx:oReq:Respond(...)`.
