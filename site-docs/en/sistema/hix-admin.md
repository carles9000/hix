# 👑 Admin panel

HIX exposes a set of **administration endpoints** under the `/hix-*` prefix
that allow you to check server status, reload routes, clear caches, enable/disable
traces, and stop the server gracefully. All are protected by an **admin session
with a signed cookie** (`hix_admin`).

The panel self-configures on first startup: if there are no credentials, it
redirects to `/hix-setup` so you can create the initial user/password.

---

## When do you need it?

- To **monitor** the server in production (`/hix-status`).
- To **reload routes** from `routes/*.json` without restarting.
- To **clear the view cache** after a deploy.
- To **stop HIX** from a remote script without TTY access.
- To **enable traces** on specific modules and diagnose a problem.

---

## Setup in `hix.json`

### `admin` section

`enabled = false` disables the panel and the `/hix-*` routes. Empty `user` /
`password` enables `/hix-setup`. The admin session lifetime is controlled by
`session.lifetime` (minutes).

```json
{
  "admin": {
    "enabled":  true,
    "user":     "",
    "password": "",
    "secret":   ""
  }
}
```

With `user` and `password` empty, any request to an admin endpoint **redirects
to `/hix-setup`** to create credentials. Once created, HIX writes them to
`hix.json` with `oCfg:Generate()`.

### Behavior by `env`

| `app.env` | Auth required                   |
|-----------|---------------------------------|
| `dev`     | **No** - open access            |
| `prod`    | **Yes** - `hix_admin` cookie    |

In `dev` the endpoints are open for quick iteration. In `prod` they require login.

---

## Available endpoints

All are defined in `src/hix_router.prg` and depend on `HIX_AdminCheck(oReq)`.

### Operation

| Route                      | Method    | Description                                          |
|----------------------------|-----------|------------------------------------------------------|
| `/hix-ping`                | GET       | Public healthcheck (no auth required)                |
| `/hix-status`              | GET       | JSON with all [metrics](metricas.md)                 |
| `/hix-monitor`             | GET       | HTML page with interactive dashboard                 |
| `/hix-index`               | GET       | HTML page listing all registered routes              |
| `/hix-stop`                | GET       | Stops the server gracefully                          |
| `/hix-cache-clear`         | GET       | Clears view cache (RAM + disk)                       |
| `/hix-trace`               | GET/POST  | Lists or adjusts traces by module                    |

### Dynamic routes

| Route                      | Method    | Description                                          |
|----------------------------|-----------|------------------------------------------------------|
| `/hix-routes/list`         | GET       | Lists registered routes (except internal `hix.*`)    |
| `/hix-routes/listall`      | GET       | Lists ALL routes, including system ones              |
| `/hix-routes/add`          | POST      | Adds a new route (JSON body)                         |
| `/hix-routes/delete`       | POST      | Deletes a route (JSON body `{name: "..."}`)          |
| `/hix-routes/reload`       | GET       | Reloads routes from `routes/*.json`                  |

### Benchmark

| Route                      | Method    | Description                                          |
|----------------------------|-----------|------------------------------------------------------|
| `/hix-bench-start`         | GET       | Resets metrics and starts measurement window         |
| `/hix-bench-stop`          | GET       | Returns JSON with metrics accumulated in the window  |

### Authentication

| Route                      | Method    | Description                                          |
|----------------------------|-----------|------------------------------------------------------|
| `/hix-login`               | GET/POST  | Admin login page and submit                          |
| `/hix-logout`              | GET       | Clears the `hix_admin` cookie                        |
| `/hix-setup`               | GET/POST  | Initial credentials creation page                    |

> 🔒 If `admin.enabled = false`, none of these routes are registered and any
> request to `/hix-*` returns 404.

---

## Session and cookie

When login is successful, HIX signs the cookie with simulated HMAC:

```
hix_admin = <timestamp>:<md5( cAdminSecret + "|" + timestamp )>
```

On each admin request, `HIX_AdminCheck(oReq)`:

