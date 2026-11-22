# WDO SQLite3 — Concept and Singleton

The `WDO_Sqlite3` driver wraps `sqlcipher.dll` via `hb_DynCall`. Unlike the MySQL or PostgreSQL drivers, **there is no pool** — the driver manages a single shared connection among all HIX server workers.

## Why singleton and not pool

SQLite is a library embedded in the process, not an external TCP server. There is no network handshake, no ephemeral sockets that can be exhausted. The `.db` file lives on disk and the driver opens it **once** at startup.

Multiple simultaneous connections to the same SQLite file are possible in WAL mode, but WDO uses a shared connection with an internal mutex to serialise operations. This eliminates pool complexity and makes behaviour predictable:

```
Startup:
  └─ HIX_InitPoolsFromConfig()
       └─ WDO_InitSqlite3Ex("APP", hParams)
            └─ sqlite3_open() — once only

Per request:
  └─ WDO_Get("APP")   →  same instance every time (no slot checkout)
       └─ Query / Prepare / Exec / ...
  └─ oConn:Close()    →  no-op as singleton (returns to Harbour stack)

Shutdown:
  └─ HIX_EndPoolsFromConfig()
       └─ WDO_EndSqlite3("APP")
            └─ sqlite3_close() — once only
```

!!! info "oConn:Close() is good practice even if it does nothing"
    Calling `Close()` keeps code portable across drivers. If you migrate to MySQL or PG in the future, the same `Get/Close` pattern works without changes. The HIX dispatcher also calls `WDO_ReleaseAllThread()` at the end of each request; in SQLite3 this has no harmful effect.

## WAL mode — the default

The driver activates `PRAGMA journal_mode=WAL` at startup (configurable). In WAL mode:

- Multiple readers can read simultaneously while a writer is writing.
- Uncommitted changes accumulate in the `-wal` sidecar and are merged into the `.db` at checkpoint.
- Write performance is notably better than DELETE mode (SQLite's historical default).

!!! warning "Sidecars on disk"
    WAL creates two additional files alongside the `.db`: `-wal` and `-shm`. When making a backup, copy all three. When deleting in tests, also delete the sidecars with `FErase(cDb + "-wal")` and `FErase(cDb + "-shm")`.

## Performance comparison

| Pattern | Cost per request | Scales under load |
|---------|-----------------|-------------------|
| `WDO_MySql():New()` per request | ~0.77 ms (87% TCP setup) | Collapses with error 10048 |
| `WDO_Get("mysql")` (pool 5 slots) | ~0.06 ms | Stable indefinitely |
| `WDO_Get("APP")` (SQLite3 singleton) | < 0.01 ms (no TCP) | Serialises with mutex; writers queued |

The SQLite3 singleton is extremely fast for concurrent reads. The bottleneck is write serialisation: only one writer can execute at a time.

## When to use SQLite3

- **Small to medium apps** with moderate traffic (< 50 req/s with frequent writes).
- **Local development** without an external database server.
- **Embedded data** — configuration, sessions, local cache, internal queues.
- **Portable apps** — a single `.db` file contains everything, even encrypted with SQLCipher.
- **Integration tests** — in-memory database with `"file": ":memory:"`.

## When to use PostgreSQL or MySQL instead

- **High write concurrency** — more than 100 requests per second with simultaneous writes.
- **Shared data** among multiple server instances (SQLite3 is not a network server).
- **Replication or sharding** — SQLite has no such concepts.
- **Advanced features** — JSONB with GIN indexes (PG), complex stored procedures, GIS, etc.
- **Data size > 1 GB** with frequent writes — the write mutex becomes a bottleneck.

## Full lifecycle

```
Startup
  └─ HIX_InitPoolsFromConfig()
       └─ sqlite3_open() + configuration PRAGMAs

  Per request:
  └─ WDO_Get("APP")   →  same instance (internal mutex manages concurrency)
       └─ Query / Prepare / Exec / ...
  └─ oConn:Close()    →  no-op in singleton; mutex already released in Free()/Execute()

Shutdown
  └─ HIX_EndPoolsFromConfig()
       └─ WDO_EndSqlite3("APP")  →  sqlite3_close() + HB_LibFree()
```

!!! info "Next step"
    Now that you understand the model, [configure the singleton in `config.json`](config.md).
