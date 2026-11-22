# WDO PostgreSQL — Configuration

There are three ways to start the PostgreSQL pool. The recommended one is the declarative method via `config.json`.

## Method 1 — Declarative (recommended)

Add the `databases` section to `www/config.json`:

```json
{
  "databases": {
    "PG": {
      "driver":             "pg",
      "host":               "127.0.0.1",
      "port":               5432,
      "user":               "postgres",
      "pwd":                "secret",
      "db":                 "myapp",
      "pool_size":          5,
      "timeout_ms":         5000,
      "ping":               true,
      "read_timeout_s":     30,
      "connect_timeout_s":  10,
      "sslmode":            "disable",
      "application_name":   "hix-worker",
      "client_encoding":    "UTF8",
      "berror":             "WDO_DefaultErrorHandler"
    }
  }
}
```

In `app.prg` with **hixstyle** nothing more is needed: `Start()` automatically calls `HIX_InitPoolsFromConfig(.T.)` and `HIX_EndPoolsFromConfig()`.

In apps without hixstyle:

```harbour
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()
   HIX_ConfigAppLoad( "www/config.json" )
   HIX_InitPoolsFromConfig()   // aborts if any pool fails (default)
   oSrv:Start()
   IF oSrv:hThread != NIL
      hb_threadJoin( oSrv:hThread )
   ENDIF
   HIX_EndPoolsFromConfig()
RETURN
```

### Multiple pools

You can declare several databases with different keys:

```json
{
  "databases": {
    "PG":        { "driver": "pg", "host": "127.0.0.1", "db": "myapp", ... },
    "PG_REPORT": { "driver": "pg", "host": "10.0.0.42", "db": "reports", ... }
  }
}
```

In handlers: `WDO_Get("PG")` and `WDO_Get("PG_REPORT")` coexist in the same process.

### Available fields

| Field | Default | Description |
|-------|---------|-------------|
| `driver` | _(required)_ | `"pg"` (case-insensitive) |
| `host` | `"localhost"` | IP or hostname of the PostgreSQL server |
| `user` | `""` | Authentication user |
| `pwd` | `""` | Password |
| `db` | `""` | Default database |
| `port` | `5432` | TCP port |
| `pool_size` | `5` | Number of connections opened at startup |
| `timeout_ms` | `5000` | Maximum wait time in `WDO_Get()` (0 = infinite) |
| `ping` | `true` | Ping before delivering each slot; reconnects if dead |
| `read_timeout_s` | `30` | `statement_timeout` in seconds applied per session (0 = no timeout). Caps runaway queries; without this a slot can be held indefinitely |
| `connect_timeout_s` | `10` | Timeout for the TCP + auth connection phase in seconds (0 = no timeout). Prevents the pool startup from hanging if the server is unresponsive |
| `sslmode` | `"disable"` | `disable` / `allow` / `prefer` / `require` / `verify-ca` / `verify-full` |
| `application_name` | `"hix-worker"` | Visible in `pg_stat_activity` to identify pool connections |
| `client_encoding` | `"UTF8"` | Session encoding; must match or be compatible with the DB |
| `debug` | `false` | If any pool has `"debug": true`, enables `HIX_Dbg()` globally: `dbg.log` captures Acquire/Release traces and all `HIX_Dbg()` calls in controllers. Development only |
| `berror` | — | Harbour function name to handle pool errors |
| `dll` | — | Explicit path to `libpq.dll` (overrides automatic resolution) |

!!! warning "Relationship with `exec_timeout_ms`"
    `read_timeout_s` must be **greater** than the slowest legitimate query and consistent with the dispatcher's `exec_timeout_ms` (in `hix.json`). `read_timeout_s` is implemented as `SET statement_timeout = N * 1000` per session, so it affects all queries on that connection.

!!! tip "Default berror"
    `"berror": "WDO_DefaultErrorHandler"` is already included in the lib: it logs the error with `le()` and returns 500 if there is an active request. Sufficient for most projects.

---

## Method 2 — Programmatic hash

```harbour
WDO_InitPoolPgEx( "PG", { ;
   "host"             => hb_GetEnv( "DB_HOST" ),     ;
   "user"             => hb_GetEnv( "DB_USER" ),     ;
   "pwd"              => hb_GetEnv( "DB_PWD"  ),     ;
   "db"               => "myapp",                    ;
   "pool_size"        => 10,                         ;
   "timeout_ms"       => 5000,                       ;
   "ping"             => .T.,                        ;
   "sslmode"          => "require",                  ;
   "application_name" => "hix-worker",               ;
   "client_encoding"  => "UTF8",                     ;
   "berror"           => "WDO_DefaultErrorHandler"   ;
} )
```

