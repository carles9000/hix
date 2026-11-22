# WDO SQLite3 — Troubleshooting

Diagnostic guide for the most common errors of the SQLite3/SQLCipher driver.

## Symptom → solution map

| Symptom | Go to |
|---------|-------|
| `sqlcipher.dll not found` / DLL fails to load | [§1](#1-dll-not-found) |
| `SQLITE_BUSY` / "database is locked" | [§2](#2-sqlite_busy-database-is-locked) |
| `SQLITE_NOTADB` / "SQLCipher key verification failed" | [§3](#3-wrong-key-sqlite_notadb) |
| Sidecars `-wal` / `-shm` not deleted in tests | [§4](#4-wal-shm-sidecars-in-tests) |
| WARN `RELEASE_RECLAIM` in log | [§5](#5-warn-release_reclaim) |
| `Count()` always returns -1 | [§6](#6-count-returns-1) |
| `Rekey("")` returns `.F.` | [§7](#7-rekey-returns-f-with-empty-string) |

---

## 1. DLL not found

```
==> Error: Cannot load SQLite3 DLL: sqlcipher.dll
```

**Possible causes:**

1. The DLLs are not in any of the searched paths.
2. The `"dll"` field in `config.json` points to an incorrect path.
3. A dependency DLL is missing (`libcrypto-4-x64.dll`, `libssl-4-x64.dll`).
4. Only `sqlcipher.dll` was copied but not its OpenSSL dependencies.

**Solutions:**

=== "Option A — dll/ subdirectory alongside the executable"
    Copy the three DLLs to the `dll/` subdirectory alongside the executable. This is the path the driver looks for by default:

    ```
    myapp/
      myapp.exe
      dll/
        sqlcipher.dll
        libcrypto-4-x64.dll
        libssl-4-x64.dll
    ```

    The DLLs ready to copy are in `resources/wdo/sqlite3/dll/`.

=== "Option B — environment variable"
    ```
    set HIX_SQLITE3_DLL=C:\myapp\sqlite3\sqlcipher.dll
    ```
    The dependency DLLs must be in the same directory or in PATH.

=== "Option C — dll field in config.json"
    ```json
    {
      "databases": {
        "APP": {
          "driver": "sqlite3",
          "dll":    "C:/myapp/sqlite3/sqlcipher.dll"
        }
      }
    }
    ```

To verify which DLL the driver is using at runtime:

```harbour
oSrv:AddRouteGet( "dbinfo", "/dbinfo", {||
   LOCAL oConn := WDO_Get( "APP" )
   IF oConn == NIL ; RETURN USendError( 503, "no singleton" ) ; ENDIF
   USendJson( oConn:GetClientInfo() )
   oConn:Close()
} )
```

`GetClientInfo()` returns `dll_path` and `dll_source` among other fields.

---

## 2. SQLITE_BUSY — database is locked

```
Error WDO/SQLITE_BUSY  database is locked
```

**Possible causes:**

1. Another process (SQLite Browser, a migration script) has the file open with a write lock.
2. Two threads are trying to write simultaneously and `busy_timeout_ms` is too low.
3. A write transaction was left open without `Commit()` or `Rollback()` (transaction leak).

**Solutions:**

**Increase `busy_timeout_ms`** if the problem is write contention between workers:

```json
{
  "databases": {
    "APP": {
      "busy_timeout_ms": 10000
    }
  }
}
```

**Verify no other process has the file open:**

```bash
# Windows — which process has the file open
handle64.exe app.db
```

**Look for transaction leaks** — verify that all handlers that call `BeginTrans()` also call `Commit()` or `Rollback()` on all exit paths, including error paths. Always use `TRY / FINALLY`.

!!! info "WAL reduces but does not eliminate SQLITE_BUSY"
    In WAL mode, multiple readers can coexist with one writer. But if there are two simultaneous writers, the second still waits. `busy_timeout_ms` defines how long it waits before returning an error.

---

## 3. Wrong key — SQLITE_NOTADB

```
==> Error: SQLCipher key verification failed for file: www/data/app.db
```

**Cause:** The passphrase configured in `key` or resolved from `key_ref` does not match the one that encrypted the file.

**This message appears only once per file** (deduplication by path). If you see the message repeated for different paths, there are multiple files with wrong keys.

**Diagnosis:**

1. Verify the value of `key_ref` in the `keys` section of `www/config.json`.
2. If using `key` directly, verify there are no spaces or invisible characters.
3. If the file was created with an older version of SQLCipher (< 4.0), KDF defaults are different — specify `cipher_kdf_iter`, `cipher_hmac_algorithm` and `cipher_kdf_algorithm` explicitly.

**In tests — install bError to prevent the error from escalating:**

```harbour
LOCAL oConn := WDO_Sqlite3():New()
oConn:bError := {| oErr | .T. }   // absorb the error without Break()
oConn:cFile  := "test.db"
oConn:cKey   := "wrong-key"
oConn:Open()

IF ! oConn:lConnect
   ? "Open failed (expected): " + oConn:cError
ENDIF
```

!!! warning "CLASSDATA lShowError INIT .T."
    If `bError` is NIL and `lShowError` is active (the default), an `Open()` with a wrong key calls `Break()` and escalates the error to Harbour's error system. In HIX handlers the dispatcher catches it and returns 500. In unit tests outside the pipeline, install `bError` before `Open()`.

---

## 4. WAL/SHM sidecars in tests

```
// FErase( cDb ) deletes app.db but sidecars remain on disk
```

**Cause:** WAL mode creates `app.db-wal` and `app.db-shm`. If the connection is not closed cleanly (or if there is a transaction without commit), the sidecars contain data and are not deleted.

**Solution — delete all three files:**

```harbour
FErase( cDb )
FErase( cDb + "-wal" )
FErase( cDb + "-shm" )
```

**Better solution — close the singleton before deleting:**

```harbour
WDO_EndSqlite3( "APP" )   // closes cleanly + automatic checkpoint
FErase( cDb )
FErase( cDb + "-wal" )    // normally already empty after checkpoint
FErase( cDb + "-shm" )
```

!!! tip "In-memory DB for tests"
    Unit tests that do not need persistence can use `"file": ":memory:"`. An in-memory DB generates no sidecars, is instantaneous to create/destroy and is isolated between runs.

    ```json
    { "driver": "sqlite3", "file": ":memory:", "create": true }
    ```

---

## 5. WARN RELEASE_RECLAIM

```
WARN  WDO_ReleaseAllThread: reclaiming 1 leaked connection(s) from thread 15432
```

**Cause:** A handler acquired a reference to the singleton with `WDO_Get()` and ran code with the driver mutex acquired (e.g. in the middle of a `Fetch` without finishing) without releasing it. The HIX dispatcher detects the state at the end of the request and forces the release.

**In SQLite3 this is less severe than in MySQL/PG** (there is no pool slot that gets stuck), but it indicates that a statement was not released with `Free()`.

**Solution:** Locate the handler that does not call `oStmt:Free()` and add it in a `FINALLY` block:

```harbour
TRY
   oStmt := oConn:Prepare( "SELECT ..." )
   // ... logic ...
FINALLY
   IF oStmt != NIL ; oStmt:Free() ; ENDIF
   oConn:Close()
END
```

---

## 6. Count() returns -1

```harbour
oStmt := oConn:Query( "SELECT * FROM users" )
? oStmt:Count()   // -1   ← expected behaviour, not a bug
```

**Cause:** SQLite does not know the total number of rows in a SELECT before having iterated all of them. `sqlite3_data_count()` and `sqlite3_column_count()` do not return the row count — only the number of columns.

**This is a fundamental difference from MySQL/PG** where `Count()` returns the number of rows in the resultset.

**Solution — get the total first if needed:**

```harbour
// Get the total
oStmt  := oConn:Query( "SELECT count(*) FROM users" )
aRow   := oStmt:Fetch()
nTotal := Val( aRow[ 1 ] )
oStmt:Free()

// Then get the data
oStmt := oConn:Query( "SELECT * FROM users LIMIT 20" )
aRows := oStmt:FetchAll( .T. )
oStmt:Free()

USendJson( { "total" => nTotal, "data" => aRows } )
```

!!! info "FetchAll and Count()"
    After `FetchAll()`, `oStmt:Count()` still returns -1. `FetchAll` does not store the row count — it returns the array directly. If you need the total, use `Len()` on the resulting array:

    ```harbour
    aRows  := oStmt:FetchAll( .T. )
    nTotal := Len( aRows )
    ```

---

## 7. Rekey() returns .F. with empty string

```harbour
IF ! oConn:Rekey( "" )
   le( "SQLCipher cannot decrypt with empty rekey" )
ENDIF
```

**Cause:** SQLCipher does not support `PRAGMA rekey = ''` to decrypt the file in place. The operation is blocked at the SQLCipher engine level and returns an error.

**Solution — ATTACH + sqlcipher_export process:**

See the [Decrypt an encrypted DB](encryption.md#decrypting-an-encrypted-db) section in the encryption documentation.

---

## Logger messages — quick reference

| Message | Level | Meaning |
|---------|-------|---------|
| `==> Error: Cannot load SQLite3 DLL: ...` | ERROR | The DLL does not exist at the path or `hb_LibLoad` fails |
| `==> Error: SQLCipher key verification failed for file: ...` | ERROR | Wrong passphrase or file not encrypted; `Open()` failed |
| `WDO_LOG_SQLITE3_INIT_FAIL` | ERROR | The singleton could not open at startup |
| `WDO_LOG_SQLITE3_BUSY` | WARN | `sqlite3_step` returned `SQLITE_BUSY` after exhausting `busy_timeout` |
| `WDO_WARN_BERROR_NOT_FOUND` | WARN | The function in the `berror` field is not linked to the executable |
| `WDO_LOG_SQLITE3_INIT` | INFO | Singleton initialised correctly |
| `WDO_LOG_SQLITE3_END` | INFO | Singleton closed correctly on server shutdown |
| `WDO_WARN_RELEASE_RECLAIM` | WARN | Unreleased statement detected and forced by the dispatcher |
