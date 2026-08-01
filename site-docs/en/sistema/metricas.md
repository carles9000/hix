# 🕒 Metrics

HIX maintains in memory a set of **atomic counters** that describe in real time
the health and load of the server: requests served, errors, active connections,
bytes transferred, latencies, memory, view cache hits, etc.

These counters are exposed as JSON at the `/hix-status` endpoint (admin panel)
and can be consumed from any code via `HIX_Metric*` helpers. A **monitor thread**
periodically updates them with system data (memory, uptime, queue saturation).

---

## When do you need it?

- To **monitor** server health without parsing logs.
- To plug HIX into an **external dashboard** (Prometheus, Grafana, Zabbix,
  Datadog) by consuming the JSON.
- For **automatic alerts** when a pool queue saturates or average latency
  increases.
- For your application to **publish its own business counters** (logins, sales,
  payment errors...) through the same channel.

---

## Setup in `hix.json`

### `monitor` section

```json
{
  "monitor": {
    "enabled":    true,
    "interval_s": 5,
    "alert_pct":  75
  }
}
```

| Key          | Type | Description                                      |
|--------------|------|--------------------------------------------------|
| `enabled`    | bool | Starts the monitor thread in the background      |
| `interval_s` | int  | Tick every N seconds                             |
| `alert_pct`  | int  | % of queue that triggers an `SATURATED` alert    |

The monitor is a **separate thread** that every `interval_s` seconds:

1. Updates `uptimesec`.
2. Reads `Memory(HB_MEM_USED)` and `Memory(HB_MEM_USEDMAX)` and publishes
   `memused` / `mempeak`.
3. Checks that `oServer:lRunning = .T.` (detects crashes).
4. If any queue exceeds `alert_pct`, increments `saturated`.

> 💡 With `"enabled": false` the counters still exist and are updated by
> workers, but **there's no periodic tick** or memory measurements.

---

## Available counters

| Key (`HIXM_*`)          | Description                                          |
|-------------------------|------------------------------------------------------|
| `requests`              | Total requests served                                |
| `errors`                | Errors returned (4xx/5xx)                            |
| `activehttp`            | HTTP workers busy right now                          |
| `activews`              | WebSocket workers busy                               |
| `activeotros`           | SSE / LongPoll workers busy                          |
| `bytesin`               | Bytes received in bodies                             |
| `bytesout`              | Bytes sent in responses                              |
| `saturated`             | Times a queue exceeded the `alert_pct` threshold     |
| `uptimesec`             | Seconds since startup                                |
| `memused`               | Current memory (bytes, via `Memory(HB_MEM_USED)`)    |
| `mempeak`               | Historical peak memory                               |
| `req_ms_max`            | Maximum latency recorded (ms)                        |
| `req_ms_avg`            | Moving average latency (ms)                          |
| `req_ms_count`          | Number of timed requests                             |
| `req_slowest_dyn`       | Top-N slowest requests (dynamic routes)              |
| `req_slowest_stat`      | Top-N slowest requests (static assets)               |
| `vcache_entries`        | Entries in the view RAM cache                        |
| `vcache_bytes`          | Bytes occupied by the view RAM cache                 |
| `vcache_hits`           | Cache hits                                           |
| `vcache_misses`         | Cache misses (compiled/read from disk)               |

All counters are **integers**, accessible via `HIX_MetricGet(HIXM_REQUESTS)` or
by their direct string key.

---

## API from code

```clipper
// Increment (delta optional, default 1)
HIX_Metric( "myapp.logins" )
HIX_Metric( "myapp.bytes_uploaded", 4096 )

// Decrement (Max(0, ...) - never negative)
HIX_MetricDec( "myapp.active_sessions" )

// Absolute set
HIX_MetricSet( "myapp.users_online", 47 )

// Read
nLogins := HIX_MetricGet( "myapp.logins" )

// Timings per request (moving average + top-N)
HIX_MetricTiming( 152, "/api/checkout" )       // generic
HIX_MetricTimingDyn( 152, "/api/checkout" )    // dynamic top only
HIX_MetricTimingStat( 12, "/static/logo.png" ) // static top only

// JSON serialized with all counters
cJson := HIX_MetricsJson()

// Reset (keeps config, puts counters to 0)
HIX_MetricsReset()
```

