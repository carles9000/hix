# WDO -- SQLite3 / SQLCipher example

Standalone HIX example that registers a shared SQLite3 / SQLCipher
singleton connection declared under `databases.sqlite` in
`www/config.json`.

## Requirements at runtime

- `sqlcipher.dll` (plus its OpenSSL 4 / libcurl runtime deps) next to
  `app.exe`.

  The reference DLL ships inside the repo at:

      C:\HIX.PROJECT\hix.pro\resources\wdo\sqlite3\dll\

  Copied automatically next to this `app.exe`:

      sqlcipher.dll        # SQLite 3.46 + SQLCipher 4.6 (MinGW64 + OpenSSL 4)
      libcrypto-4-x64.dll  # OpenSSL -- needed by SQLCipher + HIX core
      libssl-4-x64.dll     # OpenSSL -- needed by SQLCipher + HIX core
      libcurl-x64.dll      # HIX core

  Without `sqlcipher.dll`, `app.exe` aborts at startup with a
  DLL-not-found message.

- No external server needed. The demo DB lives at
  `www/data/demo.db` (WAL + SHM auto-created on first write). The
  file is plaintext SQLite by default -- see "SQLCipher (optional)"
  below to enable AES-256 transparent encryption.

## Build and run

```
.\go_msvc64.bat          REM Windows / MSVC 64
.\go_mingw64.bat         REM Windows / MinGW 64
./go_gcc.sh              # Linux / gcc
```

Server listens on **http://127.0.0.1:8081** by default.
Browse `/index.html` for the demo index.

## Pages covered

| URL               | Feature                                             |
|-------------------|-----------------------------------------------------|
| `/sqlite0.html`   | Singleton connection (`WDO_Get("SQLITE")`)          |
| `/sqlite1.html`   | Direct `WDO_Sqlite3():New(":memory:")` instance     |
| `/sqlite2.html`   | `Query` / `Fetch_Assoc` / `DbStruct` / `FetchAll`   |
| `/sqlite3.html`   | `Prepare` + `BindParam` (`?`, `:name`, `@name`, `$name`) |
| `/sqlite4.html`   | `Prepare` + loop (bulk insert inside a transaction) |
| `/sqlite5.html`   | Transactions (`BeginTrans` / `Transaction(bCode)`)  |
| `/sqlite6.html`   | Library info (PRAGMAs, sqlite_master, SQLCipher)    |
| `/sqlite7.html`   | SQLCipher `Rekey` + `Rekey("")` refused + `key_ref` |

## SQLCipher (optional)

The example ships in **plaintext** mode so it boots with zero setup.
To try transparent encryption follow the 4-step walkthrough below --
it takes ~15 seconds end-to-end and leaves the DB fully encrypted on
disk.

### Walkthrough

1.- Edit `www/config.json > databases.sqlite` and set a passphrase:

```json
"key": "hix-demo-passphrase"
```

   For production, keep the passphrase out of `databases.sqlite.key`
   and put it under the top-level `keys` block instead; then reference
   it via `key_ref`:

```json
{
  "keys": {
    "sqlite3": "hix-demo-passphrase"
  },
  "databases": {
    "sqlite": {
      "key":     "",
      "key_ref": "sqlite3"
    }
  }
}
```

   `HIX_InitPoolsFromConfig` resolves `key_ref` via `HIX_KeyGet(cRef)`
   at pool bootstrap -- same wire effect as `key`, different source of
   the secret. `/sqlite7.html` walks through this layout plus an
   interactive `Rekey` + decrypt-refused demo.

2.- Wipe any pre-existing plaintext DB -- SQLCipher cannot auto-encrypt
    an already-open file:

```
del www\data\demo.db www\data\demo.db-wal www\data\demo.db-shm
```

3.- Launch the server and hit a couple of pages so a DB gets written:

```
app.exe
curl http://127.0.0.1:8081/sqlite2.html
curl http://127.0.0.1:8081/sqlite3.html
```

4.- Verify the DB is encrypted:

   -  Open `http://127.0.0.1:8081/sqlite6.html` -- section
      **6) SQLCipher info** should report `IsEncrypted: T` and the
      cipher/KDF parameters (expected: `cipher_version 4.6.1`,
      `page_size 4096`, `HMAC_SHA512`, `PBKDF2_HMAC_SHA512`).

   -  Inspect the raw header -- the first 16 bytes of
      `www/data/demo.db` should be random (not the ASCII magic
      `SQLite format 3\0`):

```
C:\> powershell -c "[System.IO.File]::ReadAllBytes('www\data\demo.db')[0..15] | ForEach-Object { '{0:x2}' -f $_ }"
```

   -  Try opening it with the plain `sqlite3.exe` CLI -- it must
      refuse with `file is not a database`.

### Optional tuning knobs

Leave `0` / `""` for SQLCipher defaults
(KDF PBKDF2-HMAC-SHA512, 256 000 iterations, 4096-byte pages,
HMAC-SHA512):

```json
"cipher_kdf_iter":       0,
"cipher_page_size":      0,
"cipher_hmac_algorithm": "",
"cipher_kdf_algorithm":  ""
```

### Reverting to plaintext

Rekeying a cipher DB to an empty key is **not** supported by
SQLCipher (`Rekey("")` returns `.F.` on purpose). To go back to
plaintext, drop the encrypted file and let the example recreate it
with `"key": ""`:

```
del www\data\demo.db www\data\demo.db-wal www\data\demo.db-shm
```

See `.claude/rules/hix_bible.md` §18 for the full API reference
(`Rekey`, `GetCipherInfo`, DLL override env vars, wrong-key
detection flow).
