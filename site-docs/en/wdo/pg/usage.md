# WDO PostgreSQL — Pool Usage

Once the pool is configured in `config.json`, using it in handlers is straightforward.

## Basic handler template

```harbour
FUNCTION ProductList()

   LOCAL oConn := WDO_Get( "PG" )   // acquires a pool slot
   LOCAL oStmt, aRows

   IF oConn == NIL
      RETURN USendError( 503, "DB unavailable" )
   ENDIF

   TRY
      oStmt := oConn:Query( "SELECT id, name, price FROM products ORDER BY id" )
      aRows := oStmt:FetchAll( .T. )   // .T. = array of hashes
      oStmt:Free()
   CATCH oError
      oConn:Close()
      RETURN USendError( 500, oError:description )
   END

   oConn:Close()   // returns the slot to the pool (does NOT close the socket)

RETURN USendJson( aRows )
```

!!! warning "Always call Close()"
    `oConn:Close()` returns the slot to the pool so another thread can use it. If you forget, the slot stays blocked until the HIX dispatcher reclaims it at the end of the request (with a WARN in the log).

## Driver API

### Read queries

```harbour
// Simple query → resultset object
oStmt := oConn:Query( "SELECT id, name FROM users WHERE active = true" )

// Get all rows as array of hashes (field => value)
aRows := oStmt:FetchAll( .T. )

// Or as array of arrays (faster, index-based access)
aRows := oStmt:FetchAll( .F. )

// Row by row
DO WHILE ( hRow := oStmt:Fetch_Assoc() ) != NIL
   ? hRow[ "name" ]
ENDDO

oStmt:Free()   // always release the resultset
```

!!! info "Query always returns an object"
    Unlike some drivers, `Query()` in WDO_PG never returns NIL. Always check `oStmt:lError` and `oStmt:cError` to detect SQL errors.

    ```harbour
    oStmt := oConn:Query( "SELECT ..." )
    IF oStmt:lError
       RETURN USendError( 500, oStmt:cError )
    ENDIF
    ```

### Write queries

```harbour
// Exec — for INSERT / UPDATE / DELETE without resultset
oConn:Exec( "UPDATE users SET active = false WHERE id = " + hb_NToS( nId ) )

// Affected rows
? oConn:Affected_Rows()

// Last generated ID — uses lastval() internally
nNewId := oConn:Last_Insert_Id()
```

!!! tip "Prefer RETURNING to get the ID"
    `Last_Insert_Id()` calls `lastval()`, which returns the last value of the **last sequence used in the session**. If the same connection does several INSERTs in different tables, the result may be unexpected. The safe way in PostgreSQL is to use `RETURNING`:

    ```harbour
    oStmt := oConn:Query( "INSERT INTO users (name, email) " + ;
                          "VALUES ('Alice', 'alice@example.com') RETURNING id" )
    hRow := oStmt:Fetch_Assoc()
    nNewId := Val( hRow[ "id" ] )
    oStmt:Free()
    ```

### Manual escaping

!!! tip "Use Prepared Statements for external input"
    For external values (form, JSON, query string), always use [Prepared Statements](prepared.md). Manual escaping is only for SQL built entirely in code without external input.

```harbour
// PostgreSQL uses standard_conforming_strings=on (since PG 9.1):
// only the single quote is doubled, NO backslash escape is used.
cSafe := oConn:Escape( cExternalValue )
oConn:Exec( "INSERT INTO log (msg) VALUES ('" + cSafe + "')" )
```

### DDL NOTICEs

!!! warning "Silencing DDL NOTICEs"
    PostgreSQL emits NOTICE when doing `DROP TABLE IF EXISTS` on non-existent tables. These messages are not errors but clutter the log. To silence them in the current session:

    ```harbour
    oConn:Exec( "SET client_min_messages TO WARNING" )
    oConn:Exec( "DROP TABLE IF EXISTS temp_work" )
    oConn:Exec( "CREATE TABLE temp_work (...)" )
    ```

    This `SET` only affects the current session, never the global server.

### Server information

```harbour
? oConn:ServerInfo()           // "16.0.3"
? oConn:ClientInfo()           // libpq version ("16.0")
? oConn:GetEncoding()          // "UTF8"
? oConn:GetConnectionInfo()    // hash { "db", "user", "host", "port", "encoding" }
? oConn:DllPath()              // "c:/myapp/dll/libpq.dll"
? oConn:DllSource()            // "exedir" / "override" / "env" / "default"
```

