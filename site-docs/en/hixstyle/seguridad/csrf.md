# 🛑 CSRF — Cross-Site Request Forgery

An attacker can trick a logged-in user's browser into sending a "real" request (with the session cookie included) to your site. Because the cookie travels with every request automatically, the server cannot distinguish the legitimate form from the fake one.

**CSRF tokens** prevent this: each form includes a secret token that only the real page knows. If the POST arrives without a token or with an invalid one → **403 Forbidden**.

```
GET  /edit/42          <input type="hidden" name="_csrf" value="ABCxyz...">
POST /edit/42          _csrf=ABCxyz...  ->  middleware checks and allows
POST /edit/42 (forge)  no _csrf        ->  middleware rejects with 403
```

---

## Two flavors in HIX

HIX comes with **two** CSRF middlewares. They cover different scenarios:

| Middleware | State | Needs session | Use case |
|---|---|---|---|
| **`HIX_MwCsrf`** | statefull | ✅ Yes | The token lives in the session. Traditional web pipeline. |
| **`HIX_MwCsrfCheck`** | stateless (HMAC) | ❌ No | The token is signed with `app_key`. Works without active session. |

> Fenix uses **`HIX_MwCsrfCheck`** because it allows including the CSRF token
> even in public forms (login) where there's no session yet.

---

## Setup

### From code

```clipper
HIX_MwCsrfSetup( ;
   "/login",         ;   // cRedirect — URL on failure; "" -> JSON 403
   "x-csrf-token",   ;   // HTTP header with the token
   "_csrf",          ;   // form field with the token
   "my_app_secret",  ;   // HMAC secret (stored as app_key)
   0 )                   // nLapsus — TTL in seconds; 0 = no expiration
```

### Fenix convention — `www/middlewares/config.json`

```json
{
  "setup": {
    "csrf": {
      "redirect": "/login"
    }
  }
}
```

---

## `HIX_MwCsrfCheck` — stateless (Fenix)

This is the pattern Fenix uses in every form. The token is signed with `app_key` and validated without touching the session:

```clipper
// www/middlewares/myapplogin.prg — for public forms
FUNCTION MyAppLogin( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession"    ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
RETURN o:Run()

// www/middlewares/myappauthedit.prg — for authenticated forms
FUNCTION MyAppAuthEdit( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession"    ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"     ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
RETURN o:Run()
```

And the routes:

```json
{ "name": "sys.auth",         "url": "/auth",                "method": "POST",
  "action": "controllers/auth.prg",
  "middleware": "MyAppLogin" }

{ "name": "customer.update",  "url": "/customer/:id/edit",   "method": "POST",
  "action": "controllers/masters/update@customer.prg",
  "middleware": "MyAppAuthEdit", "scope": "customers:edit" }
```

### In the template

```html
<form method="POST" action="/auth">
  {{ UCsrfToHtml() }}
  <input name="username">
  <input name="password" type="password">
  <button>Sign in</button>
</form>
```

`UCsrfToHtml()` generates the `<input type="hidden" name="_csrf" value="...">`
with a freshly signed token. The template embeds it without touching the session.

### Via header (AJAX)

```js
fetch( "/customer/42/edit", {
   method: "POST",
   headers: {
      "X-CSRF-Token": "{{ HIX_CsrfMakeToken() }}",
      "Content-Type": "application/x-www-form-urlencoded"
   },
   body: "name=Carles&email=c@example.com"
} );
```

---

## `HIX_MwCsrf` — statefull

Generates the token on the first GET, saves it in the session as `_csrf_token`, and validates every POST/PUT/DELETE/PATCH against that value.

```clipper
// Apply to the entire server
oSrv:Use( { "HIX_MwSession", "HIX_MwCsrf" } )
```

The token is exposed in `oCtx:hData["csrf_token"]` so templates can read it:

```html
<form method="POST">
  <input type="hidden" name="_csrf" value="{{ csrf_token }}">
  ...
</form>
```

If a POST arrives without a token or with an invalid one → **403 JSON**.

---

## Safe vs unsafe methods

The middleware **only validates** methods that modify state:

| Method | Middleware action |
|---|---|
| `GET`, `HEAD`, `OPTIONS` | Always passes (no validation) |
| `POST`, `PUT`, `DELETE`, `PATCH` | Requires valid token |

---

## Error handling

When `HIX_MwCsrfCheck` fails and has `cRedirect` configured:

1. Saves a flash `csrf` with `error => "..."`.
2. Does `URedirect( cRedirect )`.

Your `login.prg` recovers the message:

```clipper
FUNCTION Main()
   LOCAL oFlash := UFlash( "login" )
   LOCAL cError := oFlash:Get( "error" )
   oFlash:Save()

   IF Empty( cError )
      oFlash := UFlash( "csrf" )                  // ⬅ fallback to CSRF flash
      cError := oFlash:Get( "error" )
      oFlash:Save()
   ENDIF

RETURN UView( "sys/login.view.html", cError )
```

If `cRedirect` is empty, returns **403 JSON** with `{ "error": "..." }`—useful for AJAX/SPA.

---

## `app_key` — the HMAC secret

`HIX_MwCsrfCheck` signs each token with `HIX_ConfigApp("app_key")`. If it doesn't exist, uses the default value **`H!x@CSRF@2026`** (⚠️ **always change in production**).

Configure the app_key:

```clipper
// Via setup
HIX_MwCsrfSetup( "/login", "x-csrf-token", "_csrf", ;
                 "my_secret_app_key", 0 )

// Via direct API
HIX_ConfigAppSet( "app_key", "my_secret_app_key" )
```

> ⚠️ **Changing the `app_key` invalidates all CSRF tokens issued before**, including forms open in active tabs. Users will see a 403 until they refresh the page.

---

## Best practices

1. **CSRF on all POST forms.** Not just login—also edit/delete/transfer/any action that mutates state.
2. **`HIX_MwCsrfCheck` by default.** Simpler (no session involved) and more reusable. Works with `UCsrfToHtml()` directly in templates.
3. **Change `app_key` in production.** The default value is published in the source code.
4. **Reasonable TTL.** `nLapsus = 3600` (1h) limits token reuse if someone copies cached HTML. `0` = no expiration.
5. **CSRF + session go together.** CSRF only makes sense for cookie-based auth. If you use [JWT](jwt.md) in an API, CSRF doesn't apply (Bearer tokens aren't sent automatically).
6. **Double cookie / SameSite=Lax.** HIX's session cookie already carries `SameSite=Lax`, which filters some CSRF attacks. CSRF tokens are the defense in depth.
