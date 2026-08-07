---
description: Add a single HTTP route (controller + routes JSON) to an existing HIX project, then verify it responds. Wraps the hix-add-route skill.
argument-hint: <name> <url> [method]
---

# /hix-add-route

User invocation: `/hix-add-route $ARGUMENTS`

Invoke the **`hix-add-route`** skill.

## Argument parsing

`$ARGUMENTS` is the raw text after `/hix-add-route`. Parse it positionally:

- **Token 1** -> route/CLASS name in PascalCase (required). Examples: `Ping`, `Hello`, `Webhook`.
- **Token 2** -> URL path (required). Must start with `/`. Examples: `/ping`, `/api/webhook`, `/hello/:name`.
- **Token 3** -> HTTP method (optional, default `GET`). One of `GET|POST|PUT|DELETE|PATCH`.

If any required arg is missing or malformed (URL doesn't start with `/`, unknown method), ask the user before invoking. Do not guess.

## What the skill does

Overlays the `module-route` template onto `<cwd>/www/`, renders 2 shipped tests (200-JSON + 405-on-wrong-method), then runs `tests/run.ps1`. Reports OK only when both pass. See `~/.claude/skills/hix-add-route/SKILL.md` for the full contract.

## Post-run

Report exactly as the skill prints it. Route-generation bugs belong in `templates/module-route/` -- do not hand-edit the user's generated files.
