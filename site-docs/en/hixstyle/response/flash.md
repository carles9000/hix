# ⚡ Flash messages


A **flash** is a message that lives for **a single request**: it's stored in the
session during a POST, survives a redirect, and is consumed (auto-deleted)
when read in the next GET.

It's the piece that completes the **PRG (Post / Redirect / Get)** pattern: the
user sends a POST, the server processes, redirects, and the next GET
displays the result — without resubmitting the form if the page is refreshed.

```
POST /customer/update
      │
      │  oVal:Make()   → fails
      │  UFlash("customer"):Set({ errors, input })
      │  URedirect( "/customer/edit/42" )
      ▼
GET /customer/edit/42
      │
      │  oFlash := UFlash("customer")
      │  hErrors := oFlash:Get("errors")   ← reads and deletes
      │  hInput  := oFlash:Get("input")    ← reads and deletes
      │  USendView( "edit.html", hRow, hErrors, hInput )
      ▼
HTML with errors + values that the user had entered
```

> If the user refreshes the GET, the flashes **are no longer there** — the browser
> does not resubmit the POST and the banner "Customer updated!"
> is not shown twice.

---

## When to use it

| Case | Flash |
|---|---|
| Message "✅ Customer created" after redirect | ✅ Yes |
| Show validation errors when returning to form | ✅ Yes |
| Repopulate form with `oVal:Resume()` after error | ✅ Yes |
| Persistent data (preferences) | ❌ No — use cookies or database |
| Shared data between tabs | ❌ No — flash is per-session |
| Informational message in same request | ❌ No — just pass it to the view |

---

## Basic API

```clipper
UFlash( cFormId )   // returns a TFlash
```

`cFormId` is the namespace within the session: each form / module
has its own "bag", so two flows open in different tabs don't interfere.

```clipper
LOCAL oFlash := UFlash( "customer" )

oFlash:Set( "type",    "success" )
oFlash:Set( "message", "Customer updated" )
oFlash:Save()
```

If you call with a **complete hash**, it does `merge` and **auto-Save**:

```clipper
UFlash("customer"):Set( { ;
   "type"    => "success",                     ;
   "message" => "Customer updated"             ;
} )
// Save() implicit — already in session
```

If you call with `(cKey, xVal)`, it marks dirty but **does not save** until
`Save()`. When the object goes out of scope, the destructor calls `Save()`
automatically if there are pending changes.

---

## Methods

### `Set( cKey, xVal )` / `Set( hHash )`

```clipper
oFlash:Set( "name", "Carles" )
oFlash:Set( "age",  42 )
oFlash:Save()    // explicit

// Or all in one line — auto-save
UFlash("login"):Set( { "error" => "Bad password", "input" => { "user" => cUser } } )
```

### `Get( cKey, xDef )` - **one-shot**

Returns the value and **deletes** it from the bag. Next call → `xDef`.

```clipper
cMessage := oFlash:Get( "message", "" )    // first time → text
cMessage := oFlash:Get( "message", "" )    // second time → ""
```

> `Get` leaves the bag `dirty` so the destructor persists it empty — the
> message is definitively consumed even if there's another read/write flow.

### `Has( cKey )`

Checks if there's a value **without** consuming it:

```clipper
IF oFlash:Has( "message" )
   USetHeader( "X-Has-Notice", "1" )
ENDIF
```

### `Delete( cKey )`

Explicitly deletes without reading:

```clipper
oFlash:Delete( "old_state" )
```

### `Clear()`

Empties the entire bag for that `cFormId`:

```clipper
UFlash("customer"):Clear()
```

### `Save()`

Persists the bag to session. **Not necessary** to call if:

- You used `Set(hHash)` (auto-save).
- The object goes out of scope (destructor calls it if `lDirty`).

### `GetId()`

Returns the `cFormId` this flash uses:

```clipper
oFlash:GetId()   // "customer"
```

---

## Storage

- The flash is stored in the **session**, under the key `_flash`.
- `_flash` is a hash `{ cFormId => hBag }` — each form has its
  own bag.
- Empty bag → the entry in `_flash` is removed on `Save()` — the session
  doesn't fill with garbage.
- **Requires `HIX_MwSession`** active on the route. Without session, no flash.

```clipper
HIX_MwSessionSetup( "HIXSID", 3600, 60, "memory" )
oSrv:Use( "HIX_MwSession" )

// Now you can use UFlash() in any action
```

---

## Complete PRG pattern (Fenix)

### POST → Update with flash

```clipper
METHOD Update() CLASS Customer

   LOCAL oVal, oCustomers, lSuccess, nId, cError := ""

   nId := Val( UParam( "id", "0" ) )

   oVal := UValidatePost( { ;
      "first" => "required|string|max:20|field", ;
      "last"  => "required|string|max:20|field", ;
      "city"  => "required|string|max:30|field"  ;
   } )

   IF ! oVal:Make()
      // Validation fails — flash errors + input + redirect to edit
      UFlash("customer"):Set( { ;
         "type"   => "danger",          ;
         "errors" => oVal:GetErrors(),  ;
         "input"  => oVal:Resume()      ;
      } )
      RETURN URedirect( URoute( "customer.edit", nId ) )
   ENDIF

   oCustomers := TCustomers()
   lSuccess   := oCustomers:Update( nId, oVal:DataFields(), @cError )

   IF lSuccess
      UFlash("customer"):Set( { ;
         "type"    => "success",                                     ;
         "message" => "Customer " + LTrim( Str( nId ) ) + " updated!" ;
      } )
      RETURN URedirect( URoute( "customer.show", nId ) )
   ELSE
      // Database error — flash error + input (don't lose what was written)
      UFlash("customer"):Set( { ;
         "type"    => "danger",        ;
         "message" => cError,          ;
         "input"   => oVal:Resume()    ;
      } )
      RETURN URedirect( URoute( "customer.edit", nId ) )
   ENDIF

RETURN NIL
```

