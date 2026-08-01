# 🍪 Cookies


A **cookie** is a small `name=value` pair that the server sends to the
browser via `Set-Cookie`, and that the browser returns in each subsequent
request via `Cookie`. It's the basic mechanism for maintaining state
(sessions, preferences, authentication) between HTTP requests, which on their
own have no memory.

```
Browser  ─── GET /login ───────────────▶ HIX
                                          │  validates user/pass
                                          │  USetCookie( "HIXSID", cSid, 3600 )
         <── 200 + Set-Cookie  ───────────┤
            HIXSID=abc...; Max-Age=3600;
            Path=/; HttpOnly; SameSite=Lax

Browser  ─── GET /dashboard ───────────▶ HIX
            Cookie: HIXSID=abc...         │  UCookie( "HIXSID" )  → "abc..."
                                          │  identifies the user
         <── 200 + data  ─────────────────┤
```

---

## Read a cookie

```clipper
UCookie( cName, xDef )
```

```clipper
cSid   := UCookie( "HIXSID",     "" )
cTheme := UCookie( "ui_theme",   "light" )
cLang  := UCookie( "lang",       "es" )
```

Internally it parses the `Cookie` header only once per request (lazy).

---

## Write a cookie

```clipper
USetCookie( cName, cValue, nMaxAge )
```

```clipper
USetCookie( "ui_theme", "dark", 86400 * 30 )    // 30 days
USetCookie( "HIXSID",   cSid,   3600 )          // 1 hour
USetCookie( "pref",     "x",    0 )             // session cookie
USetCookie( "old",      "",     -1 )            // expire
```

### Meaning of `nMaxAge`

| Value | Behavior |
|---|---|
| `> 0` | Duration in seconds — the browser saves it until it expires |
| `0` | **Session cookie** — the browser deletes it when closing |
| `-1` | **Expire immediately** — sends `Max-Age=0` to delete it |

```clipper
// Logout
USetCookie( "HIXSID", "", -1 )    // browser forgets the cookie
URedirect( "/login" )
```

---

## Automatic flags

HIX **always** adds three default flags:

```
Set-Cookie: name=value; Path=/; HttpOnly; SameSite=Lax
```

| Flag | What it does |
|---|---|
| `Path=/` | The cookie is sent for the entire app, not just `/login` |
| `HttpOnly` | JavaScript **cannot** read it (`document.cookie` ignores it) — anti-XSS |
| `SameSite=Lax` | The browser does not send it in cross-site POST/PUT requests — basic CSRF defense |

> The three flags together cover 80% of typical cookie attacks.
> If you need different behavior, see
> [HIX_SetCookie direct](#hix_setcookie-low-level).

### `Secure` flag — pending

The `Secure` flag would indicate that the cookie travels only over HTTPS.
The current version of HIX **does not emit it automatically** — if you
terminate TLS in a proxy in front, the proxy normally adds it. If HIX
terminates TLS directly, write the `Set-Cookie` manually with `USetHeader`
to include `Secure`.

---

## Multiple cookies

Each `USetCookie` generates an independent `Set-Cookie` header — browsers
accept multiple in the same response:

```clipper
USetCookie( "HIXSID",   cSid,    3600 )
USetCookie( "ui_theme", "dark",  86400 * 30 )
USetCookie( "lang",     "es",    86400 * 30 )

// In the response:
// Set-Cookie: HIXSID=...; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600
// Set-Cookie: ui_theme=dark; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000
// Set-Cookie: lang=es; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000
```

`HIX_SetCookie` detects cookies with the same name and **replaces** them
instead of duplicating — you don't end up with two different `HIXSID` values.

---

## `HIX_SetCookie` — low-level

When you're not in a route action (for example, inside a middleware with
`oCtx`), use the function with explicit `oReq`:

```clipper
FUNCTION MyAppRememberMeMw( oCtx )
   LOCAL cToken := _GenerateRememberToken( oCtx )

   HIX_SetCookie( oCtx:oReq, "remember", cToken, 86400 * 30 )
RETURN .T.
```

It's exactly the same as `USetCookie`, but receives `oReq` as the first
parameter. `USetCookie` calls it under the hood with the request of the
current thread.

---

## Useful patterns

### Login with session + remember-me

```clipper
FUNCTION _LoginAction()
   LOCAL hUser := _CheckCredentials( UPost("user"), UPost("pass") )

   IF hUser == NIL
      RETURN USendError( 401, "Invalid credentials" )
   ENDIF

   USession():Set( "user_id", hUser["id"] )
   USession():Save()

   IF UPost( "remember", "" ) == "1"
      USetCookie( "remember", _MakeRememberToken( hUser ), 86400 * 30 )
   ENDIF

   URedirect( "/dashboard" )
RETURN NIL
```

### Logout — clean cookies

```clipper
FUNCTION _LogoutAction()
   USession():Destroy()              // expires HIXSID
   USetCookie( "remember", "", -1 )  // deletes the remember-me

   URedirect( "/" )
RETURN NIL
```

### UI preferences (light/dark)

```clipper
oSrv:AddRoutePost( "ui.theme.set", "/ui/theme", {||
   LOCAL cTheme := UPost( "theme", "light" )

   IF AScan( { "light", "dark", "auto" }, cTheme ) == 0
      RETURN USendError( 400, "Invalid theme" )
   ENDIF

   USetCookie( "ui_theme", cTheme, 86400 * 365 )
   USendJson( { "ok" => .T., "theme" => cTheme } )
} )
```

### Persistent language

```clipper
FUNCTION MyAppLangMw( oCtx )
   LOCAL cLang := UCookie( "lang", "" )

   IF Empty( cLang )
      cLang := Left( UHeader( "accept-language", "es" ), 2 )
      USetCookie( "lang", cLang, 86400 * 365 )
   ENDIF

   oCtx:hData[ "lang" ] := cLang
RETURN .T.
```

---

## Common errors

| Symptom | Cause |
|---|---|
| Cookie doesn't reach the client | `USetCookie` after sending the response (`USendJson`/`URedirect`) |
| Cookie arrives but `UCookie` reads it as empty | Name with different case — comparison is case-sensitive |
| Cookie arrives only sometimes | Different `Path` or client blocking cross-site cookies |
| `document.cookie` doesn't see it in JS | `HttpOnly` prevents it — correct design |
| POST from external form doesn't send the cookie | `SameSite=Lax` prevents it — correct design |
| Cookie expires on refresh | You passed `nMaxAge=0` (session cookie) instead of a value in seconds |

---

## Best practices

1. **Never store sensitive data in cookies.** Only opaque identifiers
   (`HIXSID=abc...`). Real data goes in server-side session.
2. **`HttpOnly` and `SameSite` always.** HIX already sets them — don't disable
   them without a clear reason.
3. **Keep size under control.** Cookies are sent in **every** request.
   A 4KB cookie × 30 requests/second = wasted bandwidth.
4. **Sign cookies if sensitive.** If you need to store something "real"
   (a user ID, a role), sign the value with HMAC + `app_key`. If the
   client manipulates it, the signature won't match.
5. **Expire when logging out.** It's not enough to destroy the session
   server-side — you also need to send the cookie with `Max-Age=0` so
   the browser forgets it.
6. **Be careful with `SameSite=Strict`.** Lax is the usual sweet-spot. Strict
   blocks cookies on navigation from external sites (including links) and
   breaks many flows.

