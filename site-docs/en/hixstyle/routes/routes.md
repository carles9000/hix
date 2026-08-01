# 🗺️ Routes

## 📂 `<root>/routes`

A route is the association between a URL pattern, an HTTP method, and the action that must be executed
when a request arrives that matches.

When, for example, we specify in the URL `https://my_domain/hello`, we tell the server to execute
an action identified as `hello`.

When **HIX** receives a request, the dispatcher traverses the registered routes **in order of specificity**
(the most concrete first), looking for one that matches the URL and method.

A literal segment (`/users`) scores 10; a variable parameter (`:id`) scores 1.
    `/users/profile` will be evaluated before `/users/:id`.

Once it finds a match:

1. It executes the **middleware** chain assigned to that route (optional).
2. If the middleware approves, it executes the **action**.

---

## Route definition

**HIX** allows you to define routes in 2 different ways:

- Defining them at the program level (Server)

- Defining them at the file level that will be read when the server initializes (data-driven)

The use of either method is the programmer's choice and does not change the behavior

### In code — server

To define routes at the application code level, once we have instantiated the server object
with `THixServer():New()`, we can define the routes using the following methods.


| Method | HTTP verb |
|--------|-----------|
| `AddRouteGet` | GET |
| `AddRoutePost` | POST |
| `AddRoutePut` | PUT |
| `AddRouteDelete` | DELETE |
| `AddRoute` | Any — pass the method as the fifth parameter |

Creating a route has the following parameters:

