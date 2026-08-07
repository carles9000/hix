# Changelog

All notable changes to the HIX AI System will be documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: aligned with git tags (`ia-vX.Y.Z`)

---

## [Unreleased]

_(no changes yet)_

---

## [0.1.0] — 2026-08-07

First public release. All 8 sessions of the scoped build complete; system exercised end-to-end against a clean scratch project.

### Highlights

- **5 skills** — `hix-scaffold`, `hix-add-crud`, `hix-add-route`, `hix-add-middleware`, `hix-compile-and-test`.
- **6 slash commands** — `/hix-scaffold`, `/hix-add-crud`, `/hix-add-route`, `/hix-add-middleware`, `/hix-test`, `/hix-review`.
- **4 agents** — `hix-architect` (design, read-only), `hix-router-expert` (routes, edit + build/test), `hix-view-builder` (views, edit), `hix-reviewer` (audit, read-only).
- **4 templates** — `project-web-crud`, `module-crud`, `module-route`, `module-middleware`.
- **Declarative test runner** — `*.test.json` schema + `tests/run.ps1` (build, spawn, poll, iterate, teardown, restore `hix.json`; exit 0 = pass, N = failures).
- **Knowledge base** — 24 topical docs (12 EN + 12 ES) covering overview, layout, routing, middleware, controllers, views, models, validation, sessions/auth, hixstyle, `U*` helpers, Harbour rules.
- **Docs** — README + INSTALL + UNINSTALL + CONTRIBUTING + QUICKSTART, all in EN and ES.

### Verified end-to-end