> 🔒 **Thread-safe**: all increments are protected by internal mutex. You can
> call from any worker without synchronizing.

---

## The `/hix-status` endpoint

Returns a JSON with **all** counters and the top-N latencies:

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

It's protected by the [admin panel](hix-admin.md): in `env = prod` it requires
login via the signed `hix_admin` cookie.

---

## Example: business counter

A controller that records each successful/failed login:

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
      HIX_Metric( "myapp.login.ok" )
      USession():Set( "user", oVal:Get("email") )
      USession():Save()
      RETURN URedirect( "/dashboard" )
   ENDIF

   HIX_Metric( "myapp.login.fail" )
   lw( "Failed login: " + oVal:Get("email") )
RETURN USendView( "login.view.html", { "cError" => _( "ERR_AUTH" ) } )
```

And a public endpoint that exposes those filtered counters:

```clipper
oSrv:AddRouteGet( "ventas.kpis", "/api/kpis", {|| USendJson( { ;
   "logins_ok"   => HIX_MetricGet( "myapp.login.ok"   ), ;
   "logins_fail" => HIX_MetricGet( "myapp.login.fail" ), ;
   "uptime_s"    => HIX_MetricGet( "uptimesec"        )  ;
} ) } )
```

---

## Console dump

```clipper
HIX_MetricsDump()
```

Prints a tabulated summary in the logger (useful when shutting down the server):

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

`HIX_MetricsClose()` automatically executes `Dump()` on shutdown.

---

## Common errors

| Symptom                                | Cause                                             | Fix                                         |
|----------------------------------------|---------------------------------------------------|---------------------------------------------|
| `/hix-status` returns `{}`             | Metrics not initialized                           | Check that `THixServer:New()` executed      |
| `memused` always 0                     | Monitor disabled (`monitor.enabled = false`)      | Activate it or call `HIX_MetricSet` manually|
| `saturated` increases without abnormal traffic | `alert_pct` too low                   | Raise to 80-90 or expand pool workers       |
| `req_ms_avg` very high                 | Pool saturated or slow view                       | Check `req_slowest_dyn`, scale pool         |
| `vcache_hits = 0`                      | Cache disabled or views always changing           | Check `hixstyle.cache` config                |

---

## Best practices

- **Prefix your counters** with a namespace (`myapp.*`, `sales.*`...) to
  avoid colliding with framework counters.
- Reserve `req_slowest_*` for diagnosing regressions after changes — if a new
  route appears at the top, pay attention.
- In microservices, **scrape the JSON every 10-30 seconds** from Prometheus.
  No need for higher resolution than `interval_s`.
- To reset between load tests: `HIX_MetricsReset()` before starting and
  `HIX_MetricsJson()` when done.
- Metrics **are not logs**: don't use them to record unique events, only for
  numeric aggregates.

---

## Metrics vs. Boot Log

They're often confused — they're not the same:

| Aspect       | Metrics                                 | [Boot Log](bootlog.md)                       |
|--------------|-----------------------------------------|----------------------------------------------|
| Window       | **Runtime** (while server is running)   | **Startup** (once only, on initialization)   |
| Content      | Numeric counters (aggregates)           | Discrete events with status and payload      |
| Update       | Continuous (workers, monitor thread)    | Only when initializing subsystems            |
| Typical use  | Dashboards, alerts, SLOs                | Startup diagnosis, admin panel               |
| Reset        | `HIX_MetricsReset()` (manual)           | Automatic on re-boot `_Init()`               |

Use them together: the **boot log** tells you if startup was correct, the
**metrics** show how the server behaves once running.
