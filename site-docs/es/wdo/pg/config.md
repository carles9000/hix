# WDO PostgreSQL — Configuración

Hay tres formas de arrancar el pool PostgreSQL. La recomendada es la declarativa desde `config.json`.

## Método 1 — Declarativo (recomendado)

Añade la sección `databases` en `www/config.json`:

```json
{
  "databases": {
    "PG": {
      "driver":             "pg",
      "host":               "127.0.0.1",
      "port":               5432,
      "user":               "postgres",
      "pwd":                "secret",
      "db":                 "myapp",
      "pool_size":          5,
      "timeout_ms":         5000,
      "ping":               true,
      "read_timeout_s":     30,
      "connect_timeout_s":  10,
      "sslmode":            "disable",
      "application_name":   "hix-worker",
      "client_encoding":    "UTF8",
      "berror":             "WDO_DefaultErrorHandler"
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
    "PG":        { "driver": "pg", "host": "127.0.0.1", "db": "myapp", ... },
    "PG_REPORT": { "driver": "pg", "host": "10.0.0.42", "db": "reports", ... }
  }
}
```

En los handlers: `WDO_Get("PG")` y `WDO_Get("PG_REPORT")` coexisten en el mismo proceso.

### Campos disponibles

| Campo | Default | Descripción |
|-------|---------|-------------|
| `driver` | _(obligatorio)_ | `"pg"` (case-insensitive) |
| `host` | `"localhost"` | IP o hostname del servidor PostgreSQL |
| `user` | `""` | Usuario de autenticación |
| `pwd` | `""` | Contraseña |
| `db` | `""` | Base de datos por defecto |
| `port` | `5432` | Puerto TCP |
| `pool_size` | `5` | Número de conexiones al arrancar |
| `timeout_ms` | `5000` | Tiempo máximo de espera en `WDO_Get()` (0 = infinito) |
| `ping` | `true` | Ping antes de entregar cada slot; reconecta si está muerto |
| `read_timeout_s` | `30` | `statement_timeout` en segundos que se aplica por sesión (0 = sin timeout). Acota queries que se disparan; sin esto un slot puede quedar ocupado indefinidamente |
| `connect_timeout_s` | `10` | Timeout de la fase de conexión TCP + auth en segundos (0 = sin timeout). Evita que el arranque del pool quede colgado si el servidor no responde |
| `sslmode` | `"disable"` | `disable` / `allow` / `prefer` / `require` / `verify-ca` / `verify-full` |
| `application_name` | `"hix-worker"` | Visible en `pg_stat_activity` para identificar conexiones del pool |
| `client_encoding` | `"UTF8"` | Encoding de la sesión; debe coincidir con la BD o ser compatible |
| `debug` | `false` | Si cualquier pool tiene `"debug": true`, activa `HIX_Dbg()` globalmente: `dbg.log` captura trazas de Acquire/Release y toda llamada `HIX_Dbg()` en controllers. Solo para desarrollo |
| `berror` | — | Nombre de función Harbour para manejar errores del pool |
| `dll` | — | Ruta explícita a `libpq.dll` (override de la resolución automática) |

!!! warning "Relación con `exec_timeout_ms`"
    `read_timeout_s` debe ser **mayor** que la query legítima más lenta y acorde con el `exec_timeout_ms` del dispatcher (en `hix.json`). `read_timeout_s` se implementa como `SET statement_timeout = N * 1000` en cada sesión, así que afecta a todas las queries de esa conexión.

!!! tip "berror por defecto"
    `"berror": "WDO_DefaultErrorHandler"` ya viene incluido en la lib: loguea el error con `le()` y devuelve 500 si hay request activo. Suficiente para la mayoría de proyectos.

---

## Método 2 — Programático hash

```harbour
WDO_InitPoolPgEx( "PG", { ;
   "host"             => hb_GetEnv( "DB_HOST" ),     ;
   "user"             => hb_GetEnv( "DB_USER" ),     ;
   "pwd"              => hb_GetEnv( "DB_PWD"  ),     ;
   "db"               => "myapp",                    ;
   "pool_size"        => 10,                         ;
   "timeout_ms"       => 5000,                       ;
   "ping"             => .T.,                        ;
   "sslmode"          => "require",                  ;
   "application_name" => "hix-worker",               ;
   "client_encoding"  => "UTF8",                     ;
   "berror"           => "WDO_DefaultErrorHandler"   ;
} )
```

Útil cuando las credenciales se leen de variables de entorno o secrets.

