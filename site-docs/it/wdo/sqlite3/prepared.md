# WDO SQLite3 — Prepared Statement

I prepared statement sono il modo corretto per eseguire query con valori esterni. SQLite3 li implementa nativamente tramite `sqlite3_prepare_v2` + `sqlite3_step`, senza alcuna riscrittura lato client.

## Prepare o Query?

```
Qualche valore proviene dall'esterno (form, URL, JSON, sessione)?
├── SÌ  → Prepare. Sempre. Senza eccezioni.
└── NO  → La query si ripete molte volte con valori diversi?
          ├── SÌ  → Prepare (evita di ricompilare il piano ad ogni chiamata)
          └── NO  → Query. SQL costante senza variabili esterne.
```

Regola semplice: **se scriveresti `Escape()`, scrivi `Prepare()`**.

## Esempio base

```harbour
LOCAL oConn := WDO_Get( "APP" )
LOCAL oStmt, aRows

IF oConn == NIL ; RETURN USendError( 503, "DB non disponibile" ) ; ENDIF

oStmt := oConn:Prepare( "SELECT id, name FROM users WHERE age > ? AND city = ?" )
oStmt:BindParam( 1, 18,     "i" )   // indice 1-based, tipo "i" = intero
oStmt:BindParam( 2, "Roma", "s" )   // tipo "s" = stringa
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()   // OBBLIGATORIO — chiama sqlite3_finalize

oConn:Close()
USendJson( aRows )
```

## Placeholder — 4 stili nativi

A differenza di MySQL o PostgreSQL, SQLite accetta tutti e quattro gli stili di placeholder nativamente. Il driver WDO non fa nessuna riscrittura.

### Posizionale `?`

```harbour
oStmt := oConn:Prepare( "INSERT INTO log (level, msg) VALUES (?, ?)" )
oStmt:BindParam( 1, "error",    "s" )
oStmt:BindParam( 2, cMessaggio, "s" )
oStmt:Execute()
oStmt:Free()
```

### Nominato `:name`

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id FROM users WHERE city = :city AND active = :active" )
oStmt:BindParam( ":city",   "Roma", "s" )
oStmt:BindParam( ":active", 1,      "i" )
oStmt:Execute()
```

### Nominato `@name`

```harbour
oStmt := oConn:Prepare( "UPDATE config SET value = @val WHERE key = @key" )
oStmt:BindParam( "@val", cValore, "s" )
oStmt:BindParam( "@key", cChiave, "s" )
oStmt:Execute()
oStmt:Free()
```

### Nominato `$name`

```harbour
oStmt := oConn:Prepare( "INSERT INTO events (name, ts) VALUES ($name, $ts)" )
oStmt:BindParam( "$name", cNome,         "s" )
oStmt:BindParam( "$ts",   hb_DateTime(), "t" )
oStmt:Execute()
oStmt:Free()
```

!!! tip "Lo stesso nome può apparire più volte"
    Con placeholder nominati, basta un solo `BindParam` per tutte le occorrenze:
    ```harbour
    oStmt := oConn:Prepare( "SELECT * FROM a WHERE x = :v UNION SELECT * FROM b WHERE x = :v" )
    oStmt:BindParam( ":v", cValore, "s" )
    ```

## Tipi di bind

| `cType` | Uso | Esempio |
|---------|-----|---------|
| `"i"` | Intero, booleano (0/1) | `18`, `.T.` → `1` |
| `"n"` | Numerico decimale | `12.50` |
| `"s"` / `"T"` | Stringa / testo | `"Roma"` |
| `"d"` | Date → `'YYYY-MM-DD'` | `Date()` |
| `"t"` | Timestamp → `'YYYY-MM-DD HH:MM:SS'` | `hb_DateTime()` |
| `"b"` | Blob binario | dati binari |
| `"N"` | NULL esplicito | equivale a passare `NIL` |
| _(omesso)_ | Inferito da `ValType()` | consigliato solo per tipi chiari |

!!! warning "NIL = NULL"
    `BindParam(n, NIL)` chiama `sqlite3_bind_null`. Se vuoi una stringa SQL vuota usa `BindParam(n, "", "s")`.

## BindParams — scorciatoia posizionale

```harbour
oStmt := oConn:Prepare( "INSERT INTO events (name, ts) VALUES (?, ?)" )
oStmt:BindParams( { cName, hb_DateTime() } )   // inferisce i tipi automaticamente
oStmt:Execute()
oStmt:Free()
```

## Riutilizzare i prepared statement con Reset()

In SQLite3, un prepared statement compilato può essere resettato ed eseguito di nuovo senza chiamare di nuovo `sqlite3_prepare_v2`. Questo è particolarmente utile negli INSERT massivi:

```harbour
LOCAL oStmt := oConn:Prepare( "INSERT INTO log (msg, livello) VALUES (?, ?)" )

