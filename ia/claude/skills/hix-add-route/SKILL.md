---
name: hix-add-route
description: Add a single HTTP route (controller + routes JSON) to an existing HIX web project, then verify it responds and does not shadow neighbouring paths. Use when the user asks to "add a route", "create an endpoint", "add a GET/POST /path". Arguments expected - route name in PascalCase, url path, optional method (default GET), and project path (defaults to cwd). Renders 2 parametric HTTP tests and runs them.
---

# hix-add-route -- Add a single route to a HIX project

## When to use

Trigger phrases:

- "add a route GET /ping"
- "create a POST /webhook endpoint"
- "add a route Hello at /hello"

Do NOT use for:
- Full CRUD -> use `hix-add-crud`.
- Middleware skeleton -> use `hix-add-middleware`.
- Creating a new project -> use `hix-init` (binary-first, default) or `hix-scaffold-source` (source-first legacy).

## Arguments

Required:
- `name` -- PascalCase route/controller class name. Examples: `Ping`, `Hello`, `Webhook`.
  - Rejects: names with spaces, non-ASCII, starting with a digit.
- `url` -- URL path, must start with `/`. Examples: `/ping`, `/api/webhook`, `/hello/:name`.

Optional:
- `method` -- HTTP method: `GET|POST|PUT|DELETE|PATCH`. Default `GET`.
- `project` -- absolute path to the HIX distribution (the folder that contains `hix.exe`). Default: cwd. Common value: `C:\hix`.
- `author` -- override for `{{AUTHOR}}`. Default: `git config user.name` -> `Developer`.

If `name` or `url` is missing, ask the user before proceeding.

## Pre-flight

1. Resolve `IA_ROOT`. Verify `IA_ROOT/templates/module-route/` exists.
2. Resolve `<project>` to an absolute path. Verify it contains `hix.exe`, `hix.json`, `www/`. If any is missing, abort with a message pointing to `/hix-init`.
3. Check the route files do not already exist. If any of these are present, ask the user before overwriting (they must accept `-Force`):
   - `<project>/www/controllers/<name_lower>.prg`
   - `<project>/www/routes/<name_lower>.json`

## Steps

### 1. Apply the `module-route` template

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\scripts\apply-template.ps1" `
    -Template   module-route `
    -Target     "<project>\www" `
    -RouteName  "<name>" `
    -RouteUrl   "<url>" `
    -RouteMethod "<method>" `
    [-Author "<author>"] `
    [-Force]
```

Expected exit code: 0. Verify:

- `<project>/www/controllers/<name_lower>.prg`
- `<project>/www/routes/<name_lower>.json`

### 2. Render the route tests into the project

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\scripts\render-tests.ps1" `
    -Source     "<IA_ROOT>\claude\skills\hix-add-route\tests" `
    -Target     "<project>\tests" `
    -RouteName  "<name>" `
    -RouteUrl   "<url>" `
    -RouteMethod "<method>" `
    -Prefix     "route-<name_lower>-" `
    [-Force]
```

This copies 2 files, substituting `{{ROUTE_NAME_LOWER}}`, `{{ROUTE_URL}}`, `{{ROUTE_METHOD}}`. The `-Prefix` flag ensures tests from multiple routes coexist (`route-ping-1-route-ok.test.json`, `route-hello-1-route-ok.test.json`, ...).

Tests execute in alphabetical order:
- `route-<name_lower>-1-route-ok.test.json` -- `<method> <url>` returns 200 with `{"ok":true, ...}`.
- `route-<name_lower>-2-route-wrong-method.test.json` -- `DELETE <url>` returns 405 (proves the route is scoped to `<method>`, not method-agnostic).

### 3. Run tests against the live hix.exe

Adding a new `www/routes/<name_lower>.json` requires a restart -- routes are read at HIX boot.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\tests\run-live.ps1" `
    -Root  "<project>" `
    -Tests "<project>\tests" `
    -Restart
```

Exit codes: 0 = all pass. Otherwise report the failing test names + assertion details and stop -- route-generation bugs are template bugs and belong in `templates/module-route/`, not in the user's project.

### 4. Report to the user

On success, print exactly:

```
Added route: <method> <url>
Files:       www/controllers/<name_lower>.prg
             www/routes/<name_lower>.json
Tests:       2 (route-<name_lower>-*.test.json)
Test run:    2/2 pass
```

## Idempotency

Rerunning with the same name should reproduce the same state. If the controller or routes JSON already exists, ask before passing `-Force`. Tests use a `route-<name_lower>-` prefix so multiple routes never clobber each other's test files.

## Notes for Claude

- Do NOT hand-edit generated files. Bugs live in `templates/module-route/`.
- Do NOT merge the new route into `web.json`. HIX loads every `www/routes/*.json`, so one file per route keeps everything additive and reversible.
- The controller is a CLASS with a single `Index()` METHOD (mirrors `module-crud`'s style). The route action is `controllers/index@<name_lower>.prg`.
- `-Prefix` (used for tests) is separate from the `<name_lower>` used inside filenames -- the prefix prevents clashes across skill invocations, the filename token is what the template ships.
- If the user asks for a URL with `:vars` (e.g. `/hello/:name`), the template accepts it but the generated controller returns a static JSON body. The user can then edit the controller to read `UParam("name","")` themselves -- do not try to auto-generate `:var` handling in this skill (that would drift from the single-file template pattern).
