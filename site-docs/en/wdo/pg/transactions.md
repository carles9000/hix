# WDO PostgreSQL — Transactions

WDO supports explicit transactions with `BeginTrans / Commit / Rollback` and a convenience method `Transaction(bCode)` that manages commit/rollback automatically.

PostgreSQL always operates in **autocommit** mode when there is no open transaction. `BeginTrans` issues `BEGIN` to the server; `Commit` issues `COMMIT`; `Rollback` issues `ROLLBACK`.

## BeginTrans / Commit

The basic pattern for a flow that always succeeds:

```harbour
LOCAL oConn := WDO_Get( "PG" )

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

// Check provisional balance within the transaction
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

   LOCAL oConn   := WDO_Get( "PG" )
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
- If it finishes without exception → `Commit`.
- If an exception is raised → `Rollback` and re-raises the exception for the caller to handle.

```harbour
LOCAL oConn := WDO_Get( "PG" )
LOCAL oErr

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

TRY
   oConn:Transaction( {| o | ;
      o:Exec( "UPDATE accounts SET balance = balance - 200 WHERE owner = 'alice'" ), ;
      o:Exec( "UPDATE accounts SET balance = balance + 200 WHERE owner = 'bob'"   ) ;
   } )
CATCH oErr
   oConn:Close()
   RETURN USendError( 500, oErr:description )
END

oConn:Close()
USendJson( { "ok" => .T. } )
```

## Transactions with Prepared Statements

Prepared statements are compatible with transactions — they live on the same connection:

```harbour
LOCAL oConn   := WDO_Get( "PG" )
LOCAL oStmt   := NIL
LOCAL nOrderId
LOCAL oErr

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

oConn:BeginTrans()

TRY
   oStmt := oConn:Prepare( ;
      "INSERT INTO orders (uid, total) VALUES ($1, $2) RETURNING id" )
   oStmt:BindParam( 1, nUid,   "i" )
   oStmt:BindParam( 2, nTotal, "n" )
   oStmt:Execute()
   nOrderId := Val( oStmt:Fetch_Assoc()[ "id" ] )
   oStmt:Free()

   oStmt := oConn:Prepare( ;
      "INSERT INTO order_items (order_id, sku) VALUES ($1, $2)" )
   FOR EACH cSku IN aSkus
      oStmt:BindParam( 1, nOrderId, "i" )
      oStmt:BindParam( 2, cSku,     "s" )
      oStmt:Execute()
   NEXT
   oStmt:Free()

   oConn:Commit()

CATCH oErr
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   oConn:Rollback()
   le( "Order create failed: " + oErr:description )
END

oConn:Close()
```

!!! tip "RETURNING instead of Last_Insert_Id()"
    The example uses `RETURNING id` to reliably get the newly created ID within the transaction, without depending on `lastval()`.

## Savepoints

PostgreSQL supports savepoints within an open transaction. WDO_PG exposes them directly via `Exec`:

```harbour
oConn:BeginTrans()

oConn:Exec( "INSERT INTO audit_log (msg) VALUES ('start')" )
oConn:Exec( "SAVEPOINT sp1" )

TRY
   oConn:Exec( "INSERT INTO risky_table (data) VALUES ('...') " )
   oConn:Exec( "RELEASE SAVEPOINT sp1" )
CATCH oErr
   oConn:Exec( "ROLLBACK TO SAVEPOINT sp1" )
   lw( "Risky insert failed, continuing: " + oErr:description )
END

oConn:Exec( "INSERT INTO audit_log (msg) VALUES ('end')" )
oConn:Commit()

oConn:Close()
```

## Automatic rollback in the pool

If a handler acquires a connection, opens a transaction and calls `oConn:Close()` without doing an explicit Commit or Rollback (or if the dispatcher reclaims the connection via the safety net), the pool performs an **automatic Rollback** before releasing the slot. Data is never left in a partial state on the server.

!!! warning "PostgreSQL in error state"
    If a query within a transaction fails (e.g. constraint violation), PostgreSQL puts the transaction in an error state and rejects any command except `ROLLBACK`. Always catch errors within a transaction and call `Rollback()` if you detect a failure.

## Transaction state

```harbour
oConn:InTransaction()   // .T. if there is an open transaction (BeginTrans without Commit/Rollback)
```

Useful for diagnostics or for handlers that need to know if they are inside a transactional context.

## Quick reference

| Method | Description |
|--------|-------------|
| `oConn:BeginTrans()` | Starts the transaction (`BEGIN`) |
| `oConn:Commit()` | Confirms changes and closes the transaction (`COMMIT`) |
| `oConn:Rollback()` | Undoes changes and closes the transaction (`ROLLBACK`) |
| `oConn:Transaction(bCode)` | Sugar: begin + eval + automatic commit/rollback |
| `oConn:InTransaction()` | `.T.` if there is an open transaction |
| `oConn:Exec("SAVEPOINT sp")` | Creates a savepoint within the transaction |
| `oConn:Exec("ROLLBACK TO SAVEPOINT sp")` | Rolls back to the savepoint |
| `oConn:Exec("RELEASE SAVEPOINT sp")` | Releases the savepoint without rolling back |
