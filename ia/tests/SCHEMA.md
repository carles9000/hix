# `*.test.json` — Schema v1

Declarative HTTP test format for the HIX IA testing framework.

Each `*.test.json` file describes **one HTTP request** against a running HIX server, plus the expected response. The runner (`run.ps1`) iterates every `*.test.json` in a given directory and reports pass/fail.

---

## Full example

```json
{
  "name": "users list returns 200",
  "request": {
    "method": "GET",
    "path": "/users",
    "headers": { "Accept": "application/json" },
    "body": null
  },
  "expect": {
    "status": 200,
    "content_type_contains": "application/json",
    "body_contains": ["\"ok\""],
    "body_matches": "^\\{.*\\}$"
  }
}
```

---

## Fields

### `name` (required)

Human title. Shown in the runner report. Any string.

### `request` (required)

The HTTP request to send.

| Field | Type | Required | Notes |
|---|---|---|---|
| `method` | string | yes | `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS` |
| `path` | string | yes | Path relative to server root, must start with `/` |
| `headers` | object | no | Hash `{ "Header-Name": "value" }` |
| `body` | string \| null | no | Raw request body — encode JSON yourself if needed |

### `expect` (required)

What the runner checks about the response. All fields are optional; missing fields skip that check.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `status` | integer | `200` | HTTP status code must match exactly |
| `content_type_contains` | string | (skip) | Substring must appear in `Content-Type` header |
| `body_contains` | string[] | (skip) | Every string in the array must appear in the response body |
| `body_matches` | string | (skip) | Regex (single-line) must match the response body |

At least one `expect.*` field should be present, otherwise the test only verifies that the server responded at all.

---

## Notes and conventions

- **File naming**: `<what>.test.json`, e.g. `list.test.json`, `create.test.json`, `login-invalid.test.json`.
- **One test per file**. Batching multiple assertions in one file is intentionally not supported — keep tests atomic so failures are readable.
- **Port and host** are supplied by the runner via `-Port` / `-BaseUrl`. Never hardcode a port in a test file.
- **Regex** in `body_matches` uses .NET regex syntax (PowerShell native). Remember to escape `\` as `\\` in JSON.
- **`body_contains`** does raw substring matching — no JSON parsing, no whitespace normalization.

---

## More examples

### GET with expected JSON keys

```json
{
  "name": "health endpoint returns ok",
  "request": {
    "method": "GET",
    "path": "/health"
  },
  "expect": {
    "status": 200,
    "content_type_contains": "application/json",
    "body_contains": ["\"ok\"", "\"uptime\""]
  }
}
```

### POST form-encoded with 302 redirect

```json
{
  "name": "login redirects on success",
  "request": {
    "method": "POST",
    "path": "/login",
    "headers": { "Content-Type": "application/x-www-form-urlencoded" },
    "body": "user=admin&pass=secret"
  },
  "expect": {
    "status": 302
  }
}
```

### POST JSON body

```json
{
  "name": "create user returns 201",
  "request": {
    "method": "POST",
    "path": "/api/users",
    "headers": { "Content-Type": "application/json" },
    "body": "{\"name\":\"Ada\",\"email\":\"ada@example.com\"}"
  },
  "expect": {
    "status": 201,
    "content_type_contains": "application/json",
    "body_matches": "\"id\"\\s*:\\s*\\d+"
  }
}
```

### 404 expected

```json
{
  "name": "unknown route returns 404",
  "request": {
    "method": "GET",
    "path": "/does-not-exist"
  },
  "expect": {
    "status": 404
  }
}
```

---

## Not in v1 (intentionally out of scope)

- Chained tests (share cookies across requests).
- Full JSON schema validation.
- File upload / multipart bodies.
- Retries / eventual consistency waits.
- Assertions on individual response headers other than `Content-Type`.

If any of these become common, they will be added in v2 — but every skill that needs them today can express the check with `body_contains` + `body_matches`.
