# WDO — Web Database Objects

WDO es la capa de acceso a datos de HIX. Su nombre completo es **W**rapped **D**ata **O**bjects: envuelve los drivers de base de datos nativos (librerías C) y expone una API Harbour coherente, thread-safe y lista para producción.

## Por qué existe WDO

En un servidor web multihilo como HIX, cada petición HTTP corre en su propio hilo. Sin WDO, la forma "natural" de conectarse a la base de datos sería abrir y cerrar una conexión TCP por petición. Esto funciona en desarrollo, pero bajo carga real colapsa en minutos:

- Cada `connect()` deja el socket en estado **TIME_WAIT** durante 60–240 segundos.
- El sistema operativo tiene un rango limitado de puertos efímeros (~16.000 en Windows).
- Tras unos miles de peticiones rápidas, el SO ya no puede asignar más puertos → error 10048 / `WSAEADDRINUSE`.

WDO resuelve esto con un **pool de conexiones** (MySQL, PostgreSQL) o un **singleton con mutex** (SQLite3): abre N sockets al arrancar la app, los mantiene vivos y los presta a los hilos que los necesitan.

## Los tres motores

Los tres drivers comparten la misma superficie de API: `WDO_Get()`, `Query()`, `Exec()`, `Prepare()`, `BindParam()`, `Execute()`, `FetchAll()`, `BeginTrans()`, `Transaction()`, `Free()`. El código de un handler es prácticamente idéntico entre los tres.

| Driver | Modelo | Clave JSON | Estado |
|--------|--------|------------|--------|
| **[MySQL / MariaDB](mysql/index.md)** | Pool N conexiones | `"driver": "mysql"` o `"driver": "mariadb"` | Production-ready |
| **[PostgreSQL](pg/index.md)** | Pool N conexiones | `"driver": "pg"` | Production-ready |
| **[SQLite3 / SQLCipher](sqlite3/index.md)** | Singleton + mutex | `"driver": "sqlite3"` | Production-ready |

!!! tip "¿Qué driver elegir?"
    - **SQLite3** — Apps pequeñas/medianas, desarrollo local, datos embebidos. Sin servidor externo. Soporta cifrado completo del fichero con SQLCipher.
    - **PostgreSQL** — Alta concurrencia, features avanzadas (JSONB, GIS, full-text, pgcrypto), replicación.
    - **MySQL / MariaDB** — Ecosistema consolidado, hosting compartido, apps que ya usan MySQL.

## API común — referencia rápida

El patrón es idéntico entre los tres drivers:

```harbour
// Adquirir conexión (pool) o referencia (sqlite3)
oConn := WDO_Get( "APP" )
IF oConn == NIL ; RETURN USendError( 503, "DB unavailable" ) ; ENDIF

// Query directa
oStmt := oConn:Query( "SELECT id, nombre FROM productos WHERE activo = 1" )
aRows := oStmt:FetchAll( .T. )   // .T. = array de hashes
oStmt:Free()

// Prepared statement (protección SQL injection)
oStmt := oConn:Prepare( "SELECT id FROM usuarios WHERE email = ?" )
oStmt:BindParam( 1, cEmail )
oStmt:Execute()
hRow := oStmt:Fetch_Assoc()
oStmt:Free()

// DML
oConn:Exec( "DELETE FROM sesiones WHERE expira < NOW()" )

// Transacción
oConn:Transaction( {|o|
   o:Exec( "UPDATE cuentas SET saldo = saldo - 100 WHERE id = 1" ),
   o:Exec( "UPDATE cuentas SET saldo = saldo + 100 WHERE id = 2" )
} )

oConn:Close()   // devuelve al pool (MySQL/PG) o no-op (SQLite3)
```

## Configuración declarativa

Con `hixstyle.enabled=true`, los drivers se arrancan desde `hix.json` (o `www/config.json`) sin código en la app:

