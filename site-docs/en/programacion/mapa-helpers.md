# 📘 HIX - Complete Reference of U* Helpers

The `U*` helpers are global functions accessible from any route, controller, or
`.hrb` file without needing to pass `oReq` as a parameter. The dispatcher calls
`HIX_SetRequest(oReq)` before executing each action, so the helpers always
have access to the request of the current thread.


---

## 1. Reading the request

### Input data

| Function | Returns | Description |
|---|---|---|
| `UMethod()` | `C` | HTTP method in uppercase: `"GET"`, `"POST"`, `"PUT"`, `"DELETE"`, `"PATCH"` |
| `UPath()` | `C` | Path without query string: `"/api/users/42"` |
| `UQuery()` | `C` | Raw query string: `"page=1&limit=10"` |
| `UGet(cKey, xDef)` | `X` | Query string parameter. Without arguments returns complete hash |
| `UPost(cKey, xDef)` | `X` | POST body field (form or JSON). Without arguments returns complete hash |
| `UParam(cKey, xDef)` | `C` | Route variable `:var`. Without default throws 400 error if missing |
| `UHeader(cKey, xDef)` | `C` | HTTP header (case-insensitive) |
| `UCookie(cName, xDef)` | `C` | Request cookie (parsed once, lazy) |
| `UBody()` | `C` | Raw body as string |
| `UJson()` | `H`/`A` | Body parsed as JSON; `NIL` if body is not valid JSON |
| `UContentType()` | `C` | Content-Type in lowercase: `"application/json"` |
| `UContentLength()` | `N` | Body length in bytes |
| `UFiles()` | `A` | Array of hashes of uploaded files (multipart). See uploads section |
| `URequest()` | `O` | `THixRequest` object of the current thread (low-level access) |
| `UContext()` | `O` | `THixContext` of the current middleware chain (access to `oCtx:hData`); `NIL` if not in MW chain |

**UGet / UPost without arguments**: return a hash with all fields.

```clipper
// Get all GET parameters at once
hParams := UGet()   // { "page" => "1", "limit" => "10" }

// Get a field with default
cNombre := UPost( "nombre", "Anonymous" )

// Route variable with safe default
nId := Val( UParam( "id", "0" ) )

// Route variable without default - throws 400 if missing
cSlug := UParam( "slug" )
```

**UParam with numeric index**: when the route uses `*` the wildcard is captured as `_1`.

```clipper
oSrv:AddRouteGet( "static", "/static/*", {||
   cFile := UParam( 1 )   // equivalent to UParam("_1")
} )
```

### Content type and negotiation

| Function | Returns | Description |
|---|---|---|
| `UIsGet()` | `L` | `.T.` if method is GET |
| `UIsPost()` | `L` | `.T.` if method is POST |
| `UIsAjax()` | `L` | `.T.` if `X-Requested-With: XMLHttpRequest` |
| `UIsHttps()` | `L` | `.T.` if connection is HTTPS |
| `UScheme()` | `C` | `"http"` or `"https"` |
| `UIsJson()` | `L` | `.T.` if Content-Type is `application/json` |
| `UIsForm()` | `L` | `.T.` if Content-Type is `application/x-www-form-urlencoded` |
| `UIsMultipart()` | `L` | `.T.` if Content-Type is `multipart/form-data` |
| `UWantsJson()` | `L` | `.T.` if client prefers JSON (Accept header or AJAX) |

### Client data

| Function | Returns | Description |
|---|---|---|
| `UIP()` | `C` | Client's real IP (respects `X-Forwarded-For` if `mode=proxied`) |
| `UHost()` | `C` | Request hostname (Host header) |
| `UPort()` | `N` | Server port |

### Multipart uploads

```clipper
aFiles := UFiles()
FOR EACH hFile IN aFiles
   // hFile["name"]  -> field name
   // hFile["data"]  -> binary content
   // hFile["mime"]  -> file Content-Type
   // hFile["size"]  -> size in bytes
   hb_MemoWrit( "uploads/" + hFile["name"], hFile["data"] )
NEXT
```

---

## 2. Sending responses

### Direct responses

