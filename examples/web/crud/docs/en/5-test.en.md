# HTML Test Suite — `www/test/index.html`

An interactive HTML page that runs **25 sequential requests** against the CRUD application and validates the HTTP status code returned by each one. It serves as a manual smoke test for the complete cycle: public → login with CSRF → authenticated operations → logout → login as restricted user → verification that `HasRole` blocks.

Location:

```
examples/web/crud/www/test/index.html
```

Access URL while the server is running:

```
http://localhost/test/index.html
```

---

## `oServer:AllowDir( "test", .F. )` — Why This Line Exists

`src/app.prg` contains a single explicit call:

```harbour
oServer := THixServer():New()
   oServer:AllowDir( "test", .F. )   // ← Without this, the test returns 404!
oServer:Start()
```

In hixstyle mode, HIX applies a **strict ACL whitelist** on the configured `<root>`, by default `www/`. Only the following are served:

- `www/public/*` — automatically included (CSS/JS/images).
- Directories the project explicitly adds via `AllowDir()`.

Everything else (`www/controllers/`, `www/middlewares/`, `www/views/`, `www/models/`, `www/loaders/`, …) is blocked with **HTTP 403**. This is a framework-level defense: it ensures you cannot accidentally expose a `.prg`, a configuration `.json`, or a view without going through a route.

`AllowDir( "test", .F. )` extends the whitelist:

- First parameter: subdirectory name under `www/` (here `www/test/`).
- Second parameter:
  - `.F.` → **static files only**; any `.prg` files inside the directory are not executed even if they exist. This is the correct setting for serving a test HTML.
  - `.T.` → allows `.prg` execution (dangerous; only if you know what you are doing).

Without this line, `GET /test/index.html` would return 404. With it, the dispatcher serves the HTML as a static file.

---

## Why the Test Must Be Served from the Same Origin

An initial attempt was to open `test/index.html` directly via `file://`. **It does not work.** Reasons:

1. **Cookies**: the session (`FENIXSID`) and the CSRF token are stored as cookies of the origin `http://localhost`. An HTML served from `file://` is a different origin, and the browser does not share cookies across origins.
2. **CORS**: the app does not enable CORS (there is no `HIX_MwCorsSetup`). Any cross-origin fetch without CORS is blocked by the browser.
3. **Opaque redirects**: without the same origin, the response to a 302 is received as `type: opaqueredirect` with no headers — the cookies from the 302 (for example the `Set-Cookie: FENIXSID=...` issued by `POST /auth`) are lost.

That is why the file is in `www/test/` (same app root, same port, same origin) and not in, for example, `examples/web/crud/test/` (outside `www/`, impossible to serve).

---

## The Tests, by Block

| # | Method | URL | Expected | What it tests |
|---|--------|-----|:--------:|---------------|
|   | | **Public (no session)** | | |
| 01 | GET  | `/`                          | 200 | Static home page is served |
| 02 | GET  | `/login`                     | 200 | The form includes a fresh CSRF token |
|   | | **Protected without session → 302 → /login** | | |
| 03 | GET  | `/main`                      | 302 | `MyAppAuth` rejects |
| 04 | GET  | `/module_a`                  | 302 | Same |
| 05 | GET  | `/customer/search`           | 302 | `MyAppAuthRole` rejects (no session → IsAuth cuts before HasRole) |
| 06 | GET  | `/customer/1`                | 302 | Same |
|   | | **Auth as `demo` (full admin)** | | |
| 07 | POST | `/auth` without CSRF          | 302 | `MyAppLogin` → `CsrfCheck` rejects |
| 08 | POST | `/auth` demo/1234 + CSRF      | 302 | OK → redirects to `/main` |
| 09 | GET  | `/main` with session          | 200 | Dashboard rendered |
| 10 | GET  | `/module_a`                  | 200 | Authenticated OK |
| 11 | GET  | `/module_b`                  | 200 | Same |
| 12 | GET  | `/customer/search`           | 200 | demo has `customers:search` |
| 13 | GET  | `/customer/create`           | 200 | demo has `customers:create` |
| 14 | GET  | `/customer/1`                | 200 | demo has `customers:show` |
| 15 | GET  | `/customer/1/edit`           | 200 | demo has `customers:edit` |
|   | | **Write protected by CSRF (as demo)** | | |
| 15b | POST | `/customer/store` without CSRF | 302 | `MyAppAuthRoleEdit` → `CsrfCheck` rejects (HasRole would have passed — demo has the scope) |
|   | | **Logout** | | |
| 16 | GET  | `/logout`                    | 302 | Session destroyed, redirects to `/login` |
| 17 | GET  | `/main` after logout         | 302 | Rejects again without session |
|   | | **Auth as `carles` (restricted — search+show only)** | | |
| 18 | POST | `/auth` carles/1234 + CSRF   | 302 | OK |
| 19 | GET  | `/customer/search`           | 200 | carles has `customers:search` |
| 20 | GET  | `/customer/1`                | 200 | carles has `customers:show` |
| 21 | GET  | `/customer/create`           | 403 | carles does NOT have `customers:create` → HasRole rejects |
| 22 | GET  | `/customer/1/edit`           | 403 | carles does NOT have `customers:edit` → HasRole rejects |
| 23 | POST | `/customer/store` as carles  | 403 | HasRole rejects (no `customers:create`) **before** CsrfCheck |
|   | | **Cleanup** | | |
| 24 | GET  | `/logout`                    | 302 | Final session destroyed |

