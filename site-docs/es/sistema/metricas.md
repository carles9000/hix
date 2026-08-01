# 🕒 Métricas

HIX mantiene en memoria un conjunto de **contadores atómicos** que
describen en tiempo real la salud y la carga del servidor: peticiones
atendidas, errores, conexiones activas, bytes transferidos, latencias,
memoria, hits del cache de vistas, etc.

Estos contadores se exponen como JSON en el endpoint `/hix-status`
(panel admin) y son consumibles desde cualquier código mediante helpers
`HIX_Metric*`. Un **thread monitor** los actualiza periódicamente con
datos del sistema (memoria, uptime, saturación de colas).

---

## ¿Cuándo lo necesitas?

- Para **monitorizar** la salud del servidor sin parsear logs.
- Para enchufar HIX a un **dashboard externo** (Prometheus, Grafana,
  Zabbix, Datadog) consumiendo el JSON.
- Para **alertas** automáticas cuando la cola de un pool se satura o la
  latencia media sube.
- Para que tu aplicación **publique sus propios contadores** de negocio
  (logins, ventas, errores de pago...) en el mismo canal.

---

## Setup en `hix.json`

### Sección `monitor`

```json
{
  "monitor": {
    "enabled":    true,
    "interval_s": 5,
    "alert_pct":  75
  }
}
```

| Clave        | Tipo | Descripción                                            |
|--------------|------|--------------------------------------------------------|
| `enabled`    | bool | Arranca el thread monitor en background                |
| `interval_s` | int  | Tick cada N segundos                                   |
| `alert_pct`  | int  | % de cola que dispara alerta `SATURATED`               |

El monitor es un **thread aparte** que cada `interval_s` segundos:

1. Actualiza `uptimesec`.
2. Lee `Memory(HB_MEM_USED)` y `Memory(HB_MEM_USEDMAX)` y publica
   `memused` / `mempeak`.
3. Comprueba que `oServer:lRunning = .T.` (detecta caídas).
4. Si alguna cola supera `alert_pct`, incrementa `saturated`.

> 💡 Con `"enabled": false` los contadores siguen existiendo y se actualizan
> desde los workers, pero **no hay tick periódico** ni medidas de memoria.

---

## Contadores disponibles

| Clave (`HIXM_*`)        | Descripción                                            |
|-------------------------|--------------------------------------------------------|
| `requests`              | Peticiones totales servidas                            |
| `errors`                | Errores devueltos (4xx/5xx)                            |
| `activehttp`            | Workers HTTP ocupados ahora mismo                      |
| `activews`              | Workers WebSocket ocupados                             |
| `activeotros`           | Workers SSE / LongPoll ocupados                        |
| `bytesin`               | Bytes recibidos en bodies                              |
| `bytesout`              | Bytes enviados en respuestas                           |
| `saturated`             | Veces que una cola pasó del umbral `alert_pct`         |
| `uptimesec`             | Segundos desde arranque                                |
| `memused`               | Memoria actual (bytes, vía `Memory(HB_MEM_USED)`)      |
| `mempeak`               | Pico histórico de memoria                              |
| `req_ms_max`            | Latencia máxima registrada (ms)                        |
| `req_ms_avg`            | Latencia media móvil (ms)                              |
| `req_ms_count`          | Número de peticiones cronometradas                     |
| `req_slowest_dyn`       | Top-N peticiones más lentas (rutas dinámicas)          |
| `req_slowest_stat`      | Top-N peticiones más lentas (assets estáticos)         |
| `vcache_entries`        | Entradas en el cache RAM de vistas                     |
| `vcache_bytes`          | Bytes ocupados por el cache RAM de vistas              |
| `vcache_hits`           | Aciertos del cache                                     |
| `vcache_misses`         | Fallos del cache (compilaron/leyeron disco)            |

Todos los contadores son **enteros**, accesibles vía
`HIX_MetricGet(HIXM_REQUESTS)` o por su clave string directa.

---

## API desde código

```clipper
// Incrementar (delta opcional, default 1)
HIX_Metric( "miapp.logins" )
HIX_Metric( "miapp.bytes_subidos", 4096 )

// Decrementar (Max(0, ...) - nunca negativos)
HIX_MetricDec( "miapp.sesiones_activas" )

// Set absoluto
HIX_MetricSet( "miapp.usuarios_online", 47 )

// Lectura
nLogins := HIX_MetricGet( "miapp.logins" )

// Tiempos por petición (la media móvil + top-N)
HIX_MetricTiming( 152, "/api/checkout" )       // genérico
HIX_MetricTimingDyn( 152, "/api/checkout" )    // sólo top dinámico
HIX_MetricTimingStat( 12, "/static/logo.png" ) // sólo top estático

// JSON serializado con todos los contadores
cJson := HIX_MetricsJson()

// Reset (mantiene el config, pone los contadores a 0)
HIX_MetricsReset()
```

> 🔒 **Thread-safe**: todos los incrementos están protegidos por mutex
> interno. Puedes llamar desde cualquier worker sin sincronizar.

---

## El endpoint `/hix-status`

Devuelve un JSON con **todos** los contadores y los top-N de latencias:

