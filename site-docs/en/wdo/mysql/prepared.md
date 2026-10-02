# WDO MySQL - Prepared Statements

Prepared statements are the correct way to execute queries with external values (from forms, query strings, JSON, etc.). They protect against SQL injection and, for bulk INSERTs, reuse the query plan server-side.

## Prepare or Query?

```
Does any value come from the outside (form, URL, JSON, session)?
├── YES → Prepare. No exceptions.
└── NO  → Is the query repeated many times with different values?
         ├── YES → Prepare (avoids re-parsing on the server)
         └── NO  → Query. Constant SQL with no external variables.
```

Simple rule: **if you would write `Escape()`, write `Prepare()`**.

## Basic example

```harbour
LOCAL oConn := WDO_Get( "mysql" )
LOCAL oStmt, aRows

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

oStmt := oConn:Prepare( "SELECT id, name FROM users WHERE age > ? AND city = ?" )
oStmt:BindParam( 1, 18,       "i" )   // 1-based index, type "i" = integer
oStmt:BindParam( 2, "Girona", "s" )   // type "s" = string
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()     // MANDATORY before Close

oConn:Close()
USendJson( aRows )
```

## Placeholders

### Positional `?`

The N-th `?` in the SQL corresponds to `BindParam(N, ...)`:

```harbour
oStmt := oConn:Prepare( "INSERT INTO log (level, msg) VALUES (?, ?)" )
oStmt:BindParam( 1, "error",   "s" )
oStmt:BindParam( 2, cMessage,  "s" )
oStmt:Execute()
oStmt:Free()
```

### Named `:name`

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id FROM users WHERE city = :city AND active = :active" )
oStmt:BindParam( ":city",   "Girona", "s" )
oStmt:BindParam( ":active", 1,        "i" )
oStmt:Execute()
```

The same `:name` can appear multiple times in the SQL — a single `BindParam` is enough.

### `BindParams` - positional shortcut

```harbour
oStmt := oConn:Prepare( "INSERT INTO events (name, ts) VALUES (?, ?)" )
oStmt:BindParams( { cName, hb_DateTime() } )   // infers types automatically
oStmt:Execute()
oStmt:Free()
```

## Types

| `cType` | Use | Example |
|---------|-----|---------|
| `"i"` | Integer, boolean (0/1) | `18`, `.T.` → `1` |
| `"n"` | Decimal number | `12.50` |
| `"s"` | String | `"Girona"` |
| `"d"` | Date → `'YYYY-MM-DD'` | `Date()` |
| `"t"` | Timestamp → `'YYYY-MM-DD HH:MM:SS'` | `hb_DateTime()` |
| `"b"` | Binary blob → `x'HEX'` | binary data |
| _(omitted)_ | Inferred from `ValType` | recommended only for clear types |

!!! warning "Cases where inference may fail"
    - `CToD("")` has `ValType == "D"` but should be `NULL` → pass explicit `NIL`.
    - Empty strings → `''` (empty SQL string), not `NULL`. If you want NULL, pass `NIL`.

## Common patterns

### Pagination

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id, name FROM users ORDER BY id LIMIT ? OFFSET ?" )
oStmt:BindParam( 1, nLimit,  "i" )
oStmt:BindParam( 2, nOffset, "i" )
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()
```

### LIKE with wildcards

The `%` signs go in the **value**, not in the SQL:

```harbour
oStmt := oConn:Prepare( "SELECT id FROM users WHERE name LIKE ?" )
oStmt:BindParam( 1, "%" + cSearch + "%", "s" )
oStmt:Execute()
```

### Dynamic IN-list

MySQL does not accept `IN (?)` with an array — generate N placeholders:

```harbour
LOCAL aIds := { 1, 5, 42 }
LOCAL cSql, i

cSql  := "SELECT id, name FROM users WHERE id IN (" + ;
         Left( Replicate( "?,", Len( aIds ) ), Len( aIds ) * 2 - 1 ) + ")"
oStmt := oConn:Prepare( cSql )

FOR i := 1 TO Len( aIds )
   oStmt:BindParam( i, aIds[ i ], "i" )
NEXT
oStmt:Execute()
```

### Bulk INSERT - reuse the same Prepare

```harbour
oStmt := oConn:Prepare( "INSERT INTO log (level, msg) VALUES (?, ?)" )

FOR EACH hRow IN aLogRows
   oStmt:BindParam( 1, hRow[ "level" ], "s" )
   oStmt:BindParam( 2, hRow[ "msg"   ], "s" )
   IF ! oStmt:Execute()
      le( "insert failed: " + oStmt:cError )
      EXIT
   ENDIF
NEXT

oStmt:Free()
```

### UPDATE with optional fields

```harbour
LOCAL aSet := {}, aVal := {}

IF ! Empty( cName )
   AAdd( aSet, "name = ?" ) ; AAdd( aVal, { cName, "s" } )
ENDIF
IF nAge > 0
   AAdd( aSet, "age = ?" )  ; AAdd( aVal, { nAge,  "i" } )
ENDIF

IF Empty( aSet ) ; RETURN ; ENDIF

oStmt := oConn:Prepare( "UPDATE users SET " + ;
         hb_ArrayToList( aSet, ", " ) + " WHERE id = ?" )

LOCAL i
FOR i := 1 TO Len( aVal )
   oStmt:BindParam( i, aVal[ i ][ 1 ], aVal[ i ][ 2 ] )
NEXT
oStmt:BindParam( Len( aVal ) + 1, nId, "i" )
oStmt:Execute()
oStmt:Free()
```

## Integration with the pool - `Free()` is mandatory

!!! danger "Free() before Close()"
    If you don't call `Free()`, the server-side statement stays alive on the connection (`SHOW PREPARED STATEMENTS` will see them accumulate). The next time the pool delivers that connection, the slot has orphaned statements.

Defensive pattern:

```harbour
LOCAL oConn, oStmt

oConn := WDO_Get( "mysql" )
oStmt := NIL

TRY
   oStmt := oConn:Prepare( "SELECT id FROM users WHERE age > ?" )
   oStmt:BindParam( 1, 18, "i" )
   oStmt:Execute()
   // ...
FINALLY
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   oConn:Close()
END
```

## Introspection after Execute

```harbour
oStmt:FCount()           // number of columns in the resultset
oStmt:DbStruct()         // { { "id", "N", ... }, { "name", "C", ... }, ... }
oStmt:Row_Count()        // rows affected (INSERT/UPDATE/DELETE) or returned (SELECT)
oConn:Last_Insert_Id()   // last AUTO_INCREMENT generated
oStmt:lError             // .T. if there is an error
oStmt:cError             // error description
```

## Antipatterns to avoid

| Antipattern | Problem | Fix |
|-------------|---------|-----|
| `Prepare` inside the loop | N Prepare + N DEALLOCATE | One Prepare outside, N Execute inside |
| `oStmt:Free()` forgotten | Statements accumulate on the server | Put it in FINALLY |
| `LIKE '%?%'` | The `?` is inside a literal, not a placeholder | `LIKE ?` and wildcard in the value |
| `oStmt` in STATIC across requests | Points to the wrong connection | Prepare inside the Get/Close scope |
| Reuse `oStmt` after `Close()` | `oConn` no longer belongs to this thread | oStmt scope = Get/Close scope |

## Alt A - native binary protocol

For large BLOBs (> 1 MB), binary data with NUL bytes or high-precision decimal bulk INSERTs, `WDO_MySqlStmtBin` (Alt A) is available, which uses MySQL's native binary protocol (`mysql_stmt_*`). See `docs/mysql/prepared_statements_bin.md` for details.
