# WDO SQLite3 — Transactions

WDO supports explicit transactions with `BeginTrans / Commit / Rollback` and a convenience method `Transaction(bCode)` that manages commit/rollback automatically.

## Concurrency in SQLite3 — a key difference

!!! warning "SQLite serialises writes"
    Unlike MySQL or PostgreSQL, SQLite allows **only one writer** at a time. In WAL mode, multiple readers can coexist with that writer, but if two threads try to start a write transaction simultaneously, the second waits until the first releases the lock.

    If the wait exceeds `busy_timeout_ms`, SQLite returns `SQLITE_BUSY`. Configure `busy_timeout_ms >= 5000` in production to absorb peaks of concurrent writes.

## Transaction isolation

The driver operates in two modes according to `pool_size` ([config](config.md#pool_size)). Each mode gives different isolation guarantees:

### Singleton (`pool_size: 1`, default)

A single connection shared among all threads. The internal mutex protects **individual operations** but **does not hold the lock between `BeginTrans()` and `Commit()`** — between these two calls other threads can interleave `Exec` / `Query` on the same connection. SQLite documents that *a single connection does not isolate its own operations* ([sqlite.org/isolation](https://www.sqlite.org/isolation.html)).

Practical consequence: if two concurrent handlers run `Transaction()` at the same time, the second handler's `BEGIN` collides with `::lInTrans = .T.` from the first and returns `.F.` silently, or worse — a `SELECT` from thread B can read uncommitted intermediate state from thread A.

This mode is valid for apps with one worker, CLI scripts, or loads where DB concurrency is null.

### Pool (`pool_size: N > 1`, recommended for HIX multi-worker)

Each thread reserves its own connection when entering the handler. `BEGIN/COMMIT` operate on independent handles; SQLite coordinates writes at the file level via `busy_timeout_ms`.

- **Real isolation:** transactions from different threads never interleave.
- **`SQLITE_BUSY` possible:** two concurrent write `Transaction()` calls on the same file compete for the lock at the SQLite level. With `busy_timeout_ms: 5000`, SQLite retries for 5 seconds before giving up.
- **Parallel reads:** WAL mode allows multiple simultaneous readers.
- **Encryption compatible:** SQLCipher applies the same `PRAGMA key` to each pool connection; the DLL is loaded only once, shared via refcount.

Recommended configuration for multi-worker production:

```json
"databases": {
   "APP": {
      "driver":          "sqlite3",
      "file":            "www/data/app.db",
      "journal_mode":    "WAL",
      "busy_timeout_ms": 5000,
      "pool_size":       4
   }
}
```

!!! tip "Choose `pool_size` based on HTTP workers"
    As a practical rule, `pool_size` ≈ number of HTTP workers that can touch the DB simultaneously. 4–8 is sufficient for most apps; raising it higher rarely helps because SQLite still serialises writes at the file level.

Added in v2.5.3 (Claim 2 — transactional isolation).

## BeginTrans / Commit

The basic pattern for a flow that always succeeds:

```harbour
LOCAL oConn := WDO_Get( "APP" )

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

oConn:BeginTrans()

oConn:Exec( "UPDATE accounts SET balance = balance - 200 WHERE owner = 'alice'" )
oConn:Exec( "UPDATE accounts SET balance = balance + 200 WHERE owner = 'bob'"   )

oConn:Commit()

oConn:Close()
```

## BeginTrans / Rollback

When a business condition requires undoing:

```harbour
oConn:BeginTrans()

oConn:Exec( "UPDATE accounts SET balance = balance - 5000 WHERE owner = 'alice'" )

LOCAL oStmt := oConn:Query( "SELECT balance FROM accounts WHERE owner = 'alice'" )
LOCAL hRow  := oStmt:Fetch_Assoc()
oStmt:Free()

IF Val( hRow[ "balance" ] ) < 0
   oConn:Rollback()   // undo the UPDATE
   RETURN USendError( 422, "Insufficient balance" )
ELSE
   oConn:Commit()
ENDIF

oConn:Close()
```

## TRY / FINALLY — recommended pattern

In real handlers, combine `BeginTrans` with `TRY / FINALLY` to guarantee the transaction is always closed even if an exception is raised:

```harbour
FUNCTION TransferFunds()

   LOCAL oConn   := WDO_Get( "APP" )
   LOCAL nFrom   := Val( UPost( "from_id", "0" ) )
   LOCAL nTo     := Val( UPost( "to_id",   "0" ) )
   LOCAL nAmount := Val( UPost( "amount",  "0" ) )
   LOCAL oErr    := NIL
   LOCAL lOk     := .F.

   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   oConn:BeginTrans()

   TRY
      oConn:Exec( "UPDATE accounts SET balance = balance - " + ;
                  hb_NToS( nAmount ) + " WHERE id = " + hb_NToS( nFrom ) )

      oConn:Exec( "UPDATE accounts SET balance = balance + " + ;
                  hb_NToS( nAmount ) + " WHERE id = " + hb_NToS( nTo ) )

      oConn:Commit()
      lOk := .T.

   CATCH oErr
      oConn:Rollback()
      le( "TransferFunds: " + oErr:description )
   FINALLY
      oConn:Close()
   END

   IF ! lOk
      RETURN USendError( 500, "Transfer failed" )
   ENDIF

RETURN USendJson( { "ok" => .T. } )
```

## Transaction(bCode) — syntactic sugar

`oConn:Transaction(bCode)` handles the full cycle automatically:

- Calls `BeginTrans`.
- Evaluates the codeblock.
- If it finishes without exception → `Commit` and returns `.T.`.
- If an exception is raised → `Rollback`, leaves the original description
  in `oConn:cError` (format `"SQLite3 Transaction aborted: <description>"`)
  and returns `.F.`. The exception is **not** re-raised — the caller decides
  what to do by reading the `.F.`.

```harbour
LOCAL oConn := WDO_Get( "APP" )

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

IF ! oConn:Transaction( {| o | ;
      o:Exec( "UPDATE accounts SET balance = balance - 200 WHERE owner = 'alice'" ), ;
      o:Exec( "UPDATE accounts SET balance = balance + 200 WHERE owner = 'bob'"   ) ;
   } )
   RETURN USendError( 500, oConn:cError )
ENDIF

USendJson( { "ok" => .T. } )
```

## Transactions with Prepared Statements

Prepared statements are fully compatible with transactions — they operate on the same connection reserved by the request:

```harbour
oConn:BeginTrans()

TRY
   LOCAL oStmt := oConn:Prepare( "INSERT INTO orders (uid, total) VALUES (?, ?)" )
   oStmt:BindParam( 1, nUid,   "i" )
   oStmt:BindParam( 2, nTotal, "n" )
   oStmt:Execute()
   LOCAL nOrderId := oConn:Last_Insert_Id()
   oStmt:Free()

   oStmt := oConn:Prepare( "INSERT INTO order_items (order_id, sku) VALUES (?, ?)" )
   FOR EACH cSku IN aSkus
      oStmt:BindParam( 1, nOrderId, "i" )
      oStmt:BindParam( 2, cSku,     "s" )
      oStmt:Execute()
      oStmt:Reset()
   NEXT
   oStmt:Free()

   oConn:Commit()

CATCH oErr
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   oConn:Rollback()
END

oConn:Close()
```

## Bulk INSERT — transactions are critical

!!! tip "Speed: 100× with explicit transaction"
    By default SQLite operates in autocommit mode: each `INSERT` is an implicit transaction with one fsync to disk. Inserting 10,000 rows without an explicit transaction produces 10,000 fsyncs.

    With an explicit transaction there is only **one fsync** at `Commit()`. The speed difference is two orders of magnitude:

    ```harbour
    oConn:BeginTrans()

    oStmt := oConn:Prepare( "INSERT INTO data (a, b) VALUES (?, ?)" )
    FOR i := 1 TO 10000
       oStmt:BindParam( 1, aA[ i ], "s" )
       oStmt:BindParam( 2, aB[ i ], "n" )
       oStmt:Execute()
       oStmt:Reset()
    NEXT
    oStmt:Free()

    oConn:Commit()   // single fsync
    ```

## Transaction state

```harbour
oConn:InTransaction()   // .T. if there is an open transaction
```

Useful in handlers that may be called from inside or outside a transactional context.

## SQLITE_BUSY — what to do

If a write transaction cannot acquire the lock within `busy_timeout_ms` milliseconds, the driver raises an error with SQLite code `SQLITE_BUSY` (5) or `SQLITE_LOCKED` (6):

```harbour
TRY
   oConn:BeginTrans()
   // ...
   oConn:Commit()
CATCH oErr
   IF "busy" $ Lower( oErr:description ) .OR. "locked" $ Lower( oErr:description )
      RETURN USendError( 503, "Database busy. Retry in a moment." )
   ENDIF
   RETURN USendError( 500, oErr:description )
END
```

!!! info "busy_timeout_ms default"
    The driver configures `PRAGMA busy_timeout = 5000` when opening the connection (configurable in `config.json`). With this value, SQLite automatically retries for 5 seconds before returning `SQLITE_BUSY`. For most apps this is sufficient.

## Quick reference

| Method | Description |
|--------|-------------|
| `oConn:BeginTrans()` | Starts the transaction (`BEGIN`) |
| `oConn:Commit()` | Confirms changes (`COMMIT`) |
| `oConn:Rollback()` | Undoes changes (`ROLLBACK`) |
| `oConn:Transaction(bCode)` | Sugar: begin + eval + automatic commit/rollback |
| `oConn:InTransaction()` | `.T.` if there is an open transaction |
