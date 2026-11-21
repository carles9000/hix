# 🔑 Password storage — `HIX_Password*`

## What is it?

Core HIX primitive for **storing passwords** securely. Converts a
human password (`"admin1234"`) into a portable record that can be
stored in DBF, SQL or JSON and verified later.

Algorithm: **PBKDF2-HMAC-SHA256** via OpenSSL `libcrypto` (the same
library HIX already loads for HMAC, JWT and CSRF — no new link-time
dependencies). Default minimum: **600 000 iterations**, per OWASP 2026.

!!! tip "Where it lives"
    Core module: `src/hix_password.prg`. The three public functions
    (`HIX_PasswordHash`, `HIX_PasswordVerify`, `HIX_PasswordNeedsRehash`)
    are available in any HIX app with no middleware or loader to register.

---

## Why not a simple `SHA256(password)`?

A fast hash (SHA256, MD5) is **trivial to brute-force**: a modern
GPU computes billions of SHA256 per second. A 10 M-word dictionary
cracks in seconds.

PBKDF2 adds **artificial cost**:

| Iterations | Legitimate login time | Attacker's tries/sec |
|---|---|---|
| 1               | ~1 µs   | ~1 000 000 000 |
| 100 000         | ~100 ms | ~10             |
| **600 000**     | ~600 ms | ~1.6            |
| 1 000 000       | ~1 s    | ~1              |

600 ms are imperceptible to the user; for an attacker with a DB
dump, each candidate password costs those same 600 ms. A 10 M-word
dictionary goes from "cracked in 10 s" to "cracked in 1–2 months" —
enough time to detect the breach and rotate.

The random per-user **salt** also defeats *rainbow tables*: two
users with the same password produce different hashes.

---

## Public API

```clipper
HIX_PasswordHash( cPassword [, nRounds ] )  -> hash record | NIL
HIX_PasswordVerify( cPassword, hRecord )    -> .T. | .F.
HIX_PasswordNeedsRehash( hRecord )          -> .T. | .F.
```

| Parameter | Valid range | Behavior out of range |
|---|---|---|
| `cPassword` | string, 1..1024 bytes | `NIL` / `.F.` |
| `nRounds`   | 600 000..2 000 000 (default 600 000) | `NIL` |
| `hRecord`   | hash with `PASSALG`, `PASSITER`, `SALT`, `PASSHASH` | `.F.` |

- The salt (16 OS-seeded bytes) is produced with `RAND_bytes` from libcrypto.
- `Verify` compares with `HIX_ConstantEq` → **timing-safe**: the
  attacker cannot infer the hash via latency differences.

---

## Hash record layout

```clipper
{ ;
   "PASSALG"  => "PBKDF2-SHA256",      ;   // algorithm tag
   "PASSITER" => 600000,               ;   // effective iteration count
   "SALT"     => "…32 hex chars…",     ;   // 16 bytes in hex (lowercase)
   "PASSHASH" => "…64 hex chars…"      ;   // 32 bytes in hex (lowercase)
}
```

Portable to any backend:

| Field | DBF | SQL | JSON |
|---|---|---|---|
| `PASSALG`  | `C(16)` | `VARCHAR(16)` | string |
| `PASSITER` | `N(9)`  | `INTEGER`     | number |
| `SALT`     | `C(32)` | `CHAR(32)`    | string |
| `PASSHASH` | `C(64)` | `CHAR(64)`    | string |

!!! warning "All 4 fields are mandatory"
    If you collapse the record into a single `encrypted_password`
    field you lose the ability to **raise the cost** (`PASSITER`) or
    **migrate algorithm** (`PASSALG`) without forcing every user to
    reset. The 4 fields together are the PBKDF2 contract.

---

## Typical flow

### User signup

```clipper
FUNCTION UserCreate()

   LOCAL hRec, oVal

   oVal := UValidateOrFail( { ;
      "user" => "required|string|max:40", ;
      "pass" => "required|string|min:8"   ;
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF

   hRec := HIX_PasswordHash( oVal:Get( "pass" ) )
   IF hRec == NIL
      RETURN USendError( 400, "password out of range" )
   ENDIF

   oRow := UserRepoNew( oVal:Get( "user" ) )
   oRow:PASSALG  := hRec[ "PASSALG" ]
   oRow:PASSITER := hRec[ "PASSITER" ]
   oRow:SALT     := hRec[ "SALT" ]
   oRow:PASSHASH := hRec[ "PASSHASH" ]
   oRow:Save()

   USendJson( { "ok" => .T., "user" => oRow:USUARIO }, 201 )
RETURN NIL
```

### Login — verify + transparent rehash

