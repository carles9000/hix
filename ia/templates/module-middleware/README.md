# module-middleware

Overlay template that scaffolds a user-owned middleware plus a probe route to prove it runs. The middleware skeleton denies every request that does not carry an `X-Api-Key` header -- replace that logic with whatever the middleware should really do.

## Layout

```
templates/module-middleware/
├── controllers/
│   └── {{MIDDLEWARE_NAME_LOWER}}_probe.prg
├── loaders/
│   └── init_mw_{{MIDDLEWARE_NAME_LOWER}}.prg     # #include of the MW .prg
├── middlewares/
│   └── {{MIDDLEWARE_NAME_LOWER}}.prg              # HixMw{{MIDDLEWARE_NAME}}( oCtx )
└── routes/
    └── mw_{{MIDDLEWARE_NAME_LOWER}}_probe.json    # route wired with the MW
```

## Tokens

| Token                          | Source arg           | Example              |
|--------------------------------|----------------------|----------------------|
| `{{MIDDLEWARE_NAME}}`          | `-MiddlewareName`    | `RequireApiKey`      |
| `{{MIDDLEWARE_NAME_LOWER}}`    | (derived)            | `requireapikey`      |
| `{{PROBE_URL}}`                | `-ProbeUrl` (or auto)| `/__mw_probe_requireapikey` |
| `{{AUTHOR}}`                   | `-Author` / git      | `Developer`          |
| `{{DATE}}`                     | (auto)               | `2026-08-07`         |

If `-ProbeUrl` is omitted, it defaults to `/__mw_probe_<middleware_lower>`.

## Usage

```
powershell -File scripts\apply-template.ps1 `
    -Template module-middleware `
    -Target  <project>\www `
    -MiddlewareName RequireApiKey
```

Files written: 4. Rebuild and:

- `GET /__mw_probe_requireapikey` without header -> `401`.
- `GET /__mw_probe_requireapikey` with `X-Api-Key: anything` -> `200 {ok:true}`.

## Design notes

- **No JSON edits.** The middleware is registered by dropping it into `www/loaders/init_mw_*.prg`, which pulls the function into the compile unit via `#include`. `HIX_Loaders()` compiles every `.prg` in `www/loaders/` at boot and publishes its public symbols globally -- the router then resolves `"middleware": "HixMw..."` in the route JSON by macro expansion. This avoids touching `www/middlewares/config.json` (which is only needed for built-in `HIX_Mw*` setup, not user MW registration).
- The route JSON uses a `__mw_probe_` prefix so it does not clash with real app routes and can be trimmed later.
- The probe controller is a trivial CLASS/METHOD that returns 200 -- if the middleware blocks, the controller never runs, so the JSON response is enough to distinguish "MW allowed" from "MW denied".