Fresh scratch project at `C:\tmp\hix-e2e-v01\` (2026-08-07):

- `apply-template project-web-crud` → 10 files → `go.bat build` exit 0.
- `apply-template module-crud Note` + `render-tests` (7 tests) → `run.ps1` → **7/7 pass, exit 0**.

Skill-shipped tests verified in prior sessions:

- `hix-add-route Ping /ping GET` → **2/2 pass** (200 JSON + 405 wrong method).
- `hix-add-middleware RequireApiKey` → **2/2 pass** (401 without header + 200 with header).

### Deferred to backlog

- `templates/project-api-class`, `templates/project-api-function` — deferred (S3.5, S3.6); pattern already extensible via `apply-template.ps1`.
- Cursor / Windsurf support, telemetry, additional templates, framework-lint CI, distribution via `hbmk2 -pkg`, migration to standalone `hix-ia` repo (B1–B6).

### Session-by-session detail

### Added — Session 7 (2026-08-07)

- `claude/agents/hix-architect.md` — read-only design agent (tools: Read/Grep/Glob/WebFetch). Turns a fuzzy app description into an ordered list of `/hix-scaffold` + `/hix-add-crud` + `/hix-add-route` + `/hix-add-middleware` invocations, with entity/routes/middleware tables and a risks section. Never scaffolds or edits.
- `claude/agents/hix-router-expert.md` — routing surgeon (tools: Read/Grep/Glob/Bash/Edit/Write). Handles route groups, `:var` regex, middleware chain composition, precedence debug. Proves every change with `go.bat build` + `tests/run.ps1`.
- `claude/agents/hix-view-builder.md` — templates + controller-wiring agent (tools: Read/Write/Edit/Grep/Glob). Ports HTML into `.view.html`, extracts partials, wires positional `@args` correctly. Never touches routes/middleware.
- `claude/agents/hix-reviewer.md` — code-review agent (tools: Read/Grep/Glob only — no Write/Edit/Bash). Walks a checklist of Harbour + HIX public rules (LOCAL placement, `!=` on strings, `hb_UnixTime`, `controllers/METHOD@CLASS.prg` action format, `Start()`+join, `USendView` positional args, MW registration via loaders, whitelist ACL) and outputs findings by severity with `file:line` citations.
- `claude/agents/README.md` — index of the 4 agents with tools/writes-files table, anatomy of an agent (frontmatter fields), design principles (one role per agent, restrict tools by intent, reference public knowledge base), and skill-vs-agent-vs-command decision table.
- `claude/commands/hix-review.md` — slash command that invokes `hix-reviewer` via the `Task` tool. Closes the S6.5 deferred item.
- `claude/commands/README.md` — added `/hix-review` row + "Notes on `/hix-review`" section explaining the agent-vs-skill distinction; removed the `Planned` section.

### Verified — Session 7

- All 5 files created (4 agents + agents README) with valid frontmatter (`name`, `description`, `tools`). The reviewer's tool list is intentionally read-only.
- `/hix-review` frontmatter includes `description` and `argument-hint` consistent with the other command wrappers.
- Interactive smoke test (invoking `Task(subagent_type="hix-architect", ...)` etc. and confirming Claude Code recognises each agent) is a manual step — cannot be automated from within this session.

### Added — Session 6 (2026-08-07)

- `claude/commands/hix-scaffold.md` — one-line slash wrapper around the `hix-scaffold` skill. Frontmatter: `description` + `argument-hint: <project-name>`. Parses `$ARGUMENTS` positionally (token 1 = project name).
- `claude/commands/hix-add-crud.md` — wraps `hix-add-crud`. Argument: `<entity-pascalcase>`. Rejects names with spaces / non-ASCII / leading digit.
- `claude/commands/hix-add-route.md` — wraps `hix-add-route`. Arguments: `<name> <url> [method]`. Enforces URL leading `/` and method ∈ `GET|POST|PUT|DELETE|PATCH`.
- `claude/commands/hix-add-middleware.md` — wraps `hix-add-middleware`. Arguments: `<name> [probe-url]`. Default probe URL is `/__mw_probe_<name_lower>`.
- `claude/commands/hix-test.md` — wraps `hix-compile-and-test`. Argument: `[project-path]` (defaults to cwd; must contain `hix.json`, `www/`, `go.bat`).
- `claude/commands/README.md` — index with command→skill mapping table, examples, "why so thin?" rationale, install instructions, note about the deferred `/hix-review` command.

### Deferred — Session 6

- `/hix-review` — postponed to Session 7. A slash command that targets a non-existent `hix-reviewer` agent would be a dead link, so it will land alongside the agent itself.

### Verified — Session 6

- All 6 files created with valid frontmatter (`description` + `argument-hint`) and consistent structure. Interactive smoke test (typing `/hix-scaffold`, `/hix-add-crud`, etc. in a fresh Claude Code session after `scripts/install.bat`) is a manual step — cannot be automated from within this session.

### Added — Session 5 Tier 2 (2026-08-07)

- `claude/skills/hix-add-route/` — generates a single HTTP route (controller CLASS + routes JSON) in an existing scaffold, renders 2 tests (200-JSON + 405-on-wrong-method), and returns OK only when both pass.
- `claude/skills/hix-add-middleware/` — scaffolds a user-owned middleware (`HixMw<Name>` function + `www/loaders/init_mw_*.prg` stub that `#include`s the MW), a probe controller, a probe route wired with the MW, and 2 tests that assert the MW denies unauthenticated requests (401) and allows authenticated ones (200).
- `templates/module-route/` — 2-file overlay (controller + routes JSON). Tokens: `{{ROUTE_NAME}}`, `{{ROUTE_NAME_LOWER}}`, `{{ROUTE_URL}}`, `{{ROUTE_METHOD}}`. `-RouteMethod` validated against `GET|POST|PUT|DELETE|PATCH`; `-RouteUrl` must start with `/`.
- `templates/module-middleware/` — 4-file overlay (middleware `.prg` + loader stub + probe controller + probe route). Tokens: `{{MIDDLEWARE_NAME}}`, `{{MIDDLEWARE_NAME_LOWER}}`, `{{PROBE_URL}}` (auto-derives to `/__mw_probe_<lower>` when omitted). No JSON is edited -- registration happens through the loader.
- `scripts/apply-template.ps1`: added `-RouteName / -RouteUrl / -RouteMethod / -MiddlewareName / -ProbeUrl` params and a per-template dispatch that computes only the tokens each module template needs.
- `scripts/render-tests.ps1`: same set of new params, gated by whichever token set the caller supplied (route / middleware / entity).

### Fixed — Session 5 Tier 2 (2026-08-07)

- `scripts/apply-template.ps1`: module templates were leaking their own top-level `README.md` into the user's `<project>/www/README.md`. Pre-existed for `module-crud` and would have hit `module-route` / `module-middleware` on their first run. Now skipped alongside `.gitkeep` when kind is `module`.

### Verified — Session 5 Tier 2

- End-to-end (`hix-scaffold RouteE2E` -> `hix-add-route Ping /ping GET` -> `run.ps1`): **2/2 pass, exit 0**. Second test asserts `DELETE /ping` -> 405 (HIX returns 200 for `OPTIONS` due to CORS handling, so wrong-method probe uses `DELETE`).
- End-to-end (`hix-scaffold MwE2E` -> `hix-add-middleware RequireApiKey` -> `run.ps1`): **2/2 pass, exit 0** on first attempt.

### Added — Session 5 Tier 1 (2026-08-07)

