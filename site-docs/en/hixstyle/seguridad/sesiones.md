# 🔑 Sessions

A **session** is storage space on the server where HIX keeps data associated
with a specific client (typically the logged-in user). What ties the client
to their session is a **cookie** that travels in each request containing an
opaque identifier (SID).

```
Client                              Server
   │                                    │
   │  GET /login                        │
   ├───────────────────────────────────>│  no SID -> creates new session
   │                                    │  SID = "abc...123"
   │  Set-Cookie: HIXSID=abc...123      │
   │<───────────────────────────────────┤
   │                                    │
   │  POST /auth                        │
   │  Cookie: HIXSID=abc...123          │  recognizes SID -> retrieves data
   ├───────────────────────────────────>│  USession():Set("user", hUser)
```

HIX sessions are **idempotent**: touching `oCtx:hData["session"]` from a
middleware or calling `USession():Set()` from a controller modifies the same
data hash for that client.

---

## When to use them

| Use case | Sessions |
|---|---|
| Traditional web app with login | ✅ Yes - canonical pattern |
| SPA with cookie-based auth | ✅ Yes |
| Stateless REST API | ❌ No - use [JWT](jwt.md) |
| Microservices / mobile apps | ❌ No - use [JWT](jwt.md) |
| Shopping cart, multi-screen wizards | ✅ Yes |
| Flash messages between redirects | ✅ Yes (`UFlash`) |

> Sessions are **stateful**: the server remembers the client across requests.
> They make programming easier but tie the client to one instance (or require
> session affinity / shared storage in a cluster).

---

## Setup

### From `hix.json`

`storage`: `"memory"` | `"file"`.
`lifetime`: session cookie lifetime in minutes (`0` = indefinite).
`gc_days`: days for GC of orphaned files (only `storage="file"`).
`seed`: secret key for encryption (required if `crypt=true`).

```json
{
  "session": {
    "storage":  "memory",
    "prefix":   "sess_",
    "crypt":    false,
    "seed":     "",
    "lifetime": 60,
    "gc_days":  3
  }
}
```

### From code

```clipper
HIX_MwSessionSetup( ;
   "HIXSID",     ;   // cookie name
   3600,         ;   // TTL in seconds (1 hour)
   60,           ;   // GC: clean expired every N calls
   "memory",     ;   // storage: "memory" | "file"
   "sessions/",  ;   // path (only if storage="file")
   "sess_",      ;   // file prefix
   .F.,          ;   // encrypt
   "",           ;   // encryption seed
   7 )               // cookie lifetime in days
```

### From the app - Fenix convention

Fenix exposes the parameters in `www/middlewares/config.json` to keep them
close to the app logic:

```json
{
  "setup": {
    "session": {
      "cookie":  "FENIXSID",
      "ttl":     3600,
      "max":     100,
      "storage": "memory"
    }
  }
}
```

Those values are read with `UMwConfig("session", "cookie")` from any
controller or middleware.

---

## Enable session on a route

`HIX_MwSession` is the middleware that loads/creates the session. It's added
to the middleware chain of the route - directly or inside an app middleware group.

### Individual route

```clipper
oSrv:AddRouteGet( "dash", "/dashboard", bAction, "HIX_MwSession" )
```

```json
{ "name": "dashboard", "url": "/dashboard", "action": "controllers/dash.prg",
  "middleware": "HIX_MwSession" }
```

### Fenix pattern - reusable middleware group

In Fenix you define **once** a group combining session + authentication and
apply it to all routes that need it:

```clipper
// www/middlewares/myappauth.prg
FUNCTION MyAppAuth( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "HIX_MwSession" ) )
   o:Add( UMiddleware():New( "HIX_MwIsAuth"  ) )
RETURN o:Run()
```

```json
{ "name": "main", "url": "/main", "action": "controllers/main.prg",
  "middleware": "MyAppAuth" }
```

> 📖 Details of the pattern in [Middleware](../middleware/middleware.md).

---

## Read and write from a controller

With the session active, the `USession()` and `UFlash()` helpers allow you
to access the data without touching `oCtx`.

### Read

```clipper
cUser := USession( "user" )              // value or NIL
cRole := USession( "role", "viewer" )    // value with default
```