```clipper
FUNCTION UserLogin()

   LOCAL oRow, hStored, hRec

   oRow := UserRepoFind( UParam( "user" ) )
   IF oRow == NIL
      // Dummy hash so response time is indistinguishable between
      // "user missing" and "wrong password" (anti-enumeration).
      HIX_PasswordVerify( UParam( "pass" ), _DummyRecord() )
      RETURN USendError( 401, "invalid credentials" )
   ENDIF

   hStored := { "PASSALG"  => oRow:PASSALG,  ;
                "PASSITER" => oRow:PASSITER, ;
                "SALT"     => oRow:SALT,     ;
                "PASSHASH" => oRow:PASSHASH }

   IF ! HIX_PasswordVerify( UParam( "pass" ), hStored )
      RETURN USendError( 401, "invalid credentials" )
   ENDIF

   // Transparent rehash: if the stored parameters are obsolete
   // (iterations below the minimum or an old algorithm), re-derive
   // with current parameters and update the row.
   IF HIX_PasswordNeedsRehash( hStored )
      hRec := HIX_PasswordHash( UParam( "pass" ) )
      IF hRec != NIL
         oRow:PASSALG  := hRec[ "PASSALG" ]
         oRow:PASSITER := hRec[ "PASSITER" ]
         oRow:SALT     := hRec[ "SALT" ]
         oRow:PASSHASH := hRec[ "PASSHASH" ]
         oRow:Save()
      ENDIF
   ENDIF

   USession():Set( "user", { "id" => oRow:ID, "name" => oRow:NOMBRE } )
   USession():Save()
   URedirect( "/main" )
RETURN NIL
```

---

## `HIX_PasswordNeedsRehash` — raising the cost in place

OWASP's recommended cost **goes up every ~2 years** to keep the
attack cost constant. With per-user `PASSITER` you can:

1. Raise the internal minimum (`HIX_PASSWORD_MIN_ROUNDS`).
2. On each user's next login, `NeedsRehash` returns `.T.` if their
   record is below the new minimum.
3. Re-derive with `HIX_PasswordHash` (new cost) and save.

You raise security **transparently for the user**, no reset required.

The helper returns `.T.` in these cases:

| Case | Reason |
|---|---|
| `hRecord` is not a hash | `.T.` — invalid record |
| `PASSALG != "PBKDF2-SHA256"` | legacy algorithm, migrate |
| `PASSITER < 600 000` | cost below minimum |
| `SALT` or `PASSHASH` with wrong length/format | corrupt record |

---

## Security — important details

### `libcrypto` is resolved at runtime

HIX does not statically link libcrypto; it loads with `LoadLibraryA`
(Windows: `libcrypto-4-x64.dll`) or `dlopen` (Linux:
`libcrypto.so.{4,3,1.1}`) **on first use**.

If the library is unavailable:

- `HIX_PasswordHash` returns `NIL` → never falls back to a weak hash.
- `HIX_PasswordVerify` returns `.F.` → login fails, door stays shut.

The "fail rather than weaken" policy avoids the classic case where
an app silently starts accepting MD5 because someone deployed
without the DLLs.

### Timing attacks

`HIX_PasswordVerify` compares with `HIX_ConstantEq` — it walks all
32 bytes and XOR-accumulates differences. Two hashes that differ at
byte 1 take the same time as two identical hashes. The attacker
cannot use latency to guess the hash byte-by-byte.

### Never send the record to the client

The 4 fields together are **sensitive material**. Never emit them
in a JSON response, a view or a log. If `GET /users/:id` returns
user data, explicitly filter these fields before serializing.

### Maximum password length

The 1024-byte cap protects against **denial-of-service** by
ultra-long passwords: without it, a client could post 100 MB and
force the server to run 600 k derivations over that string.

---

## Comparison with other algorithms

| Algorithm | CPU-hard | Memory-hard | Status |
|---|---|---|---|
| MD5 / SHA1 / SHA256 direct | ❌ | ❌ | **Insecure** — never use |
| bcrypt      | ✅ | Weak (4 KB) | Acceptable |
| **PBKDF2**  | ✅ | ❌            | **HIX standard** (NIST/FIPS) |
| scrypt      | ✅ | ✅            | Good |
| Argon2id    | ✅ | ✅ (tunable) | OWASP 2026 recommendation |

PBKDF2 remains valid because:

- It is in every standard library.
- Required by **FIPS 140** (government/banking environments).
- At 600 k+ iterations the attack cost is still prohibitive for
  most attackers.

If HIX later adds Argon2id, the `PASSALG` field enables **gradual
migration**: new passwords tagged `"argon2id"`, existing ones with
`"PBKDF2-SHA256"` keep verifying with their stored parameters.

---

## What this primitive does **not** do

`HIX_Password*` is **pure crypto input/output**. It does not cover:

| Out of scope | Layer that covers it |
|---|---|
| Rate-limiting login attempts | Middleware (`HIX_MwRateLimit` or user repo) |
| Record persistence | Your `model/userrepo.prg` (DBF, WDO, etc.) |
| Post-login session | `HIX_MwSession` + `USession()` |
| Revoking sessions on password change | `AUTHVER` field + `MyAppReloadUser` |
| Password-reset-by-email flow | Your app (HIX provides tokens via `HIX_TokenMake`) |
| Password policies (uppercase, digits...) | `UValidator` with `regex:` rule |

The design is deliberate: a small, auditable primitive — not a
monolithic "auth framework".

---

## References

- **RFC 2898** / **RFC 8018** — formal PBKDF2 specification
- **NIST SP 800-63B** — Digital Identity Guidelines
- **OWASP Password Storage Cheat Sheet** — iteration counts by year
- **Password Hashing Competition 2015** — Argon2 context