- `claude/skills/hix-scaffold/` — rewritten from PoC stub. Wraps `scripts/apply-template.ps1 project-web-crud`, resolves author/date tokens, validates output layout, and asserts the initial `go.bat build` succeeds before returning.
- `claude/skills/hix-add-crud/` — generates a full CRUD module (controller CLASS + function-form model + 3 views + routes JSON + loader `#include`) into an existing scaffold, then renders and runs 7 `*.test.json` (list/show/create-form/create-post-redirect/edit-form/update/delete). Returns OK only when all 7 pass.
- `claude/skills/hix-compile-and-test/` — thin skill that shells out to `go.bat build` and `tests/run.ps1` for any HIX project directory.
- `claude/skills/README.md` — index of installed skills with one-line purpose, invocation snippet, and pointers to the underlying scripts/templates.
- `scripts/render-tests.ps1` — expands `*.test.json.tmpl` under `templates/module-crud/tests/` into concrete `*.test.json` in the target project (token substitution matching `apply-template.ps1`).

### Fixed — Templates and runner (found during Session 5 end-to-end)

- `scripts/apply-template.ps1`: module overlay mode was gated on a stale directory check that skipped copying when the parent scaffold already had `www/`. Rewrote the gate to detect module templates by presence of `models/` + `controllers/` + `views/` in the template root instead.
- `templates/module-crud/routes/{{ENTITY_PLURAL_LOWER}}.json`: action strings must be `controllers/METHOD@CLASS.prg` (with `.prg`), not bare `CLASS@METHOD` — the dispatcher looks up the file on disk.
- `templates/module-crud/controllers/{{ENTITY_LOWER}}.prg`: rewrote as a CLASS with a METHOD list; all `USendView` calls now pass args **positionally** (matching the `@args` line in the view), not as a hash — `hix_view_params.prg:64` confirms positional binding.
- `templates/module-crud/models/{{ENTITY_LOWER}}.prg`: `_Open()` now self-provisions the DBF (creates `data/` + `dbCreate` when missing) because HIX only invokes the single global `USERINIT()` — per-loader `UserInit_XXX` is never called. Update/Delete now wrap `FieldPut`/`dbDelete` in `dbRLock()` / `dbRUnlock()` (RDD refuses writes on unlocked records).
- `templates/module-crud/loaders/init_{{ENTITY_LOWER}}.prg`: reduced to a single `#include '/models/{{ENTITY_LOWER}}.prg'`. The include is what pulls model functions into the compile unit so `hb_hrbLoad` registers them; the previous init procedure never ran.
- `templates/module-crud/views/{{ENTITY_LOWER}}/show.view.html`: removed calls to non-existent `HIX_EscapeHtml()` (grepped `hix.pro/src` — no such function). Uses direct `{{ hRow['name'] }}` interpolation.
- `tests/run.ps1`: `$buildPath` was defined only inside the `if (-not $SkipBuild)` block but referenced later when launching the server — with `-SkipBuild` it was `$null`, producing an empty `cmd /c ""` command. Moved the assignment above the gate.
- `tests/run.ps1`: replaced `Invoke-WebRequest` with raw `[System.Net.HttpWebRequest]` because PS 5.1's `-MaximumRedirection 0` throws `InvalidOperationException` instead of surfacing the 302 response. `AllowAutoRedirect = $false` + explicit `WebException` catch of `$_.Exception.Response` gives clean redirect handling.

### Verified

- End-to-end: `hix-scaffold CrudE2E` -> `hix-add-crud Product` -> `go.bat build` -> `tests/run.ps1` against generated tests -> **7/7 pass, exit 0**.
- Contract enforced: `hix-add-crud` returns failure if any generated test fails.

### Added — Session 4 (2026-08-07)

- `tests/SCHEMA.md` — v1 schema for `*.test.json` (fields: `name`, `request.{method,path,headers,body}`, `expect.{status,content_type_contains,body_contains,body_matches}`). Explicit list of v2 out-of-scope items.
- `tests/run.ps1` — declarative test runner. Builds via `go.bat` (or `-BuildScript`), picks a free port, patches `hix.json`'s `server.port` in place, launches the project `.exe` hidden, polls until alive (`Wait-ForHttp`), iterates every `*.test.json`, sends request and validates status + content-type + body contains/matches, tears down (`Stop-Process` + `taskkill /F /T`), restores `hix.json`. Exit codes: 0 pass, N failures, 2 bad input, 3 build/exe fail, 4 server timeout.
- `tests/helpers.ps1` — `Find-FreePort` (TcpListener port 0), `Wait-ForHttp` (poll with WebException tolerance), `Stop-ProjectExe` (idempotent kill by PID + name), `Get-ProjectExeName` (defaults to `app.exe`), `Set-HixJsonPort` / `Restore-HixJson` (JSON port patch with original restoration).
- `tests/self-test/` — meta-tests (`basic-get.test.json` for `GET /`, `not-found.test.json` for 404) with README explaining how to run against a scaffolded project.
- `tests/README.md` — quick start, `run.ps1` flag reference, exit codes, conventions (one test per file, no shared state, no hardcoded ports, UTF-8 no BOM), where tests live (skill-owned vs project-owned), troubleshooting (timeout, orphan exe, ExecutionPolicy, bash path mangling).

