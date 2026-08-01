# 👑 Panel admin


HIX expone un conjunto de **endpoints de administración** bajo el prefijo
`/hix-*` que permiten consultar el estado del servidor, recargar rutas,
limpiar caches, activar/desactivar trazas y detener el servidor de forma
ordenada. Todos están protegidos por una **sesión de admin con cookie
firmada** (`hix_admin`).

El panel se autoconfigura al primer arranque: si no hay credenciales,
redirige a `/hix-setup` para que crees el usuario/contraseña inicial.

---

## ¿Cuándo lo necesitas?

- Para **monitorizar** el servidor en producción (`/hix-status`).
- Para **recargar rutas** desde `routes/*.json` sin reiniciar.
- Para **limpiar el cache** de vistas tras un deploy.
- Para **parar HIX** desde un script remoto sin acceso TTY.
- Para **activar trazas** puntuales por módulo y diagnosticar un
  problema.

---

## Setup en `hix.json`

### Sección `admin`

`enabled = false` desactiva el panel y las rutas `/hix-*`.
`user` / `password` vacíos activan `/hix-setup`. La vida de la sesión admin
la controla `session.lifetime` (minutos).

```json
{
  "admin": {
    "enabled":  true,
    "user":     "",
    "password": "",
    "secret":   ""
  }
}
```

Con `user` y `password` vacíos, cualquier petición a un endpoint admin
**redirige a `/hix-setup`** para crear las credenciales. Una vez creadas,
HIX las escribe en `hix.json` con `oCfg:Generate()`.

### Comportamiento según `env`

| `app.env` | Auth requerida              |
|-----------|-----------------------------|
| `dev`     | **No** - acceso libre       |
| `prod`    | **Sí** - cookie `hix_admin` |

En `dev` los endpoints están abiertos para iterar rápido. En `prod`
exigen login.

---

## Endpoints disponibles

Todos están definidos en `src/hix_router.prg` y dependen de
`HIX_AdminCheck(oReq)`.

### Operación

| Ruta                       | Método    | Descripción                                          |
|----------------------------|-----------|------------------------------------------------------|
| `/hix-ping`                | GET       | Healthcheck público (no requiere auth)               |
| `/hix-status`              | GET       | JSON con todas las [métricas](metricas.md)           |
| `/hix-monitor`             | GET       | Página HTML con dashboard interactivo                |
| `/hix-index`               | GET       | Página HTML con el listado de rutas registradas      |
| `/hix-stop`                | GET       | Detiene el servidor de forma ordenada                |
| `/hix-cache-clear`         | GET       | Limpia el cache de vistas (RAM + disco)              |
| `/hix-trace`               | GET/POST  | Lista o ajusta trazas por módulo                     |

### Rutas dinámicas

| Ruta                       | Método    | Descripción                                          |
|----------------------------|-----------|------------------------------------------------------|
| `/hix-routes/list`         | GET       | Lista rutas registradas (sin las internas `hix.*`)   |
| `/hix-routes/listall`      | GET       | Lista TODAS las rutas, incluidas las del sistema     |
| `/hix-routes/add`          | POST      | Añade una ruta nueva (body JSON)                     |
| `/hix-routes/delete`       | POST      | Elimina una ruta (body JSON `{name: "..."}`)         |
| `/hix-routes/reload`       | GET       | Recarga rutas desde `routes/*.json`                  |

### Benchmark

| Ruta                       | Método    | Descripción                                          |
|----------------------------|-----------|------------------------------------------------------|
| `/hix-bench-start`         | GET       | Resetea métricas y arranca ventana de medición       |
| `/hix-bench-stop`          | GET       | Devuelve JSON con métricas acumuladas en la ventana  |

### Autenticación

| Ruta                       | Método    | Descripción                                          |
|----------------------------|-----------|------------------------------------------------------|
| `/hix-login`               | GET/POST  | Página y submit de login admin                       |
| `/hix-logout`              | GET       | Borra la cookie `hix_admin`                          |
| `/hix-setup`               | GET/POST  | Página de creación inicial de credenciales           |

> 🔒 Si `admin.enabled = false`, ninguna de estas rutas se registra y
> cualquier petición a `/hix-*` devuelve 404.

---

## Sesión y cookie

Cuando el login es correcto, HIX firma la cookie con HMAC simulado:

```
hix_admin = <timestamp>:<md5( cAdminSecret + "|" + timestamp )>
```

En cada petición admin, `HIX_AdminCheck(oReq)`:

