# WDO PostgreSQL — Prepared Statements

Los prepared statements son la forma correcta de ejecutar queries con valores externos (de formularios, query strings, JSON, etc.). Protegen contra SQL injection y, en INSERTs masivos, reusan el plan de query server-side gracias a `PQprepare` / `PQexecPrepared` de libpq.

## ¿Prepare o Query?

```
¿Algún valor viene del exterior (form, URL, JSON, sesión)?
├── SÍ  → Prepare. Siempre. Sin excepciones.
└── NO  → ¿La query se repite muchas veces con distintos valores?
         ├── SÍ  → Prepare (evita re-parseo en el servidor)
         └── NO  → Query. SQL constante sin variables externas.
```

Regla sencilla: **si escribirías `Escape()`, escribe `Prepare()`**.

## Tres dialectos de placeholder

PostgreSQL usa nativamente el placeholder `$N` (posicional numerado). WDO_PG acepta además `?` y `:name` como azúcar sintáctico, reescribiéndolos internamente a `$1`, `$2`, etc. antes de llamar a `PQprepare`.

!!! info "SQL que ya usa $N se pasa literal"
    Si tu SQL ya contiene `$1`, `$2`, etc., el driver lo detecta y lo envía a `PQprepare` sin modificaciones. Los tres dialectos son **mutuamente excluyentes** en una misma query: no mezcles `?` con `$N` ni con `:name` en el mismo SQL.

### Dialecto 1 — `?` posicional

El N-ésimo `?` del SQL corresponde a `BindParam(N, ...)`:

```harbour
LOCAL oConn := WDO_Get( "PG" )
LOCAL oStmt, aRows

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

oStmt := oConn:Prepare( "SELECT id, name FROM users WHERE age > ? AND city = ?" )
oStmt:BindParam( 1, 18,       "i" )   // índice 1-based, tipo "i" = entero
oStmt:BindParam( 2, "Girona", "s" )   // tipo "s" = string
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()

oConn:Close()
USendJson( aRows )
```

### Dialecto 2 — `:name` nombrado

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id FROM users WHERE city = :city AND active = :active" )
oStmt:BindParam( ":city",   "Girona", "s" )
oStmt:BindParam( ":active", 1,        "i" )
oStmt:Execute()
```

El mismo `:name` puede aparecer varias veces en el SQL — basta un solo `BindParam`.

### Dialecto 3 — `$N` nativo PostgreSQL

```harbour
// SQL nativo PG — máxima claridad, sin reescritura cliente-lado
oStmt := oConn:Prepare( ;
   "INSERT INTO log(name, score) VALUES($1::text, $2::int)" )
oStmt:BindParam( 1, "alice", "s" )
oStmt:BindParam( 2, 42,      "i" )
oStmt:Execute()
oStmt:Free()
```

Los casts `::text`, `::int`, etc. en el SQL son opcionales pero ayudan al planificador de PostgreSQL.

### `BindParams` — atajo posicional

```harbour
oStmt := oConn:Prepare( "INSERT INTO events (name, ts) VALUES ($1, $2)" )
oStmt:BindParams( { cName, hb_DateTime() } )   // infiere tipos automáticamente
oStmt:Execute()
oStmt:Free()
```

## Tipos

| `cType` | Uso | Ejemplo |
|---------|-----|---------|
| `"i"` | Entero, booleano (true/false → 1/0) | `18`, `.T.` → `1` |
| `"n"` | Numérico decimal | `12.50` |
| `"s"` | String (default si se omite y el valor es C) | `"Girona"` |
| `"d"` | Date → `'YYYY-MM-DD'` | `Date()` |
| `"t"` | Timestamp → `'YYYY-MM-DD HH:MM:SS'` | `hb_DateTime()` |
| `"b"` | Blob → bytea hexadecimal `\x...` | datos binarios |
| _(omitido)_ | Inferido de `ValType` | recomendado solo para tipos claros |

!!! warning "Casos donde la inferencia puede fallar"
    - `CToD("")` tiene `ValType == "D"` pero debería ser `NULL` → pasa `NIL` explícito.
    - Strings vacíos → `''` (string vacío SQL), no `NULL`. Si quieres NULL, pasa `NIL`.
    - PostgreSQL es más estricto con los tipos que MySQL: un `"i"` pasado a una columna `text` puede fallar. Usa el cast SQL `$1::text` o el tipo `"s"` correcto.

## Nombre del prepared statement server-side

WDO_PG genera un nombre único por conexión con el formato `hix_pg_<tid>_<seq>` (p.ej. `hix_pg_15432_3`). Cada `Prepare()` incrementa el contador de secuencia. `Free()` emite `DEALLOCATE hix_pg_15432_3` al servidor para liberar el plan cacheado.

## Patrones habituales

### Paginación

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id, name FROM users ORDER BY id LIMIT $1 OFFSET $2" )
oStmt:BindParam( 1, nLimit,  "i" )
oStmt:BindParam( 2, nOffset, "i" )
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()
```

