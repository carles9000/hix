# 🔑 Keys and Secrets - Shared Store

Every HIX security engine (JWT, sessions, signed tokens, CSRF,
resource IDs…) needs a **secret key** to sign data. To avoid repeating
setups per module, HIX provides a single key store:

- `HIX_KeySet( cName, cVal )` - saves a key with a name.
- `HIX_KeyGet( cName, cDefault )` - reads it (or returns the default).
- `HIX_KeyExists( cName )` - checks if it exists.

Engines always read through `HIX_KeyGet()`. **They don't care where the
key comes from** - only that it's loaded before `oSrv:Start()`.

## Keys used by HIX

| Name       | Consumed by                         | Fallback default      |
|------------|-------------------------------------|-----------------------|
| `csrf`     | CSRF (`HIX_CsrfMakeToken/Valid`)    | `"H!x@CSRF@2026"`     |
| `resource` | Resource IDs (`HIX_ResourceHtml`)   | `"H!x@RES@2026"`      |
| `jwt`      | JWT (`HIX_JwtEncode/Validate`)      | `"H!x@JWT@2026"`      |
| `session`  | Sessions (seed for SID encryption)  | `"H!x@SESSION@2026"`  |
| `token`    | Generic signed tokens               | `"H!x@TOKEN@2026"`    |

> Defaults exist so the library boots; **always change them** in
> production.

---

## HixStyle profile - automatic loading from `config.json`

In **hixstyle** mode (`config.json` present at project root), the server
bootstrap reads the `keys` section right after applying Harbour configuration
and publishes each entry to the store.

```json
{
  "sets": { "language": "ES", "dateformat": "dd/mm/yyyy" },
  "dbf":  { "rddname": "DBFCDX" },
  "keys": {
    "csrf":     "T7$k9pM2!vX4qL8w",
    "resource": "res-2026-abc",
    "jwt":      "hix-jwt-prod-2026",
    "session":  "sess-seed-random",
    "token":    "tok-2026-xyz"
  }
}
```

On first run, HIX generates `config.json` with this section already seeded
(with the fallback defaults). You only need to replace the values with
your own and restart - no recompilation needed.

## Standalone profile - without `config.json`

If you prefer to boot without `config.json` (fully programmatic startup),
publish the keys yourself before `oSrv:Start()`:

```harbour
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()

   // Load keys from wherever you like: .ini file, environment variables,
   // KMS, hard-coded for development…
   HIX_KeySet( "csrf",    GetEnv( "HIX_CSRF_KEY" ) )
   HIX_KeySet( "jwt",     GetEnv( "HIX_JWT_KEY"  ) )
   HIX_KeySet( "session", GetEnv( "HIX_SESS_KEY" ) )

   oSrv:Start()
   IF oSrv:hThread != NIL ; hb_threadJoin( oSrv:hThread ) ; ENDIF
RETURN
```

Engines see exactly the same thing - the only difference is where the
value comes from.

## Legacy profile - per-module setups

Historical setups (`HIX_MwJwtSetup`, `HixMwSessionSetup`,
`HIX_TokenSetSecret`, …) **still work**. They internally delegate to
`HIX_KeySet` with the appropriate key name.

```harbour
HIX_MwJwtSetup( "my-jwt-secret", 3600 )    // equivalent to HIX_KeySet("jwt", ...)
HIX_TokenSetSecret( "tok-2026" )           // equivalent to HIX_KeySet("token", ...)
```

They coexist with the other two modes. If you mix sources, the last
write wins.

---

## Precedence

1. **HixStyle bootstrap** - runs first: `HIX_KeysLoadFromAppConfig()`
   copies the `keys` section to the store.
2. **Per-module setup** - any `HIX_*Setup()` you call afterwards.
3. **Manual `HIX_KeySet()`** - the most direct way; overwrites the above.

Practical rule: if a value is in `config.json` **and** you also call
`HIX_MwJwtSetup("another")` in `Main()`, the later execution wins.

## Safe inspection

To debug or expose the store state without leaking secrets:

```harbour
? HIX_KeysAsHash()
// { "csrf" => "T7***4w", "jwt" => "hi***26", ... }
```

Each value is masked showing only the first 2 and last 2 characters.
It's the same hash you can emit from an internal status endpoint.
