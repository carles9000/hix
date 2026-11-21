# WDO SQLite3 — Prepared Statements

Los prepared statements son la forma correcta de ejecutar queries con valores externos. SQLite3 los implementa de forma nativa mediante `sqlite3_prepare_v2` + `sqlite3_step`, sin ninguna reescritura en el cliente.

## ¿Prepare o Query?

```
¿Algún valor viene del exterior (form, URL, JSON, sesión)?
├── SÍ  → Prepare. Siempre. Sin excepciones.
└── NO  → ¿La query se repite muchas veces con distintos valores?
         ├── SÍ  → Prepare (evita recompilar el plan en cada llamada)
         └── NO  → Query. SQL constante sin variables externas.
```

Regla sencilla: **si escribirías `Escape()`, escribe `Prepare()`**.

## Ejemplo básico

```harbour
LOCAL oConn := WDO_Get( "APP" )
LOCAL oStmt, aRows

IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

oStmt := oConn:Prepare( "SELECT id, name FROM users WHERE age > ? AND city = ?" )
oStmt:BindParam( 1, 18,       "i" )   // índice 1-based, tipo "i" = entero
oStmt:BindParam( 2, "Girona", "s" )   // tipo "s" = string
oStmt:Execute()
aRows := oStmt:FetchAll( .T. )
oStmt:Free()   // OBLIGATORIO — llama a sqlite3_finalize

oConn:Close()
USendJson( aRows )
```

## Placeholders — 4 estilos nativos

A diferencia de MySQL o PostgreSQL, SQLite acepta los cuatro estilos de placeholder de forma nativa. El driver WDO no hace ninguna reescritura.

### Posicional `?`

```harbour
oStmt := oConn:Prepare( "INSERT INTO log (level, msg) VALUES (?, ?)" )
oStmt:BindParam( 1, "error",   "s" )
oStmt:BindParam( 2, cMensaje,  "s" )
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

### Nombrado `@name`

```harbour
oStmt := oConn:Prepare( "UPDATE config SET value = @val WHERE key = @key" )
oStmt:BindParam( "@val", cValor, "s" )
oStmt:BindParam( "@key", cClave, "s" )
oStmt:Execute()
oStmt:Free()
```

### Nombrado `$name`

```harbour
oStmt := oConn:Prepare( "INSERT INTO events (name, ts) VALUES ($name, $ts)" )
oStmt:BindParam( "$name", cNombre,       "s" )
oStmt:BindParam( "$ts",   hb_DateTime(), "t" )
oStmt:Execute()
oStmt:Free()
```

!!! tip "El mismo nombre puede aparecer varias veces"
    Con placeholders nombrados, basta un solo `BindParam` para todos los lugares donde aparece:
    ```harbour
    oStmt := oConn:Prepare( "SELECT * FROM a WHERE x = :v UNION SELECT * FROM b WHERE x = :v" )
    oStmt:BindParam( ":v", cValor, "s" )
    ```

## Tipos de bind

| `cType` | Uso | Ejemplo |
|---------|-----|---------|
| `"i"` | Entero, booleano (0/1) | `18`, `.T.` → `1` |
| `"n"` | Numérico decimal | `12.50` |
| `"s"` / `"T"` | String / texto | `"Girona"` |
| `"d"` | Date → `'YYYY-MM-DD'` | `Date()` |
| `"t"` | Timestamp → `'YYYY-MM-DD HH:MM:SS'` | `hb_DateTime()` |
| `"b"` | Blob binario | datos binarios |
| `"N"` | NULL explícito | equivale a pasar `NIL` |
| _(omitido)_ | Inferido de `ValType()` | recomendado solo para tipos claros |

!!! warning "NIL = NULL"
    `BindParam(n, NIL)` llama a `sqlite3_bind_null`. Si quieres una cadena vacía SQL usa `BindParam(n, "", "s")`.

## BindParams — atajo posicional

```harbour
oStmt := oConn:Prepare( "INSERT INTO events (name, ts) VALUES (?, ?)" )
oStmt:BindParams( { cName, hb_DateTime() } )   // infiere tipos automáticamente
oStmt:Execute()
oStmt:Free()
```

## Reusar prepared statements con Reset()

En SQLite3, un prepared statement compilado puede resetearse y ejecutarse de nuevo sin volver a llamar `sqlite3_prepare_v2`. Esto es especialmente útil en INSERTs masivos:

```harbour
LOCAL oStmt := oConn:Prepare( "INSERT INTO log (msg, nivel) VALUES (?, ?)" )

