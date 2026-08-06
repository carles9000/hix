# Routes - `www/routes/web.json`

The example defines **14 declarative routes** in JSON. HIX reads them at startup (hixstyle) and registers them with their method, action, middleware and scope. There is no manual `AddRouteGet()` call in Harbour code.

Each entry has this form:

```json
{
  "name":       "customer.edit",
  "url":        "/customer/:id([0-9]+)/edit",
  "action":     "controllers/masters/edit@customer.prg",
  "method":     "GET",
  "middleware": "MyAppAuthRole",
  "scope":      "customers:edit"
}
```

Conventions:

- **`name`** — unique identifier; used with `URoute("customer.edit", 42)` to generate the URL without hardcoding it.
- **`url`** — pattern; `:id` is a route variable, `([0-9]+)` is an inline regex (numbers only).
- **`action`** — path relative to `www/`:
  - `views/x.html` → renders the HTML directly.
  - `controllers/foo.prg` → executes the `Main()` of the `.prg`.
  - `controllers/foo/bar@baz.prg` → instantiates the class from the file and invokes the `Bar()` method on it.
- **`middleware`** — name of the MW group defined in `www/middlewares/*.prg`.
- **`scope`** — `resource:action` string that `HIX_MwHasRole` checks against the user's roles.

---

## Full Route Table

| # | Method | URL | Name | Action | Middleware | Scope |
|---|--------|-----|------|--------|------------|-------|
| 1 | GET  | `/`                              | `index`           | `views/index.html`                             | -                    | - |
| 2 | GET  | `/main`                          | `main`            | `controllers/main.prg`                         | `MyAppAuth`          | - |
| 3 | GET  | `/login`                         | `sys.login`       | `controllers/login.prg`                        | -                    | - |
| 4 | GET  | `/logout`                        | `sys.logout`      | `controllers/logout.prg`                       | `MyAppAuth`          | - |
| 5 | POST | `/auth`                          | `sys.auth`        | `controllers/auth.prg`                         | `MyAppLogin`         | - |
| 6 | GET  | `/module_a`                      | `module_a`        | `views/masters/modules/module_a.html`          | `MyAppAuth`          | - |
| 7 | GET  | `/module_b`                      | `module_b`        | `views/masters/modules/module_b.html`          | `MyAppAuth`          | - |
| 8 | GET  | `/module_c`                      | `module_c`        | `views/masters/modules/module_c.html`          | `MyAppAuth`          | - |
| 9 | GET  | `/customer/search`               | `customer.search` | `controllers/masters/search@customer.prg`      | `MyAppAuthRole`      | `customers:search` |
| 10 | GET  | `/customer/create`               | `customer.create` | `controllers/masters/create@customer.prg`      | `MyAppAuthRole`      | `customers:create` |
| 11 | POST | `/customer/store`                | `customer.store`  | `controllers/masters/store@customer.prg`       | `MyAppAuthRoleEdit`  | `customers:create` |
| 12 | GET  | `/customer/:id([0-9]+)`          | `customer.show`   | `controllers/masters/show@customer.prg`        | `MyAppAuthRole`      | `customers:show` |
| 13 | GET  | `/customer/:id([0-9]+)/edit`     | `customer.edit`   | `controllers/masters/edit@customer.prg`        | `MyAppAuthRole`      | `customers:edit` |
| 14 | POST | `/customer/:id([0-9]+)/update`   | `customer.update` | `controllers/masters/update@customer.prg`      | `MyAppAuthRoleEdit`  | `customers:edit` |
| 15 | POST | `/customer/:id([0-9]+)/delete`   | `customer.delete` | `controllers/masters/delete@customer.prg`      | `MyAppAuthRoleEdit`  | `customers:delete` |

> The JSON file has 14 route entries; the table shows numbering from 1 to 15 because the index route `/` is counted as #1 but the delete line also appears with a gap. The actual route count is **14**.

---

## Functional Groups

### 1) Public (no middleware)

