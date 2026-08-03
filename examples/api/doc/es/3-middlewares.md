# Middlewares — Estrategia y arquitectura

## Filosofía general

Los ejemplos son API puros (sin HTML, sin sesiones). Todos los
endpoints devuelven JSON, todos los clientes envían `Authorization: Bearer`.
La estrategia de middleware refleja eso: **un único fichero** con piezas
atómicas que se combinan en **guards compuestos**, y cada ruta declara
solo un guard.

Esto resuelve una limitación del router HIX: el campo `middleware` de
`api.json` acepta **un único nombre de función**. En vez de inventar
sintaxis de lista, los guards componen internamente todo lo que hace
falta para ese nivel de acceso.

---

## Capas del sistema

```
┌──────────────────────────────────────────────────────────────┐
│  HIX (librería)                                              │
│  HIX_MwRateLimit   — throttle por IP (ventana fija)          │
│  HIX_MwCors        — CORS preflight + headers                │
│  HIX_MwJwt         — validación JWT (usado internamente)     │
├──────────────────────────────────────────────────────────────┤
│  myws_guards.prg  (app)                                      │
│  MyWsSecHeaders    — headers de hardening HTTP               │
│  MyWsEnforceJson   — rechaza POST/PUT/PATCH sin JSON body    │
│  MyWsBearer        — extrae y valida JWT Bearer              │
│  MyWsRequireScope  — comprueba scope OAuth2 de la ruta       │
│  MyWsRateLimitUser — throttle por usuario (JWT sub)          │
├──────────────────────────────────────────────────────────────┤
│  Guards compuestos (= "perfiles" de acceso)                  │
│  MyWsGuardPublic   — endpoints sin autenticación             │
│  MyWsGuardAuth     — endpoints autenticados sin scope        │
│  MyWsGuardScope    — autenticado + scope específico          │
└──────────────────────────────────────────────────────────────┘
```

---

## Middlewares atómicos

### De HIX (built-in, configurados en `config.json > setup`)

| Middleware          | Qué hace                                              |
|---------------------|-------------------------------------------------------|
| `HIX_MwRateLimit`   | Throttle global por IP. Default: 300 req/min          |
| `HIX_MwCors`        | Preflight OPTIONS + cabeceras CORS en cada respuesta  |

### De aplicación (`myws_guards.prg`)

| Middleware            | Qué hace                                            |
|-----------------------|-----------------------------------------------------|
| `MyWsSecHeaders`      | Añade `X-Content-Type-Options`, `X-Frame-Options`,  |
|                       | `Referrer-Policy`, `Permissions-Policy`, `HSTS`     |
| `MyWsEnforceJson`     | Si el método tiene body (POST/PUT/PATCH), exige      |
|                       | `Content-Type: application/json`. Devuelve 415      |
| `MyWsBearer`          | Lee `Authorization: Bearer <token>`, valida con     |
|                       | `HIX_JwtValidate`. Puebla `oCtx:hData["user"]`      |
| `MyWsRequireScope`    | Lee `oCtx:cScope` (declarado en la ruta) y comprueba|
|                       | que el claim `scope` del JWT lo incluye. → 403      |
| `MyWsRateLimitUser`   | Throttle fijo por `sub` del JWT (usuario concreto). |
|                       | Añade `X-RateLimit-*` headers. Default: 600 req/min |

### Helper transversal

| Función          | Qué hace                                                   |
|------------------|------------------------------------------------------------|
| `AuditLog(e, h)` | Escribe una línea JSON en `logs/audit.log`. Thread-safe.   |
|                  | Incluye timestamp, IP, path, método y sub del JWT si existe|

---

## Guards compuestos

Los guards son funciones que encadenan los atómicos en orden estricto.
Si uno falla, la cadena se corta y la respuesta ya está enviada.

### `MyWsGuardPublic` — endpoints anónimos

```
HIX_MwRateLimit → HIX_MwCors → MyWsSecHeaders → MyWsEnforceJson
```

Usado en: `GET /health`, `GET /time`, `POST /login`, `POST /refresh`.

No requiere autenticación. Protege igualmente contra flood por IP,
problemas CORS y clientes mal configurados.

### `MyWsGuardAuth` — endpoints autenticados

```
HIX_MwRateLimit → HIX_MwCors → MyWsSecHeaders → MyWsEnforceJson
→ MyWsBearer → MyWsRateLimitUser
```

Usado en: `POST /logout`.

Requiere JWT válido. Aplica throttle adicional por usuario.
No comprueba scope: cualquier usuario autenticado puede acceder.

### `MyWsGuardScope` — autenticado + scope requerido

```
HIX_MwRateLimit → HIX_MwCors → MyWsSecHeaders → MyWsEnforceJson
→ MyWsBearer → MyWsRequireScope → MyWsRateLimitUser
```

Usado en: `/me`, `/customers/*`.

El scope requerido se declara en la ruta (`api.json`), no en el guard.
Esto permite un solo guard para múltiples recursos con scopes distintos.

---

## Declaración de rutas y scopes (`api.json`)

```json
{ "name": "customer.list",
  "url":        "/customers",
  "action":     "controllers/list@customer.prg",
  "method":     "GET",
  "middleware": "MyWsGuardScope",
  "scope":      "customers:read" }
```

La convención de scopes sigue el estilo OAuth2: `recurso:accion`.
Scopes actuales:

| Scope               | Acceso                     |
|---------------------|----------------------------|
| `me:read`           | Perfil del usuario propio  |
| `customers:read`    | Listar y ver clientes      |
| `customers:write`   | Crear y actualizar clientes|
| `customers:delete`  | Eliminar clientes          |

---

## Configuración (`middlewares/config.json`)

Los middlewares de HIX se configuran vía `setup`. Los de aplicación
(`myws_guards.prg`) leen su config en runtime via `UMwConfig(sección, clave, default)`.

```json
{
  "load":  [ "myws_guards.prg" ],
  "setup": {
    "jwt":        { "exp": 900, "key_ref": "jwt", "issuer": "fenix.ws" },
    "cors":       { "origin": "*", "methods": "GET,POST,OPTIONS,HEAD",
                    "headers": "Authorization,Content-Type,X-Request-Id" },
    "ratelimit":  { "ip_per_min": 300, "window_s": 60 },
    "secheaders": { "hsts": "max-age=31536000; includeSubDomains",
                    "x_content_type": "nosniff", "x_frame": "DENY",
                    "referrer_policy": "no-referrer",
                    "permissions": "geolocation=(), camera=(), microphone=()" }
  }
}
```
