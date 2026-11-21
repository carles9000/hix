# WDO PostgreSQL — Troubleshooting

Guía de diagnóstico para los errores más frecuentes del driver PostgreSQL.

## Mapa síntoma → solución

| Síntoma | Ve a |
|---------|------|
| App cuelga al arrancar sin mensajes (TCP probe) | [§1](#1-app-cuelga-al-arrancar) |
| DLL no encontrada / "Cannot load PostgreSQL DLL" | [§2](#2-dll-no-encontrada) |
| `WDO_Get()` retorna NIL bajo carga | [§3](#3-wdoget-retorna-nil-bajo-carga) |
| "FATAL: password authentication failed" | [§4](#4-error-de-autenticacion) |
| "SSL connection required" / error de SSL | [§5](#5-error-ssl) |
| NOTICE spam en la consola ("tabla no existe, omitiendo") | [§6](#6-notice-spam-de-ddl) |
| WARN `RELEASE_RECLAIM` en el log | [§7](#7-warn-release_reclaim) |
| `psql` conecta pero la app no | [§8](#8-psql-conecta-pero-la-app-no) |

---

## 1. App cuelga al arrancar

La app arranca, no hay mensajes de error, pero no responde. El proceso se queda consumiendo CPU mínima durante minutos.

**Causa más frecuente:** `PQconnectdb` de libpq espera la respuesta TCP del servidor. Sin timeout de red, puede bloquearse hasta 2 minutos si el host no responde (firewall que descarta paquetes sin RST, host incorrecto, PostgreSQL apagado).

**Mecanismo de protección — TCP preflight probe:**

WDO_PG hace un TCP probe de bajo nivel antes de llamar a `PQconnectdb`. Si el host no responde el probe en `connect_timeout_s` segundos, el pool falla en milisegundos:

```
==> Error: WDO_PG TCP probe failed — host=10.0.0.42 port=5432
```

Si ves este mensaje, el problema es de red o de host/puerto incorrecto.

**Diagnóstico:**

=== "Windows"
    ```cmd
    :: Probar conectividad TCP directamente
    Test-NetConnection -ComputerName 127.0.0.1 -Port 5432

    :: O con psql
    psql -h 127.0.0.1 -U postgres -d myapp
    ```

=== "Linux / WSL"
    ```bash
    nc -zv 127.0.0.1 5432
    psql -h 127.0.0.1 -U postgres -d myapp
    ```

**Soluciones por orden:**

1. Verifica que PostgreSQL está arrancado: `pg_ctl status` o `systemctl status postgresql`.
2. Comprueba que `postgresql.conf` tiene `listen_addresses = '*'` o al menos `'127.0.0.1'`.
3. Verifica el puerto: por defecto 5432, pero instalaciones custom pueden usar otro.
4. Revisa el firewall: PostgreSQL debe aceptar conexiones TCP en el puerto configurado.
5. Reduce `connect_timeout_s` a 3 durante el diagnóstico para fallar rápido.

!!! info "Coste del TCP probe"
    El probe añade ~1–2 ms por arranque del pool. Es despreciable y compensa eliminando los hangs de 2 minutos.

---

## 2. DLL no encontrada

```
==> Error: Cannot load PostgreSQL DLL (libpq.dll)
```

**Causas posibles:**

1. `libpq.dll` no está en ninguna de las rutas buscadas.
2. El campo `"dll"` en `config.json` apunta a una ruta incorrecta.
3. `libpq.dll` existe pero faltan sus dependencias (`libcrypto-4-x64.dll`, `libssl-4-x64.dll`, `libcurl-x64.dll`) — Windows falla al cargar la DLL sin mensaje claro.

**Soluciones:**

=== "Opción A — junto al ejecutable"
    Copia las cuatro DLLs de `resources/wdo/pg/dll/` al directorio del servidor (`hb_DirBase()`). Es la opción más simple.

    ```
    resources/wdo/pg/dll/
      libpq.dll
      libcrypto-4-x64.dll
      libssl-4-x64.dll
      libcurl-x64.dll
    ```

=== "Opción B — variable de entorno"
    ```cmd
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

Para ver qué DLL está usando el driver en tiempo de ejecución:

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "PG" )
   IF oConn == NIL ; RETURN USendError( 503, "no pool" ) ; ENDIF
   USendJson( { ;
      "dll_path"   => oConn:DllPath(),   ;
      "dll_source" => oConn:DllSource()  ;
   } )
   oConn:Close()
} )
```

!!! warning "Dependencias de libpq"
    `libpq.dll` carga dinámicamente sus dependencias. Si `libcrypto-4-x64.dll` no está junto al ejecutable ni en `PATH`, obtendrás un error críptico de Windows («no se puede inicializar el procedimiento»). Copia siempre las cuatro DLLs juntas.

---

## 3. WDO_Get retorna NIL bajo carga

```
WARN  WDO_Pool[PG] Acquire timeout after 5000ms
```

**Causa:** Todos los slots del pool están ocupados. Los handlers tardan más de lo esperado y los slots no se liberan a tiempo.

**Diagnóstico:**

```harbour
// Añade este endpoint para ver el estado en vivo
oSrv:AddRouteGet( "health.db", "/health/db", {||
   USendJson( WDO_PoolStats( "PG" ) )
   // { "size" => 5, "busy" => 5, "free" => 0, "closed" => false }
} )
```

También puedes consultar las conexiones activas desde PostgreSQL:

```sql
SELECT pid, application_name, state, query_start, query
FROM   pg_stat_activity
WHERE  application_name = 'hix-worker'
ORDER  BY query_start;
```

**Soluciones (en orden):**

1. **Aumentar `pool_size`** en `config.json` (empieza duplicando).
2. **Verificar que todos los handlers llaman `oConn:Close()`** — un solo handler que filtre una conexión bajo carga llena el pool.
3. **Revisar la latencia de las queries** — queries lentas (sin índice, full scan) ocupan los slots más tiempo del necesario. Usa `EXPLAIN ANALYZE`.
4. **Aumentar `timeout_ms`** si los picos son breves y el pool se libera pronto.

---

## 4. Error de autenticación

```
FATAL:  password authentication failed for user "postgres"
```

o

```
FATAL:  no pg_hba.conf entry for host "127.0.0.1", user "postgres", database "myapp"
```

**Causas:**

- Contraseña incorrecta en `config.json`.
- El método de autenticación en `pg_hba.conf` no admite la conexión desde la IP del servidor HIX.
- El usuario no existe o no tiene permisos sobre la base de datos.

**Diagnóstico:**

```bash
# Verificar que el usuario existe y la contraseña es correcta
psql -h 127.0.0.1 -U postgres -d myapp -c "SELECT 1"

# Revisar pg_hba.conf
psql -U postgres -c "SHOW hba_file"
```

**Configuración mínima en `pg_hba.conf`** para conexiones locales con password:

```
# TYPE  DATABASE  USER      ADDRESS         METHOD
host    all       all       127.0.0.1/32    scram-sha-256
host    all       all       ::1/128         scram-sha-256
```

Después de modificar `pg_hba.conf`:

```bash
pg_ctl reload   # o: SELECT pg_reload_conf();
```

---

## 5. Error SSL

**Síntoma A — sslmode require pero el servidor no tiene SSL:**

```
FATAL:  SSL connection required but not supported by server
```

**Solución:** Cambia `sslmode` a `"disable"` en `config.json` si PostgreSQL no está configurado con SSL, o configura SSL en el servidor.

**Síntoma B — certificate verification failed:**

```
FATAL:  certificate verify failed
```

**Solución:** Usa `sslmode: "require"` (verifica que hay cifrado pero no el certificado) en lugar de `"verify-ca"` o `"verify-full"` si no tienes los certificados del servidor instalados.

**Tabla de modos SSL:**

| `sslmode` | Cifrado | Verifica cert CA | Verifica hostname | Uso recomendado |
|-----------|---------|------------------|-------------------|-----------------|
| `disable` | No | No | No | Desarrollo local |
| `allow` | Si servidor lo ofrece | No | No | — |
| `prefer` | Preferido pero no forzado | No | No | — |
| `require` | Siempre | No | No | Producción sin PKI propia |
| `verify-ca` | Siempre | Sí | No | Producción con CA propia |
| `verify-full` | Siempre | Sí | Sí | Máxima seguridad |

!!! tip "Empezar siempre con disable"
    Durante el diagnóstico inicial, fija `sslmode: "disable"` para eliminar SSL como variable. Una vez que la conexión funciona, activa el nivel de SSL necesario.

---

## 6. NOTICE spam de DDL

**Síntoma:**

```
NOTICE:  table "temp_work" does not exist, skipping
```

Estos mensajes aparecen en la consola del servidor HIX cuando ejecutas `DROP TABLE IF EXISTS` sobre tablas inexistentes. No son errores, pero ensucian el log.

**Causa:** PostgreSQL emite NOTICE por defecto para operaciones DDL que "no hacen nada" (IF EXISTS en objetos ausentes).

**Solución — `SET client_min_messages` por sesión:**

```harbour
// Silenciar NOTICEs solo en la sesión actual (no afecta al servidor)
oConn:Exec( "SET client_min_messages TO WARNING" )
oConn:Exec( "DROP TABLE IF EXISTS temp_work" )
oConn:Exec( "CREATE TABLE temp_work (id SERIAL PRIMARY KEY, ...)" )
// Restaurar si quieres volver a ver NOTICEs en esta sesión
oConn:Exec( "SET client_min_messages TO NOTICE" )
```

!!! warning "Scope: solo la sesión actual"
    `SET client_min_messages` afecta únicamente a la conexión donde se ejecuta. Las demás conexiones del pool no se ven afectadas. No es necesario ni recomendable cambiarlo a nivel de servidor (`postgresql.conf`) solo para silenciar NOTICEs de DDL.

---

## 7. WARN RELEASE_RECLAIM

```
WARN  WDO_ReleaseAllThread: reclaiming 1 leaked connection(s) from thread 15432
```

**Causa:** Un handler adquirió una conexión con `WDO_Get()` pero no llamó `oConn:Close()` antes de terminar. El dispatcher de HIX detecta el leak al final del request y libera el slot automáticamente.

**Gravedad:** No es un error crítico — el slot se recupera. Pero el hilo tuvo la conexión más tiempo del necesario, lo que reduce la disponibilidad del pool bajo carga. Si el handler tenía una transacción abierta, el pool hace Rollback automático antes de liberar.

**Solución:** Localiza el handler que no cierra la conexión y añade `oConn:Close()`, idealmente en un bloque `FINALLY`:

```harbour
TRY
   // ... lógica del handler ...
FINALLY
   IF oConn != NIL ; oConn:Close() ; ENDIF
END
```

---

## 8. psql conecta pero la app no

La aplicación HIX no puede conectar aunque `psql` con los mismos parámetros funciona perfectamente.

**Causas frecuentes y verificaciones:**

**A) `sslmode` incorrecto:**

`psql` por defecto usa `sslmode=prefer` (intenta SSL, acepta sin SSL). Si en `config.json` tienes `sslmode: "require"` y el servidor PostgreSQL no tiene SSL, la app falla pero `psql` sin parámetros funciona.

```bash
# Probar con el mismo sslmode que usa la app
psql "host=127.0.0.1 dbname=myapp user=postgres sslmode=disable"
```

**B) `pg_hba.conf` distingue entre usuarios:**

`psql` puede conectar como `postgres` (superusuario) aunque el usuario de la app no tenga acceso.

```bash
# Probar exactamente con el usuario configurado en config.json
psql -h 127.0.0.1 -U hix_user -d myapp
```

**C) Variables de entorno que `psql` hereda pero la app no:**

`psql` usa `PGPASSWORD`, `PGHOST`, `PGPORT` del entorno. La app HIX lee solo los campos de `config.json`.

```bash
# Verificar sin variables de entorno
env -i psql "host=127.0.0.1 port=5432 dbname=myapp user=hix_user password=secret"
```

**D) DLL diferente a libpq de `psql`:**

Si el `psql` del PATH usa libpq de una instalación diferente a la DLL que usa HIX, puede haber diferencias de protocolo o soporte de autenticación.

```bash
# Ver qué libpq usa psql
psql --version
# Ver qué DLL usa HIX
curl http://localhost:8080/dbinfo
```

---

## Mensajes del logger (referencia rápida)

| Mensaje | Nivel | Qué significa |
|---------|-------|---------------|
| `WDO_LOG_POOL_INIT_FAIL` | WARN | Un slot del pool no pudo abrirse al arrancar |
| `WDO_LOG_ACQUIRE_TIMEOUT` | WARN | `WDO_Get()` esperó `timeout_ms` sin conseguir slot |
| `WDO_LOG_PG_POOL_INIT_FAIL` | WARN | Ningún slot del pool se abrió; pool no disponible |
| `WDO_ERR_LIB_NOT_FOUND` | ERROR | `libpq.dll` no existe en la ruta buscada |
| `WDO_ERR_LIB_LOAD_FAIL` | ERROR | `libpq.dll` existe pero `hb_LibLoad` no pudo cargarla (dependencias ausentes) |
| `WDO_WARN_NEW_IN_REQUEST` | WARN | `New()` llamado dentro de un handler HTTP |
| `WDO_WARN_BERROR_NOT_FOUND` | WARN | La función del campo `berror` no está enlazada |
| `WDO_LOG_POOLS_INIT` | INFO | `N/M pools` inicializados correctamente |
| `WDO_LOG_POOLS_END` | INFO | Pools cerrados al apagar el servidor |
| `WDO_PG TCP probe failed` | ERROR | El host no responde al probe TCP antes de `PQconnectdb` |
| `WDO_ReleaseAllThread: reclaiming` | WARN | Slot no devuelto por el handler; reclamado por el dispatcher |
