# Routing

Dos formas de registrar rutas: imperativa (código Harbour) y declarativa (JSON, hixstyle).

## Esquema JSON de rutas

Array de objetos-ruta. Cada objeto:

| Campo | Tipo | Obligatorio | Ejemplo |
|-------|------|-------------|---------|
| name | string | sí | `"users.list"` |
| url | string | sí | `"/users/:id"` |
| method | string | sí | `"GET"` / `"POST"` / `"PUT"` / `"DELETE"` / `"PATCH"` |
| action | string | sí | `"users@list"` (`controller@method`) |
| middleware | string | no | `"HIX_MwSession,HIX_MwJwt"` (separado por comas) |
| scope | string | no | `"admin"` (metadata libre) |
| onFail | string | no | Nombre de ruta a la que redirigir si un middleware rechaza |

## Patrones de URL

- Literal: `/users`
- Variable: `/users/:id` — capturada con `UParam("id")`
- Variable con regex: `/users/:id([0-9]+)`
- Comodín: `/static/*`

## Registro imperativo

    oSrv:AddRouteGet(    "home", "/",             {|| USendHtml("<h1>Hola</h1>") } )
    oSrv:AddRoutePost(   "sub",  "/subscribe",    {|| _Subscribe() } )
    oSrv:AddRoutePut(    "edit", "/users/:id",    {|| _Update(UParam("id")) } )
    oSrv:AddRouteDelete( "del",  "/users/:id",    {|| _Delete(UParam("id")) } )

Firma:

    AddRouteXxx( cName, cPattern, bAction [, cMiddleware, cScope, uCargo] )

`bAction` es un codeblock sin parámetros — el request actual se lee mediante los helpers `U*`, que consultan un `HIX_GetRequest()` thread-local.

## Grupos de rutas

    oSrv:AddRouteGroup( "/api/v1", "HIX_MwJwt", NIL, {|o|
       o:AddRouteGet(  "list", "/items",     {|| USendJson(aItems) } )
       o:AddRoutePost( "add",  "/items",     {|| _Create() } )
       o:AddRouteGet(  "one",  "/items/:id", {|| _Get(UParam("id")) } )
    } )

Todas las rutas hijas heredan el prefijo y el middleware.

## Borrar una ruta

    oSrv:DeleteRoute( "home" )

## Handlers 404 / 405

    oSrv:SetRouteHandler( "404", {|| USendError( 404, "No encontrado" ) } )
    oSrv:SetRouteHandler( "405", {|| USendError( 405, "No permitido" ) } )

## Generación de URLs (rutas con nombre)

    cUrl := URoute( "users.one", 42 )   // -> "/users/42"

## Reglas de oro

- **Siempre** responde con helpers `U*` (`USendJson`, `USendHtml`, ...). Nunca llames a `oReq:Respond()` desde un codeblock de ruta.
- Los nombres de ruta deben ser únicos.
- El orden de registro solo importa cuando los patrones se solapan — gana la primera coincidencia.
- El string de middleware va separado por comas (los espacios se recortan).

## Patrones comunes

Proteger una sección entera:

    { "url": "/admin/*", "method": "GET", "action": "admin@dashboard", "middleware": "HIX_MwSession,HIX_MwRequireRole", "scope": "admin" }

POST público con CSRF:

    { "url": "/contact", "method": "POST", "action": "contact@submit", "middleware": "HIX_MwCsrf" }

API rate-limited:

    { "url": "/api/search", "method": "GET", "action": "api@search", "middleware": "HIX_MwRateLimit" }
