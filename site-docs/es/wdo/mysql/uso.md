# WDO MySQL — Uso del pool

Una vez configurado el pool en `config.json`, usarlo en los handlers es muy sencillo.

## Plantilla básica de handler

```harbour
FUNCTION ProductosList()

   LOCAL oConn := WDO_Get( "mysql" )   // adquiere un slot del pool
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
oStmt := oConn:Query( "SELECT id, name FROM users WHERE active = 1" )

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

### Queries de escritura

```harbour
// Exec — para INSERT / UPDATE / DELETE sin resultset
oConn:Exec( "UPDATE users SET active = 0 WHERE id = " + hb_NToS( nId ) )

// Filas afectadas
? oConn:Affected_Rows()

// Último ID autogenerado (tras INSERT con AUTO_INCREMENT)
nNewId := oConn:Last_Insert_Id()
```

### Escaping manual

!!! tip "Usa Prepared Statements"
    Para valores externos (form, JSON, query string), usa siempre [Prepared Statements](prepared.md). El escaping manual es solo para SQL construido íntegramente en código sin input externo.

```harbour
// Para queries sin prepared statements con strings externos
cSeguro := oConn:Escape( cValorExterno )
oConn:Exec( "INSERT INTO log (msg) VALUES ('" + cSeguro + "')" )
```

### Información del servidor

```harbour
? oConn:mysql_get_server_info()    // "8.0.33"
? oConn:mysql_get_client_info()    // "6.1.6" (versión de la DLL cliente)
? oConn:VersionName()              // "MySQL 8.0.33"
? oConn:DllPath()                  // "c:/myapp/libmysql64.dll"
? oConn:DllSource()                // "exedir" / "override" / etc.
```

## Balanceo HIX ↔ Pool ↔ MySQL

Los tres niveles deben estar dimensionados en cascada:

```
MySQL max_connections  >  HIX pool_size  ≥  WDO pool_size
```

| Nivel | Parámetro | Recomendación |
|-------|-----------|---------------|
| HIX workers | `hix.ini → server.pool_size` | 2× el pool WDO |
| WDO pool | `config.json → pool_size` | `QPS_pico × latencia_media_seg` |
| MySQL | `my.cnf → max_connections` | WDO pool + 30 (margen admin) |

**Fórmula de Little:** si tu app hace 500 req/s y cada query tarda 10 ms de media, necesitas `500 × 0.010 = 5 conexiones` activas simultáneas. Un pool de 10 da un margen de 2×.

### Verificar en producción

```harbour
oSrv:AddRouteGet( "health.db", "/health/db", {||
   USendJson( WDO_PoolStats( "mysql" ) )
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
      RETURN USendError( 400, "id invalido" )
   ENDIF

   oConn := WDO_Get( "mysql" )
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

   LOCAL nPage  := Max( 1, Val( UGet( "page",  "1"  ) ) )
   LOCAL nLimit := Min( 100, Val( UGet( "limit", "20" ) ) )
   LOCAL nOffset := ( nPage - 1 ) * nLimit
   LOCAL oConn, oStmt, aRows

   oConn := WDO_Get( "mysql" )
   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   // Para valores externos, usa Prepare (ver sección Prepared Statements)
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

   LOCAL oConn := WDO_Get( "mysql" )
   LOCAL oStmt := NIL

   IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

   TRY
      oStmt := oConn:Prepare( "SELECT id FROM users WHERE age > ?" )
      oStmt:BindParam( 1, 18, "i" )
      oStmt:Execute()
      // ... proceso ...
   FINALLY
      IF oStmt != NIL ; oStmt:Free() ; ENDIF
      oConn:Close()   // siempre se ejecuta, éxito o error
   END

RETURN NIL
```

!!! info "Siguiente paso"
    Para insertar o actualizar con valores externos de forma segura, usa [Prepared Statements](prepared.md).
