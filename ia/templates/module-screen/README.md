# module-screen

Overlay template that adds a single HTML screen (route + controller + view) to an existing HIX web project. Emits no middleware, no model, no form.

## Layout

```
templates/module-screen/
├── controllers/
│   └── {{SCREEN_NAME_LOWER}}.prg     # CLASS with a single Index() METHOD that calls USendView(...)
├── routes/
│   └── {{SCREEN_NAME_LOWER}}.json    # single-entry routes file (GET only)
└── views/
    └── {{SCREEN_NAME_LOWER}}.view.html  # minimal HTML with @args cTitle
```

## Tokens

| Token                     | Source arg        | Example       |
|---------------------------|-------------------|---------------|
| `{{SCREEN_NAME}}`         | `-ScreenName`     | `Hello`       |
| `{{SCREEN_NAME_LOWER}}`   | (derived)         | `hello`       |
| `{{SCREEN_URL}}`          | `-ScreenUrl`      | `/hello`      |
| `{{SCREEN_TITLE}}`        | `-ScreenTitle`    | `Hello`       |
| `{{AUTHOR}}`              | `-Author` / git   | `Developer`   |
| `{{DATE}}`                | (auto)            | `2026-08-09`  |

`-ScreenUrl` must start with `/`. `-ScreenTitle` defaults to `-ScreenName` if omitted.

## Usage

```
powershell -File scripts\apply-template.ps1 `
    -Template module-screen `
    -Target   <project>\www `
    -ScreenName Hello `
    -ScreenUrl  /hello
```

Files written: 3. Rebuild not needed -- HIX reads routes at boot and templates hot-reload. Hit `GET /hello` to see the rendered HTML.

## Design notes

- The controller returns HTML via `USendView(...)`. The view receives a single `cTitle` variable so the paired test can assert on `<h1>{{ cTitle }}</h1>` deterministically.
- Routes go in a dedicated file (not merged into `web.json`) so multiple `hix-add-screen` invocations coexist without editing shared JSON. HIX reads every `www/routes/*.json` at boot.
- No CSS `<link>` is emitted in the view. Add `<link rel="stylesheet" href="/public/css/...">` yourself when you have styles to serve -- keeps the scaffold zero-dependency and avoids 404s on fresh projects.
- The URL supports `:vars` (e.g. `/user/:id`) syntactically, but the generated controller ignores them. Read them yourself with `UParam("id","")` in `Index()` if needed.