Total: **25 tests** (15b is numbered separately to place it in the write-with-demo block). The success rule is: returned code == expected code. Any discrepancy is marked red.

---

## Technical Design of the Runner

The HTML is self-contained — it does not depend on external libraries. Key points:

### 1. Connectivity Check on Load

Before showing the UI, it does a `fetch("/")` with a 3 s timeout. If it fails, it displays the "server not reachable" banner and prevents running tests.

### 2. Dynamic Origin

```javascript
const API = location.protocol.startsWith('http')
            ? location.origin
            : 'http://localhost';
```

If the HTML is opened via http (correct) → uses the same origin. If opened via `file://` (incorrect, but as a fallback) → tries `http://localhost`. The latter will likely fail due to CORS/cookies but shows a meaningful message instead of a raw error.

### 3. `redirect: 'manual'` by Default

```javascript
const r = await fetch(API + url, {
  method,
  headers: h,
  body,
  credentials: 'include',
  cache: 'no-store',
  redirect: follow ? 'follow' : 'manual'
});
```

`redirect: 'manual'` allows **explicitly detecting the 302** instead of the browser following it automatically. When the browser cannot expose the real status of an opaque redirect, it synthesizes `status: 302`. Tests 03-07, 15b, 16, 17, 23, 24 depend on this.

Exception: setup calls that need the `Set-Cookie` from the 302 to be applied (for example the `POST /auth` in test 08) pass `follow: true`, forcing the browser to follow the 302 and propagate the cookie.

### 4. `credentials: 'include'`

Essential: without this the browser neither sends nor receives cookies. The `FENIXSID` cookie would not travel and the entire session flow would fail.

### 5. `cache: 'no-store'`

Prevents the browser from serving cached responses — essential for re-running the suite and seeing fresh results.

### 6. CSRF Token Extraction

```javascript
async function fetchCsrf() {
  const d = await req('/login', 'GET');
  const m = d.body.match(/name=["']_csrf["']\s+value=["']([^"']+)["']/i)
         || d.body.match(/value=["']([^"']+)["']\s+name=["']_csrf["']/i);
  csrfToken = m ? m[1] : '';
  return csrfToken;
}
```

Before a `POST /auth` with CSRF (tests 08, 18), the runner does `GET /login`, scans the returned HTML and extracts the `_csrf` from the hidden `<input>`. It then includes it in the form-urlencoded body of the POST.

### 7. Response Popup

Each `▶` button in the Run column executes the test individually and **shows the complete response** in a popup — useful when something fails and you need to see the HTML/message the server returned. "Run All" does not open a popup; it only colors the button (green/red) and updates the `N ok / N ko` counter.

---

## Reset

The **Reset** button clears local state (`csrfToken = ''`, neutral buttons) and does `GET /logout` to destroy the session on the server. It is advisable to press it between reruns.

Even so, if a test fails intermittently due to browser cache, the safe recipe is **Ctrl+F5 with DevTools open and "Disable cache" checked**.

---

## Extending the Test Suite

To add a new test 25:

1. Add the `<tr>` row in the table with a new id, button `runTest('25', this)` and span `.e2xx/.e3xx/.e4xx` with the expected code.
2. Add the entry in the JS `EXPECT` object: `'25': 200`.
3. Add the entry in the handler object: `'25': async () => req('/my/route', 'GET')`.
4. If the new test changes session state (login/logout), place it in the correct block so it does not break subsequent tests.

Test order matters: they are sequential and share the session cookie. Test 09 assumes test 08 (login) passed; test 20 assumes test 18 passed.

---

## Relation to Other Parts of the Project

- How expected codes are validated → see [2-rutas.en.md](2-rutas.en.md) to understand which middleware covers each URL.
- Why test 23 gives 403 and not 302 → MW order in [4-middlewares.en.md](4-middlewares.en.md), section `MyAppAuthRoleEdit`.
- What permissions each user has per scope → [3-users.en.md](3-users.en.md).
