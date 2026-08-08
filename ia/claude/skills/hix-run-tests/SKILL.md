---
name: hix-run-tests
description: Run the full HIX declarative test suite against a binary-first HIX distribution. Use when the user asks to "run the tests", "test everything", "verify the app", "check if MyApp works", or after manual edits to a HIX root that ships with hix.exe. Arguments - HIX root path (defaults to cwd) and optional tests path (defaults to <root>/tests). NO build phase - HIX hot-reloads .prg on each request. For source-first projects that compile their own .exe, use hix-compile-and-test instead.
---

# hix-run-tests — Run the HIX declarative test suite (binary-first)

## When to use

Trigger phrases:

- "run the tests"
- "test everything"
- "verify the app"
- "check if MyApp still works"
- "run the test suite"

Precondition detection — this skill applies when the target directory contains:
- `hix.exe`
- `hix.json`
- A `tests/` folder with one or more `*.test.json` files

Also use proactively after:
- The user manually edited any `.prg` under `<root>/www/`.
- Another HIX skill (`hix-add-crud`, `hix-add-route`, `hix-add-middleware`) reports it added files but did not run the full suite.

Do NOT use for:
- Creating an app → `hix-init`.
- Adding a CRUD → `hix-add-crud`.
- Source-first projects with `app.hbp` + `go.bat build` → `hix-compile-and-test`.
- Debugging a single failing test — read the `*.test.json` and the target controller directly.

## Arguments

Optional:
- `root` — absolute path to the HIX distribution (folder containing `hix.exe` + `hix.json`). Default: current working directory.
- `tests` — absolute path to the folder containing `*.test.json` files. Default: `<root>/tests`.
- `timeoutMs` — how long to wait for the server to answer HTTP when the runner starts `hix.exe`. Default: 15000. Bump on slow machines or cold cache.
- `restart` — pass `-Restart` to the runner. Kills any running `hix.exe` and relaunches. Required after adding/removing `www/routes/*.json`, `www/loaders/*.prg` or editing `hix.json`. Controllers, models and views hot-reload — no restart needed.
- `keepRunning` — pass `-KeepRunning`. Leaves `hix.exe` alive after the suite ends (useful for manual debugging). Default: cleanup asymmetric — only kill `hix.exe` if the runner started it.

## Pre-flight

1. Resolve `IA_ROOT`. Verify `IA_ROOT/tests/run-live.ps1` exists. If not, abort — the AI System is not installed correctly, point at `INSTALL.md`.
2. Resolve `<root>` to an absolute path. Verify `<root>/hix.exe` and `<root>/hix.json` are present. If not, abort with:
   ```
   Not a HIX binary distribution: <root>
   Missing: hix.exe and/or hix.json.
   Run /hix-init first, or point -root at the folder that contains hix.exe.
   ```
3. Resolve `<tests>`. If the folder does not exist or contains zero `*.test.json` files, abort — nothing to run.

## Steps

### 1. Invoke the runner

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\tests\run-live.ps1" `
    -Root  "<root>" `
    -Tests "<tests>" `
    [-TimeoutMs <n>] `
    [-Restart] `
    [-KeepRunning]
```

The runner handles everything: port discovery from `hix.json` (regex tolerant of `/* */` comments), detect-if-listening, reuse or start `hix.exe`, iterate every `*.test.json`, HTTP request + assertions, cleanup. See `IA_ROOT/tests/run-live.ps1` header for the full contract.

### 2. Interpret the exit code

| Code    | Meaning                            | What to report                                                            |
|---------|------------------------------------|---------------------------------------------------------------------------|
| 0       | All tests pass                     | "N/N pass" and list the test names.                                       |
| 1..N    | N tests failed                     | List failing names + the assertion failure(s) for each.                   |
| 2       | Bad CLI input / missing file       | Verbatim runner error. Point at `/hix-init` if `hix.exe`/`hix.json` missing. |
| 4       | Server never answered              | Suggest `-TimeoutMs` bump; check port collisions; kill stale `hix.exe`.   |

There is no exit code 3 (no build phase).

### 3. Report to the user

On success:

```
Tests: N/N pass  (<tests-path>)

Passed:
  <test 1 name>
  <test 2 name>
  ...
```

On test failures (exit code 1..N):

```
Tests: M/N pass, K failed

Failed:
  <test name> -- <first assertion failure>
  ...
```

On timeout (exit code 4):

```
Server never answered on port <n> within <TimeoutMs> ms.
Suggestions:
  - Bump -TimeoutMs (current: <n>)
  - Check for stale hix.exe processes:  Get-Process hix
  - Confirm the port is free:  netstat -ano | findstr :<n>
  - Try again with --restart to force a clean relaunch.
```

On bad input (exit code 2):

```
<verbatim runner error>

If hix.exe or hix.json is missing, run /hix-init to bootstrap this root.
```

## Notes for Claude

- Do NOT try to fix failing tests. Report them and let the user or a follow-up prompt drive the fix.
- Do NOT modify `run-live.ps1`. It is shared infrastructure — bugs in it belong in the AI system repo, not the user's project.
- If the user asks "why did test X fail?", read `<tests>/<X>.test.json` and the relevant controller/view/route file before guessing.
- Cleanup is asymmetric: if `hix.exe` was already running when the runner started, it is left running at the end. If the runner started it, the runner kills it (unless `--keepRunning`). This is intentional — respect the state the user had.
- Pass `--restart` when the user has changed:
  - `<root>/www/routes/*.json` (added/removed a route file)
  - `<root>/www/loaders/*.prg` (added/removed a loader)
  - `<root>/hix.json`
  Do NOT pass `--restart` for controller/model/view edits — those hot-reload.
- Rerunning is safe. If a port shows still bound after a failure, `Stop-Process -Name hix -Force` clears it.

## Manual equivalent

```powershell
powershell -File C:\HIX.PROJECT\hix\ia\tests\run-live.ps1 `
    -Root  C:\hix `
    -Tests C:\hix\tests
```

Optional flags: `-TimeoutMs <n>`, `-Restart`, `-KeepRunning`.
