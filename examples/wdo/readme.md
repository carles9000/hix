# WDO examples

Each driver ships as a self-contained HIX project in its own
subfolder, so you only install the runtime dependencies of the
drivers you actually want to run.

| Driver | Folder | Runtime deps |
|---|---|---|
| MySQL      | [`mysql/`](mysql)     | `libmysql64.dll` or `libmariadb64.dll` next to `app.exe` — ship-ready copies live at `resources/wdo/mysql/dll/` |
| PostgreSQL | [`pg/`](pg)           | `libpq.dll` + OpenSSL next to `app.exe` — ship-ready copies live at `resources/wdo/pg/dll/` |
| SQLite3    | [`sqlite3/`](sqlite3) | `sqlcipher.dll` + OpenSSL next to `app.exe` — ship-ready copies live at `resources/wdo/sqlite3/dll/`. SQLCipher opt-in via `databases.sqlite.key`. |

Each subfolder has its own `app.hbp`, `go_msvc64.bat`,
`go_mingw64.bat`, `go_gcc.sh`, `hix.json`, `src/`, and `www/`.
Follow the subfolder `readme.md` for build / run instructions.

Default listening port is `8081` for every subproject — run them
one at a time, or edit `hix.json` to listen on different ports if
you want to compare side by side.

## Pages covered (identical surface across drivers)

| Page | Feature                                                       |
|------|---------------------------------------------------------------|
| `/*0.html` | Pool / singleton connection (`WDO_Get(...)`)            |
| `/*1.html` | Direct `WDO_*():New()` instance                         |
| `/*2.html` | `Query` / `Fetch_Assoc` / `DbStruct` / `FetchAll`       |
| `/*3.html` | `Prepare` + `BindParam` (`?`, `:name`, driver-specific) |
| `/*4.html` | `Prepare` + loop (bulk insert inside a transaction)     |
| `/*5.html` | Transactions (`BeginTrans` / `Transaction(bCode)`)      |
| `/*6.html` | Server info (version, PRAGMAs / `pg_stat_*` / variables)|
| `/*7.html` | **Encryption**: SQLCipher Rekey (sqlite3) · TLS + pgcrypto (pg) |

MySQL has no `/*7.html` yet — transport encryption is handled by the
server's `require_secure_transport` + libmysql's own TLS flags, both
set at connection string / config level only.

More help: https://carles9000.github.io/hix/wdo/

---

<img width="126" height="126" alt="qr" src="https://github.com/user-attachments/assets/fb06adb3-a2e3-4ff7-bb9e-3a9306f90313" />