| Function | Description |
|---|---|
| `USendJson(xData [, nStatus])` | JSON 200. `xData` can be hash, array, or string |
| `USendHtml(cHtml [, nStatus])` | HTML 200 |
| `USendText(cText [, nStatus])` | `text/plain` 200 |
| `USendView(cView [, hVars])` | Renders template and sends HTML |
| `USendEmpty()` | 204 No Content |
| `USendError(nStatus, cDetail)` | HTTP error with detail message |
| `URedirect(cUrl [, nStatus])` | Redirect (302 by default) |

```clipper
// Simple JSON response
USendJson( { "ok" => .T. } )

// With custom status
USendJson( { "id" => 42, "name" => "Test" }, 201 )

// Permanent redirect
URedirect( "/new-url", 301 )

// HTTP error
USendError( 403, "Insufficient permissions" )
```

### Fine-grained buffer control

When you need to build the response step by step before sending it:

| Function | Description |
|---|---|
| `UWrite(cText)` | Accumulates text in response buffer |
| `UEcho(cText)` | Alias for `UWrite` |
| `USetStatus(nStatus)` | Sets HTTP status of buffer |
| `USetMime(cMime)` | Sets MIME of buffer (`"json"`, `"html"`, `"text"` or full MIME) |
| `UGetMime()` | Returns the currently configured MIME |
| `USetHeader(cKey, cVal)` | Adds extra header to response |
| `UFlush()` | Sends accumulated buffer as chunk (initiates streaming if first time) |

```clipper
// Build JSON manually
USetStatus( 201 )
USetMime( "json" )
USetHeader( "X-Request-Id", "abc123" )
UWrite( hb_jsonEncode( { "created" => .T. } ) )
// The dispatcher sends the buffer when the action ends
```

### Cookies in response

| Function | Description |
|---|---|
| `USetCookie(cName, cVal, nMaxAge)` | Writes `Set-Cookie` in response |

`nMaxAge`:
- `0` - session cookie (no `Max-Age`)
- `-1` - expire immediately (`Max-Age=0`)
- `> 0` - duration in seconds

The flags `HttpOnly; SameSite=Lax; Path=/` are added automatically.

```clipper
USetCookie( "session_id", cSid, 3600 )   // 1 hour
USetCookie( "pref", "dark", 0 )          // session
USetCookie( "old_cookie", "", -1 )       // expire
```

---

## 3. Chunked streaming

For SSE, progressive downloads, or long-duration responses:

| Function | Description |
|---|---|
| `USendStreamStart(cMime, nStatus, hExtra)` | Initiates chunked response; extra headers in `hExtra` |
| `USendChunk(cData)` | Sends a chunk of data |
| `USendStreamEnd()` | Closes stream (zero-length chunk) |

```clipper
// SSE - Server-Sent Events
oSrv:AddRouteGet( "events", "/events", {||
   LOCAL i := 0
   USendStreamStart( "text/event-stream", 200, ;
      { "Cache-Control" => "no-cache", "X-Accel-Buffering" => "no" } )
   DO WHILE i < 10
      i++
      USendChunk( "data: " + hb_jsonEncode( { "n" => i } ) + hb_eol() + hb_eol() )
      hb_idleSleep( 1 )
   ENDDO
   USendStreamEnd()
} )
```

---

## 4. Session

| Function | Description |
|---|---|
| `USession()` | Returns a proxy object with methods `Get/Set/Save/Destroy` |
| `USession(cKey)` | Reads a session value; `NIL` if not exists |
| `USession(cKey, xDef)` | Reads a value with default |

```clipper
// Read a field
cUser := USession( "user" )

// Write and save
USession():Set( "user", "carles" )
USession():Set( "role", "admin" )
USession():Save()   // renews TTL and emits Set-Cookie

// Destroy session
USession():Destroy()
```

> Requires that `HIX_MwSession` is registered as middleware on the route.

---

## 5. JWT

| Function | Description |
|---|---|
| `UJwt()` | Returns the complete JWT payload hash; `NIL` if no JWT |
| `UJwt(cKey)` | Returns a claim from payload; `NIL` if not exists |
| `UJwt(cKey, xDef)` | Returns a claim with default |
| `UHasScope(cScope)` | `.T.` if JWT includes the scope in the `scope` field |

