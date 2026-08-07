# Helpers `U*` — Referencia completa

Helpers disponibles en cualquier acción de ruta / controller. Todos leen el request thread-local que el router establece.

## Leer entrada

| Helper | Devuelve |
|--------|----------|
| `UGet( cKey, xDef )` | Param de query string. Sin args → hash de todos. |
| `UPost( cKey, xDef )` | Clave de POST form / JSON body. Sin args → hash de todos. |
| `UParam( cKey )` | `:var` de ruta. Sin default → error 400. |
| `UParam( cKey, xDef )` | `:var` de ruta con fallback. |
| `UHeader( cKey, xDef )` | Header HTTP (case-insensitive). |
| `UCookie( cName, xDef )` | Cookie del request. |
| `UBody()` | Body en bruto (string). |
| `UJson()` | Body parseado como JSON → hash/array/NIL. |
| `UFiles()` | Ficheros subidos: array de `{ "name", "data", "mime", "size" }`. |

## Introspección

| Helper | Devuelve |
|--------|----------|
| `UMethod()` | `"GET"`, `"POST"`, ... |
| `UPath()` | `"/api/users/42"` |
| `UQuery()` | `"page=1&limit=10"` |
| `UIsGet()` | `.T.` / `.F.` |
| `UIsPost()` | `.T.` / `.F.` |
| `UIsAjax()` | `.T.` si `X-Requested-With: XMLHttpRequest` |
| `UIsJson()` | `.T.` si `Content-Type: application/json` |
| `UWantsJson()` | `.T.` si `Accept: application/json` |
| `UIsForm()` | `.T.` si `application/x-www-form-urlencoded` |
| `UIsMultipart()` | `.T.` si `multipart/form-data` |
| `UIsHttps()` | `.T.` si TLS |
| `UScheme()` | `"http"` / `"https"` |
| `UIP()` | IP real del cliente (respeta `X-Forwarded-For` si `mode=proxied`) |
| `UHost()` | Host solicitado |
| `UPort()` | Puerto TCP |

## Enviar respuestas

| Helper | Efecto |
|--------|--------|
| `USendJson( xData [, nStatus] )` | JSON. `xData` = hash/array/string. Default 200. |
| `USendHtml( cHtml [, nStatus] )` | HTML. Default 200. |
| `USendText( cText [, nStatus] )` | text/plain. Default 200. |
| `USendEmpty()` | 204 No Content. |
| `USendError( nStatus, cMsg )` | Error HTTP con mensaje. |
| `URedirect( cUrl [, nStatus] )` | 302 (o 301 con `nStatus`). |
| `USendView( cView [, hVars] )` | Renderiza template + envía HTML. |
| `USendStreamStart( cMime, nStatus [, hExtra] )` | Inicia streaming chunked (SSE). |
| `USendChunk( cData )` | Envía un chunk. |
| `USendEnd()` / `USendStreamEnd()` | Cierra el stream. |

## Respuesta con buffer (control fino)

| Helper | Efecto |
|--------|--------|
| `USetStatus( nStatus )` | Status de respuesta. |
| `USetMime( cType )` | Content-Type (nombre corto: `"json"`, `"html"`, `"text"`, o mime completo). |
| `USetHeader( cName, cValue )` | Header de respuesta. |
| `UWrite( cData )` | Añade al buffer de respuesta (el dispatcher hace flush cuando la acción retorna). |

## Cookies (respuesta)

    USetCookie( cName, cValue, nMaxAge )
    // nMaxAge  0  → cookie de sesión
    //         -1  → expira inmediatamente
    //        > 0  → segundos

Flags aplicados automáticamente: `HttpOnly; SameSite=Lax; Path=/`.

## Vistas

| Helper | Efecto |
|--------|--------|
| `USendView( cView [, hVars] )` | Renderiza + envía. |
| `UView( cView [, hVars] )` | Renderiza, devuelve string (sin enviar). |

## Sesiones (formas cortas)

| Helper | Efecto |
|--------|--------|
| `USession( cKey )` | Lee valor de sesión. |
| `USession():Set( cKey, xValue )` | Escribe. |
| `USession():Save()` | Persiste + renueva cookie. |
| `USession():Destroy()` | Limpia + expira cookie. |

## Validación

| Helper | Efecto |
|--------|--------|
| `UValidatePost( hRules )` | Valida body POST → devuelve validator. |
| `UValidateGet( hRules )` | Valida query. |
| `UValidateParams( hRules )` | Valida query + params de ruta. |
| `UValidateJson( hRules )` | Valida body JSON. |
| `UValidateOrFail( hRules )` | Valida POST; 422 automático si falla (devuelve NIL). |

## Generación de URLs

| Helper | Devuelve |
|--------|----------|
| `URoute( cName [, xArgs...] )` | URL nombrada con `:var`s sustituidas. |

## Cuándo usar `U*` vs `oReq:`

Usa **siempre** `U*` en código de ruta/controller. `oReq:Respond()` se llama por debajo desde `U*` — usarlo directo salta el buffering y puede provocar bugs de doble respuesta.

La única excepción: cuando tienes `oCtx` en un middleware y quieres responder desde ahí: `oCtx:oReq:Respond(...)`.
