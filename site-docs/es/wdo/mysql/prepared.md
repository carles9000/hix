# WDO MySQL — Prepared Statements

Los prepared statements son la forma correcta de ejecutar queries con valores externos (de formularios, query strings, JSON, etc.). Protegen contra SQL injection y, en INSERTs masivos, reusan el plan de query server-side.

## ¿Prepare o Query?

```
¿Algún valor viene del exterior (form, URL, JSON, sesión)?
├── SÍ  → Prepare. Siempre. Sin excepciones.
└── NO  → ¿La query se repite muchas veces con distintos valores?
         ├── SÍ  → Prepare (evita re-parseo en el servidor)
         └── NO  → Query. SQL constante sin variables externas.
```

Regla sencilla: **si escribirías `Escape()`, escribe `Prepare()`**.

## Ejemplo básico

```harbour
LOCAL oConn := WDO_Get( "mysql" )
LOCAL oStmt, aRows

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

oStmt := oConn:Prepare( "SELECT id, name FROM users WHERE age > ? AND city = ?" )
oStmt:BindParam( 1, 18,       "i" )   // índice 1-based, tipo "i" = entero
oStmt:BindParam( 2, "Girona", "s" )   // tipo "s" = string
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()     // OBLIGATORIO antes de Close

oConn:Close()
USendJson( aRows )
```

## Placeholders

### Posicional `?`

El N-ésimo `?` del SQL corresponde a `BindParam(N, ...)`:

```harbour
oStmt := oConn:Prepare( "INSERT INTO log (level, msg) VALUES (?, ?)" )
oStmt:BindParam( 1, "error", "s" )
oStmt:BindParam( 2, cMensaje, "s" )
oStmt:Execute()
oStmt:Free()
```

### Nombrado `:name`

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id FROM users WHERE city = :city AND active = :active" )
oStmt:BindParam( ":city",   "Girona", "s" )
oStmt:BindParam( ":active", 1,        "i" )
oStmt:Execute()
```

El mismo `:name` puede aparecer varias veces en el SQL — basta un solo `BindParam`.

### `BindParams` — atajo posicional

```harbour
oStmt := oConn:Prepare( "INSERT INTO events (name, ts) VALUES (?, ?)" )
oStmt:BindParams( { cName, hb_DateTime() } )   // infiere tipos automáticamente
oStmt:Execute()
oStmt:Free()
```

## Tipos

| `cType` | Uso | Ejemplo |
|---------|-----|---------|
| `"i"` | Entero, booleano (0/1) | `18`, `.T.` → `1` |
| `"n"` | Numérico decimal | `12.50` |
| `"s"` | String | `"Girona"` |
| `"d"` | Date → `'YYYY-MM-DD'` | `Date()` |
| `"t"` | Timestamp → `'YYYY-MM-DD HH:MM:SS'` | `hb_DateTime()` |
| `"b"` | Blob binario → `x'HEX'` | datos binarios |
| _(omitido)_ | Inferido de `ValType` | recomendado solo para tipos claros |

!!! warning "Casos donde la inferencia puede fallar"
    - `CToD("")` tiene `ValType == "D"` pero debería ser `NULL` → pasa `NIL` explícito.
    - Strings vacíos → `''` (string vacío SQL), no `NULL`. Si quieres NULL, pasa `NIL`.

## Patrones habituales

### Paginación

```harbour
oStmt := oConn:Prepare( ;
   "SELECT id, name FROM users ORDER BY id LIMIT ? OFFSET ?" )
oStmt:BindParam( 1, nLimit,  "i" )
oStmt:BindParam( 2, nOffset, "i" )
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()
```

### LIKE con wildcards

Los `%` van en el **valor**, no en el SQL:

```harbour
oStmt := oConn:Prepare( "SELECT id FROM users WHERE name LIKE ?" )
oStmt:BindParam( 1, "%" + cBusqueda + "%", "s" )
oStmt:Execute()
```

### IN-list dinámica

MySQL no acepta `IN (?)` con un array — genera N placeholders:

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

### INSERT masivo — reusar el mismo Prepare

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

### UPDATE con campos opcionales

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

## Integración con el pool — `Free()` obligatorio

!!! danger "Free() antes de Close()"
    Si no llamas `Free()`, el statement server-side queda vivo en la conexión (`SHOW PREPARED STATEMENTS` lo verá acumularse). La próxima vez que el pool entregue esa conexión, el slot tiene statements huérfanos.

Patrón defensivo:

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

## Introspección tras Execute

```harbour
oStmt:FCount()           // número de columnas del resultset
oStmt:DbStruct()         // { { "id", "N", ... }, { "name", "C", ... }, ... }
oStmt:Row_Count()        // filas afectadas (INSERT/UPDATE/DELETE) o devueltas (SELECT)
oConn:Last_Insert_Id()   // último AUTO_INCREMENT generado
oStmt:lError             // .T. si hay error
oStmt:cError             // descripción del error
```

## Antipatterns a evitar

| Antipattern | Problema | Corrección |
|-------------|----------|------------|
| `Prepare` dentro del loop | N Prepare + N DEALLOCATE | Un Prepare fuera, N Execute dentro |
| `oStmt:Free()` olvidado | Statements acumulados en el server | Siempre en FINALLY |
| `LIKE '%?%'` | El `?` está dentro de literal, no es placeholder | `LIKE ?` y wildcard en el valor |
| `oStmt` en STATIC entre requests | Apunta a la conexión equivocada | Prepare dentro del scope Get/Close |
| Reusar `oStmt` tras `Close()` | `oConn` ya no pertenece a este thread | Scope de oStmt = scope del Get/Close |

## Alt A — protocolo binario nativo

Para BLOBs grandes (> 1 MB), datos binarios con NUL bytes o INSERT masivo de alta precisión decimal, existe `WDO_MySqlStmtBin` (Alt A), que usa el protocolo binario nativo de MySQL (`mysql_stmt_*`). Consulta `docs/mysql/prepared_statements_bin.md` para más detalles.
