# Migrating from HIX AI System v0.1 to v0.2

**Applies to**: users who installed `hix/ia` v0.1 (any tag `ia-v0.1.x`) and want to move to `ia-v0.2.0`.

**Reading time**: 5 minutes.
**Migration time**: 2 minutes (Scenario A) or 10 minutes (Scenario B).

---

## TL;DR

| v0.1 | v0.2 | Action |
|------|------|--------|
| `/hix-scaffold`         | `/hix-scaffold-source` | Rename in your own scripts / muscle memory. |
| `/hix-compile-and-test` | `/hix-test`            | Rename **and** re-learn semantics: no build step. |
| Source-first by default | Binary-first by default | `/hix-init` is the new entry point. Old flow preserved via `/hix-scaffold-source`. |
| `CLAUDE.md` hard-coded to `C:\HIX.PROJECT\hix\` | `{{HIX_ROOT}}` token, expanded at install time | Re-run `install.bat` — see verification below. |
| `hix-compile-and-test` skill | `hix-run-tests` skill | Skill folder renamed. Stale symlink? Delete and re-run install. |

Everything above is covered in detail in `CHANGELOG.md` under `[0.2.0]`. This document tells you **what to do**, not what changed.

---

## Why v0.2 exists

v0.1 assumed you were a Harbour developer with `hbmk2` on your PATH — the AI System scaffolded a source project and compiled a `.exe` for you. That's a high floor for anyone who just wants a web app.

v0.2 flips the default: HIX ships as a pre-built `hix.exe` + DLLs. The AI System scaffolds a `www/` directory on top, and `hix.exe` recompiles your `.prg` files in memory on every request. Zero build step, zero Harbour install, zero `hbmk2`.

The source-first path is preserved for developers who need it (linking against `hix_server.lib`, customising the server binary) — see Scenario A below.

---

## Choose your migration path

- **Scenario A** — I already use v0.1 source-first and want to keep doing that. Minimal changes.
- **Scenario B** — I want to switch to the new binary-first flow (recommended for new apps).

---

## Scenario A — Stay source-first (developers)

You still compile your own `.exe` against `hix_server.lib`. The v0.2 upgrade for you is essentially cosmetic.

### 1. Update your commands and muscle memory

- Anywhere you scripted or documented `/hix-scaffold`, rename to `/hix-scaffold-source`.
- Anywhere you scripted or documented `/hix-compile-and-test`, rename to `/hix-test`.

The old slash command names no longer resolve — the skill folders were renamed on disk.

### 2. Re-run the installer

    cd C:\path\to\hix\ia
    .\scripts\install.bat C:\MyProject

This regenerates `~\.claude\hix-claude-rendered.md` with the new `{{HIX_ROOT}}` token expanded, refreshes the six `~\.claude\skills\hix-*` symlinks, and updates `.claude\settings.local.json` in your project with any new permission entries.

### 3. Verify

    ls ~/.claude/skills/ | grep hix

You should see:

    hix-add-crud
    hix-add-middleware
    hix-add-route
    hix-init
    hix-run-tests
    hix-scaffold-source

If any old entry remains (`hix-scaffold`, `hix-compile-and-test`, ...), delete it manually — `install.bat` doesn't garbage-collect obsolete symlinks:

    rm ~/.claude/skills/hix-scaffold
    rm ~/.claude/skills/hix-compile-and-test
    rm ~/.claude/commands/hix-scaffold.md
    rm ~/.claude/commands/hix-compile-and-test.md

### 4. Sanity check on your existing project

Open Claude in that project and run:

    > /hix-scaffold-source --help

If Claude recognises the command and prints usage, you're done.

---

## Scenario B — Switch to binary-first (recommended)

You want the new default flow: no Harbour install, no `hbmk2`, no build.

### 1. Obtain the HIX binary bundle

Get `hix.exe` + DLLs from your HIX distribution channel (release ZIP, internal share, etc.). You need:

    hix.exe
    libcrypto-3-x64.dll
    libssl-3-x64.dll
    libcurl.dll
    z.dll

Place them in an empty directory — the canonical location is `C:\hix\`, but any absolute path works.

Note: `hix.json` is **not required upfront**. If it's missing, `/hix-init` launches `hix.exe` once to let it self-generate the default config, then stops the process before continuing.

### 2. Place the AI System next to the binary

Copy the `ia/` directory of this repo into `C:\hix\ia\` (or wherever your HIX root lives):

    xcopy C:\path\to\hix\ia C:\hix\ia /E /I /Y

### 3. Run the installer against your HIX root

    cd C:\hix\ia
    .\scripts\install.bat C:\hix

This wires the six `hix-*` skills, four agents, and seven commands into your Claude Code user directory. It also creates `C:\hix\CLAUDE.md` and `C:\hix\.claude\settings.local.json`.

### 4. Bootstrap your first app

Open Claude from your HIX root and run:

    cd C:\hix
    claude
    > /hix-init MyFirstApp

Expected: `/health` responds 200, browser shows the welcome page, zero prompts along the way.

### 5. Validate end-to-end

Run each of the five follow-up commands and confirm the reported test counts:

    > /hix-add-crud Note                        # 7/7 tests
    > /hix-add-route Ping /ping GET             # 2/2 tests
    > /hix-add-middleware RequireApiKey         # 2/2 tests
    > /hix-test                                 # 11/11 tests
    > /hix-review                               # clean or findings cited with file:line

If any of these fails, capture the output and open an issue — that combination is the canonical smoke test for v0.2.

### 6. Retire your v0.1 source project (optional)

If you were using v0.1 solely to build sample apps, your v0.1 source project is superseded — the binary-first flow does everything you did before, minus the compile step. If you had non-trivial Harbour code in your source project, keep it; you can still add binary-first routes to it if desired.

---

## Verification checklist

After migration, all of the following should be true:

- `~/.claude/hix-claude-rendered.md` exists and contains **no** literal `{{HIX_ROOT}}` string. Grep it: `grep HIX_ROOT ~/.claude/hix-claude-rendered.md` should return nothing.
- `~/.claude/skills/` contains: `hix-init`, `hix-add-crud`, `hix-add-route`, `hix-add-middleware`, `hix-run-tests`, `hix-scaffold-source`.
- `~/.claude/commands/` contains: `hix-init.md`, `hix-add-crud.md`, `hix-add-route.md`, `hix-add-middleware.md`, `hix-test.md`, `hix-review.md`, `hix-scaffold-source.md`.
- `~/.claude/agents/` contains: `hix-architect.md`, `hix-reviewer.md`, `hix-router-expert.md`, `hix-view-builder.md`.
- From a HIX root, `/hix-init MyApp` succeeds with zero prompts and `/health` returns 200.

---

## Troubleshooting

**`{{HIX_ROOT}}` appears in Claude's output.**
The installer didn't render the template, or the PowerShell execution policy blocked it. Re-run `scripts\install.bat` (the batch wrapper bypasses the policy). If you invoked `install.ps1` directly, use `-ExecutionPolicy Bypass`.

**"Undefined function" or unknown slash command after upgrade.**
Stale symlinks. Delete the offending entry under `~/.claude/skills/` or `~/.claude/commands/` and re-run `install.bat`.

**`/hix-init` aborts with "not a HIX binary distribution".**
`hix.exe` is not at the target root. Check the directory contains `hix.exe` (the DLLs live alongside).

**`/hix-init` reports "did not create hix.json within 8 s".**
`hix.exe` failed to start silently. Run it manually once from the target directory (`.\hix.exe`) and inspect `.\.logs\hix.log`. Common causes: port 80 blocked (needs admin) or a DLL missing.

**Old `hix-scaffold` / `hix-compile-and-test` still show up in Claude's slash-command list.**
Symlinks in `~/.claude/commands/` weren't cleaned. Remove `hix-scaffold.md` and `hix-compile-and-test.md` manually and reopen Claude.

**`install.bat` complains it can't create symlinks.**
Enable Windows Developer Mode (Settings → Update & Security → For developers) or pass `/copy` to fall back to file copies:

    .\scripts\install.bat C:\hix /copy

File-copy mode works but breaks the "`git pull` propagates instantly" property — you'll need to re-run `install.bat` after every source update.

---

## FAQ

**Do I have to migrate?**
No. v0.1 still works if you never re-install. But new fixes and skills only land in v0.2+.

**Can v0.1 and v0.2 coexist on the same machine?**
Not cleanly — both install into `~/.claude/skills/hix-*` and the folder names collide. Pick one.

**Can source-first and binary-first coexist on the same machine?**
Yes. That's the whole point of keeping `/hix-scaffold-source`. Different projects can use different flows.

**Where's the changelog?**
`CHANGELOG.md`, section `[0.2.0]`.

**I moved my `C:\hix\` folder after installing. Now nothing works.**
The rendered `CLAUDE.md` has the old path baked in. Re-run `install.bat` from the new location.

---

## Related documents

- [CHANGELOG.md](CHANGELOG.md) — full list of changes in v0.2.0.
- [INSTALL.md](INSTALL.md) — installation reference.
- [QUICKSTART.md](QUICKSTART.md) — 5-minute walk-through of the binary-first flow.
- [README.md](README.md) — project overview.
