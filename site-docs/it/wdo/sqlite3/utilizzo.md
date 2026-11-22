# WDO SQLite3 — Utilizzo

Una volta configurato il DB in `config.json`, usarlo negli handler è diretto. `WDO_Get("APP")` restituisce una connessione pronta per operare.

!!! info "Singleton vs pool — `pool_size`"
    Il driver opera in due modalità secondo `pool_size` (vedi [Configurazione](config.md#pool_size)):

    - **`pool_size: 1`** (default) — **singleton**. `WDO_Get("APP")` restituisce sempre la stessa istanza. Un unico handle contro il file; il driver serializza internamente con mutex.
    - **`pool_size: N > 1`** — **pool reale**. N connessioni contro lo stesso file; ogni thread ne prenota una durante la request. Necessario quando due handler concorrenti possono avere `Transaction()` sovrapposte (vedi [Transazioni](transazioni.md)). Aggiunto in v2.5.3.

    In entrambe le modalità l'API dell'handler è identica: `WDO_Get` + `Close()`. Il driver gestisce la prenotazione/rilascio automaticamente.

## Template base dell'handler

```harbour
FUNCTION ProdottiList()

   LOCAL oConn := WDO_Get( "APP" )   // riferimento al singleton
   LOCAL oStmt, aRows, oErr

   IF oConn == NIL
      RETURN USendError( 503, "DB non disponibile" )
   ENDIF

   TRY
      oStmt := oConn:Query( "SELECT id, nome, prezzo FROM prodotti ORDER BY id" )
      aRows := oStmt:FetchAll( .T. )   // .T. = array di hash
      oStmt:Free()
   CATCH oErr
      RETURN USendError( 500, oErr:description )
   END

   oConn:Close()   // buona pratica di portabilità; è no-op nel singleton

RETURN USendJson( aRows )
```

!!! info "Close() — comportamento per modalità"
    - **Singleton (`pool_size: 1`)**: `oConn:Close()` è no-op; la connessione vive dall'avvio allo shutdown.
    - **Pool (`pool_size > 1`)**: `oConn:Close()` rilascia lo slot al pool affinché un altro thread possa usarlo. In ogni caso, il dispatcher HIX chiama `WDO_ReleaseAllThread()` alla fine di ogni request, quindi **non è obbligatorio** chiamarlo esplicitamente.

    Mantenere il pattern `oConn:Close()` negli handler facilita il porting del codice tra SQLite / PG / MySQL.

## API del driver

### Query di lettura

```harbour
// Query semplice → oggetto resultset
oStmt := oConn:Query( "SELECT id, name FROM users WHERE active = 1" )

// Ottenere tutte le righe come array di hash (campo => valore)
aRows := oStmt:FetchAll( .T. )

// O come array di array (accesso per indice, 1-based)
aRows := oStmt:FetchAll( .F. )

// Riga per riga — hash
DO WHILE ( hRow := oStmt:Fetch_Assoc() ) != NIL
   ? hRow[ "name" ]
ENDDO

// Riga per riga — array
DO WHILE ( aRow := oStmt:Fetch() ) != NIL
   ? aRow[ 1 ]   // prima colonna
ENDDO

oStmt:Free()   // liberare sempre lo statement
```

!!! warning "Count() restituisce -1 in SQLite3"
    SQLite non conosce il numero totale di righe di un SELECT prima di averle percorse tutte. `oStmt:Count()` **restituisce sempre -1**. Per ottenere il totale, esegui prima `SELECT count(*) FROM ...`:

    ```harbour
    oStmt  := oConn:Query( "SELECT count(*) FROM prodotti" )
    aRow   := oStmt:Fetch()
    nTotal := Val( aRow[ 1 ] )
    oStmt:Free()
    ```

### Query di scrittura

```harbour
// Exec — per INSERT / UPDATE / DELETE senza resultset
oConn:Exec( "UPDATE users SET active = 0 WHERE id = " + hb_NToS( nId ) )

// Righe interessate dall'ultimo statement eseguito
? oConn:Changes()         // alias: oConn:Affected_Rows()

// Accumulato per l'intera sessione di connessione
? oConn:Total_Changes()

// Ultimo rowid generato (dopo INSERT)
nNewId := oConn:Last_Insert_Id()
```

### Verificare l'esistenza di una tabella

```harbour
IF ! oConn:IsTable( "utenti" )
   oConn:Exec( "CREATE TABLE utenti (" + ;
               "  id      INTEGER PRIMARY KEY AUTOINCREMENT," + ;
               "  nome    TEXT NOT NULL," + ;
               "  email   TEXT UNIQUE" + ;
               ")" )
ENDIF
```

`IsTable(cName)` esegue internamente `SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?`.

### Escape manuale

!!! tip "Usa i Prepared Statement"
    Per valori esterni (form, JSON, query string), usa sempre i [Prepared Statement](prepared.md). L'escape manuale è solo per SQL costruito interamente nel codice senza input esterno.

```harbour
cSicuro := oConn:Escape( cValoreEsterno )   // raddoppia le virgolette singole
oConn:Exec( "INSERT INTO log (msg) VALUES ('" + cSicuro + "')" )
```

### Struttura di una tabella

```harbour
// Restituisce array di hash { cName, cType, nSize, nDec }
aStruct := oConn:DbStruct( "prodotti" )
FOR EACH hCol IN aStruct
   ? hCol[ "cName" ], hCol[ "cType" ]
NEXT
```

### Informazioni del server e della connessione

```harbour
// Versione della libreria SQLite
? oConn:ServerInfo()       // "3.46.1"

// Codifica del testo
? oConn:GetEncoding()      // "UTF-8"

// Hash con i parametri di connessione attuali
hInfo := oConn:GetConnectionInfo()
// {
//   "file"          => "www/data/app.db",
//   "journal_mode"  => "WAL",
//   "synchronous"   => "NORMAL",
//   "foreign_keys"  => "1",
//   "busy_timeout"  => "5000",
//   "encrypted"     => .F.
// }

// Hash esteso con info della DLL
hClient := oConn:GetClientInfo()
// {
//   "dll_path"   => "C:/miapp/dll/sqlcipher.dll",
//   "dll_source" => "exedir",
//   "encrypted"  => .F.
// }
```

## Concorrenza — mutex singleton vs pool reale

### Modalità singleton (`pool_size: 1`)

Tutti i worker HIX condividono la stessa istanza `WDO_Sqlite3`. Il driver mantiene un mutex interno (`oConn:hMutex`) acquisito in `Execute()` e rilasciato nello stesso `Execute()` o in `Fetch*()`. Questo significa:

- **Letture concorrenti:** più worker possono essere nella fase `Fetch` contemporaneamente (il mutex copre solo la fase `sqlite3_step`).
- **Scritture serializzate:** `Exec()` e `Execute()` di un DML preparato acquisiscono il mutex esclusivo.
- **Nessun deadlock:** il mutex è non ricorsivo; non chiamare metodi del driver dall'interno di un codeblock Transaction annidato.
- **Transazioni NON isolate tra thread.** Il mutex copre le operazioni singole; tra `BeginTrans()` e `Commit()` il lock viene rilasciato. Vedi [Transazioni § Isolamento](transazioni.md#isolamento-delle-transazioni).

### Modalità pool (`pool_size > 1`)

Ogni thread prenota la propria connessione all'entrata nell'handler. Non c'è mutex condiviso tra thread: ogni connessione opera sul proprio handle `sqlite3*`. SQLite coordina le scritture a livello di file tramite `busy_timeout_ms`.

- **Letture concorrenti:** N thread leggono in parallelo senza bloccarsi a vicenda.
- **Scritture serializzate a livello di file:** SQLite consente un solo writer; se due thread fanno `UPDATE` contemporaneamente, il secondo aspetta `busy_timeout_ms` prima di restituire `SQLITE_BUSY`.
- **Transazioni isolate:** ogni thread ha il proprio `BEGIN/COMMIT`; nessun interleaving è possibile.

!!! warning "Non usare Lock/Unlock direttamente"
    I metodi `oConn:Lock()` e `oConn:Unlock()` sono per uso interno del driver (modalità singleton). Chiamarli manualmente nel codice dell'applicazione può produrre deadlock. In modalità pool questi metodi sono no-op.

## Pattern frequenti

### Leggere un record per ID

```harbour
FUNCTION ProdottoGet()

   LOCAL nId   := Val( UParam( "id", "0" ) )
   LOCAL oConn, oStmt, hRow

   IF nId <= 0
      RETURN USendError( 400, "id non valido" )
   ENDIF

   oConn := WDO_Get( "APP" )
   IF oConn == NIL ; RETURN USendError( 503, "DB non disponibile" ) ; ENDIF

   oStmt := oConn:Prepare( "SELECT * FROM prodotti WHERE id = ?" )
   oStmt:BindParam( 1, nId, "i" )
   oStmt:Execute()
   hRow := oStmt:Fetch_Assoc()
   oStmt:Free()
   oConn:Close()

   IF hRow == NIL
      RETURN USendError( 404, "Prodotto non trovato" )
   ENDIF

RETURN USendJson( hRow )
```

### Paginazione

```harbour
FUNCTION ProdottiList()

   LOCAL nPage   := Max( 1, Val( UGet( "page",  "1"  ) ) )
   LOCAL nLimit  := Min( 100, Val( UGet( "limit", "20" ) ) )
   LOCAL nOffset := ( nPage - 1 ) * nLimit
   LOCAL oConn, oStmt, aRows

   oConn := WDO_Get( "APP" )
   IF oConn == NIL ; RETURN USendError( 503, "DB non disponibile" ) ; ENDIF

   oStmt := oConn:Prepare( ;
      "SELECT id, nome, prezzo FROM prodotti ORDER BY id LIMIT ? OFFSET ?" )
   oStmt:BindParam( 1, nLimit,  "i" )
   oStmt:BindParam( 2, nOffset, "i" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   oStmt:Free()
   oConn:Close()

RETURN USendJson( { "page" => nPage, "limit" => nLimit, "data" => aRows } )
```

### FINALLY — rilascio garantito

Se l'handler è complesso e può uscire per più strade:

```harbour
FUNCTION ComplexHandler()

   LOCAL oConn := WDO_Get( "APP" )
   LOCAL oStmt := NIL
   LOCAL oErr

   IF oConn == NIL ; RETURN USendError( 503, "DB non disponibile" ) ; ENDIF

   TRY
      oStmt := oConn:Prepare( "SELECT id FROM prodotti WHERE prezzo > ?" )
      oStmt:BindParam( 1, 10.0, "n" )
      oStmt:Execute()
      // ... processo ...
   CATCH oErr
      le( "ComplexHandler: " + oErr:description )
   FINALLY
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      oConn:Close()   // no-op nel singleton, ma manteniamo il pattern
   END

RETURN NIL
```

!!! info "Passo successivo"
    Per inserire o aggiornare con valori esterni in modo sicuro, usa i [Prepared Statement](prepared.md).
