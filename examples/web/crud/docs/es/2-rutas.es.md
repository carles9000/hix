# Rutas - `www/routes/web.json`

El ejemplo define **14 rutas** declarativas en JSON. HIX las lee en el arranque (hixstyle) y las registra con su método, action, middleware y scope. No hay `AddRouteGet()` manual en el código Harbour.

Cada entrada tiene esta forma:

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

Convenciones:

- **`name`** - identificador único; usado con `URoute("customer.edit", 42)` para generar la URL sin hardcodearla.
- **`url`** - patrón; `:id` es una variable de ruta, `([0-9]+)` es regex inline (solo números).
- **`action`** - ruta relativa a `www/`:
  - `views/x.html` → renderiza directamente el HTML.
  - `controllers/foo.prg` → ejecuta el `Main()` del `.prg`.
  - `controllers/foo/bar@baz.prg` → instancia la clase del fichero e invoca el método `Bar()` sobre ella.
- **`middleware`** - nombre del grupo de MW definido en `www/middlewares/*.prg` .
- **`scope`** - cadena `recurso:accion` que `HIX_MwHasRole` cruza contra los roles del usuario.

---

## Tabla completa de rutas

| # | Método | URL | Nombre | Action | Middleware | Scope |
|---|--------|-----|--------|--------|------------|-------|
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

> El fichero JSON tiene 14 líneas de ruta; en la tabla se muestra la numeración de la 1 a la 15 saltando el índice porque la ruta de índice `/` se cuenta como #1 pero también aparece la línea en blanco antes del delete. La cuenta real de rutas es **14**.

---

## Grupos funcionales

### 1) Público (sin middleware)

| URL | Qué hace |
|-----|----------|
| `GET  /`       | Sirve `www/views/index.html` directamente (portada estática con enlace a `/login`). |
| `GET  /login`  | Ejecuta `controllers/login.prg` → renderiza `sys/login.html` con formulario. Inyecta token CSRF vía `@csrf`. Recupera mensaje de flash `login` (si el `POST /auth` falló) y lo muestra. |
| `POST /auth`   | Ver bloque siguiente - es público en cuanto a "no necesita sesión previa" pero pasa por `MyAppLogin` (rate-limit + CSRF). |

### 2) Login / Logout

| URL | Middleware | Qué hace |
|-----|------------|----------|
| `POST /auth`  | `MyAppLogin` | Valida username/password contra `ModelUser()`, si OK guarda `_auth_user` en la sesión y redirige a `/main`. Si KO deja `error` en flash y redirige a `/login`. Ver `controllers/auth.prg`. |
| `GET  /logout`| `MyAppAuth`  | Ejecuta `USession():Destroy()` y redirige a `/login`. Necesita sesión activa (por eso lleva `MyAppAuth`). |

### 3) Zona autenticada (sesión obligatoria, sin scope)

| URL | Middleware | Qué hace |
|-----|------------|----------|
| `GET /main`     | `MyAppAuth` | Dashboard tras login. Lee `user` del context, muestra su nombre y lista sus roles (`controllers/main.prg`). |
| `GET /module_a` | `MyAppAuth` | Sirve `views/masters/modules/module_a.html` - placeholder para módulos accesibles por cualquier usuario logueado. |
| `GET /module_b` | `MyAppAuth` | Idem. |
| `GET /module_c` | `MyAppAuth` | Idem. |

### 4) CRUD de clientes (scope obligatorio)

Todas las rutas de este grupo comparten patrón: `MyAppAuthRole` en **GET** (solo lectura, sin CSRF) y `MyAppAuthRoleEdit` en **POST** (con validación CSRF además de sesión + rol).

| URL | Método | Scope | Método de `CLASS Customer` |
|-----|--------|-------|----------------------------|
| `/customer/search`         | GET  | `customers:search` | `Search()`  → `masters/customer/search.html` |
| `/customer/create`         | GET  | `customers:create` | `Create()`  → `masters/customer/form.html`   (blank) |
| `/customer/store`          | POST | `customers:create` | `Store()`   → valida + `Append()`, redirige a `show` |
| `/customer/:id`            | GET  | `customers:show`   | `Show()`    → `masters/customer/show.html`   |
| `/customer/:id/edit`       | GET  | `customers:edit`   | `Edit()`    → `masters/customer/form.html`   (con datos) |
| `/customer/:id/update`     | POST | `customers:edit`   | `Update()`  → valida + `Replace()`, redirige a `show` |
| `/customer/:id/delete`     | POST | `customers:delete` | `Delete()`  → soft-delete, redirige a `search` |

Todas las 7 funciones viven en la misma `CLASS Customer` (`www/controllers/masters/customer.prg`). La sintaxis `action: "controllers/masters/store@customer.prg"` le dice al router "carga `customer.prg` e invoca su método `Store()`".

---

## Patrón `:var([regex])`

`:id([0-9]+)` fuerza que el segmento sea numérico. Sin la regex, `/customer/hola` matchearía y llegaría al controlador; con ella el router directamente responde 404. Esto evita validaciones defensivas en cada método.

Otras posibilidades soportadas:

- `:id` - cualquier valor no vacío.
- `:slug([a-z-]+)` - solo minúsculas y guiones.
- `/static/*` - comodín (captura el resto de la URL).

---

## Handlers globales 404 / 405

El ejemplo no define handlers personalizados de 404 / 405; usa los defaults de HIX. Si quisieras uno propio:

```harbour
oServer:SetRouteHandler( "404", {|| USendError( 404, "Página no encontrada" ) } )
```

---

## URL nombradas

Nunca hardcodees URLs en controladores. Usa `URoute()`:

```harbour
URedirect( URoute( "sys.login" ) )                    // → "/login"
URedirect( URoute( "customer.show", 42 ) )            // → "/customer/42"
```

Ejemplos reales del código:

- `controllers/auth.prg:41` → `URedirect( URoute( 'sys.login' ) )`
- `controllers/logout.prg:20` → `URedirect( URoute( 'sys.login' ) )`
- `controllers/masters/customer.prg` → múltiples `URoute( 'customer.search' )`, `URoute( 'customer.show', nId )`.
