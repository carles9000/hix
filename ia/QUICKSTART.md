# HIX AI System — Quickstart

**5 minutes from an empty `hix.exe` folder to a running HIX app with tests verified by Claude.**

## Prerequisites

- Windows 10/11. Developer Mode recommended (allows symlinks without admin).
- [Claude Code](https://claude.com/claude-code) CLI installed and logged in.
- A HIX binary distribution (typically `C:\hix\` containing `hix.exe`, `hix.json`, and the runtime DLLs).

You do **not** need Harbour, `hbmk2`, or any compiler for the default flow. `hix.exe` recompiles your `.prg` files in memory per request.

## 1. Install the AI System (30 s)

```
cd C:\hix\ia
.\scripts\install.bat C:\hix
```

This:
- Symlinks every `hix-*` skill, agent, and command into `~\.claude\`.
- Renders `~\.claude\hix-claude-rendered.md` with your actual HIX root path.
- Creates `C:\hix\CLAUDE.md` with an `@import` to that rendered file.
- Writes `C:\hix\.claude\settings.local.json` with the permissions the skills need (PowerShell / Bash / curl) so Claude Code doesn't prompt on every command.

Re-run any time — safe and idempotent.

## 2. Bootstrap the app (30 s)

```
cd C:\hix
claude
> /hix-init MyFirstApp
```

Claude applies the `project-www` template into `C:\hix\www\`, enables `hixstyle` in `hix.json`, starts `hix.exe` in the background, and verifies `GET http://127.0.0.1:<port>/health` returns 200. If any step fails, the skill aborts with the exact error.

## 3. Add a CRUD resource (1 min)

```
> /hix-add-crud Note
```

Claude overlays the `module-crud` template (7 routes: list / show / create-form / create-post / edit-form / update / delete), renders the 7 shipped `*.test.json` under `tests/` with `Note` substituted for the token, wipes any stale DBF, and runs `tests/run-live.ps1`. Expected: **7/7 pass, exit 0**. If any test fails, Claude stops and reports the failing assertion verbatim.

No restart of `hix.exe` needed — controllers/models/views recompile in memory per request.

## 4. Add a custom endpoint (1 min)

```
> /hix-add-route Ping /ping GET
```

Adds a controller under `www/controllers/` and a routes JSON entry under `www/routes/`, renders 2 tests (200 JSON body + 405 on the wrong method), runs them. Expected: **2/2 pass**.

`www/routes/*.json` is loaded once at boot — Claude passes `--restart` to the runner so `hix.exe` picks up the new route.

## 5. Add a middleware (1 min)

```
> /hix-add-middleware RequireApiKey
```

Scaffolds `HixMwRequireApiKey` (denies unless `X-Api-Key` is present), a loader stub under `www/loaders/` that publishes it, a probe controller + route, and 2 tests (401 without header / 200 with header). Expected: **2/2 pass**.

The shipped skeleton is a template — replace the body of `HixMwRequireApiKey()` with your real auth logic. Registration and wiring are already done.

## 6. Verify everything (30 s)

```
> /hix-test
```

Re-runs every `*.test.json` under `tests/` against the live `hix.exe`. No build phase. Should still be all green (**11/11**). If you touched `hix.json`, `www/routes/*.json`, or `www/loaders/*.prg` since the last run, add `--restart`.

## 7. Get a code review (30 s)

```
> /hix-review
```

Invokes the `hix-reviewer` agent (read-only): audits everything under `www/` against public HIX and Harbour rules (LOCAL placement, `!=` on strings, action string format, `USendView` positional args, middleware registration, whitelist ACL, etc.). Findings by severity with `file:line` citations. On a clean project, one-line verdict.

---

## What you have now

- A hixstyle app under `C:\hix\www\` with:
  - 7 CRUD routes for `Note` at `/notes/*`.
  - A `GET /ping` endpoint.
  - A middleware skeleton ready to gate any route.
- 11 tests, all passing, verified against the live `hix.exe`.
- A `CLAUDE.md` at the project root that any future Claude session automatically loads — with the HIX framework rules baked in.

## Next steps

- Framework depth: `knowledge/en/00_overview.md` (start), then browse `knowledge/en/*.md` (12 topical docs) or `knowledge/es/*.md`.
- Agent capabilities: `claude/agents/README.md` — when to reach for `hix-architect`, `hix-router-expert`, `hix-view-builder`, `hix-reviewer` instead of the commands.
- Extend templates: `templates/README.md` for the token catalog; add your own overlay under `templates/module-<name>/`.
- Add your own skills / commands / agents: `CONTRIBUTING.md`.
- Uninstall: `.\scripts\uninstall.bat C:\hix` — cleans symlinks and restores your project's `CLAUDE.md`.

## Source-first path (legacy)

If you build your own `.exe` linked against `hix_server.lib` (requires Harbour + hbmk2), skip step 2 and use `/hix-scaffold-source MyApp` instead. From step 3 onward the flow is identical, except you run `go.bat build` by hand before `/hix-test` — the AI System does not manage source-first builds.

## Troubleshooting

- **`/hix-init` reports `hix.exe did not open port`**: check `C:\hix\.logs\hix.log`. Most common cause is another process on the configured port (default 80 requires admin on Windows) or `hix.json` `hixstyle.enabled` still `false`. The skill toggles it, but a corrupted JSON may prevent the regex edit.
- **`/hix-add-crud` fails on test 3 or 4**: usually a stale DBF from a previous run. The skill wipes `data/<entity>*.dbf` before each run, but if you manually locked the file (open in another process), it can't clear it. `taskkill //F //IM hix.exe` and retry.
- **Slash commands don't autocomplete in Claude Code**: re-run `.\scripts\install.bat <project-path>` — the symlinks under `~\.claude\commands\` may not have been created (e.g. first install failed silently).
- **`/hix-review` reports "unknown agent"**: agents symlink didn't take. Same fix as above — re-install.
- **PowerShell still prompts for each command**: `install.bat` didn't write `.claude/settings.local.json` (permission error?). Re-run install; the file should list `Bash(powershell.exe *)`, `PowerShell(*)`, `Bash(curl.exe *)` in `permissions.allow`.
