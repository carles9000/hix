# Contributing to the HIX AI System

> Español · [CONTRIBUTING.es.md](CONTRIBUTING.es.md)

Thanks for wanting to improve HIX for everyone. This guide explains how to add or modify each asset type.

## Golden rules

1. **All assets targeted at Claude Code must be prefixed `hix-`** (skills, agents, commands). The installer only touches entries with that prefix.
2. **Every skill or command that generates code must ship a `*.test.json`** under its `tests/` folder (see [tests framework — Session 4](.)). No test → no merge.
3. **PowerShell scripts stay ASCII-only.** Windows PowerShell 5.1 reads `.ps1` as Windows-1252 by default and corrupts UTF-8 chars, causing parser errors. Use `--` instead of `—`.
4. **English is the default language for filenames and code identifiers.** Human-readable docs go in EN + ES (side-by-side files with `.es.md` suffix).

## Add a new skill

Directory: `claude/skills/hix-<name>/`

Minimum:

    hix-<name>/
        SKILL.md
        tests/
            <case>.test.json

`SKILL.md` template:

    ---
    name: hix-<name>
    description: >
        One sentence describing what the skill does + when to use it.
        Include trigger phrases the user might say.
    ---

    # hix-<name> -- Short title

    ## When to use
    - "phrase 1"
    - "phrase 2"

    ## Instructions for Claude
    Numbered steps. Reference templates by absolute path
    (C:\HIX.PROJECT\hix\ia\templates\<template>\).

    ## Test
    See tests/<case>.test.json

## Add a new slash command

Directory: `claude/commands/hix-<name>.md` (single file, no subfolder).

Template:

    ---
    description: One-line summary. Shown in the / picker.
    argument-hint: <arg1> <arg2>
    ---

    Purpose sentence.

    Arguments: $ARGUMENTS

    Steps: (numbered — Claude will execute them)
    1. ...
    2. ...

If the command orchestrates a skill, keep the command file thin — put the logic in the skill and have the command invoke it.

## Add a new agent

Directory: `claude/agents/hix-<name>.md`

Template:

    ---
    name: hix-<name>
    description: When Claude Code should delegate to this agent (be specific).
    tools: Read, Grep, Glob    # allowed tools; keep to the minimum
    ---

    You are a specialist in <domain>. Given <input>, produce <output>.
    Reference: `hix/ia/knowledge/<relevant_doc>.md`

Do NOT ship agents with `Edit` or `Write` tools unless strictly required — most agents just research and produce a report.

## Add knowledge (`knowledge/`)

- One topic per file, <2000 tokens.
- Filename pattern: `<NN>_<topic>.md` (e.g. `03_middleware.md`) for stable ordering.
- EN under `knowledge/en/`, ES under `knowledge/es/` — same filenames.
- Update `knowledge/INDEX.md` when adding a file.

Knowledge docs are what Claude reads for reference. Keep them dense, factual, and code-example-heavy.

## Add a template (`templates/`)

- Directory naming: `project-<kind>/` for full projects, `module-<kind>/` for reusable modules.
- Only supported tokens: `{{PROJECT_NAME}}`, `{{PROJECT_NAME_LOWER}}`, `{{DATE}}`, `{{YEAR}}`, `{{AUTHOR}}`, `{{ENTITY}}`, `{{ENTITY_LOWER}}`.
- No demo data in DBFs — ship header-only.
- Include a `README.md` in the template explaining what tokens it expects.

## Update the CHANGELOG

Every merged change adds an entry under `[Unreleased]` at the top of `CHANGELOG.md`. On release, that block is renamed to the new version + date.

## Test your contribution locally

    cd C:\HIX.PROJECT\hix\ia
    .\scripts\install.bat C:\tmp\hix_contrib_test

Open Claude Code in `C:\tmp\hix_contrib_test`, invoke your skill/command/agent, verify behaviour. Then run the automated tests (Session 4 — coming).

Uninstall when done:

    .\scripts\uninstall.bat C:\tmp\hix_contrib_test

## Submitting a PR

- Branch name: `ia/<kind>/<name>` — e.g. `ia/skill/hix-add-crud`, `ia/knowledge/routing`.
- PR title: `[ia] <kind>: <what>` — e.g. `[ia] skill: add hix-add-crud`.
- PR body: link to related issue, list what you added, mention tests included.
