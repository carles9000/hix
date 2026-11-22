# WDO SQLite3 — Prepared Statements

Prepared statements are the correct way to execute queries with external values. SQLite3 implements them natively via `sqlite3_prepare_v2` + `sqlite3_step`, without any client-side rewriting.

## Prepare or Query?

```
Does any value come from the outside (form, URL, JSON, session)?
├── YES → Prepare. Always. No exceptions.
└── NO  → Is the query repeated many times with different values?
          ├── YES → Prepare (avoids recompiling the plan on each call)
          └── NO  → Query. Constant SQL without external variables.
```

Simple rule: **if you would write `Escape()`, write `Prepare()`**.

## Basic example

```harbour
LOCAL oConn := WDO_Get( "APP" )
LOCAL oStmt, aRows

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

oStmt := oConn:Prepare( "SELECT id, name FROM users WHERE age > ? AND city = ?" )
oStmt:BindParam( 1, 18,       "i" )   // 1-based index, type "i" = integer
oStmt:BindParam( 2, "London", "s" )   // type "s" = string
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()   // MANDATORY — calls sqlite3_finalize

oConn:Close()
USendJson( aRows )
```

## Placeholders — 4 native styles

Unlike MySQL or PostgreSQL, SQLite accepts all four placeholder styles natively. The WDO driver does no rewriting.

### Positional `?`

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
oStmt:BindParam( ":city",   "London", "s" )
oStmt:BindParam( ":active", 1,        "i" )
oStmt:Execute()
```

### Named `@name`

```harbour
oStmt := oConn:Prepare( "UPDATE config SET value = @val WHERE key = @key" )
oStmt:BindParam( "@val", cValue, "s" )
oStmt:BindParam( "@key", cKey,   "s" )
oStmt:Execute()
oStmt:Free()
```

### Named `$name`

```harbour
oStmt := oConn:Prepare( "INSERT INTO events (name, ts) VALUES ($name, $ts)" )
oStmt:BindParam( "$name", cName,          "s" )
oStmt:BindParam( "$ts",   hb_DateTime(), "t" )
oStmt:Execute()
oStmt:Free()
```

!!! tip "The same name can appear multiple times"
    With named placeholders, a single `BindParam` is enough for all occurrences:
    ```harbour
    oStmt := oConn:Prepare( "SELECT * FROM a WHERE x = :v UNION SELECT * FROM b WHERE x = :v" )
    oStmt:BindParam( ":v", cValue, "s" )
    ```

## Bind types

| `cType` | Use | Example |
|---------|-----|---------|
| `"i"` | Integer, boolean (0/1) | `18`, `.T.` → `1` |
| `"n"` | Decimal numeric | `12.50` |
| `"s"` / `"T"` | String / text | `"London"` |
| `"d"` | Date → `'YYYY-MM-DD'` | `Date()` |
| `"t"` | Timestamp → `'YYYY-MM-DD HH:MM:SS'` | `hb_DateTime()` |
| `"b"` | Binary blob | binary data |
| `"N"` | Explicit NULL | equivalent to passing `NIL` |
| _(omitted)_ | Inferred from `ValType()` | recommended only for clear types |

!!! warning "NIL = NULL"
    `BindParam(n, NIL)` calls `sqlite3_bind_null`. If you want an empty SQL string use `BindParam(n, "", "s")`.

## BindParams — positional shortcut

```harbour
oStmt := oConn:Prepare( "INSERT INTO events (name, ts) VALUES (?, ?)" )
oStmt:BindParams( { cName, hb_DateTime() } )   // infers types automatically
oStmt:Execute()
oStmt:Free()
```

## Reusing prepared statements with Reset()

In SQLite3, a compiled prepared statement can be reset and executed again without calling `sqlite3_prepare_v2` again. This is especially useful in bulk INSERTs:

```harbour
LOCAL oStmt := oConn:Prepare( "INSERT INTO log (msg, level) VALUES (?, ?)" )

FOR EACH cMsg IN aMessages
   oStmt:BindParam( 1, cMsg,    "s" )
   oStmt:BindParam( 2, nLevel,  "i" )
   oStmt:Execute()
   oStmt:Reset()   // sqlite3_reset + sqlite3_clear_bindings — ready for the next