```json
{
  "requests": 18472,
  "errors": 12,
  "activehttp": 3,
  "activews": 15,
  "activeotros": 1,
  "bytesin": 4823910,
  "bytesout": 92834729,
  "saturated": 0,
  "uptimesec": 78423,
  "memused": 41943040,
  "mempeak": 52428800,
  "req_ms_max": 412,
  "req_ms_avg": 18.43,
  "req_ms_count": 18472,
  "req_slowest_dyn": [
    { "ms": 412, "at": "2026-06-27 09:14:32", "path": "/api/reports/big" },
    { "ms": 308, "at": "2026-06-27 08:51:11", "path": "/api/export/csv" }
  ],
  "req_slowest_stat": [
    { "ms": 88, "at": "2026-06-27 09:02:14", "path": "/static/video.mp4" }
  ],
  "vcache_entries": 27,
  "vcache_hits": 18221,
  "vcache_misses": 245
}
```

Está protegido por el [panel admin](hix-admin.md): en `env = prod` exige
login mediante cookie firmada `hix_admin`.

---

## Ejemplo: contador de negocio

Un controlador que registra cada login exitoso/fallido:

```clipper
// app/controllers/auth.prg
#include "hix_logger.ch"

FUNCTION login_post()
   LOCAL oVal := UValidateOrFail( { ;
      "email"    => "required|email",  ;
      "password" => "required|string"  ;
   } )

   IF oVal == NIL ; RETURN NIL ; ENDIF

   IF _CheckCredentials( oVal:Get("email"), oVal:Get("password") )
      HIX_Metric( "miapp.login.ok" )
      USession():Set( "user", oVal:Get("email") )
      USession():Save()
      RETURN URedirect( "/dashboard" )
   ENDIF

   HIX_Metric( "miapp.login.fail" )
   lw( "Login fallido: " + oVal:Get("email") )
RETURN USendView( "login.view.html", { "cError" => _( "ERR_AUTH" ) } )
```

Y un endpoint público que expone esos contadores filtrados:

```clipper
oSrv:AddRouteGet( "ventas.kpis", "/api/kpis", {|| USendJson( { ;
   "logins_ok"   => HIX_MetricGet( "miapp.login.ok"   ), ;
   "logins_fail" => HIX_MetricGet( "miapp.login.fail" ), ;
   "uptime_s"    => HIX_MetricGet( "uptimesec"        )  ;
} ) } )
```

---

## Dump por consola

```clipper
HIX_MetricsDump()
```

Imprime un resumen tabulado en el logger (útil al apagar el servidor):

```
=== Metrics ===============================
  uptime=78423s  requests=18472  errors=12
  active_http=3  active_ws=15  active_otros=1
  bytes_in=4823910  bytes_out=92834729  saturations=0
  req_ms_max=412ms  req_ms_avg=18.43ms  req_count=18472
  top slowest dyn (prg/hrb):
    412ms  2026-06-27 09:14:32  /api/reports/big
    308ms  2026-06-27 08:51:11  /api/export/csv
  top slowest stat (html/js/img/...):
     88ms  2026-06-27 09:02:14  /static/video.mp4
===========================================
```

`HIX_MetricsClose()` ejecuta `Dump()` automáticamente al cerrar.

---

## Errores típicos

| Síntoma                                  | Causa                                            | Fix                                              |
|------------------------------------------|--------------------------------------------------|--------------------------------------------------|
| `/hix-status` devuelve `{}`              | Métricas no inicializadas                        | Comprobar que `THixServer:New()` se ejecutó      |
| `memused` siempre 0                      | Monitor desactivado (`monitor.enabled = false`)  | Activarlo o llamar `HIX_MetricSet` a mano        |
| `saturated` sube sin tráfico anormal     | `alert_pct` demasiado bajo                       | Subir a 80-90 o ampliar workers del pool         |
| `req_ms_avg` muy alto                    | Pool saturado o vista lenta                      | Revisar `req_slowest_dyn`, escalar pool          |
| `vcache_hits = 0`                        | Cache deshabilitado o vistas siempre cambiantes  | Revisar config de `hixstyle.cache`               |

---

## Buenas prácticas

- **Prefijar tus contadores** con un namespace (`miapp.*`, `ventas.*`...)
  para no colisionar con los del framework.
- Reservar `req_slowest_*` para diagnosticar regresiones después de
  cambios - si una ruta nueva aparece arriba, atención.
- En microservicios, **scrap el JSON cada 10-30 s** desde Prometheus.
  No hace falta más resolución que `interval_s`.
- Para resetear entre tests de carga: `HIX_MetricsReset()` antes de
  empezar y `HIX_MetricsJson()` al terminar.
- Métricas **no son logs**: no las uses para registrar eventos únicos,
  sólo para agregados numéricos.

---

## Métricas vs. Boot Log

Suelen confundirse — no son lo mismo:

| Aspecto      | Métricas                                | [Boot Log](bootlog.md)                  |
|--------------|-----------------------------------------|-----------------------------------------|
| Ventana      | **Runtime** (mientras el server atiende)| **Arranque** (una única vez, al iniciar)|
| Contenido    | Contadores numéricos (agregados)        | Eventos discretos con status y payload  |
| Actualización| Continua (workers, monitor thread)      | Sólo al inicializar subsistemas         |
| Uso típico   | Dashboards, alertas, SLOs               | Diagnóstico del arranque, panel admin   |
| Reset        | `HIX_MetricsReset()` (manual)           | Automático al re-arrancar `_Init()`     |

Úsalos juntos: el **boot log** te dice si el arranque fue correcto, las
**métricas** cómo se comporta el servidor una vez en marcha.
