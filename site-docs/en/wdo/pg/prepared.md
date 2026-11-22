# WDO PostgreSQL — Prepared Statements

Prepared statements are the correct way to execute queries with external values (from forms, query strings, JSON, etc.). They protect against SQL injection and, in bulk INSERTs, reuse the query plan server-side thanks to `PQprepare` / `PQexecPrepared` from libpq.

## Prepare or Query?

```
Does any value come from the outside (form, URL, JSON, session)?
├── YES → Prepare. Always. No exceptions.
└── NO  → Is the query repeated many times with different values?
          ├── YES → Prepare (avoids re-parsing on the server)
          └── NO  → Query. Constant SQL without external variables.
```

Simple rule: **if you would write `Escape()`, write `Prepare()`**.

## Three placeholder dialects

PostgreSQL natively uses the `$N` placeholder (numbered positional). WDO_PG also accepts `?` and `:name` as syntactic sugar, rewriting them internally to `$1`, `$2`, etc. before calling `PQprepare`.

!!! info "SQL that already uses $N is passed literally"
    If your SQL already contains `$1`, `$2`, etc., the driver detects it and sends it to `PQprepare` without modification. The three dialects are **mutually exclusive** in the same query: do not mix `?` with `$N` or with `:name` in the same SQL.

### Dialect 1 — positional `?`

The N-th `?` in the SQL corresponds to `BindParam(N, ...)`:

```harbour
LOCAL oConn := WDO_Get( "PG" )
LOCAL oStmt, aRows

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

oStmt := oConn:Prepare( "SELECT id, name FROM users WHERE age > ? AND city = ?" )
oStmt:BindParam( 1, 18,       "i" )   // 1-based index, type "i" = integer
oStmt:BindParam( 2, "London", "s" )   // type "s" = string
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()

oConn:Close()
USendJson( aRows )
```

### Dialect 2 — named `:name`

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id FROM users WHERE city = :city AND active = :active" )
oStmt:BindParam( ":city",   "London", "s" )
oStmt:BindParam( ":active", 1,        "i" )
oStmt:Execute()
```

The same `:name` can appear multiple times in the SQL — a single `BindParam` is enough.

### Dialect 3 — native PostgreSQL `$N`

```harbour
// Native PG SQL — maximum clarity, no client-side rewriting
oStmt := oConn:Prepare( ;
   "INSERT INTO log(name, score) VALUES($1::text, $2::int)" )
oStmt:BindParam( 1, "alice", "s" )
oStmt:BindParam( 2, 42,      "i" )
oStmt:Execute()
oStmt:Free()
```

The casts `::text`, `::int`, etc. in the SQL are optional but help the PostgreSQL query planner.

### `BindParams` — positional shortcut

```harbour
oStmt := oConn:Prepare( "INSERT INTO events (name, ts) VALUES ($1, $2)" )
oStmt:BindParams( { cName, hb_DateTime() } )   // infers types automatically
oStmt:Execute()
oStmt:Free()
```

## Types

| `cType` | Use | Example |
|---------|-----|---------|
| `"i"` | Integer, boolean (true/false → 1/0) | `18`, `.T.` → `1` |
| `"n"` | Decimal numeric | `12.50` |
| `"s"` | String (default if omitted and value is C) | `"London"` |
| `"d"` | Date → `'YYYY-MM-DD'` | `Date()` |
| `"t"` | Timestamp → `'YYYY-MM-DD HH:MM:SS'` | `hb_DateTime()` |
| `"b"` | Blob → hexadecimal bytea `\x...` | binary data |
| _(omitted)_ | Inferred from `ValType` | recommended only for clear types |

!!! warning "Cases where inference may fail"
    - `CToD("")` has `ValType == "D"` but should be `NULL` → pass explicit `NIL`.
    - Empty strings → `''` (empty SQL string), not `NULL`. If you want NULL, pass `NIL`.
    - PostgreSQL is stricter with types than MySQL: an `"i"` passed to a `text` column may fail. Use the SQL cast `$1::text` or the correct `"s"` type.

## Server-side prepared statement name

WDO_PG generates a unique name per connection with the format `hix_pg_<tid>_<seq>` (e.g. `hix_pg_15432_3`). Each `Prepare()` increments the sequence counter. `Free()` issues `DEALLOCATE hix_pg_15432_3` to the server to release the cached plan.

## Common patterns

### Pagination

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id, name FROM users ORDER BY id LIMIT $1 OFFSET $2" )
oStmt:BindParam( 1, nLimit,  "i" )
oStmt:BindParam( 2, nOffset, "i" )
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()
```

### LIKE with wildcards

The `%` go in the **value**, not in the SQL:

```harbour
oStmt := oConn:Prepare( "SELECT id FROM users WHERE name ILIKE $1" )
oStmt:BindParam( 1, "%" + cSearch + "%", "s" )
oStmt:Execute()
```

!!! info "ILIKE vs LIKE in PostgreSQL"
    `ILIKE` is PostgreSQL's case-insensitive LIKE. It does not exist in MySQL. Use it when you do not want to distinguish case.

