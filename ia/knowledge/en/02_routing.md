# Routing

Two ways to register routes: imperative (Harbour code) and declarative (JSON, hixstyle).

## Route JSON schema

Array of route objects. Each object:

| Field | Type | Required | Example |
|-------|------|----------|---------|
| name | string | yes | `"users.list"` |
| url | string | yes | `"/users/:id"` |
| method | string | yes | `"GET"` / `"POST"` / `"PUT"` / `"DELETE"` / `"PATCH"` |
| action | string | yes | `"users@list"` (`controller@method`) |
| middleware | string | no | `"HIX_MwSession,HIX_MwJwt"` (comma-separated) |
| scope | string | no | `"admin"` (metadata, free) |
| onFail | string | no | Route name to redirect to if middleware rejects |

## URL patterns

- Literal: `/users`
- Variable: `/users/:id` — captured as `UParam("id")`
- Variable with regex: `/users/:id([0-9]+)`
- Wildcard: `/static/*`

## Imperative registration

    oSrv:AddRouteGet(    "home", "/",             {|| USendHtml("<h1>Hi</h1>") } )
    oSrv:AddRoutePost(   "sub",  "/subscribe",    {|| _Subscribe() } )
    oSrv:AddRoutePut(    "edit", "/users/:id",    {|| _Update(UParam("id")) } )
    oSrv:AddRouteDelete( "del",  "/users/:id",    {|| _Delete(UParam("id")) } )

Signature:

    AddRouteXxx( cName, cPattern, bAction [, cMiddleware, cScope, uCargo] )

`bAction` is a codeblock with no parameters — the current request is accessible via `U*` helpers, which read a thread-local `HIX_GetRequest()`.

## Route groups

    oSrv:AddRouteGroup( "/api/v1", "HIX_MwJwt", NIL, {|o|
       o:AddRouteGet(  "list", "/items",     {|| USendJson(aItems) } )
       o:AddRoutePost( "add",  "/items",     {|| _Create() } )
       o:AddRouteGet(  "one",  "/items/:id", {|| _Get(UParam("id")) } )
    } )

All child routes inherit the prefix and middleware.

## Delete a route

    oSrv:DeleteRoute( "home" )

## 404 / 405 handlers

    oSrv:SetRouteHandler( "404", {|| USendError( 404, "Not found"   ) } )
    oSrv:SetRouteHandler( "405", {|| USendError( 405, "Not allowed" ) } )

## URL generation (named routes)

    cUrl := URoute( "users.one", 42 )   // -> "/users/42"

## Golden rules

- **Always** respond via `U*` helpers (`USendJson`, `USendHtml`, ...). Never call `oReq:Respond()` in a route codeblock.
- Route names must be unique.
- Registration order matters only when patterns overlap — first match wins.
- Middleware string is comma-separated (spaces are trimmed).

## Common patterns

Guard entire section:

    { "url": "/admin/*", "method": "GET", "action": "admin@dashboard", "middleware": "HIX_MwSession,HIX_MwRequireRole", "scope": "admin" }

Public POST with CSRF:

    { "url": "/contact", "method": "POST", "action": "contact@submit", "middleware": "HIX_MwCsrf" }

Rate-limited API:

    { "url": "/api/search", "method": "GET", "action": "api@search", "middleware": "HIX_MwRateLimit" }
