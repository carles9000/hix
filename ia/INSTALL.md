# Install Guide

> Español · [INSTALL.es.md](INSTALL.es.md)

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Claude Code CLI | https://claude.com/claude-code — must be on PATH |
| HIX repo cloned | This repo, at `C:\HIX.PROJECT\hix\` (path is currently hard-coded — see [issue in Backlog](.claude/plans/tasks_hix_ia_system.md)) |
| Windows 10/11 | Developer Mode ON is strongly recommended |

### Enable Developer Mode (once per machine)

Settings → *For developers* → **Developer Mode: On**

Or via PowerShell (admin):

    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense /t REG_DWORD /d 1 /f

Without Developer Mode the installer falls back to file copy — everything still works, but a `git pull` in the HIX repo will **not** propagate to your `~/.claude/`. You would need to re-run install.

## Install into a project

Simplest (recommended):

    cd C:\HIX.PROJECT\hix\ia
    .\scripts\install.bat C:\Path\To\MyProject

Force file copy (skip symlinks):

    .\scripts\install.bat C:\Path\To\MyProject /copy

Or invoke PowerShell directly:

    powershell -NoProfile -ExecutionPolicy Bypass ^
        -File C:\HIX.PROJECT\hix\ia\scripts\install.ps1 ^
        -Target C:\Path\To\MyProject

## What the installer does

1. **Creates or updates** `C:\Path\To\MyProject\CLAUDE.md`
   - If the file did not exist: creates it with a title + the HIX import block.
   - If it existed: appends an import block at the end. Existing content is preserved.
   - The import points to `C:\HIX.PROJECT\hix\ia\claude\CLAUDE.md` via `@` syntax.
2. **Creates hix-* entries in `~\.claude\{skills,agents,commands}\`**
   - Symlinks by default (single source of truth, updates on `git pull`).
   - Regular files/directories if `-ForceCopy` or symlink capability unavailable.
   - Only entries starting with `hix-` or `hix.` are touched. Your own skills/agents/commands are never modified.
3. **Prints a summary** of every action taken.

## After install

    cd C:\Path\To\MyProject
    claude

Inside Claude Code:

    > /hix-scaffold web-crud MyApp

If the skill responds, the wiring is correct.

## Verify install manually

    Get-ChildItem "$env:USERPROFILE\.claude\skills\" | Where-Object Name -like 'hix-*'
    Get-Content C:\Path\To\MyProject\CLAUDE.md

Expected:
- One `hix-scaffold` entry in `skills\` (SymbolicLink or Directory)
- The project's `CLAUDE.md` ends with:

      # HIX AI System -- auto-imported
      @C:\HIX.PROJECT\hix\ia\claude\CLAUDE.md

## Troubleshooting

### "execution of scripts is disabled on this system"

You bypassed the `.bat` wrapper. Either use `install.bat` (recommended) or add `-ExecutionPolicy Bypass` to the PowerShell invocation.

### "Cannot create symbolic link. A required privilege is not held by the client."

Developer Mode is off and PowerShell is not running as admin. Two fixes:

- **Preferred**: turn Developer Mode on (see Prerequisites) and re-run.
- **Fallback**: run with `/copy` — you lose auto-update via `git pull`.

### Claude Code does not see the `/hix-scaffold` command

- Confirm the symlink/copy exists at `~\.claude\skills\hix-scaffold\SKILL.md`.
- Restart Claude Code — some hosts cache the skill index on session start.

### The CLAUDE.md import is not being applied

Claude Code loads `CLAUDE.md` from the project root only. Confirm you launched `claude` from the same directory that contains `CLAUDE.md` (not from a subdirectory).

## Upgrade

If installed with symlinks (default), just:

    cd C:\HIX.PROJECT\hix
    git pull

Skills, agents, commands, knowledge — everything updates instantly for every installed project.

If installed with `/copy`, re-run `install.bat` after `git pull`.

## Uninstall

See [UNINSTALL.md](UNINSTALL.md).
