# HIX Templates

Skeletons the installer / skills copy into a new project.

## Available templates

| Template                | Purpose                                             |
|-------------------------|-----------------------------------------------------|
| `project-web-crud/`     | New empty web-crud project (server + hixstyle wiring, no domain code) |
| `module-crud/`          | Drop-in CRUD module (route + controller + model + views) for an existing project |
| `module-route/`         | Single HTTP route (controller + routes JSON) overlay |
| `module-middleware/`    | User-owned middleware (function + loader stub + probe controller + probe route) |

*(More coming: `project-api-class`, `project-api-function`, `project-websocket`...)*

## Token replacement

Templates use `{{TOKEN}}` placeholders. `scripts/apply-template.ps1` walks the
tree, reads every text file, replaces the tokens, and writes to the target.

### Project-level tokens (`project-*`)

| Token                     | Example                          | Notes |
|---------------------------|----------------------------------|-------|
| `{{PROJECT_NAME}}`        | `MyNotes`                        | PascalCase, used in titles, headers |
| `{{PROJECT_NAME_LOWER}}`  | `mynotes`                        | Auto-derived (lowercased) |
| `{{AUTHOR}}`              | `Carles Aubia`                   | From `git config user.name` if empty |
| `{{DATE}}`                | `2026-08-06`                     | Today (ISO) |
| `{{YEAR}}`                | `2026`                           | Today's year |
| `{{HIX_PATH}}`            | `c:\HIX.PROJECT\hix.pro`         | Path to your HIX repo (needed by `app.hbp` + `go.bat`) |

### Module-level tokens (`module-crud`)

| Token                     | Example         | Notes |
|---------------------------|-----------------|-------|
| `{{ENTITY}}`              | `Product`       | PascalCase singular. Function/class names. |
| `{{ENTITY_LOWER}}`        | `product`       | Auto-derived. File names, hash keys. |
| `{{ENTITY_PLURAL_LOWER}}` | `products`      | URL segments, DBF file basenames. |
| `{{DATE}}`                | `2026-08-06`    | Today (ISO) |
| `{{AUTHOR}}`              | `Carles Aubia`  | From `git config user.name` if empty |

### Module-level tokens (`module-route`)

| Token                    | Example    | Notes |
|--------------------------|------------|-------|
| `{{ROUTE_NAME}}`         | `Ping`     | PascalCase. CLASS name for the controller. |
| `{{ROUTE_NAME_LOWER}}`   | `ping`     | Auto-derived. File names, route `name` field. |
| `{{ROUTE_URL}}`          | `/ping`    | URL path. Must start with `/`. |
| `{{ROUTE_METHOD}}`       | `GET`      | HTTP method: `GET|POST|PUT|DELETE|PATCH`. |

### Module-level tokens (`module-middleware`)

| Token                          | Example                     | Notes |
|--------------------------------|-----------------------------|-------|
| `{{MIDDLEWARE_NAME}}`          | `RequireApiKey`             | PascalCase. Generated function is `HixMw<Name>`. |
| `{{MIDDLEWARE_NAME_LOWER}}`    | `requireapikey`             | Auto-derived. File names. |
| `{{PROBE_URL}}`                | `/__mw_probe_requireapikey` | Probe route URL. Auto-derived from name if `-ProbeUrl` omitted. |

## Usage

Directly:

```bat
powershell -File hix\ia\scripts\apply-template.ps1 ^
  -Template project-web-crud ^
  -Target   C:\dev\MyNotes ^
  -Name     MyNotes
```

Via skill (recommended):

```
/hix-scaffold web-crud MyNotes
```

The skill knows where the templates live (via the installed CLAUDE.md) and
runs `apply-template.ps1` for you.

## Contributing a template

1. Create `templates/<kind>-<name>/` with all skeleton files.
2. Use `{{TOKEN}}` for anything that varies by project.
3. Text files only — DBFs and other binaries stay out of the template
   (generate them via a loader `.prg` at first boot, or document their
   creation in `readme.md`).
4. Add a row to this README.
5. Update the token table if you introduce new tokens (edit
   `apply-template.ps1` to compute them).
6. Bump `CHANGELOG.md`.

Golden rules from `CONTRIBUTING.md` still apply: no non-ASCII in `.ps1`,
EN as source language, `.es.md` sibling for docs.
