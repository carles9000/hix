# HIX Project — Claude Instructions

> This file is auto-generated on install with `{{HIX_ROOT}}` expanded to the actual HIX install path, then imported by the CLAUDE.md at the root of any HIX-powered project.

You are helping the user build a web/API/server application using **HIX**, a Harbour-based web server framework. HIX v0.2 is **binary-first**: users receive `hix.exe` + DLLs + a `www/` folder they scaffold with `/hix-init`. No compilation is required for the default flow.

## Framework location

- HIX source (framework internals, reference only): `{{HIX_ROOT}}\src\`
- HIX examples (patterns to follow): `{{HIX_ROOT}}\examples\`
  - `examples/api/api.class/` — class-based API
  - `examples/api/api.function/` — function-based API
  - `examples/web/crud/` — web CRUD (reference implementation for the `project-web-crud` template)
  - `examples/server/` — standalone server
- HIX docs (human-readable, for reference only): `{{HIX_ROOT}}\site-docs\es\` (Spanish) and `.../en/` (English)
- HIX knowledge base (compact, LLM-optimised): `{{HIX_ROOT}}\ia\knowledge\` — 12 EN + 12 ES docs covering routing, middleware, controllers, views, models, validation, sessions/auth, hixstyle, `U*` helpers, and Harbour rules. Read from here before consulting `site-docs`.

## Fundamental rules

1. **Always use `U*` helpers** in route codeblocks (`USendJson`, `USendHtml`, `USendError`, `UParam`, `UGet`, `UPost`, `UHeader`, `UCookie`, `USession`, `URedirect`, etc.). Never call `oReq:Respond()` directly from a route action — the codeblock closure does not reliably capture `oReq`.
2. **All `LOCAL` declarations must appear at the top** of any FUNCTION/PROCEDURE, before executable code. Harbour will refuse to compile otherwise.
3. **Every new `.prg` file starts with a header** in English (fields: File, Author, Created, Modified, Version, Description, Usage, Notes).
4. **Prefer JSON configuration** (`www/routes/*.json`, `www/middlewares/config.json`, `www/config.json`) over hard-coded Harbour — hixstyle is the default.
5. **String comparison**: use `==`, never `!=`. Reason: Harbour's default `SET EXACT OFF` makes `!=` unreliable for prefixes (`"abc" != "ab"` returns `.F.`).
6. **Timestamps**: use `Int( hb_TToSec( hb_DateTime() ) )` — `hb_UnixTime()` does not exist in HIX and produces a linker error.
7. **Route action strings** always follow `controllers/<method>@<CLASS>.prg` (with the `.prg` suffix, method before class). The dispatcher looks up the file on disk — any other shape fails silently at request time.
8. **User-owned middlewares register via loaders**, not via `www/middlewares/config.json`. Write `www/loaders/init_mw_<name>.prg` with `#include '/middlewares/<name>.prg'`; the JSON file's `setup.*` section is only for the built-in `HIX_Mw*` (session, csrf, cors, ratelimit, methodfilter, jwt).

## Compilation

Binary-first (default): **no compilation**. `hix.exe` recompiles `www/**/*.prg` in memory per request (controllers, models, views) or per boot (`www/loaders/*.prg`, `www/routes/*.json`, `hix.json`). Restart `hix.exe` only after touching those boot-time files.

Source-first (legacy, opt-in via `/hix-scaffold-source`): the user maintains an `app.hbp` + `src/app.prg` + `go.bat` and builds their own `.exe` with `hbmk2`. The AI System does not manage source-first builds — the user runs `go.bat build` by hand.

## Testing (mandatory)

Every route or controller you generate must come with a **`*.test.json`** declarative test. Schema and runner:

- Schema: `{{HIX_ROOT}}\ia\tests\SCHEMA.md`
- Runner: `{{HIX_ROOT}}\ia\tests\run-live.ps1` — reuses or starts `hix.exe`, hits each endpoint, verifies status + content-type + body, then tears down (only if it started the server). Exit codes: `0` all pass, `N` failures, `2` bad input, `4` server timeout.

Never mark a feature as done until its test passes. When a skill scaffolds code, it also renders and runs the shipped tests — the skill only reports OK when the runner returns exit 0.

## Available skills / commands / agents

Loaded automatically from `~/.claude/` after `scripts\install.bat` runs against your project.

**Skills** — `~/.claude/skills/hix-*/SKILL.md`

| Skill                    | Purpose                                              |
|--------------------------|------------------------------------------------------|
| `hix-init`               | Bootstrap `www/` on a HIX binary distribution (default entry point). |
| `hix-add-crud`           | Add a full CRUD module (7 routes + 7 tests) to a project. |
| `hix-add-route`          | Add a single HTTP route + 2 tests.                   |
| `hix-add-middleware`     | Scaffold a `HixMw<Name>` middleware + probe route + 2 tests. |
| `hix-run-tests`          | Run every `*.test.json` against a live `hix.exe`. No build. |
| `hix-scaffold-source`    | Legacy: scaffold a source-first project (`app.hbp` + `go.bat`). |

**Slash commands** — `~/.claude/commands/hix-*.md` (thin wrappers around the skills / agents)

| Command                    | Wraps                            |
|----------------------------|----------------------------------|
| `/hix-init`                | `hix-init`                       |
| `/hix-add-crud`            | `hix-add-crud`                   |
| `/hix-add-route`           | `hix-add-route`                  |
| `/hix-add-middleware`      | `hix-add-middleware`             |
| `/hix-test`                | `hix-run-tests`                  |
| `/hix-review`              | `hix-reviewer` agent             |
| `/hix-scaffold-source`     | `hix-scaffold-source` (legacy)   |

**Agents** — `~/.claude/agents/hix-*.md` (invoked via the `Task` tool with `subagent_type=<name>`)

| Agent                | Role                                                  | Writes files? |
|----------------------|-------------------------------------------------------|---------------|
| `hix-architect`      | Turn a fuzzy app idea into an ordered slash-command plan | No         |
| `hix-router-expert`  | Route groups, `:var` regex, middleware chains         | Yes           |
| `hix-view-builder`   | Build `.view.html` templates and wire controllers     | Yes           |
| `hix-reviewer`       | Audit a project against public HIX/Harbour rules      | No            |

## Typical flow

For a new HIX web app (binary-first), this is the canonical sequence:

```
/hix-init MyApp                       # scaffold www/ against hix.exe, verify /health
/hix-add-crud Note                    # add first CRUD resource, 7/7 tests must pass
/hix-add-crud Tag                     # more resources as needed
/hix-add-route Ping /ping GET         # any non-CRUD endpoint
/hix-add-middleware RequireApiKey     # any user-owned middleware
/hix-test                             # run every test in tests/ against live hix.exe
/hix-review                           # optional final audit against the rule set
```

For anything more elaborate (an app whose shape you're not sure of, complex route composition, view work, code review), invoke the corresponding **agent** via the `Task` tool instead of running commands blind:

- `hix-architect` before `/hix-init` if the app design is fuzzy.
- `hix-router-expert` when routes need groups, regex-constrained `:vars`, or middleware surgery.
- `hix-view-builder` when porting HTML or extracting shared partials.
- `hix-reviewer` (via `/hix-review`) when the user asks for an audit.

## When in doubt

- Read a matching example under `{{HIX_ROOT}}\examples\` first — patterns there are canonical.
- Consult `{{HIX_ROOT}}\ia\knowledge\en\*.md` for schemas and conventions before consulting `site-docs`.
- If the user asks something not covered by the public knowledge base, ask before guessing.
