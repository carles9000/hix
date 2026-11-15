# WDO MySQL - Transactions

WDO supports explicit transactions with `BeginTrans / Commit / Rollback` and a convenience method `Transaction(bCode)` that manages commit/rollback automatically.

## BeginTrans / Commit

The basic pattern for a flow that always succeeds:

```harbour
LOCAL oConn := WDO_Get( "mysql" )

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

oConn:BeginTrans()

oConn:Exec( "UPDATE accounts SET balance = balance - 200 WHERE owner = 'alice'" )
oConn:Exec( "UPDATE accounts SET balance = balance + 200 WHERE owner = 'bob'"   )

oConn:Commit()

oConn:Close()
```

## BeginTrans / Rollback

When a business condition requires undoing changes:

```harbour
oConn:BeginTrans()

oConn:Exec( "UPDATE accounts SET balance = balance - 5000 WHERE owner = 'alice'" )

// Check provisional balance inside the transaction
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

## TRY / FINALLY - recommended pattern

In real handlers, combine `BeginTrans` with `TRY / FINALLY` to guarantee the transaction is always closed even if an exception is thrown:

```harbour
FUNCTION TransferFunds()

   LOCAL oConn  := WDO_Get( "mysql" )
   LOCAL nFrom  := Val( UPost( "from_id", "0" ) )
   LOCAL nTo    := Val( UPost( "to_id",   "0" ) )
   LOCAL nAmount:= Val( UPost( "amount",  "0" ) )
   LOCAL oErr   := NIL
   LOCAL lOk    := .F.

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

## Transaction(bCode) - syntactic sugar

`oConn:Transaction(bCode)` handles the full cycle automatically:

- Calls `BeginTrans`.
- Evaluates the codeblock.
- If it ends without exception → `Commit`.
- If an exception is thrown → `Rollback` and re-throws the exception for the caller to handle.

```harbour
LOCAL oConn := WDO_Get( "mysql" )

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
   NEXT
   oStmt:Free()

   oConn:Commit()

CATCH oErr
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   oConn:Rollback()
END

oConn:Close()
```

## Automatic rollback in the pool

If a handler acquires a connection, opens a transaction and calls `oConn:Close()` without an explicit Commit or Rollback (or if the dispatcher reclaims the connection via the safety net), the pool performs an **automatic Rollback** before releasing the slot. Data is never left in a partial state on the server.

## Transaction state

```harbour
oConn:InTransaction()   // .T. if a transaction is open (BeginTrans without Commit/Rollback)
```

Useful for diagnostics or for handlers that need to know whether they are inside a transactional context.

## Quick reference

| Method | Description |
|--------|-------------|
| `oConn:BeginTrans()` | Starts the transaction (`SET autocommit=0` + `BEGIN`) |
| `oConn:Commit()` | Confirms the changes and closes the transaction |
| `oConn:Rollback()` | Undoes the changes and closes the transaction |
| `oConn:Transaction(bCode)` | Sugar: begin + eval + automatic commit/rollback |
| `oConn:InTransaction()` | `.T.` if a transaction is open |
