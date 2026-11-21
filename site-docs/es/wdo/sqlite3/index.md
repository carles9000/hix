# WDO SQLite3 — Concepto y Singleton

El driver `WDO_Sqlite3` envuelve `sqlcipher.dll` mediante `hb_DynCall`. A diferencia de los drivers MySQL o PostgreSQL, **no hay pool** — el driver gestiona una única conexión compartida entre todos los workers del servidor HIX.

## Por qué singleton y no pool

SQLite es una librería embebida en el proceso, no un servidor TCP externo. No hay handshake de red, no hay sockets efímeros que se agoten. El fichero `.db` vive en disco y el driver lo abre **una sola vez** al arrancar.

Múltiples conexiones simultáneas al mismo fichero SQLite son posibles en modo WAL, pero WDO usa una conexión compartida con un mutex interno para serializar las operaciones. Esto elimina la complejidad del pool y hace que el comportamiento sea predecible:

```
Arranque:
  └─ HIX_InitPoolsFromConfig()
       └─ WDO_InitSqlite3Ex("APP", hParams)
            └─ sqlite3_open() — una sola vez

Por cada request:
  └─ WDO_Get("APP")   →  misma instancia siempre (no checkout de slot)
       └─ Query / Prepare / Exec / ...
  └─ oConn:Close()    →  no-op como singleton (retorna al stack de Harbour)

Shutdown:
  └─ HIX_EndPoolsFromConfig()
       └─ WDO_EndSqlite3("APP")
            └─ sqlite3_close() — una sola vez
```

!!! info "oConn:Close() es buena práctica aunque no haga nada"
    Llamar `Close()` mantiene la portabilidad del código entre drivers. Si en el futuro migras a MySQL o PG, el mismo patrón `Get/Close` funciona sin cambios. El dispatcher de HIX también llama `WDO_ReleaseAllThread()` al final de cada request; en SQLite3 no tiene efecto dañino.

## WAL mode — el default

El driver activa `PRAGMA journal_mode=WAL` al arrancar (configurable). En modo WAL:

- Múltiples lectores pueden leer simultáneamente mientras un escritor escribe.
- Los cambios no confirmados se acumulan en el sidecar `-wal` y se integran en el `.db` en el checkpoint.
- El rendimiento de escritura es notablemente mejor que el modo DELETE (el default histórico de SQLite).

!!! warning "Sidecars en disco"
    WAL crea dos ficheros adicionales junto al `.db`: `-wal` y `-shm`. Al hacer backup, copia los tres. Al borrar en tests, borra también los sidecars con `FErase(cDb + "-wal")` y `FErase(cDb + "-shm")`.

## Rendimiento comparado

| Patrón | Coste por request | Escala bajo carga |
|--------|-------------------|-------------------|
| `WDO_MySql():New()` por request | ~0.77 ms (87% setup TCP) | Colapsa con error 10048 |
| `WDO_Get("mysql")` (pool 5 slots) | ~0.06 ms | Estable indefinidamente |
| `WDO_Get("APP")` (SQLite3 singleton) | < 0.01 ms (sin TCP) | Serializa con mutex; writers en cola |

El singleton SQLite3 es extremadamente rápido para lecturas concurrentes. El cuello de botella es la serialización de escrituras: solo un writer puede ejecutar a la vez.

## Cuándo usar SQLite3

- **Apps pequeñas y medianas** con tráfico moderado (< 50 req/s con escrituras frecuentes).
- **Desarrollo local** sin servidor de base de datos externo.
- **Datos embebidos** — configuración, sesiones, caché local, colas internas.
- **Apps portátiles** — un solo fichero `.db` lo contiene todo, incluso cifrado con SQLCipher.
- **Tests de integración** — base de datos en memoria con `"file": ":memory:"`.

## Cuándo usar PostgreSQL o MySQL en su lugar

- **Alta concurrencia de escritura** — más de 100 peticiones por segundo con escrituras simultáneas.
- **Datos compartidos** entre múltiples instancias del servidor (SQLite3 no es un servidor de red).
- **Replicación o sharding** — SQLite no tiene estos conceptos.
- **Features avanzadas** — JSONB con índices GIN (PG), procedimientos almacenados complejos, GIS, etc.
- **Tamaño de datos > 1 GB** con escrituras frecuentes — el mutex de escritura se convierte en cuello de botella.

## Ciclo de vida completo

```
Arranque
  └─ HIX_InitPoolsFromConfig()
       └─ sqlite3_open() + PRAGMAs de configuración

  Por cada request:
  └─ WDO_Get("APP")   →  misma instancia (el mutex interno gestiona concurrencia)
       └─ Query / Prepare / Exec / ...
  └─ oConn:Close()    →  no-op en singleton; el mutex ya se liberó en Free()/Execute()

Shutdown
  └─ HIX_EndPoolsFromConfig()
       └─ WDO_EndSqlite3("APP")  →  sqlite3_close() + HB_LibFree()
```

!!! info "Siguiente paso"
    Ahora que entiendes el modelo, [configura el singleton en `config.json`](config.md).
