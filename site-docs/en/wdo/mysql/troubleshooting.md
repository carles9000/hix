# WDO MySQL - Troubleshooting

Diagnostic guide for the most frequent errors in the MySQL driver.

## Symptom → solution map

| Symptom | Go to |
|---------|-------|
| Error 10048 / `WSAEADDRINUSE` at startup | [§1](#1-error-10048-wsaeaddrinuse) |
| DLL not loading / "not found" in console | [§2](#2-dll-not-found) |
| `WDO_Get()` returns NIL under load | [§3](#3-wdoget-returns-nil-under-load) |
| "MySQL server has gone away" | [§4](#4-mysql-server-has-gone-away) |
| "Too many connections" in MySQL | [§5](#5-too-many-connections) |
| App hangs at startup with no messages | [§6](#6-app-hangs-at-startup) |
| WARN `RELEASE_RECLAIM` in the log | [§7](#7-warn-release_reclaim) |

---

## 1. Error 10048 WSAEADDRINUSE

```
Error WDO/500  Connection = (Failed connection)
Can't connect to MySQL server on 'localhost' (10048)
```

**Cause:** You are using `WDO_MySql():New()` inside an HTTP handler (or outside the pool). Each request opens a socket that stays in `TIME_WAIT` for ~60 s. After ~10,000 fast requests, Windows exhausts the ephemeral port range (49152–65535).

**Solution:** Always use `WDO_Get("mysql")` in handlers. Never use `New()` inside a controller.

!!! warning "New() in handlers - warning in the log"
    The driver detects this pattern and writes to the log:
    ```
    WARN  WDO_MySql:New called inside HTTP request handler.
          Use WDO_Get("mysql") + oConn:Close() instead.
    ```
    If you see this warning, locate the handler producing it and change it to use the pool.

---

## 2. DLL not found

```
==> Error: Cannot load MySQL DLL
```

**Possible causes:**

1. The DLL is not in any of the searched paths.
2. The `"dll"` field in `config.json` points to an incorrect path.
3. You are using `"driver": "mysql"` but only have `libmariadb64.dll` (or vice versa).

**Solutions:**

=== "Option A - next to the executable"
    Copy `libmysql64.dll` (or `libmariadb64.dll`) to the server directory (`hb_DirBase()`). The simplest option.

=== "Option B - environment variable"
    ```
    set WDO_LIB_MYSQL=C:\mysql\lib\libmysql64.dll
    ```

=== "Option C - dll field in config.json"
    ```json
    {
      "databases": {
        "mysql": {
          "driver": "mysql",
          "dll": "C:/mysql/lib/libmysql64.dll",
          ...
        }
      }
    }
    ```

To see which DLL the driver is using at runtime:

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "mysql" )
   IF oConn == NIL ; RETURN USendError( 503, "no pool" ) ; ENDIF
   USendJson( { "dll_path" => oConn:DllPath(), "dll_source" => oConn:DllSource() } )
   oConn:Close()
} )
```

---

## 3. WDO_Get returns NIL under load

```
WARN  WDO_Pool[MySQL] Acquire timeout after 5000ms
```

**Cause:** All pool slots are busy. Handlers are taking longer than expected and slots are not being released in time.

**Diagnostics:**

```harbour
// Add this endpoint to see live status
oSrv:AddRouteGet( "health.db", "/health/db", {||
   USendJson( WDO_PoolStats( "mysql" ) )
   // { "size" => 5, "busy" => 5, "free" => 0, "closed" => false }
} )
```

**Solutions (in order):**

1. **Increase `pool_size`** in `config.json` (start by doubling it).
2. **Verify that all handlers call `oConn:Close()`** — a single handler leaking a connection under load will fill the pool.
3. **Review query latency** — if slow queries are holding slots too long, optimise indexes or add more slots.
4. **Increase `timeout_ms`** if peaks are brief and the pool frees up quickly.

---

## 4. MySQL server has gone away

```
Error WDO/500  Connection = (Failed connection)
MySQL server has gone away
```

**Cause:** The pool's TCP connection was idle longer than MySQL's `wait_timeout` (default 8 hours, sometimes 30 minutes on shared hosting). MySQL closed the connection server-side, but the pool slot doesn't know.

**Solution:** Enable `"ping": true` in `config.json`. Before delivering each slot, the pool pings and reconnects if the socket is dead:

```json
{
  "databases": {
    "mysql": {
      "ping": true,
      ...
    }
  }
}
```

!!! info "Ping cost"
    The ping adds ~0.5 ms per `WDO_Get()`. In practice, irrelevant compared to the cost of any real query. Always recommended in production with a remote MySQL server.

If the problem persists, increase `wait_timeout` in MySQL (`my.cnf`):
```ini
[mysqld]
wait_timeout = 28800
interactive_timeout = 28800
```

---

## 5. Too many connections

```
Can't connect to MySQL server (1040): Too many connections
```

**Cause:** The number of active connections exceeds MySQL's `max_connections` (default 151).

**Diagnostics:**
```sql
SHOW STATUS LIKE 'Threads_connected';
SHOW VARIABLES LIKE 'max_connections';
```

**Solutions:**

1. **Reduce `pool_size`** in `config.json` — you should not have more WDO connections than MySQL can accept.
2. **Increase `max_connections`** in `my.cnf` (carefully: each connection consumes ~1 MB of RAM):
   ```ini
   [mysqld]
   max_connections = 300
   ```
3. **Check for duplicate pools** — if multiple app instances point to the same MySQL, the total connection count is the sum of all pools.

Golden rule: `MySQL.max_connections > HIX_workers ≥ WDO_pool_size + 20 (admin margin)`.

---

## 6. App hangs at startup

The app starts, there are no error messages, but it does not respond.

**Most frequent cause:** The DLL loads but `mysql_real_connect` keeps waiting — the host is not responding (firewall, MySQL stopped, incorrect hostname).

**Diagnostics:**

```bash
# Test connectivity directly
mysql -h 127.0.0.1 -u harbour -p employees
```

!!! warning "localhost vs 127.0.0.1 on Linux"
    On Linux, `mysql_real_connect("localhost")` uses the **Unix socket** (`/var/run/mysqld/mysqld.sock`) instead of TCP. If the socket doesn't exist, the connection hangs. WDO automatically remaps `"localhost"` to `"127.0.0.1"` to force TCP, but if you have problems on Linux verify that mysqld is listening on TCP (`bind-address = 0.0.0.0`).

**Other causes:**

- `lAbortOnFail = .T.` in `HIX_InitPoolsFromConfig` → the process waits for `Inkey(0)`. If you start as a service without a console, it hangs waiting for a key. Check the system log (`journalctl -u hix` on Linux).
- Very high network timeout — try reducing `timeout_ms` to 3000 to fail fast during diagnostics.

---

## 7. WARN RELEASE_RECLAIM

```
WARN  WDO_ReleaseAllThread: reclaiming 1 leaked connection(s) from thread 15432
```

**Cause:** A handler acquired a connection with `WDO_Get()` but did not call `oConn:Close()` before finishing. The HIX dispatcher detects the leak at the end of the request and releases the slot automatically.

**Severity:** Not a critical error — the slot is recovered. But the thread held the connection longer than necessary, which reduces pool availability under load.

**Solution:** Locate the handler that doesn't close the connection and add `oConn:Close()`, ideally in a `FINALLY` block:

```harbour
TRY
   // ... handler logic ...
FINALLY
   IF oConn != NIL ; oConn:Close() ; ENDIF
END
```

---

## Logger messages (quick reference)

| Message | Level | Meaning |
|---------|-------|---------|
| `WDO_LOG_POOL_INIT_FAIL` | WARN | A pool slot could not be opened at startup |
| `WDO_LOG_ACQUIRE_TIMEOUT` | WARN | `WDO_Get()` waited `timeout_ms` without getting a slot |
| `WDO_LOG_MYSQL_POOL_INIT_FAIL` | WARN | No pool slot opened; pool unavailable |
| `WDO_ERR_LIB_NOT_FOUND` | ERROR | The DLL does not exist at the searched path |
| `WDO_ERR_LIB_LOAD_FAIL` | ERROR | The DLL exists but `hb_LibLoad` could not load it |
| `WDO_WARN_NEW_IN_REQUEST` | WARN | `New()` called inside an HTTP request handler |
| `WDO_WARN_BERROR_NOT_FOUND` | WARN | The function in the `berror` field is not linked |
| `WDO_LOG_POOLS_INIT` | INFO | `N/M pools` initialised successfully |
| `WDO_LOG_POOLS_END` | INFO | Pools closed when the server shuts down |
