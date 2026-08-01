# 🔗 API - Endpoints `/hix-*`

Referencia completa de los endpoints del panel admin de HIX. Para el detalle
conceptual (sesión, cookie firmada, configuración inicial) ver
[sistema/hix-admin](../sistema/hix-admin.md).

---

## Resumen

| Endpoint                | Método      | Auth   | Función                               |
|-------------------------|-------------|:------:|---------------------------------------|
| `/hix-ping`             | `GET`       |   -    | Health check público                  |
| `/hix-slow`             | `GET`       |   -    | Endpoint lento (3s) - debug latencia  |
| `/hix-status`           | `GET`       |   ✅   | Métricas en JSON                      |
| `/hix-monitor`          | `GET`       |   ✅   | Dashboard HTML en vivo                |
| `/hix-index`            | `GET`       |   ✅   | Listado HTML de rutas registradas     |
| `/hix-trace`            | `GET POST`  |   ✅   | Estado/toggle de trazas por módulo    |
| `/hix-cache-clear`      | `GET`       |   ✅   | Borra cache de views compiladas       |
| `/hix-stop`             | `GET`       |   ✅   | Detiene HIX de forma ordenada         |
| `/hix-bench-start`      | `GET`       |   ✅   | Resetea métricas (bench)              |
| `/hix-bench-stop`       | `GET`       |   ✅   | Volcado JSON del bench                |
| `/hix-routes/add`       | `POST`      |   ✅   | Añade ruta dinámica                   |
| `/hix-routes/delete`    | `POST`      |   ✅   | Elimina ruta por nombre               |
| `/hix-routes/reload`    | `GET`       |   ✅   | Recarga `routes/*.json`               |
| `/hix-routes/list`      | `GET`       |   ✅   | Listado HTML - solo rutas de app      |
| `/hix-routes/listall`   | `GET`       |   ✅   | Listado HTML - todas las rutas        |
| `/hix-login`            | `GET POST`  |   -    | Login del admin                       |
| `/hix-logout`           | `GET`       |   -    | Cierra la sesión admin                |
| `/hix-setup`            | `GET POST`  |   -    | Configuración inicial de credenciales |

> **Auth** = requiere `HIX_AdminCheck(oReq)` antes de ejecutar el handler.
> En `env=dev` la auth se desactiva automáticamente - todos los endpoints
> responden sin cookie. En `env=prod` se exige cookie `hix_admin` válida.

---

## Endpoints públicos

### `GET /hix-ping`

Health check ligero - pensado para balanceadores y monitorización externa.

**Respuesta `200 OK`** (JSON):

```json
{ "status": "ok", "server": "HIX/2.1" }
```

### `GET /hix-slow`

Igual que `ping` pero con `hb_idleSleep(3)`. Útil para probar timeouts de
clientes, balanceadores o front proxy.

**Respuesta `200 OK`** tras 3 segundos:

```json
{ "status": "ok", "time": "12:34:56" }
```

---

## Métricas y monitor

### `GET /hix-status`

Vuelca el estado del servidor (conexiones activas, requests totales,
errores, uso de pools, alerta de saturación, etc.) como JSON. Lo genera
`HIX_MetricsJson()`.

**Respuesta `200 OK`** (extracto):

```json
{
  "uptime_s": 12345,
  "requests": { "total": 9876, "errors": 12 },
  "pool_http": { "workers": 64, "queue": 5, "alert": false },
  "pool_ws":   { "workers": 100, "active": 42 },
  "pool_rest": { "sse": 3, "longpoll": 1 }
}
```

Ver [sistema/metricas](../sistema/metricas.md) para el detalle completo del
schema.

### `GET /hix-monitor`

Sirve `html/monitor.html` - dashboard HTML que consume `/hix-status` cada
`[monitor] interval_s` segundos y renderiza gráficos. Útil para inspección
visual.

### `GET /hix-index`

Página HTML autocontenida con la **lista de todas las rutas registradas**
(nombre, métodos, patrón, botón "Abrir"). Útil para descubrir qué tiene el
servidor sin acceder al código.

Cada fila muestra:

