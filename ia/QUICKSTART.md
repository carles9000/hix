# HIX AI System — Quickstart

**5 minutes from zero to a running HIX app with tests verified by Claude.**

## Prerequisites

- Windows 10/11. Developer Mode recommended (allows symlinks without admin).
- [Claude Code](https://claude.com/claude-code) CLI installed and logged in.
- Harbour + HIX installed at `C:\HIX.PROJECT\hix\` (this repo's parent).

## 1. Install (30 s)

```
cd C:\HIX.PROJECT\hix\ia
.\scripts\install.bat C:\tmp\MyFirstApp
```

This:
- Creates `C:\tmp\MyFirstApp\` and its `CLAUDE.md` (with an `@import` to the HIX AI CLAUDE.md).
- Symlinks every `hix-*` skill, agent and command into `~\.claude\`.

Re-run it any time you want to pick up new items — safe and idempotent.

## 2. Scaffold a project (30 s)

```
cd C:\tmp\MyFirstApp
claude
> /hix-scaffold MyFirstApp
```

Claude runs the `project-web-crud` template overlay, verifies `go.bat build` returns exit 0, and reports the file layout. If the build fails, the skill aborts — no half-scaffolded project.

## 3. Add a CRUD resource (1 min)

```
> /hix-add-crud Note
```

Claude overlays the `module-crud` template (7 routes: list / show / create-form / create-post / edit-form / update / delete), renders the 7 shipped `*.test.json` under `tests/` with `Note` substituted for the token, wipes any stale DBF, and runs `tests/run.ps1`. Expected: **7/7 pass, exit 0**. If any test fails, Claude stops and reports the failing assertion verbatim.

## 4. Add a custom endpoint (1 min)

```
> /hix-add-route Ping /ping GET
```

Adds a controller + routes JSON entry, renders 2 tests (200 JSON body + 405 on the wrong method), runs them. Expected: **2/2 pass**.

## 5. Add a middleware (1 min)

```
> /hix-add-middleware RequireApiKey
```

Scaffolds `HixMwRequireApiKey` (denies unless `X-Api-Key` is present), a loader stub that publishes it, a probe controller + route, and 2 tests (401 without header / 200 with header). Expected: **2/2 pass**.

The shipped skeleton is a template — replace the body of `HixMwRequireApiKey()` with your real auth logic. Registration and wiring are already done.

## 6. Verify everything (30 s)

```
> /hix-test
```

Full rebuild + re-run every `*.test.json` under `tests/`. Should still be all green.

## 7. Get a code review (30 s)

```
> /hix-review
```

Invokes the `hix-reviewer` agent (read-only): audits the project against public HIX and Harbour rules (LOCAL placement, `!=` on strings, action string format, `Start()`+join, `USendView` positional args, middleware registration, whitelist ACL, etc.). Findings by severity with `file:line` citations. On a clean project, one-line verdict.

---

## What you have now

- A hixstyle project under `C:\tmp\MyFirstApp\` with:
  - 7 CRUD routes for `Note` at `/notes/*`.
  - A `GET /ping` endpoint.
  - A middleware skeleton ready to gate any route.
- 11 tests, all passing, verified by the runner.
- A `CLAUDE.md` linked to the HIX AI CLAUDE.md so any future Claude session in this project understands the framework.

## Next steps

- Framework depth: `knowledge/en/00_overview.md` (start), then browse `knowledge/en/*.md` (12 topical docs) or `knowledge/es/*.md`.
- Agent capabilities: `claude/agents/README.md` — when to reach for `hix-architect`, `hix-router-expert`, `hix-view-builder`, `hix-reviewer` instead of the commands.
- Extend templates: `templates/README.md` for the token catalog; add your own overlay under `templates/module-<name>/`.
- Add your own skills / commands / agents: `CONTRIBUTING.md`.
- Uninstall: `.\scripts\uninstall.bat C:\tmp\MyFirstApp` — cleans symlinks and restores your project's `CLAUDE.md`.

## Troubleshooting

- **`/hix-scaffold` reports build failure**: check `go.bat` returns exit 0 manually first (`.\go.bat build`). Most common cause is `PATH` missing `%hix%\dll\msvc` — the template already handles this, but a corrupted install may not.
- **`/hix-add-crud` fails on test 3 or 4**: usually a stale DBF from a previous run. The skill wipes `data/<entity>*.dbf` before each run, but if you manually locked the file (open in another process), it can't clear it. `taskkill //F //IM app.exe` and retry.
- **Slash commands don't autocomplete in Claude Code**: re-run `.\scripts\install.bat <project-path>` — the symlinks under `~\.claude\commands\` may not have been created (e.g. first install failed silently).
- **`/hix-review` reports "unknown agent"**: agents symlink didn't take. Same fix as above — re-install.
