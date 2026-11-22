# WDO -- PostgreSQL example

Standalone HIX example that boots the server with a pre-warmed
PostgreSQL connection pool declared under `databases.pg` in
`www/config.json`.

## Requirements at runtime

- `libpq.dll` (plus its OpenSSL/libcurl runtime deps) next to
  `app.exe`.

  The reference DLL ships inside the repo at:

      C:\HIX.PROJECT\hix.pro\resources\wdo\pg\dll\

  Copied automatically next to this `app.exe`:

      libpq.dll            # libpq 18 (dynamic, OpenSSL 4 ABI)
      libcrypto-4-x64.dll  # OpenSSL -- needed by libpq + HIX core
      libssl-4-x64.dll     # OpenSSL -- needed by libpq + HIX core
      libcurl-x64.dll      # HIX core

  Without `libpq.dll`, `app.exe` aborts at startup with a
  DLL-not-found message. The dedupe guard prints the error exactly
  once per `host:port`.

- A reachable PostgreSQL server. Defaults (editable in
  `www/config.json`):

      host=127.0.0.1  user=postgres  pwd=postgres  db=postgres  port=5432

- Most pages self-bootstrap their demo tables (`hix_demo_*`) so no
  pre-loaded dataset is required. Every page drops the table it
  creates on exit, keeping the example idempotent across refreshes.

## Build and run

```
.\go_msvc64.bat          REM Windows / MSVC 64
.\go_mingw64.bat         REM Windows / MinGW 64
./go_gcc.sh              # Linux / gcc
```

Server listens on **http://127.0.0.1:8081** by default.
Browse `/index.html` for the demo index.

## Pages covered

| URL             | Feature                                           |
|-----------------|---------------------------------------------------|
| `/pg0.html`     | Pool connection (`WDO_Get("PG")`)                 |
| `/pg1.html`     | Direct `WDO_PG():New()` instance                  |
| `/pg2.html`     | `Query` / `Fetch_Assoc` / `DbStruct` / `FetchAll` |
| `/pg3.html`     | `Prepare` + `BindParam` (`?`, `:name`, `$N`)      |
| `/pg4.html`     | `Prepare` + loop (bulk insert, re-Execute)        |
| `/pg5.html`     | Transactions (`BeginTrans` / `Transaction(bCode)`)|
| `/pg6.html`     | Server info (`pg_stat_activity`, `pg_settings`)   |
| `/pg7.html`     | TLS (`sslmode` + `pg_stat_ssl`) + `pgcrypto` demo |
