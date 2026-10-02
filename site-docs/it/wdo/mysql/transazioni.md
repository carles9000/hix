# WDO MySQL - Transazioni

WDO supporta le transazioni esplicite con `BeginTrans / Commit / Rollback` e un metodo di convenienza `Transaction(bCode)` che gestisce automaticamente il commit/rollback.

## BeginTrans / Commit

Il pattern base per un flusso che ha sempre successo:

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

Quando c'è una condizione di business che obbliga a annullare:

```harbour
oConn:BeginTrans()

oConn:Exec( "UPDATE accounts SET balance = balance - 5000 WHERE owner = 'alice'" )

// Controllare il saldo provvisorio all'interno della transazione
LOCAL oStmt := oConn:Query( "SELECT balance FROM accounts WHERE owner = 'alice'" )
LOCAL hRow  := oStmt:Fetch_Assoc()
oStmt:Free()

IF Val( hRow[ "balance" ] ) < 0
   oConn:Rollback()   // annullare l'UPDATE
   RETURN USendError( 422, "Saldo insufficiente" )
ELSE
   oConn:Commit()
ENDIF

oConn:Close()
```

## TRY / FINALLY - pattern consigliato

Negli handler reali, combina `BeginTrans` con `TRY / FINALLY` per garantire che la transazione venga sempre chiusa anche se viene lanciata un'eccezione:

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

## Transaction(bCode) - zucchero sintattico

`oConn:Transaction(bCode)` esegue l'intero ciclo automaticamente:

- Chiama `BeginTrans`.
- Valuta il codeblock.
- Se termina senza eccezione → `Commit`.
- Se viene lanciata un'eccezione → `Rollback` e rilancia l'eccezione affinché il chiamante la gestisca.

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

## Transazioni con Prepared Statements

I prepared statement sono compatibili con le transazioni - vivono nella stessa connessione:

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

## Rollback automatico nel pool

Se un handler acquisisce una connessione, apre una transazione e chiama `oConn:Close()` senza eseguire Commit né Rollback esplicito (o se il dispatcher recupera la connessione tramite il safety net), il pool esegue il **Rollback automatico** prima di liberare lo slot. I dati non rimangono mai in uno stato parziale nel server.

## Stato della transazione

```harbour
oConn:InTransaction()   // .T. se c'è una transazione aperta (BeginTrans senza Commit/Rollback)
```

Utile per la diagnostica o per handler che devono sapere se si trovano in un contesto transazionale.

## Riferimento rapido

| Metodo | Descrizione |
|--------|-------------|
| `oConn:BeginTrans()` | Avvia la transazione (`SET autocommit=0` + `BEGIN`) |
| `oConn:Commit()` | Conferma le modifiche e chiude la transazione |
| `oConn:Rollback()` | Annulla le modifiche e chiude la transazione |
| `oConn:Transaction(bCode)` | Zucchero: begin + eval + commit/rollback automatico |
| `oConn:InTransaction()` | `.T.` se c'è una transazione aperta |
