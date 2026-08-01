# 🛡️ Authentication


**Authentication** identifies the client making the request (login) and verifies that they have permission to access a specific resource (authorization by role/operation).

In HIX, there are two stacks that cover the two main scenarios:

| Stack | State | Typical use |
|---|---|---|
| **Session + auth middleware** | statefull (cookie + server storage) | Traditional web app, admin panel |
| **JWT** | stateless (signed token) | REST API, mobile, microservices |

This page covers the **session-based** stack — the pattern that Fenix uses. For the JWT stack, see [JWT](jwt.md).

---

## The pieces of the puzzle

```
┌──────────────────────────────────────────────────────────────┐
│  HIX_MwSession   loads/creates the session (HIXSID cookie)   │
│        │                                                     │
│        ▼                                                     │
│  HIX_MwIsAuth    reads session["_auth_user"]                 │
│                  - exists -> hData["user"] := hUser          │
│                  - NIL    -> 302 /login                      │
│        │                                                     │
│        ▼                                                     │
│  HIX_MwHasRole   compares oCtx:cScope with user["roles"]     │
│                  - allows -> continues                       │
│                  - denies  -> 403                            │
│        │                                                     │
│        ▼                                                     │
│  Controller      hData["user"] available via URequest()      │
└──────────────────────────────────────────────────────────────┘
```

The three pieces are independent middlewares that combine into a single reusable chain.

---

## Setup

### Fenix convention - `www/middlewares/config.json`

```json
{
  "setup": {
    "auth": {
      "session_user_key": "_auth_user",
      "roles_key":        "roles",
      "redirect_login":   "/login",
      "redirect_accept":  "/main"
    },
    "session": {
      "cookie":  "FENIXSID",
      "ttl":     3600,
      "storage": "memory"
    }
  }
}
```

| Key | Purpose |
|---|---|
| `session_user_key` | Key within the session hash where the user is stored |
| `roles_key` | Key within the user hash that contains the roles |
| `redirect_login` | URL to redirect to if there is no active session (302) |
| `redirect_accept` | URL after successful login |

These values are read with `UMwConfig( "auth", "session_user_key" )` from any controller or middleware.

---

## Define the middleware groups

In Fenix, they are defined **only once** and reused across all routes:

```clipper
// www/middlewares/myappauth.prg
FUNCTION MyAppAuth( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession" ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"  ) )
RETURN o:Run()

FUNCTION MyAppAuthRole( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession" ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"  ) )
   o:Add( UMiddleware():New( "HIX_MwHasRole" ) )
RETURN o:Run()
```

And in `config.json` they are loaded on startup:

```json
{
  "load": [
    "myappauth.prg",
    "myapplogin.prg",
    "myappauthedit.prg"
  ]
}
```

---

## Apply to the routes

```json
[
  { "name": "main",
    "url": "/main", "method": "GET",
    "action": "controllers/main.prg",
    "middleware": "MyAppAuth" },

  { "name": "customer.show",
    "url": "/customer/:id", "method": "GET",
    "action": "controllers/masters/show@customer.prg",
    "middleware": "MyAppAuthRole", "scope": "customers:show" },

  { "name": "customer.delete",
    "url": "/customer/:id([0-9]+)/delete", "method": "POST",
    "action": "controllers/masters/delete@customer.prg",
    "middleware": "MyAppAuthRole", "scope": "customers:delete" }
]
```

> The `"scope"` field maps to `oCtx:cScope` and is consumed by `HIX_MwHasRole`.

---

## The user hash

`HIX_MwIsAuth` expects the session to contain a hash with this shape:

```clipper
{ "id"    => "1",
  "name"  => "Admin Demo",
  "roles" => { "customers" => "show;edit;delete;create",
               "sales"     => "",
               "purchases" => "" } }
```

Rules of the `roles` hash:

| Value | Meaning |
|---|---|
| `""` | The user has **full access** to that role (any operation passes) |
| `"op1;op2;op3"` | Only those operations are allowed |
| _(role absent)_ | The user **does not have** that role → 403 |

---

## Scope syntax

`oCtx:cScope` is compared against the user's roles hash:

| Scope | Passes if... |
|---|---|
| `""` | Always (no role check) |
| `"customers"` | The user has the `customers` role (with any ops) |
| `"customers:show"` | The user has `customers` with `""` **or** with `"show"` in the list |
| `"customers:delete"` | The user has `customers` with `""` **or** with `"delete"` in the list |

