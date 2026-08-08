# Install Guide

> Español · [INSTALL.es.md](INSTALL.es.md)

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Claude Code CLI | https://claude.com/claude-code — must be on PATH |
| HIX distribution | A folder containing `hix.exe`, `hix.json`, and runtime DLLs. Typical location: `C:\hix\`. The AI System bundle lives beside it at `<hix>\ia\`. |
| Windows 10/11 | Developer Mode ON is strongly recommended |

Harbour + `hbmk2` are **not** required for the default binary-first flow. They are only needed if you use `/hix-scaffold-source` (legacy) to build your own `.exe`.

### Enable Developer Mode (once per machine)

Settings → *For developers* → **Developer Mode: On**

Or via PowerShell (admin):

    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense /t REG_DWORD /d 1 /f

Without Developer Mode the installer falls back to file copy — everything still works, but a `git pull` in the HIX repo will **not** propagate to your `~/.claude/`. You would need to re-run install.

## Install into a project

Simplest (recommended):

    cd C:\hix\ia
    .\scripts\install.bat C:\Path\To\MyProject

Common case — install the AI System into the same folder that contains `hix.exe`, so you can drive `/hix-init` from there:

    cd C:\hix\ia
    .\scripts\install.bat C:\hix

Force file copy (skip symlinks):

    .\scripts\install.bat C:\Path\To\MyProject /copy

Or invoke PowerShell directly:

    powershell -NoProfile -ExecutionPolicy Bypass ^
        -File C:\hix\ia\scripts\install.ps1 ^
        -Target C:\Path\To\MyProject

## What the installer does

1. **Creates hix-\* entries in `~\.claude\{skills,agents,commands}\`**
   - Symlinks by default (single source of truth, updates on `git pull`).
   - Regular files/directories if `-ForceCopy` or symlink capability unavailable.
   - Only entries starting with `hix-` or `hix.` are touched. Your own skills/agents/commands are never modified.
2. **Renders `~\.claude\hix-claude-rendered.md`**
   - Reads `<hix>\ia\claude\CLAUDE.md` (which uses the `{{HIX_ROOT}}` placeholder).
   - Substitutes `{{HIX_ROOT}}` with the actual parent of `<hix>\ia\` (typically `C:\hix`).
   - Writes the rendered file so Claude Code can import it verbatim.
3. **Creates or updates** `C:\Path\To\MyProject\CLAUDE.md`
   - If the file did not exist: creates it with a title + the HIX import block.
   - If it existed: appends an import block at the end. Existing content is preserved.
   - The import points to `~\.claude\hix-claude-rendered.md` via `@` syntax.
4. **Writes `C:\Path\To\MyProject\.claude\settings.local.json`**
   - Adds permissions (`Bash(powershell.exe *)`, `PowerShell(*)`, `Bash(curl.exe *)`, etc.) so the HIX skills can run their PowerShell scripts without prompting per command.
   - Idempotent: existing entries are preserved, only missing ones are added.
5. **Prints a summary** of every action taken.

## After install

    cd C:\hix          # or your target folder
    claude

Inside Claude Code:

    > /hix-init MyApp

If the skill responds, the wiring is correct.

## Verify install manually

    Get-ChildItem "$env:USERPROFILE\.claude\skills\" | Where-Object Name -like 'hix-*'
    Get-Content "$env:USERPROFILE\.claude\hix-claude-rendered.md" -TotalCount 5
    Get-Content C:\Path\To\MyProject\CLAUDE.md
    Get-Content C:\Path\To\MyProject\.claude\settings.local.json

Expected:
- Entries under `skills\`, `agents\`, `commands\` starting with `hix-*` (SymbolicLink or Directory).
- The rendered `hix-claude-rendered.md` has your actual HIX path expanded (no `{{HIX_ROOT}}` left).
- The project's `CLAUDE.md` ends with:

      # HIX AI System -- auto-imported
      @C:\Users\<you>\.claude\hix-claude-rendered.md

- `settings.local.json` lists at least `Bash(powershell.exe *)`, `PowerShell(*)`, `Bash(curl.exe *)` in `permissions.allow`.

## Troubleshooting

### "execution of scripts is disabled on this system"

You bypassed the `.bat` wrapper. Either use `install.bat` (recommended) or add `-ExecutionPolicy Bypass` to the PowerShell invocation.

### "Cannot create symbolic link. A required privilege is not held by the client."

Developer Mode is off and PowerShell is not running as admin. Two fixes:

- **Preferred**: turn Developer Mode on (see Prerequisites) and re-run.
- **Fallback**: run with `/copy` — you lose auto-update via `git pull`.

### Claude Code does not see the `/hix-init` command

- Confirm the symlink/copy exists at `~\.claude\commands\hix-init.md` and `~\.claude\skills\hix-init\SKILL.md`.
- Restart Claude Code — some hosts cache the skill index on session start.

### The CLAUDE.md import is not being applied

Claude Code loads `CLAUDE.md` from the project root only. Confirm you launched `claude` from the same directory that contains `CLAUDE.md` (not from a subdirectory).

### PowerShell still prompts for permission on every command

`install.bat` did not write `.claude/settings.local.json` (permission error, or Target path resolved incorrectly). Re-run install; verify the file exists and contains the expected `permissions.allow` list.

### `{{HIX_ROOT}}` visible in Claude's context

The rendered file was not created, or the project's `CLAUDE.md` still imports the master `<hix>\ia\claude\CLAUDE.md` from a pre-v0.2 install. Re-run `install.bat` — it regenerates the rendered file and updates the import line.

## Upgrade

If installed with symlinks (default):

    cd C:\hix          # or the folder that contains ia\ as a subdir
    git pull

Skills, agents, commands, knowledge — everything updates instantly for every installed project.

The rendered `hix-claude-rendered.md` is a snapshot from install time. Re-run `install.bat` after `git pull` **only if** the master `CLAUDE.md` template itself changed (e.g. new sections). For pure skill/agent updates, no reinstall is needed.

If installed with `/copy`, always re-run `install.bat` after `git pull`.

## Uninstall

See [UNINSTALL.md](UNINSTALL.md).
