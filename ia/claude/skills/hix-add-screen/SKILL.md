---
name: hix-add-screen
description: Add a full HTML screen (route + controller + .view.html + 2 HTTP tests) to an existing HIX web project. Use when the user asks to "add a screen", "create a page /path", "make a view at /path", "hazme una pantalla /X", "crea una pagina /X", "anade una vista en /X". Arguments expected - screen name in PascalCase, URL path, optional title, project path (defaults to cwd). Renders 2 parametric HTTP tests and runs them.
---

# hix-add-screen -- Add a complete HTML screen to a HIX project

## When to use

Trigger phrases:

- "add a screen /hello"
- "create a page at /about"
- "make a view at /contact"
- "hazme una pantalla /hello"
- "crea una pagina /about"
- "anade una vista en /contacto"

Do NOT use for:
- JSON endpoints -> use `hix-add-route`.
- Full CRUD with model + list/show/edit -> use `hix-add-crud`.
- Screens with a POST form + validation -> use `hix-add-form` (v0.3.1).
- Middleware skeleton -> use `hix-add-middleware`.
- Creating a new project -> use `hix-init`.

## Arguments

Required:
- `name` -- PascalCase screen/controller class name. Examples: `Hello`, `About`, `Contacto`.
  - Rejects: names with spaces, non-ASCII, starting with a digit.
- `url` -- URL path, must start with `/`. Examples: `/hello`, `/about`, `/contacto`.
  - `:vars` are accepted syntactically (`/user/:id`) but the generated controller ignores them. User edits `Index()` to call `UParam(...)` if needed.

Optional:
- `title` -- text for `<title>` and `<h1>`. Default: `<name>` verbatim.
- `project` -- absolute path to the HIX distribution (the folder that contains `hix.exe`). Default: cwd.
- `author` -- override for `{{AUTHOR}}`. Default: `git config user.name` -> `Developer`.

If `name` or `url` is missing, ask the user before proceeding.

**Inference**: if the user says *"hazme una pantalla /hello"* with no explicit name, derive `name = "Hello"` from the first path segment (PascalCase). Only ask if the path yields no viable token (`/`, `/api/v1/x`, ...).

## Pre-flight

1. Resolve `IA_ROOT`. Verify `IA_ROOT/templates/module-screen/` exists.
2. Resolve `<project>` to an absolute path. Verify it contains `hix.exe`, `hix.json`, `www/`. If any is missing, abort with a message pointing to `/hix-init`.
3. Check the screen files do not already exist. If any of these are present, ask the user before overwriting (they must accept `-Force`):
   - `<project>/www/controllers/<name_lower>.prg`
   - `<project>/www/routes/<name_lower>.json`
   - `<project>/www/views/<name_lower>.view.html`

## Steps

### 1. Apply the `module-screen` template

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\scripts\apply-template.ps1" `
    -Template    module-screen `
    -Target      "<project>\www" `
    -ScreenName  "<name>" `
    -ScreenUrl   "<url>" `
    [-ScreenTitle "<title>"] `
    [-Author "<author>"] `
    [-Force]
```

Expected exit code: 0. Verify:

- `<project>/www/controllers/<name_lower>.prg`
- `<project>/www/routes/<name_lower>.json`
- `<project>/www/views/<name_lower>.view.html`

### 2. Render the screen tests into the project

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\scripts\render-tests.ps1" `
    -Source      "<IA_ROOT>\claude\skills\hix-add-screen\tests" `
    -Target      "<project>\tests" `
    -ScreenName  "<name>" `
    -ScreenUrl   "<url>" `
    [-ScreenTitle "<title>"] `
    -Prefix      "screen-<name_lower>-" `
    [-Force]
```

This copies 2 files, substituting `{{SCREEN_NAME_LOWER}}`, `{{SCREEN_URL}}`, `{{SCREEN_TITLE}}`. The `-Prefix` flag ensures tests from multiple screens coexist (`screen-hello-1-screen-html-200.test.json`, `screen-about-1-screen-html-200.test.json`, ...).

Tests execute in alphabetical order:
- `screen-<name_lower>-1-screen-html-200.test.json` -- `GET <url>` returns 200 with `text/html` and `<h1><title></h1>` in the body.
- `screen-<name_lower>-2-screen-wrong-method.test.json` -- `POST <url>` returns 405 (proves the route is GET-only, not method-agnostic).

### 3. Run tests against the live hix.exe

Adding a new `www/routes/<name_lower>.json` requires a restart -- routes are read at HIX boot.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\tests\run-live.ps1" `
    -Root  "<project>" `
    -Tests "<project>\tests" `
    -Restart
```

Exit codes: 0 = all pass. Otherwise report the failing test names + assertion details and stop -- screen-generation bugs are template bugs and belong in `templates/module-screen/`, not in the user's project.

### 4. Report to the user

On success, print exactly:

```
Added screen: GET <url>  ->  <name_lower>.view.html
Files:        www/controllers/<name_lower>.prg
              www/routes/<name_lower>.json
              www/views/<name_lower>.view.html
Tests:        2 (screen-<name_lower>-*.test.json)
Test run:     2/2 pass
```

## Idempotency

Rerunning with the same name should reproduce the same state. If the controller, routes JSON or view already exists, ask before passing `-Force`. Tests use a `screen-<name_lower>-` prefix so multiple screens never clobber each other's test files.

## Notes for Claude

- Do NOT hand-edit generated files. Bugs live in `templates/module-screen/`.
- Do NOT merge the new route into `web.json`. HIX loads every `www/routes/*.json`, so one file per screen keeps everything additive and reversible.
- The controller is a CLASS with a single `Index()` METHOD (mirrors `module-route`'s style). The route action is `controllers/index@<name_lower>.prg`.
- The view uses the mambo template engine and receives a single `cTitle` variable via `@args`. If the user asks for a richer layout (partials, header/footer, forms), stop and delegate to the `hix-view-builder` agent -- do NOT extend the scaffold in-place.
- If the URL contains `:vars` (e.g. `/user/:id`), the template accepts it but the generated controller ignores them. The user edits `Index()` to add `UParam("id","")` themselves.
- Even when the user says *"just a view, no controller"*, this skill still generates the controller trivially -- HIX requires every route to route through a controller action. The user sees only the view path in the report; the controller stays invisible until they need to add logic.