```clipper
// Read claim
cSub  := UJwt( "sub" )
nExp  := UJwt( "exp", 0 )

// Check scope
IF ! UHasScope( "read:products" )
   USendError( 403, "Insufficient scope" )
   RETURN
ENDIF
```

> Requires that `HixMwJwt` is registered as middleware on the route.

---

## 6. Authentication and roles

Available when the `HIX_MwAuth` or `HIX_MwIsAuth` middleware is active.

| Function | Description |
|---|---|
| `UCurrentUser()` | Complete hash of authenticated user; `NIL` if no session |
| `UAuthUser()` | Hash of the request's user (set by middleware); `NIL` if not authenticated |
| `UAuthUser(cKey)` | Field of the user hash |
| `UAuthUser(cKey, xDef)` | Field of the hash with default |
| `UHasRole(cRole)` | `.T.` if user has the role (full access) |
| `UHasRole(cRole, cOp)` | `.T.` if user has the role with the specified operation |
| `UGetRoles()` | Hash of user roles: `{ "admin" => "", "editor" => "read;write" }` |
| `UAuthLogout()` | Destroys session and clears current user |

```clipper
// Check role
IF ! UHasRole( "admin" )
   USendError( 403, "Administrators only" )
   RETURN
ENDIF

// Check role with granular operation
IF ! UHasRole( "products", "delete" )
   USendError( 403, "No delete permission" )
   RETURN
ENDIF

// Read user data
hUser := UAuthUser()
cEmail := UAuthUser( "email", "" )

// Logout
UAuthLogout()
URedirect( "/login" )
```

---

## 7. Validation

### Building a validator

| Function | Data source |
|---|---|
| `UValidate(hRules)` | POST (form or JSON) |
| `UValidatePost(hRules)` | Explicit POST |
| `UValidateGet(hRules)` | Query string |
| `UValidateParams(hRules)` | Query string + route variables merged |
| `UValidateJson(hRules)` | Explicit JSON body |
| `UValidateInput(hRules)` | Equivalent to `UValidatePost` (POST form body) |
| `UValidateOrFail(hRules)` | POST - automatically responds 422 if fails; returns `NIL` |

All accept an optional second parameter `hSanitate` with sanitization rules.

### Typical flow

```clipper
FUNCTION _CreateUser()
   LOCAL oVal := UValidateOrFail( { ;
      "name"  => "required|string|max:100", ;
      "email" => "required|string|email",   ;
      "age"   => "required|integer|min:18"  ;
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF   // already responded 422

   cName  := oVal:Get( "name" )
   cEmail := oVal:Get( "email" )
   nAge   := oVal:Get( "age" )
   // ...
   USendJson( { "ok" => .T. }, 201 )
RETURN NIL
```

### Manual error handling

```clipper
LOCAL oVal := UValidatePost( hRules )
IF ! oVal:Make()
   USendJson( { "errors" => oVal:GetErrorsJson() }, 422 )
   RETURN
ENDIF
```

### Available rules

```
required            mandatory field (not empty)
string              string type
integer             integer
numeric             number (int or decimal)
boolean             logical
array               array
min:N               string: length >= N  /  number: value >= N
max:N               string: length <= N  /  number: value <= N
minlen:N            string length >= N
maxlen:N            string length <= N
between:N:M         number between N and M
email               email format
url                 starts with http:// or https://
ip                  valid IPv4
regex:PATRON        Harbour regular expression
in:a,b,c            value in list
notin:a,b           value not in list
field               include the field in DataFields() if valid
```

Sanitization (applied before validation):

```
trim                AllTrim()
lower               Lower()
upper               Upper()
```

### Quick predicates

| Function | Description |
|---|---|
| `UIsMail(cStr)` | `.T.` if `cStr` has email format |
| `UIsNumeric(uValue)` | `.T.` if value is numeric (number or numeric string) |
| `UIsInteger(uValue)` | `.T.` if value is an integer |
| `UIsUrl(cStr)` | `.T.` if starts with `http://` or `https://` |
| `UIsIp(cStr)` | `.T.` if valid IPv4 |

---

## 8. Views / Templates

