# WDO MySQL — Concept and Pool

The `WDO_MySql` driver wraps the MySQL/MariaDB client library (`libmysqlclient` / `libmariadb`) via `hb_DynCall`. On top of it, `WDO_Pool` implements the thread-safe connection pool used by HTTP handlers.

## The problem the pool solves

Imagine 100 concurrent requests, each opening and closing its own MySQL connection:

```
Request 1  →  New() → TCP connect + auth (~0.7 ms) → Query → End() → socket in TIME_WAIT
Request 2  →  New() → TCP connect + auth (~0.7 ms) → Query → End() → socket in TIME_WAIT
...×100
```

After a few thousand fast requests on Windows, the system runs out of ephemeral ports and error **10048** (`WSAEADDRINUSE`) appears. The second bench run without a pool collapses with exactly this error.

With a pool, sockets are opened **only once** at startup and reused indefinitely:

```
Startup:   WDO_Init → opens 5 TCP connections (once, amortised cost)

Request 1  →  WDO_Get() → slot #1 borrowed (~0.005 ms) → Query → Close() → slot #1 returned
Request 2  →  WDO_Get() → slot #2 borrowed (~0.005 ms) → Query → Close() → slot #2 returned
...×100  →  rotating over 5 slots, no sockets opened/closed
```

## Performance comparison

| Pattern | Cost per request | Scales under load |
|---------|-----------------|-------------------|
| `WDO_MySql():New()` per request | ~0.77 ms (87% is setup) | Collapses with 10048 |
| `WDO_Get()` / `Close()` (pool) | ~0.06 ms (83% is the query) | Stable indefinitely |

**The pool is ~13× faster** in overhead, and the only one that scales in production.

## How the pool works

### At app startup

`WDO_InitPoolMySql` (or the declarative startup from `config.json`) creates `N` instances of `WDO_MySql`, connects them and stores them in the pool's internal array marked as free.

### For each request

1. `WDO_Get("mysql")` — acquires the pool mutex, finds the first free slot, marks it as busy and delivers it to the thread. If all slots are busy, it blocks until one is released (or `timeout_ms` expires).
2. The handler uses the connection (Query, Prepare, Exec…).
3. `oConn:Close()` — returns the slot to the pool (without closing the TCP socket). If the connection had an open transaction, it performs an automatic Rollback.

### Safety net

If a handler has a bug and forgets to call `Close()`, the HIX dispatcher calls `WDO_ReleaseAllThread()` at the end of the request. This returns any slot the thread has borrowed. **No leaks are possible**, even when code is careless.

## Basic rule

!!! warning "Inside an HTTP handler"
    Always use `WDO_Get("mysql")` + `oConn:Close()`. **Never** `WDO_MySql():New()` inside a controller.

`WDO_MySql():New()` is only legitimate in CLI scripts, unit tests or a startup sanity-ping. The driver itself logs a warning if it detects a `New()` inside an HTTP request handler.

## When to use `New()` directly

- Command-line scripts (migrations, backups, reports).
- Driver unit tests.
- Connections with different credentials from the pool (another database, another server).

## Full lifecycle

```
Startup
  └─ HIX_InitPoolsFromConfig()  (or WDO_InitPoolMySql)
       └─ opens N TCP connections

  For each request:
  └─ WDO_Get("mysql")   →  slot borrowed
       └─ Query / Prepare / Exec / ...
  └─ oConn:Close()      →  slot returned to pool

Shutdown
  └─ HIX_EndPoolsFromConfig()  (or WDO_EndPoolMySql)
       └─ closes the N sockets (once)
```

!!! info "Next step"
    Now that you understand the model, [configure the pool in `config.json`](config.md).
