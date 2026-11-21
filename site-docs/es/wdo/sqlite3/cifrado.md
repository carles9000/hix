# WDO SQLite3 — Cifrado con SQLCipher

SQLCipher es una extensión de SQLite que encripta cada página del fichero `.db` con **AES-256-CBC + HMAC-SHA512**. El fichero cifrado es completamente opaco sin la passphrase — no puede inspeccionarse ni recuperarse con herramientas SQLite estándar.

La versión incluida en la DLL de HIX es **SQLCipher 4.6.1 community**.

## Por qué página a página

SQLCipher no cifra el fichero como un bloque monolítico. Cada página SQLite (típicamente 4096 bytes) se cifra de forma independiente con su propio IV derivado del número de página. Esto permite:

- Acceso aleatorio eficiente — leer la página 500 no requiere descifrar las 499 anteriores.
- Integridad verificable por página — un HMAC por página detecta modificaciones parciales del fichero.
- Compatibilidad total con el motor SQLite — el cifrado es transparente para las capas superiores.

## Configurar cifrado

=== "Declarativo (recomendado)"

    ```json
    {
      "keys": {
        "sqlite3": "mi-passphrase-muy-secreta"
      },
      "databases": {
        "APP": {
          "driver":   "sqlite3",
          "file":     "www/data/app.db",
          "key_ref":  "sqlite3"
        }
      }
    }
    ```

    `key_ref` resuelve a `HIX_KeyGet("sqlite3")` en tiempo de arranque. La passphrase nunca aparece en el código fuente ni en logs.

=== "Programático"

    ```harbour
    WDO_InitSqlite3Ex( "APP", { ;
       "file"    => "www/data/secure.db",  ;
       "key_ref" => "sqlite3"              ;
    } )
    ```

=== "Solo para pruebas"

    ```harbour
    WDO_InitSqlite3Ex( "APP", { ;
       "file" => "test.db",          ;
       "key"  => "clave-de-prueba"   ;
    } )
    ```

    !!! danger "Nunca uses `key` en producción"
        La passphrase queda en texto plano en el código fuente o en el JSON de configuración. Cualquiera con acceso al repositorio o al servidor tiene la clave.

## Verificar que la BD está cifrada

```harbour
LOCAL oConn := WDO_Get( "APP" )

IF oConn == NIL
   RETURN USendError( 503, "DB unavailable" )
ENDIF

IF oConn:IsEncrypted()
   l( "BD cifrada. SQLCipher " + oConn:GetCipherInfo()[ "cipher_version" ] )
ELSE
   lw( "ATENCIÓN: la BD no está cifrada" )
ENDIF

oConn:Close()
```

## GetCipherInfo() — parámetros activos

```harbour
hInfo := oConn:GetCipherInfo()
// {
//   "cipher_version" => "4.6.1 community",
//   "kdf_iter"       => 256000,
//   "page_size"      => 4096,
//   "hmac_algorithm" => "HMAC_SHA512",
//   "kdf_algorithm"  => "PBKDF2_HMAC_SHA512"
// }
```

Si la conexión no está cifrada, retorna un hash vacío `{=>}`.

## Rekey — cambiar la passphrase

`Rekey(cNewKey)` re-encripta el fichero entero con la nueva passphrase:

```harbour
LOCAL oConn := WDO_Get( "APP" )

IF oConn:Rekey( "nueva-passphrase-segura" )
   l( "Passphrase cambiada correctamente" )
   // oConn:cKey ahora es "nueva-passphrase-segura"
ELSE
   le( "Rekey fallido: " + oConn:cError )
ENDIF

oConn:Close()
```

!!! warning "Rekey a cadena vacía no descifra"
    ```harbour
    IF ! oConn:Rekey( "" )
       le( "SQLCipher rechaza rekey a clave vacía" )
    ENDIF
    ```
    SQLCipher no puede descifrar el fichero en su lugar mediante `PRAGMA rekey`. El driver retorna `.F.` sin modificar el fichero. Para descifrar, usa el proceso ATTACH + sqlcipher_export (ver más abajo).

## Descifrar una BD cifrada

No es posible con un simple `Rekey("")`. El proceso correcto usa el CLI de SQLCipher (o una conexión programática con dos ATTACH simultáneos):

```sql
-- Desde el CLI de SQLCipher, con la clave original:
PRAGMA key = 'mi-passphrase';
ATTACH DATABASE 'plain.db' AS plaintext KEY '';
SELECT sqlcipher_export('plaintext');
DETACH DATABASE plaintext;
-- plain.db es ahora un SQLite estándar sin cifrar
```

