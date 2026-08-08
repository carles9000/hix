---
description: Initialise a HIX binary distribution -- populate www/, enable hixstyle, verify /health. Wraps the hix-init skill. No build phase.
argument-hint: <name> [root-path] [--force] [--restart]
---

# /hix-init

User invocation: `/hix-init $ARGUMENTS`

Invoke the **`hix-init`** skill.

## Argument parsing

`$ARGUMENTS` is the raw text after `/hix-init`. Parse positionally + flags:

- **Token 1** -> app name in PascalCase (required, e.g. `MyNotes`, `Payments`). If missing, ask before proceeding.
- **Token 2** -> HIX root path (optional, default: cwd). Must contain `hix.exe` + `hix.json`.
- **Flag `--force`** -> pass `-Force`. Overwrite `www/config.json` if it already exists.
- **Flag `--restart`** -> pass `-Restart`. If `hix.exe` is already running, kill and relaunch (needed after enabling `hixstyle` or writing new routes).
- **Flag `--author "<name>"`** -> override for `{{AUTHOR}}` token.

Note: this skill does NOT ask about PowerShell / Bash permissions. Those are wired at install time by `install.bat` into `<root>\.claude\settings.local.json`. If you skipped install, expect per-command prompts.

If the path is not a HIX binary distribution (missing `hix.exe` or `hix.json`), abort. For source-first projects that compile their own `.exe`, redirect the user to `/hix-scaffold` (soon `/hix-scaffold-source`).

## What the skill does

1. Applies the `project-www` template into `<root>/www/`.
2. Enables `hixstyle` in `<root>/hix.json` (regex-safe -- preserves comments).
3. Starts or restarts `hix.exe` in background.
4. Verifies `GET http://127.0.0.1:<port>/health` returns 200.

No build. No `hbmk2`. See `~/.claude/skills/hix-init/SKILL.md` for the full contract.

## Post-run

Print the health check result verbatim + the list of files created under `www/`. On failure, do not paraphrase -- report the exact error from the skill.

## Next steps hint

On success, remind the user of the natural progression:

```
Next: /hix-add-crud <Entity>    # add a CRUD module
      /hix-add-route  <Name> <path> <METHOD>
      /hix-test                  # run the full suite
```
