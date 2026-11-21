# Run the SQLite3 / SQLCipher modules:

1.- Install `sqlcipher.dll` next to `app.exe` (plus its OpenSSL 4 and
    libcurl runtime deps). The reference DLLs ship at:

        C:\HIX.PROJECT\hix.pro\resources\wdo\sqlite3\dll\sqlcipher.dll
        C:\HIX.PROJECT\hix.pro\resources\dll\msvc64\libcrypto-4-x64.dll
        C:\HIX.PROJECT\hix.pro\resources\dll\msvc64\libssl-4-x64.dll
        C:\HIX.PROJECT\hix.pro\resources\dll\msvc64\libcurl-x64.dll

    Optionally override the DLL path via env vars (first match wins):

        set HIX_SQLITE3_DLL=C:\path\to\sqlcipher.dll
        set WDO_SQLITE3_DLL=C:\path\to\sqlcipher.dll

2.- No external server is needed. The demo DB is created at:

        www/data/demo.db

    on the first write. WAL + SHM sidecar files appear alongside it.

    Edit `www/config.json > databases.sqlite` to point at a different
    file, journal mode or page size if needed.

3.- Browse http://127.0.0.1:8081/ to run the demo pages. Every page
    creates and drops its own `hix_demo_*` / `employees_demo` tables,
    so recurring refreshes stay idempotent.

4.- (Optional) To enable SQLCipher transparent encryption, set in
    `www/config.json > databases.sqlite`:

        "key":     "my-passphrase"      <-- literal, dev-friendly
        "key_ref": "sqlite3"            <-- resolve from HIX_Keys

    The first run encrypts the DB file in place (AES-256-CBC + HMAC
    SHA-512 per page). After that `sqlcipher.exe` cannot open it
    without the key. See `.claude/rules/hix_bible.md` §18 for the
    full API reference, including `Rekey` and `GetCipherInfo`.

5.- (Optional) To clear the demo DB, stop the server and delete:

        www/data/demo.db
        www/data/demo.db-wal
        www/data/demo.db-shm
