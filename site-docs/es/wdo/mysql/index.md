# WDO MySQL — Concepto y Pool

El driver `WDO_MySql` envuelve la librería cliente de MySQL/MariaDB (`libmysqlclient` / `libmariadb`) mediante `hb_DynCall`. Sobre él, `WDO_Pool` implementa el pool de conexiones thread-safe que usan los handlers HTTP.

## El problema que resuelve el pool

Imagina 100 peticiones concurrentes, cada una abriendo y cerrando su propia conexión MySQL:

```
Request 1  →  New() → TCP connect + auth (~0.7 ms) → Query → End() → socket en TIME_WAIT
Request 2  →  New() → TCP connect + auth (~0.7 ms) → Query → End() → socket en TIME_WAIT
...×100
```

Tras unos miles de peticiones rápidas en Windows, el sistema se queda sin puertos efímeros y aparece el error **10048** (`WSAEADDRINUSE`). La segunda corrida del bench sin pool colapsa con exactamente este error.

Con pool, los sockets se abren **una sola vez** al arrancar y se reusan indefinidamente:

```
Arranque:  WDO_Init → abre 5 conexiones TCP (una vez, coste amortizado)

Request 1  →  WDO_Get() → slot #1 prestado (~0.005 ms) → Query → Close() → slot #1 devuelto
Request 2  →  WDO_Get() → slot #2 prestado (~0.005 ms) → Query → Close() → slot #2 devuelto
...×100  →  se turnan sobre los 5 slots, sin abrir/cerrar sockets
```

## Rendimiento comparado

| Patrón | Coste por request | Escala bajo carga |
|--------|-------------------|-------------------|
| `WDO_MySql():New()` por request | ~0.77 ms (87% es setup) | Colapsa con 10048 |
| `WDO_Get()` / `Close()` (pool) | ~0.06 ms (83% es la query) | Estable indefinidamente |

**El pool es ~13× más rápido** en overhead, y el único que escala en producción.

## Cómo funciona el pool

### Al arrancar la app

`WDO_InitPoolMySql` (o el arranque declarativo desde `config.json`) crea `N` instancias de `WDO_MySql`, las conecta y las guarda en el array interno del pool marcadas como libres.

### Por cada request

1. `WDO_Get("mysql")` — toma el mutex del pool, busca el primer slot libre, lo marca como ocupado y lo entrega al hilo. Si todos están ocupados, bloquea hasta que alguno se libere (o se agota el `timeout_ms`).
2. El handler usa la conexión (Query, Prepare, Exec…).
3. `oConn:Close()` — devuelve el slot al pool (sin cerrar el socket TCP). Si la conexión tenía una transacción abierta, hace Rollback automático.

### Red de seguridad

Si un handler tiene un bug y olvida llamar `Close()`, el dispatcher de HIX llama `WDO_ReleaseAllThread()` al terminar el request. Esto devuelve cualquier slot que el hilo tenga prestado. **No hay leaks posibles**, aunque el código sea descuidado.

## Regla básica

!!! warning "Dentro de un handler HTTP"
    Siempre usa `WDO_Get("mysql")` + `oConn:Close()`. **Nunca** `WDO_MySql():New()` dentro de un controller.

`WDO_MySql():New()` es legítimo solo en scripts CLI, tests unitarios o un sanity-ping de arranque. El propio driver avisa en el log si detecta un `New()` dentro de un request HTTP.

## Cuándo usar `New()` directamente

- Scripts de línea de comandos (migraciones, backups, reports).
- Tests unitarios del driver.
- Conexiones con credenciales distintas a las del pool (otra BD, otro servidor).

## Ciclo de vida completo

```
Arranque
  └─ HIX_InitPoolsFromConfig()  (o WDO_InitPoolMySql)
       └─ abre N conexiones TCP

  Por cada request:
  └─ WDO_Get("mysql")   →  slot prestado
       └─ Query / Prepare / Exec / ...
  └─ oConn:Close()      →  slot devuelto al pool

Shutdown
  └─ HIX_EndPoolsFromConfig()  (o WDO_EndPoolMySql)
       └─ cierra los N sockets (una vez)
```

!!! info "Siguiente paso"
    Ahora que entiendes el modelo, [configura el pool en `config.json`](config.md).