- **Name** - nombre lógico (`hix.status`, `users.list`, ...)
- **Methods** - badges coloreados por método (`GET`, `POST`, ...)
- **Pattern** - URL pattern (`/users/:id`)
- **Action** - botón "Abrir" si la ruta acepta `GET`

---

## Trazas

### `GET /hix-trace`

**Sin parámetros:** devuelve el estado actual de todas las trazas por
módulo en JSON.

```json
{
  "app": true,
  "server": true,
  "worker_http": false,
  "worker_ws": false,
  ...
}
```

**Con `?mod=<modulo>&on=<0|1>`:** activa o desactiva la traza para ese
módulo y devuelve el estado actualizado.

| Query                              | Efecto                                |
|------------------------------------|---------------------------------------|
| `?mod=worker_http&on=1`            | Activa traza del módulo `worker_http` |
| `?mod=worker_http&on=0`            | Desactiva traza del módulo            |
| `?mod=all&on=1`                    | Activa **todos** los módulos          |
| `?mod=all&on=0`                    | Desactiva **todos**                   |

Módulos disponibles: `app`, `server`, `worker_http`, `worker_ws`,
`worker_otros`, `pool`, `pool_detector`, `metrics`, `config`, `socket`,
`monitor`, `response`, `logger`, `error`.

> `WARN`/`ERROR`/`FATAL` siempre se loguean, independientemente del trace.

---

## Cache

### `GET /hix-cache-clear`

Borra recursivamente la cache de views compiladas en
`.cached/views/` (ficheros `.hrb` y `__*.prg`). Útil tras un deploy donde
los `.view.html` cambian pero `cache_disk = true` mantiene los HRB
viejos.

**Respuesta `200 OK`:**

```json
{ "status": "ok", "deleted": 42, "path": "C:/hix.pro/.cached/views" }
```

> No afecta a la cache RAM (`cache_ram`); esa se invalida sola por
> `mtime`.

---

## Bench

### `GET /hix-bench-start`

Resetea **todos los contadores** del módulo de métricas (`HIX_MetricsReset()`)
y deja el servidor listo para una nueva medición.

**Respuesta `200 OK`:**

```json
{ "bench": "start" }
```

### `GET /hix-bench-stop`

Cierra el bench y devuelve un volcado completo de `HIX_MetricsJson()`.

**Respuesta `200 OK`:**

```json
{
  "bench": "stop",
  "metrics": { "uptime_s": 60, "requests": { "total": 50000, ... } }
}
```

---

## Parada ordenada

### `GET /hix-stop`

Marca el servidor para detener (`HIX_ServerRequestStop()`), cierra el
keep-alive del request actual y deja que los workers terminen sus tareas en
curso antes de salir.

**Respuesta `200 OK`:**

```json
{ "status": "stopping" }
```

> Equivale a un `Ctrl+C` controlado por HTTP. El loop principal sale
> cuando la cola de cada pool se vacía.

---

## API de gestión de rutas dinámicas

Permite añadir, eliminar y recargar rutas **en caliente** sin reiniciar
HIX. Las rutas creadas por esta API son volátiles (se pierden al
reiniciar) salvo que las persistas en `routes/*.json` antes.

> **Reservado:** los nombres con prefijo `hix.*` son del sistema y no se
> pueden registrar por esta API (responde `400`).

### `POST /hix-routes/add`

Añade una ruta nueva. Body **JSON**:

```json
{
  "name":       "users.list",
  "url":        "/users",
  "action":     "/controllers/users/list.prg",
  "method":     "GET",
  "middleware": "HIX_MwJwt",
  "scope":      ""
}
```

| Campo        | Tipo   | Obligatorio | Notas                                          |
|--------------|--------|:-----------:|------------------------------------------------|
| `name`       | string |     ✅      | No puede empezar por `hix.`                    |
| `url`        | string |     ✅      | URL pattern (admite `:var`). Alias: `pattern`  |
| `action`     | string |     ✅      | Ruta del PRG/HRB/HTML a ejecutar               |
| `method`     | string |     ❌      | Default `*` (todos). Coma-separado: `GET,POST` |
| `middleware` | string |     ❌      | MW(s) separados por coma                       |
| `scope`      | string |     ❌      | Metadata libre (ej. `admin`)                   |

