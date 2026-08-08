# HIX AI System — Skills

Skills that Claude Code invokes when helping the user work on a HIX project.
Each skill lives in its own folder and is discovered by Claude via the
`description` field in the frontmatter of its `SKILL.md`.

## Index (v0.2)

Default flow (binary-first — you have `hix.exe` + `www/`):

| Skill                                        | Purpose                                              | Triggers                                                        |
|----------------------------------------------|------------------------------------------------------|-----------------------------------------------------------------|
| [`hix-init`](hix-init/)                      | Bootstrap `www/` on a HIX binary distribution        | "init HIX", "start a HIX app", "prepare www"                    |
| [`hix-add-crud`](hix-add-crud/)              | Add a full CRUD module to an existing project        | "add a CRUD for X", "generate a Product resource"               |
| [`hix-add-route`](hix-add-route/)            | Add a single HTTP route (controller + routes JSON)   | "add a route GET /ping", "add an endpoint"                      |
| [`hix-add-middleware`](hix-add-middleware/)  | Scaffold a user-owned middleware + probe route       | "add a middleware", "auth guard skeleton"                       |
| [`hix-run-tests`](hix-run-tests/)            | Run the declarative HTTP test suite (no build)       | "run the tests", "verify the app", "test everything"            |

Legacy (source-first — you compile your own `.exe` against `hix_server.lib`):

| Skill                                                | Purpose                                                  | Triggers                                                    |
|------------------------------------------------------|----------------------------------------------------------|-------------------------------------------------------------|
| [`hix-scaffold-source`](hix-scaffold-source/)        | Scaffold a source-first HIX project (`app.hbp` + `go.bat`) | "scaffold source HIX", "project that compiles its own exe"  |

## Anatomy of a skill

    hix-<name>/
      SKILL.md              # frontmatter (name, description) + prompt Claude follows
      README.md             # human-readable summary
      tests/                # (optional) parametric *.test.json templates the skill ships
      _internal/            # (optional) auxiliary helpers

The `SKILL.md` frontmatter must include:

```yaml
---
name: hix-<name>
description: <what it does, when to use, what args it expects>
---
```

Claude Code matches a user request against every skill's `description`
field. Descriptions should be:

- **Specific** — enumerate trigger phrases so Claude picks the right skill.
- **Exclusive** — mention what the skill does NOT do, to avoid overlap.
- **Argument-forward** — list what the skill expects from the user.

## Common contract

Every skill in this system follows the same discipline:

1. **Delegate file work to PowerShell scripts** under `scripts/`. Skills
   never do their own file copies or token substitution — that logic lives
   in `apply-template.ps1` and `render-tests.ps1` where it can be tested
   and reused.
2. **Verify with `tests/run.ps1`.** A skill only reports success if the
   generated code compiles and the shipped tests pass. No half-scaffolded
   projects.
3. **Fail loudly.** Any pre-flight violation (missing template, project
   layout mismatch, unresolved args) aborts before any file is written.
4. **Idempotent by default.** Rerunning a skill with the same args should
   produce the same result — or ask the user before overwriting.

## Shared infrastructure

| Path                              | Purpose                                          |
|-----------------------------------|--------------------------------------------------|
| `scripts/apply-template.ps1`      | Copy a template with `{{TOKEN}}` substitution.   |
| `scripts/render-tests.ps1`        | Copy parametric `*.test.json` templates.         |
| `tests/run.ps1`                   | Declarative HTTP test runner (spawn + iterate).  |
| `tests/helpers.ps1`               | Port picking, HTTP polling, process teardown.    |
| `tests/self-test/`                | 2 baseline tests (GET / any body, 404).          |
| `templates/project-web-crud/`     | Minimal hixstyle project skeleton.               |
| `templates/module-crud/`          | 7-route CRUD module (controller/model/views).    |
| `templates/module-route/`         | Single-route overlay (controller + routes JSON). |
| `templates/module-middleware/`    | User middleware skeleton + loader stub + probe.  |

Skills should not duplicate this logic — call the scripts.

## Adding a new skill

1. Create `hix-<name>/SKILL.md` with a frontmatter description that lists
   trigger phrases and args.
2. Write the prompt body: When to use / Arguments / Pre-flight / Steps /
   Report. Use existing skills as reference for tone and structure.
3. If the skill ships tests, put them under `hix-<name>/tests/` with
   `{{TOKEN}}` placeholders and use `render-tests.ps1` to instantiate.
4. Add a `hix-<name>/README.md` with a human summary and a manual-equivalent
   command block for debugging.
5. Add a row to the Index table above.
6. Verify: install the AI System (`scripts/install.bat`) and drive the
   skill end-to-end from a real Claude Code session against a scratch
   project.