### LIKE con wildcards

Los `%` van en el **valor**, no en el SQL:

```harbour
oStmt := oConn:Prepare( "SELECT id FROM users WHERE name ILIKE $1" )
oStmt:BindParam( 1, "%" + cBusqueda + "%", "s" )
oStmt:Execute()
```

!!! info "ILIKE vs LIKE en PostgreSQL"
    `ILIKE` es el LIKE case-insensitive de PostgreSQL. No existe en MySQL. Úsalo cuando no quieras distinguir mayúsculas.

### IN-list dinámica

PostgreSQL no acepta `IN ($1)` con un array — genera N placeholders:

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

### INSERT masivo — reusar el mismo Prepare

Prepara una vez, ejecuta N veces — el plan de query queda cacheado en el servidor:

```harbour
oStmt := oConn:Prepare( "INSERT INTO log(name, score) VALUES($1::text, $2::int)" )

FOR i := 1 TO nRows
   oStmt:BindParam( 1, "user_" + StrZero( i, 3 ) )
   oStmt:BindParam( 2, 100 + i * 3, "i" )
   IF ! oStmt:Execute()
      le( "insert failed: " + oStmt:cError )
      EXIT
   ENDIF
NEXT

oStmt:Free()
```

### Input hostil — O'Connor

Los prepared statements manejan automáticamente las comillas simples sin escaping manual:

```harbour
oStmt := oConn:Prepare( "SELECT COUNT(*) AS n FROM users WHERE last_name = $1" )
oStmt:BindParam( 1, "O'Connor" )   // comillas simples, punto y coma, --: todo seguro
oStmt:Execute()
hRow := oStmt:Fetch_Assoc()
oStmt:Free()
? hRow[ "n" ]
```

### RETURNING — obtener ID tras INSERT

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

### UPDATE con campos opcionales

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

## Introspección tras Execute

```harbour
oStmt:FCount()          // número de columnas del resultset
oStmt:DbStruct()        // { { "id", "N", ... }, { "name", "C", ... }, ... }
oStmt:nAffectedRows     // filas afectadas (INSERT/UPDATE/DELETE)
oStmt:lError            // .T. si hay error
oStmt:cError            // descripción del error de libpq
```

## Integración con el pool — `Free()` obligatorio

!!! danger "Free() antes de Close()"
    Si no llamas `Free()`, el plan del prepared statement queda vivo en la conexión PostgreSQL (`SELECT * FROM pg_prepared_statements` lo verá acumularse). La próxima vez que el pool entregue esa conexión, el slot tiene planes huérfanos que consumen memoria en el servidor.

Patrón defensivo:

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
   le( "Handler error: " + oError:description )
FINALLY
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   oConn:Close()
END
```

## Antipatterns a evitar

| Antipattern | Problema | Corrección |
|-------------|----------|------------|
| `Prepare` dentro del loop | N Prepare + N DEALLOCATE en el servidor | Un Prepare fuera, N Execute dentro |
| `oStmt:Free()` olvidado | Planes acumulados en `pg_prepared_statements` | Siempre en FINALLY |
| `LIKE '%$1%'` | El `$1` está dentro de un literal string, no es placeholder | `LIKE $1` y wildcard en el valor |
| Mezclar `?` con `$N` en el mismo SQL | Reescritura interna indefinida | Un solo dialecto por query |
| `oStmt` en STATIC entre requests | Apunta a la conexión equivocada tras `Close()` | Scope de oStmt = scope del Get/Close |
| Reusar `oStmt` tras `oConn:Close()` | La conexión ya no pertenece a este thread | Preparar de nuevo tras adquirir slot |