### Fixed — Template `project-web-crud` (found during Session 4 end-to-end)

- `src/app.prg` header comment: `www/**/*.json` inside `/* */` closed the comment prematurely (the `*/` in `**/`). Reworded the description text.
- `src/app.prg`: `Main()` now calls `hb_threadJoin( oServer:hThread )` after `oServer:Start()` — `Start()` is non-blocking, without the join the process exited immediately.
- `go.bat` PATH: added `%hbdir%\dll\msvc64` and `%hix%\dll\msvc` so `app.exe` can find `libcrypto-3-x64.dll`, `libssl-3-x64.dll`, `libcurl.dll`.
- `go.bat` modes: added `go.bat build` (compile only) and `go.bat serve` (launch only, inherits full env). The test runner uses these to compile once and then launch the exe with the correct DLL path.
- `go.bat`: launches `.\app.exe` (not `app.exe`) — cmd.exe does not have `.` on PATH.
- `www/index.html` moved to `www/views/index.html` to match the `home` route in `www/routes/web.json`.

### Verified

- End-to-end: `apply-template.ps1 project-web-crud` -> `run.ps1` against `tests/self-test/` -> **2/2 pass, exit 0**.
- Deliberate-fail test: exit code 1.

### Added — Session 3 (2026-08-06)

- `templates/README.md` — token catalog and usage.
- `templates/project-web-crud/` — minimal hixstyle skeleton (`app.hbp`, `go.bat`, `hix.json`, `src/app.prg`, `www/{config.json,index.html,public/css/style.css,routes/web.json,middlewares/config.json}`, empty `data/`, `controllers/`, `models/`, `views/`, `loaders/`). Tokens: `{{PROJECT_NAME}}`, `{{PROJECT_NAME_LOWER}}`, `{{AUTHOR}}`, `{{DATE}}`, `{{YEAR}}`, `{{HIX_PATH}}`.
- `templates/module-crud/` — 7-route CRUD module (controller + model + 3 views + routes + first-boot DBF loader). Tokens: `{{ENTITY}}`, `{{ENTITY_LOWER}}`, `{{ENTITY_PLURAL_LOWER}}`, `{{DATE}}`, `{{AUTHOR}}`.
- `scripts/apply-template.ps1` — token replacer. Substitutes tokens in file contents AND path segments; auto-fills `{{AUTHOR}}` from `git config user.name`, falls back to `Developer`. ASCII-only per `.ps1` rule. Verified end-to-end with both `project-web-crud` and `module-crud`.

### Added — Session 2 (2026-08-06)

- `knowledge/INDEX.md` — bilingual index of all knowledge docs (EN + ES).
- `knowledge/en/` — 12 docs: `00_overview`, `01_project_layout`, `02_routing`, `03_middleware`, `04_controllers`, `05_views`, `06_models`, `07_validation`, `08_sessions_auth`, `09_hixstyle`, `10_u_helpers_ref`, `11_harbour_rules`.
- `knowledge/es/` — 12 Spanish translations (code identical, prose translated).
- Content sourced from the private `hix.pro/.claude/rules/hix_bible.md`, pruned to the public surface: patterns, rules and gotchas any HIX app author needs.

### Added — Session 1 (2026-08-06)

- `README.es.md` — Spanish version of the README.
- `INSTALL.md` + `INSTALL.es.md` — detailed install guide (EN + ES) with prerequisites, troubleshooting, upgrade.
- `UNINSTALL.md` + `UNINSTALL.es.md` — uninstall guide (EN + ES).
- `CONTRIBUTING.md` + `CONTRIBUTING.es.md` — how to add skills / agents / commands / knowledge / templates.
- `scripts/install.bat` — wrapper that bypasses PowerShell execution policy so users don't need to remember the flag.
- `scripts/uninstall.bat` — same wrapper for uninstall.
- README.md updated to link all new docs and recommend `install.bat` as the entry point.

## [0.0.1] — 2026-08-06 — Proof of Concept

### Added

- Initial directory layout under `hix/ia/`
- Minimal `claude/CLAUDE.md` with base rules for HIX projects
- Minimal `claude/skills/hix-scaffold/SKILL.md` (echo test skill)
- `scripts/install.ps1` — symlink-based installer with copy fallback
- `scripts/uninstall.ps1` — reverse of install
- `README.md` — POC overview and quick-start

### Known limitations

- Only English (EN); Spanish (ES) coming in Session 1.
- Only `hix-scaffold` skill available; more in Session 5.
- No knowledge base yet — Claude relies on training data + this repo's `examples/`.
- No testing framework yet — Session 4.
- Symlinks require Windows Developer Mode or admin PowerShell.
