# WDO SQLite3 — Encryption with SQLCipher

SQLCipher is a SQLite extension that encrypts each page of the `.db` file with **AES-256-CBC + HMAC-SHA512**. The encrypted file is completely opaque without the passphrase — it cannot be inspected or recovered with standard SQLite tools.

The version bundled in the HIX DLL is **SQLCipher 4.6.1 community**.

## Why page-by-page

SQLCipher does not encrypt the file as a monolithic block. Each SQLite page (typically 4096 bytes) is encrypted independently with its own IV derived from the page number. This allows:

- Efficient random access — reading page 500 does not require decrypting the previous 499.
- Per-page verifiable integrity — a per-page HMAC detects partial file modifications.
- Full compatibility with the SQLite engine — encryption is transparent to the upper layers.

## Configuring encryption

=== "Declarative (recommended)"

    ```json
    {
      "keys": {
        "sqlite3": "my-very-secret-passphrase"
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

    `key_ref` resolves to `HIX_KeyGet("sqlite3")` at startup. The passphrase never appears in source code or logs.

=== "Programmatic"

    ```harbour
    WDO_InitSqlite3Ex( "APP", { ;
       "file"    => "www/data/secure.db",  ;
       "key_ref" => "sqlite3"              ;
    } )
    ```

=== "Tests only"

    ```harbour
    WDO_InitSqlite3Ex( "APP", { ;
       "file" => "test.db",        ;
       "key"  => "test-passphrase" ;
    } )
    ```

    !!! danger "Never use `key` in production"
        The passphrase is stored in plain text in the source code or configuration JSON. Anyone with access to the repository or server has the key.

## Verifying the DB is encrypted

```harbour
LOCAL oConn := WDO_Get( "APP" )

IF oConn == NIL
   RETURN USendError( 503, "DB unavailable" )
ENDIF

IF oConn:IsEncrypted()
   l( "DB encrypted. SQLCipher " + oConn:GetCipherInfo()[ "cipher_version" ] )
ELSE
   lw( "WARNING: DB is not encrypted" )
ENDIF

oConn:Close()
```

## GetCipherInfo() — active parameters

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

If the connection is not encrypted, returns an empty hash `{=>}`.

## Rekey — changing the passphrase

`Rekey(cNewKey)` re-encrypts the entire file with the new passphrase:

```harbour
LOCAL oConn := WDO_Get( "APP" )

IF oConn:Rekey( "new-secure-passphrase" )
   l( "Passphrase changed successfully" )
   // oConn:cKey is now "new-secure-passphrase"
ELSE
   le( "Rekey failed: " + oConn:cError )
ENDIF

oConn:Close()
```

!!! warning "Rekey to empty string does not decrypt"
    ```harbour
    IF ! oConn:Rekey( "" )
       le( "SQLCipher rejects rekey to empty key" )
    ENDIF
    ```
    SQLCipher cannot decrypt the file in place via `PRAGMA rekey`. The driver returns `.F.` without modifying the file. To decrypt, use the ATTACH + sqlcipher_export process (see below).

## Decrypting an encrypted DB {#decrypting-an-encrypted-db}

It is not possible with a simple `Rekey("")`. The correct process uses the SQLCipher CLI (or a programmatic connection with two simultaneous ATTACHes):

```sql
-- From the SQLCipher CLI, with the original key:
PRAGMA key = 'my-passphrase';
ATTACH DATABASE 'plain.db' AS plaintext KEY '';
SELECT sqlcipher_export('plaintext');
DETACH DATABASE plaintext;
-- plain.db is now a standard unencrypted SQLite database
```

From Harbour, the same process with two connections:

```harbour
LOCAL oCipher := WDO_Sqlite3():New()
LOCAL oPlain  := WDO_Sqlite3():New()

oCipher:cFile := "secure.db"
oCipher:cKey  := "my-passphrase"
oCipher:Open()

oPlain:cFile  := "plain.db"
oPlain:Open()

oCipher:Exec( "ATTACH DATABASE 'plain.db' AS plaintext KEY ''" )
oCipher:Exec( "SELECT sqlcipher_export('plaintext')" )
oCipher:Exec( "DETACH DATABASE plaintext" )

oCipher:Close()
oPlain:Close()
```

## Wrong key — detection and behaviour

If the passphrase does not match the one that encrypted the file, SQLite returns `SQLITE_NOTADB` (26) when executing the first verification PRAGMA. The driver:

1. Detects the error in the internal verification (`SELECT count(*) FROM sqlite_master`).
2. Writes **a single line** to the console per file (deduplicated by path):
   ```
   ==> Error: SQLCipher key verification failed for file: www/data/app.db
   ```
3. Closes the connection with `sqlite3_close()` and releases the DLL.
4. Leaves `::lConnect = .F.` and `::lError = .T.`.

In a handler, this manifests as `WDO_Get("APP")` returning `NIL` (if the config uses `HIX_InitPoolsFromConfig`) or as a `bError` callback fired if using `New()` directly:

```harbour
oConn := WDO_Get( "APP" )
IF oConn == NIL
   RETURN USendError( 503, "DB unavailable" )   // wrong passphrase or corrupted file
ENDIF
```

!!! tip "The console message appears only once"
    The driver deduplicates by file path. If 50 workers try to open the same DB with the wrong key, you will only see one message in the log. Makes diagnosis easy without flooding the production log.

## Advanced SQLCipher parameters

Most apps should use SQLCipher 4.x defaults. Only change these parameters if you have specific compatibility or performance requirements:

| Parameter | SQLCipher 4.x default | When to change |
|-----------|----------------------|----------------|
| `cipher_kdf_iter` | 256 000 | Lower to 1000–10 000 in tests to speed up `Open()`. **Never** in production. |
| `cipher_page_size` | 4096 | Only if you need compatibility with older SQLCipher versions (< 4.0). |
| `cipher_hmac_algorithm` | `HMAC_SHA512` | Only for interop with apps using `HMAC_SHA1` (SQLCipher < 4.0). |
| `cipher_kdf_algorithm` | `PBKDF2_HMAC_SHA512` | Same as above. |

!!! warning "KDF iter and Open() time"
    With 256 000 iterations, `sqlite3_key()` takes ~0.3 seconds on modern hardware. This cost is paid **once** at server startup, not per request. It is completely acceptable in production.

    In integration tests where `Open()` is called dozens of times, use `"cipher_kdf_iter": 1000` to reduce setup time from ~10s to ~40ms.

## Performance considerations

| Operation | Encryption overhead |
|-----------|---------------------|
| Read (SELECT) | ~5–10% vs unencrypted SQLite |
| Write (INSERT/UPDATE) | ~15% vs unencrypted SQLite |
| Open() with `kdf_iter=256000` | ~0.3s (once at startup) |
| Rekey() — re-encrypts everything | Proportional to file size (~2 MB/s) |

Benchmark on reference hardware: Intel Core i7-10750H, SQLCipher 4.6.1, `PRAGMA synchronous=NORMAL`, WAL mode.

## Encryption API reference

| Method / Property | Description |
|-------------------|-------------|
| `oConn:cKey := cPass` + `oConn:Open()` | Opens an existing encrypted file |
| `oConn:IsEncrypted()` | `.T.` if the connection is on an encrypted file |
| `oConn:lEncrypted` | DATA — reflects state after `Open()` or `Rekey()` |
| `oConn:Rekey(cNewKey)` | Re-encrypts the file with the new passphrase. `.T.` if OK |
| `oConn:GetCipherInfo()` | Hash with 5 fields: `cipher_version`, `kdf_iter`, `page_size`, `hmac_algorithm`, `kdf_algorithm` |
