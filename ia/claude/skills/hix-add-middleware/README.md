# hix-add-middleware

Scaffold a user-owned middleware in an existing HIX web project: `HixMwName` function + loader stub + probe controller + probe route + 2 self-tests.

## Contract

- Input: `name` (PascalCase), optional `probe_url` (default `/__mw_probe_<name_lower>`), optional `project` (default cwd).
- Output: 4 files under `<project>/www/` + 2 test files under `<project>/tests/` + `2/2 pass` from `tests/run.ps1`.
- Returns OK **only** if both tests pass end-to-end (denies without header -> 401, allows with header -> 200).

See `SKILL.md` for the full contract and the invocation used by Claude.
