# HIX IA -- Testing framework

Declarative HTTP tests for HIX projects. Every skill that generates code is expected to ship one or more `*.test.json` files that prove the generated code runs against a live server.

- Schema: [SCHEMA.md](./SCHEMA.md)
- Runners:
  - [`run-live.ps1`](./run-live.ps1) — **binary-first (canon in v0.2+)**. Runs tests against an already-installed `hix.exe`. No build phase. Used by `/hix-init`, `/hix-add-crud`, `/hix-add-route`, `/hix-add-middleware`.
  - [`run.ps1`](./run.ps1) — source-first (legacy). Compiles a project via `go.bat build`, launches its `app.exe`, then runs tests. Used only by the `/hix-scaffold-source` flow.
- Helpers: [`helpers.ps1`](./helpers.ps1) (shared)
- Meta-tests: [`self-test/`](./self-test/)

---

## Quick start (binary-first — canonical)

```powershell
# 1. Bootstrap an HIX app on top of an existing hix.exe distribution
#    (via /hix-init or apply-template.ps1 project-www + edit hix.json)

# 2. Drop *.test.json files under <hix_root>\tests\
#    e.g. C:\hix\tests\health.test.json

# 3. Run
.\tests\run-live.ps1 -Root C:\hix -Tests C:\hix\tests
```

`run-live.ps1`:

1. Reads `server.port` from `<root>\hix.json` (regex-based — the file may carry `/* ... */` comments).
2. Checks if `hix.exe` is already listening on that port. Reuses it, or starts it in the background.
3. Iterates every `*.test.json` file, sends the HTTP request, compares the response.
4. If it started `hix.exe` itself, stops it at the end. If it reused a running instance, leaves it alone.
5. Exit codes identical to `run.ps1` below.

Pass `-Restart` after adding routes, loaders, or editing `hix.json` (config is read once at boot; controllers/views/models hot-reload without restart).

## Quick start (source-first — legacy)

```powershell
# 1. Scaffold a project (or use an existing one)
.\scripts\apply-template.ps1 -Template project-web-crud -Target C:/tmp/myapp -Name MyApp

# 2. Drop one or more *.test.json files somewhere (see SCHEMA.md)
#    e.g. C:/tmp/myapp/tests/list.test.json

# 3. Run
.\tests\run.ps1 -Project C:/tmp/myapp -Tests C:/tmp/myapp/tests
```

`run.ps1`:

1. Runs `go.bat` (or `-BuildScript <name>`).
2. Picks a free TCP port on the loopback interface.
3. Patches `hix.json` (`server.port`) with that port, then restores the original at the end.
4. Launches the project's `.exe` in the background (hidden window).
5. Polls `http://127.0.0.1:<port>/` until it responds (default timeout 15 s).
6. Iterates every `*.test.json` file, sends the HTTP request, and compares the response.
7. Stops the process (and any orphans) via `Stop-Process` + `taskkill /F /T`.
8. Restores `hix.json`.
9. Exits with `0` on full success, `N` = number of failures otherwise.

---

## `run.ps1` reference

    .\run.ps1 -Project <path> -Tests <path>
              [-Port <n>]           # default: pick a free one
              [-TimeoutMs <n>]      # health-check timeout, default 15000
              [-BuildScript <name>] # default 'go.bat'
              [-SkipBuild]          # do not rebuild before running
              [-KeepRunning]        # leave the server up after tests (debug)

Exit codes:

| Code | Meaning |
|---|---|
| `0` | all tests passed |
| `N > 0` | N tests failed |
| `2` | invalid inputs (missing path, no tests) |
| `3` | build failed / no exe produced |
| `4` | server did not come up within `-TimeoutMs` |

---

## Conventions

- **One test per file**: `<what>.test.json`, e.g. `login-invalid.test.json`.
- **No shared state between tests**: cookies, sessions, DB rows -- do not rely on them. Every test starts from the same fresh server state.
- **No hardcoded ports** in `*.test.json`. The runner supplies the port.
- **UTF-8, no BOM** for `.test.json` files.

---

## Where tests live

Two conventions coexist:

### Skill-owned tests (framework-level)

Ship with the skill definition, prove the skill itself works:

    ia/skills/hix-scaffold/tests/basic.test.json
    ia/skills/hix-add-crud/tests/list.test.json
    ia/skills/hix-add-crud/tests/create.test.json

Each skill's README documents its `run.ps1` invocation.

### Project-owned tests (user-generated)

Live inside the scaffolded project, generated on demand by skills like `hix-add-crud`:

    C:/tmp/myapp/tests/users-list.test.json
    C:/tmp/myapp/tests/users-create.test.json

Run with:

    .\tests\run.ps1 -Project C:/tmp/myapp -Tests C:/tmp/myapp/tests

---

## Troubleshooting

### "Server did not respond on http://127.0.0.1:<port>/ within 15000 ms"

- Confirm the `.exe` runs standalone: `cd <project> && .\app.exe`.
- Increase timeout: `-TimeoutMs 30000`.
- Check `hix.json` -> `server.autostart` is `true`.
- Check `hix.json` -> `paths.log` for startup errors.

### "Build failed"

- Run the build script manually first: `cd <project> && .\go.bat`.
- Confirm Harbour + MSVC are on PATH (see main `INSTALL.md`).

### Orphan `.exe` between runs

- The runner uses `Stop-Process -Force` + `taskkill /F /IM <exe> /T`, which normally clears everything. If it doesn't:

    taskkill /F /IM app.exe /T

- If the port stays busy: pick a different one with `-Port <n>` or wait ~30 s for TIME_WAIT.

### PowerShell says "cannot be loaded because running scripts is disabled"

    powershell.exe -ExecutionPolicy Bypass -File .\tests\run.ps1 -Project ... -Tests ...

Or set per-session:

    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

### Bash on Windows breaks the path

MSYS/Git Bash eats single backslashes in unquoted Windows paths. When invoking `run.ps1` from bash, always use forward slashes or single-quote:

    powershell.exe -File tests/run.ps1 -Project 'C:/tmp/myapp' -Tests 'C:/tmp/myapp/tests'

---

## Not in scope (yet)

See [SCHEMA.md § Not in v1](./SCHEMA.md#not-in-v1-intentionally-out-of-scope).
