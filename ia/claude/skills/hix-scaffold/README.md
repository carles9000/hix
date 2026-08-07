# hix-scaffold

Skill that scaffolds a new HIX web project from the `project-web-crud` template
and verifies it builds and answers HTTP.

## What it does

1. Runs `scripts/apply-template.ps1 -Template project-web-crud`.
2. Copies the two self-tests from `tests/self-test/` into `<project>/tests/`.
3. Runs `tests/run.ps1` against the freshly scaffolded project.
4. Reports pass/fail with next-step instructions.

## What it does NOT do

- Add CRUD modules → use `hix-add-crud`.
- Add individual routes / middleware → use `hix-add-route` / `hix-add-middleware`.
- Modify existing projects.

## Invocation

Claude Code picks this skill up when the user asks to create a new HIX project.
The user does not run the skill manually — Claude drives it via the tools
described in `SKILL.md`.

## Manual equivalent

For debugging, the same result can be obtained by hand:

```powershell
# 1. Apply template
powershell -File <IA_ROOT>\scripts\apply-template.ps1 `
    -Template project-web-crud `
    -Target   C:\work\MyApp `
    -Name     MyApp

# 2. Copy self-tests
mkdir C:\work\MyApp\tests
copy <IA_ROOT>\tests\self-test\*.test.json C:\work\MyApp\tests\

# 3. Build + test
powershell -File <IA_ROOT>\tests\run.ps1 `
    -Project C:\work\MyApp `
    -Tests   C:\work\MyApp\tests
```

`<IA_ROOT>` is the install root of the HIX AI System (typically the target of
the symlink `~/.claude/` points to, e.g. `C:\HIX.PROJECT\hix\ia`).

## Tests

`tests/` holds the two self-tests the skill copies into every scaffolded project:

- `basic-get.test.json` — `GET /` returns any body.
- `not-found.test.json` — an unknown path returns 404.

These are duplicated from `<IA_ROOT>/tests/self-test/` so the skill remains
self-contained even if the shared self-tests move.

## Exit contract

The skill reports success only if `run.ps1` exits 0. On any failure it prints
the failing step, the exit code, and up to 20 lines of relevant output — it
does NOT print the "Next steps" block on failure.
