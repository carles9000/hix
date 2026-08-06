# Seguridad y middlewares

El ejemplo separa la seguridad en dos capas:

1. **Middlewares nativos de HIX** (`HIX_Mw*`) - Ladrillos genéricos: sesión, autenticación, autorización por rol, CSRF, rate-limit.
2. **Grupos de middleware del proyecto** (`MyApp*`) - combinan los ladrillos en cadenas reutilizables que las rutas referencian por nombre.

Las rutas nunca declaran MW nativos sueltos; siempre invocan un grupo (`MyAppAuth`, `MyAppAuthRole`, `MyAppAuthRoleEdit`, `MyAppLogin`). Así, cambiar la política de seguridad de una zona se hace en un solo sitio.

---

## Los cuatro grupos del proyecto

Definidos en `www/middlewares/*.prg` - todos siguen el mismo patrón `UBaseMiddleware` + `Add()` + `Run()`.

### `MyAppAuth` - Zona autenticada básica

Archivo: `myappauth.prg`

```harbour
FUNCTION MyAppAuth( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession" ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"  ) )
RETURN o:Run()
```

**Cadena**: `Session → IsAuth`
**Propósito**: proteger cualquier página que requiera "estar logueado", sin importar el rol.
**Rechazo**: si no hay sesión válida → **302 → /login**.
**Rutas que lo usan**: `/main`, `/logout`, `/module_a`, `/module_b`, `/module_c`.

---

### `MyAppAuthRole` - Zona autenticada + control por scope (GET)

Archivo: `myappauthrole.prg`

```harbour
FUNCTION MyAppAuthRole( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession" ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"  ) )
   o:Add( UMiddleware():New( "HIX_MwHasRole" ) )
RETURN o:Run()
```

**Cadena**: `Session → IsAuth → HasRole`
**Propósito**: GETs autenticados con permiso por scope (`customers:show`, `customers:edit`, …).
**Rechazo**:
- Sin sesión → **302 → /login**.
- Con sesión pero sin el scope → **403 Forbidden**.

**Rutas que lo usan**: `GET /customer/search`, `GET /customer/create`, `GET /customer/:id`, `GET /customer/:id/edit`.

Como es GET, no verifica CSRF (los GET no modifican estado).

---

### `MyAppAuthRoleEdit` - Zona autenticada + scope + CSRF (POST)

Archivo: `myappauthedit.prg`

```harbour
FUNCTION MyAppAuthRoleEdit( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession"   ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"    ) )
   o:Add( UMiddleware():New( "HIX_MwHasRole"   ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
RETURN o:Run()
```

**Cadena**: `Session → IsAuth → HasRole → CsrfCheck`
**Propósito**: POSTs que modifican estado en el módulo de clientes.
**Rechazo** (por orden de evaluación):
- Sin sesión → **302 → /login**.
- Con sesión pero sin el scope → **403 Forbidden**.
- Con sesión y scope pero sin token CSRF válido → **302 → /login** (redirect configurable).

**Rutas que lo usan**: `POST /customer/store`, `POST /customer/:id/update`, `POST /customer/:id/delete`.

Detalle importante del orden: `HasRole` corre **antes** que `CsrfCheck`. Consecuencia observable en el test suite (`test 23`): un `POST /customer/store` como `carles` (sin `customers:create`) devuelve **403** aunque tampoco tenga token CSRF, porque `HasRole` corta antes.

---

### `MyAppLogin` - Login endurecido (POST)

Archivo: `myapplogin.prg`

```harbour
FUNCTION MyAppLogin( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession"   ) )
   o:Add( UMiddleware():New( "HIX_MwRateLimit" ) )
   o:Add( UMiddleware():New( "HIX_MwCsrfCheck" ) )
RETURN o:Run()
```

**Cadena**: `Session → RateLimit → CsrfCheck`
**Propósito**: proteger `POST /auth` contra fuerza bruta y contra envío desde formularios de terceros.
**Rechazo**:
- Superado el rate-limit → **429 Too Many Requests**.
- Sin token CSRF válido → **302 → /login**.

**Nota** (del comentario del propio fichero): el rate-limit es global, aplicado solo a `/auth` en este ejemplo. Si se reutilizara `MyAppLogin` en otra ruta se compartiría el mismo contador; en ese caso conviene un factory (`HIX_MwRateLimitFactory( ... )`) para instanciar contadores por ruta.

---

## Los ladrillos: middlewares nativos HIX usados aquí

| MW nativo | Qué hace | Config | Setup |
|-----------|----------|--------|-------|
| `HIX_MwSession`   | Recupera/crea sesión, lee cookie `FENIXSID`, mete el hash de sesión en `oCtx:hData["session"]`. | cookie name, TTL, GC, storage | `www/middlewares/config.json > setup.session` |
| `HIX_MwIsAuth`    | Comprueba que `session["_auth_user"]` existe. Si no, redirige a `/login`. | clave user, redirect | `setup.auth` |
| `HIX_MwHasRole`   | Cruza el `scope` de la ruta contra `roles` del user (formato `recurso:accion`). Ver [users.es.md](users.es.md). | usa `setup.auth.roles_key` | `setup.auth` |
| `HIX_MwCsrfCheck` | Verifica token CSRF (HMAC stateless). Ligado a la sesión + `keys.csrf` de `www/config.json`. | redirect, TTL | `setup.csrf` |
| `HIX_MwRateLimit` | Contador por IP en ventana deslizante. Aplica siempre - configuración global. | `ip_per_min`, `window_s` | `setup.ratelimit` |

