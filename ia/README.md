# HIX AI System

**Status**: 🟢 v0.2.0 — Binary-first

AI-powered tooling to help you build HIX applications with Claude Code.

**Get started in 5 minutes → [QUICKSTART.md](QUICKSTART.md)** · [ES](QUICKSTART.es.md)

## What is this?

A collection of Claude Code assets (skills, agents, slash commands, knowledge base) that let Claude generate correct, idiomatic HIX code for your project.

HIX v0.2 is **binary-first**: you get `hix.exe` + DLLs + an empty folder, and the AI System scaffolds the `www/` app on top. **No compilation** is needed for the default flow — `hix.exe` recompiles your `.prg` files in memory on each request.

Once installed, you can ask Claude things like:

- *"Initialise a HIX app called MyNotes"*
- *"Add a CRUD module for `Note`"*
- *"Add a route `GET /ping` and a middleware that requires an API key"*
- *"Review this project against HIX best practices"*

Claude scaffolds files, wires them into the running `hix.exe`, and runs declarative HTTP tests against the live server — reporting OK only when every test passes.

## What's in v0.2.0

- **6 skills** — `hix-init` (default), `hix-add-crud`, `hix-add-route`, `hix-add-middleware`, `hix-run-tests`, `hix-scaffold-source` (legacy)
- **7 slash commands** — `/hix-init`, `/hix-add-crud`, `/hix-add-route`, `/hix-add-middleware`, `/hix-test`, `/hix-review`, `/hix-scaffold-source`
- **4 agents** — `hix-architect` (design), `hix-router-expert` (routes), `hix-view-builder` (views), `hix-reviewer` (audit)
- **4 templates** — `project-www` (binary-first), `project-web-crud` (source-first), `module-crud`, `module-route`, `module-middleware`
- **Declarative test runner** — `*.test.json` files verified by `tests/run-live.ps1` against a live `hix.exe`
- **Knowledge base** — 12 EN + 12 ES docs covering routing, middleware, controllers, views, models, validation, sessions/auth, hixstyle, `U*` helpers, Harbour rules

## Requirements

- [Claude Code](https://claude.com/claude-code) CLI installed
- Windows 10/11 with either:
  - **Developer Mode enabled** (recommended, allows symlinks without admin), or
  - Ability to run PowerShell as Administrator (only during install)
- A HIX binary distribution (typically `C:\hix\` with `hix.exe`, `hix.json`, and required DLLs)

Source-first (legacy) additionally needs Harbour + hbmk2 to build your own `.exe`. Not required for the default flow.

## Install

    cd C:\hix\ia          # or wherever you extracted the AI System bundle
    .\scripts\install.bat C:\MyProject

(For details and PowerShell direct invocation see [INSTALL.md](INSTALL.md).)

This will:

1. Symlink `~\.claude\{skills,agents,commands}\hix-*` → the AI System repo (updates via `git pull` propagate instantly).
2. Render `~\.claude\hix-claude-rendered.md` with `{{HIX_ROOT}}` expanded to your actual install path.
3. Create/append `C:\MyProject\CLAUDE.md` with an `@import` to the rendered file.
4. Write `C:\MyProject\.claude\settings.local.json` with the permissions the skills need (PowerShell / Bash / curl), so Claude Code does not prompt for each command.

Then, from the folder that contains `hix.exe`:

    cd C:\hix
    claude
    > /hix-init MyApp
    > /hix-add-crud Note
    > /hix-test

For the full 5-minute walk-through see [QUICKSTART.md](QUICKSTART.md).

## Source-first (legacy)

If you build your own `.exe` linked against `hix_server.lib` (requires Harbour + hbmk2), use:

    > /hix-scaffold-source MyApp

This generates the `app.hbp` + `src/app.prg` + `go.bat` skeleton. From that point on, everything else (`/hix-add-crud`, `/hix-add-route`, `/hix-add-middleware`, `/hix-test`) works the same — but the AI System will not manage your build. You run `go.bat build` on your own before invoking `/hix-test`.

## Architecture (referenced, not copied)

Assets live in this repo (`hix/ia/claude/`) and are **referenced** from your Claude Code user directory (`~/.claude/`) via symlinks. When you `git pull` in this repo, your Claude gets the update instantly — nothing to reinstall (except when the rendered CLAUDE.md itself changes; re-run `install.bat`).

## Uninstall

    cd C:\hix\ia
    .\scripts\uninstall.bat C:\MyProject

See [UNINSTALL.md](UNINSTALL.md) for details.

## Documentation

- [QUICKSTART.md](QUICKSTART.md) — 5-min onboarding (EN) · [ES](QUICKSTART.es.md)
- [INSTALL.md](INSTALL.md) — detailed install guide (EN) · [ES](INSTALL.es.md)
- [UNINSTALL.md](UNINSTALL.md) — uninstall guide (EN) · [ES](UNINSTALL.es.md)
- [CONTRIBUTING.md](CONTRIBUTING.md) — how to add skills / agents / commands (EN) · [ES](CONTRIBUTING.es.md)
- `knowledge/` — knowledge base Claude reads (12 EN + 12 ES topical docs)
- `templates/` — project + module skeletons Claude applies
- `tests/` — declarative test runner + shipped self-tests
- [claude/agents/README.md](claude/agents/README.md) — agent index and design principles
- [claude/commands/README.md](claude/commands/README.md) — slash command index
- [claude/skills/README.md](claude/skills/README.md) — skill index
- [CHANGELOG.md](CHANGELOG.md) — version history
- Español · [README.es.md](README.es.md)

## Verified end-to-end (v0.2.0)

Fresh `C:\hix` install with only `hix.exe` + DLLs:

- `/hix-init MyApp` → `/health` returns 200, no prompts
- `/hix-add-crud Note` → **7/7 tests pass**
- `/hix-add-route Ping /ping GET` → **2/2 tests pass**
- `/hix-add-middleware RequireApiKey` → **2/2 tests pass**
- `/hix-test` full suite → **11/11 tests pass**

## License

Same as HIX — see `../license.md`
