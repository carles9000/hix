# 🐛 System error pages

When HIX returns an HTTP error (404, 403, 405, 422, 429, 500, 503...)
**to a client that requests HTML**, it serves an **error page**. If the
client requests JSON (API, AJAX, `Accept: application/json`), it returns
`{ "error": "...", "detail": "..." }` automatically.

HIX lets you **replace the HTML pages with your own static HTML** for
each status code: `error_404.html`, `error_500.html`,
`error_403.html`, etc.

> 🆚 This page covers **system** pages (HTTP errors from routes not found,
> not allowed, pool saturation, etc). If what you want is to customize
> the **5xx page that renders when your own code fails** (exceptions,
> Harbour traces), that lives in
> [programacion/errorsys](../programacion/errorsys.md).

---

## When you need it

- For **branding**: a 404 shows your logo, not the generic gray page.
- To **redirect** to a custom landing (`/not-found`, maintenance page,
  etc).
- For **multilingual** messages (404 translated by locale).
- To **hide technical information** in production (no "HIX Web Server" at
  the bottom).

---

## Setup in `hix.ini`

### Section `[paths]`

```ini
[paths]
root = www      ; app root directory
```

### Fixed location: `<root>/errors/`

HIX looks for custom error pages in the fixed folder `errors/`
relative to `paths.root` (default `www/errors/`):

```text
www/
 ├── errors/
 │   ├── error_404.html
 │   ├── error_403.html
 │   ├── error_500.html
 │   └── error_503.html
 └── ...
```

If the file for a specific code doesn't exist, HIX uses the minimalist
built-in inline page.

---

## How the lookup works

When HIX internally calls `HIX_HttpError(oReq, nStatus, cDetail)`:

```
                 HIX_HttpError(oReq, 404, "Route: /no-existe")
                              │
                              ▼
              Does HIX_WantsJson(oReq)?
                     ├── Yes → JSON {"error":"Not Found","detail":"..."}
                     │
                     └── No → HIX_HttpErrorHtml(404, "Not Found", "...")
                                       │
                                       ▼
                  Does <root>/errors/error_404.html exist?
                         ├── Yes → hb_MemoRead() → serve that HTML
                         │
                         └── No → HIX minimalist inline HTML
```

The JSON vs HTML negotiation checks:

- `Accept: application/json` or `application/json` anywhere.
- `X-Requested-With: XMLHttpRequest` (classic AJAX).
- `Content-Type: application/json` from the request.

---

## HTTP codes returned by HIX

HIX can emit any standard code. The most common ones you see daily:

| Code | When                                                 | Typical detail          |
|------|------------------------------------------------------|-------------------------|
| 400  | Invalid body or parameter                            | Bad Request             |
| 401  | Missing auth (JWT/API key/session)                   | Unauthorized            |
| 403  | No permissions for that route or IP filtered         | Forbidden               |
| 404  | Route not registered or file not found               | Not Found, Route: /...  |
| 405  | Route exists but method not allowed                  | Method Not Allowed      |
| 413  | Body larger than `[bodylimit]`                       | Payload Too Large       |
| 422  | Validation failed (`UValidateOrFail`)                | Unprocessable Entity    |
| 429  | Rate-limit exceeded                                  | Too Many Requests       |
| 500  | Exception in your code                               | Internal Server Error   |
| 502  | Backend / external API down                          | Bad Gateway             |
| 503  | Pool saturated, maintenance mode                     | Service Unavailable     |

The complete list is maintained by `HIX_StatusText(nStatus)` in
`src/hix_error.prg`.

---

## Example `error_404.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
   <meta charset="UTF-8">
   <title>Page not found</title>
   <link rel="stylesheet" href="/static/css/app.css">
</head>
<body>
   <header>
      <img src="/static/img/logo.svg" alt="MiApp">
   </header>

   <main class="error">
      <h1>404</h1>
      <p>This page has disappeared.</p>
      <a href="/">Back to home</a>
   </main>

   <footer>
      <small>&copy; 2026 MiApp</small>
   </footer>
