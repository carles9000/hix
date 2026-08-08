# HIX AI System -- Agents

Agents are **specialised roles** Claude Code can invoke via its `Task` tool
(`subagent_type=<name>`). Unlike skills (which execute a procedure using
scripts) and unlike slash commands (which are thin wrappers), agents run in
their **own context window** with a **restricted tool set** — they behave
like a focused colleague you brief once and then let work.

## Index (v0.2)

| Agent                                | Role                                                             | Tools                          | Writes files? |
|--------------------------------------|------------------------------------------------------------------|--------------------------------|---------------|
| [`hix-architect`](hix-architect.md)      | Turn a fuzzy app idea into an ordered slash-command plan     | Read, Grep, Glob, WebFetch     | No            |
| [`hix-router-expert`](hix-router-expert.md) | Route groups, `:var` regex, middleware chains, precedence | Read, Grep, Glob, Bash, Edit, Write | Yes    |
| [`hix-view-builder`](hix-view-builder.md)   | Build `.view.html` templates and wire controllers          | Read, Write, Edit, Grep, Glob  | Yes           |
| [`hix-reviewer`](hix-reviewer.md)           | Audit a project against public HIX/Harbour rules           | Read, Grep, Glob               | No            |

## Anatomy of an agent

    hix-<name>.md          # single file with frontmatter + system prompt

Frontmatter must include:

```yaml
---
name: hix-<name>
description: <trigger phrases + when to use + what NOT to do>
tools: <comma-separated allowlist>
---
```

- **`name`** — the id Claude Code uses in `Task(subagent_type="hix-<name>")`.
- **`description`** — Claude reads this to decide whether to route a request
  to this agent. Be **specific** about trigger phrases and **exclusive**
  about what the agent does not do (to avoid overlap with other agents /
  skills).
- **`tools`** — the tool allowlist. Restrict to what the agent needs. A
  reviewer with `Write` is not a reviewer.

Optional `model: sonnet | opus | haiku` overrides the inherited model. Leave
it out unless the agent specifically needs a heavier model (e.g. `hix-architect`
doing a big system design).

## Design principles

1. **One agent, one role.** If the description starts to enumerate
   unrelated capabilities, split the agent. Overlap with a sibling agent
   is worse than a gap — Claude picks arbitrarily when both descriptions
   match.
2. **Restrict tools by intent.** A pure reviewer gets `Read/Grep/Glob`;
   a builder gets `Write/Edit`; a router surgeon also gets `Bash` so it
   can prove the change with a rebuild. Never grant `Bash` unless the
   agent needs to run something.
3. **Reference the public knowledge base.** Every agent's system prompt
   should point to specific files in `knowledge/en/*.md` and say "read
   these first." That keeps the framework rules in one place; agents
   don't paraphrase and drift.
4. **Silent when there's nothing to say.** Reviewer output when clean is
   a one-line verdict, not padding. Same principle for other agents.

## When to reach for an agent vs a skill vs a command

| You want to…                                              | Use               |
|-----------------------------------------------------------|-------------------|
| Generate the standard CRUD for a new entity               | `/hix-add-crud`   |
| Add a single trivial endpoint                             | `/hix-add-route`  |
| Add a middleware skeleton with the shipped shape          | `/hix-add-middleware` |
| Compose route groups + shared middleware + regex `:vars`  | `hix-router-expert` |
| Port existing HTML into `.view.html` templates            | `hix-view-builder`  |
| Design an app from a paragraph of requirements            | `hix-architect`     |
| Audit an existing project for rule violations             | `hix-reviewer` (via `/hix-review`) |

Rule of thumb: **skills for the shape, agents for the judgement.** If
a template can do it, use the skill. If the task needs reading the
context and deciding, use the agent.

## Installation

`scripts/install.ps1` (called by `install.bat`) symlinks every file
named `hix-*` in this folder into `~/.claude/agents/`. After adding a
new agent, re-run `install.bat` — safe and idempotent.

`README.md` (this file) is NOT installed — only `hix-*` items are
symlinked so the user's own agent files are never clobbered.

## Adding a new agent

1. Create `hix-<name>.md` with the frontmatter above.
2. System prompt sections in order: role in one line, public knowledge to
   read, when invoked, process (numbered), constraints, output format.
3. Add a row to the Index table above.
4. Re-install (`scripts\install.bat`) and verify Claude Code picks up
   the agent (`Task(subagent_type="hix-<name>")` should not error with
   "unknown agent").

## Planned (not in v0.1)

- `hix-migration` — port from `uhttpd2` to HIX. Deferred: new users don't
  need it, existing users are few and can be helped ad-hoc.
- `hix-perf` — pool / metrics analysis. Deferred: depends on knowledge
  docs for `hix_metrics.prg` which are not yet public.
