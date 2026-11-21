# WDO PostgreSQL — Transacciones

WDO soporta transacciones explícitas con `BeginTrans / Commit / Rollback` y un método de conveniencia `Transaction(bCode)` que gestiona el commit/rollback automáticamente.

PostgreSQL opera siempre en modo **autocommit** cuando no hay transacción abierta. `BeginTrans` emite `BEGIN` al servidor; `Commit` emite `COMMIT`; `Rollback` emite `ROLLBACK`.

## BeginTrans / Commit

El patrón básico para un flujo que siempre tiene éxito:

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

Cuando hay una condición de negocio que obliga a deshacer:

```harbour
oConn:BeginTrans()

oConn:Exec( "UPDATE accounts SET balance = balance - 5000 WHERE owner = 'alice'" )

// Comprobar saldo provisional dentro de la transacción
LOCAL oStmt := oConn:Query( "SELECT balance FROM accounts WHERE owner = 'alice'" )
LOCAL hRow  := oStmt:Fetch_Assoc()
oStmt:Free()

IF Val( hRow[ "balance" ] ) < 0
   oConn:Rollback()   // deshacer el UPDATE
   RETURN USendError( 422, "Saldo insuficiente" )
ELSE
   oConn:Commit()
ENDIF

oConn:Close()
```

## TRY / FINALLY — patrón recomendado

En handlers reales, combina `BeginTrans` con `TRY / FINALLY` para garantizar que la transacción siempre se cierra aunque salte una excepción:

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

## Transaction(bCode) — azúcar sintáctico

`oConn:Transaction(bCode)` hace todo el ciclo automáticamente:

- Llama `BeginTrans`.
- Evalúa el codeblock.
- Si termina sin excepción → `Commit`.
- Si se lanza una excepción → `Rollback` y re-lanza la excepción para que el caller la gestione.

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

## Transacciones con Prepared Statements

Los prepared statements son compatibles con transacciones — viven en la misma conexión:

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

!!! tip "RETURNING en lugar de Last_Insert_Id()"
    El ejemplo usa `RETURNING id` para obtener el ID recién creado de forma fiable dentro de la transacción, sin depender de `lastval()`.

## Savepoints

PostgreSQL soporta savepoints dentro de una transacción abierta. WDO_PG los expone directamente via `Exec`:

```harbour
oConn:BeginTrans()

oConn:Exec( "INSERT INTO audit_log (msg) VALUES ('start')" )
oConn:Exec( "SAVEPOINT sp1" )

TRY
   oConn:Exec( "INSERT INTO risky_table (data) VALUES ('...') " )
   oConn:Exec( "RELEASE SAVEPOINT sp1" )
CATCH oErr
   oConn:Exec( "ROLLBACK TO SAVEPOINT sp1" )
   lw( "Risky insert falló, continuando: " + oErr:description )
END

oConn:Exec( "INSERT INTO audit_log (msg) VALUES ('end')" )
oConn:Commit()

oConn:Close()
```

## Rollback automático en el pool

Si un handler adquiere una conexión, abre una transacción y llama `oConn:Close()` sin hacer Commit ni Rollback explícito (o si el dispatcher reclama la conexión por el safety net), el pool hace **Rollback automático** antes de liberar el slot. Los datos nunca quedan en un estado parcial en el servidor.

!!! warning "PostgreSQL en estado de error"
    Si una query dentro de una transacción falla (p.ej. violación de constraint), PostgreSQL pone la transacción en estado de error y rechaza cualquier comando salvo `ROLLBACK`. Siempre captura los errores dentro de una transacción y llama `Rollback()` si detectas un fallo.

## Estado de la transacción

```harbour
oConn:InTransaction()   // .T. si hay una transacción abierta (BeginTrans sin Commit/Rollback)
```

Útil para diagnóstico o para handlers que necesitan saber si están dentro de un contexto transaccional.

## Referencia rápida

| Método | Descripción |
|--------|-------------|
| `oConn:BeginTrans()` | Inicia la transacción (`BEGIN`) |
| `oConn:Commit()` | Confirma los cambios y cierra la transacción (`COMMIT`) |
| `oConn:Rollback()` | Deshace los cambios y cierra la transacción (`ROLLBACK`) |
| `oConn:Transaction(bCode)` | Azúcar: begin + eval + commit/rollback automático |
| `oConn:InTransaction()` | `.T.` si hay transacción abierta |
| `oConn:Exec("SAVEPOINT sp")` | Crea un savepoint dentro de la transacción |
| `oConn:Exec("ROLLBACK TO SAVEPOINT sp")` | Deshace hasta el savepoint |
| `oConn:Exec("RELEASE SAVEPOINT sp")` | Libera el savepoint sin deshacer |
