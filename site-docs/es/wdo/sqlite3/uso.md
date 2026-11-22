# WDO SQLite3 — Uso

Una vez configurada la BD en `config.json`, usarla en los handlers es directo. `WDO_Get("APP")` retorna una conexión lista para operar.

!!! info "Singleton vs pool — `pool_size`"
    El driver opera en dos modos según `pool_size` (ver [Configuración](config.md#pool_size)):

    - **`pool_size: 1`** (default) — **singleton**. `WDO_Get("APP")` devuelve siempre la misma instancia. Un solo handle contra el fichero; el driver serializa internamente con mutex.
    - **`pool_size: N > 1`** — **pool real**. N conexiones contra el mismo fichero; cada hilo reserva una durante el request. Necesario cuando dos handlers concurrentes pueden tener `Transaction()` solapadas (ver [Transacciones](transacciones.md)). Añadido en v2.5.3.

    En ambos modos la API del handler es idéntica: `WDO_Get` + `Close()`. El driver gestiona la reserva/liberación automáticamente.

## Plantilla básica de handler

```harbour
FUNCTION ProductosList()

   LOCAL oConn := WDO_Get( "APP" )   // referencia al singleton
   LOCAL oStmt, aRows, oErr

   IF oConn == NIL
      RETURN USendError( 503, "DB unavailable" )
   ENDIF

   TRY
      oStmt := oConn:Query( "SELECT id, nombre, precio FROM productos ORDER BY id" )
      aRows := oStmt:FetchAll( .T. )   // .T. = array de hashes
      oStmt:Free()
   CATCH oErr
      RETURN USendError( 500, oErr:description )
   END

   oConn:Close()   // buena práctica de portabilidad; es no-op en singleton

RETURN USendJson( aRows )
```

!!! info "Close() — comportamiento según modo"
    - **Singleton (`pool_size: 1`)**: `oConn:Close()` es no-op; la conexión vive de bootstrap a shutdown.
    - **Pool (`pool_size > 1`)**: `oConn:Close()` libera el slot al pool para que otro hilo pueda usarlo. En cualquier caso, el dispatcher HIX hace `WDO_ReleaseAllThread()` al final de cada request, así que **no es obligatorio** llamarlo explícitamente.

    Mantener el patrón `oConn:Close()` en los handlers facilita portar el código entre SQLite / PG / MySQL.

## API del driver

### Queries de lectura

```harbour
// Query simple → objeto resultset
oStmt := oConn:Query( "SELECT id, name FROM users WHERE active = 1" )

// Obtener todas las filas como array de hashes (campo => valor)
aRows := oStmt:FetchAll( .T. )

// O como array de arrays (acceso por índice, 1-based)
aRows := oStmt:FetchAll( .F. )

// Fila a fila — hash
DO WHILE ( hRow := oStmt:Fetch_Assoc() ) != NIL
   ? hRow[ "name" ]
ENDDO

// Fila a fila — array
DO WHILE ( aRow := oStmt:Fetch() ) != NIL
   ? aRow[ 1 ]   // primera columna
ENDDO

oStmt:Free()   // siempre liberar el statement
```

!!! warning "Count() retorna -1 en SQLite3"
    SQLite no conoce el número total de filas de un SELECT antes de haberlas recorrido todas. `oStmt:Count()` **siempre retorna -1**. Para obtener el total de filas, ejecuta primero `SELECT count(*) FROM ...`:

    ```harbour
    oStmt  := oConn:Query( "SELECT count(*) FROM productos" )
    aRow   := oStmt:Fetch()
    nTotal := Val( aRow[ 1 ] )
    oStmt:Free()
    ```

### Queries de escritura

```harbour
// Exec — para INSERT / UPDATE / DELETE sin resultset
oConn:Exec( "UPDATE users SET active = 0 WHERE id = " + hb_NToS( nId ) )

// Filas afectadas por el último statement ejecutado
? oConn:Changes()         // alias: oConn:Affected_Rows()

// Acumulado de toda la sesión de conexión
? oConn:Total_Changes()

// Último rowid generado (tras INSERT)
nNewId := oConn:Last_Insert_Id()
```

### Verificar existencia de tabla

```harbour
IF ! oConn:IsTable( "usuarios" )
   oConn:Exec( "CREATE TABLE usuarios (" + ;
               "  id      INTEGER PRIMARY KEY AUTOINCREMENT," + ;
               "  nombre  TEXT NOT NULL," + ;
               "  email   TEXT UNIQUE" + ;
               ")" )
ENDIF
```

`IsTable(cName)` hace `SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?` internamente.

### Escaping manual

!!! tip "Usa Prepared Statements"
    Para valores externos (form, JSON, query string), usa siempre [Prepared Statements](prepared.md). El escaping manual es solo para SQL construido íntegramente en código sin input externo.

```harbour
cSeguro := oConn:Escape( cValorExterno )   // duplica comillas simples
oConn:Exec( "INSERT INTO log (msg) VALUES ('" + cSeguro + "')" )
```

### Estructura de una tabla

```harbour
// Devuelve array de hashes { cName, cType, nSize, nDec }
aEstr := oConn:DbStruct( "productos" )
FOR EACH hCol IN aEstr
   ? hCol[ "cName" ], hCol[ "cType" ]
NEXT
```

### Información del servidor y conexión

```harbour
// Versión de la librería SQLite
? oConn:ServerInfo()       // "3.46.1"

// Codificación de texto
? oConn:GetEncoding()      // "UTF-8"

// Hash con parámetros de conexión actuales
hInfo := oConn:GetConnectionInfo()
// {
//   "file"          => "www/data/app.db",
//   "journal_mode"  => "WAL",
//   "synchronous"   => "NORMAL",
//   "foreign_keys"  => "1",
//   "busy_timeout"  => "5000",
//   "encrypted"     => .F.
// }

// Hash extendido con info de la DLL
hClient := oConn:GetClientInfo()
// {
//   "dll_path"   => "C:/miapp/dll/sqlcipher.dll",
//   "dll_source" => "exedir",
//   "encrypted"  => .F.
// }
```

## Concurrencia — mutex singleton vs pool real

### Modo singleton (`pool_size: 1`)

Todos los workers de HIX comparten la misma instancia `WDO_Sqlite3`. El driver mantiene un mutex interno (`oConn:hMutex`) que se adquiere en `Execute()` y se libera en el mismo `Execute()` o en `Fetch*()`. Esto significa:

- **Reads concurrentes:** múltiples workers pueden estar en la fase de `Fetch` simultáneamente (el mutex solo cubre la fase de `sqlite3_step`).
- **Writes serializados:** `Exec()` y el `Execute()` de un prepared DML adquieren el mutex exclusivo.
- **Sin interbloqueos:** el mutex es no recursivo; no llames a métodos del driver desde dentro de un codeblock Transaction anidado.
- **Transacciones NO aisladas entre hilos.** El mutex cubre operaciones sueltas; entre `BeginTrans()` y `Commit()` el lock se libera. Ver [Transacciones § Aislamiento](transacciones.md#aislamiento-de-transacciones).

### Modo pool (`pool_size > 1`)

Cada hilo reserva su propia conexión al entrar al handler. No hay mutex compartido entre hilos: cada conexión opera sobre su propio handle `sqlite3*`. SQLite coordina los writes a nivel de fichero vía `busy_timeout_ms`.

- **Reads concurrentes:** N hilos leen en paralelo sin bloquearse mutuamente.
- **Writes serializados a nivel de fichero:** SQLite permite un solo writer; si dos hilos hacen `UPDATE` simultáneo, el segundo espera `busy_timeout_ms` antes de retornar `SQLITE_BUSY`.
- **Transacciones aisladas:** cada hilo tiene su `BEGIN/COMMIT` local; no hay interleaving posible.

!!! warning "No uses Lock/Unlock directamente"
    Los métodos `oConn:Lock()` y `oConn:Unlock()` son de uso interno del driver (modo singleton). Invocarlos manualmente en código de aplicación puede producir interbloqueos. En modo pool estos métodos son no-op.

## Patrones frecuentes

### Leer un registro por ID

```harbour
FUNCTION ProductoGet()

   LOCAL nId   := Val( UParam( "id", "0" ) )
   LOCAL oConn, oStmt, hRow

   IF nId <= 0
      RETURN USendError( 400, "id invalido" )
   ENDIF

   oConn := WDO_Get( "APP" )
   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   oStmt := oConn:Prepare( "SELECT * FROM productos WHERE id = ?" )
   oStmt:BindParam( 1, nId, "i" )
   oStmt:Execute()
   hRow := oStmt:Fetch_Assoc()
   oStmt:Free()
   oConn:Close()

   IF hRow == NIL
      RETURN USendError( 404, "Producto no encontrado" )
   ENDIF

RETURN USendJson( hRow )
```

### Paginación

```harbour
FUNCTION ProductoList()

   LOCAL nPage   := Max( 1, Val( UGet( "page",  "1"  ) ) )
   LOCAL nLimit  := Min( 100, Val( UGet( "limit", "20" ) ) )
   LOCAL nOffset := ( nPage - 1 ) * nLimit
   LOCAL oConn, oStmt, aRows

   oConn := WDO_Get( "APP" )
   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   oStmt := oConn:Prepare( ;
      "SELECT id, nombre, precio FROM productos ORDER BY id LIMIT ? OFFSET ?" )
   oStmt:BindParam( 1, nLimit,  "i" )
   oStmt:BindParam( 2, nOffset, "i" )
   oStmt:Execute()
   aRows := oStmt:FetchAll( .T. )
   oStmt:Free()
   oConn:Close()

RETURN USendJson( { "page" => nPage, "limit" => nLimit, "data" => aRows } )
```

### FINALLY — liberación garantizada

Si el handler es complejo y puede salir por varios caminos:

```harbour
FUNCTION ComplexHandler()

   LOCAL oConn := WDO_Get( "APP" )
   LOCAL oStmt := NIL
   LOCAL oErr

   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   TRY
      oStmt := oConn:Prepare( "SELECT id FROM productos WHERE precio > ?" )
      oStmt:BindParam( 1, 10.0, "n" )
      oStmt:Execute()
      // ... proceso ...
   CATCH oErr
      le( "ComplexHandler: " + oErr:description )
   FINALLY
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      oConn:Close()   // no-op en singleton, pero mantenemos el patrón
   END

RETURN NIL
```

!!! info "Siguiente paso"
    Para insertar o actualizar con valores externos de forma segura, usa [Prepared Statements](prepared.md).
