# Uninstall Guide

> Español · [UNINSTALL.es.md](UNINSTALL.es.md)

## Uninstall from a project

    cd C:\HIX.PROJECT\hix\ia
    .\scripts\uninstall.bat C:\Path\To\MyProject

Or:

    powershell -NoProfile -ExecutionPolicy Bypass ^
        -File C:\HIX.PROJECT\hix\ia\scripts\uninstall.ps1 ^
        -Target C:\Path\To\MyProject

## What the uninstaller does

1. **Removes hix-* entries from `~\.claude\{skills,agents,commands}\`**
   - Only entries starting with `hix-` or `hix.` are removed.
   - Whether they were symlinks or copies, they go.
   - Your own skills/agents/commands are never touched.
2. **Cleans `CLAUDE.md` in the project**
   - Removes the `# HIX AI System -- auto-imported` block and its `@import` line.
   - Preserves everything else you added.
   - If nothing else was in the file, the file is deleted.

## What is NOT removed

- Files inside `C:\HIX.PROJECT\hix\ia\` — the source stays intact.
- Files inside your project other than `CLAUDE.md`.
- Any `.claude\` directory local to your project (never touched by the installer either).

## Uninstall from multiple projects

Run the command once per project. `~\.claude\` is cleaned on the first run; the following runs only clean each project's `CLAUDE.md`.

## Uninstall globally (remove skills/agents/commands, keep repo)

If you want to keep the HIX repo cloned but stop exposing skills to Claude Code:

    Get-ChildItem "$env:USERPROFILE\.claude\skills\"   -Filter 'hix-*' | Remove-Item -Recurse -Force
    Get-ChildItem "$env:USERPROFILE\.claude\agents\"   -Filter 'hix-*' | Remove-Item -Recurse -Force
    Get-ChildItem "$env:USERPROFILE\.claude\commands\" -Filter 'hix-*' | Remove-Item -Recurse -Force

You still need to manually clean `CLAUDE.md` in each installed project (or run `uninstall.bat` per project).
