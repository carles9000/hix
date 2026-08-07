---
name: hix-scaffold
description: Scaffold a new HIX web project from the project-web-crud template. Use when the user asks to create a new HIX project, initialise a HIX web app, or says "new HIX project", "scaffold HIX", "start a HIX web app". Arguments expected - project name (required) and optional target directory. Runs the template applier, copies self-tests, and verifies the scaffolded project builds and answers HTTP.
---

# hix-scaffold — Scaffold a new HIX web project

## When to use

Trigger phrases:

- "create a new HIX project called MyNotes"
- "scaffold a HIX web app named payments"
- "new HIX project"
- "start a HIX web-crud project"

Do NOT use for:
- Adding a CRUD module to an existing project → use `hix-add-crud`.
- Adding a single route or middleware → use `hix-add-route` / `hix-add-middleware`.
- Just compiling / running tests on an existing project → use `hix-compile-and-test`.

## Arguments

Required:
- `name` — project directory name in PascalCase or hyphenated (e.g. `MyNotes`, `payments-api`).

Optional:
- `target` — parent directory. Default: the user's current working directory. The project is created at `<target>/<name>`.
- `author` — override for `{{AUTHOR}}` token. Default: `git config user.name` → `Developer`.
- `hixPath` — override for `{{HIX_PATH}}` token (path to the HIX lib repo). Default: `$env:HIX_PATH` → `c:\HIX.PROJECT\hix.pro`.

If `name` is missing, ask the user before proceeding.

## Pre-flight

1. Resolve `IA_ROOT` — the directory containing this skill's parent tree. Typically `~/.claude/skills/hix-scaffold/../../..` or the install location of the HIX AI System. Use the absolute path stored during install.
2. Verify `IA_ROOT/templates/project-web-crud/` exists. If not, abort with a clear error pointing to `INSTALL.md`.
3. Resolve `<target>/<name>` to an absolute path. If it already exists and is non-empty, ask the user whether to overwrite (translates to `-Force` on the applier).

## Steps

Run each step and report the outcome before continuing to the next. If any step fails, stop and report the exact error.

### 1. Apply the template

Invoke the PowerShell applier via `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`. Use forward-slash paths only where PowerShell tolerates them; otherwise pass backslash Windows paths.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\scripts\apply-template.ps1" `
    -Template project-web-crud `
    -Target  "<absolute-target>\<name>" `
    -Name    "<name>" `
    [-Author "<author>"] `
    [-HixPath "<hixPath>"] `
    [-Force]
```

Expected exit code: 0. Expected stdout tail: `Applied template 'project-web-crud' to <path>` and `Files written: 10 (skipped .gitkeep: N)`.

### 2. Copy self-tests into the new project

Create `<target>/<name>/tests/` if it does not exist, and copy the two files from `IA_ROOT/tests/self-test/`:

- `basic-get.test.json`
- `not-found.test.json`

Do NOT copy `README.md`.

Use a straight file copy (`Copy-Item` or `Read` + `Write`). No token replacement is needed — these tests are literal.

### 3. Build and run the test suite

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\tests\run.ps1" `
    -Project "<absolute-target>\<name>" `
    -Tests   "<absolute-target>\<name>\tests"
```

Exit codes (from `run.ps1`):

| Code | Meaning                        | Action                                                 |
|------|--------------------------------|--------------------------------------------------------|
| 0    | All tests pass                 | Report success, print next steps.                      |
| >0 <2| N tests failed                 | Report the failing test names and their assertions.    |
| 2    | Bad input                      | Report the CLI error verbatim.                         |
| 3    | Build failed                   | Read `<project>/build.log` if present; show tail.      |
| 4    | Server never answered          | Report timeout; suggest bumping `-TimeoutMs`.          |

### 4. Report to the user

On success, print exactly this (substituting values):

```
Scaffolded HIX project: <name>
Location: <absolute-target>\<name>
Files written: 10
Self-tests: 2/2 pass

Next steps:
  cd <absolute-target>\<name>
  .\go.bat            # compile and start the server
  # then open http://localhost:<port>/ in a browser
```

On failure, do not print the "Next steps" block. Print the failing step, the exit code, and the last 20 lines of relevant output.

## Idempotency

If the target directory already contains a project, ask before overwriting. Do not silently overwrite. If the user confirms, pass `-Force` to `apply-template.ps1`.

## Notes for Claude

- Never invent a template that does not live under `IA_ROOT/templates/`. Only `project-web-crud` is supported by this skill in v1.
- Do not edit files under the scaffolded project after the applier runs — the template is the contract. If the user wants changes, they invoke `hix-add-crud` or edit manually.
- Never modify `apply-template.ps1` or `run.ps1` from this skill. They are shared infrastructure.
- If the user is on a non-Windows machine, abort: HIX is Windows-only in v1.
