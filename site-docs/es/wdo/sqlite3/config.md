# WDO SQLite3 — Configuración

Hay tres formas de inicializar el driver SQLite3 (singleton o pool). La recomendada es la declarativa desde `hix.json` (o `www/config.json` con hixstyle).

## Método 1 — Declarativo (recomendado)

Añade la sección `databases` en `hix.json`:

```json
{
  "databases": {
    "APP": {
      "driver":                "sqlite3",
      "file":                  "www/data/app.db",
      "create":                true,
      "journal_mode":          "WAL",
      "synchronous":           "NORMAL",
      "foreign_keys":          true,
      "busy_timeout_ms":       5000,
      "key_ref":               "sqlite3"
    }
  }
}
```

En apps con **hixstyle** no necesitas nada más: `Start()` llama automáticamente a `HIX_InitPoolsFromConfig(.T.)` y `HIX_EndPoolsFromConfig()`.

En apps sin hixstyle:

```harbour
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()
   HIX_ConfigAppLoad( "www/config.json" )
   HIX_InitPoolsFromConfig()   // aborta si el singleton no arranca (default)
   oSrv:Start()
   IF oSrv:hThread != NIL
      hb_threadJoin( oSrv:hThread )
   ENDIF
   HIX_EndPoolsFromConfig()
RETURN
```

### Campos disponibles

