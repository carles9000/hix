---
description: LEGACY / source-first only. Scaffold a HIX project that compiles its own .exe (app.hbp + src/app.prg + go.bat). For the default v0.2 binary-first flow use /hix-init.
argument-hint: <project-name>
---

# /hix-scaffold-source

User invocation: `/hix-scaffold-source $ARGUMENTS`

Invoke the **`hix-scaffold-source`** skill.

## When to use

This is the **legacy / source-first** path. Use only when the user explicitly wants to
build their own `.exe` linked against `hix_server.lib` (requires Harbour + hbmk2).

For the default v0.2 flow (drop `hix.exe` into a folder, scaffold `www/`), redirect
the user to `/hix-init` instead.

## Argument parsing

`$ARGUMENTS` is the raw text the user typed after `/hix-scaffold-source`. Parse it as:

- **First token** -> project name (PascalCase, required). Example: `MyNotes`.
- **Remaining tokens** -> ignored for now. The skill only supports the
  `project-web-crud` template today; do not invent flags.

If no project name is given, ask the user for one before invoking the skill. Do not guess.

## What the skill does

Runs `scripts/apply-template.ps1 -Template project-web-crud -Target <cwd>\<name> -Name <name>`,
then compiles it with `go.bat build` to verify the skeleton is buildable. See
`~/.claude/skills/hix-scaffold-source/SKILL.md` for the full contract.

## Post-run

Report the result back to the user exactly as the skill prints it (file list, build status,
next-step hint). Do NOT paraphrase -- the skill's output is the source of truth.