### GET → Edit consumes flash

```clipper
METHOD Edit() CLASS Customer

   LOCAL oVal, oCustomers, lFound, oFlash, hInput, nId
   LOCAL hRow     := {=>}
   LOCAL hMessage := {=>}
   LOCAL hErrors  := {=>}

   oVal := UValidateParams( { "id" => "required|numeric" } )
   IF ! oVal:Make()
      RETURN URedirect( URoute( "customer.search" ) )
   ENDIF
   nId := oVal:Get( "id" )

   oCustomers := TCustomers()
   lFound     := oCustomers:GetRecno( nId, @hRow, NIL, .T. )

   IF ! lFound
      hRow := oCustomers:Blank( .T. )
   ENDIF

   // Consume flash in the controller, the view only paints
   oFlash := UFlash( "customer" )

   hMessage[ "type" ]    := oFlash:Get( "type" )
   hMessage[ "message" ] := oFlash:Get( "message" )
   hErrors               := oFlash:Get( "errors" )

   // If there's flashed input → it has priority over database (repopulate form)
   hInput := oFlash:Get( "input" )
   IF hb_IsHash( hInput )
      hRow := hInput
   ENDIF

RETURN USendView( "views/masters/customer/edit.html", ;
                  lFound, hRow, hMessage, hErrors )
```

> **Process the flash in the controller, not in the view.** The view is
> "dumb": it receives `hRow`, `hMessage`, and `hErrors` already prepared. That
> allows the same template to serve both CREATE (without flash) and EDIT
> (with or without flash) without the view knowing anything.

---

## Useful patterns

### Success banner after login

```clipper
FUNCTION _LoginAction()
   LOCAL hUser := _CheckCredentials( UPost("user"), UPost("pass") )

   IF hUser == NIL
      UFlash("login"):Set( { ;
         "type"    => "danger",                ;
         "message" => "Invalid credentials"    ;
      } )
      RETURN URedirect( URoute( "auth.login" ) )
   ENDIF

   USession():Set( "user_id", hUser["id"] )
   USession():Save()

   UFlash("dashboard"):Set( { ;
      "type"    => "success",                            ;
      "message" => "Hello " + hUser["name"] + ", welcome!" ;
   } )

   RETURN URedirect( URoute( "dashboard" ) )
```

### Flash across different domains

Each form / module uses its own `cFormId` to avoid interference:

```clipper
UFlash("customer"):Set( { "message" => "Customer OK" } )
UFlash("invoice"):Set(  { "message" => "Invoice OK" } )

// The customer controller reads only "customer", invoice only "invoice"
```

### Multi-step flash (wizard)

Preserves input across several steps by passing `_HixCheckpoint` between them:

```clipper
// Step 1
UFlash("wizard"):Set( { "step1" => oVal:Resume() } )
URedirect( "/wizard/step2" )

// Step 2 — read step1 and add step2
LOCAL hStep1 := UFlash("wizard"):Get( "step1" )
UFlash("wizard"):Set( { "step1" => hStep1, "step2" => oVal:Resume() } )
URedirect( "/wizard/step3" )
```

> Each `Get` consumes — if you want to keep it, flash it again. Some frameworks
> have `keep()` / `reflash()`; in HIX the pattern is read + set again.

---

## Common errors

| Symptom | Cause |
|---|---|
| Flash doesn't appear after redirect | Missing `HIX_MwSession` on the destination GET route |
| Message shows twice | You called `Get()` and then `USendView` without saving to a variable; you consumed it without sending it |
| Data persists between different logins | You used the same `cFormId` in both — sessions are isolated but the bag is reused if you don't clean it |
| `Get()` returns `""` even though you just did `Set()` | The `Set` was done in another thread / process; flash lives in the current request's session |
| `HIXSID` cookie doesn't reach the GET | After `Save()` the session is serialized, but if you do `URedirect` without returning, the Set-Cookie is not sent |

---

## Best practices

1. **One `cFormId` per context.** `"customer"`, `"invoice"`, `"login"` —
   semantic names, not generic ones like `"main"`.
2. **Process flash in the controller.** The view only paints what it receives;
   if it reads flash directly, it's no longer reusable.
3. **Always flash input on errors.** Along with `errors`, flash
   `oVal:Resume()` to repopulate the form. Nothing worse than a user
   retyping 20 fields.
4. **Short, typed messages.** Convention `{ "type" => "success|danger|warning|info", "message" => "..." }` — the view paints the banner according to `type`.
5. **Don't overuse.** Flash is for "a single read". If you need to show
   a message many times, store it in session / cookie / database directly.
6. **Logout cleans up.** When closing session, call `USession():Destroy()` —
   the flash disappears with the session.
