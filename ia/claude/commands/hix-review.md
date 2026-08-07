---
description: Review a HIX project against the framework's public rules (routing, middleware, controllers, views, Harbour gotchas). Delegates to the hix-reviewer agent -- read-only, produces a findings report grouped by severity.
argument-hint: [project-path]
---

# /hix-review

User invocation: `/hix-review $ARGUMENTS`

Invoke the **`hix-reviewer`** agent via the `Task` tool with
`subagent_type=hix-reviewer`.

## Argument parsing

`$ARGUMENTS` is the raw text after `/hix-review`. Parse positionally:

- **Token 1** -> project path (optional, default: cwd). Must contain
  `hix.json`, `www/`, `go.bat` for the agent to proceed. If missing,
  the agent will abort with a pointer to `/hix-scaffold`.

## What the agent does

Reads the project files under `www/` and `src/`, walks a checklist of
public HIX / Harbour rules (LOCAL placement, `!=` on strings,
`hb_UnixTime`, action string format, `Start()`+join, `USendView`
positional args, MW registration via loaders, whitelist ACL, etc.),
and produces a findings report classified as blocker / warning /
suggestion. Read-only: it never edits, builds, or fixes. See
`~/.claude/agents/hix-reviewer.md` for the full contract.

## Post-run

Print the agent's report verbatim. Do not paraphrase, do not add
"looks good overall" — an empty report already means clean. If the
user asks for fixes, that's a separate turn: they can act on the
findings themselves, hand them to `hix-router-expert` / `hix-view-builder`
for specific areas, or open the files directly.
