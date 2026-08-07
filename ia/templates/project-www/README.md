# Template: project-www

**Mode:** binary-first (default in v0.2+)

Minimal `www/` layout for an HIX distribution where the user already has
`hix.exe` + DLLs installed and only edits files under `www/`. No `.hbp`,
no `go.bat`, no compilation.

Applied by the skill `hix-init` (slash command `/hix-init`).

## What it creates

    www/
      config.json                # sets, DBF driver, keys
      views/index.html           # welcome page (served by / route)
      routes/web.json            # 2 routes: / and /health
      controllers/health.prg     # returns {ok:true, name:"{{PROJECT_NAME}}"}
      public/                    # static assets (empty by default)

## Tokens

- `{{PROJECT_NAME}}`       — project name in PascalCase (e.g. `MyNotes`).
- `{{PROJECT_NAME_LOWER}}` — project name lowercased (e.g. `mynotes`).
- `{{AUTHOR}}`             — author name for file headers.
- `{{DATE}}`               — creation date (`yyyy-MM-dd`).

## Post-apply steps handled by `hix-init`

1. Set `hixstyle.enabled = true` in the existing `hix.json` (in-place edit,
   never overwritten).
2. Optionally change `server.port` to `8080` (asks first if it was `80`).
3. Start `hix.exe` in background, `GET /health`, verify `{ok:true}`.
