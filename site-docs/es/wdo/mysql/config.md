# WDO MySQL — Configuración

Hay tres formas de arrancar el pool MySQL. La recomendada es la declarativa desde `config.json`.

## Método 1 — Declarativo (recomendado)

Añade la sección `databases` en `www/config.json`:

```json
{
  "databases": {
    "mysql": {
      "driver":     "mysql",
      "host":       "127.0.0.1",
      "user":       "harbour",
      "pwd":        "hb1234",
      "db":         "employees",
      "port":       3306,
      "pool_size":  5,
      "timeout_ms": 5000,
      "ping":       true,
      "berror":     "WDO_DefaultErrorHandler"
    }
  }
}
```

En `app.prg` con **hixstyle** no necesitas nada más: `Start()` llama automáticamente a `HIX_InitPoolsFromConfig(.T.)` y `HIX_EndPoolsFromConfig()`.

En apps sin hixstyle:

```harbour
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()
   HIX_ConfigAppLoad( "www/config.json" )
   HIX_InitPoolsFromConfig()   // aborta si algún pool falla (default)
   oSrv:Start()
   IF oSrv:hThread != NIL
      hb_threadJoin( oSrv:hThread )
   ENDIF
   HIX_EndPoolsFromConfig()
RETURN
```

### Múltiples pools

Puedes declarar varias bases de datos con claves distintas:

```json
{
  "databases": {
    "mysql":     { "driver": "mysql",   "host": "127.0.0.1", ... },
    "analytics": { "driver": "mariadb", "host": "10.0.0.42", ... }
  }
}
```

En los handlers: `WDO_Get("mysql")` y `WDO_Get("analytics")` coexisten en el mismo proceso.

### Campos disponibles

| Campo | Default | Descripción |
|-------|---------|-------------|
| `driver` | _(obligatorio)_ | `"mysql"` o `"mariadb"` (case-insensitive) |
| `host` | `"localhost"` | IP o hostname del servidor |
| `user` | `""` | Usuario de autenticación |
| `pwd` | `""` | Contraseña |
| `db` | `""` | Base de datos por defecto |
| `port` | `3306` | Puerto TCP |
| `pool_size` | `5` | Número de conexiones al arrancar |
| `timeout_ms` | `5000` | Tiempo máximo de espera en `WDO_Get()` (0 = infinito) |
| `ping` | `true` | Ping antes de entregar cada slot; reconecta si está muerto |
| `berror` | — | Nombre de función Harbour para manejar errores del pool |
| `dll` | — | Ruta explícita a la DLL (override de la resolución automática) |

!!! tip "berror por defecto"
    `"berror": "WDO_DefaultErrorHandler"` ya viene incluido en la lib: loguea el error con `le()` y devuelve 500 si hay request activo. Suficiente para la mayoría de proyectos.

## Método 2 — Programático hash

```harbour
WDO_InitPoolMySqlEx( "mysql", { ;
   "host"       => hb_GetEnv( "DB_HOST" ), ;
   "user"       => hb_GetEnv( "DB_USER" ), ;
   "pwd"        => hb_GetEnv( "DB_PWD" ),  ;
   "db"         => "employees",            ;
   "pool_size"  => 10,                     ;
   "timeout_ms" => 5000,                   ;
   "ping"       => .T.,                    ;
   "berror"     => "WDO_DefaultErrorHandler" ;
} )
```

Útil cuando las credenciales se leen de variables de entorno o secrets.

## Método 3 — Posicional (legacy)

```harbour
WDO_InitPoolMySql( "localhost", "harbour", "hb1234", "employees", 3306, ;
                    5,     /* pool_size   */ ;
                    5000,  /* timeout_ms  */ ;
                    .T.,   /* ping        */ ;
                    {|oErr, oConn| WdoErrorHandler( oErr, oConn ) } )
```

Registra el pool bajo la clave fija `"MYSQL"`. Compatible con código anterior a v2.3.01.

---

## DLLs — driver MySQL vs MariaDB

El driver necesita la librería cliente del protocolo MySQL:

| `"driver"` | DLL Windows | SO Linux |
|-----------|-------------|----------|
| `"mysql"` | `libmysql64.dll` | `libmysqlclient.so` |
| `"mariadb"` | `libmariadb64.dll` | `libmariadb.so` |

### Precedencia de resolución de la DLL

El driver busca la librería en este orden (mayor prioridad primero):

1. **Campo `"dll"` en `config.json`** — ruta absoluta explícita por pool.
2. **Variable de entorno `WDO_LIB_MYSQL`** — ruta absoluta al fichero.
3. **Variable de entorno `WDO_PATH_MYSQL`** — directorio; el driver añade el nombre canónico.
4. **Directorio del ejecutable** (`hb_DirBase()`).
5. **PATH del sistema** — nombre canónico sin ruta.

### Diagnóstico

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "mysql" )
   IF oConn == NIL ; RETURN USendError( 503, "pool unavailable" ) ; ENDIF
   USendJson( { ;
      "dll_source" => oConn:DllSource(), ;
      "dll_path"   => oConn:DllPath(),   ;
      "server"     => oConn:mysql_get_server_info() ;
   } )
   oConn:Close()
} )
```

`DllSource()` retorna `"override"`, `"WDO_LIB_MYSQL"`, `"WDO_PATH_MYSQL"`, `"exedir"` o `"default"`.

### Si la DLL no se encuentra

El pool falla al arrancar y escribe en consola:

```
==> Error: Cannot load MySQL DLL
```

Con `HIX_InitPoolsFromConfig(.T.)` el servidor aborta. Con `.F.` continúa, pero `WDO_Get("mysql")` retornará NIL y los handlers responderán 503.

---

## Handler de error personalizado

Si necesitas lógica custom (alertas Slack, métricas, etc.), define una función pública:

```harbour
FUNCTION WdoErrorHandler( oErr, oConn )

   HB_SYMBOL_UNUSED( oConn )

   le( "[WDO] " + oErr:description + " @ " + oErr:operation )

   IF HIX_GetRequest() != NIL
      USendError( 500, "DB error: " + oErr:description )
   ENDIF

RETURN NIL
```

Y referénciala en el JSON:

```json
"berror": "WdoErrorHandler"
```

!!! warning "Requisitos de la función"
    Debe ser una `FUNCTION` pública (no `STATIC`, no `PROCEDURE`) y estar **estáticamente enlazada** al ejecutable. Si vive en un `.hrb` dinámico, `hb_isFunction` no la encontrará al arrancar.