### Dynamic IN-list

PostgreSQL does not accept `IN ($1)` with an array — generate N placeholders:

```harbour
LOCAL aIds := { 1, 5, 42 }
LOCAL cSql, i

cSql := "SELECT id, name FROM users WHERE id IN (" + ;
        Left( Replicate( "?,", Len( aIds ) ), Len( aIds ) * 2 - 1 ) + ")"
oStmt := oConn:Prepare( cSql )

FOR i := 1 TO Len( aIds )
   oStmt:BindParam( i, aIds[ i ], "i" )
NEXT
oStmt:Execute()
```

### Bulk INSERT — reuse the same Prepare

Prepare once, execute N times — the query plan stays cached on the server:

```harbour
oStmt := oConn:Prepare( "INSERT INTO log(name, score) VALUES($1::text, $2::int)" )

FOR i := 1 TO nRows
   oStmt:BindParam( 1, "user_" + StrZero( i, 3 ) )
   oStmt:BindParam( 2, 100 + i * 3, "i" )
   IF ! oStmt:Execute()
      le( "insert failed: " + oStmt:cError )
      EXIT
   ENDIF
NEXT

oStmt:Free()
```

### Hostile input — O'Connor

Prepared statements handle single quotes automatically without manual escaping:

```harbour
oStmt := oConn:Prepare( "SELECT COUNT(*) AS n FROM users WHERE last_name = $1" )
oStmt:BindParam( 1, "O'Connor" )   // single quotes, semicolons, --: all safe
oStmt:Execute()
hRow := oStmt:Fetch_Assoc()
oStmt:Free()
? hRow[ "n" ]
```

### RETURNING — get ID after INSERT

```harbour
oStmt := oConn:Prepare( ;
   "INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, created_at" )
oStmt:BindParam( 1, cName,  "s" )
oStmt:BindParam( 2, cEmail, "s" )
oStmt:Execute()
hRow := oStmt:Fetch_Assoc()
oStmt:Free()

nNewId   := Val( hRow[ "id" ] )
cCreated := hRow[ "created_at" ]
```

### UPDATE with optional fields

```harbour
LOCAL aSet := {}, aVal := {}

IF ! Empty( cName )
   AAdd( aSet, "name = $" + hb_NToS( Len( aSet ) + 1 ) )
   AAdd( aVal, { cName, "s" } )
ENDIF
IF nAge > 0
   AAdd( aSet, "age = $" + hb_NToS( Len( aSet ) + 1 ) )
   AAdd( aVal, { nAge, "i" } )
ENDIF

IF Empty( aSet ) ; RETURN ; ENDIF

AAdd( aVal, { nId, "i" } )
oStmt := oConn:Prepare( "UPDATE users SET " + ;
         hb_ArrayToList( aSet, ", " ) + ;
         " WHERE id = $" + hb_NToS( Len( aVal ) ) )

LOCAL i
FOR i := 1 TO Len( aVal )
   oStmt:BindParam( i, aVal[ i ][ 1 ], aVal[ i ][ 2 ] )
NEXT
oStmt:Execute()
oStmt:Free()
```

## Introspection after Execute

```harbour
oStmt:FCount()          // number of resultset columns
oStmt:DbStruct()        // { { "id", "N", ... }, { "name", "C", ... }, ... }
oStmt:nAffectedRows     // affected rows (INSERT/UPDATE/DELETE)
oStmt:lError            // .T. if there is an error
oStmt:cError            // libpq error description
```

## Pool integration — `Free()` mandatory

!!! danger "Free() before Close()"
    If you do not call `Free()`, the prepared statement plan stays alive on the PostgreSQL connection (`SELECT * FROM pg_prepared_statements` will see it accumulate). The next time the pool hands out that connection, the slot has orphaned plans consuming memory on the server.

Defensive pattern:

```harbour
LOCAL oConn  := WDO_Get( "PG" )
LOCAL oStmt  := NIL
LOCAL oError

TRY
   oStmt := oConn:Prepare( "SELECT id FROM users WHERE age > $1" )
   oStmt:BindParam( 1, 18, "i" )
   oStmt:Execute()
   // ...
CATCH oError
   le( "Handler error: " + oError:description )
FINALLY
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   oConn:Close()
END
```

## Antipatterns to avoid

| Antipattern | Problem | Fix |
|-------------|---------|-----|
| `Prepare` inside the loop | N Prepare + N DEALLOCATE on the server | One Prepare outside, N Execute inside |
| `oStmt:Free()` forgotten | Plans accumulating in `pg_prepared_statements` | Always in FINALLY |
| `LIKE '%$1%'` | `$1` is inside a string literal, not a placeholder | `LIKE $1` with wildcard in the value |
| Mixing `?` with `$N` in the same SQL | Undefined internal rewriting | One dialect per query |
| `oStmt` in STATIC between requests | Points to the wrong connection after `Close()` | oStmt scope = Get/Close scope |
| Reusing `oStmt` after `oConn:Close()` | Connection no longer belongs to this thread | Prepare again after acquiring slot |