### Write

```clipper
LOCAL oSess := USession()                // proxy with Set/Save/Destroy
oSess:Set( "user", hUser )
oSess:Set( "role", "admin" )
oSess:Save()                             // persists + renews TTL + emits cookie
```

### Destroy

```clipper
USession():Destroy()                     // erase data + expire cookie
```

### Real example - `auth.prg` from Fenix

```clipper
// POST /auth - credential validation and session startup
FUNCTION Main()
   LOCAL oVal, oSess, hUser

   oVal := UValidatePost( { ;
      "username" => { "required|min:3|max:30", "Username", "" }, ;
      "password" => { "required|min:4",        "Password", "" }  ;
   } )

   IF ! oVal:Make()
      UFlash( "login" ):Set( { "error" => oVal:GetFirstError() } )
      URedirect( "/login" )
      RETURN
   ENDIF

   hUser := ModelUser( oVal:Get( "username" ), oVal:Get( "password" ) )

   IF ValType( hUser ) == "H"
      // Save user with configured key
      oSess := USession()
      oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )
      oSess:Save()
      URedirect( UMwConfig( "auth", "redirect_accept" ) )
   ELSE
      UFlash( "login" ):Set( { "error" => "Username or password incorrect" } )
      URedirect( UMwConfig( "auth", "redirect_login" ) )
   ENDIF
RETURN
```

### Real example - `logout.prg` from Fenix

```clipper
PROCEDURE Main(...)
   LOCAL oSess := USession()
   oSess:Destroy()
   URedirect( "/login" )
RETURN
```

---

## Storage: memory vs file

| Storage | Persistence | Cluster | Restart | Typical use |
|---|---|---|---|---|
| `memory` | Process RAM | ❌ single instance | Lost | Development, monoliths |
| `file` | Disk | ✅ with session affinity | Survive | Production, load balancer |

### Memory

Fast sessions, no disk write. All sessions lost on restart. In a cluster,
the client loses the session if the load balancer sends them to another instance.

### File

Each session is a file in `sessions/<prefix><SID>.dat`. They survive restarts
and allow multiple instances to share the same storage.

```clipper
HIX_MwSessionSetup( "HIXSID", 3600, 60, "file", "sessions/", "sess_" )
```

### Cluster with Apache + stickysession

When deploying behind Apache load balancer, call `HIX_MwSessionSetRoute( "i1" )`
with your `BalancerMember`'s `route=`. HIX appends the suffix to the SID so
Apache can keep the client sticky to the same instance with
`stickysession=HIXSID`.

---

## Optional encryption

If `crypt=1` in config (or `lCrypt=.T.` in `HIX_MwSessionSetup`), session files
are encrypted with the `seed`. Without the correct seed they can't be read.

```clipper
HIX_MwSessionSetup( "HIXSID", 3600, 60, "file", "sessions/", "sess_", ;
                    .T., "clave_secreta_de_app", 7 )
```

> ⚠️ Changing the seed invalidates all existing sessions.

---

## Useful patterns

### Retrieve the user in any controller

```clipper
PROCEDURE Main(...)
   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Unknown" } )

   // hUser was placed by HIX_MwIsAuth after reading the session
RETURN UView( "main.view.html", hUser["name"], hUser )
```

> Auth middlewares already read `USession( cKey )` for you and place the user hash
> in `oReq:hData["user"]`.

### Flash messages (one-time messages)

`UFlash` uses the session under the hood. Essential for carrying messages
through a `URedirect`.

```clipper
// POST with error -> flash + redirect
UFlash( "login" ):Set( { ;
   "error" => "Username or password incorrect", ;
   "user"  => cUserIntent ;
} )
URedirect( "/login" )

// GET /login -> consumes flash once only
oFlash := UFlash( "login" )
cError := oFlash:Get( "error" )       // erased after read
cUser  := oFlash:Get( "user"  )
oFlash:Save()
```

### Sub-hashes to organize the session

```clipper
USession():Set( "cart",  { "items" => aItems, "total" => nTotal } )
USession():Set( "prefs", { "theme" => "dark", "lang"  => "es"   } )
USession():Save()

hCart := USession( "cart" )
nTot  := hCart[ "total" ]
```

