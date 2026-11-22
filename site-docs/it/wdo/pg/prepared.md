# WDO PostgreSQL — Prepared Statement

I prepared statement sono il modo corretto per eseguire query con valori esterni (da form, query string, JSON, ecc.). Proteggono dall'SQL injection e, negli INSERT massivi, riutilizzano il piano di query lato server grazie a `PQprepare` / `PQexecPrepared` di libpq.

## Prepare o Query?

```
Qualche valore proviene dall'esterno (form, URL, JSON, sessione)?
├── SÌ  → Prepare. Sempre. Senza eccezioni.
└── NO  → La query si ripete molte volte con valori diversi?
          ├── SÌ  → Prepare (evita il re-parsing sul server)
          └── NO  → Query. SQL costante senza variabili esterne.
```

Regola semplice: **se scriveresti `Escape()`, scrivi `Prepare()`**.

## Tre dialetti di placeholder

PostgreSQL usa nativamente il placeholder `$N` (posizionale numerato). WDO_PG accetta anche `?` e `:name` come zucchero sintattico, riscrivendoli internamente in `$1`, `$2`, ecc. prima di chiamare `PQprepare`.

!!! info "SQL che già usa $N viene passato letteralmente"
    Se il tuo SQL contiene già `$1`, `$2`, ecc., il driver lo rileva e lo invia a `PQprepare` senza modifiche. I tre dialetti sono **mutuamente esclusivi** nella stessa query: non mescolare `?` con `$N` né con `:name` nello stesso SQL.

### Dialetto 1 — posizionale `?`

L'N-esimo `?` nell'SQL corrisponde a `BindParam(N, ...)`:

```harbour
LOCAL oConn := WDO_Get( "PG" )
LOCAL oStmt, aRows

IF oConn == NIL ; RETURN USendError( 503, "DB non disponibile" ) ; ENDIF

oStmt := oConn:Prepare( "SELECT id, name FROM users WHERE age > ? AND city = ?" )
oStmt:BindParam( 1, 18,      "i" )   // indice 1-based, tipo "i" = intero
oStmt:BindParam( 2, "Roma",  "s" )   // tipo "s" = stringa
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()

oConn:Close()
USendJson( aRows )
```

### Dialetto 2 — nominato `:name`

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id FROM users WHERE city = :city AND active = :active" )
oStmt:BindParam( ":city",   "Roma", "s" )
oStmt:BindParam( ":active", 1,      "i" )
oStmt:Execute()
```

Lo stesso `:name` può apparire più volte nell'SQL — basta un solo `BindParam`.

### Dialetto 3 — nativo PostgreSQL `$N`

```harbour
// SQL nativo PG — massima chiarezza, nessuna riscrittura lato client
oStmt := oConn:Prepare( ;
   "INSERT INTO log(name, score) VALUES($1::text, $2::int)" )
oStmt:BindParam( 1, "alice", "s" )
oStmt:BindParam( 2, 42,      "i" )
oStmt:Execute()
oStmt:Free()
```

I cast `::text`, `::int`, ecc. nell'SQL sono opzionali ma aiutano il query planner di PostgreSQL.

### `BindParams` — scorciatoia posizionale

```harbour
oStmt := oConn:Prepare( "INSERT INTO events (name, ts) VALUES ($1, $2)" )
oStmt:BindParams( { cName, hb_DateTime() } )   // inferisce i tipi automaticamente
oStmt:Execute()
oStmt:Free()
```

## Tipi

| `cType` | Uso | Esempio |
|---------|-----|---------|
| `"i"` | Intero, booleano (true/false → 1/0) | `18`, `.T.` → `1` |
| `"n"` | Numerico decimale | `12.50` |
| `"s"` | Stringa (default se omesso e il valore è C) | `"Roma"` |
| `"d"` | Date → `'YYYY-MM-DD'` | `Date()` |
| `"t"` | Timestamp → `'YYYY-MM-DD HH:MM:SS'` | `hb_DateTime()` |
| `"b"` | Blob → bytea esadecimale `\x...` | dati binari |
| _(omesso)_ | Inferito da `ValType` | consigliato solo per tipi chiari |

!!! warning "Casi in cui l'inferenza può fallire"
    - `CToD("")` ha `ValType == "D"` ma dovrebbe essere `NULL` → passa `NIL` esplicito.
    - Stringhe vuote → `''` (stringa SQL vuota), non `NULL`. Se vuoi NULL, passa `NIL`.
    - PostgreSQL è più severo con i tipi rispetto a MySQL: un `"i"` passato a una colonna `text` può fallire. Usa il cast SQL `$1::text` o il tipo `"s"` corretto.

## Nome del prepared statement lato server

WDO_PG genera un nome univoco per connessione con il formato `hix_pg_<tid>_<seq>` (es. `hix_pg_15432_3`). Ogni `Prepare()` incrementa il contatore di sequenza. `Free()` emette `DEALLOCATE hix_pg_15432_3` al server per liberare il piano in cache.

## Pattern abituali

### Paginazione

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id, name FROM users ORDER BY id LIMIT $1 OFFSET $2" )
oStmt:BindParam( 1, nLimit,  "i" )
oStmt:BindParam( 2, nOffset, "i" )
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()
```

### LIKE con wildcard

I `%` vanno nel **valore**, non nell'SQL:

```harbour
oStmt := oConn:Prepare( "SELECT id FROM users WHERE name ILIKE $1" )
oStmt:BindParam( 1, "%" + cRicerca + "%", "s" )
oStmt:Execute()
```

