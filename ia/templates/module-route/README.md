# module-route

Overlay template that adds a single HTTP route (controller + routes JSON) to an existing HIX web project. Emits no middleware, no model, no view.

## Layout

```
templates/module-route/
├── controllers/
│   └── {{ROUTE_NAME_LOWER}}.prg    # CLASS with a single Index() METHOD
└── routes/
    └── {{ROUTE_NAME_LOWER}}.json   # single-entry routes file
```

## Tokens

| Token                    | Source arg      | Example    |
|--------------------------|-----------------|------------|
| `{{ROUTE_NAME}}`         | `-RouteName`    | `Ping`     |
| `{{ROUTE_NAME_LOWER}}`   | (derived)       | `ping`     |
| `{{ROUTE_URL}}`          | `-RouteUrl`     | `/ping`    |
| `{{ROUTE_METHOD}}`       | `-RouteMethod`  | `GET`      |
| `{{AUTHOR}}`             | `-Author` / git | `Developer`|
| `{{DATE}}`               | (auto)          | `2026-08-07` |

`-RouteMethod` accepts `GET|POST|PUT|DELETE|PATCH` (default `GET`). `-RouteUrl` must start with `/`.

## Usage

```
powershell -File scripts\apply-template.ps1 `
    -Template module-route `
    -Target  <project>\www `
    -RouteName Ping `
    -RouteUrl  /ping `
    -RouteMethod GET
```

Files written: 2. Rebuild and hit `GET /ping` to see the JSON response.

## Design notes

- The controller returns a JSON body with `ok`, `route`, `method`, `url` — enough for the paired test (`hix-add-route/tests/1-route-ok.test.json.tmpl`) to assert both status and body without a database or session.
- Routes go in a dedicated file (not merged into `web.json`) so multiple `hix-add-route` invocations coexist without editing shared JSON. HIX reads every `www/routes/*.json` at boot.
