# hix-add-route

Add a single HTTP route to an existing HIX web project: controller class + one-entry routes JSON + 2 self-tests.

## Contract

- Input: `name` (PascalCase), `url` (must start with `/`), optional `method` (default `GET`), optional `project` (default cwd).
- Output: 2 files under `<project>/www/` + 2 test files under `<project>/tests/` + `2/2 pass` from `tests/run.ps1`.
- Returns OK **only** if both tests pass end-to-end.

See `SKILL.md` for the full contract and the invocation used by Claude.
