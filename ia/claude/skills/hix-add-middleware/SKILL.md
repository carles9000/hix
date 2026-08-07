---
name: hix-add-middleware
description: Scaffold a user-owned middleware (function HixMwName + loader stub + probe controller + probe route) in an existing HIX web project, then verify with 2 HTTP tests that the middleware denies unauthenticated requests and allows authenticated ones. Use when the user asks to "add a middleware", "generate an auth guard", "create a middleware skeleton". Arguments expected - middleware name in PascalCase, optional probe URL, and project path (defaults to cwd).
---

# hix-add-middleware -- Scaffold a middleware in a HIX project

## When to use

Trigger phrases:

- "add a middleware RequireApiKey"
- "generate an auth guard middleware"
- "scaffold a middleware for rate limiting"

Do NOT use for:
- Registering a built-in `HIX_Mw*` (session, csrf, cors, ratelimit, methodfilter, jwt) -> edit `www/middlewares/config.json > setup` instead. See `knowledge/en/03_middleware.md`.
- A route without middleware -> use `hix-add-route`.

## Arguments

Required:
- `name` -- PascalCase middleware name. The generated function will be `HixMw<name>`. Examples: `RequireApiKey`, `LogRequest`, `AllowFromOffice`.

Optional:
- `probe_url` -- URL for the probe route. Default: `/__mw_probe_<name_lower>`. Must start with `/`.
- `project` -- absolute path to the target HIX project. Default: cwd.
- `author` -- override for `{{AUTHOR}}`. Default: `git config user.name` -> `Developer`.

If `name` is missing, ask the user before proceeding.

## Pre-flight

1. Resolve `IA_ROOT`. Verify `IA_ROOT/templates/module-middleware/` exists.
2. Resolve `<project>` to an absolute path. Verify it contains `hix.json`, `www/`, `go.bat`. If any is missing, abort with a message pointing to `hix-scaffold`.
3. Check the module files do not already exist. If any of these are present, ask the user before overwriting (they must accept `-Force`):
   - `<project>/www/middlewares/<name_lower>.prg`
   - `<project>/www/loaders/init_mw_<name_lower>.prg`
   - `<project>/www/controllers/<name_lower>_probe.prg`
   - `<project>/www/routes/mw_<name_lower>_probe.json`

## Steps

### 1. Apply the `module-middleware` template

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\scripts\apply-template.ps1" `
    -Template       module-middleware `
    -Target         "<project>\www" `
    -MiddlewareName "<name>" `
    [-ProbeUrl "<probe_url>"] `
    [-Author "<author>"] `
    [-Force]
```

Expected exit code: 0. Verify all 4 files exist after the run.

### 2. Render the middleware tests into the project

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\scripts\render-tests.ps1" `
    -Source         "<IA_ROOT>\claude\skills\hix-add-middleware\tests" `
    -Target         "<project>\tests" `
    -MiddlewareName "<name>" `
    [-ProbeUrl "<probe_url>"] `
    -Prefix         "mw-<name_lower>-" `
    [-Force]
```

This copies 2 files, substituting `{{MIDDLEWARE_NAME}}` and `{{PROBE_URL}}`. The `-Prefix` flag isolates multiple middleware invocations.

### 3. Build and run tests

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\tests\run.ps1" `
    -Project "<project>" `
    -Tests   "<project>\tests"
```

Tests execute in alphabetical order:
- `mw-<name_lower>-1-probe-denies.test.json` -- expect 401.
- `mw-<name_lower>-2-probe-allows.test.json` -- send `X-Api-Key: any-value`, expect 200.

### 4. Report to the user

On success, print exactly:

```
Added middleware: HixMw<name>
Files:            www/middlewares/<name_lower>.prg
                  www/loaders/init_mw_<name_lower>.prg
                  www/controllers/<name_lower>_probe.prg
                  www/routes/mw_<name_lower>_probe.json
Probe route:      GET <probe_url>
Tests:            2 (mw-<name_lower>-*.test.json)
Test run:         2/2 pass
```

Follow up with a note: the shipped skeleton denies any request without an `X-Api-Key` header -- the user is expected to replace the body of `HixMw<name>()` with the real check.

## Idempotency

Rerunning with the same name should reproduce the same state. If any of the 4 module files already exist, ask before passing `-Force`.

## Notes for Claude

- No JSON is edited. Registration happens via `www/loaders/init_mw_<name_lower>.prg`, which `#include`s the MW `.prg` so `HIX_Loaders()` publishes its public function globally at boot. Router resolves the `"middleware": "HixMw<name>"` string in the route JSON by macro expansion once the symbol is registered.
- The probe route uses a `__mw_probe_` prefix to avoid clashing with real app routes. Users can delete it once they wire the MW into real routes.
- The default `X-Api-Key` check is a placeholder. Do not hand-edit the generated file to add real logic during scaffold -- ask the user what the middleware should do, then let them edit it (or run a follow-up skill / manual edit).
- If the user wants a middleware factory / configurable MW, that is a different pattern (`HixMw<Name>Factory` returning a codeblock). Not in scope of this skill -- point them at `knowledge/en/03_middleware.md`.