!!! info "ILIKE vs LIKE in PostgreSQL"
    `ILIKE` è il LIKE case-insensitive di PostgreSQL. Non esiste in MySQL. Usalo quando non vuoi distinguere maiuscole e minuscole.

### IN-list dinamica

PostgreSQL non accetta `IN ($1)` con un array — genera N placeholder:

```harbour
LOCAL aIds := { 1, 5, 42 }
LOCAL cSql, i

cSql := "SELECT id, name FROM users WHERE id IN (" + ;
        Left( Replicate( "?,", Len( aIds ) ), Len( aIds ) * 2 - 1 ) + ")"
oStmt := oConn:Prepare( cSql )

FOR i := 1 TO Len( aIds )
   oStmt:BindParam( i, aIds[ i ], "i" )
NEXT
oStmt:Execute()
```

### INSERT massivo — riutilizzare lo stesso Prepare

Prepara una volta, esegui N volte — il piano di query rimane in cache sul server:

```harbour
oStmt := oConn:Prepare( "INSERT INTO log(name, score) VALUES($1::text, $2::int)" )

FOR i := 1 TO nRows
   oStmt:BindParam( 1, "user_" + StrZero( i, 3 ) )
   oStmt:BindParam( 2, 100 + i * 3, "i" )
   IF ! oStmt:Execute()
      le( "insert fallito: " + oStmt:cError )
      EXIT
   ENDIF
NEXT

oStmt:Free()
```

### Input ostile — O'Connor

I prepared statement gestiscono automaticamente le virgolette singole senza escape manuale:

```harbour
oStmt := oConn:Prepare( "SELECT COUNT(*) AS n FROM users WHERE last_name = $1" )
oStmt:BindParam( 1, "O'Connor" )   // virgolette singole, punto e virgola, --: tutto sicuro
oStmt:Execute()
hRow := oStmt:Fetch_Assoc()
oStmt:Free()
? hRow[ "n" ]
```

### RETURNING — ottenere l'ID dopo INSERT

```harbour
oStmt := oConn:Prepare( ;
   "INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, created_at" )
oStmt:BindParam( 1, cName,  "s" )
oStmt:BindParam( 2, cEmail, "s" )
oStmt:Execute()
hRow := oStmt:Fetch_Assoc()
oStmt:Free()

nNewId   := Val( hRow[ "id" ] )
cCreated := hRow[ "created_at" ]
```

### UPDATE con campi opzionali

```harbour
LOCAL aSet := {}, aVal := {}

IF ! Empty( cName )
   AAdd( aSet, "name = $" + hb_NToS( Len( aSet ) + 1 ) )
   AAdd( aVal, { cName, "s" } )
ENDIF
IF nAge > 0
   AAdd( aSet, "age = $" + hb_NToS( Len( aSet ) + 1 ) )
   AAdd( aVal, { nAge, "i" } )
ENDIF

IF Empty( aSet ) ; RETURN ; ENDIF

AAdd( aVal, { nId, "i" } )
oStmt := oConn:Prepare( "UPDATE users SET " + ;
         hb_ArrayToList( aSet, ", " ) + ;
         " WHERE id = $" + hb_NToS( Len( aVal ) ) )

LOCAL i
FOR i := 1 TO Len( aVal )
   oStmt:BindParam( i, aVal[ i ][ 1 ], aVal[ i ][ 2 ] )
NEXT
oStmt:Execute()
oStmt:Free()
```

## Introspezione dopo Execute

```harbour
oStmt:FCount()          // numero di colonne del resultset
oStmt:DbStruct()        // { { "id", "N", ... }, { "name", "C", ... }, ... }
oStmt:nAffectedRows     // righe interessate (INSERT/UPDATE/DELETE)
oStmt:lError            // .T. se c'è un errore
oStmt:cError            // descrizione dell'errore libpq
```

## Integrazione con il pool — `Free()` obbligatorio

!!! danger "Free() prima di Close()"
    Se non chiami `Free()`, il piano del prepared statement rimane attivo sulla connessione PostgreSQL (`SELECT * FROM pg_prepared_statements` lo vedrà accumularsi). La prossima volta che il pool consegna quella connessione, lo slot ha piani orfani che consumano memoria sul server.

Pattern difensivo:

```harbour
LOCAL oConn  := WDO_Get( "PG" )
LOCAL oStmt  := NIL
LOCAL oError

TRY
   oStmt := oConn:Prepare( "SELECT id FROM users WHERE age > $1" )
   oStmt:BindParam( 1, 18, "i" )
   oStmt:Execute()
   // ...
CATCH oError
   le( "Errore handler: " + oError:description )
FINALLY
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   oConn:Close()
END
```

## Antipattern da evitare

| Antipattern | Problema | Correzione |
|-------------|----------|------------|
| `Prepare` dentro il loop | N Prepare + N DEALLOCATE sul server | Un Prepare fuori, N Execute dentro |
| `oStmt:Free()` dimenticato | Piani accumulati in `pg_prepared_statements` | Sempre in FINALLY |
| `LIKE '%$1%'` | `$1` è dentro un letterale stringa, non è un placeholder | `LIKE $1` e wildcard nel valore |
| Mescolare `?` con `$N` nello stesso SQL | Riscrittura interna indefinita | Un solo dialetto per query |
| `oStmt` in STATIC tra request | Punta alla connessione sbagliata dopo `Close()` | Scope di oStmt = scope di Get/Close |
| Riutilizzare `oStmt` dopo `oConn:Close()` | La connessione non appartiene più a questo thread | Preparare di nuovo dopo aver acquisito lo slot |
