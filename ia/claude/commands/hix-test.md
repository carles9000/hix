---
description: Build the current HIX project and run every *.test.json in its tests/ folder. Wraps the hix-compile-and-test skill.
argument-hint: [project-path]
---

# /hix-test

User invocation: `/hix-test $ARGUMENTS`

Invoke the **`hix-compile-and-test`** skill.

## Argument parsing

`$ARGUMENTS` is the raw text after `/hix-test`. Parse positionally:

- **Token 1** -> project path (optional, default: cwd). Must contain `hix.json`, `www/`, `go.bat`.

If the arg is empty, use the current working directory. If the path is not a valid HIX project (missing required files), abort with a message pointing to `/hix-scaffold`.

## What the skill does

Runs `go.bat build` in `<project>` and then `tests/run.ps1 -Project <project> -Tests <project>\tests`. Returns the runner's exit code (0 = all pass, N = N failures, 3 = build failed, 4 = server did not answer). See `~/.claude/skills/hix-compile-and-test/SKILL.md` for the full contract.

## Post-run

Print the runner's `Total / Pass / Fail` block verbatim plus any failure names + assertion errors. Do not paraphrase, do not summarise -- the runner's output is the source of truth.
