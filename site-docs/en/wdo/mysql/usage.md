# WDO MySQL - Pool Usage

Once the pool is configured in `config.json`, using it in handlers is straightforward.

## Basic handler template

```harbour
FUNCTION ProductList()

   LOCAL oConn := WDO_Get( "mysql" )   // acquire a pool slot
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
    `oConn:Close()` returns the slot to the pool so another thread can use it. If you forget, the slot stays locked until the HIX dispatcher reclaims it at the end of the request (with a WARN in the log).

## Driver API

### Read queries

```harbour
// Simple query → resultset object
oStmt := oConn:Query( "SELECT id, name FROM users WHERE active = 1" )

// Get all rows as array of hashes (field => value)
aRows := oStmt:FetchAll( .T. )

// Or as array of arrays (faster, index-based access)
aRows := oStmt:FetchAll( .F. )

// Row by row
DO WHILE ( hRow := oStmt:Fetch_Assoc() ) != NIL
   ? hRow[ "name" ]
ENDDO

oStmt:Free()   // always free the resultset
```

### Write queries

```harbour
// Exec - for INSERT / UPDATE / DELETE without a resultset
oConn:Exec( "UPDATE users SET active = 0 WHERE id = " + hb_NToS( nId ) )

// Affected rows
? oConn:Affected_Rows()

// Last auto-generated ID (after INSERT with AUTO_INCREMENT)
nNewId := oConn:Last_Insert_Id()
```

### Manual escaping

!!! tip "Use Prepared Statements"
    For external values (form, JSON, query string), always use [Prepared Statements](prepared.md). Manual escaping is only for SQL built entirely in code with no external input.

```harbour
// For queries without prepared statements with external strings
cSafe := oConn:Escape( cExternalValue )
oConn:Exec( "INSERT INTO log (msg) VALUES ('" + cSafe + "')" )
```

### Server information

```harbour
? oConn:mysql_get_server_info()    // "8.0.33"
? oConn:mysql_get_client_info()    // "6.1.6" (client DLL version)
? oConn:VersionName()              // "MySQL 8.0.33"
? oConn:DllPath()                  // "c:/myapp/libmysql64.dll"
? oConn:DllSource()                // "exedir" / "override" / etc.
```

## HIX ↔ Pool ↔ MySQL balancing

The three levels must be sized in cascade:

```
MySQL max_connections  >  HIX pool_size  ≥  WDO pool_size
```

| Level | Parameter | Recommendation |
|-------|-----------|----------------|
| HIX workers | `hix.ini → server.pool_size` | 2× the WDO pool |
| WDO pool | `config.json → pool_size` | `peak_QPS × avg_latency_sec` |
| MySQL | `my.cnf → max_connections` | WDO pool + 30 (admin margin) |

**Little's Law:** if your app handles 500 req/s and each query takes 10 ms on average, you need `500 × 0.010 = 5` simultaneous active connections. A pool of 10 gives a 2× margin.

### Verify in production

```harbour
oSrv:AddRouteGet( "health.db", "/health/db", {||
   USendJson( WDO_PoolStats( "mysql" ) )
   // returns: { "size" => 5, "busy" => 2, "free" => 3, "closed" => false }
} )
```

If `free` stays at 0 consistently → increase `pool_size`. If `busy` never exceeds 2 with a pool of 10 → you are over-provisioned.

## Common patterns

### Read a record by ID

```harbour
FUNCTION UserGet()

   LOCAL nId   := Val( UParam( "id", "0" ) )
   LOCAL oConn, oStmt, hRow

   IF nId <= 0
      RETURN USendError( 400, "invalid id" )
   ENDIF

   oConn := WDO_Get( "mysql" )
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

   LOCAL nPage  := Max( 1, Val( UGet( "page",  "1"  ) ) )
   LOCAL nLimit := Min( 100, Val( UGet( "limit", "20" ) ) )
   LOCAL nOffset := ( nPage - 1 ) * nLimit
   LOCAL oConn, oStmt, aRows

   oConn := WDO_Get( "mysql" )
   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   // For external values, use Prepare (see Prepared Statements section)
   oStmt := oConn:Query( "SELECT id, name FROM users ORDER BY id " + ;
                         "LIMIT "  + hb_NToS( nLimit  ) + ;
                         " OFFSET " + hb_NToS( nOffset ) )
   aRows := oStmt:FetchAll( .T. )
   oStmt:Free()
   oConn:Close()

RETURN USendJson( { "page" => nPage, "limit" => nLimit, "data" => aRows } )
```

### FINALLY - guaranteed release

If the handler is complex and can exit through multiple paths:

```harbour
FUNCTION ComplexHandler()

   LOCAL oConn := WDO_Get( "mysql" )
   LOCAL oStmt := NIL

   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   TRY
      oStmt := oConn:Prepare( "SELECT id FROM users WHERE age > ?" )
      oStmt:BindParam( 1, 18, "i" )
      oStmt:Execute()
      // ... processing ...
   FINALLY
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      oConn:Close()   // always executes, whether success or error
   END

RETURN NIL
```
