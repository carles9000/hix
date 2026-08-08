# hix-run-tests

Thin skill that wraps `tests/run-live.ps1` for use from Claude Code. Runs the
full declarative HTTP test suite of a **binary-first** HIX distribution
(`hix.exe` + `www/` + `tests/`). No build phase — HIX hot-reloads `.prg` on
each request.

## What it does

1. Verifies the target directory is a HIX binary distribution (`hix.exe` +
   `hix.json`).
2. Invokes `tests/run-live.ps1 -Root <path> -Tests <path>/tests`.
3. Formats the runner's exit code and output into a Claude-friendly report.

## What it does NOT do

- Compile anything (there is no source to compile in binary-first mode).
- Generate code.
- Fix failing tests.
- Modify any files under `<root>` or the HIX AI System.

## Invocation

Claude picks up this skill when the user asks to run the tests, verify the
app, or check that a HIX root still works. Wrapped by the `/hix-test` slash
command.

## When to prefer another skill

- Source-first project (`app.hbp` + `go.bat build` + `app.exe`) →
  `hix-compile-and-test`.
- Empty `www/` (never initialised) → `hix-init` first.
- Only adding a CRUD/route/middleware → those skills already invoke
  `run-live.ps1` on their own subset of tests.

## Manual equivalent

```powershell
powershell -File C:\HIX.PROJECT\hix\ia\tests\run-live.ps1 `
    -Root  C:\hix `
    -Tests C:\hix\tests
```

Optional flags: `-TimeoutMs <n>`, `-Restart`, `-KeepRunning`.

## Exit contract

Reports success only when `run-live.ps1` exits 0. Any other code produces a
failure report with the relevant runner output. Same contract as
`hix-compile-and-test`, minus the build phase (no exit code 3).
