# 🖥️ Apache / Nginx reverse proxy

HIX can run in two topologies:

- **Standalone** — HIX listens directly on port 80/443 and handles internet
  traffic without intermediaries.
- **Behind a reverse proxy** (Apache, Nginx, Cloudflare Tunnel, Traefik...) —
  the proxy terminates SSL, load-balances, compresses, and forwards the request
  to HIX over plain HTTP on an internal port.

When you work behind a proxy, **HIX needs to know** in order to correctly
reconstruct the client's real IP, the scheme (`http` vs `https`), and the
original host. That configuration is the **`proxied` mode**.

---

## When do you need it?

- To serve **HTTPS with Let's Encrypt** without managing certificates in HIX.
- To place HIX behind **existing Apache/Nginx** that already serves other sites.
- To use **Cloudflare** as CDN/WAF in front of HIX.
- To **load-balance** multiple HIX instances behind a single frontend.
- To offload **TLS and compression** from HIX and dedicate it to application logic.

---

## Setup in `hix.json`

### `server` section

`host = 127.0.0.1` → listens only locally, proxy is the sole client.
`port = 8080` → internal port.
`mode = "proxied"` → HIX knows it's behind a proxy and reads `X-Forwarded-*` / `Forwarded`.

```json
{
  "server": {
    "host": "127.0.0.1",
    "port": 8080,
    "mode": "proxied"
  }
}
```

### `server` section — trusted proxy list

```json
{
  "server": {
    "trusted_proxies": "127.0.0.1 ::1 10.0.0.0/8"
  }
}
```

`trusted_proxies` is a space-separated list of IPs or CIDR ranges whose
`X-Forwarded-*` headers HIX will accept. **Without this list, HIX ignores the
headers** and uses the TCP connection IP (the proxy's, not the client's).

> ⚠️ **Never use `0.0.0.0/0` as trusted_proxy**. That would allow any external
> client to spoof their IP by sending a forged `X-Forwarded-For`. List only IPs
> you control.

---

## Supported headers

HIX detects the client's real IP by looking, in order:

1. `CF-Connecting-IP` (Cloudflare)
2. `X-Forwarded-For` (first public value in the chain)
3. `X-Real-IP` (classic Nginx)
4. `Client-IP` (legacy)
5. The TCP connection IP (fallback)

It also understands **RFC 7239 `Forwarded:`** (modern standard):

```
Forwarded: for=203.0.113.5;proto=https;host=myapp.com
```

`HIX_ParseForwarded()` extracts `for`, `proto`, `host`, `by`, `port` from the
first hop (closest to the client).

---

## Apache configuration

### Basic reverse proxy

```apache
<VirtualHost *:443>
   ServerName myapp.com

   SSLEngine on
   SSLCertificateFile      /etc/letsencrypt/live/myapp.com/fullchain.pem
   SSLCertificateKeyFile   /etc/letsencrypt/live/myapp.com/privkey.pem

   ProxyPreserveHost On
   ProxyRequests     Off

   # HTTP — all requests to HIX
   ProxyPass        / http://127.0.0.1:8080/
   ProxyPassReverse / http://127.0.0.1:8080/

   # Headers for HIX
   RequestHeader set X-Forwarded-Proto "https"
   RequestHeader set X-Forwarded-Host  "%{HTTP_HOST}s"
   # X-Forwarded-For added by Apache automatically

   # For WebSockets (pool_ws)
   RewriteEngine on
   RewriteCond %{HTTP:Upgrade} =websocket [NC]
   RewriteRule /(.*) ws://127.0.0.1:8080/$1 [P,L]
</VirtualHost>
```

Required modules: `proxy`, `proxy_http`, `proxy_wstunnel`, `rewrite`, `headers`,
`ssl`.

### Healthcheck

Apache can test HIX with the public `/hix-ping` endpoint:

```apache
<Proxy "balancer://hix">
   BalancerMember "http://127.0.0.1:8080" route=hix1
   ProxySet hcmethod=GET hcuri=/hix-ping hcinterval=10
</Proxy>
```

---

## Nginx configuration

