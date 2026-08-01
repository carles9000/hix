# Logger

**HIX** includes a **thread-safe centralized logger** that records server events
in a file with automatic rotation. It's used both by the server itself
(startup, routes, errors, sessions, etc.) and your application
via the macros `l()`, `lw()`, `le()`, `lf()`, and `ld()`.

Along with the general log (`hix.log`), HIX maintains in parallel an
**Apache-style CLF access log** (`access.log`) with one line per HTTP request served.

---

## When do you need it?

- To **diagnose** server behavior in production without
  stopping it.
- To keep an **auditable record** of the HTTP requests received
  (`access.log`).
- To have your controllers and middlewares leave **structured traces**
  with severity levels.

---

## Setup in `hix.json`

### Section `paths`

Define the common directory where all logs are written:

```json
{
  "paths": {
    "log": ".logs"
  }
}
```

### Section `log` - general log

`level`: `debug` | `info` | `warn` | `error` | `fatal`.
`console = true` also prints to console.
`max_size_mb`: MB for rotation when this size is exceeded.
`max_files = 0`: unlimited backups.

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

### Section `access_log` - request log

```json
{
  "access_log": {
    "enabled": true,
    "file":    "access.log"
  }
}
```

The access log is generated **automatically** from
`THixRequest:Respond()` - you don't need to call it manually.

> 💡 `errors.log` is reserved for future structured HTTP error records;
> today all errors go to the general log with level
> `ERROR` or `FATAL`.

---

## Levels

| Macro  | Constant          | Level | When to use                                |
|--------|-------------------|-------|--------------------------------------------|
| `ld()` | `HIX_LOG_DEBUG`   | 1     | Internal details, development only         |
| `l()`  | `HIX_LOG_INFO`    | 2     | Normal operational information             |
| `lw()` | `HIX_LOG_WARN`    | 3     | Something recoverable that deserves watching |
| `le()` | `HIX_LOG_ERROR`   | 4     | Error affecting the request or subsystem   |
| `lf()` | `HIX_LOG_FATAL`   | 5     | Serious error that can crash the server    |

Only messages **equal to or higher** than the configured `level`
are written. `level=info` filters out `ld()`; `level=warn` filters out `ld()` and
`l()`; etc.

---

## Usage from code

Any `.prg` that wants to log must include the macros header:

```clipper
#include "hix_logger.ch"

FUNCTION MyController()
   l( "Access to user panel" )
   IF ! _CheckPermissions()
      lw( "Unauthorized access attempt from " + UIP() )
      RETURN USendError( 403 )
   ENDIF
   le( "Something went wrong with the database" )
RETURN NIL
```

### Output format

```
[2026-06-27 09:14:32.123] [INFO ] [router] Route /users/42 -> users.show
[2026-06-27 09:14:32.456] [WARN ] [auth  ] Login failed: carles
[2026-06-27 09:14:32.789] [ERROR] [db    ] Cannot open customers.dbf
```

Each line contains:

1. Timestamp with milliseconds.
2. Severity level.
3. Sending module (defined by `#define HIX_LOG_MODULE` at the start of the .prg).
4. Free message.

> 📚 The module is declared like this in each framework `.prg` file
> (and you can do the same in yours):
>
> ```clipper
> #define HIX_LOG_MODULE "myapp.users"
> #include "hix_logger.ch"
> ```

---

## Automatic rotation

When `hix.log` reaches `max_size_mb`:

1. The current file is renamed to `hix_YYYYMMDDHHMMSS_NNNNNN.log`.
2. A new empty `hix.log` is created.
3. If `max_files > 0`, the oldest backups are deleted to keep
   only `max_files` historical files.

Rotation is **seamless**: no logs are lost, write handlers
are synchronized via mutex.

```text
.logs/
   ├── hix.log                              <- active
   ├── hix_20260620120134000000.log         <- rotated
   ├── hix_20260622150812000000.log
   └── access.log                           <- active (no automatic rotation)
```

> ⚠️ `access.log` **does not rotate automatically**. If you need it with
> high traffic, configure `logrotate` (Linux) or a scheduled script (Windows).

---

## Access log: CLF format

`access.log` follows the [Common Log Format](https://en.wikipedia.org/wiki/Common_Log_Format)
standard from Apache:

```
192.168.1.100 - - [27/Jun/2026:09:14:32 +0000] "GET /users/42 HTTP/1.1" 200
192.168.1.100 - - [27/Jun/2026:09:14:35 +0000] "POST /login HTTP/1.1" 302
10.0.0.5      - - [27/Jun/2026:09:14:40 +0000] "GET /admin HTTP/1.1" 403
```

Compatible with standard tools (`awstats`, `goaccess`, `lnav`...).

---

## Per-module tracing

`ld()` and `l()` accept an additional **sending module** filter. This lets you
activate detail only from one subsystem without flooding the log:

```clipper
HIX_TraceSet( "router",  .T. )   // activate DEBUG/INFO from router
HIX_TraceSet( "session", .F. )   // silence DEBUG/INFO from session
HIX_TraceAll( .T. )              // activate all
```

The levels `WARN`, `ERROR`, and `FATAL` **always pass** regardless of the
trace filter. This is the key difference from simple `level`:

- `level` = global threshold by severity.
- `HIX_TraceSet` = fine-grained filter by module, only for lower levels.

> 🔧 Useful for diagnosing a production issue without lowering the `level`
> setting to `debug` (which would generate huge logs).

---

## Manual initialization

In standalone applications that start `THixServer` without going through
`hix.json`, you must initialize the logger yourself:

```clipper
HIX_LoggerInit( "logs/app.log", HIX_LOG_DEBUG, .T., 10485760, 5 )
//              ^cFile           ^level         ^console ^maxsize  ^maxfiles
```

In the normal flow with `hix.json`, `THixServer:New()` takes care of it.

---

## Common errors

| Symptom                            | Cause                                              | Fix                              |
|------------------------------------|----------------------------------------------------|----------------------------------|
| The log is empty                   | Level above the emitted messages                   | Lower `level` to `debug` or `info` |
| Appears in console but not in file | `paths.log` points to a directory without write permission | Create/allow the directory       |
| `access.log` is not written        | `access_log.enabled = false`                       | Set `enabled = true`             |
| Old logs are not deleted           | `max_files = 0`                                    | Define a limit (`max_files = 10`) |
| Missing `l()` in a .prg            | You forgot `#include "hix_logger.ch"`              | Add it in header                 |




