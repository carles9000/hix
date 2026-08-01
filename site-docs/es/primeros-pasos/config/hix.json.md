# 🛠️ Configuración `hix.json`

Toda la configuración de HIX vive en un único archivo `hix.json` situado junto
al ejecutable del servidor. Sirve igual para usar HIX en modo **básico**
(rutas programáticas, plantillas a mano) que para el modo **HixStyle**
(motor MVC, loaders, views, controllers).

---



## Convención de las columnas

En la tabla maestra cada parámetro lleva dos columnas con la marca de
entorno:

| Columna       | Significado                                                          |
|---------------|----------------------------------------------------------------------|
| **Básico**    | Afecta al servidor en modo HIX básico (rutas Harbour programáticas + estáticos)|
| **HixStyle**  | Afecta al servidor en modo HixStyle (`enabled = true`)                      |

✅ = el parámetro es relevante en ese entorno.
❌ = el parámetro **no tiene efecto** o no se usa en ese entorno.

Las claves marcadas únicamente en **HixStyle** son:

- Toda la sección `hixstyle`

El resto afecta a los **dos** entornos por igual.

---

## Tabla maestra de parámetros

| Sección        | Clave             | Default        | Básico | HixStyle | Descripción                                                                       |
|----------------|-------------------|----------------|:------:|:--------:|-----------------------------------------------------------------------------------|
| `server`       | `host`            | `localhost`    |   ✅   |    ✅    | Interfaz de escucha. `0.0.0.0` = todas. `localhost` = solo local.                 |
| `server`       | `port`            | `80`           |   ✅   |    ✅    | Puerto TCP. Puertos < 1024 requieren admin/root.                                  |
| `server`       | `maxconn`         | `1024`         |   ✅   |    ✅    | Conexiones simultáneas máximas.                                                   |
| `server`       | `timeout`         | `30`           |   ✅   |    ✅    | Timeout de conexión (segundos).                                                   |
| `server`       | `name`            | `HIX/2.1`      |   ✅   |    ✅    | Valor de la cabecera HTTP `Server:`.                                              |
| `server`       | `mode`            | `standalone`   |   ✅   |    ✅    | `standalone` o `proxied` (detrás de nginx/Apache).                                |
| `server`       | `trusted_proxies` | `127.0.0.1 ::1`|   ✅   |    ✅    | IPs/CIDR de confianza, separados por espacio (`mode=proxied`).                    |
| `server`       | `ssl`             | `false`        |   ✅   |    ✅    | Activa TLS. Requiere `cert_private` + `cert_public`.                              |
| `server`       | `cert_private`    | `""`           |   ✅   |    ✅    | Nombre del fichero de clave privada `.key` (dentro de `paths.certs`).             |
| `server`       | `cert_public`     | `""`           |   ✅   |    ✅    | Nombre del fichero de certificado `.crt` (dentro de `paths.certs`).               |
| `server`       | `gzip`            | `true`         |   ✅   |    ✅    | Comprime respuestas HTTP.                                                         |
| `server`       | `gzip_min_size`   | `2048`         |   ✅   |    ✅    | Tamaño mínimo del body para comprimir (bytes).                                    |
| `server`       | `autostart`       | `true`         |   ✅   |    ✅    | Abre el navegador en la URL del servidor al arrancar.                             |
| `server`       | `exec_timeout_ms` | `30000`        |   ✅   |    ✅    | Tiempo máximo de ejecución para `.prg`/`.hrb` (ms). `0` = sin límite.             |
| `paths`        | `root`            | `www`          |   ✅   |    ✅    | Document root.                                                                    |
| `paths`        | `log`             | `.logs`        |   ✅   |    ✅    | Directorio de logs.                                                               |
| `paths`        | `tmp`             | `tmp`          |   ✅   |    ✅    | Temporales (uploads, transpiles).                                                 |
| `paths`        | `errors`          | `.logs`        |   ✅   |    ✅    | Páginas custom de error HTTP.                                                     |
| `paths`        | `session`         | `.sessions`    |   ✅   |    ✅    | Almacenamiento de sesiones (storage=`file`).                                      |
| `paths`        | `certs`           | `certs`        |   ✅   |    ✅    | Directorio de certificados SSL/TLS.                                               |
| `app`          | `errorsys`        | `""`           |   ✅   |    ✅    | Template HTML del error sys (relativo a `root/`). Vacío = usa el built-in.        |
| `app`          | `default_page`    | `index.html`   |   ✅   |    ✅    | Recurso por defecto cuando la URL no incluye fichero.                             |
| `app`          | `dispatch_mode`   | `full`         |   ✅   |    ✅    | `routes` (solo programáticas) / `static` (+ ficheros) / `full` (+ prg/hrb).       |
| `app`          | `auto_close_dbf`  | `true`         |   ✅   |    ✅    | Cierra DBFs abiertos al terminar la request.                                      |
| `app`          | `auto_close_dbf_log` | `false`     |   ✅   |    ✅    | Loguea cada auto-cierre de DBF.                                                   |
| `app`          | `env`             | `dev`          |   ✅   |    ✅    | `dev` (errores detallados) / `prod` (errores genéricos).                          |
| `app`          | `debug`           | `false`        |   ✅   |    ✅    | `true` = nivel DEBUG en consola.                                                  |
| `admin`        | `enabled`         | `true`         |   ✅   |    ✅    | `false` = desactiva el panel admin y todas las rutas `/hix-*`.                    |
| `admin`        | `user`            | `""`           |   ✅   |    ✅    | Usuario admin.                                                                    |
| `admin`        | `password`        | `""`           |   ✅   |    ✅    | Hash MD5 de la contraseña. Vacío = muestra `/hix-setup`.                          |
| `admin`        | `secret`          | `""`           |   ✅   |    ✅    | Clave de firma de cookie, auto-generada por `/hix-setup`.                         |
| `detector`     | `workers`         | `4`            |   ✅   |    ✅    | Workers que detectan protocolo en cada nueva conexión.                            |
| `detector`     | `queue_size`      | `256`          |   ✅   |    ✅    | Cola interna.                                                                     |
| `detector`     | `peek_timeout_ms` | `100`          |   ✅   |    ✅    | Espera máxima del primer byte. LAN=10, internet=50.                               |
| `detector`     | `peek_bytes`      | `512`          |   ✅   |    ✅    | Bytes a leer para identificar el protocolo.                                       |
| `pool_http`    | `workers`         | `64`           |   ✅   |    ✅    | Workers HTTP (~1MB stack/thread en Windows).                                      |
| `pool_http`    | `queue_size`      | `256`          |   ✅   |    ✅    | Cola de requests pendientes.                                                      |
| `pool_http`    | `read_timeout_ms` | `2000`         |   ✅   |    ✅    | Timeout de lectura de cabeceras HTTP (ms).                                        |
| `pool_http`    | `keep_alive`      | `true`         |   ✅   |    ✅    | Activa HTTP Keep-Alive.                                                           |
| `pool_http`    | `keep_alive_max`  | `100`          |   ✅   |    ✅    | Requests máximos por conexión keep-alive.                                         |
| `pool_ws`      | `workers`         | `100`          |   ✅   |    ✅    | Workers WebSocket. Cada WS activo ocupa 1 worker hasta cerrar.                    |
| `pool_ws`      | `queue_size`      | `256`          |   ✅   |    ✅    | Cola de conexiones pendientes.                                                    |
| `pool_ws`      | `ping_interval_s` | `30`           |   ✅   |    ✅    | Intervalo de ping al cliente (segundos).                                          |
| `pool_ws`      | `ping_timeout_s`  | `10`           |   ✅   |    ✅    | Timeout de respuesta al ping (segundos).                                          |
| `pool_rest`    | `workers_sse`     | `20`           |   ✅   |    ✅    | Workers para Server-Sent Events (cada SSE ocupa 1).                               |
| `pool_rest`    | `workers_longpoll`| `10`           |   ✅   |    ✅    | Workers para Long Polling.                                                        |
| `pool_rest`    | `queue_size`      | `128`          |   ✅   |    ✅    | Cola compartida.                                                                  |
| `pool_rest`    | `stream_timeout_s`| `3600`         |   ✅   |    ✅    | Duración máxima de un stream abierto (segundos).                                  |
| `pool_hix`     | `workers`         | `4`            |   ✅   |    ✅    | Workers dedicados al canal HIX interno.                                           |
| `pool_hix`     | `queue_size`      | `64`           |   ✅   |    ✅    | Cola del pool HIX.                                                                |
| `pool_hix`     | `read_timeout_ms` | `2000`         |   ✅   |    ✅    | Timeout de lectura (ms).                                                          |
| `session`      | `storage`         | `memory`       |   ✅   |    ✅    | `memory` (volátil, rápido) / `file` (persistente).                                |
| `session`      | `prefix`          | `sess_`        |   ✅   |    ✅    | Prefijo del nombre de fichero de sesión.                                          |
| `session`      | `crypt`           | `false`        |   ✅   |    ✅    | Encripta datos de sesión en disco.                                                |
| `session`      | `seed`            | `""`           |   ✅   |    ✅    | Clave de encriptación (obligatoria si `crypt=true`).                              |
| `session`      | `lifetime`        | `60`           |   ✅   |    ✅    | Vida de la sesión en minutos (aplica a cookie usuario y admin). `0` = indefinido. |
| `session`      | `gc_days`         | `3`            |   ✅   |    ✅    | Días para GC de ficheros de sesión huérfanos (solo `storage=file`).               |
| `monitor`      | `enabled`         | `true`         |   ✅   |    ✅    | Activa el hilo monitor de salud.                                                  |
| `monitor`      | `interval_s`      | `5`            |   ✅   |    ✅    | Intervalo de comprobación (segundos).                                             |
| `monitor`      | `alert_pct`       | `75`           |   ✅   |    ✅    | % de uso de cola que dispara la alerta `SATURATED`.                               |
| `log`          | `file`            | `hix.log`      |   ✅   |    ✅    | Nombre del fichero de log (ruta = `paths.log`).                                   |
| `log`          | `level`           | `info`         |   ✅   |    ✅    | `debug` / `info` / `warn` / `error` / `fatal`.                                    |
| `log`          | `console`         | `true`         |   ✅   |    ✅    | `true` = duplica la salida en consola.                                            |
| `log`          | `max_size_mb`     | `10`           |   ✅   |    ✅    | Tamaño máximo antes de rotar (MB).                                                |
| `log`          | `max_files`       | `0`            |   ✅   |    ✅    | Backups máximos retenidos. `0` = ilimitado.                                       |
| `access_log`   | `enabled`         | `true`         |   ✅   |    ✅    | Activa el log de acceso HTTP (Common Log Format).                                 |
| `access_log`   | `file`            | `access.log`   |   ✅   |    ✅    | Nombre del fichero de access log (ruta = `paths.log`).                            |
| `firewall`     | `mode`            | `blacklist`    |   ✅   |    ✅    | `blacklist` (bloquea listadas) / `whitelist` (solo listadas).                     |
| `firewall`     | `filter`          | `""`           |   ✅   |    ✅    | Lista de IP/CIDR separadas por coma. Ej.: `192.168.1.0/24, 10.0.0.0/8`.           |
| `hixstyle`     | `enabled`         | `false`        |   ❌   |    ✅    | Activa el motor MVC HixStyle.                                                     |
| `hixstyle`     | `cache_disk`      | `true`         |   ❌   |    ✅    | Cachea las views compiladas a disco (`.cached/views/`).                           |
| `hixstyle`     | `trace`           | `false`        |   ❌   |    ✅    | Activa el trace de HixStyle en el log.                                            |
| `hixstyle`     | `cache_ram`       | `false`        |   ❌   |    ✅    | Cache global de views en RAM compartida entre workers. ~10× más rápido que disco. |
| `trace`        | `app`             | `true`         |   ✅   |    ✅    | Trace del módulo `app`.                                                           |
| `trace`        | `server`          | `true`         |   ✅   |    ✅    | Trace del módulo `server`.                                                        |
| `trace`        | `worker_http`     | `false`        |   ✅   |    ✅    | Trace del worker HTTP.                                                            |
| `trace`        | `worker_ws`       | `false`        |   ✅   |    ✅    | Trace del worker WebSocket.                                                       |
| `trace`        | `worker_otros`    | `false`        |   ✅   |    ✅    | Trace del worker SSE/LongPoll.                                                    |
| `trace`        | `pool`            | `false`        |   ✅   |    ✅    | Trace de los pools.                                                               |
| `trace`        | `pool_detector`   | `false`        |   ✅   |    ✅    | Trace del detector de protocolo.                                                  |
| `trace`        | `metrics`         | `false`        |   ✅   |    ✅    | Trace del módulo de métricas.                                                     |
| `trace`        | `config`          | `false`        |   ✅   |    ✅    | Trace de carga de configuración.                                                  |
| `trace`        | `socket`          | `false`        |   ✅   |    ✅    | Trace de operaciones de socket.                                                   |
| `trace`        | `monitor`         | `false`        |   ✅   |    ✅    | Trace del monitor.                                                                |
| `trace`        | `response`        | `false`        |   ✅   |    ✅    | Trace del módulo response.                                                        |
| `trace`        | `logger`          | `false`        |   ✅   |    ✅    | Trace del propio logger.                                                          |
| `trace`        | `error`           | `false`        |   ✅   |    ✅    | Trace de errores.                                                                 |

