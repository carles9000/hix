# WDO PostgreSQL — Utilizzo del pool

Una volta configurato il pool in `config.json`, usarlo negli handler è molto semplice.

## Template base dell'handler

```harbour
FUNCTION ProdottiList()

   LOCAL oConn := WDO_Get( "PG" )   // acquisisce uno slot del pool
   LOCAL oStmt, aRows

   IF oConn == NIL
      RETURN USendError( 503, "DB non disponibile" )
   ENDIF

   TRY
      oStmt := oConn:Query( "SELECT id, nome, prezzo FROM prodotti ORDER BY id" )
      aRows := oStmt:FetchAll( .T. )   // .T. = array di hash
      oStmt:Free()
   CATCH oError
      oConn:Close()
      RETURN USendError( 500, oError:description )
   END

   oConn:Close()   // restituisce lo slot al pool (NON chiude il socket)

RETURN USendJson( aRows )
```

!!! warning "Chiama sempre Close()"
    `oConn:Close()` restituisce lo slot al pool affinché un altro thread possa usarlo. Se te ne dimentichi, lo slot rimane bloccato finché il dispatcher HIX non lo reclama alla fine della request (con un WARN nel log).

## API del driver

### Query di lettura

```harbour
// Query semplice → oggetto resultset
oStmt := oConn:Query( "SELECT id, name FROM users WHERE active = true" )

// Ottenere tutte le righe come array di hash (campo => valore)
aRows := oStmt:FetchAll( .T. )

// O come array di array (più veloce, accesso per indice)
aRows := oStmt:FetchAll( .F. )

// Riga per riga
DO WHILE ( hRow := oStmt:Fetch_Assoc() ) != NIL
   ? hRow[ "name" ]
ENDDO

oStmt:Free()   // liberare sempre il resultset
```

!!! info "Query restituisce sempre un oggetto"
    A differenza di alcuni driver, `Query()` in WDO_PG non restituisce mai NIL. Controlla sempre `oStmt:lError` e `oStmt:cError` per rilevare errori SQL.

    ```harbour
    oStmt := oConn:Query( "SELECT ..." )
    IF oStmt:lError
       RETURN USendError( 500, oStmt:cError )
    ENDIF
    ```

### Query di scrittura

```harbour
// Exec — per INSERT / UPDATE / DELETE senza resultset
oConn:Exec( "UPDATE users SET active = false WHERE id = " + hb_NToS( nId ) )

// Righe interessate
? oConn:Affected_Rows()

// Ultimo ID generato — usa lastval() internamente
nNewId := oConn:Last_Insert_Id()
```

!!! tip "Preferisci RETURNING per ottenere l'ID"
    `Last_Insert_Id()` chiama `lastval()`, che restituisce l'ultimo valore dell'**ultima sequenza usata nella sessione**. Se la stessa connessione fa diversi INSERT in tabelle diverse, il risultato può essere inatteso. Il modo sicuro in PostgreSQL è usare `RETURNING`:

    ```harbour
    oStmt := oConn:Query( "INSERT INTO users (name, email) " + ;
                          "VALUES ('Alice', 'alice@example.com') RETURNING id" )
    hRow := oStmt:Fetch_Assoc()
    nNewId := Val( hRow[ "id" ] )
    oStmt:Free()
    ```

### Escape manuale

!!! tip "Usa i Prepared Statement per l'input esterno"
    Per valori esterni (form, JSON, query string), usa sempre i [Prepared Statement](prepared.md). L'escape manuale è solo per SQL costruito interamente nel codice senza input esterno.

```harbour
// PostgreSQL usa standard_conforming_strings=on (da PG 9.1):
// si raddoppia solo la virgoletta singola, NON si usa il backslash di escape.
cSicuro := oConn:Escape( cValoreEsterno )
oConn:Exec( "INSERT INTO log (msg) VALUES ('" + cSicuro + "')" )
```

### NOTICE DDL

!!! warning "Silenziare i NOTICE DDL"
    PostgreSQL emette NOTICE quando si fa `DROP TABLE IF EXISTS` su tabelle inesistenti. Questi messaggi non sono errori ma sporcano il log. Per silenziarlı nella sessione corrente:

    ```harbour
    oConn:Exec( "SET client_min_messages TO WARNING" )
    oConn:Exec( "DROP TABLE IF EXISTS temp_work" )
    oConn:Exec( "CREATE TABLE temp_work (...)" )
    ```

    Questo `SET` influisce solo sulla sessione corrente, mai sul server globale.

### Informazioni del server

```harbour
? oConn:ServerInfo()           // "16.0.3"
? oConn:ClientInfo()           // versione di libpq ("16.0")
? oConn:GetEncoding()          // "UTF8"
? oConn:GetConnectionInfo()    // hash { "db", "user", "host", "port", "encoding" }
? oConn:DllPath()              // "c:/myapp/dll/libpq.dll"
? oConn:DllSource()            // "exedir" / "override" / "env" / "default"
```

### Struttura della tabella