FOR EACH cMsg IN aMessaggi
   oStmt:BindParam( 1, cMsg,    "s" )
   oStmt:BindParam( 2, nLivello,"i" )
   oStmt:Execute()
   oStmt:Reset()   // sqlite3_reset + sqlite3_clear_bindings — pronto per il prossimo
NEXT

oStmt:Free()   // sqlite3_finalize al termine
```

!!! info "Reset() vs Free()"
    `Reset()` pulisce lo stato interno dello statement per riutilizzarlo. `Free()` lo distrugge definitivamente (`sqlite3_finalize`). `Free()` va chiamato una sola volta al termine, anche se `Reset()` è stato chiamato molte volte.

## Pattern abituali

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

SQLite non accetta `IN (?)` con un array — genera N placeholder:

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
aRows := oStmt:FetchAll( .T. )
oStmt:Free()
```

### INSERT massivo — riutilizzo con Reset()

```harbour
oStmt := oConn:Prepare( "INSERT INTO log (livello, msg) VALUES (?, ?)" )

FOR EACH hRow IN aLogRows
   oStmt:BindParam( 1, hRow[ "livello" ], "s" )
   oStmt:BindParam( 2, hRow[ "msg"     ], "s" )
   IF ! oStmt:Execute()
      le( "insert fallito: " + oStmt:cError )
      EXIT
   ENDIF
   oStmt:Reset()
NEXT

oStmt:Free()
```

!!! tip "INSERT massivo + Transazione"
    Avvolgere un INSERT massivo in una transazione esplicita moltiplica la velocità di un fattore 100× o più. SQLite fa un fsync per ogni transazione implicita; con una transazione esplicita c'è solo un fsync alla fine. Vedi [Transazioni](transazioni.md).

### UPDATE con campi opzionali

```harbour
LOCAL aSet := {}, aVal := {}, i

IF ! Empty( cName )
   AAdd( aSet, "name = ?" ) ; AAdd( aVal, { cName, "s" } )
ENDIF
IF nAge > 0
   AAdd( aSet, "age = ?" )  ; AAdd( aVal, { nAge,  "i" } )
ENDIF

IF Empty( aSet ) ; RETURN ; ENDIF

oStmt := oConn:Prepare( "UPDATE users SET " + ;
         hb_ArrayToList( aSet, ", " ) + " WHERE id = ?" )

FOR i := 1 TO Len( aVal )
   oStmt:BindParam( i, aVal[ i ][ 1 ], aVal[ i ][ 2 ] )
NEXT
oStmt:BindParam( Len( aVal ) + 1, nId, "i" )
oStmt:Execute()
oStmt:Free()
```

## Free() obbligatorio

!!! danger "Free() prima di Close()"
    Se non chiami `Free()`, lo statement rimane in memoria fino alla fine del processo. Negli handler chiamati migliaia di volte, questo accumula `sqlite3_stmt*` senza liberarli. Chiama sempre `Free()` in un blocco `FINALLY`:

```harbour
LOCAL oConn, oStmt

oConn := WDO_Get( "APP" )
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
oStmt:FCount()          // numero di colonne del resultset (disponibile dopo Execute)
oStmt:Count()           // SEMPRE -1 in SQLite3 (totale non noto prima di EOF)
oStmt:Row_Count()       // righe interessate (INSERT/UPDATE/DELETE)
oStmt:Changes()         // alias di Row_Count()
oConn:Last_Insert_Id()  // ultimo rowid autogenerato
oStmt:lError            // .T. se c'è un errore
oStmt:cError            // descrizione dell'errore
```

## Antipattern da evitare

| Antipattern | Problema | Correzione |
|-------------|----------|------------|
| `Prepare` dentro un loop senza `Reset` | N `Prepare` + N `Free` senza riutilizzo | Un `Prepare` fuori, N `Execute + Reset` dentro |
| `oStmt:Free()` dimenticato | Statement accumulati in memoria | Sempre in `FINALLY` |
| `LIKE '%?%'` | `?` è dentro un letterale, non è un placeholder | `LIKE ?` e wildcard nel valore |
| `oStmt` in STATIC tra request | SQLite serializza; lo statement può essere in uso da un altro worker | `Prepare` nello scope di ogni handler |
| Chiamare `Reset()` dopo `Free()` | `sqlite3_stmt*` non è più valido → crash | `Free()` è sempre l'ultima chiamata |
