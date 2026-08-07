# HIX AI System -- Slash Commands

Thin wrappers that let the user drive a HIX skill from a single line typed
into a Claude Code session. Every command in this folder just invokes the
skill of the same base name -- the real logic lives in `../skills/`.

## Available commands

| Command                | Skill invoked          | Args                              | One-line purpose                                             |
|------------------------|------------------------|-----------------------------------|--------------------------------------------------------------|
| `/hix-scaffold`        | `hix-scaffold`         | `<project-name>`                  | Create a new HIX web project from `project-web-crud`.        |
| `/hix-add-crud`        | `hix-add-crud`         | `<entity>`                        | Add a full CRUD module (7 routes + 7 tests) to a project.    |
| `/hix-add-route`       | `hix-add-route`        | `<name> <url> [method]`           | Add a single HTTP route + 2 tests.                           |
| `/hix-add-middleware`  | `hix-add-middleware`   | `<name> [probe-url]`              | Scaffold a `HixMw<Name>` middleware + probe route + 2 tests. |
| `/hix-test`            | `hix-compile-and-test` | `[project-path]`                  | Build the project and run all `*.test.json` in `tests/`.     |
| `/hix-review`          | `hix-reviewer` (agent) | `[project-path]`                  | Audit a project against the public HIX/Harbour rule set.     |

## Examples

```
/hix-scaffold MyNotes
/hix-add-crud Product
/hix-add-route Ping /ping GET
/hix-add-middleware RequireApiKey
/hix-test
/hix-review
```

## Why so thin?

Two rules keep drift out of the system:

1. **Commands never duplicate the skill.** They only translate `$ARGUMENTS` into named arguments and hand off. If a command started to describe what the skill does step-by-step, it would rot the moment the skill changed.
2. **Frontmatter carries the discovery bits.** `description` (what it does) and `argument-hint` (what to type) show up in Claude Code's `/` autocomplete. Users see both without opening the file.

## Installation

`scripts/install.ps1` (called by `install.bat`) symlinks every file named
`hix-*` in this folder into `~/.claude/commands/`. To pick up newly added
commands after the first install, re-run `install.bat` -- it re-symlinks
everything (safe, idempotent).

The `README.md` you're reading is NOT installed to `~/.claude/commands/` --
the installer only touches `hix-*` items so it never clobbers the user's
own commands.

## Adding a new command

1. Create `hix-<name>.md` with frontmatter:
   ```
   ---
   description: <one line summary>
   argument-hint: <hint shown in autocomplete>
   ---
   ```
2. Body: parse `$ARGUMENTS`, list required/optional args, name the skill it
   invokes, and (optionally) any post-run reminder for the user.
3. Add a row to the table above.
4. Re-install: `scripts\install.bat`.
5. Verify in a fresh Claude Code session by typing `/hix-<name>` and
   confirming autocomplete + invocation.

## Notes on `/hix-review`

Unlike the other commands, `/hix-review` wraps an **agent** (`hix-reviewer`)
rather than a skill. Agents run in an isolated context with a restricted
tool set — for the reviewer, that means read-only (no `Write`/`Edit`/`Bash`).
The command delegates via the `Task` tool with `subagent_type=hix-reviewer`;
the agent lives under `~/.claude/agents/`. See `claude/agents/README.md`
for the full agent index.
