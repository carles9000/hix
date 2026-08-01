# 🧱 Firewall - IP Filtering

## What is it?

The **firewall** in HIX decides, **before** accepting a TCP connection,
whether the client's IP is allowed in. It's the **first line of defense**:
if the IP is blocked, HTTP is never even spoken - the socket closes immediately.

```
TCP accept()    ┌───────────────────┐
   ↓            │   Firewall check  │
  cIP ------->  │  ¿IP allowed?     │
                └─────────┬─────────┘
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
        ✅ continue pipeline    ❌ socket close
        (HTTP/WS/SSE)
```

---

## When to use it

| Case | Firewall |
|---|---|
| Block specific IPs that abuse | ✅ Yes - blacklist |
| Limit admin panel to internal network | ✅ Yes - whitelist with CIDR |
| API only accessible from certain partners | ✅ Yes - whitelist |
| Block entire countries | ⚠️ Yes, but carefully - use GeoIP DBs outside |
| Replace auth | ❌ No - IP changes, doesn't authenticate |
| Replace rate limit | ❌ No - new IPs slip through |

---

## Setup

### From `hix.json`

```json
{
  "firewall": {
    "mode":   "blacklist",
    "filter": "1.2.3.4 10.0.0.0/8 192.168.1.10-192.168.1.50"
  }
}
```

### From code

```clipper
HIX_FirewallSetup( ;
   "1.2.3.4 10.0.0.0/8 !10.0.1.0/24",   ;   // cFilter
   "blacklist" )                            // cMode: blacklist | whitelist
```

Call **before** `oSrv:Start()`. If `cFilter` is empty, the firewall
is disabled and lets everything through.

### Disable at runtime

```clipper
HIX_FirewallClear()        // allows any IP
```

---

## Modes

| Mode | Meaning |
|---|---|
| **`blacklist`** | IPs in the filter are **blocked**. All others pass. |
| **`whitelist`** | Only IPs in the filter **pass**. The rest are blocked. |

```clipper
// Blacklist - blocks known attackers
HIX_FirewallSetup( "1.2.3.4 5.6.7.8 198.51.100.0/24", "blacklist" )

// Whitelist - office + VPN only
HIX_FirewallSetup( "10.0.0.0/8 203.0.113.42", "whitelist" )
```

---

## Filter syntax

List of expressions separated by **spaces or commas** (both valid - use
whichever looks cleaner in your `hix.json`). Each expression is one of these forms:

| Form | Example | Represents |
|---|---|---|
| Individual IP | `1.2.3.4` | Just that IP |
| CIDR | `192.168.1.0/24` | `/24` block |
| Dotted netmask | `192.168.1.0/255.255.255.0` | Equivalent to `/24` |
| Range | `192.168.1.10-192.168.1.50` | All IPs in the range |
| Exclusion | `!10.0.1.0/24` | Excludes a sub-block |
| IPv6 | `::1` `2001:db8::/32` | Also supported |

### Combining inclusion + exclusion

```json
{
  "firewall": {
    "filter": "10.0.0.0/8 !10.0.1.0/24 !10.0.2.5"
  }
}
```

Equivalent to: "all `10.0.0.0/8` **except** `10.0.1.0/24` and IP
`10.0.2.5`".

```clipper
HIX_FirewallSetup( "10.0.0.0/8 !10.0.1.0/24 !10.0.2.5", "whitelist" )
```

Exclusions (`!`) are applied after merging inclusions - the
parser leaves a final sorted and compact set.

---

## Complete examples

### Admin panel for LAN only

```json
{
  "firewall": {
    "mode":   "whitelist",
    "filter": "127.0.0.1 ::1 192.168.0.0/16 10.0.0.0/8"
  }
}
```

Only localhost and private networks reach the server. Internet → drop.

### Block detected attackers

```json
{
  "firewall": {
    "mode":   "blacklist",
    "filter": "1.2.3.4 5.6.7.8 91.0.0.0/8"
  }
}
```

Each IP/block falls silent (no HTTP response). Useful for removing
scrapers you've already identified.

### Whitelist with internal exceptions

```json
{
  "firewall": {
    "mode":   "whitelist",
    "filter": "203.0.113.0/24 !203.0.113.99"
  }
}
```

IPs in the `/24` block pass **except** `203.0.113.99` (server under
maintenance, for example).

---

## Behind proxies

If HIX is behind a load balancer (Apache, Nginx, AWS ALB), the IP the
firewall sees is the **proxy's**, not the real client's. IP filtering
**doesn't work** unless you configure it.

```json
{
  "server": {
    "mode": "proxied"
  }
}
```

With `server.mode = "proxied"`, HIX reads `X-Forwarded-For` / `X-Real-IP` to identify
the real client. But **the firewall acts at `accept()`**, before parsing
headers - the IP it filters is the TCP socket's.

> That's why the firewall is only useful when HIX is **directly exposed**.
> Behind a proxy, configure the firewall **in the proxy**
> (mod_authz_host in Apache, deny in Nginx).

---

## Manual verification

Useful for tests or checking if an IP is allowed:

```clipper
IF HIX_FirewallCheck( "1.2.3.4" )
   ? "IP allowed"
ELSE
   ? "IP blocked"
ENDIF
```

---

## Comparison with other layers

| Layer | Blocks | When |
|---|---|---|
| **Firewall** | Specific IPs / ranges | At `accept()` - before HTTP |
| **[Rate Limit](ratelimit.md)** | Too many requests from same IP | Per HTTP request |
| **[CORS](cors.md)** | Cross-origin from browser | Per HTTP request |
| **[Auth](autenticacion.md)** | Unauthenticated user | Per HTTP request |

All four usually stack: firewall cuts bad IPs, rate limit slows abuse, CORS validates origin, and auth identifies the user.

---

## Best practices

1. **Whitelist for internal services.** Admin panel, metrics, or a
   webhook endpoint should be IP whitelisted.
2. **Blacklist for spot fires.** Block specific IPs after detecting abuse. Don't rely on blacklist as your only defense - IPs change.
3. **Don't block entire countries with manual lists.** Impossible to maintain.
   If you need serious geo-blocking, use GeoIP services outside the firewall.
4. **Combine with rate limit.** Firewall cuts **known** IPs;
   rate limit cuts **abusive unknown** IPs.
5. **Be careful with whitelist + IPv6.** If you publish IPv6, remember to add
   both v4 and v6 of your allowed locations.
6. **Test before applying whitelist in prod.** A bad whitelist locks you out of
   your own server - including your own IP.