> Toggle de trace en caliente: `GET /hix-trace?mod=<modulo>&on=1`.
> `WARN`/`ERROR`/`FATAL` siempre se loguean, independientemente del trace.

---

## Resumen por sección

### `server` - red e identidad
Define cómo escucha el servidor: interfaz, puerto, TLS y modo (standalone o
detrás de proxy). Tocar antes del primer arranque en producción.

### `paths` - disposición en disco
Estructura raíz del servidor. Cambia si quieres reubicar `www/`, logs o
sesiones a otra unidad.

### `app` - aplicación
Template `errorsys` para la pantalla de error del sistema, `env` (dev/prod),
`debug`, dispatcher, timeout de ejecución, página por defecto. Las páginas
custom de error viven en la carpeta fija `<paths.root>/errors/`. El
fichero `<paths.root>/config.json` (opcional) y la carpeta
`<paths.root>/loaders/` (opcional) se cargan automáticamente si existen.

### `admin` - panel `/hix-*`
Credenciales del panel admin. Si dejas `password` vacío, el primer acceso a
`/hix-setup` lo configura. `enabled = false` apaga todas las rutas `/hix-*`.

### `detector`, `pool_http`, `pool_ws`, `pool_rest`, `pool_hix` - concurrencia
Tamaños de pool y colas. Los defaults aguantan tráfico medio; ajusta si el
monitor reporta saturación (`SATURATED` cuando la cola supera `alert_pct`).

### `session` - sesiones HTTP
`memory` es lo más rápido pero se pierde al reiniciar. `file` persiste pero
añade I/O. Para multi-proceso usa siempre `file` con `seed`.

### `monitor`, `log`, `access_log` - observabilidad
Logger principal con rotación, access log CLF y monitor de salud que expone
`/hix-status`. Ver también: [sistema/logger](../../sistema/logger.md),
[sistema/metricas](../../sistema/metricas.md).

### `firewall` - filtrado por IP
Lista blanca o negra de IPs/CIDR. Ver
[hixstyle/seguridad/firewall](../../hixstyle/seguridad/firewall.md).

### `hixstyle` - motor MVC
Activa y afina HixStyle. Solo se aplica si `enabled = true`.

### `trace` - verbosidad por módulo
Flags binarios para activar trazas de cada módulo del core. Útil para
diagnosticar problemas concretos sin inundar el log.


Aunque se pueden observar numerosos parámetro, no deja de ser la definición de los 
parámetros de uns ervidor web. No debes de cambiar estos parámetros si no conoces 
exactamente su funcionalidad. No debes preocuparte al principio porque todo está 
ya configurado.