# Logger

**HIX** incluye un **logger thread-safe** centralizado que registra eventos del
servidor en un fichero con rotación automática. Lo usan tanto el propio
servidor (arranque, rutas, errores, sesiones, etc.) como tu aplicación
mediante las macros `l()`, `lw()`, `le()`, `lf()` y `ld()`.

Junto al log general (`hix.log`), HIX mantiene en paralelo un **access log
estilo CLF** (`access.log`) con una línea por cada petición HTTP atendida.

---

## ¿Cuándo lo necesitas?

- Para **diagnosticar** comportamientos del servidor en producción sin
  detenerlo.
- Para llevar un **rastro auditable** de las peticiones HTTP recibidas
  (`access.log`).
- Para que tus controladores y middlewares dejen **traza estructurada**
  con niveles de severidad.

---

## Setup en `hix.json`

### Sección `paths`

Define el directorio común donde se escriben todos los logs:

```json
{
  "paths": {
    "log": ".logs"
  }
}
```

### Sección `log` - log general

`level`: `debug` | `info` | `warn` | `error` | `fatal`.
`console = true` imprime también a consola.
`max_size_mb`: MB para rotación al superar este tamaño.
`max_files = 0`: sin límite de backups.

```json
{
  "log": {
    "file":        "hix.log",
    "level":       "info",
    "console":     true,
    "max_size_mb": 10,
    "max_files":   0
  }
}
```

### Sección `access_log` - log de peticiones

```json
{
  "access_log": {
    "enabled": true,
    "file":    "access.log"
  }
}
```

El access log se genera **automáticamente** desde
`THixRequest:Respond()` - no requieres llamarlo a mano.

> 💡 `errors.log` se reserva para registros futuros de errores HTTP
> estructurados; hoy todos los errores van al log general con nivel
> `ERROR` o `FATAL`.

---

## Niveles

| Macro  | Constante         | Nivel | Cuándo usarla                              |
|--------|-------------------|-------|--------------------------------------------|
| `ld()` | `HIX_LOG_DEBUG`   | 1     | Detalles internos, sólo desarrollo         |
| `l()`  | `HIX_LOG_INFO`    | 2     | Información operativa normal               |
| `lw()` | `HIX_LOG_WARN`    | 3     | Algo recuperable que conviene vigilar      |
| `le()` | `HIX_LOG_ERROR`   | 4     | Error que afecta a la petición o subsistema|
| `lf()` | `HIX_LOG_FATAL`   | 5     | Error grave que puede tumbar el servidor   |

Sólo se escriben los mensajes **iguales o superiores** al `level`
configurado. `level=info` filtra los `ld()`; `level=warn` filtra `ld()` y
`l()`; etc.

---

## Uso desde código

Cualquier `.prg` que quiera loguear debe incluir el header de macros:

```clipper
#include "hix_logger.ch"

FUNCTION MiControlador()
   l( "Acceso a panel de usuario" )
   IF ! _CheckPermissions()
      lw( "Intento de acceso sin permisos desde " + UIP() )
      RETURN USendError( 403 )
   ENDIF
   le( "Algo fue mal con la base de datos" )
RETURN NIL
```

### Formato de salida

```
[2026-06-27 09:14:32.123] [INFO ] [router] Route /users/42 -> users.show
[2026-06-27 09:14:32.456] [WARN ] [auth  ] Login fallido: carles
[2026-06-27 09:14:32.789] [ERROR] [db    ] Cannot open customers.dbf
```

Cada línea contiene:

1. Timestamp con milisegundos.
2. Nivel de severidad.
3. Módulo emisor (definido por `#define HIX_LOG_MODULE` al inicio del .prg).
4. Mensaje libre.

> 📚 El módulo se declara así en cada fichero `.prg` del framework
> (y puedes hacer lo mismo en el tuyo):
>
> ```clipper
> #define HIX_LOG_MODULE "miapp.users"
> #include "hix_logger.ch"
> ```

---

## Rotación automática

Cuando `hix.log` alcanza `max_size_mb`:

1. El fichero actual se renombra a `hix_YYYYMMDDHHMMSS_NNNNNN.log`.
2. Se crea un nuevo `hix.log` vacío.
3. Si `max_files > 0`, se borran los backups más antiguos para mantener
   sólo `max_files` ficheros históricos.

La rotación es **transparente**: ningún log se pierde, los handlers de
escritura se sincronizan mediante mutex.

```text
.logs/
   ├── hix.log                              <- activo
   ├── hix_20260620120134000000.log         <- rotado
   ├── hix_20260622150812000000.log
   └── access.log                           <- activo (sin rotación automática)
```

> ⚠️ `access.log` **no rota automáticamente**. Si lo necesitas con tráfico
> alto, configura `logrotate` (Linux) o un script programado (Windows).

---

## Access log: formato CLF

`access.log` sigue el [Common Log Format](https://en.wikipedia.org/wiki/Common_Log_Format)
estándar de Apache:

```
192.168.1.100 - - [27/Jun/2026:09:14:32 +0000] "GET /users/42 HTTP/1.1" 200
192.168.1.100 - - [27/Jun/2026:09:14:35 +0000] "POST /login HTTP/1.1" 302
10.0.0.5      - - [27/Jun/2026:09:14:40 +0000] "GET /admin HTTP/1.1" 403
```

Compatible con herramientas estándar (`awstats`, `goaccess`, `lnav`...).

---

## Trace por módulo

`ld()` y `l()` admiten un filtro adicional por **módulo emisor**. Esto te
permite activar el detalle sólo de un subsistema sin inundar el log:

```clipper
HIX_TraceSet( "router",  .T. )   // activa DEBUG/INFO de router
HIX_TraceSet( "session", .F. )   // silencia DEBUG/INFO de session
HIX_TraceAll( .T. )              // activa todo
```

Los niveles `WARN`, `ERROR` y `FATAL` **siempre pasan** sin importar el
filtro de trace. Esta es la diferencia clave con el simple `level`:

- `level` = umbral global por severidad.
- `HIX_TraceSet` = filtro fino por módulo, sólo para los niveles bajos.

> 🔧 Útil para diagnosticar un problema en producción sin bajar el `level`
> general a `debug` (lo que generaría logs enormes).

---

## Inicialización manual

En aplicaciones standalone que arrancan `THixServer` sin pasar por
`hix.json`, debes inicializar el logger tú mismo:

```clipper
HIX_LoggerInit( "logs/app.log", HIX_LOG_DEBUG, .T., 10485760, 5 )
//              ^cFile           ^level         ^console ^maxsize  ^maxfiles
```

En el flujo normal con `hix.json`, `THixServer:New()` se encarga.

---

## Errores típicos

| Síntoma                                | Causa                                                          | Fix                                  |
|----------------------------------------|----------------------------------------------------------------|--------------------------------------|
| El log está vacío                      | Nivel por encima de los mensajes emitidos                      | Bajar `level` a `debug` o `info`     |
| Aparece en consola pero no en fichero  | `paths.log` apunta a un directorio sin permiso de escritura    | Crear/permitir el directorio         |
| `access.log` no se escribe             | `access_log.enabled = false`                                   | Poner `enabled = true`               |
| Logs antiguos no se borran             | `max_files = 0`                                                | Definir un límite (`max_files = 10`) |
| Falta el `l()` en un .prg              | Olvidaste `#include "hix_logger.ch"`                           | Añadirlo en cabecera                 |