1. Reads the `hix_admin` cookie.
2. Verifies the signature with `cAdminSecret`.
3. Checks that `now - timestamp < session.lifetime * 60` (if `lifetime > 0`).
4. If it fails, redirects to `/hix-login?next=<current_route>`.

The cookie is **HttpOnly; SameSite=Lax; Path=/** and is renewed on each login.

---

## First startup flow

```
1. You start HIX for the first time (admin user/password empty)
            │
            ▼
2. You access /hix-status
            │
            ▼
3. HIX redirects to /hix-setup
            │
            ▼
4. You fill user + password (minimum 6 characters)
            │
            ▼
5. HIX saves user/MD5(password)/secret in hix.json
            │
            ▼
6. Redirects to /hix-login
            │
            ▼
7. You log in → signed hix_admin cookie → full access
```

> 💡 The `secret` is generated with `MD5( timestamp + user + password )` on first
> run. If you want to **invalidate all admin sessions**, just empty `secret` in
> `hix.json` — HIX will generate a new one on the next setup/login.

---

## Example: consuming `/hix-status` from monitoring

```bash
# 1. Login and save the cookie
curl -c hix.jar -X POST https://myserver.com/hix-login \
  -d 'user=admin&password=secret'

# 2. Consume status
curl -b hix.jar https://myserver.com/hix-status
```

Output:

```json
{ "requests": 18472, "errors": 12, "uptimesec": 78423, ... }
```

For integration with **Prometheus**, just wrap it in a trivial exporter that
does GET every 30 seconds.

---

## Dynamic traces with `/hix-trace`

`GET /hix-trace` returns the hash of active traces by module:

```json
{ "router": true, "session": false, "auth": true }
```

`POST /hix-trace` with JSON body adjusts a specific trace:

```json
{ "module": "router", "enabled": true }
```

Useful for diagnosing a problem in production without touching `hix.json`.
When done, disable the trace again to keep the log clean.

> 📚 More detail in [logger - trace by module](logger.md#trace-por-módulo).

---

## Disabling the panel

In very restrictive environments you can turn off the entire panel:

```json
{
  "admin": {
    "enabled": false
  }
}
```

This **does not register the admin endpoints** (`/hix-status`, `/hix-monitor`,
`/hix-stop`, `/hix-login`, `/hix-routes/*`, etc.). Requests to those URLs
return 404.

> ℹ️ `/hix-ping` and `/hix-slow` are **always** registered (they are public
> health-check routes and do not depend on `admin.enabled`).

> ⚠️ If you disable it, you'll lose `/hix-status` and the other endpoints. To
> monitor you'll have to expose your own endpoint consuming `HIX_MetricsJson()`
> with your auth.

---

## Common errors

| Symptom                                        | Cause                                              | Fix                                                |
|------------------------------------------------|----------------------------------------------------|----------------------------------------------------|
| `/hix-status` redirects to `/hix-setup`        | `admin.user` / `password` empty                    | Complete setup from `/hix-setup`                   |
| After login, redirects again to `/hix-login`   | `secret` different from what signed the cookie    | Delete cookie in browser, log in again             |
| Cookie expires too fast                        | `session.lifetime` too low                         | Raise the value (minutes, `0` = indefinite)        |
| `/hix-routes/add` returns 401                  | Missing admin cookie or it expired                 | Login at `/hix-login` first                        |
| Don't want login in dev                        | You're in `env = "prod"`                           | Change `app.env = "dev"`                           |

---

## Best practices

- **`app.env = "prod"` always on servers exposed to the internet**. With `"dev"`
  anyone can shut down the server with `/hix-stop`.
- **Change `secret` periodically** by emptying it in `hix.json` to force cookie
  rotation.
- If your HIX is behind [Apache/Nginx](apache-proxy.md), **limit access to
  `/hix-*` by IP** in the reverse proxy as an extra layer.
- **Don't expose `/hix-stop` or `/hix-cache-clear`** on open internet — protect
  them with firewall if possible.
- For CI/CD, **use a dedicated admin account** different from the human operator's;
  rotate its password when rotating the team.
