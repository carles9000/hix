---
name: hix-init
description: Initialise a new HIX web app inside an existing binary distribution (hix.exe + www/). Use when the user says "init HIX", "start HIX app", "prepare www folder", "set up a HIX website", or points to a folder that already contains hix.exe and asks to bootstrap an app. This is the DEFAULT entry point for HIX projects in v0.2+ (binary-first mode). Do NOT use for source-first projects that need their own app.hbp — use hix-scaffold-source instead.
---

# hix-init — Bootstrap an HIX app on an existing binary distribution

## When to use

Trigger phrases:

- "init HIX in c:\hix"
- "start a HIX app"
- "prepare the www folder"
- "bootstrap HIX web app called MyNotes"
- "set up HIX website"

Precondition detection — this skill applies when the target directory already contains:
- `hix.exe`
- `hix.json`
- Runtime DLLs (`libcrypto-3-x64.dll`, `libssl-3-x64.dll`, `libcurl.dll`, `z.dll`)
- Typically an empty or missing `www/` directory

Do NOT use for:
- Adding a CRUD to an already-initialised app → `hix-add-crud`.
- Projects that will link against `hix_server.lib` and compile their own `.exe` → `hix-scaffold-source`.
- Adding a single route or middleware → `hix-add-route` / `hix-add-middleware`.

## Arguments

Required:
- `name` — logical name of the app in PascalCase (e.g. `MyNotes`, `Payments`). Used for tokens in `www/config.json` (key seeds) and `www/index.html` (page title).

Optional:
- `root` — root directory of the HIX distribution (where `hix.exe` lives). Default: current working directory. Common value: `C:\hix`.
- `author` — override for `{{AUTHOR}}` token. Default: `git config user.name` → `Developer`.
- `force` — if `www/config.json` already exists, overwrite. Default: ask first.
- `restart` — if `hix.exe` is already running, kill and relaunch. Default: ask first.

If `name` is missing, ask the user before proceeding.

Note: PowerShell / Bash / curl permissions for this project are wired by `install.bat` at install time (writes `<root>\.claude\settings.local.json`). This skill does NOT touch permissions.

## Pre-flight

1. Resolve `IA_ROOT` — the directory containing this skill's parent tree. Typically the install location of the HIX AI System (contains `templates/`, `scripts/`, `tests/`).
2. Verify `IA_ROOT/templates/project-www/` exists. If not, abort with a clear error pointing to `INSTALL.md`.
3. Resolve `<root>` to an absolute path (default: CWD). Verify `<root>/hix.exe` and `<root>/hix.json` exist. If not, abort — this is not a binary distribution; user probably wants `hix-scaffold-source`.
4. Detect if `hix.exe` is already running:
   ```
   Get-Process hix -ErrorAction SilentlyContinue
   ```
   Store PID if any. Do NOT kill yet — decision comes later.
5. Read current port from `<root>/hix.json`. Regex-scan (do not `ConvertFrom-Json` — the file may contain `/* ... */` comments that break the parser):
   ```
   $port = [regex]::Match($json, '"port"\s*:\s*(\d+)').Groups[1].Value
   ```
   Default to 80 if not found. Warn if port is 80 and OS is Windows (typically requires admin).

## Steps

Run each step and report the outcome before continuing to the next. If any step fails, stop and report the exact error.

### 1. Apply the project-www template

Invoke the PowerShell applier:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
    "<IA_ROOT>\scripts\apply-template.ps1" `
    -Template project-www `
    -Target  "<root>" `
    -Name    "<name>" `
    [-Author "<author>"] `
    -Force
```

Notes:
- `-Target` is the **root** of the HIX distribution, not a subdirectory. The template's internal structure (`www/**`) lands correctly.
- `-Force` is always passed because the target directory contains `hix.exe` etc. — the template's file paths do not collide (only `README.md` in root does; that is expected and harmless).

Expected exit code: 0. Expected files created:
- `<root>/README.md` (template overview — safe to delete)
- `<root>/www/config.json`
- `<root>/www/views/index.html`
- `<root>/www/routes/web.json`
- `<root>/www/controllers/health.prg`
- `<root>/www/public/README.md`

