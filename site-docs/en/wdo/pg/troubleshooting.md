# WDO PostgreSQL — Troubleshooting

Diagnostic guide for the most common errors of the PostgreSQL driver.

## Symptom → solution map

| Symptom | Go to |
|---------|-------|
| App hangs at startup with no messages (TCP probe) | [§1](#1-app-hangs-at-startup) |
| DLL not found / "Cannot load PostgreSQL DLL" | [§2](#2-dll-not-found) |
| `WDO_Get()` returns NIL under load | [§3](#3-wdoget-returns-nil-under-load) |
| "FATAL: password authentication failed" | [§4](#4-authentication-error) |
| "SSL connection required" / SSL error | [§5](#5-ssl-error) |
| NOTICE spam on console ("table does not exist, skipping") | [§6](#6-ddl-notice-spam) |
| WARN `RELEASE_RECLAIM` in log | [§7](#7-warn-release_reclaim) |
| `psql` connects but the app does not | [§8](#8-psql-connects-but-app-does-not) |

---

## 1. App hangs at startup

The app starts, no error messages, but it does not respond. The process stays consuming minimal CPU for minutes.

**Most common cause:** `PQconnectdb` from libpq waits for the TCP response from the server. Without a network timeout, it can block up to 2 minutes if the host does not respond (firewall dropping packets without RST, wrong host, PostgreSQL down).

**Protection mechanism — TCP preflight probe:**

WDO_PG does a low-level TCP probe before calling `PQconnectdb`. If the host does not respond to the probe within `connect_timeout_s` seconds, the pool fails in milliseconds:

```
==> Error: WDO_PG TCP probe failed — host=10.0.0.42 port=5432
```

If you see this message, the problem is network or wrong host/port.

**Diagnosis:**

=== "Windows"
    ```cmd
    :: Test TCP connectivity directly
    Test-NetConnection -ComputerName 127.0.0.1 -Port 5432

    :: Or with psql
    psql -h 127.0.0.1 -U postgres -d myapp
    ```

=== "Linux / WSL"
    ```bash
    nc -zv 127.0.0.1 5432
    psql -h 127.0.0.1 -U postgres -d myapp
    ```

**Solutions in order:**

1. Verify PostgreSQL is running: `pg_ctl status` or `systemctl status postgresql`.
2. Check that `postgresql.conf` has `listen_addresses = '*'` or at least `'127.0.0.1'`.
3. Verify the port: default 5432, but custom installs may use a different one.
4. Check the firewall: PostgreSQL must accept TCP connections on the configured port.
5. Reduce `connect_timeout_s` to 3 during diagnosis to fail fast.

!!! info "TCP probe cost"
    The probe adds ~1–2 ms per pool startup. Negligible and compensates by eliminating 2-minute hangs.

---

## 2. DLL not found

```
==> Error: Cannot load PostgreSQL DLL (libpq.dll)
```

**Possible causes:**

1. `libpq.dll` is not in any of the searched paths.
2. The `"dll"` field in `config.json` points to an incorrect path.
3. `libpq.dll` exists but its dependencies are missing (`libcrypto-4-x64.dll`, `libssl-4-x64.dll`, `libcurl-x64.dll`) — Windows fails to load the DLL without a clear message.

**Solutions:**

=== "Option A — alongside the executable"
    Copy the four DLLs from `resources/wdo/pg/dll/` to the server directory (`hb_DirBase()`). The simplest option.

    ```
    resources/wdo/pg/dll/
      libpq.dll
      libcrypto-4-x64.dll
      libssl-4-x64.dll
      libcurl-x64.dll
    ```

=== "Option B — environment variable"
    ```cmd
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

To see which DLL the driver is using at runtime:

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "PG" )
   IF oConn == NIL ; RETURN USendError( 503, "no pool" ) ; ENDIF
   USendJson( { ;
      "dll_path"   => oConn:DllPath(),   ;
      "dll_source" => oConn:DllSource()  ;
   } )
   oConn:Close()
} )
```

!!! warning "libpq dependencies"
    `libpq.dll` dynamically loads its dependencies. If `libcrypto-4-x64.dll` is not alongside the executable or in `PATH`, you will get a cryptic Windows error ("procedure entry point not found"). Always copy the four DLLs together.

---

## 3. WDO_Get returns NIL under load

```
WARN  WDO_Pool[PG] Acquire timeout after 5000ms
```

**Cause:** All pool slots are busy. Handlers take longer than expected and slots are not released in time.

**Diagnosis:**

```harbour
// Add this endpoint to see the live state
oSrv:AddRouteGet( "health.db", "/health/db", {||
   USendJson( WDO_PoolStats( "PG" ) )
   // { "size" => 5, "busy" => 5, "free" => 0, "closed" => false }
} )
```

You can also query active connections from PostgreSQL:

```sql
SELECT pid, application_name, state, query_start, query
FROM   pg_stat_activity
WHERE  application_name = 'hix-worker'
ORDER  BY query_start;
```

**Solutions (in order):**

1. **Increase `pool_size`** in `config.json` (start by doubling).
2. **Verify all handlers call `oConn:Close()`** — a single handler leaking a connection under load fills the pool.
3. **Review query latency** — slow queries (no index, full scan) occupy slots longer than necessary. Use `EXPLAIN ANALYZE`.
4. **Increase `timeout_ms`** if peaks are brief and the pool frees up soon.

---

## 4. Authentication error

```
FATAL:  password authentication failed for user "postgres"
```

or

```
FATAL:  no pg_hba.conf entry for host "127.0.0.1", user "postgres", database "myapp"
```

**Causes:**

- Incorrect password in `config.json`.
- The authentication method in `pg_hba.conf` does not allow the connection from the HIX server's IP.
- The user does not exist or does not have permissions on the database.

**Diagnosis:**

```bash
# Verify the user exists and the password is correct
psql -h 127.0.0.1 -U postgres -d myapp -c "SELECT 1"

# Review pg_hba.conf
psql -U postgres -c "SHOW hba_file"
```

**Minimum `pg_hba.conf` configuration** for local connections with password:

```
# TYPE  DATABASE  USER      ADDRESS         METHOD
host    all       all       127.0.0.1/32    scram-sha-256
host    all       all       ::1/128         scram-sha-256
```

After modifying `pg_hba.conf`:

```bash
pg_ctl reload   # or: SELECT pg_reload_conf();
```

---

## 5. SSL error

**Symptom A — sslmode require but server has no SSL:**

```
FATAL:  SSL connection required but not supported by server
```

**Solution:** Change `sslmode` to `"disable"` in `config.json` if PostgreSQL is not configured with SSL, or configure SSL on the server.

**Symptom B — certificate verification failed:**

```
FATAL:  certificate verify failed
```

**Solution:** Use `sslmode: "require"` (verifies encryption but not the certificate) instead of `"verify-ca"` or `"verify-full"` if you do not have the server certificates installed.

**SSL modes table:**

| `sslmode` | Encryption | Verifies CA cert | Verifies hostname | Recommended use |
|-----------|------------|------------------|-------------------|-----------------|
| `disable` | No | No | No | Local development |
| `allow` | If server offers it | No | No | — |
| `prefer` | Preferred but not forced | No | No | — |
| `require` | Always | No | No | Production without own PKI |
| `verify-ca` | Always | Yes | No | Production with own CA |
| `verify-full` | Always | Yes | Yes | Maximum security |

!!! tip "Always start with disable"
    During initial diagnosis, set `sslmode: "disable"` to eliminate SSL as a variable. Once the connection works, enable the required SSL level.

---

## 6. DDL NOTICE spam

**Symptom:**

```
NOTICE:  table "temp_work" does not exist, skipping
```

These messages appear in the HIX server console when you run `DROP TABLE IF EXISTS` on non-existent tables. They are not errors but clutter the log.

**Cause:** PostgreSQL emits NOTICE by default for DDL operations that "do nothing" (IF EXISTS on absent objects).

**Solution — `SET client_min_messages` per session:**

```harbour
// Silence NOTICEs only in the current session (does not affect the server)
oConn:Exec( "SET client_min_messages TO WARNING" )
oConn:Exec( "DROP TABLE IF EXISTS temp_work" )
oConn:Exec( "CREATE TABLE temp_work (id SERIAL PRIMARY KEY, ...)" )
// Restore if you want to see NOTICEs again in this session
oConn:Exec( "SET client_min_messages TO NOTICE" )
```

!!! warning "Scope: current session only"
    `SET client_min_messages` affects only the connection where it is executed. Other pool connections are not affected. It is not necessary or recommended to change it at the server level (`postgresql.conf`) just to silence DDL NOTICEs.

---

## 7. WARN RELEASE_RECLAIM

```
WARN  WDO_ReleaseAllThread: reclaiming 1 leaked connection(s) from thread 15432
```

**Cause:** A handler acquired a connection with `WDO_Get()` but did not call `oConn:Close()` before finishing. The HIX dispatcher detects the leak at the end of the request and releases the slot automatically.

**Severity:** Not a critical error — the slot is recovered. But the thread held the connection longer than necessary, reducing pool availability under load. If the handler had an open transaction, the pool performs an automatic Rollback before releasing.

**Solution:** Locate the handler that does not close the connection and add `oConn:Close()`, ideally in a `FINALLY` block:

```harbour
TRY
   // ... handler logic ...
FINALLY
   IF oConn != NIL ; oConn:Close() ; ENDIF
END
```

---

## 8. psql connects but app does not

The HIX application cannot connect even though `psql` with the same parameters works perfectly.

**Common causes and checks:**

**A) Incorrect `sslmode`:**

`psql` defaults to `sslmode=prefer` (tries SSL, accepts without SSL). If in `config.json` you have `sslmode: "require"` and PostgreSQL server has no SSL, the app fails but `psql` without parameters works.

```bash
# Test with the same sslmode the app uses
psql "host=127.0.0.1 dbname=myapp user=postgres sslmode=disable"
```

**B) `pg_hba.conf` distinguishes between users:**

`psql` can connect as `postgres` (superuser) even if the app user has no access.

```bash
# Test with exactly the user configured in config.json
psql -h 127.0.0.1 -U hix_user -d myapp
```

**C) Environment variables that `psql` inherits but the app does not:**

`psql` uses `PGPASSWORD`, `PGHOST`, `PGPORT` from the environment. The HIX app reads only fields from `config.json`.

```bash
# Verify without environment variables
env -i psql "host=127.0.0.1 port=5432 dbname=myapp user=hix_user password=secret"
```

**D) Different libpq DLL from `psql`:**

If the `psql` in PATH uses libpq from a different installation to the DLL HIX uses, there may be protocol or authentication support differences.

```bash
# See what libpq psql uses
psql --version
# See what DLL HIX uses
curl http://localhost:8080/dbinfo
```

---

## Logger messages (quick reference)

| Message | Level | Meaning |
|---------|-------|---------|
| `WDO_LOG_POOL_INIT_FAIL` | WARN | A pool slot could not be opened at startup |
| `WDO_LOG_ACQUIRE_TIMEOUT` | WARN | `WDO_Get()` waited `timeout_ms` without getting a slot |
| `WDO_LOG_PG_POOL_INIT_FAIL` | WARN | No pool slot opened; pool unavailable |
| `WDO_ERR_LIB_NOT_FOUND` | ERROR | `libpq.dll` does not exist at the searched path |
| `WDO_ERR_LIB_LOAD_FAIL` | ERROR | `libpq.dll` exists but `hb_LibLoad` could not load it (missing dependencies) |
| `WDO_WARN_NEW_IN_REQUEST` | WARN | `New()` called inside an HTTP handler |
| `WDO_WARN_BERROR_NOT_FOUND` | WARN | The function in the `berror` field is not linked |
| `WDO_LOG_POOLS_INIT` | INFO | `N/M pools` initialised successfully |
| `WDO_LOG_POOLS_END` | INFO | Pools closed on server shutdown |
| `WDO_PG TCP probe failed` | ERROR | Host does not respond to TCP probe before `PQconnectdb` |
| `WDO_ReleaseAllThread: reclaiming` | WARN | Slot not returned by handler; reclaimed by dispatcher |