```json
{
  "databases": {
    "APP": {
      "driver":    "sqlite3",
      "file":      "www/data/app.db",
      "key_ref":   "sqlite3"
    },
    "PG": {
      "driver":    "pg",
      "host":      "127.0.0.1",
      "user":      "postgres",
      "db":        "myapp",
      "pool_size": 5
    },
    "MYSQL": {
      "driver": "mysql",
      "host":   "127.0.0.1",
      "user":   "myapp",
      "db":     "myapp"
    }
  }
}
```

Los tres pools/singletons pueden coexistir en el mismo proceso. `WDO_Get("APP")`, `WDO_Get("PG")` y `WDO_Get("MYSQL")` son independientes.

## Estructura de ficheros fuente

```
src/wdo/
  wdo_pool.prg              Pool genérico thread-safe
  wdo_config.prg            Bootstrap declarativo desde config.json
  wdo.prg                   Registro global y funciones WDO_Get / WDO_PoolStats
  mysql/
    wdo_mysql.prg           Driver MySQL/MariaDB (New/Open/Query/Close)
    wdo_mysql_pool.prg      Factory del pool MySQL
    wdo_mysql_stmt.prg      Prepared statements texto
    wdo_mysql_stmt_bin.prg  Prepared statements binario nativo (blobs)
  pg/
    wdo_pg.prg              Driver PostgreSQL vía libpq
    wdo_pg_pool.prg         Factory del pool PG
    wdo_pg_stmt.prg         Prepared statements (PQprepare / PQexecPrepared)
  sqlite3/
    wdo_sqlite3.prg         Driver SQLite3/SQLCipher (singleton)
    wdo_sqlite3_stmt.prg    Prepared statements (sqlite3_prepare_v2)
```

## Primeros pasos

Elige tu driver y sigue su documentación:

### MySQL / MariaDB

1. **[Concepto y Pool](mysql/index.md)** — entiende el modelo antes de escribir código.
2. **[Configuración](mysql/config.md)** — cómo declarar el pool en `config.json`.
3. **[Uso del pool](mysql/uso.md)** — cómo usar `WDO_Get` en tus handlers.
4. **[Prepared Statements](mysql/prepared.md)** — protección SQL injection y bulk insert.
5. **[Transacciones](mysql/transacciones.md)** — `BeginTrans`, `Commit`, `Rollback`.
6. **[Troubleshooting](mysql/troubleshooting.md)** — errores frecuentes y soluciones.

### PostgreSQL

1. **[Concepto y Pool](pg/index.md)** — pool vs `New()`, TCP preflight probe.
2. **[Configuración](pg/config.md)** — `sslmode`, `application_name`, `client_encoding`.
3. **[Uso del pool](pg/uso.md)** — API completa, NOTICEs, `RETURNING`.
4. **[Prepared Statements](pg/prepared.md)** — tres dialectos: `?`, `:name`, `$N`.
5. **[Transacciones](pg/transacciones.md)** — `BeginTrans`, `Transaction(bCode)`, savepoints.
6. **[Troubleshooting](pg/troubleshooting.md)** — `pg_hba.conf`, sslmode, NOTICEs.

### SQLite3 / SQLCipher

1. **[Concepto y Singleton](sqlite3/index.md)** — singleton vs pool, WAL mode, casos de uso.
2. **[Configuración](sqlite3/config.md)** — `key_ref`, WAL sidecars, rutas relativas.
3. **[Uso](sqlite3/uso.md)** — `IsTable()`, `Changes()`, `Count()=-1`.
4. **[Prepared Statements](sqlite3/prepared.md)** — 4 estilos de placeholder, `Reset()`.
5. **[Transacciones](sqlite3/transacciones.md)** — `SQLITE_BUSY`, bulk insert.
6. **[Cifrado SQLCipher](sqlite3/cifrado.md)** — AES-256, `Rekey()`, `GetCipherInfo()`.
7. **[Troubleshooting](sqlite3/troubleshooting.md)** — sidecars WAL, clave errónea, `Count()=-1`.