```clipper
// Reading in HIX_MwHasRole
aScope := hb_ATokens( oCtx:cScope, ":" )
cRole  := aScope[1]                              // "customers"
cOp    := iif( Len( aScope ) > 1, aScope[2], "")  // "show"
cOps   := hb_HGetDef( hRoles, cRole, NIL )
```

---

## Login - Fenix's `auth.prg`

```clipper
// POST /auth  middleware: MyAppLogin (Session + CsrfCheck)
FUNCTION Main()
   LOCAL oVal, oSess, hUser

   oVal := UValidatePost( { ;
      "username" => { "required|min:3|max:30", "Username", "" }, ;
      "password" => { "required|min:4",        "Password", "" }  ;
   } )

   IF ! oVal:Make()
      UFlash( "login" ):Set( { ;
         "error" => oVal:GetFirstError(), ;
         "user"  => oVal:Get( "username" ) } )
      URedirect( "/login" )
      RETURN
   ENDIF

   hUser := ModelUser( oVal:Get( "username" ), oVal:Get( "password" ) )

   IF ValType( hUser ) == "H"
      oSess := USession()
      oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )
      oSess:Save()
      URedirect( UMwConfig( "auth", "redirect_accept" ) )       // -> /main
   ELSE
      UFlash( "login" ):Set( { ;
         "error" => "Invalid username or password", ;
         "user"  => oVal:Get( "username" ) } )
      URedirect( UMwConfig( "auth", "redirect_login" ) )        // -> /login
   ENDIF
RETURN

#include '/models/modeluser.prg'
```

### User model - `modeluser.prg`

```clipper
FUNCTION ModelUser( cUser, cPass )
   LOCAL hStore, hEntry

   hStore := { ;
      "demo"   => { "id" => "1", "name" => "Admin Demo", "pass" => "1234", ;
                    "roles" => { "sales"     => "",                         ;
                                 "purchases" => "",                         ;
                                 "customers" => "show;edit;delete;create" } ;
                  }, ;
      "carles" => { "id" => "2", "name" => "Carles Aubia", "pass" => "1234", ;
                    "roles" => { "customers" => "show",                      ;
                                 "purchases" => "" } } ;
   }

   hEntry := hb_HGetDef( hStore, Lower( cUser ), NIL )

   IF hEntry == NIL .OR. ! ( hEntry["pass"] == cPass )
      RETURN NIL
   ENDIF

RETURN { "id"    => hEntry["id"],   ;
         "name"  => hEntry["name"], ;
         "roles" => hEntry["roles"] }
```

> In production, `ModelUser` queries a database and compares with `hb_BCrypt` or similar. The shape of the returned hash **does not change**.

---

## Logout - Fenix's `logout.prg`

```clipper
PROCEDURE Main(...)
   LOCAL oSess := USession()
   oSess:Destroy()
   URedirect( "/login" )
RETURN
```

`Destroy()` clears all session content and emits a cookie with `Max-Age=0` so the browser deletes it.

---

## Read the user from a controller

`HIX_MwIsAuth` leaves the hash in `oCtx:hData["user"]` **and** in `oReq:hData["user"]`, so any protected controller can read it without touching the session directly:

```clipper
PROCEDURE Main(...)
   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Unknown" } )

RETURN UView( "main.view.html", hUser["name"], hUser )
```

### Check roles in code

```clipper
IF UHasRole( "customers" )            // has the role (any op)
IF UHasRole( "customers", "delete" )  // has the role with that op
```

---

## When to use which stack

| Use case | Stack |
|---|---|
| Web app with login form | ✅ Session + IsAuth |
| Admin panel with fine-grained permissions | ✅ Session + IsAuth + HasRole |
| REST API consumed by SPA with cookie | ✅ Session |
| Stateless REST API / mobile / microservices | ❌ Use [JWT](jwt.md) |
| Same endpoint accessible from web + API | Combine both middlewares |

---

## Best practices

1. **Single source of truth for roles.** The `roles` hash travels in the
   session—if you change the user's permissions in the database, refresh the session
   or invalidate it.
2. **`Destroy()` on logout.** Clear the entire session, not just the user key,
   to prevent **session fixation**.
3. **CSRF mandatory on POST auth forms.** Login redirects via `URedirect` and leaves the session
   started—without CSRF, an attacker can force a login. Combine with [CSRF](csrf.md).
4. **HTTPS in production.** The cookie travels in every request—without [SSL](ssl.md) an intermediary can steal it.
5. **Don't put the password in the session.** Only `id`, `name`, `roles`, and
   what's strictly necessary to authorize requests.
6. **Granular roles with `""` for admin.** The empty value (`"customers" => ""`) means "all ops"—use it only for superusers.