`HIX_MwSession` es el primero de todas las cadenas porque el resto depende de que el contexto tenga sesión disponible.

---

## Setup declarativo - `www/middlewares/config.json`

Un solo JSON gestiona qué `.prg` cargar y con qué parámetros arrancar los MW nativos:

```json
{
  "load": [
    "myappauth.prg",
    "myappauthrole.prg",
    "myappauthedit.prg",
    "myapplogin.prg"
  ],
  "setup": {
    "auth": {
      "session_user_key": "_auth_user",
      "roles_key":        "roles",
      "redirect_login":   "/login",
      "redirect_accept":  "/main"
    },
    "session": {
      "cookie":   "FENIXSID",
      "ttl":      3600,
      "max":      100,
      "storage":  "memory"
    },
    "csrf": {
      "redirect": "/login",
      "ttl":      3600
    },
    "ratelimit": {
      "ip_per_min": 300,
      "window_s":   60
    }
  }
}
```

Comportamiento en el arranque:

1. `load` - cada `.prg` se compila a HRB y queda residente. Sus funciones (`MyAppAuth`, `MyAppLogin`, …) quedan disponibles para que el router las invoque cuando `web.json` diga `"middleware": "MyAppAuth"`.
2. `setup.auth` - expone las claves vía `UMwConfig("auth", ...)`. Usado en `controllers/auth.prg` para no hardcodear la clave de sesión ni la ruta de redirect.
3. `setup.session` - llama a `HIX_MwSessionSetup( "FENIXSID", 3600, 100, "memory", ... )`.
4. `setup.csrf` - llama a `HIX_MwCsrfSetup( "/login", NIL, NIL, NIL, 3600 )` (TTL de 1 hora - token expira aunque siga la sesión).
5. `setup.ratelimit` - llama a `HIX_MwRateLimitSetup( 300, 60 )` (300 requests/IP/minuto).

**Ventaja**: puedes cambiar cualquier parámetro de seguridad sin recompilar `app.exe`. Solo reinicias.

---

## Sesión: cookie y almacenamiento

- Cookie: `FENIXSID` - HttpOnly, SameSite=Lax, Path=/.
- TTL: **3600 s** (1 hora).
- Almacenamiento: **en memoria** (perdida al reiniciar el servidor).
- Cambio a fichero: `www/middlewares/config.json > setup.session.storage = "file"` + añadir `path`.

---

## CSRF: cómo se emite y cómo se verifica

**Emisión** - en cada formulario de la app, el template usa la directiva `@csrf`:

```html
<form method="post" action="/auth">
  @csrf
  <input name="username">
  <input name="password" type="password">
  <button>Enter</button>
</form>
```

`@csrf` (o `UCsrfToHtml()` en un renderer) inserta:

```html
<input type="hidden" name="_csrf" value="TOKEN_HMAC_STATELESS">
```

El token es HMAC del SID actual + secret (`keys.csrf` de `www/config.json`) + timestamp. **No** se guarda en la sesión - se recomputa en cada verificación.

**Verificación** - `HIX_MwCsrfCheck` recompone el HMAC y compara. Si:
- No hay token → 302 → `/login`.
- Token válido pero antiguo (superó TTL 3600 s) → 302 → `/login`.
- Token válido y fresco → sigue la cadena.

En el test suite (test 15b, 07), un POST sin `_csrf` da **302** - no 403. Este es el rechazo típico de `CsrfCheck`.

---

## Rate limit

- Contador global por IP, ventana deslizante de 60 s.
- 300 peticiones por IP en 60 s → **429**.
- En este ejemplo solo entra en juego en `POST /auth`. Si volvieras a usar `MyAppLogin` para otra ruta o reciclaras el rate-limit en `MyAppAuthRoleEdit`, todas las rutas compartirían el mismo contador; para contadores independientes usa `HIX_MwRateLimitFactory()`.
- El valor era `5/60` inicialmente (endurecido contra fuerza bruta); se subió a `300/60` para que el test suite pueda re-ejecutarse muchas veces sin bloquearse. En producción, bájalo (`5/60` o `10/60`).

---

## Añadir un grupo nuevo

Ejemplo: proteger una zona "API interna" con IP whitelist + JWT + rate-limit:

1. Crear `www/middlewares/myapiinternal.prg`:

```harbour
FUNCTION MyApiInternal( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwIpWhitelist" ) )
   o:Add( UMiddleware():New( "HIX_MwJwt"         ) )
   o:Add( UMiddleware():New( "HIX_MwRateLimit"   ) )
RETURN o:Run()
```

2. Añadirlo a `www/middlewares/config.json > load`.
3. Si hace falta setup: añadir sección `jwt` / `ipwhitelist` en `setup`.
4. Referenciar en `web.json`: `"middleware": "MyApiInternal"`.

No hay que tocar `src/app.prg` ni recompilar.
