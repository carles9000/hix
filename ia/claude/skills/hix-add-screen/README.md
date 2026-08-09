# hix-add-screen

Add a full HTML screen to an existing HIX web project: controller class + one-entry routes JSON + `.view.html` template + 2 self-tests.

## Contract

- Input: `name` (PascalCase), `url` (must start with `/`), optional `title` (default `name`), optional `project` (default cwd).
- Output: 3 files under `<project>/www/` + 2 test files under `<project>/tests/` + `2/2 pass` from `tests/run-live.ps1`.
- Returns OK **only** if both tests pass end-to-end.

See `SKILL.md` for the full contract and the invocation used by Claude.