| Function | Description |
|---|---|
| `USendView(cView [, hVars])` | Renders template and sends HTML response |
| `UView(cView [, hVars])` | Renders template and returns HTML as string |

Templates are located in `www/views/` with `.html` extension.

```clipper
// Render and send
USendView( "users/list.html" )

// With variables
USendView( "users/edit.html", { ;
   "cName" => "Carles", ;
   "nAge"  => 42        ;
} )

// Only get the HTML (to compose partials)
cPartial := UView( "partials/header.html", { "cTitle" => "My app" } )
USendHtml( cPartial + "<main>content</main>" )
```

Template format:

```html
@args cName, nAge

<html>
<body>
  <h1>Edit: {{ cName }}</h1>
  <p>Age: {{ hb_NToS(nAge) }}</p>
</body>
</html>
```

---

## 9. View helpers

### Type conversion

| Function | Description |
|---|---|
| `UStr(u)` | Converts any Harbour type to string (C, N, L, D, A, H) |
| `UDateToHtml(dFecha)` | Harbour date to string `"YYYY-MM-DD"` for HTML inputs |
| `ULogicToHtmlChecked(lValue)` | `.T.` → `"checked"`, `.F.` → `""` (for checkboxes) |
| `UHtmlEncode(cText)` | Escapes HTML entities (`&`, `<`, `>`, `"`, `'`) in one pass |
| `UOsFileName(cFileName)` | Normalizes path separators to the operating system's separator |

### HTML select

```clipper
// UHashToHtmlSelect( aHash, cSelect, cKey, cValue )
// aHash: array of hashes with key and value fields
// cSelect: currently selected value
// cKey: name of the key field in each hash (default "key")
// cValue: name of the value field in each hash (default "value")

aItems := { { "key" => "es", "value" => "Spanish" }, ;
            { "key" => "en", "value" => "English" } }
cHtml := UHashToHtmlSelect( aItems, "es", "key", "value" )
// <option value="" ></option>
// <option value="es" selected>Spanish</option>
// <option value="en">English</option>
```

### Named routes

```clipper
// URoute( cName, param1, param2, ... )
cUrl := URoute( "user", 42 )       // -> "/users/42"
cUrl := URoute( "post", "my-slug" ) // -> "/posts/my-slug"
```

---

## 10. CSRF

Protect HTML forms against Cross-Site Request Forgery attacks.

| Function | Description |
|---|---|
| `UCsrfToHtml([cToken])` | Generates `<input type="hidden" name="_csrf" value="...">` |
| `HIX_CsrfMakeToken([cData])` | Generates a signed CSRF token with the `csrf` key from `HIX_Keys` store |
| `HIX_CsrfValidToken(cToken [, nLapsus])` | `.T.` if token is valid. `nLapsus` in seconds (0 = no expiration) |
| `HIX_CsrfGenRandom([nLen])` | Generates random string of `nLen` bytes |

```clipper
// In the GET action that serves the form
USendView( "form.html", { "cCsrf" => UCsrfToHtml() } )

// In the template
// {{ cCsrf }}   -- emits the <input hidden>

// In the POST action that processes the form
IF ! HIX_CsrfValidToken( UPost( "_csrf" ), 3600 )
   USendError( 403, "Invalid CSRF token" )
   RETURN
ENDIF
```

---

## 11. Resource ID

Signs an opaque ID so it is not predictable in HTML forms.

| Function | Description |
|---|---|
| `UResourceToHtml(cId)` | Generates `<input type="hidden" name="_resource_id" value="...">` with signed ID |
| `UGetResource([cToken])` | Validates token and returns original ID; `""` if invalid |

```clipper
// In the view (record list)
// {{ UResourceToHtml( hb_NToS(nId) ) }}

// In the POST action (delete, edit, ...)
cId := UGetResource()   // reads _resource_id from POST automatically
IF Empty( cId )
   USendError( 400, "Invalid resource ID" )
   RETURN
ENDIF
nId := Val( cId )
```

---

## 12. Flash messages

Temporary validation messages per form, stored in session and destroyed when read.