**Respuesta `200 OK`** si se añadió:

```json
{ "ok": true, "name": "users.list" }
```

**Respuesta `409 Conflict`** si la ruta ya existe (no sobrescribe):

```json
{ "ok": false, "error": "duplicate or invalid route", "name": "users.list" }
```

**Respuesta `400 Bad Request`** si el JSON es inválido o el nombre está
reservado:

```json
{ "ok": false, "error": "invalid JSON body" }
```

### `POST /hix-routes/delete`

Elimina una ruta por nombre. Body **JSON**:

```json
{ "name": "users.list" }
```

**Respuesta `200 OK`:**

```json
{ "ok": true, "name": "users.list" }
```

**Respuesta `400 Bad Request`** si falta `name`:

```json
{ "ok": false, "error": "name required" }
```

### `GET /hix-routes/reload`

Borra **todas las rutas de aplicación** (las que no son `hix.*`) y vuelve
a cargar las definidas en `www/routes/*.json` con `HIX_LoadRoutes()`.

**Respuesta `200 OK`:**

```json
{ "ok": true, "total_deleted": 12, "total_loaded": 14 }
```

Útil en flujos de deploy: copias el nuevo `routes/users.json` al servidor
y disparas `/hix-routes/reload` desde tu pipeline.

### `GET /hix-routes/list`

Página HTML con las **rutas de aplicación** (excluye las del sistema
`hix.*`). Columnas: name, methods, pattern, middleware, action.

### `GET /hix-routes/listall`

Igual que `/hix-routes/list` pero incluye **todas** las rutas (sistema +
aplicación).

---

## Autenticación

### `GET /hix-login`

Página HTML con el formulario de login (usuario + contraseña).
Autocontenida - no usa CDN ni assets externos.

Acepta `?next=<url>` para redirigir tras un login exitoso (default:
`/hix-status`).

### `POST /hix-login`

Procesa el login. Body **form-urlencoded**:

| Campo      | Tipo   | Notas                                       |
|------------|--------|---------------------------------------------|
| `user`     | string | Usuario admin                               |
| `password` | string | Contraseña en claro (se MD5 en el servidor) |
| `next`     | string | URL a la que redirigir tras login           |

Si las credenciales son válidas:

- Emite cookie `hix_admin = <ts>:<sign>` firmada con `oCfg:cAdminSecret`,
  válida `session.lifetime` minutos.
- Redirige a `next` (o `/hix-status` si está vacío).

Si fallan: responde `401 Unauthorized` con el formulario y un mensaje de
error.

### `GET /hix-logout`

Elimina la cookie `hix_admin` (la expira inmediatamente) y redirige a
`/hix-login`.

### `GET /hix-setup`

Página HTML con el formulario de **creación inicial** de credenciales.
Solo se muestra si `oCfg:cAdminUser` o `oCfg:cAdminPassword` están vacíos.

Si ya existen credenciales: redirige a `/hix-login`.

### `POST /hix-setup`

Crea las credenciales por primera vez. Body **form-urlencoded**:

| Campo       | Tipo   | Validación                                  |
|-------------|--------|---------------------------------------------|
| `user`      | string | No vacío                                    |
| `password`  | string | Longitud mínima 6                           |
| `password2` | string | Debe coincidir con `password`               |

Si validan:

- Guarda `oCfg:cAdminUser = user`
- Guarda `oCfg:cAdminPassword = MD5(password)`
- Genera y guarda `oCfg:cAdminSecret = MD5(timestamp + user + password)`
- Persiste todo en `hix.json` con `oCfg:Generate()`
- Redirige a `/hix-login`

Si hay errores: responde `422 Unprocessable Entity` con el formulario y
el mensaje de error correspondiente.

---

## Cookie de sesión `hix_admin`

Formato del valor de la cookie:

```
<timestamp_unix>:<md5_sign>
```

Donde:

- `timestamp_unix` = momento en segundos en que se emitió la cookie
- `md5_sign` = `MD5(secret + "|" + timestamp_unix)`

