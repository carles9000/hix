---
description: Run every *.test.json in a HIX binary distribution against a live hix.exe. Wraps the hix-run-tests skill. No build phase.
argument-hint: [root-path] [--restart] [--keep-running]
---

# /hix-test

User invocation: `/hix-test $ARGUMENTS`

Invoke the **`hix-run-tests`** skill.

## Argument parsing

`$ARGUMENTS` is the raw text after `/hix-test`. Parse positionally + flags:

- **Token 1** -> HIX root path (optional, default: cwd). Must contain `hix.exe`, `hix.json`, `tests/`.
- **Flag `--restart`** -> pass `-Restart` to the runner. Required after edits to `www/routes/*.json`, `www/loaders/*.prg` or `hix.json`.
- **Flag `--keep-running`** -> pass `-KeepRunning`. Leaves `hix.exe` alive after the suite ends.
- **Flag `--timeout <ms>`** -> pass `-TimeoutMs <n>`. Default 15000.

If the arg is empty, use the current working directory. If the path is not a valid HIX binary distribution (missing `hix.exe` or `hix.json`), abort with a message pointing to `/hix-init`.

For source-first projects (containing `app.hbp` + `go.bat` + `app.exe`), redirect the user to the legacy `hix-compile-and-test` skill instead.

## What the skill does

Invokes `tests/run-live.ps1 -Root <root> -Tests <root>\tests` -- the runner reads the port from `hix.json`, reuses or starts `hix.exe`, iterates every `*.test.json`, asserts HTTP status / content-type / body, then cleans up. No `go.bat build`, no `hbmk2`. HIX hot-reloads controllers/models/views per request.

Returns the runner's exit code:
- `0` = all pass
- `1..N` = N failures
- `2` = bad input / missing hix.exe or hix.json
- `4` = server did not answer within timeout

See `~/.claude/skills/hix-run-tests/SKILL.md` for the full contract.

## Post-run

Print the runner's `Total / Pass / Fail` block verbatim plus any failure names + assertion errors. Do not paraphrase, do not summarise -- the runner's output is the source of truth.
