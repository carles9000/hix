---
description: Scaffold a user-owned middleware (function + loader stub + probe route) in an existing HIX project, then verify it denies/allows correctly. Wraps the hix-add-middleware skill.
argument-hint: <name> [probe-url]
---

# /hix-add-middleware

User invocation: `/hix-add-middleware $ARGUMENTS`

Invoke the **`hix-add-middleware`** skill.

## Argument parsing

`$ARGUMENTS` is the raw text after `/hix-add-middleware`. Parse positionally:

- **Token 1** -> middleware name in PascalCase (required). The generated function will be `HixMw<Name>`. Examples: `RequireApiKey`, `LogRequest`, `AllowFromOffice`.
- **Token 2** -> probe URL (optional). Must start with `/`. Default: `/__mw_probe_<name_lower>`.

If the name is missing, ask the user before invoking.

## What the skill does

Overlays the `module-middleware` template onto `<cwd>/www/` (middleware `.prg` + loader stub + probe controller + probe route), renders 2 shipped tests, then runs `tests/run.ps1`. Reports OK only when the middleware denies without header (401) and allows with header (200). See `~/.claude/skills/hix-add-middleware/SKILL.md` for the full contract.

## Post-run

Report exactly as the skill prints it. Remind the user that the shipped skeleton denies any request without `X-Api-Key` -- they must replace the body of `HixMw<Name>()` with the real logic. If they want a config-based built-in (`HIX_MwSession`, `HIX_MwCors`, etc.), point them at `~/.claude/skills/../knowledge/en/03_middleware.md` instead -- this command is for user-owned MWs only.
