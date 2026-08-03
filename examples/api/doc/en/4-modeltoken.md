# modeltoken.prg — Refresh token store

## What is it?

It is the **in-memory refresh token store**. It complements the JWT: the JWT has
a short lifetime (minutes), and the refresh token has a long lifetime (days) to
renew it without requiring a re-login.

---

## The problem it solves

In a pure JWT API you face this dilemma:

- **Long-lived JWT** → if someone steals it, they have access for days
- **Short-lived JWT** → the user must re-login every 15 minutes

The standard solution is **two tokens**:

| Token                      | Lifetime | Where it travels          | Purpose                        |
|----------------------------|----------|---------------------------|--------------------------------|
| **JWT** (access token)     | 15 min   | every request             | authorize operations           |
| **Refresh token**          | 1–N days | only at `/auth/refresh`   | renew the JWT without re-login |

---

## The strategy: rotation with reuse detection

This is the core of the model. When the client calls `/auth/refresh`:

```
Client:    "Here is my refresh token A"
Server:    - Marks A as revoked
           - Issues B (rot_from = A)
           - Returns new JWT + token B
Client:    Saves B, discards A
```

**What happens if someone steals token A and uses it later?**

```
Attacker:  "Here is A"
Server:    - A exists BUT is revoked
           - Calls _TokenRevokeChain(A)
           - Revokes B, C, D… (the entire chain of descendants)
           - Returns 401 → the legitimate user also loses access
           - Must re-login (this signals that a theft occurred)
```

This is called **Refresh Token Rotation** — it is the modern OAuth 2.0 pattern.

---

## The 4 public functions

```
ModelTokenInit()               → creates the pool at startup (once)
ModelTokenIssue(userId, ip)    → mints a new token, returns { token, exp }
ModelTokenRotate(token, ip)    → validates + revokes old + issues new
ModelTokenRevoke(token)        → logout: marks as revoked
```

---

## Implementation details

- **Store**: `HIX_DataPool("token")` — in-memory hash protected by its own mutex
- **Cleanup**: `_TokenPurge()` is called on every `Issue` — removes expired tokens
  without a background worker
- **TTL**: configurable via `UMwConfig("token", "ttl_days", 1)` — default 1 day
- **Token**: 48 random alphanumeric characters (≈ 285 bits of entropy)