FOR EACH cMsg IN aMensajes
   oStmt:BindParam( 1, cMsg,     "s" )
   oStmt:BindParam( 2, nNivel,   "i" )
   oStmt:Execute()
   oStmt:Reset()   // sqlite3_reset + sqlite3_clear_bindings — listo para el siguiente
NEXT

oStmt:Free()   // sqlite3_finalize al terminar
```

!!! info "Reset() vs Free()"
    `Reset()` limpia el estado interno del statement para reutilizarlo. `Free()` lo destruye definitivamente (`sqlite3_finalize`). Solo hay que llamar `Free()` una vez al terminar, aunque se haya llamado `Reset()` muchas veces.

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

SQLite no acepta `IN (?)` con un array — genera N placeholders:

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

### INSERT masivo — reusar con Reset()

```harbour
oStmt := oConn:Prepare( "INSERT INTO log (level, msg) VALUES (?, ?)" )

FOR EACH hRow IN aLogRows
   oStmt:BindParam( 1, hRow[ "level" ], "s" )
   oStmt:BindParam( 2, hRow[ "msg"   ], "s" )
   IF ! oStmt:Execute()
      le( "insert failed: " + oStmt:cError )
      EXIT
   ENDIF
   oStmt:Reset()
NEXT

oStmt:Free()
```

!!! tip "INSERT masivo + Transaction"
    Envolver un INSERT masivo en una transacción explícita multiplica la velocidad por un factor de 100× o más. SQLite hace un fsync por cada transacción implícita; con una transacción explícita solo hay un fsync al final. Ver [Transacciones](transacciones.md).

### UPDATE con campos opcionales

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

## Free() obligatorio

!!! danger "Free() antes de Close()"
    Si no llamas `Free()`, el statement queda en memoria hasta que el proceso termine. En handlers que se llaman miles de veces, esto acumula `sqlite3_stmt*` sin liberar. Siempre llama `Free()` en un bloque `FINALLY`:

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

## Introspección tras Execute

```harbour
oStmt:FCount()          // número de columnas del resultset (disponible tras Execute)
oStmt:Count()           // SIEMPRE -1 en SQLite3 (no se conoce el total antes de EOF)
oStmt:Row_Count()       // filas afectadas (INSERT/UPDATE/DELETE)
oStmt:Changes()         // alias de Row_Count()
oConn:Last_Insert_Id()  // último rowid autogenerado
oStmt:lError            // .T. si hay error
oStmt:cError            // descripción del error
```

## Antipatterns a evitar

| Antipattern | Problema | Corrección |
|-------------|----------|------------|
| `Prepare` dentro de un loop sin `Reset` | N `Prepare` + N `Free` sin reutilización | Un `Prepare` fuera, N `Execute + Reset` dentro |
| `oStmt:Free()` olvidado | Statements acumulados en memoria | Siempre en `FINALLY` |
| `LIKE '%?%'` | El `?` está dentro de literal, no es placeholder | `LIKE ?` y wildcards en el valor |
| `oStmt` en STATIC entre requests | SQLite serializa; el statement puede estar en uso por otro worker | `Prepare` dentro del scope de cada handler |
| Llamar `Reset()` después de `Free()` | `sqlite3_stmt*` ya no es válido → crash | `Free()` es siempre la última llamada |
