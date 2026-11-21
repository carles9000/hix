# WDO PostgreSQL — Concepto y Pool

El driver `WDO_PG` envuelve la librería cliente oficial de PostgreSQL (`libpq`) mediante `hb_DynCall`. Sobre él, `WDO_Pool` implementa el pool de conexiones thread-safe que usan los handlers HTTP.

## El problema que resuelve el pool

Imagina 100 peticiones concurrentes, cada una abriendo y cerrando su propia conexión PostgreSQL:

```
Request 1  →  New() → TCP connect + auth (~1.2 ms) → Query → End() → socket en TIME_WAIT
Request 2  →  New() → TCP connect + auth (~1.2 ms) → Query → End() → socket en TIME_WAIT
...×100
```

Tras unos miles de peticiones rápidas en Windows, el sistema se queda sin puertos efímeros y aparece el error **10048** (`WSAEADDRINUSE`). La segunda corrida del bench sin pool colapsa con exactamente este error.

Con pool, los sockets se abren **una sola vez** al arrancar y se reusan indefinidamente:

```
Arranque:  WDO_Init → abre 5 conexiones TCP (una vez, coste amortizado)

Request 1  →  WDO_Get("PG") → slot #1 prestado (~0.005 ms) → Query → Close() → slot #1 devuelto
Request 2  →  WDO_Get("PG") → slot #2 prestado (~0.005 ms) → Query → Close() → slot #2 devuelto
...×100  →  se turnan sobre los 5 slots, sin abrir/cerrar sockets
```

## Rendimiento comparado

| Patrón | Coste por request | Escala bajo carga |
|--------|-------------------|-------------------|
| `WDO_PG():New()` por request | ~1.2 ms (90% es setup) | Colapsa con 10048 |
| `WDO_Get("PG")` / `Close()` (pool) | ~0.06 ms (84% es la query) | Estable indefinidamente |

**El pool es ~20× más rápido** en overhead, y el único que escala en producción.

## Cómo funciona el pool

### Al arrancar la app

`WDO_InitPoolPg` (o el arranque declarativo desde `config.json`) crea `N` instancias de `WDO_PG`, las conecta y las guarda en el array interno del pool marcadas como libres.

### Por cada request

1. `WDO_Get("PG")` — toma el mutex del pool, busca el primer slot libre, lo marca como ocupado y lo entrega al hilo. Si todos están ocupados, bloquea hasta que alguno se libere (o se agota el `timeout_ms`).
2. El handler usa la conexión (Query, Prepare, Exec…).
3. `oConn:Close()` — devuelve el slot al pool (sin cerrar el socket TCP). Si la conexión tenía una transacción abierta, hace Rollback automático.

### Red de seguridad

Si un handler tiene un bug y olvida llamar `Close()`, el dispatcher de HIX llama `WDO_ReleaseAllThread()` al terminar el request. Esto devuelve cualquier slot que el hilo tenga prestado. **No hay leaks posibles**, aunque el código sea descuidado.

### TCP preflight probe

Antes de llamar a `libpq`, el driver hace un TCP probe de bajo nivel para verificar que el servidor responde. Esto evita que `PQconnectdb` cuelgue hasta 2 minutos si el host está apagado o el firewall no devuelve RST. Si el probe falla, el arranque del pool falla en milisegundos con un mensaje claro en el log.

## Clave de pool por defecto

!!! info "Clave predeterminada: «PG» en mayúsculas"
    `WDO_InitPoolPg` (posicional) registra el pool bajo la clave fija `"PG"` (mayúsculas). Si usas `WDO_InitPoolPgEx` puedes elegir otra clave, pero `"PG"` es la convención del framework.

    En los handlers usa siempre `WDO_Get("PG")`, no `WDO_Get("pg")` (la clave es case-sensitive).

## Regla básica

!!! warning "Dentro de un handler HTTP"
    Siempre usa `WDO_Get("PG")` + `oConn:Close()`. **Nunca** `WDO_PG():New()` dentro de un controller.

`WDO_PG():New()` es legítimo solo en scripts CLI, tests unitarios o un sanity-ping de arranque. El propio driver avisa en el log si detecta un `New()` dentro de un request HTTP.

## Cuándo usar `New()` directamente

- Scripts de línea de comandos (migraciones, backups, reports).
- Tests unitarios del driver.
- Conexiones con credenciales distintas a las del pool (otra BD, otro servidor).

## Ciclo de vida completo

```
Arranque
  └─ HIX_InitPoolsFromConfig()  (o WDO_InitPoolPg)
       └─ abre N conexiones TCP + auth PostgreSQL

  Por cada request:
  └─ WDO_Get("PG")    →  slot prestado
       └─ Query / Prepare / Exec / ...
  └─ oConn:Close()    →  slot devuelto al pool

Shutdown
  └─ HIX_EndPoolsFromConfig()  (o WDO_EndPoolPg)
       └─ cierra los N sockets (una vez)
```

!!! info "Siguiente paso"
    Ahora que entiendes el modelo, [configura el pool en `config.json`](config.md).
