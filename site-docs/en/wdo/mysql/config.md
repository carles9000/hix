# WDO MySQL - Configuration

There are three ways to start the MySQL pool. The recommended one is the declarative approach from `config.json`.

## Method 1 - Declarative (recommended)

Add the `databases` section to `www/config.json`:

```json
{
  "databases": {
    "mysql": {
      "driver":     "mysql",
      "host":       "127.0.0.1",
      "user":       "harbour",
      "pwd":        "hb1234",
      "db":         "employees",
      "port":       3306,
      "pool_size":         5,
      "timeout_ms":        5000,
      "ping":              true,
      "read_timeout_s":    30,
      "connect_timeout_s": 10,
      "berror":            "WDO_DefaultErrorHandler"
    }
  }
}
```

In `app.prg` with **hixstyle** you need nothing else: `Start()` automatically calls `HIX_InitPoolsFromConfig()` and `HIX_EndPoolsFromConfig()`.

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

You can declare several databases under distinct keys:

```json
{
  "databases": {
    "mysql":     { "driver": "mysql",   "host": "127.0.0.1", ... },
    "analytics": { "driver": "mariadb", "host": "10.0.0.42", ... }
  }
}
```

In handlers: `WDO_Get("mysql")` and `WDO_Get("analytics")` coexist in the same process.

### Available fields

| Field | Default | Description |
|-------|---------|-------------|
| `driver` | _(required)_ | `"mysql"` or `"mariadb"` (case-insensitive) |
| `host` | `"localhost"` | Server IP or hostname |
| `user` | `""` | Authentication user |
| `pwd` | `""` | Password |
| `db` | `""` | Default database |
| `port` | `3306` | TCP port |
| `pool_size` | `5` | Number of connections at startup |
| `timeout_ms` | `5000` | Maximum wait time in `WDO_Get()` (0 = infinite) |
| `ping` | `true` | Ping before delivering each slot; reconnects if dead |
| `read_timeout_s` | `30` | MySQL socket read/write timeout in seconds (0 = no timeout). Bounds the `recv()` block when a dispatcher child thread exceeds `exec_timeout_ms`; without it the connection becomes zombie and the slot never returns to the pool |
| `connect_timeout_s` | `10` | Server connect-phase timeout in seconds (0 = no timeout). Prevents pool startup from hanging when the MySQL server is unresponsive |
| `debug` | `false` | If any pool has `"debug": true`, global `HIX_Dbg()` tracing is enabled: `dbg.log` captures pool Acquire/Release and every `HIX_Dbg()` call instrumented in controllers. `dbg.log` is wiped on startup. Development only — has I/O cost. |
| `berror` | - | Harbour function name to handle pool errors |
| `dll` | - | Explicit path to the DLL (overrides automatic resolution) |

!!! warning "Relationship with `exec_timeout_ms`"
    `read_timeout_s` must be **larger** than the slowest legitimate query and aligned with the dispatcher's `exec_timeout_ms` (in `hix.json`). If you raise `exec_timeout_ms`, raise `read_timeout_s` too: if a query runs longer than the socket read timeout MySQL will return an error before the query finishes.

!!! tip "Default berror"
    `"berror": "WDO_DefaultErrorHandler"` is already included in the lib: it logs the error with `le()` and returns 500 if there is an active request. Sufficient for most projects.

## Method 2 - Programmatic hash

```harbour
WDO_InitPoolMySqlEx( "mysql", { ;
   "host"       => hb_GetEnv( "DB_HOST" ), ;
   "user"       => hb_GetEnv( "DB_USER" ), ;
   "pwd"        => hb_GetEnv( "DB_PWD" ),  ;
   "db"         => "employees",            ;
   "pool_size"  => 10,                     ;
   "timeout_ms" => 5000,                   ;
   "ping"       => .T.,                    ;
   "berror"     => "WDO_DefaultErrorHandler" ;
} )
```

Useful when credentials are read from environment variables or secrets.

## Method 3 - Positional (legacy)

```harbour
WDO_InitPoolMySql( "localhost", "harbour", "hb1234", "employees", 3306, ;
                    5,     /* pool_size   */ ;
                    5000,  /* timeout_ms  */ ;
                    .T.,   /* ping        */ ;
                    {|oErr, oConn| WdoErrorHandler( oErr, oConn ) } )
```

Registers the pool under the fixed key `"MYSQL"`. Compatible with code prior to v2.3.01.

---

## DLLs - MySQL vs MariaDB driver

The driver needs the MySQL protocol client library:

| `"driver"` | Windows DLL | Linux SO |
|-----------|-------------|----------|
| `"mysql"` | `libmysql64.dll` | `libmysqlclient.so` |
| `"mariadb"` | `libmariadb64.dll` | `libmariadb.so` |

### DLL resolution precedence

The driver searches for the library in this order (highest priority first):

1. **`"dll"` field in `config.json`** - explicit absolute path per pool.
2. **Environment variable `WDO_LIB_MYSQL`** - absolute path to the file.
3. **Environment variable `WDO_PATH_MYSQL`** - directory; the driver appends the canonical name.
4. **Executable directory** (`hb_DirBase()`).
5. **System PATH** - canonical name without path.

### Diagnostics

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "mysql" )
   IF oConn == NIL ; RETURN USendError( 503, "pool unavailable" ) ; ENDIF
   USendJson( { ;
      "dll_source" => oConn:DllSource(), ;
      "dll_path"   => oConn:DllPath(),   ;
      "server"     => oConn:mysql_get_server_info() ;
   } )
   oConn:Close()
} )
```

`DllSource()` returns `"override"`, `"WDO_LIB_MYSQL"`, `"WDO_PATH_MYSQL"`, `"exedir"` or `"default"`.

### If the DLL is not found

The pool fails at startup and writes to the console:

```
==> Error: Cannot load MySQL DLL
```

With `HIX_InitPoolsFromConfig(.T.)` the server aborts. With `.F.` it continues, but `WDO_Get("mysql")` will return NIL and handlers will respond with 503.

---

## Custom error handler

If you need custom logic (Slack alerts, metrics, etc.), define a public function:

```harbour
FUNCTION WdoErrorHandler( oErr, oConn )

   HB_SYMBOL_UNUSED( oConn )

   le( "[WDO] " + oErr:description + " @ " + oErr:operation )

   IF HIX_GetRequest() != NIL
      USendError( 500, "DB error: " + oErr:description )
   ENDIF

RETURN NIL
```

And reference it in the JSON:

```json
"berror": "WdoErrorHandler"
```
