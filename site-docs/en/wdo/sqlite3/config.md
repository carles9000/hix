# WDO SQLite3 — Configuration

There are three ways to initialise the SQLite3 driver (singleton or pool). The recommended one is the declarative method via `hix.json` (or `www/config.json` with hixstyle).

## Method 1 — Declarative (recommended)

Add the `databases` section to `hix.json`:

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

In apps with **hixstyle** nothing more is needed: `Start()` automatically calls `HIX_InitPoolsFromConfig(.T.)` and `HIX_EndPoolsFromConfig()`.

In apps without hixstyle:

```harbour
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()
   HIX_ConfigAppLoad( "www/config.json" )
   HIX_InitPoolsFromConfig()   // aborts if the singleton fails to start (default)
   oSrv:Start()
   IF oSrv:hThread != NIL
      hb_threadJoin( oSrv:hThread )
   ENDIF
   HIX_EndPoolsFromConfig()
RETURN
```

### Available fields

| Field | Default | Description |
|-------|---------|-------------|
| `driver` | _(required)_ | `"sqlite3"` (case-insensitive) |
| `file` | `":memory:"` | Path to the `.db` file (relative to the working directory) |
| `create` | `true` | Creates the file if it does not exist; `.F.` fails if it does not exist |
| `journal_mode` | `"WAL"` | `WAL` / `DELETE` / `MEMORY` / `OFF`. WAL = better concurrency |
| `synchronous` | `"NORMAL"` | `FULL` / `NORMAL` / `OFF`. NORMAL = good durability/speed balance |
| `foreign_keys` | `true` | Enables `PRAGMA foreign_keys=ON` |
| `busy_timeout_ms` | `5000` | Maximum wait time if another process has the file locked |
| <a name="pool_size"></a>`pool_size` | `1` | `1` = singleton (one shared connection, mutex per operation); `> 1` = real pool of N connections with reservation per request. See [Transactions § Isolation](transactions.md#transaction-isolation). Added in v2.5.3. |
| `timeout_ms` | `5000` | Pool reservation timeout (only with `pool_size > 1`): if all connections are busy, how long `WDO_Get` waits before returning `NIL` |
| `ping` | `false` | On-acquire ping of the pool (only with `pool_size > 1`): verifies the connection is still alive before handing it to the handler |
| `debug` | `false` | Enables `HIX_Dbg()` globally; writes traces to `dbg.log` |
| `berror` | — | Harbour function name to handle driver errors |
| `dll` | — | Explicit path to `sqlcipher.dll` (overrides automatic resolution) |

SQLCipher fields (optional; ignored if there is no `key` or `key_ref`):

| Field | Default | Description |
|-------|---------|-------------|
| `key` | `""` | Passphrase in plain text. For testing only; use `key_ref` in production |
| `key_ref` | `""` | Key name in `HIX_Keys` (recommended) |
| `cipher_kdf_iter` | `0` | KDF PBKDF2 iterations (0 = SQLCipher default ~256,000) |
| `cipher_page_size` | `0` | Encrypted page size in bytes (0 = default 4096) |
| `cipher_hmac_algorithm` | `""` | `HMAC_SHA512` / `HMAC_SHA1` (`""` = SQLCipher 4.x default) |
| `cipher_kdf_algorithm` | `""` | `PBKDF2_HMAC_SHA512` / `PBKDF2_HMAC_SHA1` (`""` = default) |

### key vs key_ref

!!! warning "Never put the passphrase in plain text in production"
    The `key` field stores the passphrase directly in the JSON. Anyone with access to the configuration file knows the key. Use `key_ref` in production.

`key_ref` points to a key stored in `HIX_Keys`, which is populated from the `keys` section of `www/config.json`:

```json
{
  "keys": {
    "sqlite3": "my-very-secret-32char-passphrase"
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

At startup, `HIX_InitPoolsFromConfig()` resolves `key_ref` → `HIX_KeyGet("sqlite3")` and passes the passphrase to the driver. The value never stays in memory longer than necessary to open the connection.

---

## Method 2 — Programmatic hash

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

Useful when the path or passphrase is read from environment variables or an external vault.

## Method 3 — Positional (legacy)

```harbour
//  WDO_InitSqlite3( cFile, lCreate, bError, cKey )
WDO_InitSqlite3( "data/app.db", .T., NIL, "" )   // no encryption

//  With encryption
WDO_InitSqlite3( "data/secure.db", .T., NIL, "my-passphrase" )
```

Registers the singleton under the key `"SQLITE3"` (uppercase). Compatible with migration scripts prior to v2.5.0.

!!! info "Closing the singleton"
    To close the singleton registered under any key: `WDO_EndSqlite3("APP")` or `WDO_EndSqlite3("SQLITE3")`.

---

## DLLs — SQLCipher and OpenSSL

The driver needs these DLLs on Windows:

| DLL | Function |
|-----|----------|
| `sqlcipher.dll` | SQLite3 + SQLCipher encryption engine |
| `libcrypto-4-x64.dll` | OpenSSL — AES, HMAC, PBKDF2 algorithms |
| `libssl-4-x64.dll` | OpenSSL — TLS (required by libcrypto) |

The three DLLs precompiled for Windows x64 (MinGW64 / OpenSSL 4.x) are in `resources/wdo/sqlite3/dll/`. Copy them alongside the executable or add their directory to `PATH`.

### sqlcipher.dll resolution precedence

The driver searches for the library in this order (highest priority first):

1. **`"dll"` field in `config.json`** — explicit absolute path.
2. **Environment variable `HIX_SQLITE3_DLL`** — absolute path to the file.
3. **Environment variable `WDO_SQLITE3_DLL`** — absolute path to the file.
4. **Executable directory** `hb_DirBase() + "dll\sqlcipher.dll"`.
5. **Executable directory** `hb_DirBase() + "sqlcipher.dll"`.
6. **System PATH** — canonical name `sqlcipher.dll`.

The resolution tag is stored in `oConn:cDllSource` (`"override"`, `"env"`, `"exedir"`, `"default"`) for diagnostics.

### If the DLL is not found

```
==> Error: Cannot load SQLite3 DLL: sqlcipher.dll
```

=== "Option A — alongside the executable"
    Copy the three DLLs to the `dll/` subdirectory alongside the server executable. This is the simplest option and uses `hb_DirBase() + "dll\sqlcipher.dll"`.

=== "Option B — environment variable"
    ```
    set HIX_SQLITE3_DLL=C:\myapp\sqlite3\sqlcipher.dll
    ```

=== "Option C — dll field in config.json"
    ```json
    {
      "databases": {
        "APP": {
          "driver": "sqlite3",
          "dll":    "C:/myapp/sqlite3/sqlcipher.dll",
          ...
        }
      }
    }
    ```

---

## WAL sidecars — backup and tests

!!! warning "WAL creates additional files"
    With `journal_mode=WAL`, SQLite generates two files alongside the `.db`:

    - `app.db-wal` — uncommitted write log
    - `app.db-shm` — shared memory (WAL index)

    **Backup:** copy all three files atomically while the app is not writing, or use the SQLite backup API (`sqlite3_backup_*`).

    **Tests:** when deleting the test DB, also delete the sidecars:

    ```harbour
    FErase( cDb )
    FErase( cDb + "-wal" )
    FErase( cDb + "-shm" )
    ```

    If the connection is closed cleanly (`WDO_EndSqlite3`), SQLite performs an automatic checkpoint and the sidecars become empty or disappear.

---

## Custom error handler

```harbour
FUNCTION MySqliteErrorHandler( oErr, oConn )

   HB_SYMBOL_UNUSED( oConn )

   le( "[SQLite3] " + oErr:description + " @ " + oErr:operation )

   IF HIX_GetRequest() != NIL
      USendError( 500, "DB error: " + oErr:description )
   ENDIF

RETURN NIL
```

Reference it in the JSON:

```json
"berror": "MySqliteErrorHandler"
```

!!! warning "Function requirements"
    Must be a public `FUNCTION` statically linked to the executable. If not found, the driver writes a WARN at startup and uses the default handler (which calls `Break()` and delegates to Harbour's error system).
