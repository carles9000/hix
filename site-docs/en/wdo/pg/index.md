# WDO PostgreSQL — Concept and Pool

The `WDO_PG` driver wraps the official PostgreSQL client library (`libpq`) via `hb_DynCall`. On top of it, `WDO_Pool` implements the thread-safe connection pool used by HTTP handlers.

## The problem the pool solves

Imagine 100 concurrent requests, each opening and closing its own PostgreSQL connection:

```
Request 1  →  New() → TCP connect + auth (~1.2 ms) → Query → End() → socket in TIME_WAIT
Request 2  →  New() → TCP connect + auth (~1.2 ms) → Query → End() → socket in TIME_WAIT
...×100
```

After a few thousand quick requests on Windows, the system runs out of ephemeral ports and error **10048** (`WSAEADDRINUSE`) appears. A second bench run without a pool collapses with exactly this error.

With a pool, sockets are opened **once** at startup and reused indefinitely:

```
Startup:  WDO_Init → opens 5 TCP connections (once, amortised cost)

Request 1  →  WDO_Get("PG") → slot #1 borrowed (~0.005 ms) → Query → Close() → slot #1 returned
Request 2  →  WDO_Get("PG") → slot #2 borrowed (~0.005 ms) → Query → Close() → slot #2 returned
...×100  →  rotate across 5 slots, no open/close of sockets
```

## Performance comparison

| Pattern | Cost per request | Scales under load |
|---------|-----------------|-------------------|
| `WDO_PG():New()` per request | ~1.2 ms (90% is setup) | Collapses with 10048 |
| `WDO_Get("PG")` / `Close()` (pool) | ~0.06 ms (84% is the query) | Stable indefinitely |

**The pool is ~20× faster** in overhead, and the only approach that scales in production.

## How the pool works

### At app startup

`WDO_InitPoolPg` (or the declarative startup from `config.json`) creates `N` instances of `WDO_PG`, connects them, and stores them in the pool's internal array marked as free.

### Per request

1. `WDO_Get("PG")` — acquires the pool mutex, finds the first free slot, marks it as busy and hands it to the thread. If all slots are busy, it blocks until one is released (or `timeout_ms` expires).
2. The handler uses the connection (Query, Prepare, Exec…).
3. `oConn:Close()` — returns the slot to the pool (without closing the TCP socket). If the connection had an open transaction, it performs an automatic Rollback.

### Safety net

If a handler has a bug and forgets to call `Close()`, the HIX dispatcher calls `WDO_ReleaseAllThread()` at the end of the request. This returns any slot the thread has borrowed. **No leaks are possible**, even if the code is careless.

### TCP preflight probe

Before calling `libpq`, the driver performs a low-level TCP probe to verify the server responds. This prevents `PQconnectdb` from hanging up to 2 minutes if the host is down or the firewall doesn't return RST. If the probe fails, the pool startup fails in milliseconds with a clear log message.

## Default pool key

!!! info "Default key: «PG» in uppercase"
    `WDO_InitPoolPg` (positional) registers the pool under the fixed key `"PG"` (uppercase). If you use `WDO_InitPoolPgEx` you can choose another key, but `"PG"` is the framework convention.

    In handlers always use `WDO_Get("PG")`, not `WDO_Get("pg")` (the key is case-sensitive).

## Basic rule

!!! warning "Inside an HTTP handler"
    Always use `WDO_Get("PG")` + `oConn:Close()`. **Never** `WDO_PG():New()` inside a controller.

`WDO_PG():New()` is only valid in CLI scripts, unit tests, or a startup sanity-ping. The driver itself warns in the log if it detects a `New()` inside an HTTP request.

## When to use `New()` directly

- Command-line scripts (migrations, backups, reports).
- Driver unit tests.
- Connections with credentials different from the pool (another DB, another server).

## Full lifecycle

```
Startup
  └─ HIX_InitPoolsFromConfig()  (or WDO_InitPoolPg)
       └─ opens N TCP connections + PostgreSQL auth

  Per request:
  └─ WDO_Get("PG")    →  slot borrowed
       └─ Query / Prepare / Exec / ...
  └─ oConn:Close()    →  slot returned to pool

Shutdown
  └─ HIX_EndPoolsFromConfig()  (or WDO_EndPoolPg)
       └─ closes N sockets (once)
```

!!! info "Next step"
    Now that you understand the model, [configure the pool in `config.json`](config.md).
