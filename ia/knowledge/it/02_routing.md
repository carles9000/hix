# Routing

Due modi per registrare le route: imperativo (codice Harbour) e dichiarativo (JSON, hixstyle).

## Schema JSON delle route

Array di oggetti route. Ogni oggetto:

| Campo | Tipo | Obbligatorio | Esempio |
|-------|------|----------|---------|
| name | string | sì | `"users.list"` |
| url | string | sì | `"/users/:id"` |
| method | string | sì | `"GET"` / `"POST"` / `"PUT"` / `"DELETE"` / `"PATCH"` |
| action | string | sì | `"users@list"` (`controller@method`) |
| middleware | string | no | `"HIX_MwSession,HIX_MwJwt"` (separati da virgola) |
| scope | string | no | `"admin"` (metadata, libero) |
| onFail | string | no | Nome route per redirect se il middleware rifiuta |

## Pattern URL

- Letterale: `/users`
- Variabile: `/users/:id` — catturato come `UParam("id")`
- Variabile con regex: `/users/:id([0-9]+)`
- Wildcard: `/static/*`

## Registrazione imperativa

    oSrv:AddRouteGet(    "home", "/",             {|| USendHtml("<h1>Hi</h1>") } )
    oSrv:AddRoutePost(   "sub",  "/subscribe",    {|| _Subscribe() } )
    oSrv:AddRoutePut(    "edit", "/users/:id",    {|| _Update(UParam("id")) } )
    oSrv:AddRouteDelete( "del",  "/users/:id",    {|| _Delete(UParam("id")) } )

Signature:

    AddRouteXxx( cName, cPattern, bAction [, cMiddleware, cScope, uCargo] )

`bAction` è un codeblock senza parametri — la request corrente è accessibile tramite gli helper `U*`, che leggono un thread-local `HIX_GetRequest()`.

## Gruppi di route

    oSrv:AddRouteGroup( "/api/v1", "HIX_MwJwt", NIL, {|o|
       o:AddRouteGet(  "list", "/items",     {|| USendJson(aItems) } )
       o:AddRoutePost( "add",  "/items",     {|| _Create() } )
       o:AddRouteGet(  "one",  "/items/:id", {|| _Get(UParam("id")) } )
    } )

Tutte le route figlie ereditano il prefisso e il middleware.

## Eliminare una route

    oSrv:DeleteRoute( "home" )

## Handler 404 / 405

    oSrv:SetRouteHandler( "404", {|| USendError( 404, "Not found"   ) } )
    oSrv:SetRouteHandler( "405", {|| USendError( 405, "Not allowed" ) } )

## Generazione URL (route con nome)

    cUrl := URoute( "users.one", 42 )   // -> "/users/42"

## Regole d'oro

- Rispondi **sempre** tramite gli helper `U*` (`USendJson`, `USendHtml`, ...). Mai chiamare `oReq:Respond()` in un codeblock di route.
- I nomi delle route devono essere unici.
- L'ordine di registrazione conta solo quando i pattern si sovrappongono — vince il primo match.
- La stringa middleware è separata da virgole (gli spazi vengono trimmati).

## Pattern comuni

Guarda un'intera sezione:

    { "url": "/admin/*", "method": "GET", "action": "admin@dashboard", "middleware": "HIX_MwSession,HIX_MwRequireRole", "scope": "admin" }

POST pubblico con CSRF:

    { "url": "/contact", "method": "POST", "action": "contact@submit", "middleware": "HIX_MwCsrf" }

API rate-limited:

    { "url": "/api/search", "method": "GET", "action": "api@search", "middleware": "HIX_MwRateLimit" }
