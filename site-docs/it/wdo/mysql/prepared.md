# WDO MySQL - Prepared Statements

I prepared statement sono il modo corretto di eseguire query con valori esterni (da form, query string, JSON, ecc.). Proteggono dall'SQL injection e, negli INSERT massivi, riutilizzano il piano di query lato server.

## Prepare o Query?

```
Qualche valore proviene dall'esterno (form, URL, JSON, sessione)?
├── SÌ  → Prepare. Senza eccezioni.
└── NO  → La query si ripete molte volte con valori diversi?
         ├── SÌ  → Prepare (evita il re-parsing sul server)
         └── NO  → Query. SQL costante senza variabili esterne.
```

Regola semplice: **se scriveresti `Escape()`, scrivi `Prepare()`**.

## Esempio base

```harbour
LOCAL oConn := WDO_Get( "mysql" )
LOCAL oStmt, aRows

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

oStmt := oConn:Prepare( "SELECT id, name FROM users WHERE age > ? AND city = ?" )
oStmt:BindParam( 1, 18,       "i" )   // indice 1-based, tipo "i" = intero
oStmt:BindParam( 2, "Girona", "s" )   // tipo "s" = string
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()     // OBBLIGATORIO prima di Close

oConn:Close()
USendJson( aRows )
```

## Segnaposto

### Posizionale `?`

L'N-esimo `?` dell'SQL corrisponde a `BindParam(N, ...)`:

```harbour
oStmt := oConn:Prepare( "INSERT INTO log (level, msg) VALUES (?, ?)" )
oStmt:BindParam( 1, "error", "s" )
oStmt:BindParam( 2, cMessaggio, "s" )
oStmt:Execute()
oStmt:Free()
```

### Nominale `:name`

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id FROM users WHERE city = :city AND active = :active" )
oStmt:BindParam( ":city",   "Girona", "s" )
oStmt:BindParam( ":active", 1,        "i" )
oStmt:Execute()
```

Lo stesso `:name` può apparire più volte nell'SQL - basta un solo `BindParam`.

### `BindParams` - scorciatoia posizionale

```harbour
oStmt := oConn:Prepare( "INSERT INTO events (name, ts) VALUES (?, ?)" )
oStmt:BindParams( { cName, hb_DateTime() } )   // inferisce i tipi automaticamente
oStmt:Execute()
oStmt:Free()
```

## Tipi

| `cType` | Uso | Esempio |
|---------|-----|---------|
| `"i"` | Intero, booleano (0/1) | `18`, `.T.` → `1` |
| `"n"` | Numerico decimale | `12.50` |
| `"s"` | String | `"Girona"` |
| `"d"` | Date → `'YYYY-MM-DD'` | `Date()` |
| `"t"` | Timestamp → `'YYYY-MM-DD HH:MM:SS'` | `hb_DateTime()` |
| `"b"` | Blob binario → `x'HEX'` | dati binari |
| _(omesso)_ | Inferito da `ValType` | consigliato solo per tipi chiari |

!!! warning "Casi in cui l'inferenza può fallire"
    - `CToD("")` ha `ValType == "D"` ma dovrebbe essere `NULL` → passa `NIL` esplicito.
    - Stringhe vuote → `''` (stringa vuota SQL), non `NULL`. Se vuoi NULL, passa `NIL`.

## Pattern comuni

### Paginazione

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id, name FROM users ORDER BY id LIMIT ? OFFSET ?" )
oStmt:BindParam( 1, nLimit,  "i" )
oStmt:BindParam( 2, nOffset, "i" )
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()
```

### LIKE con wildcard

I `%` vanno nel **valore**, non nell'SQL:

```harbour
oStmt := oConn:Prepare( "SELECT id FROM users WHERE name LIKE ?" )
oStmt:BindParam( 1, "%" + cRicerca + "%", "s" )
oStmt:Execute()
```

### IN-list dinamica

MySQL non accetta `IN (?)` con un array - genera N segnaposto:

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

### INSERT massivo - riutilizzare lo stesso Prepare

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

### UPDATE con campi opzionali

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

## Integrazione con il pool - `Free()` obbligatorio

!!! danger "Free() prima di Close()"
    Se non chiami `Free()`, il prepared statement lato server rimane attivo nella connessione (`SHOW PREPARED STATEMENTS` lo vedrà accumularsi). La prossima volta che il pool consegna quella connessione, lo slot ha statement orfani.

Pattern difensivo:

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

## Introspezione dopo Execute

```harbour
oStmt:FCount()           // numero di colonne del resultset
oStmt:DbStruct()         // { { "id", "N", ... }, { "name", "C", ... }, ... }
oStmt:Row_Count()        // righe interessate (INSERT/UPDATE/DELETE) o restituite (SELECT)
oConn:Last_Insert_Id()   // ultimo AUTO_INCREMENT generato
oStmt:lError             // .T. se c'è un errore
oStmt:cError             // descrizione dell'errore
```

## Antipattern da evitare

| Antipattern | Problema | Correzione |
|-------------|----------|------------|
| `Prepare` dentro il loop | N Prepare + N DEALLOCATE | Un Prepare fuori, N Execute dentro |
| `oStmt:Free()` dimenticato | Statement accumulati nel server | - in FINALLY |
| `LIKE '%?%'` | Il `?` è dentro un literal, non è un segnaposto | `LIKE ?` e wildcard nel valore |
| `oStmt` in STATIC tra richieste | Punta alla connessione sbagliata | Prepare dentro lo scope Get/Close |
| Riutilizzare `oStmt` dopo `Close()` | `oConn` non appartiene più a questo thread | Scope di oStmt = scope del Get/Close |

## Alt A - protocollo binario nativo

Per BLOB grandi (> 1 MB), dati binari con byte NUL o INSERT massivo ad alta precisione decimale, esiste `WDO_MySqlStmtBin` (Alt A), che usa il protocollo binario nativo di MySQL (`mysql_stmt_*`). Consulta `docs/mysql/prepared_statements_bin.md` per maggiori dettagli.
