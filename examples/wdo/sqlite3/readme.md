# WDO — SQLite3 example

Standalone HIX example that registers a shared SQLite3 singleton
connection declared under `databases.sqlite` in `www/config.json`.

## Requirements at runtime

None. SQLite3 is linked statically into `hix_server.lib` via
`hbsqlit3.hbc` — no external DLL to drop in. The demo DB lives at
`www/data/demo.db` (WAL + SHM auto-created on first write).

## Build and run

```
.\go_msvc64.bat          REM Windows / MSVC 64
.\go_mingw64.bat         REM Windows / MinGW 64
./go_gcc.sh              # Linux / gcc
```

Server listens on **http://127.0.0.1:8081** by default.
Browse `/index.html` for the demo index.