1. Lee la cookie `hix_admin`.
2. Verifica la firma con `cAdminSecret`.
3. Comprueba que `now - timestamp < session.lifetime * 60` (si `lifetime > 0`).
4. Si falla, redirige a `/hix-login?next=<ruta_actual>`.

La cookie es **HttpOnly; SameSite=Lax; Path=/** y se renueva en cada login.

---

## Flujo de primer arranque

```
1. Arrancas HIX por primera vez (admin user/password vacíos)
            │
            ▼
2. Accedes a /hix-status
            │
            ▼
3. HIX redirige a /hix-setup
            │
            ▼
4. Rellenas user + password (mínimo 6 chars)
            │
            ▼
5. HIX guarda user/MD5(password)/secret en hix.json
            │
            ▼
6. Redirige a /hix-login
            │
            ▼
7. Te logas → cookie hix_admin firmada → acceso libre
```

> 💡 El `secret` se genera con `MD5( timestamp + user + password )` la
> primera vez. Si quieres **invalidar todas las sesiones admin**, basta
> con vaciar `secret` en `hix.json` - HIX generará uno nuevo en el siguiente
> setup/login.

---

## Ejemplo: consumir `/hix-status` desde monitorización

```bash
# 1. Login y guarda la cookie
curl -c hix.jar -X POST https://miservidor.com/hix-login \
  -d 'user=admin&password=secreto'

# 2. Consume status
curl -b hix.jar https://miservidor.com/hix-status
```

Salida:

```json
{ "requests": 18472, "errors": 12, "uptimesec": 78423, ... }
```

Para integración con **Prometheus**, basta envolverlo en un exporter
trivial que haga GET cada 30 s.

---

## Trazas dinámicas con `/hix-trace`

`GET /hix-trace` devuelve el hash de trazas activas por módulo:

```json
{ "router": true, "session": false, "auth": true }
```

`POST /hix-trace` con body JSON ajusta una traza concreta:

```json
{ "module": "router", "enabled": true }
```

Útil para diagnosticar un problema en producción sin tocar `hix.json`.
Cuando termines, vuelve a desactivar la traza para no inflar el log.

> 📚 Más detalle en [logger - trace por módulo](logger.md#trace-por-módulo).

---

## Deshabilitar el panel

En entornos muy restrictivos puedes apagar el panel entero:

```json
{
  "admin": {
    "enabled": false
  }
}
```

Esto **no registra los endpoints admin** (`/hix-status`, `/hix-monitor`,
`/hix-stop`, `/hix-login`, `/hix-routes/*`, etc.). Las peticiones a esas
URLs devolverán 404.

> ℹ️ `/hix-ping` y `/hix-slow` **siempre** se registran (son health-check
> públicos y no dependen de `admin.enabled`).

> ⚠️ Si lo apagas, perderás `/hix-status` y los demás endpoints. Para
> monitorizar tendrás que exponer tu propio endpoint que consuma
> `HIX_MetricsJson()` con tu auth.

---

## Errores típicos

| Síntoma                                        | Causa                                              | Fix                                                |
|------------------------------------------------|----------------------------------------------------|----------------------------------------------------|
| `/hix-status` redirige a `/hix-setup`          | `admin.user` / `password` vacíos                   | Completar setup desde `/hix-setup`                 |
| Tras login, redirige otra vez a `/hix-login`   | `secret` distinto del que firmó la cookie          | Borra cookie del navegador, vuelve a logarte       |
| Cookie expira muy rápido                       | `session.lifetime` muy bajo                        | Subir el valor (minutos, `0` = indefinido)         |
| `/hix-routes/add` devuelve 401                 | Falta cookie admin o expiró                        | Login en `/hix-login` primero                      |
| No quiero login en dev                         | Estás en `env = "prod"`                            | Cambiar `app.env = "dev"`                          |

---

## Buenas prácticas

- **`app.env = "prod"` siempre en servidores expuestos a internet**. Con `"dev"`
  cualquiera puede tirar el servidor con `/hix-stop`.
- **Cambia `secret` periódicamente** vaciándolo en `hix.json` para forzar
  rotación de cookies.
- Si tu HIX está detrás de [Apache/Nginx](apache-proxy.md), **limita el
  acceso a `/hix-*` por IP** en el reverse proxy como capa extra.
- **No expongas `/hix-stop` ni `/hix-cache-clear`** en internet abierto -
  protégelos con firewall si es posible.
- Para CI/CD, **usa una cuenta admin dedicada** distinta de la del operador
  humano; rota su password al rotar el equipo.