| Parameter | Type | Description |
|-----------|------|-------------|
| `cName` | String | Unique logical identifier. Prefix `hix.` reserved for the system. |
| `cPattern` | String | URL pattern (see section [URL Patterns](#url-patterns)). |
| `bAction` | Block/String | Action to execute (see section [What a route can execute](#what-a-route-can-execute)). |
| `cMiddleware` | String | Middleware function name (optional). |
| `cScope` | String | Free metadata accessible from `oCtx:cScope` (optional). |
| `uCargo` | Any | Arbitrary data attached to the route context (optional). |

We have a structure that could look something like:

```harbour
oSrv:AddRouteGet( cName, cPattern, bAction [, cMiddleware [, cScope [, uCargo]]] )
```


The usual way in free mode is to register routes on the `THixServer` object before calling
`Start()`.

```harbour
LOCAL oSrv := THixServer():New()

   oSrv:AddRouteGet(    "users.list",   "/api/users",     {|| _UserList()   } )
   oSrv:AddRouteGet(    "users.one",    "/api/users/:id", {|| _UserGet()    } )
   oSrv:AddRoutePost(   "users.create", "/api/users",     {|| _UserCreate() } )
   oSrv:AddRoutePut(    "users.update", "/api/users/:id", {|| _UserUpdate() } )
   oSrv:AddRouteDelete( "users.delete", "/api/users/:id", {|| _UserDelete() } )

oSrv:Start()
```

A route can have multiple methods if desired, separated by a comma.

```harbour
// Route that accepts multiple methods at once
oSrv:AddRoute( "hook", "/webhook", {|| _Webhook() }, "GET,POST" )
```

### From JSON files — HixStyle

When HixStyle is active, HIX automatically loads all `*.json` files from the
`<root>/routes/` folder when it starts. Each file is an **array** of route hashes. They follow the same
structure as defined earlier.

```json
[
  {
    "name":       "users.list",
    "url":        "/api/users",
    "method":     "GET",
    "action":     "controllers/users.prg",
    "middleware": "HixMwJwt",
    "scope":      "api"
  },
  {
    "name":    "users.one",
    "url":     "/api/users/:id",
    "method":  "GET",
    "action":  "controllers/users.prg"
  },
  {
    "name":    "home",
    "url":     "/",
    "method":  "GET",
    "action":  "views/home.html"
  }
]
```

JSON object fields:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique identifier. `hix.*` is reserved. |
| `url` | Yes | URL pattern. |
| `method` | No | `"GET"`, `"POST"`, `"GET,POST"`, `"*"` (default: `"*"`). |
| `action` | Yes | File or function to execute. |
| `middleware` | No | Middleware function name. |
| `scope` | No | Free metadata. |

## Developer Mode

In development mode, JSON routes can be reloaded on the fly without restarting the server
via API.

```
GET /hix-routes/reload
```

---

## What a route can execute

### Codeblock

The most direct way. Use the `U*` helpers to read the request and send the response.

```harbour
oSrv:AddRouteGet( "ping", "/ping", {|| USendJson( { "ok" => .T. } ) } )

oSrv:AddRouteGet( "greet", "/hello/:name", {||
   USendJson( { "msg" => "Hello, " + UParam("name") } )
} )
```

### Function name

If the action is a string **without an extension**, HIX treats it as a Harbour function name
and calls it, passing it the request object.

```harbour
oSrv:AddRouteGet( "users.list", "/api/users", "UserListAction" )

// In any .prg in the library:
FUNCTION UserListAction( oReq )
   USendJson( { "users" => {} } )
RETURN NIL
```

### `.prg` file

A `.prg` file relative to `<root>/`. HIX compiles and executes it.

```harbour
// In code:
oSrv:AddRouteGet( "home", "/", "views/home.prg" )

// In JSON:
{ "name": "home", "url": "/", "action": "views/home.prg" }
```

The file must be a compilable `.prg`. The result returned by `Main()` or
the output accumulated with `UWrite()` is sent as an HTML response.

### `.hrb` file

Same as `.prg` but already precompiled. Faster in production.

```harbour
{ "name": "api.data", "url": "/api/data", "action": "controllers/data.hrb" }
```

### Class method — `method@class.prg`

This is the most professional way to define an action because it allows you to define different actions
within the same module, such as a CRUD.

```harbour
// Calls the "index" method of the "CustomerController" class in customer.prg
{ "name": "customer.index", "url": "/customers",     "action": "index@customer.prg"  }
{ "name": "customer.show",  "url": "/customers/:id", "action": "show@customer.prg"   }
{ "name": "customer.save",  "url": "/customers",     "action": "save@customer.prg"   }
```

The `customer.prg` file defines a class with those methods:

```harbour
CLASS CustomerController
   METHOD index( oReq )
   METHOD show( oReq )
   METHOD save( oReq )
ENDCLASS

METHOD index( oReq ) CLASS CustomerController
   USendJson( { "customers" => {} } )
RETURN NIL
```

### `.html` file

Renders the HTML file with HIX's internal view engine, Mambo.

```harbour
{ "name": "home",    "url": "/",     "action": "views/home.html"      }
{ "name": "profile", "url": "/user", "action": "views/profile.view.html" }
```

---

## URL patterns

### Literal segment

```
/ping
/api/v1/status
```

### Variable parameter - `:name`

Captures any value except `/`. Accessible with `UParam("name")`.

```
/users/:id              → /users/42        → UParam("id") = "42"
/posts/:slug/comments   → /posts/hello/comments
```

### Parameter with regex constraint - `:name(expr)`

Only matches if the value satisfies the regular expression.

```
/users/:id([0-9]+)      → /users/42   ✓     /users/abc  ✗
/files/:name([a-z_]+)   → /files/foto ✓     /files/123  ✗
```

### Optional parameter - `:name!`

The segment is optional. If not present, `UParam("name")` returns `""`.

```
/docs/:section!         → /docs/intro  ✓    /docs  ✓
```

### Wildcard

```
/static/*               → matches any route that starts with /static
```

---

## Route groups

Allows you to apply a URL prefix and common middleware to a set of routes.

```harbour
oSrv:AddRouteGroup( "/api/v1", "HixMwJwt", "api", {|o|
   o:AddRouteGet(    "items.list",   "/items",     {|| _ItemList()          } )
   o:AddRoutePost(   "items.create", "/items",     {|| _ItemCreate()        } )
   o:AddRouteGet(    "items.one",    "/items/:id", {|| _ItemGet()           } )
   o:AddRoutePut(    "items.update", "/items/:id", {|| _ItemUpdate()        } )
   o:AddRouteDelete( "items.delete", "/items/:id", {|| _ItemDelete()        } )
} )
```

Routes in the block inherit the `/api/v1` prefix and the `HixMwJwt` middleware.
A route with its own middleware keeps it; the group's middleware only applies if it has none.

---

## URL generation

`URoute` generates the URL of a route based on its name, replacing parameters in order.

```harbour
URoute( "customer.show", 42 )       // → "/customers/42"
URoute( "customer.index" )          // → "/customers"
```

Useful for avoiding hardcoded URLs in views and redirects:

```harbour
URedirect( URoute( "customer.show", nId ) )
```

---

## Error handlers

By default, HIX responds with a standard JSON when it does not find a route (404)
or the method is not allowed (405). They can be replaced:

```harbour
oSrv:SetRouteHandler( "404", {|| USendError( 404, "Page not found" ) } )
oSrv:SetRouteHandler( "405", {|| USendError( 405, "Method not allowed"  ) } )
```

---

## Middleware

Middleware is a function that executes **before** the route's action.
It can validate JWT tokens, check sessions, apply rate limiting, etc. If the middleware
rejects the request, the action is not executed.

```harbour
oSrv:AddRouteGet( "dashboard", "/dashboard", {|| _Dashboard() }, "HixMwRequireAuth" )
```

See the **[Middleware](../middleware/middleware.md)** chapter for the complete reference.


