---
name: hix-add-crud
description: Add a full CRUD module (controller, model, 3 views, routes, first-boot loader) to an existing HIX web project, and verify all 7 CRUD routes work end-to-end. Use when the user asks to "add a CRUD for X", "scaffold a resource X", "generate a model X", "add entity X". Arguments expected - project path (defaults to cwd) and entity name in PascalCase (e.g. Product, Customer). Creates 7 parametric HTTP tests and runs them.
---

# hix-add-crud — Add a CRUD module to a HIX project

## When to use

Trigger phrases:

- "add a CRUD for Product"
- "scaffold a Customer resource in this project"
- "generate a Product model with views"
- "add an Order entity"

Do NOT use for:
- Creating a new project → use `hix-init` (binary-first, default) or `hix-scaffold-source` (source-first legacy).
- Adding a single non-CRUD route → use `hix-add-route`.

## Arguments

Required:
- `entity` — PascalCase entity name. Examples: `Product`, `Customer`, `OrderLine`.
  - Rejects: names with spaces, non-ASCII characters, or starting with a digit.

Optional:
- `project` — absolute path to the HIX distribution (the folder that contains `hix.exe`). Default: the user's current working directory. Common value: `C:\hix`.
- `author` — override for `{{AUTHOR}}`. Default: `git config user.name` → `Developer`.

If `entity` is missing, ask the user before proceeding.

## Pre-flight

1. Resolve `IA_ROOT`. Verify `IA_ROOT/templates/module-crud/` exists.
2. Resolve `<project>` to an absolute path. Verify it contains:
   - `hix.exe`
   - `hix.json`
   - `www/` directory
   If any is missing, abort with a message pointing to `/hix-init`.
3. Check the module does not already exist. If any of the following are present, ask the user before overwriting (they must accept `-Force`):
   - `<project>/www/controllers/<entity_lower>.prg`
   - `<project>/www/models/<entity_lower>.prg`
   - `<project>/www/routes/<entity_lower>.json`
   - `<project>/www/views/<entity_lower>/`
4. Ensure `<project>/data/` exists. Create it if not (the model needs it for DBF storage).

## Steps

### 1. Apply the `module-crud` template

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\scripts\apply-template.ps1" `
    -Template module-crud `
    -Target  "<project>\www" `
    -Entity  "<entity>" `
    [-Author "<author>"] `
    [-Force]
```

Expected exit code: 0. Expected stdout tail: `Files written: 6` (controller, model, routes JSON, 3 views; `loaders/init_<entity>.prg` also copied when its subfolder is present in the template). Verify the following files exist after the run:

- `<project>/www/controllers/<entity_lower>.prg`
- `<project>/www/models/<entity_lower>.prg`
- `<project>/www/routes/<entity_lower>.json`
- `<project>/www/views/<entity_lower>/list.view.html`
- `<project>/www/views/<entity_lower>/edit.view.html`
- `<project>/www/views/<entity_lower>/show.view.html`
- `<project>/www/loaders/init_<entity_lower>.prg` (if present in template)

### 2. Render the CRUD tests into the project

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\scripts\render-tests.ps1" `
    -Source "<IA_ROOT>\claude\skills\hix-add-crud\tests" `
    -Target "<project>\tests" `
    -Entity "<entity>" `
    -Prefix "<entity_lower>-" `
    [-Force]
```

This copies 7 files, substituting `{{ENTITY}}`, `{{ENTITY_LOWER}}`, and `{{ENTITY_PLURAL_LOWER}}` in both file names and JSON content. The `-Prefix` flag ensures tests from multiple entities can coexist (`product-1-list-empty.test.json`, `customer-1-list-empty.test.json`, ...).

### 3. Ensure a fresh data slate for this entity

The tests assume the store call in step 3 produces id=1. If a previous run left rows in `<project>/data/<entity_plural_lower>.dbf`, ids will collide.

Delete the DBF + index if they exist before running the tests:

- `<project>/data/<entity_plural_lower>.dbf`
- `<project>/data/<entity_plural_lower>.cdx`

The template's first-boot loader (`init_<entity_lower>.prg`) will recreate them empty when the server starts.

### 4. Run tests against the live hix.exe

The CRUD adds a new `www/routes/<entity_lower>.json` and a `www/loaders/init_<entity>.prg` — both are read only at HIX boot. Pass `-Restart` so the runner kills and relaunches `hix.exe` before probing.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\tests\run-live.ps1" `
    -Root  "<project>" `
    -Tests "<project>\tests" `
    -Restart
```

Exit codes (from `run-live.ps1`):

| Code | Meaning                        |
|------|--------------------------------|
| 0    | All tests pass                 |
| >0<2 | N tests failed                 |
| 2    | Bad input                      |
| 4    | Server never answered          |

Tests execute in filename order (`Get-ChildItem` alphabetical), so `1-list-empty` → `2-create-form` → `3-store` → `4-show` → `5-edit-form` → `6-update` → `7-delete`. This ordering is required — the `show`/`edit`/`update`/`delete` tests all target the id produced by `store`.

### 5. Report to the user

On success, print exactly:

```
Added CRUD module: <entity> (7 files under www/)
Tests rendered:    7 (<entity_lower>-*.test.json)
Test run:          7/7 pass

Routes now available:
  GET  /<entity_plural_lower>
  GET  /<entity_plural_lower>/create
  POST /<entity_plural_lower>/store
  GET  /<entity_plural_lower>/:id
  GET  /<entity_plural_lower>/:id/edit
  POST /<entity_plural_lower>/:id/update
  POST /<entity_plural_lower>/:id/delete
```

On failure, list which of the 7 tests failed and their assertion failures, then stop. Do not attempt to auto-repair — CRUD-generation bugs are template bugs and belong in `templates/module-crud/`, not in the user's project.

## Idempotency

Rerunning `hix-add-crud` with the same entity name should reproduce the same state. If the module files already exist, ask before passing `-Force`. Always perform the "fresh data slate" step (delete DBF + CDX) before re-running the tests — otherwise `store` will produce id=2, not id=1, and tests 4-7 will fail.

## Notes for Claude

- Do NOT hand-edit any of the generated files. If the template is wrong, fix it in `IA_ROOT/templates/module-crud/`, not per-project.
- Do NOT merge routes into `web.json`. HIX loads every `www/routes/*.json`, so a separate `<entity_lower>.json` is the correct layout.
- Never invoke `apply-template.ps1` without `-Entity`. It fails loudly, but the error is easier to read if you pass it.
- The `<entity>` argument casing matters: `Product` stays PascalCase for `{{ENTITY}}`, is lowercased for `{{ENTITY_LOWER}}`, and pluralised-then-lowercased for `{{ENTITY_PLURAL_LOWER}}`. Do not attempt smart pluralisation (only `+s` is applied, matching `apply-template.ps1`).
- If the user asks to add a CRUD to a project that is not hixstyle-enabled, abort and point them at `hix-init` (default) or `hix-scaffold-source` (legacy) — this skill only supports the hixstyle layout.
