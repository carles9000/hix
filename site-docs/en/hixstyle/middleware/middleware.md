# 🛡️ Middleware - Introduction

The middleware section is perhaps one of the most important aspects when designing a web application, because it's responsible for security. Many of you may already know about this topic, but it's vital to study it carefully to understand how we should design them. It's a bit extensive but necessary to fit all the pieces together.

Imagine you have a store with a single entrance. Before a customer reaches the counter, they pass through a security guard, then a metal detector, and if they have a VIP card, through priority access. Only then do they reach the clerk.

**Middleware** is simply a function that returns a logical value .T./.F.
This function receives a parameter `oCtx` which is the context of the call, but we can use UHelpers
to access them more easily.

In this example, we check that the request carries a valid API Key in the
`X-Api-Key` header:

```clipper
FUNCTION MW_ApiKey()

   LOCAL cKey := UHeader( "X-Api-Key", "" )

   IF cKey != "clave-secreta-123"
      USendError( 401, "Invalid API Key" )
      RETURN .F.
   ENDIF

RETURN .T.
```

In this case, the middleware retrieves the header to verify that the request has an 'X-Api-Key' header and we validate its key.




### Container - UMiddleware()

`UMiddleware` is the container that HIX uses internally to execute any middleware, whether it's a function by name or a codeblock. This class will return us an object that will be responsible for executing our function and handling it. Following our example, we would define our MW like this.

```clipper
UMiddleware():New( "MW_ApiKey", "apikey" )
```

The second parameter is a descriptive name that appears in the logs when the middleware breaks the chain and helps us trace.

### Route <-> Middleware relationship

When we define our route, we associate it with our middleware (MW). Only if we pass the security layer of the MW, the server executes the route. Otherwise, the middleware will be responsible, depending on how we define it, for what it should do.

Ex: We define a route that will use the middleware we designed `MW_ApiKey`

```clipper
oSrv:AddRouteGet( "data", "/data", 'mydata.prg', "MW_ApiKey" )
```

We define `mydata.prg`, a simple function that returns a response, but it will only be executed if it has successfully passed the middleware control.

```clipper
FUNCTION MyData()
   USendJson( { "info" => "only for clients with API Key", "ok" => .T. } )
RETURN NIL
```

### Runtime flow

```
GET /data  (without X-Api-Key header)
     │
     ▼
[MW_ApiKey]
  X-Api-Key header present and correct?
  No → USendError(401) → RETURN .F. → break
     │ Yes
     ▼
  MyData()  ← only reaches here if the key is valid
```

**NOTE** With middleware you define the rules **once** and apply them to the routes that need them, in a declarative and consistent way.

### Setup (parameters)

The last detail to know is that we can create a static or dynamic middleware. In case we want to reuse a middleware, we'll have to define its `setup` in some way. This means that when we define in our system that we're going to use the middleware MW_A(), we can also tell it what parameters it will work with.

Imagine we have a MW that controls how many times an IP makes a request and we want that on our endpoint it can't be executed more than 10 times per minute. In this case, we define our general-use MW and configure it with a setup of 10.

Each MW carries its own setup if defined that way.

## Multiple middlewares - UBaseMiddleware

But the matter of middleware isn't that simple, and now we're going to take a small leap. We can easily have many middleware that are necessary to manage our security. The system must manage the arrival of the HTTP request and the moment when your business logic processes it.

How would our system work?

```
 HTTP Request
       │
       ▼
┌──────────────┐
│ Middleware 1 │  ← Passes? ──No──▶  Responds 401/403/429...
└──────┬───────┘
       │ Yes
       ▼
┌──────────────┐
│ Middleware 2 │  ← Passes? ──No──▶  Responds 503/413...
└──────┬───────┘
       │ Yes
       ▼
┌──────────────────────────────┐
│   Your business logic        │  ← Only what should arrive gets here
└──────────────────────────────┘
```

This group of middleware we'll call a **pipeline** or **middleware stack**.

When a route needs multiple chained controls, a composite middleware function is created. `UBaseMiddleware` executes the list in order and breaks at the first failure.

In this example, we protect an administration endpoint that requires:

1. **Rate limiting** - maximum 60 requests per minute per IP
2. **Valid JWT** - verified Bearer token
3. **Admin role** - the token must include that role

Only and only if it passes these controls can it execute the route!

```clipper
// ============================================================
// MW_Admin group — rate limit + JWT + admin role
// ============================================================
FUNCTION MW_Admin( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HixMwRateLimit", "rate"  ) )
   o:Add( UMiddleware():New( "HixMwJwt"      , "jwt"   ) )
   o:Add( UMiddleware():New( "MW_ApiKey"     , "roles" ) )

RETURN o:Run()
```

With this security system that we've designed, we can now apply it to different routes.

If we define the system from code to compile everything:

```clipper
...
	LOCAL oSrv := THixServer():New()

	// --- Configuration (before Start) ---
	HIX_MwRateLimitSetup( 60, 60 )          // 60 req/min per IP
	HIX_MwJwtSetup( "mi-clave-secreta", 3600 )

...

	// --- Admin panel routes ---
	oSrv:AddRouteGet(    "admin.users",   "/admin/users",     'users.prg'      , "MW_Admin" )
	oSrv:AddRouteDelete( "admin.user",    "/admin/users/:id", 'users_del.prg'  , "MW_Admin" )
	oSrv:AddRouteGet(    "admin.metrics", "/admin/metrics",   'metrics.prg'    , "MW_Admin" )
	
...
	
	oSrv:Start()	
```

Runtime flow for any of those routes:

```
GET /admin/users
     │
     ▼
[HixMwRateLimit]
  Has the IP exceeded 60 req/min?
  No → .T.
  Yes → 429 Too Many Requests → .F. → breaks
     │
     ▼
[HixMwJwt]
  Is the Bearer token valid?
  Yes → deposits payload in oCtx:hData["jwt"] → .T.
  No → 401 Unauthorized → .F. → breaks
     │
     ▼
[MW_ApiKey]
  Is oCtx:hData["jwt"]["role"] == "admin"?
  Yes → .T.
  No → 403 Forbidden → .F. → breaks
     │
     ▼
  _AdminUsers()  ← only reaches here if it passes all three controls
```

The advantage of grouping in `MW_Admin` is that the three routes share exactly the same pipeline. If tomorrow we need to add a fourth control (for example, audit logging), we add one line in `MW_Admin` and the three routes are automatically protected, and maintenance is done only in 1 file!!!

```clipper
// Add audit to all admin routes — just one change
FUNCTION MW_Admin( oCtx )

   LOCAL o := UBaseMiddleware():New( oCtx )

   o:Add( UMiddleware():New( "HixMwRateLimit", "rate"    ) )
   o:Add( UMiddleware():New( "HixMwJwt"      , "jwt"     ) )
   o:Add( UMiddleware():New( "MW_ApiKey"     , "roles"   ) )
   o:Add( UMiddleware():New( "MW_AuditLog"   , "audit"   ) )  // new

RETURN o:Run()
```

Middleware is a structural component that acts as an intermediate layer between the operating system and applications, enabling communication between distributed systems. In an architecture, its role is to decouple components, allowing them to exchange information and functions without needing to know the internal technical details of each other.

**SUMMARY**
The middleware topic is important to control our application's security. We can choose not to use them and the application will work the same, but depending on what type of module we run, it could be exposed.

It's worth investing in doing some testing and understanding and learning how to use this mechanism, which will help us avoid possible intrusions or unauthorized access.

!!! info "Next chapter" How we should design a middleware layer.