### 2. Enable hixstyle in hix.json

Do an in-place regex edit of `<root>/hix.json` (do NOT parse+serialize — comments will be lost).

```
$json = Get-Content -Raw "<root>\hix.json"
$json = $json -replace '("hixstyle"\s*:\s*\{[^}]*"enabled"\s*:\s*)false', '${1}true'
Set-Content -Path "<root>\hix.json" -Value $json -NoNewline -Encoding utf8
```

Verify the substitution actually happened by re-reading and searching for `"enabled": true` inside the `"hixstyle"` block. If not (already `true`, or block missing), log and continue — this is not fatal.

### 3. Restart hix.exe (if running) or start it

If pre-flight detected a running `hix.exe`:
- If `restart` argument was passed OR user confirmed: `Stop-Process -Id <pid> -Force`, wait 500 ms.
- Otherwise: stop and ask.

Start `hix.exe` in the background from `<root>`:

```
Start-Process -FilePath "<root>\hix.exe" -WorkingDirectory "<root>" -WindowStyle Hidden
```

Wait for the port to answer (max 10 s, poll every 250 ms):

```
$deadline = (Get-Date).AddSeconds(10)
do {
    try {
        $conn = New-Object System.Net.Sockets.TcpClient
        $conn.Connect('127.0.0.1', <port>)
        $conn.Close()
        break
    } catch { Start-Sleep -Milliseconds 250 }
} while ((Get-Date) -lt $deadline)
```

If timeout: report `hix.exe did not open port <port> in 10 s. Check <root>\.logs\hix.log for details.` and stop.

### 4. Verify /health

```
curl.exe -s -o - -w "%{http_code}" "http://127.0.0.1:<port>/health"
```

Expected: HTTP 200 with body `{"ok":true,"name":"<name>"}` (field order may vary).

If HTTP != 200 or body missing `"ok":true`, report:
- The actual status and body.
- The tail of `<root>\.logs\hix.log` (last 30 lines).
- Suggest checking that `hixstyle.enabled` is now `true` in `hix.json` (step 2 may have silently no-op-ed).

### 5. Report to the user

On success, print exactly this (substituting values):

```
Initialised HIX app: <name>
Root: <root>
Port: <port>
Health: OK (200, {"ok":true,"name":"<name>"})

Files created under www/:
  config.json
  views/index.html
  routes/web.json
  controllers/health.prg
  public/README.md

Next steps:
  Open http://127.0.0.1:<port>/         in a browser
  Add a CRUD:        /hix-add-crud Note
  Add a route:       /hix-add-route Ping /ping GET
  Add a middleware:  /hix-add-middleware RequireApiKey
  Run tests:         /hix-test
  Review:            /hix-review
```

On failure, do not print the "Next steps" block. Print the failing step, the exit code, and the last 20 lines of relevant output (`hix.log`, apply-template stdout, or curl output as appropriate).

## Idempotency

- If `www/config.json` already exists and `force` was not passed → ask before applying template (would overwrite user's config).
- If `hix.exe` is already running and `restart` was not passed → ask before killing.
- Editing `hix.json` is idempotent (regex only changes `false` → `true`; if already `true`, no-op).
- Rerunning the skill on an already-initialised app should be safe: the health probe will pass and the "Next steps" block will print.

## Notes for Claude

- This skill NEVER compiles anything. HIX is used as a binary. `.prg` files under `www/controllers/` are compiled by HIX in-memory on each request (`HIX_CompileFile`), so edits take effect immediately with no restart.
- The only reason to restart `hix.exe` is if `hix.json` changed (config is loaded once at startup) or if `www/loaders/*.prg` changed (loaders run once at startup).
- Never modify `apply-template.ps1` from this skill.
- If the user is on non-Windows, abort: v0.2 is Windows-only.
- If the user's HIX distribution is not at the expected canonical path (`C:\hix\`), that is fine — the skill works on any `<root>` that contains `hix.exe`. No path assumption beyond that.
