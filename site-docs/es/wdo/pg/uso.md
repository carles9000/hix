# WDO PostgreSQL — Uso del pool

Una vez configurado el pool en `config.json`, usarlo en los handlers es muy sencillo.

## Plantilla básica de handler

```harbour
FUNCTION ProductosList()

   LOCAL oConn := WDO_Get( "PG" )   // adquiere un slot del pool
   LOCAL oStmt, aRows

   IF oConn == NIL
      RETURN USendError( 503, "DB unavailable" )
   ENDIF

   TRY
      oStmt := oConn:Query( "SELECT id, nombre, precio FROM productos ORDER BY id" )
      aRows := oStmt:FetchAll( .T. )   // .T. = array de hashes
      oStmt:Free()
   CATCH oError
      oConn:Close()
      RETURN USendError( 500, oError:description )
   END

   oConn:Close()   // devuelve el slot al pool (NO cierra el socket)

RETURN USendJson( aRows )
```

!!! warning "Siempre llama a Close()"
    `oConn:Close()` devuelve el slot al pool para que otro hilo pueda usarlo. Si lo olvidas, el slot queda bloqueado hasta que el dispatcher de HIX lo reclame al final del request (con un WARN en el log).

## API del driver

### Queries de lectura

```harbour
// Query simple → objeto resultset
oStmt := oConn:Query( "SELECT id, name FROM users WHERE active = true" )

// Obtener todas las filas como array de hashes (campo => valor)
aRows := oStmt:FetchAll( .T. )

// O como array de arrays (más rápido, acceso por índice)
aRows := oStmt:FetchAll( .F. )

// Fila a fila
DO WHILE ( hRow := oStmt:Fetch_Assoc() ) != NIL
   ? hRow[ "name" ]
ENDDO

oStmt:Free()   // siempre liberar el resultset
```

!!! info "Query siempre retorna un objeto"
    A diferencia de algunos drivers, `Query()` en WDO_PG nunca retorna NIL. Revisa siempre `oStmt:lError` y `oStmt:cError` para detectar errores de SQL.

    ```harbour
    oStmt := oConn:Query( "SELECT ..." )
    IF oStmt:lError
       RETURN USendError( 500, oStmt:cError )
    ENDIF
    ```

### Queries de escritura

```harbour
// Exec — para INSERT / UPDATE / DELETE sin resultset
oConn:Exec( "UPDATE users SET active = false WHERE id = " + hb_NToS( nId ) )

// Filas afectadas
? oConn:Affected_Rows()

// Último ID generado — usa lastval() internamente
nNewId := oConn:Last_Insert_Id()
```

!!! tip "Prefiere RETURNING para obtener el ID"
    `Last_Insert_Id()` llama a `lastval()`, que retorna el último valor de la **última secuencia usada en la sesión**. Si la misma conexión hace varios INSERTs en tablas distintas, el resultado puede ser inesperado. La forma segura en PostgreSQL es usar `RETURNING`:

    ```harbour
    oStmt := oConn:Query( "INSERT INTO users (name, email) " + ;
                          "VALUES ('Alice', 'alice@example.com') RETURNING id" )
    hRow := oStmt:Fetch_Assoc()
    nNewId := Val( hRow[ "id" ] )
    oStmt:Free()
    ```

### Escaping manual

!!! tip "Usa Prepared Statements para input externo"
    Para valores externos (form, JSON, query string), usa siempre [Prepared Statements](prepared.md). El escaping manual es solo para SQL construido íntegramente en código sin input externo.

```harbour
// PostgreSQL usa standard_conforming_strings=on (desde PG 9.1):
// solo se dobla la comilla simple, NO se usa backslash de escape.
cSeguro := oConn:Escape( cValorExterno )
oConn:Exec( "INSERT INTO log (msg) VALUES ('" + cSeguro + "')" )
```

### NOTICEs de DDL

!!! warning "Silenciar NOTICEs de DDL"
    PostgreSQL emite NOTICE al hacer `DROP TABLE IF EXISTS` sobre tablas inexistentes. Estos mensajes no son errores pero ensucian el log. Para silenciarlos en la sesión actual:

    ```harbour
    oConn:Exec( "SET client_min_messages TO WARNING" )
    oConn:Exec( "DROP TABLE IF EXISTS temp_work" )
    oConn:Exec( "CREATE TABLE temp_work (...)" )
    ```

    Este `SET` solo afecta a la sesión actual, nunca al servidor global.

### Información del servidor