### Table structure

```harbour
// DbStruct returns array of arrays: { cName, cType, nSize, nDec }
// cType maps PostgreSQL OID types:
//   "C" → text, varchar, char, bpchar
//   "N" → int2, int4, int8, numeric, float4, float8
//   "L" → bool
//   "D" → date
//   "T" → timestamp, timestamptz
//   "M" → bytea

aStruct := oConn:DbStruct( "users" )
FOR EACH aFld IN aStruct
   ? aFld[1], aFld[2], aFld[3], aFld[4]
NEXT
```

### Check if a table exists

```harbour
IF oConn:IsTable( "users" )
   l( "users table exists" )
ENDIF
```

## HIX ↔ Pool ↔ PostgreSQL sizing

The three levels must be dimensioned in cascade:

```
PostgreSQL max_connections  >  HIX workers  ≥  WDO pool_size
```

| Level | Parameter | Recommendation |
|-------|-----------|----------------|
| HIX workers | `hix.json → server.pool_size` | 2× the WDO pool |
| WDO pool | `config.json → pool_size` | `peak_QPS × avg_latency_sec` |
| PostgreSQL | `postgresql.conf → max_connections` | WDO pool + 20 (admin margin) |

**Little's law:** if your app does 500 req/s and each query takes 10 ms on average, you need `500 × 0.010 = 5` active connections simultaneously. A pool of 10 gives a 2× margin.

!!! info "max_connections in PostgreSQL"
    PostgreSQL's default is 100 connections. Each connection consumes ~5–10 MB of server RAM. Don't raise `max_connections` without calculating available RAM. For scaling beyond 200 connections consider PgBouncer as a pooling proxy.

### Production monitoring

```harbour
oSrv:AddRouteGet( "health.db", "/health/db", {||
   USendJson( WDO_PoolStats( "PG" ) )
   // returns: { "size" => 5, "busy" => 2, "free" => 3, "closed" => false }
} )
```

If `free` stays at 0 continuously → increase `pool_size`. If `busy` never exceeds 2 with a pool of 10 → you are over-provisioned.

## Common patterns

### Read a record by ID

```harbour
FUNCTION UserGet()

   LOCAL nId   := Val( UParam( "id", "0" ) )
   LOCAL oConn, oStmt, hRow

   IF nId <= 0
      RETURN USendError( 400, "invalid id" )
   ENDIF

   oConn := WDO_Get( "PG" )
   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   oStmt := oConn:Query( "SELECT * FROM users WHERE id = " + hb_NToS( nId ) )
   hRow  := oStmt:Fetch_Assoc()
   oStmt:Free()
   oConn:Close()

   IF hRow == NIL
      RETURN USendError( 404, "User not found" )
   ENDIF

RETURN USendJson( hRow )
```

### Pagination

```harbour
FUNCTION UserList()

   LOCAL nPage   := Max( 1, Val( UGet( "page",  "1"  ) ) )
   LOCAL nLimit  := Min( 100, Val( UGet( "limit", "20" ) ) )
   LOCAL nOffset := ( nPage - 1 ) * nLimit
   LOCAL oConn, oStmt, aRows

   oConn := WDO_Get( "PG" )
   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   // For external values use Prepare (see Prepared Statements section)
   oStmt := oConn:Query( "SELECT id, name FROM users ORDER BY id " + ;
                         "LIMIT "  + hb_NToS( nLimit  ) + ;
                         " OFFSET " + hb_NToS( nOffset ) )
   aRows := oStmt:FetchAll( .T. )
   oStmt:Free()
   oConn:Close()

RETURN USendJson( { "page" => nPage, "limit" => nLimit, "data" => aRows } )
```

### FINALLY — guaranteed release

If the handler is complex and can exit through multiple paths:

```harbour
FUNCTION ComplexHandler()

   LOCAL oConn := WDO_Get( "PG" )
   LOCAL oStmt := NIL
   LOCAL oError

   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   TRY
      oStmt := oConn:Prepare( "SELECT id FROM users WHERE age > $1" )
      oStmt:BindParam( 1, 18, "i" )
      oStmt:Execute()
      // ... process ...
   CATCH oError
      le( "ComplexHandler: " + oError:description )
   FINALLY
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      oConn:Close()   // always executes, success or error
   END

RETURN NIL
```

!!! info "Next step"
    To insert or update with external values safely, use [Prepared Statements](prepared.md).
