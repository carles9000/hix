# 🔒 SSL / TLS


**SSL/TLS** encrypts the channel between the browser and the server. Without it, everything travels in the clear—and that includes:

- Session cookies (`HIXSID=abc123`)—an intermediary can capture them and impersonate the user.
- Login credentials (`username=demo&password=1234`).
- JWT tokens (`Authorization: Bearer eyJ...`).
- The body of each response (sensitive user data).

With HTTPS, all that travels **encrypted** and signed. An attacker in the middle of the network only sees opaque bytes.

```
http://app.com   ─────▶  plaintext  ─────▶  server  (anyone reads)
https://app.com  ─────▶  TLS encrypt  ─────▶  server  (only server decrypts)
```

> In production, **HTTPS is not optional**. Anything with login, session, JWT, or payment **must** go through HTTPS. Modern browsers mark HTTP sites as "Not Secure" and block new APIs (geolocation, service workers, fetch with credentials, ...) without TLS.

---

## Activation in HIX

### From `hix.json`

```json
{
  "paths": {
    "certs": "certs"
  },
  "server": {
    "host":         "0.0.0.0",
    "port":         443,
    "ssl":          true,
    "cert_private": "hix.key",
    "cert_public":  "hix.crt"
  }
}
```

| Key | Value |
|---|---|
| `paths.certs` | Directory where certificate files reside (default: `certs`) |
| `ssl` | `true` enables TLS, `false` (default) disables it |
| `cert_private` | Name of the `.key` file inside `paths.certs` |
| `cert_public` | Name of the `.crt` file inside `paths.certs` |
| `port` | Convention: **443** for HTTPS, 80 for HTTP |

### From code

```clipper
LOCAL oCfg := THixConfig():New()
oCfg:lSSL          := .T.
oCfg:cCertPrivate  := "certs/hix.key"
oCfg:cCertPublic   := "certs/hix.crt"
oCfg:nPort         := 443

oSrv := THixServer():New( oCfg )
```

> On startup, `oCfg:Validate()` checks that both files exist. If not, the server writes an error to the log and **does not start**.

---

## Get a certificate

### Production—Let's Encrypt (free and automatic)

[Let's Encrypt](https://letsencrypt.org/) is a free CA that issues certificates with the **`certbot`** tool:

```bash
certbot certonly --standalone -d app.example.com
```

This generates two files in `/etc/letsencrypt/live/app.example.com/`:

- `privkey.pem` → `cert_private`
- `fullchain.pem` → `cert_public`

Certificates expire after 90 days—`certbot` is programmed to renew them automatically.

### Development—self-signed certificate

For `localhost`:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 ;
  -keyout certs/hix.key -out certs/hix.crt ;
  -subj "/CN=localhost"
```

The browser will show a "certificate not trusted" warning—it's expected. Fine for local testing; never for production.

---

## Detection helpers

From a controller you can know if the request arrived via HTTPS:

```clipper
UIsHttps()        // .T. / .F.
UScheme()         // "http" / "https"
```

Useful for forcing the cookie as `Secure`, or to redirect HTTP→HTTPS traffic:

```clipper
FUNCTION HixMwForceHttps( oCtx )
   IF ! UIsHttps()
      oCtx:lHandled := .T.
      URedirect( "https://" + UHost() + UPath(), 301 )
      RETURN .F.
   ENDIF
RETURN .T.
```

---

## HIX directly vs behind a proxy

### HIX directly (self-contained)

```json
{
  "paths": {
    "certs": "certs"
  },
  "server": {
    "host":         "0.0.0.0",
    "port":         443,
    "ssl":          true,
    "cert_private": "hix.key",
    "cert_public":  "hix.crt"
  }
}
```

HIX terminates TLS and serves HTTPS directly. Ideal for small apps or self-hosted.

### Behind a proxy (Apache / Nginx / Cloudflare)

The usual in production: the **proxy** terminates TLS and forwards plain HTTP to HIX on the internal network:

```json
{
  "server": {
    "host": "127.0.0.1",
    "port": 8080,
    "ssl":  false,
    "mode": "proxied"
  }
}
```

`server.ssl = false` → HIX speaks plain HTTP with the proxy. `server.mode = "proxied"` enables reading `X-Forwarded-*`.

```apache
# Apache reverse proxy
<VirtualHost *:443>
   ServerName app.example.com
   SSLEngine on
   SSLCertificateFile      /etc/letsencrypt/live/app.example.com/fullchain.pem
   SSLCertificateKeyFile   /etc/letsencrypt/live/app.example.com/privkey.pem

   ProxyPass        / http://127.0.0.1:8080/
   ProxyPassReverse / http://127.0.0.1:8080/
   RequestHeader set X-Forwarded-Proto "https"
   RequestHeader set X-Forwarded-For   "%{REMOTE_ADDR}s"
</VirtualHost>
```

| | HIX directly | Behind proxy |
|---|---|---|
| Terminates TLS | HIX | Proxy |
| Certificate | In HIX | In proxy |
| Renewal | Manual or cron | Managed by proxy |
| Multiple backends | ❌ | ✅ Load balancing |
| Suitable for | Small apps, dev | Serious production |

---

## Secure cookies with HTTPS

When everything goes through TLS, session cookies should be marked as **Secure** so the browser never sends them over HTTP:

```clipper
// Cookie marked as Secure (HTTPS only)
USetCookie( "session_id", cSid, 3600 )
// HIX automatically adds HttpOnly + SameSite=Lax
// Pending: Secure flag in newer versions—verify if exposed
```

> HIX cookies already carry `HttpOnly; SameSite=Lax` by default, which filters some attacks. The `Secure` flag is added by the proxy if it terminates TLS there, or needs to be enabled explicitly with local TLS.

---

## Common errors

| Symptom | Cause |
|---|---|
| `SSL: cert_private not found` on startup | Path to `.key` misspelled or file missing |
| `SSL: cert_public not found` | Same with the `.crt` |
| Browser: `NET::ERR_CERT_AUTHORITY_INVALID` | Self-signed certificate or unrecognized CA |
| `ERR_CERT_DATE_INVALID` | Expired certificate—renew with `certbot renew` |
| `ERR_SSL_PROTOCOL_ERROR` | Server doesn't speak TLS but client requested `https://` |
| Mixed content warnings | Your `https://` HTML loads `<img src="http://...">` — use relative URLs or `https://` |

---

## Best practices

1. **HTTPS in production always.** No exceptions. Let's Encrypt is free.
2. **HTTP → HTTPS redirect.** Port 80 is only for redirecting 301 to `https://` (or for certbot challenge).
3. **Automatic renewal.** `certbot renew` in cron + reload the server. If you don't, the certificate expires in 90 days and the app goes down.
4. **Behind a proxy in prod.** Terminate TLS in Apache/Nginx or a CDN. HIX stays on the internal network serving plain HTTP.
5. **HSTS.** Once everything is HTTPS, send the `Strict-Transport-Security: max-age=31536000; includeSubDomains` header so the browser rejects HTTP on future visits.
6. **No committed keys.** `certs/*.key` never to the repo. Add them to `.gitignore`.