```harbour
// DbStruct restituisce array di array: { cName, cType, nSize, nDec }
// cType mappa i tipi OID di PostgreSQL:
//   "C" → text, varchar, char, bpchar
//   "N" → int2, int4, int8, numeric, float4, float8
//   "L" → bool
//   "D" → date
//   "T" → timestamp, timestamptz
//   "M" → bytea

aStruct := oConn:DbStruct( "users" )
FOR EACH aFld IN aStruct
   ? aFld[1], aFld[2], aFld[3], aFld[4]
NEXT
```

### Verificare se una tabella esiste

```harbour
IF oConn:IsTable( "users" )
   l( "tabella users esistente" )
ENDIF
```

## Dimensionamento HIX ↔ Pool ↔ PostgreSQL

I tre livelli devono essere dimensionati in cascata:

```
PostgreSQL max_connections  >  HIX workers  ≥  WDO pool_size
```

| Livello | Parametro | Raccomandazione |
|---------|-----------|-----------------|
| HIX workers | `hix.json → server.pool_size` | 2× il pool WDO |
| WDO pool | `config.json → pool_size` | `QPS_picco × latenza_media_sec` |
| PostgreSQL | `postgresql.conf → max_connections` | WDO pool + 20 (margine admin) |

**Formula di Little:** se l'app fa 500 req/s e ogni query dura in media 10 ms, servono `500 × 0.010 = 5` connessioni attive simultanee. Un pool di 10 dà un margine 2×.

!!! info "max_connections in PostgreSQL"
    Il default di PostgreSQL è 100 connessioni. Ogni connessione consuma ~5–10 MB di RAM del server. Non aumentare `max_connections` senza calcolare la RAM disponibile. Per scalare oltre 200 connessioni considera PgBouncer come proxy di pooling.

### Monitoraggio in produzione

```harbour
oSrv:AddRouteGet( "health.db", "/health/db", {||
   USendJson( WDO_PoolStats( "PG" ) )
   // restituisce: { "size" => 5, "busy" => 2, "free" => 3, "closed" => false }
} )
```

Se `free` rimane a 0 in modo sostenuto → aumenta `pool_size`. Se `busy` non supera mai 2 con un pool di 10 → sei sovradimensionato.

## Pattern frequenti

### Leggere un record per ID

```harbour
FUNCTION UserGet()

   LOCAL nId   := Val( UParam( "id", "0" ) )
   LOCAL oConn, oStmt, hRow

   IF nId <= 0
      RETURN USendError( 400, "id non valido" )
   ENDIF

   oConn := WDO_Get( "PG" )
   IF oConn == NIL ; RETURN USendError( 503, "DB non disponibile" ) ; ENDIF

   oStmt := oConn:Query( "SELECT * FROM users WHERE id = " + hb_NToS( nId ) )
   hRow  := oStmt:Fetch_Assoc()
   oStmt:Free()
   oConn:Close()

   IF hRow == NIL
      RETURN USendError( 404, "Utente non trovato" )
   ENDIF

RETURN USendJson( hRow )
```

### Paginazione

```harbour
FUNCTION UserList()

   LOCAL nPage   := Max( 1, Val( UGet( "page",  "1"  ) ) )
   LOCAL nLimit  := Min( 100, Val( UGet( "limit", "20" ) ) )
   LOCAL nOffset := ( nPage - 1 ) * nLimit
   LOCAL oConn, oStmt, aRows

   oConn := WDO_Get( "PG" )
   IF oConn == NIL ; RETURN USendError( 503, "DB non disponibile" ) ; ENDIF

   // Per valori esterni usa Prepare (vedi sezione Prepared Statement)
   oStmt := oConn:Query( "SELECT id, name FROM users ORDER BY id " + ;
                         "LIMIT "  + hb_NToS( nLimit  ) + ;
                         " OFFSET " + hb_NToS( nOffset ) )
   aRows := oStmt:FetchAll( .T. )
   oStmt:Free()
   oConn:Close()

RETURN USendJson( { "page" => nPage, "limit" => nLimit, "data" => aRows } )
```

### FINALLY — rilascio garantito

Se l'handler è complesso e può uscire per più strade:

```harbour
FUNCTION ComplexHandler()

   LOCAL oConn := WDO_Get( "PG" )
   LOCAL oStmt := NIL
   LOCAL oError

   IF oConn == NIL ; RETURN USendError( 503, "DB non disponibile" ) ; ENDIF

   TRY
      oStmt := oConn:Prepare( "SELECT id FROM users WHERE age > $1" )
      oStmt:BindParam( 1, 18, "i" )
      oStmt:Execute()
      // ... processo ...
   CATCH oError
      le( "ComplexHandler: " + oError:description )
   FINALLY
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      oConn:Close()   // si esegue sempre, successo o errore
   END

RETURN NIL
```

!!! info "Passo successivo"
    Per inserire o aggiornare con valori esterni in modo sicuro, usa i [Prepared Statement](prepared.md).
