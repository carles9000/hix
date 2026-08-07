# HIX AI System

**Status**: 🟢 v0.1.0 — First public release

AI-powered tooling to help you build HIX applications with Claude Code.

**Get started in 5 minutes → [QUICKSTART.md](QUICKSTART.md)** · [ES](QUICKSTART.es.md)

## What is this?

A collection of Claude Code assets (skills, agents, slash commands, knowledge base) that let Claude generate correct, idiomatic HIX code for your project.

Once installed, you can ask Claude things like:

- *"Create a new HIX project called MyNotes"*
- *"Add a CRUD module for `Note`"*
- *"Add a route `GET /ping` and a middleware that requires an API key"*
- *"Review this project against HIX best practices"*

Claude will scaffold files, generate routes/middleware/controllers/views, and run tests against a live server to verify the endpoints work — reporting OK only when every test passes.

## What's in v0.1.0

- **5 skills** — `hix-scaffold`, `hix-add-crud`, `hix-add-route`, `hix-add-middleware`, `hix-compile-and-test`
- **6 slash commands** — `/hix-scaffold`, `/hix-add-crud`, `/hix-add-route`, `/hix-add-middleware`, `/hix-test`, `/hix-review`
- **4 agents** — `hix-architect` (design), `hix-router-expert` (routes), `hix-view-builder` (views), `hix-reviewer` (audit)
- **4 templates** — `project-web-crud`, `module-crud`, `module-route`, `module-middleware`
- **Declarative test runner** — `*.test.json` files verified by `tests/run.ps1`
- **Knowledge base** — 12 EN + 12 ES docs covering routing, middleware, controllers, views, models, validation, sessions/auth, hixstyle, `U*` helpers, Harbour rules

## Requirements

- [Claude Code](https://claude.com/claude-code) CLI installed
- Windows 10/11 with either:
  - **Developer Mode enabled** (recommended, allows symlinks without admin), or
  - Ability to run PowerShell as Administrator (only during install)
- Harbour + HIX installed at `C:\HIX.PROJECT\hix\` (this repo)

## Install

    cd C:\HIX.PROJECT\hix\ia
    .\scripts\install.bat C:\MyProject

(For details and PowerShell direct invocation see [INSTALL.md](INSTALL.md).)

This will:

1. Create/append `C:\MyProject\CLAUDE.md` with an `@import` to the HIX AI CLAUDE.md.
2. Symlink `~\.claude\skills\hix-*` → `C:\HIX.PROJECT\hix\ia\claude\skills\hix-*` (all HIX skills available in every project).
3. Same for `agents/` and `commands/`.

Then:

    cd C:\MyProject
    claude
    > /hix-scaffold MyApp
    > /hix-add-crud Note
    > /hix-test

For the full 5-minute walk-through see [QUICKSTART.md](QUICKSTART.md).

## Architecture (referenced, not copied)

Assets live in this repo (`hix/ia/claude/`) and are **referenced** from your Claude Code user directory (`~/.claude/`) via symlinks. When you `git pull` in this repo, your Claude gets the update instantly — nothing to reinstall.

## Uninstall

    cd C:\HIX.PROJECT\hix\ia
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

## Verified end-to-end (v0.1.0)

- `/hix-scaffold` + `/hix-add-crud` → **7/7 tests pass**
- `/hix-scaffold` + `/hix-add-route` → **2/2 tests pass**
- `/hix-scaffold` + `/hix-add-middleware` → **2/2 tests pass**

## License

Same as HIX — see `../license.md`
