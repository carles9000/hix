# WDO MySQL - Utilizzo del pool

Una volta configurato il pool in `config.json`, usarlo negli handler è molto semplice.

## Template base di handler

```harbour
FUNCTION ProductosList()

   LOCAL oConn := WDO_Get( "mysql" )   // acquisisce uno slot dal pool
   LOCAL oStmt, aRows

   IF oConn == NIL
      RETURN USendError( 503, "DB unavailable" )
   ENDIF

   TRY
      oStmt := oConn:Query( "SELECT id, nombre, precio FROM productos ORDER BY id" )
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
    `oConn:Close()` restituisce lo slot al pool affinché un altro thread possa usarlo. Se lo dimentichi, lo slot rimane bloccato finché il dispatcher di HIX non lo recupera al termine della richiesta (con un WARN nel log).

## API del driver

### Query di lettura

```harbour
// Query semplice → oggetto resultset
oStmt := oConn:Query( "SELECT id, name FROM users WHERE active = 1" )

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

### Query di scrittura

```harbour
// Exec - per INSERT / UPDATE / DELETE senza resultset
oConn:Exec( "UPDATE users SET active = 0 WHERE id = " + hb_NToS( nId ) )

// Righe interessate
? oConn:Affected_Rows()

// Ultimo ID autogenerato (dopo INSERT con AUTO_INCREMENT)
nNewId := oConn:Last_Insert_Id()
```

### Escaping manuale

!!! tip "Usa i Prepared Statements"
    Per valori esterni (form, JSON, query string), usa sempre i [Prepared Statements](prepared.md). L'escaping manuale è solo per SQL costruito interamente in codice senza input esterno.

```harbour
// Per query senza prepared statements con stringhe esterne
cSeguro := oConn:Escape( cValoreEsterno )
oConn:Exec( "INSERT INTO log (msg) VALUES ('" + cSeguro + "')" )
```

### Informazioni sul server

```harbour
? oConn:mysql_get_server_info()    // "8.0.33"
? oConn:mysql_get_client_info()    // "6.1.6" (versione della DLL client)
? oConn:VersionName()              // "MySQL 8.0.33"
? oConn:DllPath()                  // "c:/myapp/libmysql64.dll"
? oConn:DllSource()                // "exedir" / "override" / ecc.
```

## Bilanciamento HIX ↔ Pool ↔ MySQL

I tre livelli devono essere dimensionati a cascata:

```
MySQL max_connections  >  HIX pool_size  ≥  WDO pool_size
```

| Livello | Parametro | Raccomandazione |
|---------|-----------|-----------------|
| HIX workers | `hix.ini → server.pool_size` | 2× il pool WDO |
| WDO pool | `config.json → pool_size` | `QPS_picco × latenza_media_sec` |
| MySQL | `my.cnf → max_connections` | WDO pool + 30 (margine admin) |

**Formula di Little:** se la tua app fa 500 req/s e ogni query impiega in media 10 ms, hai bisogno di `500 × 0.010 = 5 connessioni` attive simultanee. Un pool di 10 dà un margine di 2×.

### Verificare in produzione

```harbour
oSrv:AddRouteGet( "health.db", "/health/db", {||
   USendJson( WDO_PoolStats( "mysql" ) )
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

   oConn := WDO_Get( "mysql" )
   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

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

   LOCAL nPage  := Max( 1, Val( UGet( "page",  "1"  ) ) )
   LOCAL nLimit := Min( 100, Val( UGet( "limit", "20" ) ) )
   LOCAL nOffset := ( nPage - 1 ) * nLimit
   LOCAL oConn, oStmt, aRows

   oConn := WDO_Get( "mysql" )
   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   // Per valori esterni, usa Prepare (vedi sezione Prepared Statements)
   oStmt := oConn:Query( "SELECT id, name FROM users ORDER BY id " + ;
                         "LIMIT "  + hb_NToS( nLimit  ) + ;
                         " OFFSET " + hb_NToS( nOffset ) )
   aRows := oStmt:FetchAll( .T. )
   oStmt:Free()
   oConn:Close()

RETURN USendJson( { "page" => nPage, "limit" => nLimit, "data" => aRows } )
```

### FINALLY - liberazione garantita

Se l'handler è complesso e può uscire per più percorsi:

```harbour
FUNCTION ComplexHandler()

   LOCAL oConn := WDO_Get( "mysql" )
   LOCAL oStmt := NIL

   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   TRY
      oStmt := oConn:Prepare( "SELECT id FROM users WHERE age > ?" )
      oStmt:BindParam( 1, 18, "i" )
      oStmt:Execute()
      // ... elaborazione ...
   FINALLY
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      oConn:Close()   // viene sempre eseguito, successo o errore
   END

RETURN NIL
```
