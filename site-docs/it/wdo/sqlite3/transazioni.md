# WDO SQLite3 — Transazioni

WDO supporta le transazioni esplicite con `BeginTrans / Commit / Rollback` e un metodo di convenienza `Transaction(bCode)` che gestisce commit/rollback automaticamente.

## Concorrenza in SQLite3 — una differenza chiave

!!! warning "SQLite serializza le scritture"
    A differenza di MySQL o PostgreSQL, SQLite consente **un solo writer** alla volta. In modalità WAL, più lettori possono coesistere con quel writer, ma se due thread tentano di avviare una transazione di scrittura contemporaneamente, il secondo aspetta finché il primo non rilascia il lock.

    Se l'attesa supera `busy_timeout_ms`, SQLite restituisce `SQLITE_BUSY`. Configura `busy_timeout_ms >= 5000` in produzione per assorbire i picchi di scrittura concorrente.

## Isolamento delle transazioni {#isolamento-delle-transazioni}

Il driver opera in due modalità secondo `pool_size` ([config](config.md#pool_size)). Ogni modalità offre garanzie di isolamento diverse:

### Singleton (`pool_size: 1`, default)

Una sola connessione condivisa tra tutti i thread. Il mutex interno protegge le **operazioni singole** ma **non mantiene il lock tra `BeginTrans()` e `Commit()`** — tra queste due chiamate altri thread possono intercalare `Exec` / `Query` sulla stessa connessione. SQLite documenta che *una sola connessione non isola le proprie operazioni* ([sqlite.org/isolation](https://www.sqlite.org/isolation.html)).

Conseguenza pratica: se due handler concorrenti eseguono `Transaction()` contemporaneamente, il `BEGIN` del secondo si scontra con `::lInTrans = .T.` del primo e restituisce `.F.` silenziosamente, o peggio — un `SELECT` del thread B può leggere lo stato intermedio non confermato del thread A.

Questa modalità è valida per app con un solo worker, script CLI, o carichi con concorrenza sul DB nulla.

### Pool (`pool_size: N > 1`, consigliato per HIX multi-worker)

Ogni thread prenota la propria connessione all'entrata nell'handler. `BEGIN/COMMIT` operano su handle indipendenti; SQLite coordina le scritture a livello di file tramite `busy_timeout_ms`.

- **Isolamento reale:** le transazioni di thread diversi non si interleaveranno mai.
- **`SQLITE_BUSY` possibile:** due `Transaction()` di scrittura concorrenti sullo stesso file competono per il lock a livello SQLite. Con `busy_timeout_ms: 5000`, SQLite riprova per 5 secondi prima di arrendersi.
- **Letture in parallelo:** la modalità WAL consente più lettori simultanei.
- **Cifratura compatibile:** SQLCipher applica lo stesso `PRAGMA key` a ogni connessione del pool; la DLL viene caricata una sola volta condivisa tramite refcount.

Configurazione consigliata per produzione multi-worker:

```json
"databases": {
   "APP": {
      "driver":          "sqlite3",
      "file":            "www/data/app.db",
      "journal_mode":    "WAL",
      "busy_timeout_ms": 5000,
      "pool_size":       4
   }
}
```

!!! tip "Scegli `pool_size` in base ai worker HTTP"
    Come regola pratica, `pool_size` ≈ numero di worker HTTP che possono toccare il DB contemporaneamente. 4–8 è sufficiente per la maggior parte delle app; alzarlo di più raramente aiuta perché SQLite comunque serializza le scritture a livello di file.

Aggiunto in v2.5.3 (Claim 2 — isolamento transazionale).

## BeginTrans / Commit

Il pattern base per un flusso che ha sempre successo:

```harbour
LOCAL oConn := WDO_Get( "APP" )

IF oConn == NIL ; RETURN USendError( 503, "DB non disponibile" ) ; ENDIF

oConn:BeginTrans()

oConn:Exec( "UPDATE conti SET saldo = saldo - 200 WHERE proprietario = 'alice'" )
oConn:Exec( "UPDATE conti SET saldo = saldo + 200 WHERE proprietario = 'bob'"   )

oConn:Commit()

oConn:Close()
```

## BeginTrans / Rollback

Quando una condizione di business impone di annullare:

```harbour
oConn:BeginTrans()

oConn:Exec( "UPDATE conti SET saldo = saldo - 5000 WHERE proprietario = 'alice'" )

LOCAL oStmt := oConn:Query( "SELECT saldo FROM conti WHERE proprietario = 'alice'" )
LOCAL hRow  := oStmt:Fetch_Assoc()
oStmt:Free()

IF Val( hRow[ "saldo" ] ) < 0
   oConn:Rollback()   // annullare l'UPDATE
   RETURN USendError( 422, "Saldo insufficiente" )
ELSE
   oConn:Commit()
ENDIF

oConn:Close()
```

## TRY / FINALLY — pattern consigliato

Negli handler reali, combina `BeginTrans` con `TRY / FINALLY` per garantire che la transazione venga sempre chiusa anche se viene lanciata un'eccezione:

```harbour
FUNCTION TransferisciFondi()

   LOCAL oConn   := WDO_Get( "APP" )
   LOCAL nFrom   := Val( UPost( "from_id", "0" ) )
   LOCAL nTo     := Val( UPost( "to_id",   "0" ) )
   LOCAL nAmount := Val( UPost( "amount",  "0" ) )
   LOCAL oErr    := NIL
   LOCAL lOk     := .F.

   IF oConn == NIL ; RETURN USendError( 503, "DB non disponibile" ) ; ENDIF

   oConn:BeginTrans()

   TRY
      oConn:Exec( "UPDATE conti SET saldo = saldo - " + ;
                  hb_NToS( nAmount ) + " WHERE id = " + hb_NToS( nFrom ) )

      oConn:Exec( "UPDATE conti SET saldo = saldo + " + ;
                  hb_NToS( nAmount ) + " WHERE id = " + hb_NToS( nTo ) )

      oConn:Commit()
      lOk := .T.

   CATCH oErr
      oConn:Rollback()
      le( "TransferisciFondi: " + oErr:description )
   FINALLY
      oConn:Close()
   END

   IF ! lOk
      RETURN USendError( 500, "Trasferimento fallito" )
   ENDIF

RETURN USendJson( { "ok" => .T. } )
```

## Transaction(bCode) — zucchero sintattico

`oConn:Transaction(bCode)` gestisce l'intero ciclo automaticamente:

- Chiama `BeginTrans`.
- Valuta il codeblock.
- Se termina senza eccezione → `Commit` e restituisce `.T.`.
- Se viene lanciata un'eccezione → `Rollback`, lascia la descrizione
  originale in `oConn:cError` (formato `"SQLite3 Transaction
  aborted: <descrizione>"`) e restituisce `.F.`. L'eccezione **non**
  viene rilancita — il caller decide cosa fare leggendo il `.F.`.

```harbour
LOCAL oConn := WDO_Get( "APP" )

IF oConn == NIL ; RETURN USendError( 503, "DB non disponibile" ) ; ENDIF

IF ! oConn:Transaction( {| o | ;
      o:Exec( "UPDATE conti SET saldo = saldo - 200 WHERE proprietario = 'alice'" ), ;
      o:Exec( "UPDATE conti SET saldo = saldo + 200 WHERE proprietario = 'bob'"   ) ;
   } )
   RETURN USendError( 500, oConn:cError )
ENDIF

USendJson( { "ok" => .T. } )
```

## Transazioni con Prepared Statement

I prepared statement sono completamente compatibili con le transazioni — operano sulla stessa connessione prenotata dalla request:

```harbour
oConn:BeginTrans()

TRY
   LOCAL oStmt := oConn:Prepare( "INSERT INTO ordini (uid, totale) VALUES (?, ?)" )
   oStmt:BindParam( 1, nUid,    "i" )
   oStmt:BindParam( 2, nTotale, "n" )
   oStmt:Execute()
   LOCAL nOrdineId := oConn:Last_Insert_Id()
   oStmt:Free()

   oStmt := oConn:Prepare( "INSERT INTO righe_ordine (ordine_id, sku) VALUES (?, ?)" )
   FOR EACH cSku IN aSkus
      oStmt:BindParam( 1, nOrdineId, "i" )
      oStmt:BindParam( 2, cSku,      "s" )
      oStmt:Execute()
      oStmt:Reset()
   NEXT
   oStmt:Free()

   oConn:Commit()

CATCH oErr
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   oConn:Rollback()
END

oConn:Close()
```

## INSERT massivo — le transazioni sono critiche

!!! tip "Velocità: 100× con transazione esplicita"
    Per default SQLite opera in modalità autocommit: ogni `INSERT` è una transazione implicita con un fsync su disco. Inserire 10.000 righe senza transazione esplicita produce 10.000 fsync.

    Con una transazione esplicita c'è solo **un fsync** al `Commit()`. La differenza di velocità è di due ordini di grandezza:

    ```harbour
    oConn:BeginTrans()

    oStmt := oConn:Prepare( "INSERT INTO dati (a, b) VALUES (?, ?)" )
    FOR i := 1 TO 10000
       oStmt:BindParam( 1, aA[ i ], "s" )
       oStmt:BindParam( 2, aB[ i ], "n" )
       oStmt:Execute()
       oStmt:Reset()
    NEXT
    oStmt:Free()

    oConn:Commit()   // un solo fsync
    ```

## Stato della transazione

```harbour
oConn:InTransaction()   // .T. se c'è una transazione aperta
```

Utile negli handler che possono essere chiamati dall'interno o dall'esterno di un contesto transazionale.

## SQLITE_BUSY — cosa fare

Se una transazione di scrittura non riesce ad acquisire il lock entro `busy_timeout_ms` millisecondi, il driver lancia un errore con codice SQLite `SQLITE_BUSY` (5) o `SQLITE_LOCKED` (6):

```harbour
TRY
   oConn:BeginTrans()
   // ...
   oConn:Commit()
CATCH oErr
   IF "busy" $ Lower( oErr:description ) .OR. "locked" $ Lower( oErr:description )
      RETURN USendError( 503, "Database occupato. Riprova tra un momento." )
   ENDIF
   RETURN USendError( 500, oErr:description )
END
```

!!! info "busy_timeout_ms di default"
    Il driver configura `PRAGMA busy_timeout = 5000` all'apertura della connessione (configurabile in `config.json`). Con questo valore, SQLite riprova automaticamente per 5 secondi prima di restituire `SQLITE_BUSY`. Per la maggior parte delle app è sufficiente.

## Riferimento rapido

| Metodo | Descrizione |
|--------|-------------|
| `oConn:BeginTrans()` | Avvia la transazione (`BEGIN`) |
| `oConn:Commit()` | Conferma le modifiche (`COMMIT`) |
| `oConn:Rollback()` | Annulla le modifiche (`ROLLBACK`) |
| `oConn:Transaction(bCode)` | Zucchero: begin + eval + commit/rollback automatico |
| `oConn:InTransaction()` | `.T.` se c'è una transazione aperta |
