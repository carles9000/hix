---
description: Scaffold a new HIX web project (skeleton, hix.json, go.bat, hixstyle wiring). Wraps the hix-scaffold skill.
argument-hint: <project-name>
---

# /hix-scaffold

User invocation: `/hix-scaffold $ARGUMENTS`

Invoke the **`hix-scaffold`** skill.

## Argument parsing

`$ARGUMENTS` is the raw text the user typed after `/hix-scaffold`. Parse it as:

- **First token** -> project name (PascalCase, required). Example: `MyNotes`.
- **Remaining tokens** -> ignored for now. The scaffold skill only supports the `project-web-crud` template today; do not invent flags.

If no project name is given, ask the user for one before invoking the skill. Do not guess.

## What the skill does

Runs `scripts/apply-template.ps1 -Template project-web-crud -Target <cwd>\<name> -Name <name>`, then compiles it with `go.bat build` to verify the skeleton is buildable. See `~/.claude/skills/hix-scaffold/SKILL.md` for the full contract.

## Post-run

Report the result back to the user exactly as the skill prints it (file list, build status, next-step hint). Do NOT paraphrase -- the skill's output is the source of truth.
