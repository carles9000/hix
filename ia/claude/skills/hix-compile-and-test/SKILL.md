---
name: hix-compile-and-test
description: Compile a HIX project and run its declarative HTTP test suite. Use when the user asks to "run the tests", "compile and test", "check if the project still works", "verify HIX project", or after any manual edit to a HIX project's src/, www/, or config. Arguments expected - project path (defaults to cwd) and optional tests path (defaults to <project>/tests). Reports compile errors and per-test pass/fail.
---

# hix-compile-and-test — Build a HIX project and run its tests

## When to use

Trigger phrases:

- "run the tests"
- "compile and test this project"
- "check if MyApp still works"
- "verify the HIX project"
- "run the test suite"

Also use proactively after:
- The user manually edited any `.prg` under a HIX project.
- Another HIX skill (`hix-add-crud`, `hix-add-route`, ...) reports it added
  files without running tests.

Do NOT use for:
- Creating a project → use `hix-scaffold`.
- Adding a CRUD → use `hix-add-crud`.
- Debugging a specific compile error (use `Read` + `Grep` on the build log).

## Arguments

Optional:
- `project` — absolute path to the HIX project. Default: current working
  directory. Must contain `hix.json` and `go.bat`.
- `tests` — absolute path to the folder containing `*.test.json` files.
  Default: `<project>/tests`.
- `timeoutMs` — how long to wait for the server to start answering HTTP.
  Default: 30000. Bump for cold builds on slow machines.
- `skipBuild` — pass `-SkipBuild` to `run.ps1`. Only use when you already
  built manually and want to re-run tests without recompiling.

## Pre-flight

1. Resolve `IA_ROOT`. Verify `IA_ROOT/tests/run.ps1` exists.
2. Resolve `<project>` to an absolute path. Verify `hix.json` and `go.bat`
   are present. If not, abort with a message pointing to `hix-scaffold`.
3. Resolve `<tests>`. If the folder does not exist or contains zero
   `*.test.json` files, abort — nothing to run.

## Steps

### 1. Invoke the runner

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\tests\run.ps1" `
    -Project   "<project>" `
    -Tests     "<tests>" `
    [-TimeoutMs <n>] `
    [-SkipBuild]
```

### 2. Interpret the exit code

| Code    | Meaning                    | What to report                                          |
|---------|----------------------------|---------------------------------------------------------|
| 0       | All tests pass             | "N/N pass" and list the test names.                     |
| 1..N    | N tests failed             | List failing names + first assertion failure per test.  |
| 2       | Bad CLI input              | Verbatim runner error.                                  |
| 3       | Build failed               | Show tail of `<project>/build.log` if present.          |
| 4       | Server never answered      | Suggest bumping `-TimeoutMs`; check port collisions.    |

### 3. Report to the user

On success:

```
Build:     OK
Tests:     N/N pass (<tests-path>)

Passed:
  <test 1 name>
  <test 2 name>
  ...
```

On test failures (exit code 1..N):

```
Build:     OK
Tests:     M/N pass, K failed

Failed:
  <test name> -- <first assertion that failed>
  ...
```

On build failure (exit code 3):

```
Build FAILED for <project>
Runner exit code: 3

<last 20 lines of build output>
```

On timeout (exit code 4):

```
Server never answered on port <n> within <TimeoutMs> ms.
Suggestions:
  - Bump -TimeoutMs (current: <n>)
  - Check for stale <exe> processes (Get-Process app.exe)
  - Confirm the port is free (netstat -ano | findstr :<n>)
```

## Notes for Claude

- Do NOT try to fix compile errors from this skill. Report them and let the
  user or a follow-up prompt drive the fix.
- Do NOT modify `run.ps1`. It is shared infrastructure — bugs in it belong
  in the AI system repo, not the user's project.
- If the user asks "why did test X fail?", first read the test file
  (`<tests>/<X>.test.json`) and the relevant controller/view before
  guessing.
- Rerunning is safe: `run.ps1` picks a fresh port every time and cleans up
  after itself. If the port shows as still bound, kill orphan processes
  with `Stop-Process -Name app` before retrying.
