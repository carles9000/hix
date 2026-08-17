# Helper `U*` — Riferimento Completo

Helper disponibili in qualsiasi action di route / controller. Leggono tutti la request thread-local impostata dal router.

## Lettura input

| Helper | Ritorna |
|--------|---------|
| `UGet( cKey, xDef )` | Parametro query string. Senza argomenti → hash di tutti. |
| `UPost( cKey, xDef )` | Campo POST form o JSON body. Senza argomenti → hash di tutti. |
| `UParam( cKey )` | Route `:var`. Senza default → errore 400. |
| `UParam( cKey, xDef )` | Route `:var` con fallback. |
| `UHeader( cKey, xDef )` | Header HTTP (case-insensitive). |
| `UCookie( cName, xDef )` | Cookie dalla request. |
| `UBody()` | Body raw come stringa. |
| `UJson()` | Body parsato come JSON → hash/array/NIL. |
| `UFiles()` | File caricati: array di `{ "name", "data", "mime", "size" }`. |

## Introspezione

| Helper | Ritorna |
|--------|---------|
| `UMethod()` | `"GET"`, `"POST"`, ... |
| `UPath()` | `"/api/users/42"` |
| `UQuery()` | `"page=1&limit=10"` |
| `UIsGet()` | `.T.` / `.F.` |
| `UIsPost()` | `.T.` / `.F.` |
| `UIsAjax()` | `.T.` se `X-Requested-With: XMLHttpRequest` |
| `UIsJson()` | `.T.` se `Content-Type: application/json` |
| `UWantsJson()` | `.T.` se `Accept: application/json` |
| `UIsForm()` | `.T.` se `application/x-www-form-urlencoded` |
| `UIsMultipart()` | `.T.` se `multipart/form-data` |
| `UIsHttps()` | `.T.` se TLS |
| `UScheme()` | `"http"` / `"https"` |
| `UIP()` | IP reale del client (rispetta `X-Forwarded-For` se `mode=proxied`) |
| `UHost()` | Host richiesto |
| `UPort()` | Porta TCP |

## Invio risposte

| Helper | Effetto |
|--------|--------|
| `USendJson( xData [, nStatus] )` | JSON. `xData` = hash/array/stringa. Default 200. |
| `USendHtml( cHtml [, nStatus] )` | HTML. Default 200. |
| `USendText( cText [, nStatus] )` | text/plain. Default 200. |
| `USendEmpty()` | 204 No Content. |
| `USendError( nStatus, cMsg )` | Errore HTTP con messaggio. |
| `URedirect( cUrl [, nStatus] )` | 302 (o 301 con `nStatus`). |
| `USendView( cView [, hVars] )` | Renderizza template + invia HTML. |
| `USendStreamStart( cMime, nStatus [, hExtra] )` | Inizia streaming chunked (SSE). |
| `USendChunk( cData )` | Invia un chunk. |
| `USendEnd()` / `USendStreamEnd()` | Chiude lo stream. |

## Risposta bufferizzata (controllo fine)

| Helper | Effetto |
|--------|--------|
| `USetStatus( nStatus )` | Status della response. |
| `USetMime( cType )` | Content-Type (nome breve: `"json"`, `"html"`, `"text"`, o mime completo). |
| `USetHeader( cName, cValue )` | Header della response. |
| `UWrite( cData )` | Append al buffer della response (il dispatcher fa il flush quando l'action ritorna). |

## Cookie (risposta)

    USetCookie( cName, cValue, nMaxAge )
    // nMaxAge  0  → cookie di sessione
    //         -1  → scade immediatamente
    //        > 0  → secondi

Flag applicati automaticamente: `HttpOnly; SameSite=Lax; Path=/`.

## View

| Helper | Effetto |
|--------|--------|
| `USendView( cView [, hVars] )` | Renderizza + invia. |
| `UView( cView [, hVars] )` | Renderizza, ritorna stringa (no send). |

## Sessioni (forme brevi)

| Helper | Effetto |
|--------|--------|
| `USession( cKey )` | Legge un valore di sessione. |
| `USession():Set( cKey, xValue )` | Scrive. |
| `USession():Save()` | Persiste + refresh del cookie. |
| `USession():Destroy()` | Wipe + scadenza cookie. |

## Validazione

| Helper | Effetto |
|--------|--------|
| `UValidatePost( hRules )` | Valida il body POST → ritorna il validator. |
| `UValidateGet( hRules )` | Valida la query. |
| `UValidateParams( hRules )` | Valida query + parametri di route. |
| `UValidateJson( hRules )` | Valida il body JSON. |
| `UValidateOrFail( hRules )` | Valida POST; auto 422 su fallimento (ritorna NIL). |

## Generazione URL

| Helper | Ritorna |
|--------|---------|
| `URoute( cName [, xArgs...] )` | URL con nome con i `:var` sostituiti. |

## Quando usare `U*` vs `oReq:`

**Sempre** usa `U*` nel codice di route/controller. `oReq:Respond()` è chiamato DA `U*` dietro le quinte — usarlo direttamente bypassa il buffering e può portare a bug di doppia risposta.

L'unica eccezione è quando hai `oCtx` in un middleware e vuoi rispondere da lì: `oCtx:oReq:Respond(...)`.
