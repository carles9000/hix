# 🛠️ `hix.json` Configuration

All HIX configuration lives in a single `hix.json` file located alongside
the server executable. It works the same for using HIX in **basic mode**
(programmatic routes, manual templates) as for **HixStyle mode**
(MVC engine, loaders, views, controllers).

---



## Column convention

In the master table each parameter has two environment-marking columns:

| Column       | Meaning                                                               |
|---------------|-----------------------------------------------------------------------|
| **Basic**     | Affects the server in basic HIX mode (programmatic Harbour routes + static files)|
| **HixStyle**  | Affects the server in HixStyle mode (`enabled = true`)                      |

✅ = the parameter is relevant in that environment.
❌ = the parameter **has no effect** or is not used in that environment.

The keys marked only under **HixStyle** are:

- The entire `hixstyle` section

The rest affects both environments equally.

---

## Master parameter table

| Section        | Key               | Default        | Basic | HixStyle | Description                                                                       |
|----------------|-------------------|----------------|:-----:|:--------:|-----------------------------------------------------------------------------------|
| `server`       | `host`            | `localhost`    |   ✅   |    ✅    | Listen interface. `0.0.0.0` = all. `localhost` = local only.                       |
| `server`       | `port`            | `80`           |   ✅   |    ✅    | TCP port. Ports < 1024 require admin/root.                                        |
| `server`       | `maxconn`         | `1024`         |   ✅   |    ✅    | Maximum simultaneous connections.                                                 |
| `server`       | `timeout`         | `30`           |   ✅   |    ✅    | Connection timeout (seconds).                                                     |
| `server`       | `name`            | `HIX/2.1`      |   ✅   |    ✅    | HTTP header value `Server:`.                                                      |
| `server`       | `mode`            | `standalone`   |   ✅   |    ✅    | `standalone` or `proxied` (behind nginx/Apache).                                  |
| `server`       | `trusted_proxies` | `127.0.0.1 ::1`|   ✅   |    ✅    | Trusted IPs/CIDR, space-separated (`mode=proxied`).                              |
| `server`       | `ssl`             | `false`        |   ✅   |    ✅    | Enables TLS. Requires `cert_private` + `cert_public`.                             |
| `server`       | `cert_private`    | `""`           |   ✅   |    ✅    | Private key filename `.key` (inside `paths.certs`).                               |
| `server`       | `cert_public`     | `""`           |   ✅   |    ✅    | Certificate filename `.crt` (inside `paths.certs`).                               |
| `server`       | `gzip`            | `true`         |   ✅   |    ✅    | Compresses HTTP responses.                                                        |
| `server`       | `gzip_min_size`   | `2048`         |   ✅   |    ✅    | Minimum body size to compress (bytes).                                            |
| `server`       | `autostart`       | `true`         |   ✅   |    ✅    | Opens the browser at the server URL on startup.                                   |
| `server`       | `exec_timeout_ms` | `30000`        |   ✅   |    ✅    | Maximum execution time for `.prg`/`.hrb` (ms). `0` = no limit.                    |
| `paths`        | `root`            | `www`          |   ✅   |    ✅    | Document root.                                                                    |
| `paths`        | `log`             | `.logs`        |   ✅   |    ✅    | Logs directory.                                                                   |
| `paths`        | `tmp`             | `tmp`          |   ✅   |    ✅    | Temp files (uploads, transpiles).                                                 |
| `paths`        | `errors`          | `.logs`        |   ✅   |    ✅    | Custom HTTP error pages.                                                          |
| `paths`        | `session`         | `.sessions`    |   ✅   |    ✅    | Session storage (`storage=file`).                                                 |
| `paths`        | `certs`           | `certs`        |   ✅   |    ✅    | SSL/TLS certificates directory.                                                   |
| `app`          | `errorsys`        | `""`           |   ✅   |    ✅    | HTML template for the errorsys screen (relative to `root/`). Empty = use built-in.|
| `app`          | `default_page`    | `index.html`   |   ✅   |    ✅    | Default resource when the URL has no file.                                        |
| `app`          | `dispatch_mode`   | `full`         |   ✅   |    ✅    | `routes` (programmatic only) / `static` (+ files) / `full` (+ prg/hrb).           |
| `app`          | `auto_close_dbf`  | `true`         |   ✅   |    ✅    | Closes open DBFs at the end of the request.                                       |
| `app`          | `auto_close_dbf_log` | `false`     |   ✅   |    ✅    | Logs every auto-close of DBF.                                                     |
| `app`          | `env`             | `dev`          |   ✅   |    ✅    | `dev` (detailed errors) / `prod` (generic errors).                                |
| `app`          | `debug`           | `false`        |   ✅   |    ✅    | `true` = DEBUG level to console.                                                  |
| `admin`        | `enabled`         | `true`         |   ✅   |    ✅    | `false` = disables the admin panel and all `/hix-*` routes.                       |
| `admin`        | `user`            | `""`           |   ✅   |    ✅    | Admin user.                                                                       |
| `admin`        | `password`        | `""`           |   ✅   |    ✅    | MD5 hash of the password. Empty = shows `/hix-setup`.                             |
| `admin`        | `secret`          | `""`           |   ✅   |    ✅    | Cookie signing key, auto-generated by `/hix-setup`.                               |
| `detector`     | `workers`         | `4`            |   ✅   |    ✅    | Workers that detect protocol on each new connection.                              |
| `detector`     | `queue_size`      | `256`          |   ✅   |    ✅    | Internal queue.                                                                   |
| `detector`     | `peek_timeout_ms` | `100`          |   ✅   |    ✅    | Maximum wait for first byte. LAN=10, internet=50.                                 |
| `detector`     | `peek_bytes`      | `512`          |   ✅   |    ✅    | Bytes to read to identify the protocol.                                           |
| `pool_http`    | `workers`         | `64`           |   ✅   |    ✅    | HTTP workers (~1MB stack/thread on Windows).                                      |
| `pool_http`    | `queue_size`      | `256`          |   ✅   |    ✅    | Queue of pending requests.                                                        |
| `pool_http`    | `read_timeout_ms` | `2000`         |   ✅   |    ✅    | HTTP header read timeout (ms).                                                    |
| `pool_http`    | `keep_alive`      | `true`         |   ✅   |    ✅    | Enables HTTP Keep-Alive.                                                          |
| `pool_http`    | `keep_alive_max`  | `100`          |   ✅   |    ✅    | Maximum requests per keep-alive connection.                                       |
| `pool_ws`      | `workers`         | `100`          |   ✅   |    ✅    | WebSocket workers. Each active WS uses 1 worker until closed.                     |
| `pool_ws`      | `queue_size`      | `256`          |   ✅   |    ✅    | Queue of pending connections.                                                     |
| `pool_ws`      | `ping_interval_s` | `30`           |   ✅   |    ✅    | Client ping interval (seconds).                                                   |
| `pool_ws`      | `ping_timeout_s`  | `10`           |   ✅   |    ✅    | Ping response timeout (seconds).                                                  |
| `pool_rest`    | `workers_sse`     | `20`           |   ✅   |    ✅    | Workers for Server-Sent Events (each SSE takes 1).                                |
| `pool_rest`    | `workers_longpoll`| `10`           |   ✅   |    ✅    | Workers for Long Polling.                                                         |
| `pool_rest`    | `queue_size`      | `128`          |   ✅   |    ✅    | Shared queue.                                                                     |
| `pool_rest`    | `stream_timeout_s`| `3600`         |   ✅   |    ✅    | Maximum duration of an open stream (seconds).                                     |
| `pool_hix`     | `workers`         | `4`            |   ✅   |    ✅    | Workers dedicated to the internal HIX channel.                                    |
| `pool_hix`     | `queue_size`      | `64`           |   ✅   |    ✅    | HIX pool queue.                                                                   |
| `pool_hix`     | `read_timeout_ms` | `2000`         |   ✅   |    ✅    | Read timeout (ms).                                                                |
| `session`      | `storage`         | `memory`       |   ✅   |    ✅    | `memory` (volatile, fast) / `file` (persistent).                                  |
| `session`      | `prefix`          | `sess_`        |   ✅   |    ✅    | Session file name prefix.                                                         |
| `session`      | `crypt`           | `false`        |   ✅   |    ✅    | Encrypts session data on disk.                                                    |
| `session`      | `seed`            | `""`           |   ✅   |    ✅    | Encryption key (required if `crypt=true`).                                        |
| `session`      | `lifetime`        | `60`           |   ✅   |    ✅    | Session lifetime in minutes (applies to user and admin cookie). `0` = unlimited.  |
| `session`      | `gc_days`         | `3`            |   ✅   |    ✅    | Days for GC of orphaned session files (only `storage=file`).                      |
| `monitor`      | `enabled`         | `true`         |   ✅   |    ✅    | Enables the health monitor thread.                                                |
| `monitor`      | `interval_s`      | `5`            |   ✅   |    ✅    | Check interval (seconds).                                                         |
| `monitor`      | `alert_pct`       | `75`           |   ✅   |    ✅    | % queue usage that triggers the `SATURATED` alert.                                |
| `log`          | `file`            | `hix.log`      |   ✅   |    ✅    | Log filename (path = `paths.log`).                                                |
| `log`          | `level`           | `info`         |   ✅   |    ✅    | `debug` / `info` / `warn` / `error` / `fatal`.                                    |
| `log`          | `console`         | `true`         |   ✅   |    ✅    | `true` = duplicates output to console.                                            |
| `log`          | `max_size_mb`     | `10`           |   ✅   |    ✅    | Maximum size before rotation (MB).                                                |
| `log`          | `max_files`       | `0`            |   ✅   |    ✅    | Maximum retained backups. `0` = unlimited.                                        |
| `access_log`   | `enabled`         | `true`         |   ✅   |    ✅    | Enables the HTTP access log (Common Log Format).                                  |
| `access_log`   | `file`            | `access.log`   |   ✅   |    ✅    | Access log filename (path = `paths.log`).                                         |
| `firewall`     | `mode`            | `blacklist`    |   ✅   |    ✅    | `blacklist` (blocks listed) / `whitelist` (listed only).                          |
| `firewall`     | `filter`          | `""`           |   ✅   |    ✅    | Comma-separated list of IP/CIDR. E.g.: `192.168.1.0/24, 10.0.0.0/8`.              |
| `hixstyle`     | `enabled`         | `false`        |   ❌   |    ✅    | Enables the MVC HixStyle engine.                                                  |
| `hixstyle`     | `cache_disk`      | `true`         |   ❌   |    ✅    | Caches compiled views to disk (`.cached/views/`).                                 |
| `hixstyle`     | `trace`           | `false`        |   ❌   |    ✅    | Enables HixStyle trace in the log.                                                |
| `hixstyle`     | `cache_ram`       | `false`        |   ❌   |    ✅    | Global view cache in shared RAM across workers. ~10× faster than disk.             |
| `trace`        | `app`             | `true`         |   ✅   |    ✅    | Trace of module `app`.                                                            |
| `trace`        | `server`          | `true`         |   ✅   |    ✅    | Trace of module `server`.                                                         |
| `trace`        | `worker_http`     | `false`        |   ✅   |    ✅    | Trace of HTTP worker.                                                             |
| `trace`        | `worker_ws`       | `false`        |   ✅   |    ✅    | Trace of WebSocket worker.                                                        |
| `trace`        | `worker_otros`    | `false`        |   ✅   |    ✅    | Trace of SSE/LongPoll worker.                                                     |
| `trace`        | `pool`            | `false`        |   ✅   |    ✅    | Trace of pools.                                                                   |
| `trace`        | `pool_detector`   | `false`        |   ✅   |    ✅    | Trace of protocol detector.                                                       |
| `trace`        | `metrics`         | `false`        |   ✅   |    ✅    | Trace of metrics module.                                                          |
| `trace`        | `config`          | `false`        |   ✅   |    ✅    | Trace of configuration loading.                                                   |
| `trace`        | `socket`          | `false`        |   ✅   |    ✅    | Trace of socket operations.                                                       |
| `trace`        | `monitor`         | `false`        |   ✅   |    ✅    | Trace of monitor.                                                                 |
| `trace`        | `response`        | `false`        |   ✅   |    ✅    | Trace of response module.                                                         |
| `trace`        | `logger`          | `false`        |   ✅   |    ✅    | Trace of the logger itself.                                                       |
| `trace`        | `error`           | `false`        |   ✅   |    ✅    | Trace of errors.                                                                  |