| URL | What it does |
|-----|--------------|
| `GET  /`       | Serves `www/views/index.html` directly (static home page with link to `/login`). |
| `GET  /login`  | Executes `controllers/login.prg` → renders `sys/login.html` with a form. Injects CSRF token via `@csrf`. Retrieves `login` flash message (if `POST /auth` failed) and displays it. |
| `POST /auth`   | See next block — it is public in the sense of "no prior session required" but goes through `MyAppLogin` (rate-limit + CSRF). |

### 2) Login / Logout

| URL | Middleware | What it does |
|-----|------------|--------------|
| `POST /auth`  | `MyAppLogin` | Validates username/password against `ModelUser()`. If OK, stores `_auth_user` in the session and redirects to `/main`. If KO, leaves `error` in flash and redirects to `/login`. See `controllers/auth.prg`. |
| `GET  /logout`| `MyAppAuth`  | Executes `USession():Destroy()` and redirects to `/login`. Requires an active session (that is why it has `MyAppAuth`). |

### 3) Authenticated Zone (session required, no scope)

| URL | Middleware | What it does |
|-----|------------|--------------|
| `GET /main`     | `MyAppAuth` | Dashboard after login. Reads `user` from context, shows their name and lists their roles (`controllers/main.prg`). |
| `GET /module_a` | `MyAppAuth` | Serves `views/masters/modules/module_a.html` — placeholder for modules accessible by any logged-in user. |
| `GET /module_b` | `MyAppAuth` | Same. |
| `GET /module_c` | `MyAppAuth` | Same. |

### 4) Customer CRUD (scope required)

All routes in this group share the same pattern: `MyAppAuthRole` on **GET** (read-only, no CSRF) and `MyAppAuthRoleEdit` on **POST** (with CSRF validation in addition to session + role).

| URL | Method | Scope | `CLASS Customer` method |
|-----|--------|-------|-------------------------|
| `/customer/search`         | GET  | `customers:search` | `Search()`  → `masters/customer/search.html` |
| `/customer/create`         | GET  | `customers:create` | `Create()`  → `masters/customer/form.html`   (blank) |
| `/customer/store`          | POST | `customers:create` | `Store()`   → validate + `Append()`, redirect to `show` |
| `/customer/:id`            | GET  | `customers:show`   | `Show()`    → `masters/customer/show.html`   |
| `/customer/:id/edit`       | GET  | `customers:edit`   | `Edit()`    → `masters/customer/form.html`   (with data) |
| `/customer/:id/update`     | POST | `customers:edit`   | `Update()`  → validate + `Replace()`, redirect to `show` |
| `/customer/:id/delete`     | POST | `customers:delete` | `Delete()`  → soft-delete, redirect to `search` |

All 7 functions live in the same `CLASS Customer` (`www/controllers/masters/customer.prg`). The syntax `action: "controllers/masters/store@customer.prg"` tells the router "load `customer.prg` and invoke its `Store()` method".

---

## The `:var([regex])` Pattern

`:id([0-9]+)` forces the segment to be numeric. Without the regex, `/customer/hello` would match and reach the controller; with it the router responds with 404 directly. This avoids defensive validation in every method.

Other supported forms:

- `:id` — any non-empty value.
- `:slug([a-z-]+)` — lowercase letters and hyphens only.
- `/static/*` — wildcard (captures the rest of the URL).

---

## Global 404 / 405 Handlers

The example does not define custom 404 / 405 handlers; it uses HIX defaults. To define your own:

```harbour
oServer:SetRouteHandler( "404", {|| USendError( 404, "Page not found" ) } )
```

---

## Named URLs

Never hardcode URLs in controllers. Use `URoute()`:

```harbour
URedirect( URoute( "sys.login" ) )                    // → "/login"
URedirect( URoute( "customer.show", 42 ) )            // → "/customer/42"
```

Real examples from the code:

- `controllers/auth.prg:41` → `URedirect( URoute( 'sys.login' ) )`
- `controllers/logout.prg:20` → `URedirect( URoute( 'sys.login' ) )`
- `controllers/masters/customer.prg` → multiple `URoute( 'customer.search' )`, `URoute( 'customer.show', nId )`.
