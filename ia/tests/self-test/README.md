# Self-tests

Meta-tests that exercise the runner (`../run.ps1`) itself.

These tests are intentionally minimal: they assume a working HIX project (scaffolded from `templates/project-web-crud`) and only verify that:

1. The runner can build, launch, poll, and shut down a HIX project.
2. `expect.status`, `expect.body_matches`, and `expect.content_type_contains` work.
3. The runner returns a non-zero exit code when a test fails.

---

## How to run

**Prerequisite**: scaffold a bare project from the template. From `hix\ia\`:

```powershell
.\scripts\apply-template.ps1 `
    -Template project-web-crud `
    -Target   C:/tmp/hix-selftest `
    -Name     SelfTest
```

Then run the self-tests against it:

```powershell
.\tests\run.ps1 `
    -Project C:/tmp/hix-selftest `
    -Tests   .\tests\self-test
```

Expected result: **2 pass, 0 fail** (exit code 0).

---

## Tests included

| File | Checks |
|---|---|
| `basic-get.test.json` | `GET /` returns *some* body (proves server is up and reachable) |
| `not-found.test.json` | Unknown path returns `404` (proves the runner reads status correctly) |

---

## Adding a failure-mode test

To verify that the runner correctly reports failures, drop this file in a temp dir and run it separately -- it **should** fail:

```json
{
  "name": "intentional failure",
  "request": { "method": "GET", "path": "/" },
  "expect":  { "status": 599 }
}
```

Runner should exit with `1` (one failure).
