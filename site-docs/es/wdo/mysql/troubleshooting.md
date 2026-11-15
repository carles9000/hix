# WDO MySQL — Troubleshooting

Guía de diagnóstico para los errores más frecuentes del driver MySQL.

## Mapa síntoma → solución

| Síntoma | Ve a |
|---------|------|
| Error 10048 / `WSAEADDRINUSE` al arrancar | [§1](#1-error-10048-wsaeaddrinuse) |
| La DLL no se carga / "not found" en consola | [§2](#2-dll-no-encontrada) |
| `WDO_Get()` retorna NIL bajo carga | [§3](#3-wdoget-retorna-nil-bajo-carga) |
| "MySQL server has gone away" | [§4](#4-mysql-server-has-gone-away) |
| "Too many connections" en MySQL | [§5](#5-too-many-connections) |
| App cuelga al arrancar sin mensajes | [§6](#6-app-cuelga-al-arrancar) |
| WARN `RELEASE_RECLAIM` en el log | [§7](#7-warn-release_reclaim) |

---

## 1. Error 10048 WSAEADDRINUSE

```
Error WDO/500  Connection = (Failed connection)
Can't connect to MySQL server on 'localhost' (10048)
```

**Causa:** Estás usando `WDO_MySql():New()` dentro de un handler HTTP (o fuera del pool). Cada petición abre un socket que queda en `TIME_WAIT` ~60 s. Tras ~10.000 peticiones rápidas, Windows agota los puertos efímeros (rango 49152–65535).

**Solución:** Usa siempre `WDO_Get("mysql")` en los handlers. Nunca `New()` dentro de un controller.

!!! warning "New() en handlers — aviso en el log"
    El driver detecta este patrón y escribe en el log:
    ```
    WARN  WDO_MySql:New called inside HTTP request handler.
          Use WDO_Get("mysql") + oConn:Close() instead.
    ```
    Si ves este aviso, localiza el handler que lo genera y cámbialo a pool.

---

## 2. DLL no encontrada

```
==> Error: Cannot load MySQL DLL
```

**Causas posibles:**

1. La DLL no está en ninguna de las rutas buscadas.
2. El campo `"dll"` en `config.json` apunta a una ruta incorrecta.
3. Estás usando `"driver": "mysql"` pero solo tienes `libmariadb64.dll` (o viceversa).

**Soluciones:**

=== "Opción A — junto al ejecutable"
    Copia `libmysql64.dll` (o `libmariadb64.dll`) al directorio del servidor (`hb_DirBase()`). La opción más simple.

=== "Opción B — variable de entorno"
    ```
    set WDO_LIB_MYSQL=C:\mysql\lib\libmysql64.dll
    ```

=== "Opción C — campo dll en config.json"
    ```json
    {
      "databases": {
        "mysql": {
          "driver": "mysql",
          "dll": "C:/mysql/lib/libmysql64.dll",
          ...
        }
      }
    }
    ```

Para ver qué DLL está usando el driver en tiempo de ejecución:

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "mysql" )
   IF oConn == NIL ; RETURN USendError( 503, "no pool" ) ; ENDIF
   USendJson( { "dll_path" => oConn:DllPath(), "dll_source" => oConn:DllSource() } )
   oConn:Close()
} )
```

---

## 3. WDO_Get retorna NIL bajo carga

```
WARN  WDO_Pool[MySQL] Acquire timeout after 5000ms
```

**Causa:** Todos los slots del pool están ocupados. Los handlers tardan más de lo esperado y los slots no se liberan a tiempo.

**Diagnóstico:**

```harbour
// Añade este endpoint para ver el estado en vivo
oSrv:AddRouteGet( "health.db", "/health/db", {||
   USendJson( WDO_PoolStats( "mysql" ) )
   // { "size" => 5, "busy" => 5, "free" => 0, "closed" => false }
} )
```

**Soluciones (en orden):**

1. **Aumentar `pool_size`** en `config.json` (empieza duplicando).
2. **Verificar que todos los handlers llaman `oConn:Close()`** — un solo handler que filtre una conexión bajo carga llena el pool.
3. **Revisar la latencia de las queries** — si las queries lentas ocupan los slots demasiado tiempo, optimizar índices o añadir más slots.
4. **Aumentar `timeout_ms`** si los picos son breves y el pool se libera pronto.

---

## 4. MySQL server has gone away

```
Error WDO/500  Connection = (Failed connection)
MySQL server has gone away
```

**Causa:** La conexión TCP del pool estaba idle más tiempo que el `wait_timeout` de MySQL (por defecto 8 horas, a veces 30 minutos en hosting compartido). MySQL cerró la conexión por el lado del servidor, pero el slot del pool no lo sabe.

**Solución:** Activa `"ping": true` en `config.json`. Antes de entregar cada slot, el pool hace un ping y reconecta si el socket está muerto:

```json
{
  "databases": {
    "mysql": {
      "ping": true,
      ...
    }
  }
}
```

!!! info "Coste del ping"
    El ping añade ~0.5 ms por `WDO_Get()`. En la práctica, irrelevante frente al coste de cualquier query real. Recomendado siempre en producción con MySQL remoto.

Si el problema persiste, aumenta `wait_timeout` en MySQL (`my.cnf`):
```ini
[mysqld]
wait_timeout = 28800
interactive_timeout = 28800
```

---

## 5. Too many connections

```
Can't connect to MySQL server (1040): Too many connections
```

**Causa:** El número de conexiones activas supera `max_connections` de MySQL (default 151).

**Diagnóstico:**
```sql
SHOW STATUS LIKE 'Threads_connected';
SHOW VARIABLES LIKE 'max_connections';
```

**Soluciones:**

1. **Reducir `pool_size`** en `config.json` — no deberías tener más conexiones WDO que las que MySQL puede aceptar.
2. **Aumentar `max_connections`** en `my.cnf` (con cuidado: cada conexión consume ~1 MB de RAM):
   ```ini
   [mysqld]
   max_connections = 300
   ```
3. **Verificar que no hay pools duplicados** — si varias instancias de la app apuntan al mismo MySQL, el total de conexiones es la suma de todos los pools.

Regla de oro: `MySQL.max_connections > HIX_workers ≥ WDO_pool_size + 20 (margen admin)`.

---

## 6. App cuelga al arrancar

La app arranca, no hay mensajes de error, pero no responde.

**Causa más frecuente:** La DLL carga pero `mysql_real_connect` se queda esperando — el host no responde (firewall, MySQL apagado, hostname incorrecto).

**Diagnóstico:**

```bash
# Probar conectividad directamente
mysql -h 127.0.0.1 -u harbour -p employees
```

!!! warning "localhost vs 127.0.0.1 en Linux"
    En Linux, `mysql_real_connect("localhost")` usa el **Unix socket** (`/var/run/mysqld/mysqld.sock`) en lugar de TCP. Si el socket no existe, la conexión cuelga. WDO remapea automáticamente `"localhost"` a `"127.0.0.1"` para forzar TCP, pero si tienes problemas en Linux verifica que mysqld está escuchando en TCP (`bind-address = 0.0.0.0`).

**Otras causas:**

- `lAbortOnFail = .T.` en `HIX_InitPoolsFromConfig` → el proceso espera `Inkey(0)`. Si arrancas como servicio sin consola, se cuelga esperando tecla. Revisa el log del sistema (`journalctl -u hix` en Linux).
- Timeout de red muy alto — prueba reducir `timeout_ms` a 3000 para fallar rápido durante el diagnóstico.

---

## 7. WARN RELEASE_RECLAIM

```
WARN  WDO_ReleaseAllThread: reclaiming 1 leaked connection(s) from thread 15432
```

**Causa:** Un handler adquirió una conexión con `WDO_Get()` pero no llamó `oConn:Close()` antes de terminar. El dispatcher de HIX detecta el leak al final del request y libera el slot automáticamente.

**Gravedad:** No es un error crítico — el slot se recupera. Pero el hilo tuvo la conexión más tiempo del necesario, lo que reduce la disponibilidad del pool bajo carga.

**Solución:** Localiza el handler que no cierra la conexión y añade `oConn:Close()`, idealmente en un bloque `FINALLY`:

```harbour
TRY
   // ... lógica del handler ...
FINALLY
   IF oConn != NIL ; oConn:Close() ; ENDIF
END
```

---

## Mensajes del logger (referencia rápida)

| Mensaje | Nivel | Qué significa |
|---------|-------|---------------|
| `WDO_LOG_POOL_INIT_FAIL` | WARN | Un slot del pool no pudo abrirse al arrancar |
| `WDO_LOG_ACQUIRE_TIMEOUT` | WARN | `WDO_Get()` esperó `timeout_ms` sin conseguir slot |
| `WDO_LOG_MYSQL_POOL_INIT_FAIL` | WARN | Ningún slot del pool se abrió; pool no disponible |
| `WDO_ERR_LIB_NOT_FOUND` | ERROR | La DLL no existe en la ruta buscada |
| `WDO_ERR_LIB_LOAD_FAIL` | ERROR | La DLL existe pero `hb_LibLoad` no pudo cargarla |
| `WDO_WARN_NEW_IN_REQUEST` | WARN | `New()` llamado dentro de un handler HTTP |
| `WDO_WARN_BERROR_NOT_FOUND` | WARN | La función del campo `berror` no está enlazada |
| `WDO_LOG_POOLS_INIT` | INFO | `N/M pools` inicializados correctamente |
| `WDO_LOG_POOLS_END` | INFO | Pools cerrados al apagar el servidor |