Desde Harbour, el mismo proceso con dos conexiones:

```harbour
LOCAL oCipher := WDO_Sqlite3():New()
LOCAL oPlain  := WDO_Sqlite3():New()

oCipher:cFile := "secure.db"
oCipher:cKey  := "mi-passphrase"
oCipher:Open()

oPlain:cFile  := "plain.db"
oPlain:Open()

oCipher:Exec( "ATTACH DATABASE 'plain.db' AS plaintext KEY ''" )
oCipher:Exec( "SELECT sqlcipher_export('plaintext')" )
oCipher:Exec( "DETACH DATABASE plaintext" )

oCipher:Close()
oPlain:Close()
```

## Clave errónea — detección y comportamiento

Si la passphrase no coincide con la que cifró el fichero, SQLite retorna `SQLITE_NOTADB` (26) al ejecutar el primer PRAGMA de verificación. El driver:

1. Detecta el error en la verificación interna (`SELECT count(*) FROM sqlite_master`).
2. Escribe **una sola línea** en consola por fichero (deduplicado por path):
   ```
   ==> Error: SQLCipher key verification failed for file: www/data/app.db
   ```
3. Cierra la conexión con `sqlite3_close()` y libera la DLL.
4. Deja `::lConnect = .F.` y `::lError = .T.`.

En un handler, esto se manifiesta como `WDO_Get("APP")` retornando `NIL` (si la config usa `HIX_InitPoolsFromConfig`) o como un `bError` disparado si se usa `New()` directamente:

```harbour
oConn := WDO_Get( "APP" )
IF oConn == NIL
   RETURN USendError( 503, "DB unavailable" )   // passphrase incorrecta o fichero dañado
ENDIF
```

!!! tip "El mensaje de consola aparece una sola vez"
    El driver deduplica por path del fichero. Si 50 workers intentan abrir la misma BD con clave errónea, solo verás un mensaje en el log. Facilita el diagnóstico sin inundar el log de producción.

## Parámetros SQLCipher avanzados

La mayoría de apps deben usar los defaults de SQLCipher 4.x. Solo toca estos parámetros si tienes requisitos específicos de compatibilidad o rendimiento:

| Parámetro | Default SQLCipher 4.x | Cuándo cambiarlo |
|-----------|----------------------|------------------|
| `cipher_kdf_iter` | 256 000 | Bajar a 1000–10 000 en tests para acelerar el Open(). **Nunca** en producción. |
| `cipher_page_size` | 4096 | Solo si necesitas compatibilidad con versiones antiguas de SQLCipher (< 4.0). |
| `cipher_hmac_algorithm` | `HMAC_SHA512` | Solo para interop con apps que usen `HMAC_SHA1` (SQLCipher < 4.0). |
| `cipher_kdf_algorithm` | `PBKDF2_HMAC_SHA512` | Igual que el anterior. |

!!! warning "KDF iter y tiempo de Open()"
    Con 256 000 iteraciones, `sqlite3_key()` tarda ~0.3 segundos en hardware moderno. Ese coste se paga **una sola vez** al arrancar el servidor, no por request. Es completamente aceptable en producción.

    En tests de integración donde el Open() se llama decenas de veces, usa `"cipher_kdf_iter": 1000` para reducir el tiempo de setup de ~10s a ~40ms.

## Consideraciones de rendimiento

| Operación | Overhead de cifrado |
|-----------|---------------------|
| Lectura (SELECT) | ~5–10% vs SQLite sin cifrar |
| Escritura (INSERT/UPDATE) | ~15% vs SQLite sin cifrar |
| Open() con `kdf_iter=256000` | ~0.3s (una vez al arrancar) |
| Rekey() — re-encripta todo | Proporcional al tamaño del fichero (~2 MB/s) |

Benchmark en hardware de referencia: Intel Core i7-10750H, SQLCipher 4.6.1, `PRAGMA synchronous=NORMAL`, WAL mode.

## Referencia de API de cifrado

| Método / Propiedad | Descripción |
|--------------------|-------------|
| `oConn:cKey := cPass` + `oConn:Open()` | Abre un fichero cifrado existente |
| `oConn:IsEncrypted()` | `.T.` si la conexión está sobre un fichero cifrado |
| `oConn:lEncrypted` | DATA — refleja el estado tras `Open()` o `Rekey()` |
| `oConn:Rekey(cNewKey)` | Re-encripta el fichero con la nueva passphrase. `.T.` si OK |
| `oConn:GetCipherInfo()` | Hash con 5 campos: `cipher_version`, `kdf_iter`, `page_size`, `hmac_algorithm`, `kdf_algorithm` |
