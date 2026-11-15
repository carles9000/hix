# WDO examples

Each driver ships as a self-contained HIX project in its own
subfolder, so you only install the runtime dependencies of the
drivers you actually want to run.

| Driver | Folder | Runtime deps |
|---|---|---|
| MySQL  | [`mysql/`](mysql)     | `libmysql64.dll` or `libmariadb64.dll` next to `app.exe` — ship-ready copies live at `resources/wdo/mysql/dll/` |
| SQLite3 | [`sqlite3/`](sqlite3) | None (statically linked via `hbsqlit3.hbc`) |

Each subfolder has its own `app.hbp`, `go_msvc64.bat`,
`go_mingw64.bat`, `go_gcc.sh`, `hix.json`, `src/`, and `www/`.
Follow the subfolder `readme.md` for build / run instructions.

Default listening port is `8081` for every subproject — run them
one at a time, or edit `hix.json` to listen on different ports if
you want to compare side by side.

More help: https://carles9000.github.io/hix/wdo/

---

<img width="126" height="126" alt="qr" src="https://github.com/user-attachments/assets/fb06adb3-a2e3-4ff7-bb9e-3a9306f90313" />
