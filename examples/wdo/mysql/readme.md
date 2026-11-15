# WDO — MySQL example

Standalone HIX example that boots the server with a pre-warmed
MySQL connection pool declared under `databases.mysql` in
`www/config.json`.

## Requirements at runtime

- `libmysql64.dll` **or** `libmariadb64.dll` next to `app.exe`.

  Both DLLs ship inside the repo at:

      C:\HIX.PROJECT\hix.pro\resources\wdo\mysql\dll\

  Copy whichever one your MySQL/MariaDB server uses next to this
  `app.exe`:

      copy ..\..\..\resources\wdo\mysql\dll\libmysql64.dll .

  Without the DLL, `app.exe` aborts at startup with
  `==> Error: Mysql not running (127.0.0.1:3306)` or a DLL-not-found
  message. The dedupe guard prints the error exactly once per
  `host:port`.

- A reachable MySQL/MariaDB server. Defaults (editable in
  `www/config.json`):

      host=127.0.0.1  user=harbour  pwd=hb1234  db=employees  port=3306

## Build and run

```
.\go_msvc64.bat          REM Windows / MSVC 64
.\go_mingw64.bat         REM Windows / MinGW 64
./go_gcc.sh              # Linux / gcc
```

Server listens on **http://127.0.0.1:8081** by default.
Browse `/index.html` for the demo index.