Verificación en cada request:

1. Tokenizar por `:`
2. Recalcular `MD5(secret + "|" + ts)` y comparar contra `sign`
3. Si `nMinutes > 0`: comprobar que `now - ts <= session.lifetime * 60`

Si cualquier paso falla → redirige a `/hix-login?next=<path_actual>`.

> La firma usa `cAdminSecret` que **debe** mantenerse en `hix.json`. Si lo
> rotas, todas las sesiones admin activas se invalidan.

---

## Códigos HTTP

| Código              | Cuándo                                                     |
|---------------------|------------------------------------------------------------|
| `200 OK`            | Petición exitosa                                           |
| `302 Found`         | Redirect a `/hix-login`, `/hix-setup` o `next=`           |
| `400 Bad Request`   | JSON inválido o nombre de ruta reservado (`hix.*`)         |
| `401 Unauthorized`  | Login fallido                                              |
| `409 Conflict`      | `/hix-routes/add` con nombre ya existente                  |
| `422 Unprocessable` | `/hix-setup` con validación fallida (pass corto, etc.)     |

---

## Recetas comunes

### Recargar rutas tras deploy

```bash
# 1. Subir el nuevo JSON
scp www/routes/users.json prod:/srv/hix/www/routes/

# 2. Recargar
curl --cookie-jar /tmp/c.txt --cookie /tmp/c.txt \
     -d 'user=admin&password=secret' \
     https://miapp.com/hix-login

curl --cookie /tmp/c.txt https://miapp.com/hix-routes/reload
```

### Activar trace de WebSocket en caliente

```bash
curl --cookie /tmp/c.txt \
     "https://miapp.com/hix-trace?mod=worker_ws&on=1"
```

### Parar HIX desde un script de despliegue

```bash
curl --cookie /tmp/c.txt https://miapp.com/hix-stop
# El servidor responde {"status":"stopping"} y sale tras vaciar colas.
```

### Health check público (sin auth)

```bash
curl https://miapp.com/hix-ping
# {"status":"ok","server":"HIX/2.1"}
```

---

## Errores típicos

- **`302` redirigiendo a `/hix-setup` y nunca llego al panel** - `hix.json`
  tiene `admin.user` y/o `password` vacíos. Visita `/hix-setup` desde
  el navegador para crearlos.
- **`302` redirigiendo a `/hix-login` con cookie correcta** - la cookie
  expiró (`session.lifetime` agotados) o `cAdminSecret` cambió.
- **`409 duplicate` en `/hix-routes/add`** - la ruta ya existe. Bórrala
  antes con `/hix-routes/delete` o cambia de nombre.
- **`400 reserved name`** - intentas registrar `hix.algo`. Renómbrala.
- **`/hix-status` devuelve HTML en vez de JSON** - `admin.enabled = false`
  o no estás autenticado en `env = "prod"` (te redirige al login HTML).

---

## Buenas prácticas

- En producción protege `/hix-*` también a nivel de proxy (`apache`/`nginx`)
  con allow-list por IP para minimizar superficie.
- No registres tus rutas con prefijo `hix.*` - está reservado y HIX rechaza.
- Las rutas creadas por `/hix-routes/add` son **volátiles**: si quieres que
  sobrevivan al reinicio, persístelas en `www/routes/*.json`.
- `cAdminSecret` es secreto: no lo subas a git. Para rotarlo, regenera con
  `/hix-setup` (tras borrar `user`/`password` de `hix.json`).
- Usa `/hix-cache-clear` después de cualquier deploy que toque
  `.view.html` si tienes `cache_disk = true`.
- Activa trazas (`/hix-trace?mod=X&on=1`) solo el tiempo justo para
  diagnosticar - el coste de log puede ser alto en módulos calientes
  (`worker_http`, `socket`).

---

## Recursos relacionados

- Configuración `hix.json`
- [Panel admin (visión general)](../sistema/hix-admin.md)
- [Métricas](../sistema/metricas.md)
- [Logger](../sistema/logger.md)
- Errores HTTP
- Trazas
