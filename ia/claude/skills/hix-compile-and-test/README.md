# hix-compile-and-test

Thin skill that wraps `tests/run.ps1` for use from Claude Code. Compiles a
HIX project and runs its declarative HTTP test suite.

## What it does

1. Verifies the target directory looks like a HIX project (`hix.json` +
   `go.bat`).
2. Invokes `tests/run.ps1 -Project <path> -Tests <path>/tests`.
3. Formats the runner's exit code and output into a Claude-friendly report.

## What it does NOT do

- Generate any code.
- Attempt to fix compile errors or failing tests.
- Modify any files under the project or the HIX AI System.

## Invocation

Claude picks up this skill when the user asks to run tests, compile a
project, or verify that a project still works.

## Manual equivalent

```powershell
powershell -File C:\HIX.PROJECT\hix\ia\tests\run.ps1 `
    -Project C:\work\MyApp `
    -Tests   C:\work\MyApp\tests
```

Optional flags: `-TimeoutMs <n>`, `-SkipBuild`, `-KeepRunning`,
`-BuildScript`, `-BuildArgs`, `-ServeArgs`, `-Port <n>`.

## Exit contract

Reports success only when `run.ps1` exits 0. Any other exit code produces a
failure report with the relevant tail of runner output. This is the same
contract as `hix-scaffold` and `hix-add-crud` — they both delegate their
verify step to this same runner.
