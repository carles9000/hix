# WDO SQLite3 — Troubleshooting

Guía de diagnóstico para los errores más frecuentes del driver SQLite3/SQLCipher.

## Mapa síntoma → solución

| Síntoma | Ve a |
|---------|------|
| `sqlcipher.dll not found` / DLL no carga | [§1](#1-dll-no-encontrada) |
| `SQLITE_BUSY` / "database is locked" | [§2](#2-sqlite_busy-database-is-locked) |
| `SQLITE_NOTADB` / "SQLCipher key verification failed" | [§3](#3-clave-erronea-sqlite_notadb) |
| Sidecars `-wal` / `-shm` no se borran en tests | [§4](#4-sidecars-wal-shm-en-tests) |
| WARN `RELEASE_RECLAIM` en el log | [§5](#5-warn-release_reclaim) |
| `Count()` retorna -1 siempre | [§6](#6-count-retorna-1) |
| `Rekey("")` retorna `.F.` | [§7](#7-rekey-retorna-f-con-cadena-vacia) |

---

## 1. DLL no encontrada

```
==> Error: Cannot load SQLite3 DLL: sqlcipher.dll
```

**Causas posibles:**

1. Las DLLs no están en ninguna de las rutas buscadas.
2. El campo `"dll"` en `config.json` apunta a una ruta incorrecta.
3. Falta alguna DLL de dependencia (`libcrypto-4-x64.dll`, `libssl-4-x64.dll`).
4. Se copia solo `sqlcipher.dll` pero no sus dependencias OpenSSL.

**Soluciones:**

=== "Opción A — subdirectorio dll/ junto al ejecutable"
    Copia las tres DLLs al subdirectorio `dll/` junto al ejecutable. Esta es la ruta que busca el driver por defecto:

    ```
    miapp/
      miapp.exe
      dll/
        sqlcipher.dll
        libcrypto-4-x64.dll
        libssl-4-x64.dll
    ```

    Las DLLs listas para copiar están en `resources/wdo/sqlite3/dll/`.

=== "Opción B — variable de entorno"
    ```
    set HIX_SQLITE3_DLL=C:\miapp\sqlite3\sqlcipher.dll
    ```
    Las DLLs de dependencia deben estar en el mismo directorio o en el PATH.

=== "Opción C — campo dll en config.json"
    ```json
    {
      "databases": {
        "APP": {
          "driver": "sqlite3",
          "dll":    "C:/miapp/sqlite3/sqlcipher.dll"
        }
      }
    }
    ```

Para verificar qué DLL está usando el driver en tiempo de ejecución:

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "APP" )
   IF oConn == NIL ; RETURN USendError( 503, "no singleton" ) ; ENDIF
   USendJson( oConn:GetClientInfo() )
   oConn:Close()
} )
```

`GetClientInfo()` retorna `dll_path` y `dll_source` entre otros campos.

---

## 2. SQLITE_BUSY — database is locked

```
Error WDO/SQLITE_BUSY  database is locked
```

**Causas posibles:**

1. Otro proceso (SQLite Browser, un script de migración) tiene el fichero abierto con un write lock.
2. Dos hilos intentan escribir simultáneamente y el `busy_timeout_ms` es demasiado bajo.
3. Una transacción de escritura quedó abierta sin `Commit()` ni `Rollback()` (leak de transacción).

**Soluciones:**

**Aumentar `busy_timeout_ms`** si el problema es contención de escritura entre workers:

```json
{
  "databases": {
    "APP": {
      "busy_timeout_ms": 10000
    }
  }
}
```

**Verificar que no hay otro proceso con el fichero abierto:**

```bash
# Windows — qué proceso tiene el fichero abierto
handle64.exe app.db
```

**Buscar leaks de transacción** — revisar que todos los handlers que llaman `BeginTrans()` también llaman `Commit()` o `Rollback()` en todos los caminos de salida, incluyendo los caminos de error. Usar siempre `TRY / FINALLY`.

!!! info "WAL reduce pero no elimina los SQLITE_BUSY"
    En modo WAL, múltiples lectores pueden coexistir con un writer. Pero si hay dos writers simultáneos, el segundo sigue esperando. `busy_timeout_ms` define cuánto tiempo espera antes de retornar error.

---

## 3. Clave errónea — SQLITE_NOTADB

```
==> Error: SQLCipher key verification failed for file: www/data/app.db
```

**Causa:** La passphrase configurada en `key` o resuelta desde `key_ref` no coincide con la que cifró el fichero.

**Este mensaje aparece una sola vez por fichero** (deduplicación por path). Si ves el mensaje repetido para rutas distintas, hay múltiples ficheros con clave incorrecta.

**Diagnóstico:**

1. Verifica el valor de `key_ref` en la sección `keys` de `www/config.json`.
2. Si usas `key` directamente, verifica que no hay espacios o caracteres invisibles.
3. Si el fichero se creó con una versión anterior de SQLCipher (< 4.0), los defaults KDF son distintos — especifica `cipher_kdf_iter`, `cipher_hmac_algorithm` y `cipher_kdf_algorithm` explícitamente.

**En tests — instalar bError para evitar que el error escale:**

```harbour
LOCAL oConn := WDO_Sqlite3():New()
oConn:bError := {| oErr | .T. }   // absorber el error sin Break()
oConn:cFile  := "test.db"
oConn:cKey   := "clave-incorrecta"
oConn:Open()

IF ! oConn:lConnect
   ? "Open fallido (esperado): " + oConn:cError
ENDIF
```

!!! warning "CLASSDATA lShowError INIT .T."
    Si `bError` es NIL y `lShowError` está activo (el default), un `Open()` con clave errónea llama a `Break()` y escala el error al sistema de errores de Harbour. En handlers HIX el dispatcher lo captura y retorna 500. En tests unitarios fuera del pipeline, instala `bError` antes del `Open()`.

---

## 4. Sidecars -wal / -shm en tests

```
// FErase( cDb ) borra app.db pero los sidecars quedan en disco
```

**Causa:** El WAL mode crea `app.db-wal` y `app.db-shm`. Si la conexión no se cierra limpiamente (o si hay una transacción sin commit), los sidecars contienen datos y no se eliminan.

**Solución — borrar los tres ficheros:**

```harbour
FErase( cDb )
FErase( cDb + "-wal" )
FErase( cDb + "-shm" )
```

**Mejor solución — cerrar el singleton antes de borrar:**

```harbour
WDO_EndSqlite3( "APP" )   // cierra limpiamente + checkpoint automático
FErase( cDb )
FErase( cDb + "-wal" )    // normalmente ya están vacíos tras el checkpoint
FErase( cDb + "-shm" )
```

!!! tip "BD en memoria para tests"
    Los tests unitarios que no necesitan persistencia pueden usar `"file": ":memory:"`. Una BD en memoria no genera sidecars, es instantánea de crear/destruir y está aislada entre ejecuciones.

    ```json
    { "driver": "sqlite3", "file": ":memory:", "create": true }
    ```

---

## 5. WARN RELEASE_RECLAIM

```
WARN  WDO_ReleaseAllThread: reclaiming 1 leaked connection(s) from thread 15432
```

**Causa:** Un handler adquirió una referencia al singleton con `WDO_Get()` y ejecutó código con el mutex del driver adquirido (p. ej. en medio de un `Fetch` sin terminar) sin liberar. El dispatcher de HIX detecta el estado al final del request y fuerza la liberación.

**En SQLite3 esto es menos grave que en MySQL/PG** (no hay slot de pool que se quede bloqueado), pero indica que un statement no se liberó con `Free()`.

**Solución:** Localiza el handler que no llama `oStmt:Free()` y añádelo en un bloque `FINALLY`:

```harbour
TRY
   oStmt := oConn:Prepare( "SELECT ..." )
   // ... lógica ...
FINALLY
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   oConn:Close()
END
```

---

## 6. Count() retorna -1

```harbour
oStmt := oConn:Query( "SELECT * FROM usuarios" )
? oStmt:Count()   // -1   ← comportamiento esperado, no un bug
```

**Causa:** SQLite no conoce el número total de filas de un SELECT antes de haberlas recorrido todas. `sqlite3_data_count()` y `sqlite3_column_count()` no retornan el row count — solo el número de columnas.

**Esta es una diferencia fundamental con MySQL/PG** donde `Count()` retorna el número de filas en el resultset.

**Solución — obtener el total antes si es necesario:**

```harbour
// Obtener el total
oStmt  := oConn:Query( "SELECT count(*) FROM usuarios" )
aRow   := oStmt:Fetch()
nTotal := Val( aRow[ 1 ] )
oStmt:Free()

// Luego obtener los datos
oStmt := oConn:Query( "SELECT * FROM usuarios LIMIT 20" )
aRows := oStmt:FetchAll( .T. )
oStmt:Free()

USendJson( { "total" => nTotal, "data" => aRows } )
```

!!! info "FetchAll y Count()"
    Después de `FetchAll()`, `oStmt:Count()` todavía retorna -1. `FetchAll` no guarda el row count — retorna directamente el array. Si necesitas el total, usa el `Len()` del array resultante:

    ```harbour
    aRows  := oStmt:FetchAll( .T. )
    nTotal := Len( aRows )
    ```

---

## 7. Rekey() retorna .F. con cadena vacía

```harbour
IF ! oConn:Rekey( "" )
   le( "SQLCipher no puede descifrar con rekey vacío" )
ENDIF
```

**Causa:** SQLCipher no soporta `PRAGMA rekey = ''` para descifrar el fichero en su lugar. La operación está bloqueada a nivel del motor SQLCipher y retorna un error.

**Solución — proceso ATTACH + sqlcipher_export:**

Ver la sección [Descifrar una BD cifrada](cifrado.md#descifrar-una-bd-cifrada) en la documentación de cifrado.

---

## Mensajes del logger — referencia rápida

| Mensaje | Nivel | Qué significa |
|---------|-------|---------------|
| `==> Error: Cannot load SQLite3 DLL: ...` | ERROR | La DLL no existe en la ruta o falla `hb_LibLoad` |
| `==> Error: SQLCipher key verification failed for file: ...` | ERROR | Passphrase incorrecta o fichero no cifrado; `Open()` fallido |
| `WDO_LOG_SQLITE3_INIT_FAIL` | ERROR | El singleton no pudo abrirse al arrancar |
| `WDO_LOG_SQLITE3_BUSY` | WARN | `sqlite3_step` retornó `SQLITE_BUSY` tras agotar `busy_timeout` |
| `WDO_WARN_BERROR_NOT_FOUND` | WARN | La función del campo `berror` no está enlazada al ejecutable |
| `WDO_LOG_SQLITE3_INIT` | INFO | Singleton inicializado correctamente |
| `WDO_LOG_SQLITE3_END` | INFO | Singleton cerrado correctamente al apagar el servidor |
| `WDO_WARN_RELEASE_RECLAIM` | WARN | Statement no liberado detectado y forzado por el dispatcher |