Useful when credentials are read from environment variables or secrets.

## Method 3 — Positional (legacy)

```harbour
WDO_InitPoolPg( "127.0.0.1", "postgres", "secret", "myapp", 5432, ;
                 5,     /* pool_size   */ ;
                 5000,  /* timeout_ms  */ ;
                 .T.    /* ping        */ )
```

Registers the pool under the fixed key `"PG"`. Compatible with code prior to v2.4.4.

To shut down:

```harbour
WDO_EndPoolPg()
```

---

## DLLs — libpq and dependencies

The driver needs four DLLs from the PostgreSQL Windows distribution:

| DLL | Function |
|-----|----------|
| `libpq.dll` | PostgreSQL client library (wire protocol) |
| `libcrypto-4-x64.dll` | Cryptographic primitives (SSL, SCRAM-SHA-256) |
| `libssl-4-x64.dll` | TLS for connections with `sslmode != disable` |
| `libcurl-x64.dll` | Used by libpq for HTTP proxy connections |

All four DLLs ready to copy are in `resources/wdo/pg/dll/` of the HIX project.

### libpq.dll resolution precedence

The driver searches for the library in this order (highest priority first):

1. **`"dll"` field in `config.json`** — explicit absolute path per pool.
2. **Environment variable `HIX_PG_DLL`** — absolute path to the file.
3. **Environment variable `WDO_PG_DLL`** — absolute path to the file.
4. **Executable directory** (`hb_DirBase() + "dll\libpq.dll"`).
5. **System PATH** — canonical name `libpq.dll` without path.

The tag is stored in `oConn:DllSource()` for diagnostics.

### Diagnostics

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "PG" )
   IF oConn == NIL ; RETURN USendError( 503, "pool unavailable" ) ; ENDIF
   USendJson( { ;
      "dll_source" => oConn:DllSource(), ;
      "dll_path"   => oConn:DllPath(),   ;
      "server"     => oConn:ServerInfo() ;
   } )
   oConn:Close()
} )
```

`DllSource()` returns `"override"`, `"env"`, `"exedir"` or `"default"`.

### If the DLL is not found

The pool fails at startup and writes to the console:

```
==> Error: Cannot load PostgreSQL DLL (libpq.dll)
```

With `HIX_InitPoolsFromConfig(.T.)` the server aborts. With `.F.` it continues, but `WDO_Get("PG")` will return NIL and handlers will respond with 503.

=== "Option A — alongside the executable"
    Copy the four DLLs from `resources/wdo/pg/dll/` to the server directory (`hb_DirBase()`). The simplest option, using `cDllSource = "exedir"`.

=== "Option B — environment variable"
    ```bash
    set HIX_PG_DLL=C:\postgresql\bin\libpq.dll
    ```

=== "Option C — dll field in config.json"
    ```json
    {
      "databases": {
        "PG": {
          "driver": "pg",
          "dll": "C:/postgresql/bin/libpq.dll",
          "..."
        }
      }
    }
    ```

!!! warning "libpq dependencies must be accessible"
    `libpq.dll` dynamically loads `libcrypto-4-x64.dll`, `libssl-4-x64.dll` and `libcurl-x64.dll`. If these DLLs are not alongside the executable or in `PATH`, you will get a Windows error when calling `hb_LibLoad("libpq.dll")` even if the file exists. Copy all four DLLs together.

---

## Custom error handler

If you need custom logic (Slack alerts, metrics, etc.), define a public function:

```harbour
FUNCTION WdoPgErrorHandler( oErr, oConn )

   HB_SYMBOL_UNUSED( oConn )

   le( "[WDO_PG] " + oErr:description + " @ " + oErr:operation )

   IF HIX_GetRequest() != NIL
      USendError( 500, "DB error: " + oErr:description )
   ENDIF

RETURN NIL
```

And reference it in the JSON:

```json
"berror": "WdoPgErrorHandler"
```

!!! warning "Function requirements"
    Must be a public `FUNCTION` (not `STATIC`, not `PROCEDURE`) and **statically linked** to the executable. If it lives in a dynamic `.hrb`, `hb_isFunction` will not find it at startup.