| Campo | Default | Descripción |
|-------|---------|-------------|
| `driver` | _(obligatorio)_ | `"sqlite3"` (case-insensitive) |
| `file` | `":memory:"` | Path al fichero `.db` (relativo al directorio de trabajo) |
| `create` | `true` | Crea el fichero si no existe; `.F.` falla si no existe |
| `journal_mode` | `"WAL"` | `WAL` / `DELETE` / `MEMORY` / `OFF`. WAL = mejor concurrencia |
| `synchronous` | `"NORMAL"` | `FULL` / `NORMAL` / `OFF`. NORMAL = buen balance durabilidad/velocidad |
| `foreign_keys` | `true` | Activa `PRAGMA foreign_keys=ON` |
| `busy_timeout_ms` | `5000` | Tiempo máximo de espera si otro proceso tiene el fichero bloqueado |
| <a name="pool_size"></a>`pool_size` | `1` | `1` = singleton (una conexión compartida, mutex por operación); `> 1` = pool real de N conexiones con reserva por request. Ver [Transacciones § Aislamiento](transacciones.md#aislamiento-de-transacciones). Añadido en v2.5.3. |
| `timeout_ms` | `5000` | Timeout de reserva del pool (solo con `pool_size > 1`): si todas las conexiones están ocupadas, cuánto espera `WDO_Get` antes de retornar `NIL` |
| `ping` | `false` | Ping on-acquire del pool (solo con `pool_size > 1`): verifica que la conexión sigue viva antes de entregarla al handler |
| `debug` | `false` | Activa `HIX_Dbg()` globalmente; escribe trazas en `dbg.log` |
| `berror` | — | Nombre de función Harbour para manejar errores del driver |
| `dll` | — | Ruta explícita a `sqlcipher.dll` (override de la resolución automática) |

Campos SQLCipher (opcionales; se ignoran si no hay `key` ni `key_ref`):

| Campo | Default | Descripción |
|-------|---------|-------------|
| `key` | `""` | Passphrase en texto plano. Solo para pruebas; usar `key_ref` en producción |
| `key_ref` | `""` | Nombre de clave en `HIX_Keys` (recomendado) |
| `cipher_kdf_iter` | `0` | Iteraciones KDF PBKDF2 (0 = default SQLCipher ~256 000) |
| `cipher_page_size` | `0` | Tamaño de página cifrada en bytes (0 = default 4096) |
| `cipher_hmac_algorithm` | `""` | `HMAC_SHA512` / `HMAC_SHA1` (`""` = default SQLCipher 4.x) |
| `cipher_kdf_algorithm` | `""` | `PBKDF2_HMAC_SHA512` / `PBKDF2_HMAC_SHA1` (`""` = default) |

### key vs key_ref

!!! warning "Nunca pongas la passphrase en texto plano en producción"
    El campo `key` guarda la passphrase directamente en el JSON. Cualquiera con acceso al fichero de configuración conoce la clave. Usa `key_ref` en producción.

`key_ref` apunta a una clave almacenada en `HIX_Keys`, que se puebla desde la sección `keys` de `www/config.json`:

```json
{
  "keys": {
    "sqlite3": "mi-passphrase-muy-secreta-32chars"
  },
  "databases": {
    "APP": {
      "driver":    "sqlite3",
      "file":      "www/data/app.db",
      "key_ref":   "sqlite3"
    }
  }
}
```

En tiempo de arranque, `HIX_InitPoolsFromConfig()` resuelve `key_ref` → `HIX_KeyGet("sqlite3")` y pasa la passphrase al driver. El valor nunca queda en memoria más del tiempo necesario para abrir la conexión.

---

## Método 2 — Programático hash

```harbour
WDO_InitSqlite3Ex( "APP", { ;
   "file"            => hb_GetEnv( "DB_PATH" ),  ;
   "create"          => .T.,                      ;
   "journal_mode"    => "WAL",                    ;
   "synchronous"     => "NORMAL",                 ;
   "foreign_keys"    => .T.,                      ;
   "busy_timeout_ms" => 5000,                     ;
   "key"             => hb_GetEnv( "DB_KEY" ),    ;
   "cipher_kdf_iter" => 256000                    ;
} )
```

Útil cuando el path o la passphrase se leen de variables de entorno o de un vault externo.

## Método 3 — Posicional (legacy)

```harbour
//  WDO_InitSqlite3( cFile, lCreate, bError, cKey )
WDO_InitSqlite3( "data/app.db", .T., NIL, "" )   // sin cifrado

//  Con cifrado
WDO_InitSqlite3( "data/secure.db", .T., NIL, "mi-passphrase" )
```

Registra el singleton bajo la clave `"SQLITE3"` (mayúsculas). Compatible con scripts de migración anteriores a v2.5.0.

!!! info "Cierre del singleton"
    Para cerrar el singleton registrado bajo cualquier clave: `WDO_EndSqlite3("APP")` o `WDO_EndSqlite3("SQLITE3")`.

---

## DLLs — SQLCipher y OpenSSL

El driver necesita estas DLLs en Windows:

| DLL | Función |
|-----|---------|
| `sqlcipher.dll` | SQLite3 + motor de cifrado SQLCipher |
| `libcrypto-4-x64.dll` | OpenSSL — algoritmos AES, HMAC, PBKDF2 |
| `libssl-4-x64.dll` | OpenSSL — TLS (requerida por libcrypto) |

Las tres DLLs precompiladas para Windows x64 (MinGW64 / OpenSSL 4.x) están en `resources/wdo/sqlite3/dll/`. Cópialas junto al ejecutable o añade su directorio al `PATH`.

### Precedencia de resolución de sqlcipher.dll

El driver busca la librería en este orden (mayor prioridad primero):

1. **Campo `"dll"` en `config.json`** — ruta absoluta explícita.
2. **Variable de entorno `HIX_SQLITE3_DLL`** — ruta absoluta al fichero.
3. **Variable de entorno `WDO_SQLITE3_DLL`** — ruta absoluta al fichero.
4. **Directorio del ejecutable** `hb_DirBase() + "dll\sqlcipher.dll"`.
5. **Directorio del ejecutable** `hb_DirBase() + "sqlcipher.dll"`.
6. **PATH del sistema** — nombre canónico `sqlcipher.dll`.

El tag de resolución queda en `oConn:cDllSource` (`"override"`, `"env"`, `"exedir"`, `"default"`) para diagnóstico.

### Si la DLL no se encuentra

```
==> Error: Cannot load SQLite3 DLL: sqlcipher.dll
```

=== "Opción A — junto al ejecutable"
    Copia las tres DLLs al subdirectorio `dll/` junto al ejecutable del servidor. Es la opción más simple y la que usa `hb_DirBase() + "dll\sqlcipher.dll"`.

=== "Opción B — variable de entorno"
    ```
    set HIX_SQLITE3_DLL=C:\miapp\sqlite3\sqlcipher.dll
    ```

=== "Opción C — campo dll en config.json"
    ```json
    {
      "databases": {
        "APP": {
          "driver": "sqlite3",
          "dll":    "C:/miapp/sqlite3/sqlcipher.dll",
          ...
        }
      }
    }
    ```

---

## WAL sidecars — backup y tests

!!! warning "El WAL crea ficheros adicionales"
    Con `journal_mode=WAL`, SQLite genera dos ficheros junto al `.db`:

    - `app.db-wal` — log de escritura sin confirmar
    - `app.db-shm` — memoria compartida (índice del WAL)

    **Backup:** copia los tres ficheros atómicamente mientras la app no escribe, o usa el API de backup de SQLite (`sqlite3_backup_*`).

    **Tests:** al borrar la BD de test, borra también los sidecars:

    ```harbour
    FErase( cDb )
    FErase( cDb + "-wal" )
    FErase( cDb + "-shm" )
    ```

    Si la conexión se cierra limpiamente (`WDO_EndSqlite3`), SQLite hace un checkpoint automático y los sidecars quedan a cero o desaparecen.

---

## Handler de error personalizado

```harbour
FUNCTION MiSqliteErrorHandler( oErr, oConn )

   HB_SYMBOL_UNUSED( oConn )

   le( "[SQLite3] " + oErr:description + " @ " + oErr:operation )

   IF HIX_GetRequest() != NIL
      USendError( 500, "DB error: " + oErr:description )
   ENDIF

RETURN NIL
```

Referénciala en el JSON:

```json
"berror": "MiSqliteErrorHandler"
```

!!! warning "Requisitos de la función"
    Debe ser una `FUNCTION` pública estáticamente enlazada al ejecutable. Si no se encuentra, el driver escribe un WARN al arrancar y usa el handler por defecto (que llama `Break()` y delega en el sistema de errores de Harbour).
