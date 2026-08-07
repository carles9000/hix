# hix-add-crud

Skill that adds a complete CRUD module to an existing HIX web project and
verifies all 7 routes work with a live HTTP test suite.

## What it does

1. Runs `scripts/apply-template.ps1 -Template module-crud` against
   `<project>/www/`, generating controller + model + 3 views + routes JSON
   + first-boot loader.
2. Runs `scripts/render-tests.ps1` to copy 7 parametric `*.test.json`
   templates from this skill's `tests/` into `<project>/tests/`, prefixing
   each with the entity name (`product-1-list-empty.test.json`, ...).
3. Deletes any stale DBF+CDX for this entity in `<project>/data/` so the
   store test produces id=1.
4. Runs `tests/run.ps1` against the project and reports 7/7 pass.

## What it does NOT do

- Create a project from scratch → use `hix-scaffold`.
- Add a single route without controller/model/views → use `hix-add-route`.
- Modify `web.json` (routes are added as a separate JSON file — HIX loads
  every `www/routes/*.json`).

## Invocation

Claude Code picks up this skill when the user asks to add a CRUD, resource,
or model to an existing HIX project.

## Manual equivalent

```powershell
$IA = 'C:\HIX.PROJECT\hix\ia'
$P  = 'C:\work\MyApp'

# 1. Generate module
powershell -File $IA\scripts\apply-template.ps1 `
    -Template module-crud -Target $P\www -Entity Product

# 2. Render tests
powershell -File $IA\scripts\render-tests.ps1 `
    -Source $IA\claude\skills\hix-add-crud\tests `
    -Target $P\tests -Entity Product -Prefix 'product-'

# 3. Wipe stale data (optional on first run)
Remove-Item $P\data\products.dbf, $P\data\products.cdx -ErrorAction SilentlyContinue

# 4. Run tests
powershell -File $IA\tests\run.ps1 -Project $P -Tests $P\tests
```

## The 7 tests

Numbered so `Get-ChildItem` runs them in the required order (state carries
between tests: `3-store` creates id=1, `4-show`/`5-edit-form` read it,
`6-update` mutates it, `7-delete` removes it).

| # | File                          | Method | Path                              | Expect       |
|---|-------------------------------|--------|-----------------------------------|--------------|
| 1 | `1-list-empty.test.json`      | GET    | `/{plural}`                       | 200 + HTML   |
| 2 | `2-create-form.test.json`     | GET    | `/{plural}/create`                | 200 + `<form>` |
| 3 | `3-store.test.json`           | POST   | `/{plural}/store`                 | 302          |
| 4 | `4-show.test.json`            | GET    | `/{plural}/1`                     | 200 + name   |
| 5 | `5-edit-form.test.json`       | GET    | `/{plural}/1/edit`                | 200 + `<form>` |
| 6 | `6-update.test.json`          | POST   | `/{plural}/1/update`              | 302          |
| 7 | `7-delete.test.json`          | POST   | `/{plural}/1/delete`              | 302          |

Token placeholders in the source templates:
- `{{ENTITY}}` — PascalCase entity name (e.g. `Product`)
- `{{ENTITY_LOWER}}` — lowercase (e.g. `product`)
- `{{ENTITY_PLURAL_LOWER}}` — naive plural + lower (e.g. `products`)

`render-tests.ps1` performs the substitution both in file names and JSON body.

## Exit contract

The skill reports success only if `run.ps1` exits 0 (7/7 pass). On any
failure it prints which of the 7 tests failed, the runner's exit code, and
up to 20 lines of relevant output.
