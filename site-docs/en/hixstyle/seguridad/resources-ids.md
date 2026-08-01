# 🆔 Resource IDs

## What problem does it solve?

A typical edit form embeds the resource ID as a hidden field:

```html
<input type="hidden" name="recno" value="42">
```

But that ID travels **in the clear**. Any user can inspect the HTML, change the `42` to a `99`, and send the POST to `/customer/edit` to modify a record **that isn't theirs**. You need either:

1. **Re-check permissions** on the `99` on the server _(the right approach, but costly and easy to forget)_.
2. **Sign the ID** so the client can't alter it—that's the solution `UResourceToHtml` provides.

```
Client receives   <input ... value="MTAwfDE3MzQ...sig=abc123">  (signed)
Client sends      _resource_id=MTAwfDE3MzQ...sig=abc123
Server            UGetResource() -> "100"  (valid, accept it)
Server            if client altered 1 byte -> UGetResource() -> ""
```

The token contains the ID + timestamp + **HMAC** signature with `app_key`. Without knowing the secret, the attacker cannot generate a valid one for a different ID.

---

## When to use it?

| Use case | Resource IDs |
|---|---|
| Edit / delete form for a specific record | ✅ Yes |
| Lists with actions like `<button data-id="42">` | ✅ Yes |
| Client / order / invoice ID traveling in URL | ⚠️ No—the URL is `/customer/:id`, there's already auth middleware there |
| One-shot file download token | ✅ Yes |
| REST API with JWT | ❌ No—JWT identifies the user; validate ownership with queries |

> **They don't replace permission checks.** Resource IDs guarantee *integrity* of the ID (not tampered), not *authorization*. You still need to verify the current user can edit that specific record.

---

## API

### Generate—in the controller / template

```clipper
USetView( "cResourceHtml", UResourceToHtml( nRecno ) )
```

```html
<form method="POST" action="/customer/edit">
  {{ UCsrfToHtml() }}
  {{ UResourceToHtml( nRecno ) }}
  <input name="first" value="{{ hRow['first'] }}">
  ...
  <button>Save</button>
</form>
```

`UResourceToHtml( "100" )` generates something like:

```html
<input type="hidden" name="_resource_id" value="MTAwfDE3MzQ4OTAxMjM=.aBcD3f...">
```

### Validate—in the POST controller

```clipper
LOCAL cId := UGetResource()        // reads _resource_id from POST -> GET

IF Empty( cId )
   RETURN URedirect( URoute( "main" ) )      // token missing / invalid
ENDIF

nId := Val( cId )                  // original ID recovered
```

`UGetResource()` searches for the token automatically:

1. `UPost( "_resource_id" )` — first from POST body
2. `UGet( "_resource_id" )` — fallback in query string
3. If not found or signature is invalid → returns `""`

---

## Real example—Fenix's `customer.prg`

### Update action

```clipper
METHOD Update() CLASS Customer
   LOCAL cId := UGetResource()                 // ⬅ retrieves the signed recno
   LOCAL oVal, nId, cError, lSuccess

   // 1. Do we have a valid token?
   IF Empty( cId )
      RETURN URedirect( URoute( "main" ) )     // forged / corrupt -> main
   ENDIF

   // 2. Is the ID a valid number?
   oVal := UValidatorOne( "Id", cId, "required|number|min:0" )
   IF oVal:Fails()
      RETURN URedirect( URoute( "customer.search" ) )
   ENDIF
   nId := oVal:Get()

   // 3. Validate the rest of the form
   oVal := UValidatePost( { ;
      "first"  => "required|string|max:20|field", ;
      "last"   => "required|string|max:20|field", ;
      "city"   => "required|string|max:30|field", ;
      ... ;
   } )

   IF ! oVal:Make()
      UFlash( "customer" ):Set( { ;
         "type"   => "danger",      ;
         "errors" => oVal:GetErrors(), ;
         "input"  => oVal:Resume() } )
      RETURN URedirect( URoute( "customer.edit", nId ) )
   ENDIF

   // 4. Persist
   lSuccess := TCustomers():Update( nId, oVal:DataFields(), @cError )
   ...
RETURN nil
```