> Hot-toggle trace: `GET /hix-trace?mod=<module>&on=1`.
> `WARN`/`ERROR`/`FATAL` are always logged, regardless of trace.

---

## Section summary

### `server` - network and identity
Defines how the server listens: interface, port, TLS, and mode (standalone or
behind a proxy). Set before the first production startup.

### `paths` - disk layout
Server root structure. Change if you want to relocate `www/`, logs, or
sessions to another drive.

### `app` - application
`errorsys` template for the system error screen, `env` (dev/prod),
`debug`, dispatcher, execution timeout, default page. Custom error pages live in the fixed folder
`<paths.root>/errors/`. The file
`<paths.root>/config.json` (optional) and the folder
`<paths.root>/loaders/` (optional) are loaded automatically if they exist.

### `admin` - `/hix-*` panel
Admin panel credentials. If you leave `password` empty, the first access to
`/hix-setup` sets it up. `enabled = false` turns off all `/hix-*` routes.

### `detector`, `pool_http`, `pool_ws`, `pool_rest`, `pool_hix` - concurrency
Pool and queue sizes. Defaults handle medium traffic; adjust if the
monitor reports saturation (`SATURATED` when the queue exceeds `alert_pct`).

### `session` - HTTP sessions
`memory` is the fastest but is lost on restart. `file` persists but
adds I/O. For multi-process always use `file` with `seed`.

### `monitor`, `log`, `access_log` - observability
Main logger with rotation, CLF access log, and health monitor exposing
`/hix-status`. See also: [sistema/logger](../../sistema/logger.md),
[sistema/metricas](../../sistema/metricas.md).

### `firewall` - IP filtering
Whitelist or blacklist of IPs/CIDR. See
[hixstyle/seguridad/firewall](../../hixstyle/seguridad/firewall.md).

### `hixstyle` - MVC engine
Enables and tunes HixStyle. Applies only if `enabled = true`.

### `trace` - per-module verbosity
Binary flags to enable traces for each core module. Useful for
diagnosing specific problems without flooding the log.


Although many parameters are visible, this is just the definition of a
web server's parameters. You should not change these parameters unless you know exactly what they do.
Don't worry at first: everything is already configured.