NEXT

oStmt:Free()   // sqlite3_finalize when done
```

!!! info "Reset() vs Free()"
    `Reset()` clears the internal state of the statement to reuse it. `Free()` destroys it definitively (`sqlite3_finalize`). `Free()` only needs to be called once at the end, even if `Reset()` was called many times.

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

The `%` go in the **value**, not in the SQL:

```harbour
oStmt := oConn:Prepare( "SELECT id FROM users WHERE name LIKE ?" )
oStmt:BindParam( 1, "%" + cSearch + "%", "s" )
oStmt:Execute()
```

### Dynamic IN-list

SQLite does not accept `IN (?)` with an array — generate N placeholders:

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
aRows := oStmt:FetchAll( .T. )
oStmt:Free()
```

### Bulk INSERT — reuse with Reset()

```harbour
oStmt := oConn:Prepare( "INSERT INTO log (level, msg) VALUES (?, ?)" )

FOR EACH hRow IN aLogRows
   oStmt:BindParam( 1, hRow[ "level" ], "s" )
   oStmt:BindParam( 2, hRow[ "msg"   ], "s" )
   IF ! oStmt:Execute()
      le( "insert failed: " + oStmt:cError )
      EXIT
   ENDIF
   oStmt:Reset()
NEXT

oStmt:Free()
```

!!! tip "Bulk INSERT + Transaction"
    Wrapping a bulk INSERT in an explicit transaction multiplies speed by a factor of 100× or more. SQLite does one fsync per implicit transaction; with an explicit transaction there is only one fsync at the end. See [Transactions](transactions.md).

### UPDATE with optional fields

```harbour
LOCAL aSet := {}, aVal := {}, i

IF ! Empty( cName )
   AAdd( aSet, "name = ?" ) ; AAdd( aVal, { cName, "s" } )
ENDIF
IF nAge > 0
   AAdd( aSet, "age = ?" )  ; AAdd( aVal, { nAge,  "i" } )
ENDIF

IF Empty( aSet ) ; RETURN ; ENDIF

oStmt := oConn:Prepare( "UPDATE users SET " + ;
         hb_ArrayToList( aSet, ", " ) + " WHERE id = ?" )

FOR i := 1 TO Len( aVal )
   oStmt:BindParam( i, aVal[ i ][ 1 ], aVal[ i ][ 2 ] )
NEXT
oStmt:BindParam( Len( aVal ) + 1, nId, "i" )
oStmt:Execute()
oStmt:Free()
```

## Mandatory Free()

!!! danger "Free() before Close()"
    If you do not call `Free()`, the statement stays in memory until the process ends. In handlers called thousands of times, this accumulates `sqlite3_stmt*` without freeing. Always call `Free()` in a `FINALLY` block:

```harbour
LOCAL oConn, oStmt

oConn := WDO_Get( "APP" )
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
oStmt:FCount()          // number of resultset columns (available after Execute)
oStmt:Count()           // ALWAYS -1 in SQLite3 (total unknown before EOF)
oStmt:Row_Count()       // affected rows (INSERT/UPDATE/DELETE)
oStmt:Changes()         // alias of Row_Count()
oConn:Last_Insert_Id()  // last auto-generated rowid
oStmt:lError            // .T. if there is an error
oStmt:cError            // error description
```

## Antipatterns to avoid

| Antipattern | Problem | Fix |
|-------------|---------|-----|
| `Prepare` inside a loop without `Reset` | N `Prepare` + N `Free` without reuse | One `Prepare` outside, N `Execute + Reset` inside |
| `oStmt:Free()` forgotten | Statements accumulating in memory | Always in `FINALLY` |
| `LIKE '%?%'` | `?` is inside a literal, not a placeholder | `LIKE ?` with wildcards in the value |
| `oStmt` in STATIC between requests | SQLite serialises; statement may be in use by another worker | `Prepare` inside the scope of each handler |
| Calling `Reset()` after `Free()` | `sqlite3_stmt*` is no longer valid → crash | `Free()` is always the last call |
