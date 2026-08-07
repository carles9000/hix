---
description: Add a full CRUD module (controller + model + views + routes + 7 tests) to an existing HIX project. Wraps the hix-add-crud skill.
argument-hint: <entity-pascalcase>
---

# /hix-add-crud

User invocation: `/hix-add-crud $ARGUMENTS`

Invoke the **`hix-add-crud`** skill.

## Argument parsing

`$ARGUMENTS` is the raw text after `/hix-add-crud`. Parse as:

- **First token** -> entity name (PascalCase, required). Examples: `Product`, `Customer`, `OrderLine`.
  - Reject names with spaces, non-ASCII, or starting with a digit.
- **Remaining tokens** -> ignored. Fields are inferred from the CRUD template (id/name/notes/cts); custom fields are out of scope for v1.

If no entity is given, ask the user before invoking. Do not guess a name from context.

## What the skill does

Overlays the `module-crud` template onto `<cwd>/www/`, renders the 7 shipped tests into `<cwd>/tests/` with an entity prefix, wipes any stale DBF, then runs `tests/run.ps1`. Reports OK only when all 7 tests pass. See `~/.claude/skills/hix-add-crud/SKILL.md` for the full contract.

## Post-run

Report the result exactly as the skill prints it (route list + test summary). If any test fails, do NOT try to auto-fix -- CRUD-generation bugs are template bugs and belong in `templates/module-crud/`, not in the user's project. Surface the failure to the user and stop.