```nginx
upstream hix {
   server 127.0.0.1:8080;
}

server {
   listen 443 ssl http2;
   server_name myapp.com;

   ssl_certificate     /etc/letsencrypt/live/myapp.com/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/myapp.com/privkey.pem;

   location / {
      proxy_pass         http://hix;
      proxy_http_version 1.1;

      # Forwarded headers (HIX reads them if IP is in trusted_proxies)
      proxy_set_header Host              $host;
      proxy_set_header X-Real-IP         $remote_addr;
      proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-Host  $host;

      # WebSockets — HIX pool_ws
      proxy_set_header Upgrade    $http_upgrade;
      proxy_set_header Connection "upgrade";

      # SSE — HIX pool_rest
      proxy_buffering off;
      proxy_read_timeout 3600s;
   }
}
```

> 💡 For SSE (`/events`), **`proxy_buffering off`** is **mandatory**. Without it,
> Nginx buffers the stream and nothing reaches the client.

---

## Reading from code

With `server.mode = "proxied"`, HIX helpers return values "seen" from the real
client, not from the proxy:

```clipper
UIP()       // -> "203.0.113.5"   (real client IP, not proxy)
UScheme()   // -> "https"          (reads X-Forwarded-Proto)
UIsHttps()  // -> .T.
UHost()     // -> "myapp.com"      (reads X-Forwarded-Host)
```

Without `server.mode = "proxied"`:

```clipper
UIP()       // -> "127.0.0.1"      (TCP IP of proxy)
UScheme()   // -> "http"
UIsHttps()  // -> .F.
```

> 🔍 The function `HIX_GetClientIP(oReq)` additionally applies a
> **`HIX_IsPublicIP()`** filter on the `X-Forwarded-For` chain to discard
> injected private IPs. It takes the first **public** IP in the chain.

---

## Cloudflare

If HIX is behind Cloudflare (Tunnel, orange proxy, R2):

1. Add Cloudflare ranges to `trusted_proxies`:

   ```json
   {
     "server": {
       "trusted_proxies": "173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 ..."
     }
   }
   ```

   Updated list: https://www.cloudflare.com/ips/

2. Activate `server.mode = "proxied"`.

3. HIX will automatically detect the `CF-Connecting-IP` header that Cloudflare
   adds with the client's real IP, even if you don't send `X-Forwarded-For`.

---

## Common errors

| Symptom                                  | Cause                                                | Fix                                                  |
|------------------------------------------|------------------------------------------------------|------------------------------------------------------|
| `UIP()` returns the proxy's IP           | `server.mode != "proxied"`                           | Configure correctly                                  |
| `UIP()` spoofable from outside           | `trusted_proxies` empty or `0.0.0.0/0`               | Limit to actual proxy IPs                            |
| WebSocket won't connect after Apache     | Missing `proxy_wstunnel` or `Upgrade` rule           | Add `RewriteRule [P]` with `ws://`                   |
| SSE doesn't reach the client             | Nginx is buffering                                   | `proxy_buffering off; proxy_read_timeout 3600s;`     |
| Redirects go to `http://` not `https`    | HIX doesn't see `X-Forwarded-Proto`                  | `proxy_set_header X-Forwarded-Proto $scheme;`        |
| Cookies lose `Secure`                    | HIX thinks it's plain HTTP                           | Activate `server.mode = "proxied"` so `UIsHttps()` is `.T.` |

---

## Best practices

- **`host = 127.0.0.1`** when HIX is behind a local proxy: no external user
  can bypass the proxy by talking directly to HIX.
- **`trusted_proxies` as restrictive as possible**: only the actual proxy IPs,
  never entire public ranges.
- **Terminate TLS at the proxy**, not in HIX. You leverage the certbot/Let's
  Encrypt ecosystem without moving anything on the HIX side.
- For WebSockets, keep `proxy_read_timeout` ≥ HIX's `ping_interval_s` plus a
  margin, or idle connections will be cut.
- Use the public `/hix-ping` endpoint as the **healthcheck** for your balancer.
- In multi-HIX topologies, use **sticky sessions** if you rely on in-memory
  sessions (`session.storage = "memory"`). If you switch to `"file"`, all HIX
  instances must share the `paths.session` folder.