</body>
</html>
```

> 📌 The `error_XXX.html` files are **pure static HTML** served via
> `hb_MemoRead()`. They **do not** go through the view engine. If you need
> dynamic content (interpolated variables), use
> [programacion/errorsys](../programacion/errorsys.md) with a `.view.html`.

---

## Default inline page

When there's no `error_XXX.html`, HIX serves something like:

```html
<!DOCTYPE html>
<html>
<head>
   <title>404 Not Found</title>
   <style>body{font-family:sans-serif;padding:2em;color:#333}h1{color:#c00}</style>
</head>
<body>
   <h1>404 Not Found</h1>
   <h2 style='color:#c00'><small>Route: /no-existe</small></h2>
   <hr>
   <small>HIX Web Server</small>
</body>
</html>
```

Compact, self-contained, and no external resources. For public production
it's recommended to **always** replace it.

---

## Automatic JSON response

If the client requests JSON, HIX emits directly:

```json
{ "error": "Not Found", "detail": "Route: /no-existe" }
```

For 422 errors from `UValidateOrFail`, it also includes the detail of
invalid fields:

```json
{
   "error": "Unprocessable Entity",
   "errors": {
      "email": [ "The email field is required" ],
      "age":   [ "The age field must be numeric" ]
   }
}
```

> 🤖 For a REST API you never need to touch anything: the default behavior
> is already correct.

---

## Generating errors from your code

### From a controller

```clipper
USendError( 404, "User does not exist" )
USendError( 403, "No permissions for this operation" )
USendError( 422, "Email required" )
USendError( 503, "Database under maintenance" )
```

`USendError` respects the negotiation: if the client requests JSON, it
returns JSON; if it requests HTML, it returns the custom page (or the
inline one if it doesn't have one).

### From a middleware

```clipper
FUNCTION HixMwApiKey( oCtx )
   IF Empty( oCtx:oReq:Header( "X-Api-Key", "" ) )
      oCtx:lHandled := .T.
      HIX_HttpError( oCtx:oReq, 401, "API key required" )
      RETURN .F.
   ENDIF
RETURN .T.
```

`HIX_HttpError` is the low-level helper that also respects JSON/HTML.

---

## Difference from `programacion/errorsys`

| Case                                           | What to use                               |
|------------------------------------------------|-------------------------------------------|
| Route not found (404)                          | `errors/error_404.html`                   |
| No permissions (403)                           | `errors/error_403.html`                   |
| Validation failed (422)                        | `errors/error_422.html` + JSON detail     |
| **Exception in your code** (Harbour error)     | `errors/errorsys.view.html` (errorsys)    |
| Pool saturation (503)                          | `errors/error_503.html`                   |

In other words:

- **HTTP errors from normal flow** → static `error_XXX.html`.
- **Crash of your code** → `.view.html` template with error data
  (line, file, trace). That is [errorsys](../programacion/errorsys.md).

You can (and should) use **both** systems at the same time in a production app.

---

## Common errors

| Symptom                                  | Cause                                           | Fix                                    |
|------------------------------------------|------------------------------------------------|----------------------------------------|
| My `error_404.html` doesn't appear       | File outside `www/errors/`                     | Place it in `<paths.root>/errors/`     |
| JSON appears instead of HTML             | Client sends `Accept: application/json`        | That's correct - don't touch           |
| HTML shows without CSS                   | Relative paths in the HTML                     | Use `/static/...` absolute             |
| 500 shows technical data in production   | `[behavior] env = dev`                         | Change to `env = prod`                 |
| My template doesn't interpolate vars     | It's static HTML, not `.view.html`             | Use [errorsys](../programacion/errorsys.md) |

---

## Best practices

- **Always** define at least `error_404.html` and `error_500.html` for
  production. It's the first impression of your brand when something goes
  wrong.
- Keep pages **lightweight** and **self-contained**: no heavy JS, no
  external calls. An error page that's slow shouldn't cause more errors.
- **Don't leak technical details** in production: no stacktraces, no
  server paths, no table names. That's for `dev` or the log.
- For multilingual: use **`Accept-Language` negotiation** in your i18n
  middleware and return `errors/es/error_404.html` or
  `errors/en/error_404.html` with a custom router.
- If your app is **API-only** (no HTML), no need to create pages —
  the automatic JSON response is enough.