## Método 3 — Posicional (legacy)

```harbour
WDO_InitPoolPg( "127.0.0.1", "postgres", "secret", "myapp", 5432, ;
                 5,     /* pool_size   */ ;
                 5000,  /* timeout_ms  */ ;
                 .T.    /* ping        */ )
```

Registra el pool bajo la clave fija `"PG"`. Compatible con código anterior a v2.4.4.

Al cerrar:

```harbour
WDO_EndPoolPg()
```

---

## DLLs — libpq y dependencias

El driver necesita cuatro DLLs de la distribución de PostgreSQL para Windows:

| DLL | Función |
|-----|---------|
| `libpq.dll` | Librería cliente PostgreSQL (protocolo wire) |
| `libcrypto-4-x64.dll` | Primitivas criptográficas (SSL, SCRAM-SHA-256) |
| `libssl-4-x64.dll` | TLS para conexiones `sslmode != disable` |
| `libcurl-x64.dll` | Usada por libpq para conexiones HTTP proxy |

Las cuatro DLLs listas para copiar están en `resources/wdo/pg/dll/` del proyecto HIX.

### Precedencia de resolución de libpq.dll

El driver busca la librería en este orden (mayor prioridad primero):

1. **Campo `"dll"` en `config.json`** — ruta absoluta explícita por pool.
2. **Variable de entorno `HIX_PG_DLL`** — ruta absoluta al fichero.
3. **Variable de entorno `WDO_PG_DLL`** — ruta absoluta al fichero.
4. **Directorio del ejecutable** (`hb_DirBase() + "dll\libpq.dll"`).
5. **PATH del sistema** — nombre canónico `libpq.dll` sin ruta.

El tag queda en `oConn:DllSource()` para diagnóstico.

### Diagnóstico

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "PG" )
   IF oConn == NIL ; RETURN USendError( 503, "pool unavailable" ) ; ENDIF
   USendJson( { ;
      "dll_source" => oConn:DllSource(), ;
      "dll_path"   => oConn:DllPath(),   ;
      "server"     => oConn:ServerInfo() ;
   } )
   oConn:Close()
} )
```

`DllSource()` retorna `"override"`, `"env"`, `"exedir"` o `"default"`.

### Si la DLL no se encuentra

El pool falla al arrancar y escribe en consola:

```
==> Error: Cannot load PostgreSQL DLL (libpq.dll)
```

Con `HIX_InitPoolsFromConfig(.T.)` el servidor aborta. Con `.F.` continúa, pero `WDO_Get("PG")` retornará NIL y los handlers responderán 503.

=== "Opción A — junto al ejecutable"
    Copia las cuatro DLLs de `resources/wdo/pg/dll/` al directorio del servidor (`hb_DirBase()`). La opción más simple y la que usa el campo `cDllSource = "exedir"`.

=== "Opción B — variable de entorno"
    ```bash
    set HIX_PG_DLL=C:\postgresql\bin\libpq.dll
    ```

=== "Opción C — campo dll en config.json"
    ```json
    {
      "databases": {
        "PG": {
          "driver": "pg",
          "dll": "C:/postgresql/bin/libpq.dll",
          "..."
        }
      }
    }
    ```

!!! warning "Las dependencias de libpq deben ser accesibles"
    `libpq.dll` carga dinámicamente `libcrypto-4-x64.dll`, `libssl-4-x64.dll` y `libcurl-x64.dll`. Si estas DLLs no están junto al ejecutable ni en `PATH`, obtendrás un error de Windows al hacer `hb_LibLoad("libpq.dll")` aunque el fichero exista. Copia las cuatro DLLs juntas.

---

## Handler de error personalizado

Si necesitas lógica custom (alertas Slack, métricas, etc.), define una función pública:

```harbour
FUNCTION WdoPgErrorHandler( oErr, oConn )

   HB_SYMBOL_UNUSED( oConn )

   le( "[WDO_PG] " + oErr:description + " @ " + oErr:operation )

   IF HIX_GetRequest() != NIL
      USendError( 500, "DB error: " + oErr:description )
   ENDIF

RETURN NIL
```

Y referénciala en el JSON:

```json
"berror": "WdoPgErrorHandler"
```

!!! warning "Requisitos de la función"
    Debe ser una `FUNCTION` pública (no `STATIC`, no `PROCEDURE`) y estar **estáticamente enlazada** al ejecutable. Si vive en un `.hrb` dinámico, `hb_isFunction` no la encontrará al arrancar.