| Method | Description |
|---|---|
| `UFlash([cFormId])` | Creates a `TFlash` object for the specified form |
| `oFlash:Set(cKey, xVal)` | Saves a flash value |
| `oFlash:Get(cKey [, xDef])` | Reads and deletes the flash value |
| `oFlash:Has(cKey)` | `.T.` if value exists |
| `oFlash:Delete(cKey)` | Deletes a value without reading it |
| `oFlash:Clear()` | Clears all values for the form |
| `oFlash:Save()` | Persists changes to session |
| `oFlash:Destroy()` | Destructor: saves automatically when leaving scope |

```clipper
// Save error in the POST
oFlash := UFlash( "login-form" )
oFlash:Set( "error", "Incorrect credentials" )
oFlash:Set( "email", UPost( "email" ) )
oFlash:Save()
URedirect( "/login" )

// Read in the next GET
oFlash := UFlash( "login-form" )
cError := oFlash:Get( "error", "" )
cEmail := oFlash:Get( "email", "" )
```

---

## 13. Environment and configuration

| Function | Description |
|---|---|
| `UEnv()` | Current environment: `"dev"` or `"prod"` |
| `UIsDev()` | `.T.` if `UEnv() == "dev"` |
| `UIsProd()` | `.T.` if `UEnv() == "prod"` |
| `UConfig(cKey [, xDef])` | Value from `THixConfig` by field name |
| `UMwConfig(cSection, cKey [, xDef])` | Value from `www/middlewares/config.json` section `setup` |
| `UNow()` | Current timestamp as string `"YYYYMMDDHHmmss"` |
| `URoot()` | Name of web root folder (default `"www"`) |
| `URootPath()` | Absolute path to web root with trailing separator |

```clipper
IF UIsDev()
   l( "Debug: " + hb_jsonEncode( hData ) )
ENDIF

cPort := UConfig( "nPort", "8080" )
cKey  := UMwConfig( "auth", "session_user_key", "_auth_user" )
```

---

## 14. Quick reference table

### Read request

```
UMethod()           UPath()             UQuery()
UGet(k,d)           UPost(k,d)          UParam(k,d)
UHeader(k,d)        UCookie(k,d)        UBody()
UJson()             UContentType()      UContentLength()
UFiles()            URequest()          UContext()
```

### Detect type

```
UIsGet()    UIsPost()   UIsAjax()   UIsHttps()
UIsJson()   UIsForm()   UIsMultipart()  UWantsJson()
UScheme()   UIP()       UHost()         UPort()
```

### Send response

```
USendJson(x,n)      USendHtml(c,n)      USendText(c,n)
USendView(v,h)      USendEmpty()        USendError(n,c)
URedirect(u,n)      USend(x,n,m,h)
```

### Control buffer

```
UWrite(c)   UEcho(c)    USetStatus(n)   USetMime(c)
UGetMime()  USetHeader(k,v)  USetCookie(k,v,n)  UFlush()
```

### Streaming

```
USendStreamStart(m,n,h)   USendChunk(c)   USendStreamEnd()
```

### Session and auth

```
USession()  USession(k)  USession(k,d)
UJwt()      UJwt(k)      UJwt(k,d)     UHasScope(s)
UCurrentUser()  UAuthUser(k,d)
UHasRole(r)     UHasRole(r,op)  UGetRoles()  UAuthLogout()
```

### Validation

```
UValidate(h)    UValidatePost(h)  UValidateGet(h)
UValidateParams(h)  UValidateJson(h)  UValidateInput(h)  UValidateOrFail(h)
UIsMail(s)  UIsNumeric(v)  UIsInteger(v)  UIsUrl(s)  UIsIp(s)
```

### Views and helpers

```
USendView(v,h)  UView(v,h)
UStr(u)  UDateToHtml(d)  ULogicToHtmlChecked(l)  UHtmlEncode(c)
UHashToHtmlSelect(a,s,k,v)  URoute(name, ...)  UOsFileName(f)
```

### CSRF, Resource, Flash, Config

```
UCsrfToHtml()       HIX_CsrfValidToken(t,n)
UResourceToHtml(id) UGetResource()
UFlash(id)
UEnv()  UIsDev()  UIsProd()  UConfig(k,d)  UMwConfig(s,k,d)
UNow()  URoot()   URootPath()
```
