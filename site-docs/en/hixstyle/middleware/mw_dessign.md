# 🧩 Middleware - Design

## Middleware structure

Basically it's made up of 2 functions within the same .prg:

- Setup: Some variable we define by default and can reconfigure if necessary
- Middleware: function that will execute the process and can use the setup variable

This could be the design of a middleware

```clipper
STATIC s_MyVar := 3600

FUNCTION Mw_FenixSetup( nExpSecs )

   IF ValType( nExpSecs ) == "N" .AND. nExpSecs > 0
      s_MyVar := nExpSecs 
   ENDIF
   
RETURN nil 

FUNCTION Mw_Fenix( oCtx ) 
   LOCAL lAccept := .T.
   ... 
  
      // Use of s_MyVar 
  
   ... 
	  
RETURN lAccept 
```


## Design dynamics by application type

Not all applications need the same middlewares. The choice depends on
who consumes the API and how.

Here we show some design examples according to the scenario.


### Classic Web Application (HTML + forms)

The user interacts from a browser. State is saved in session with cookie.

```
Browser request
     │
     ├─ MW_BodyLimit      ← limit size (uploads)
     ├─ MW_Session        ← load session from cookie
     ├─ MW_Csrf           ← verify CSRF token on POST/PUT/DELETE
     ├─ MW_RequireAuth    ← is there an active session?
     └─ MW_RequireRole    ← does it have the necessary role?
```

Order matters: load the session first, then verify CSRF (which needs the
session), and only then check authentication.

### REST API (JSON, external client)

The client is a mobile app, SPA, or external service. No session cookies: the
authentication is stateless with JWT or API Key.

```
API client request
     │
     ├─ MW_Cors           ← CORS headers for the browser
     ├─ MW_RateLimit      ← protection against abuse
     ├─ MW_BodyLimit      ← limit body size
     ├─ MW_Jwt            ← validate Bearer token
     ├─ MW_RequireAuth    ← is token valid?
     └─ MW_RequireRole    ← sufficient role?
```

### Internal service (machine-to-machine)

Communication between services in the same system. No human users, no sessions.
Authentication is by static API Key.

```
Internal service request
     │
     ├─ MW_BodyLimit      ← basic protection
     ├─ MW_ApiKey         ← validate X-Api-Key
     └─ MW_RequireAuth    ← key known?
```

---

## What to protect and what not to

### Always protect

| What? | With what? |
|---|---|
| Private routes (panel, user data) | Authentication + roles |
| Endpoints that modify data (POST/PUT/DELETE) | CSRF on web, JWT/ApiKey on API |
| File upload or large payloads | Body limit |
| Public endpoints with high traffic | Rate limiting |
| Anything that returns sensitive data | HTTP security headers |

### Don't over-protect

A common mistake is applying all middlewares to all routes as a precaution. The
result is unnecessary added latency and code that's harder to debug.

> The public welcome page doesn't need JWT.
> A health-check endpoint doesn't need session.
> Static assets don't need CSRF.

The rule is simple: apply the minimum middleware necessary for the level of trust
that route requires.

---

## Conceptual examples

### Simple example: request logging

The simplest possible middleware blocks nothing. It only observes and logs:

```
Request arrives
     │
     ▼
[MW_ReqLog]
  Notes: method + path + IP in the log
  Always returns .T.
     │
     ▼
  Handler - executes normally
```

Useful for traceability: knowing what routes are called, how frequently, from what IPs.

### Composite example: protected API route

An API route that only authenticated users with `editor` role can use:

```
POST /api/articles  (create article)
     │
     ▼
[MW_RateLimit]
  Has this IP exceeded 100 req/min?
  No → .T., continue
     │
     ▼
[MW_Jwt]
  Is there an Authorization: Bearer xxx header?
  Is the token valid and not expired?
  Yes → deposits payload in oCtx:hData["jwt"] → .T.
  No → responds 401 → .F. → breaks
     │
     ▼
[MW_RequireRole("editor")]
  Is oCtx:hData["jwt"]["role"] == "editor"?
  Yes → .T.
  No → responds 403 → .F. → breaks
     │
     ▼
  Handler _CreateArticle()
  Already knows that the user is valid and has permission.
  Only concerned with creating the article.
```

Three middlewares, three clear responsibilities, clean business code.