### Delete action

Same pattern—the token comes from the delete confirmation form:

```clipper
METHOD Delete() CLASS Customer
   LOCAL cId := UGetResource()
   ...
```

---

## Token anatomy

```
  payload (base64)        .   signature (HMAC-SHA256)
┌─────────────────────────┐.┌──────────────────────┐
  MTAwfDE3MzQ4OTAxMjM=    .   aBcD3f9eGgHhIi...
└─────────────────────────┘ └──────────────────────┘
        │
        └── base64Decode -> "100|1734890123"
                             │      │
                             │      └── unix timestamp
                             └── original ID
```

- The **payload** carries the original ID separated by `|` from the timestamp.
- The **signature** is calculated as `HMAC-SHA256( payload, app_key )`.
- If someone alters even one byte of the payload, the signature no longer matches and `HIX_TokenValid` returns `.F.`.
- The **timestamp** allows implementing expiration (not used by `UGetResource`, which validates with `nLapsus = 0`).

---

## The secret—`app_key`

`UResourceToHtml` and `UGetResource` share **the same `app_key`** as [CSRF](csrf.md). Configure it once:

```clipper
HIX_ConfigAppSet( "app_key", "my_secret_app_key" )
```

> ⚠️ Changing `app_key` invalidates **all** signed tokens: CSRF, Resource IDs, and any other `HIX_TokenMake` tied to the same secret. Forms open in active tabs will error until refresh.

---

## Complete edit/update pattern with Fenix

### GET /customer/42/edit—renders the form

```clipper
METHOD Edit() CLASS Customer
   LOCAL oVal := UValidateParams( { "id" => { "required|number|min:0", "Id" } } )
   LOCAL hRow

   IF ! oVal:Make()
      RETURN URedirect( URoute( "customer.search" ) )
   ENDIF

   TCustomers():GetRecno( oVal:Get( "id" ), @hRow, NIL, .T. )

RETURN UView( "masters/customer/edit.html", .T., hRow )
```

### Template—edit.html

```html
@args lEdit, hRow

<form method="POST" action="{{ URoute('customer.update', hRow['recno']) }}">
  {{ UCsrfToHtml() }}
  {{ UResourceToHtml( hRow['recno'] ) }}

  <label>Name <input name="first" value="{{ hRow['first'] }}"></label>
  <label>City  <input name="city"  value="{{ hRow['city']  }}"></label>
  ...
  <button>Save</button>
</form>
```

### POST /customer/42/edit—receives the form

```clipper
METHOD Update() CLASS Customer
   LOCAL cId := UGetResource()           // 42 signed and validated
   ...
```

---

## Comparison with CSRF

| | CSRF token | Resource ID token |
|---|---|---|
| What it signs | _nothing_—only random timestamp | The resource ID |
| Field name | `_csrf` | `_resource_id` |
| Purpose | "This form was launched from our page, not an attacker's" | "This ID is the one I gave you, not a manipulated one" |
| Render helper | `UCsrfToHtml()` | `UResourceToHtml( cId )` |
| Read helper | _(automatic via middleware)_ | `UGetResource()` |
| Share secret | ✅ `app_key` | ✅ `app_key` |

The two usually go **together** in each form (CSRF + Resource ID).

---

## Best practices

1. **CSRF + Resource ID on every edit/delete form.** They're complementary.
2. **Doesn't replace permission checks.** A valid Resource ID token only says "this is the ID I gave you"; you still must check the user can edit that resource.
3. **Don't put sensitive data in the ID.** The payload is only base64, not encrypted—anyone can read the original ID. It's only *tamper-proof*, not confidential.
4. **Change `app_key` in production.** If you keep the default published in the repo, anyone can generate valid tokens.