```harbour
? oConn:ServerInfo()           // "16.0.3"
? oConn:ClientInfo()           // versión de libpq ("16.0")
? oConn:GetEncoding()          // "UTF8"
? oConn:GetConnectionInfo()    // hash { "db", "user", "host", "port", "encoding" }
? oConn:DllPath()              // "c:/myapp/dll/libpq.dll"
? oConn:DllSource()            // "exedir" / "override" / "env" / "default"
```

### Estructura de tabla

```harbour
// DbStruct retorna array de arrays: { cName, cType, nSize, nDec }
// cType mapea tipos OID de PostgreSQL:
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

### Verificar si una tabla existe

```harbour
IF oConn:IsTable( "users" )
   l( "tabla users existe" )
ENDIF
```

## Balanceo HIX ↔ Pool ↔ PostgreSQL

Los tres niveles deben estar dimensionados en cascada:

```
PostgreSQL max_connections  >  HIX workers  ≥  WDO pool_size
```

| Nivel | Parámetro | Recomendación |
|-------|-----------|---------------|
| HIX workers | `hix.json → server.pool_size` | 2× el pool WDO |
| WDO pool | `config.json → pool_size` | `QPS_pico × latencia_media_seg` |
| PostgreSQL | `postgresql.conf → max_connections` | WDO pool + 20 (margen admin) |

**Fórmula de Little:** si tu app hace 500 req/s y cada query tarda 10 ms de media, necesitas `500 × 0.010 = 5 conexiones` activas simultáneas. Un pool de 10 da un margen de 2×.

!!! info "max_connections en PostgreSQL"
    El default de PostgreSQL es 100 conexiones. Cada conexión consume ~5–10 MB de RAM del servidor. No subas `max_connections` sin calcular la RAM disponible. Para escalar más allá de 200 conexiones considera PgBouncer como proxy de pooling.

### Verificar en producción

```harbour
oSrv:AddRouteGet( "health.db", "/health/db", {||
   USendJson( WDO_PoolStats( "PG" ) )
   // retorna: { "size" => 5, "busy" => 2, "free" => 3, "closed" => false }
} )
```

Si `free` se queda a 0 sostenidamente → sube `pool_size`. Si `busy` nunca pasa de 2 con pool de 10 → estás sobredimensionado.

## Patrones frecuentes

### Leer un registro por ID

```harbour
FUNCTION UserGet()

   LOCAL nId   := Val( UParam( "id", "0" ) )
   LOCAL oConn, oStmt, hRow

   IF nId <= 0
      RETURN USendError( 400, "id inválido" )
   ENDIF

   oConn := WDO_Get( "PG" )
   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   oStmt := oConn:Query( "SELECT * FROM users WHERE id = " + hb_NToS( nId ) )
   hRow  := oStmt:Fetch_Assoc()
   oStmt:Free()
   oConn:Close()

   IF hRow == NIL
      RETURN USendError( 404, "Usuario no encontrado" )
   ENDIF

RETURN USendJson( hRow )
```

### Paginación

```harbour
FUNCTION UserList()

   LOCAL nPage   := Max( 1, Val( UGet( "page",  "1"  ) ) )
   LOCAL nLimit  := Min( 100, Val( UGet( "limit", "20" ) ) )
   LOCAL nOffset := ( nPage - 1 ) * nLimit
   LOCAL oConn, oStmt, aRows

   oConn := WDO_Get( "PG" )
   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   // Para valores externos usa Prepare (ver sección Prepared Statements)
   oStmt := oConn:Query( "SELECT id, name FROM users ORDER BY id " + ;
                         "LIMIT "  + hb_NToS( nLimit  ) + ;
                         " OFFSET " + hb_NToS( nOffset ) )
   aRows := oStmt:FetchAll( .T. )
   oStmt:Free()
   oConn:Close()

RETURN USendJson( { "page" => nPage, "limit" => nLimit, "data" => aRows } )
```

### FINALLY — liberación garantizada

Si el handler es complejo y puede salir por varios caminos:

```harbour
FUNCTION ComplexHandler()

   LOCAL oConn := WDO_Get( "PG" )
   LOCAL oStmt := NIL
   LOCAL oError

   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   TRY
      oStmt := oConn:Prepare( "SELECT id FROM users WHERE age > $1" )
      oStmt:BindParam( 1, 18, "i" )
      oStmt:Execute()
      // ... proceso ...
   CATCH oError
      le( "ComplexHandler: " + oError:description )
   FINALLY
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      oConn:Close()   // siempre se ejecuta, éxito o error
   END

RETURN NIL
```

!!! info "Siguiente paso"
    Para insertar o actualizar con valores externos de forma segura, usa [Prepared Statements](prepared.md).
