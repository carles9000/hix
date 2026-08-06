# Users and Profiles

The example includes **three hardcoded users** in `www/models/modeluser.prg`. There is no user database — this is a deliberate stub so the focus stays on the authentication and authorization flow, not on how to persist credentials.

All users share the same password: **`1234`**.

You can replace `ModelUser()` with a function that reads from DBF/SQL without touching anything else in the example: the return contract is a hash `{ "id", "name", "roles" }` or `NIL` if the credentials are invalid.

---

## The Three Users

| User | Password | Functional Role | Typical use in tests |
|------|----------|-----------------|----------------------|
| `demo`   | `1234` | Administrator — full access to the customers module + `sales` + `purchases`. | Verify that all CRUD operations pass (tests 07-15). |
| `carles` | `1234` | Restricted user — can only list and view customers. | Verify that `HasRole` blocks with **403** the operations for which they have no permission (tests 18-23). |
| `maria`  | `1234` | Intermediate user — list, view and edit (no create or delete). | Not covered by the test suite; useful for manual exploration in the browser. |

---

## Role Format: `resource: "action1;action2;..."`

Each user's `roles` hash maps **resource → semicolon-separated string of allowed actions**. An empty string `""` means "access to the resource, no specific actions" (useful for modules like `sales` that have no sub-permissions defined in this example).

Excerpt from `modeluser.prg`:

```harbour
"demo"   => { "id" => "1", "name" => "Admin Demo", "pass" => "1234",
              "roles" => { "sales"     => "",
                           "purchases" => "",
                           "customers" => "search;show;edit;delete;recall;create" } },

"carles" => { "id" => "2", "name" => "Carles Aubia", "pass" => "1234",
              "roles" => { "customers" => "search;show",
                           "purchases" => "" } },

"maria"  => { "id" => "3", "name" => "Maria de la O", "pass" => "1234",
              "roles" => { "customers" => "search;show;edit",
                           "sales"   => "" } }
```

---

## Permission Table by User and Scope

Cross-reference between the `scope` values declared in `web.json` and the actions granted in `modeluser.prg`:

| Route                   | Required scope        | demo | carles | maria |
|-------------------------|-----------------------|:----:|:------:|:-----:|
| `GET  /customer/search` | `customers:search`    | 200  | 200    | 200   |
| `GET  /customer/:id`    | `customers:show`      | 200  | 200    | 200   |
| `GET  /customer/create` | `customers:create`    | 200  | **403**| **403** |
| `POST /customer/store`  | `customers:create`    | 302  | **403**| **403** |
| `GET  /customer/:id/edit` | `customers:edit`    | 200  | **403**| 200   |
| `POST /customer/:id/update` | `customers:edit`  | 302  | **403**| 302   |
| `POST /customer/:id/delete` | `customers:delete`| 302  | **403**| **403** |
| `GET  /main`            | - (auth only)          | 200  | 200    | 200   |
| `GET  /module_a` … `_c`  | - (auth only)         | 200  | 200    | 200   |

Notes on the codes:
- **200** → `HasRole` accepts, the controller renders HTML.
- **302** → POST operation OK; the controller redirects after `Append/Replace/Delete` (PRG pattern).
- **403** → `HasRole` rejects with `HTTP 403 Forbidden` before executing the controller.

---

## How the Permission is Evaluated

For each route with `middleware: "MyAppAuthRole"` or `"MyAppAuthRoleEdit"`, the MW `HIX_MwHasRole` receives the `scope` declared in the route and checks it against `oCtx:hData["user"]["roles"]`:

1. Splits `scope` by `:` → gets `cResource` and `cAction` (`"customers:edit"` → `"customers"` / `"edit"`).
2. Looks up `cResource` in the user's `roles` hash. If not found → **403**.
3. If `cAction == ""` (only the resource was requested) → OK.
4. If `cAction` is present in the `;`-separated string for that resource → OK. Otherwise → **403**.

Example: `carles` requests `GET /customer/1/edit` (scope `customers:edit`):
- `roles["customers"]` = `"search;show"` → `"edit"` is not there → **403**.

---

## How the User is Stored in the Session

When login is accepted (`controllers/auth.prg`):

```harbour
oSess := USession()
oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )   // key = "_auth_user"
oSess:Save()
URedirect( UMwConfig( "auth", "redirect_accept" ) )           // "/main"
```

The key `_auth_user`, the accept route and the failure route (`/login`) are declared in `www/middlewares/config.json` (section `setup.auth`) — they are not hardcoded.

On each subsequent request:
- `HIX_MwSession` retrieves the session hash and places it in `oCtx:hData["session"]`.
- `HIX_MwIsAuth` reads `session["_auth_user"]`; if absent, redirects to `/login` (302).
- `HIX_MwHasRole` takes that user and evaluates the scope.

Details in 4-middlewares.en.md

---

## Adding or Modifying Users

Edit `www/models/modeluser.prg`. Because it is a `.prg` loaded dynamically (compiled to HRB by the dispatcher), **no recompilation of `app.exe` is needed** — just restart the server or wait for the cache TTL if you have caching enabled.

Adding a new user:

```harbour
"pepe" => { "id" => "4", "name" => "Pepe Test", "pass" => "abcd",
            "roles" => { "customers" => "search;show;edit;create" } },
```

Adding a permission to `carles` without touching the rest:

```harbour
"carles" => { "id" => "2", "name" => "Carles Aubia", "pass" => "1234",
              "roles" => { "customers" => "search;show;edit",  // + edit
                           "purchases" => "" } },
```

Changing the session key name (`_auth_user` → something else): edit `www/middlewares/config.json`:

```json
"setup": {
  "auth": {
    "session_user_key": "_auth_user",
    "roles_key":        "roles",
    "redirect_login":   "/login",
    "redirect_accept":  "/main"
  }
}
```

---

## Production vs Demo

`ModelUser()` compares passwords in plain text. In production, **do not**:

- Store bcrypt/argon2 hashes in the DBF/SQL row.
- Compare using the HIX verification function or your crypto library.
- Add per-user rate-limiting in addition to the IP-based rate-limit already provided by `MyAppLogin`.
- Rotate the `keys.session` from `www/config.json` (default `H!x@SESSION@2026`) — there are hooks in `loaders/init.prg` to rotate it automatically on first startup; see the comments in that file.
