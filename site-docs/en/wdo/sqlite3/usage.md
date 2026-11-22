# WDO SQLite3 — Usage

Once the DB is configured in `config.json`, using it in handlers is straightforward. `WDO_Get("APP")` returns a connection ready to operate.

!!! info "Singleton vs pool — `pool_size`"
    The driver operates in two modes according to `pool_size` (see [Configuration](config.md#pool_size)):

    - **`pool_size: 1`** (default) — **singleton**. `WDO_Get("APP")` always returns the same instance. A single handle against the file; the driver serialises internally with a mutex.
    - **`pool_size: N > 1`** — **real pool**. N connections against the same file; each thread reserves one during the request. Needed when two concurrent handlers may have overlapping `Transaction()` calls (see [Transactions](transactions.md)). Added in v2.5.3.

    In both modes the handler API is identical: `WDO_Get` + `Close()`. The driver manages reservation/release automatically.

## Basic handler template

```harbour
FUNCTION ProductList()

   LOCAL oConn := WDO_Get( "APP" )   // reference to the singleton
   LOCAL oStmt, aRows, oErr

   IF oConn == NIL
      RETURN USendError( 503, "DB unavailable" )
   ENDIF

   TRY
      oStmt := oConn:Query( "SELECT id, name, price FROM products ORDER BY id" )
      aRows := oStmt:FetchAll( .T. )   // .T. = array of hashes
      oStmt:Free()
   CATCH oErr
      RETURN USendError( 500, oErr:description )
   END

   oConn:Close()   // good portability practice; no-op in singleton

RETURN USendJson( aRows )
```

!!! info "Close() — behaviour by mode"
    - **Singleton (`pool_size: 1`)**: `oConn:Close()` is a no-op; the connection lives from bootstrap to shutdown.
    - **Pool (`pool_size > 1`)**: `oConn:Close()` releases the slot to the pool for another thread to use. In any case, the HIX dispatcher calls `WDO_ReleaseAllThread()` at the end of each request, so it is **not mandatory** to call it explicitly.

    Keeping the `oConn:Close()` pattern in handlers makes it easy to port code between SQLite / PG / MySQL.

## Driver API

### Read queries

```harbour
// Simple query → resultset object
oStmt := oConn:Query( "SELECT id, name FROM users WHERE active = 1" )

// Get all rows as array of hashes (field => value)
aRows := oStmt:FetchAll( .T. )

// Or as array of arrays (index-based access, 1-based)
aRows := oStmt:FetchAll( .F. )

// Row by row — hash
DO WHILE ( hRow := oStmt:Fetch_Assoc() ) != NIL
   ? hRow[ "name" ]
ENDDO

// Row by row — array
DO WHILE ( aRow := oStmt:Fetch() ) != NIL
   ? aRow[ 1 ]   // first column
ENDDO

oStmt:Free()   // always release the statement
```

!!! warning "Count() returns -1 in SQLite3"
    SQLite does not know the total number of rows in a SELECT before having iterated all of them. `oStmt:Count()` **always returns -1**. To get the total row count, first run `SELECT count(*) FROM ...`:

    ```harbour
    oStmt  := oConn:Query( "SELECT count(*) FROM products" )
    aRow   := oStmt:Fetch()
    nTotal := Val( aRow[ 1 ] )
    oStmt:Free()
    ```

### Write queries

```harbour
// Exec — for INSERT / UPDATE / DELETE without resultset
oConn:Exec( "UPDATE users SET active = 0 WHERE id = " + hb_NToS( nId ) )

// Rows affected by the last executed statement
? oConn:Changes()         // alias: oConn:Affected_Rows()

// Accumulated across the entire connection session
? oConn:Total_Changes()

// Last rowid generated (after INSERT)
nNewId := oConn:Last_Insert_Id()
```

### Check if a table exists

```harbour
IF ! oConn:IsTable( "users" )
   oConn:Exec( "CREATE TABLE users (" + ;
               "  id      INTEGER PRIMARY KEY AUTOINCREMENT," + ;
               "  name    TEXT NOT NULL," + ;
               "  email   TEXT UNIQUE" + ;
               ")" )
ENDIF
```

`IsTable(cName)` internally runs `SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?`.

### Manual escaping

!!! tip "Use Prepared Statements"
    For external values (form, JSON, query string), always use [Prepared Statements](prepared.md). Manual escaping is only for SQL built entirely in code without external input.

```harbour
cSafe := oConn:Escape( cExternalValue )   // duplicates single quotes
oConn:Exec( "INSERT INTO log (msg) VALUES ('" + cSafe + "')" )
```

### Table structure

```harbour
// Returns array of hashes { cName, cType, nSize, nDec }
aStruct := oConn:DbStruct( "products" )
FOR EACH hCol IN aStruct
   ? hCol[ "cName" ], hCol[ "cType" ]
NEXT
```

### Server and connection information

```harbour
// SQLite library version
? oConn:ServerInfo()       // "3.46.1"

// Text encoding
? oConn:GetEncoding()      // "UTF-8"

// Hash with current connection parameters
hInfo := oConn:GetConnectionInfo()
// {
//   "file"          => "www/data/app.db",
//   "journal_mode"  => "WAL",
//   "synchronous"   => "NORMAL",
//   "foreign_keys"  => "1",
//   "busy_timeout"  => "5000",
//   "encrypted"     => .F.
// }

// Extended hash with DLL info
hClient := oConn:GetClientInfo()
// {
//   "dll_path"   => "C:/myapp/dll/sqlcipher.dll",
//   "dll_source" => "exedir",
//   "encrypted"  => .F.
// }
```

## Concurrency — singleton mutex vs real pool

### Singleton mode (`pool_size: 1`)

All HIX workers share the same `WDO_Sqlite3` instance. The driver maintains an internal mutex (`oConn:hMutex`) that is acquired in `Execute()` and released in the same `Execute()` or in `Fetch*()`. This means:

- **Concurrent reads:** multiple workers can be in the `Fetch` phase simultaneously (the mutex only covers the `sqlite3_step` phase).
- **Serialised writes:** `Exec()` and the `Execute()` of a prepared DML acquire the exclusive mutex.
- **No deadlocks:** the mutex is non-recursive; do not call driver methods from within a nested Transaction codeblock.
- **Transactions NOT isolated between threads.** The mutex covers individual operations; between `BeginTrans()` and `Commit()` the lock is released. See [Transactions § Isolation](transactions.md#transaction-isolation).

### Pool mode (`pool_size > 1`)

Each thread reserves its own connection when entering the handler. There is no shared mutex between threads: each connection operates on its own `sqlite3*` handle. SQLite coordinates writes at the file level via `busy_timeout_ms`.

- **Concurrent reads:** N threads read in parallel without blocking each other.
- **Writes serialised at file level:** SQLite allows only one writer; if two threads do `UPDATE` simultaneously, the second waits `busy_timeout_ms` before returning `SQLITE_BUSY`.
- **Isolated transactions:** each thread has its own `BEGIN/COMMIT`; no interleaving is possible.

!!! warning "Do not use Lock/Unlock directly"
    The `oConn:Lock()` and `oConn:Unlock()` methods are for internal driver use (singleton mode). Calling them manually in application code can produce deadlocks. In pool mode these methods are no-ops.

## Common patterns

### Read a record by ID

```harbour
FUNCTION ProductGet()

   LOCAL nId   := Val( UParam( "id", "0" ) )
   LOCAL oConn, oStmt, hRow

   IF nId <= 0
      RETURN USendError( 400, "invalid id" )
   ENDIF

   oConn := WDO_Get( "APP" )
   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   oStmt := oConn:Prepare( "SELECT * FROM products WHERE id = ?" )
   oStmt:BindParam( 1, nId, "i" )
   oStmt:Execute()
   hRow := oStmt:Fetch_Assoc()
   oStmt:Free()
   oConn:Close()

   IF hRow == NIL
      RETURN USendError( 404, "Product not found" )
   ENDIF

RETURN USendJson( hRow )
```

### Pagination

```harbour
FUNCTION ProductList()

   LOCAL nPage   := Max( 1, Val( UGet( "page",  "1"  ) ) )
   LOCAL nLimit  := Min( 100, Val( UGet( "limit", "20" ) ) )
   LOCAL nOffset := ( nPage - 1 ) * nLimit
   LOCAL oConn, oStmt, aRows

   oConn := WDO_Get( "APP" )
   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   oStmt := oConn:Prepare( ;
      "SELECT id, name, price FROM products ORDER BY id LIMIT ? OFFSET ?" )
   oStmt:BindParam( 1, nLimit,  "i" )
   oStmt:BindParam( 2, nOffset, "i" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   oStmt:Free()
   oConn:Close()

RETURN USendJson( { "page" => nPage, "limit" => nLimit, "data" => aRows } )
```

### FINALLY — guaranteed release

If the handler is complex and can exit through multiple paths:

```harbour
FUNCTION ComplexHandler()

   LOCAL oConn := WDO_Get( "APP" )
   LOCAL oStmt := NIL
   LOCAL oErr

   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   TRY
      oStmt := oConn:Prepare( "SELECT id FROM products WHERE price > ?" )
      oStmt:BindParam( 1, 10.0, "n" )
      oStmt:Execute()
      // ... process ...
   CATCH oErr
      le( "ComplexHandler: " + oErr:description )
   FINALLY
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      oConn:Close()   // no-op in singleton, but we keep the pattern
   END

RETURN NIL
```

!!! info "Next step"
    To insert or update with external values safely, use [Prepared Statements](prepared.md).
