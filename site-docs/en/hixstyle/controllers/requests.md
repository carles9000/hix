# ❔ Requests

A **request** is the set of data the client sends to the server in each HTTP call: the
URL, the method (GET/POST/PUT/...), the headers, the cookies, query string parameters,
the body (form, JSON, multipart), uploaded files, the client's IP...

In HIX, the request is represented internally with a `THixRequest` object, but the
**idiomatic** way to read it inside a controller is not to access the object directly:
it's to use the `U*` helpers.

> ✨ **Golden rule**: inside a controller, **always** use the `U*` helpers to read any
> request data. You don't need (and shouldn't) capture `oReq` in the codeblock — the
> dispatcher makes the request of the current thread automatically available to the
> helpers.

```clipper
// CORRECT - use U* helpers
oSrv:AddRouteGet( "user", "/user/:id", {|| USendJson( { "id" => UParam("id") } ) } )

// INCORRECT - oReq is not available in the closure
oSrv:AddRouteGet( "user", "/user/:id", {|oReq| oReq:Respond( {=>}, 200, "json" ) } )
```

---

## Anatomy of an HTTP request

```
POST /customer/update?lang=es HTTP/1.1           ← method + path + query + version
Host: app.example.com                            ← headers
Content-Type: application/x-www-form-urlencoded  ←
Cookie: session_id=abc123; pref=dark             ←
X-Requested-With: XMLHttpRequest                 ←
Content-Length: 42                               ←
                                                 ← blank line = end of headers
first=Carles&last=Aubia&age=42                   ← body
```

Each of these pieces has a corresponding helper:

| Request part | Helper |
|---|---|
| Method (`POST`) | `UMethod()` |
| Path (`/customer/update`) | `UPath()` |
| Raw query string (`lang=es`) | `UQuery()` |
| Header (`Content-Type`) | `UHeader( "content-type" )` |
| Cookie (`session_id`) | `UCookie( "session_id" )` |
| Raw body | `UBody()` |
| Parsed body (form/JSON) | `UPost( "first" )` / `UJson()` |

---

## 1. Request line

### HTTP method

```clipper
UMethod()           // -> "GET", "POST", "PUT", "DELETE", "PATCH"
UIsGet()            // -> .T. if GET
UIsPost()           // -> .T. if POST
```

Useful for actions that accept multiple methods on the same route:

```clipper
oSrv:AddRoute( "form", "/contact", {||
   IF UIsPost()
      _ProcessForm()
   ELSE
      USendView( "contact.view.html" )
   ENDIF
}, "GET,POST" )
```

### Path and query string

```clipper
UPath()             // -> "/customer/update"
UQuery()            // -> "lang=es&page=2"     (raw, unparsed)
```

`UPath()` returns the URL **without** the query string. To read the query, use `UGet`.

### Scheme, host and port

```clipper
UScheme()           // -> "http" / "https"
UIsHttps()          // -> .T. / .F.
UHost()             // -> "app.example.com"   (Host header)
UPort()             // -> 443
UIP()               // -> "192.168.1.10" (respects X-Forwarded-For if mode=proxied)
```

---

## 2. Route variables - `UParam`

When a route declares variable segments with `:name`, you capture the value with
`UParam`.

```clipper
oSrv:AddRouteGet( "user.show", "/users/:id", {||
   LOCAL nId := Val( UParam( "id" ) )
   USendJson( _UserRepoFind( nId ) )
} )
```

| Form | Behavior |
|---|---|
| `UParam( cKey )` | Reads the variable; if it doesn't exist **raises error 400** |
| `UParam( cKey, xDef )` | Reads with a default value if it doesn't exist |
| `UParam( 1 )` | Captures from the wildcard `*` (equivalent to `UParam("_1")`) |
| `UParam()` | Hash with all route variables |

```clipper
// Route: /products/:id([0-9]+)/edit
nId := Val( UParam( "id", "0" ) )         // with safe default

// Route: /docs/:section!  (optional)
cSection := UParam( "section", "intro" )

// Route: /static/*
cFile := UParam( 1 )                       // equivalent to UParam("_1")
```

> 📖 Complete URL patterns in [Routes](../routes/routes.md).

---

## 3. Query string - `UGet`

Reads parameters from the query string (`?key=value&...`).

```clipper
// URL: /search?q=carles&page=2&limit=20

cQ     := UGet( "q" )                     // "carles"
nPage  := Val( UGet( "page",  "1"  ) )    // 2
nLimit := Val( UGet( "limit", "20" ) )    // 20

// Without argument -> full hash
hAll := UGet()                            // { "q"=>"carles", "page"=>"2", "limit"=>"20" }
```

Always returns **string**. For integers, convert with `Val()`.

### Validate query string in bulk

When there are multiple variables, validate with `UValidateGet` or `UValidateParams`
(query + route variables merged).

```clipper
oVal := UValidateParams( { ;
   "id"   => { "required|number|min:0", "Id"   }, ;
   "lang" => { "in:es,en,ca",           "Lang" } ;
} )
IF ! oVal:Make()
   RETU URedirect( URoute( 'home' ) )
ENDIF
nId   := oVal:Get( "id" )
cLang := oVal:Get( "lang" )
```

---

## 4. POST body

### HTML forms - `UPost`

When the client sends `application/x-www-form-urlencoded` or `multipart/form-data`:

```clipper
// POST /login   first=Carles&password=secret

cUser := UPost( "username" )
cPass := UPost( "password" )

// With default
cRole := UPost( "role", "viewer" )

// Full hash
hAll := UPost()
```

`UPost` also reads from the body if it arrives as JSON (auto-detects the `Content-Type`).

### Raw JSON body - `UJson`

When the client sends `Content-Type: application/json`:

```clipper
// POST /api/users  Content-Type: application/json
// Body: { "name": "Carles", "email": "x@y.com", "tags": ["admin","editor"] }

LOCAL hData := UJson()

IF hData == NIL
   RETURN USendError( 400, "Invalid JSON" )
ENDIF

cName := hb_HGetDef( hData, "name", "" )
aTags := hb_HGetDef( hData, "tags", {} )
```

`UJson()` returns a hash, an array, or `NIL` if the body is not valid JSON.

### Raw body - `UBody`

For special integrations (signed webhooks, binary payloads, XML...):

```clipper
LOCAL cRaw  := UBody()
LOCAL cSig  := UHeader( "X-Signature" )

IF ! _VerifyHmac( cRaw, cSig, cSecret )
   RETURN USendError( 401, "Invalid signature" )
ENDIF

_ProcessWebhook( cRaw )
```

### Body size and type

```clipper
UContentType()      // "application/json"
UContentLength()    // 42 (bytes)
UIsJson()           // .T. if Content-Type is application/json
UIsForm()           // .T. if application/x-www-form-urlencoded
UIsMultipart()      // .T. if multipart/form-data
```

---

## 5. Headers - `UHeader`

**Case-insensitive** reading of any HTTP header.

```clipper
cAuth   := UHeader( "Authorization", "" )         // "Bearer abc123"
cAccept := UHeader( "Accept",        "" )         // "application/json"
cUA     := UHeader( "User-Agent",    "" )

// Content negotiation
UWantsJson()        // .T. if client prefers JSON (Accept or AJAX)
UIsAjax()           // .T. if X-Requested-With: XMLHttpRequest
```

Typical pattern to respond with JSON or HTML depending on the client:

```clipper
IF UWantsJson() .OR. UIsAjax()
   USendJson( { "error" => "Not authenticated" }, 401 )
ELSE
   URedirect( "/login" )
ENDIF
```

---

## 6. Cookies - `UCookie`

```clipper
cSid   := UCookie( "session_id", "" )
cTheme := UCookie( "pref_theme", "light" )
```

Cookies are parsed **only once** and cached in the request (lazy). Calling `UCookie`
repeatedly does not incur a penalty.

> 📖 How to write cookies in the response (`USetCookie`) in
> [Response > Cookies](../response/cookies.md).

---

## 7. Multipart uploads - `UFiles`

When a form uploads files with `enctype="multipart/form-data"`:

```clipper
LOCAL aFiles := UFiles()
LOCAL hFile

FOR EACH hFile IN aFiles
   // hFile["name"]  -> name of the form field
   // hFile["data"]  -> binary content
   // hFile["mime"]  -> Content-Type of the file
   // hFile["size"]  -> size in bytes

   IF hFile["size"] > 5 * 1024 * 1024
      RETURN USendError( 413, "File too large" )
   ENDIF

   hb_MemoWrit( "uploads/" + hFile["name"], hFile["data"] )
NEXT
```

Text fields from the same form are read with normal `UPost`.

---

## 8. Client and session data

### Client identity

```clipper
UIP()              // Real IP (respects X-Forwarded-For in proxy mode)
UHost()            // Host header
UScheme()          // "http" / "https"
UIsHttps()         // .T. if the connection is secure
```

### Session and authenticated user

When session and/or authentication middleware is active:

```clipper
// Session
cUser := USession( "user" )                  // value or NIL
USession():Set( "role", "admin" )
USession():Save()

// Authenticated user (HIX_MwAuth middleware)
hUser := UAuthUser()                          // full user hash
cMail := UAuthUser( "email", "" )

IF ! UHasRole( "admin" )
   USendError( 403, "Admins only" )
   RETURN
ENDIF

// JWT (HixMwJwt middleware)
cSub := UJwt( "sub" )
IF ! UHasScope( "read:products" )
   USendError( 403, "Insufficient scope" )
   RETURN
ENDIF
```

> 📖 Details in [Sessions](../seguridad/sesiones.md), [Authentication](../seguridad/autenticacion.md)
> and [JWT](../seguridad/jwt.md).

---

## 9. Low-level access - `URequest` and `UContext`

For special cases, you can get the request object or the middleware context.

### `URequest()` - the `THixRequest` object

```clipper
LOCAL oReq := URequest()

// Direct access to hData (data shared between middlewares and controller)
hUser := hb_HGetDef( oReq:hData, "user", NIL )

// Raw properties
? oReq:cMethod, oReq:cPath, oReq:cQuery
```

Real example (Fenix `main.prg`):

```clipper
PROCEDURE Main(...)
   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Unknown", "roles" => {=>} } )
   LOCAL cName := hUser['name']

   // ... use hUser to build the view
RETU UView( 'main.view.html', cName, hUser )
```

### `UContext()` - the middleware context

When middleware is active, MWs pass data to the controller via `oCtx:hData["key"]`.
From the controller, you read them with `UContext()`:

```clipper
LOCAL oCtx := UContext()
LOCAL hJwt := oCtx:hData[ "jwt" ]              // payload set by HixMwJwt
LOCAL cSid := oCtx:hData[ "_sid" ]             // SID set by HixMwSession
```

In most cases, you don't need to touch `oCtx` directly: the `USession()`, `UJwt()`,
`UAuthUser()` helpers already read from it.

---

## 10. Request validation

Once the data is collected, the next step is to **validate** it with the built-in
validator.

| Helper | Data source |
|---|---|
| `UValidate( hRules )` | POST (form or JSON) |
| `UValidatePost( hRules )` | Explicit POST |
| `UValidateGet( hRules )` | Query string |
| `UValidateParams( hRules )` | Query string + route variables |
| `UValidateJson( hRules )` | Explicit JSON body |
| `UValidateOrFail( hRules )` | POST - auto-responds 422 if it fails and returns `NIL` |

Typical **PRG** (Post / Redirect / Get) pattern for web forms:

```clipper
oVal := UValidatePost( { ;
   "username" => { "required|min:3|max:30", "Username", "" }, ;
   "password" => { "required|min:4",        "Password", "" }  ;
} )

IF ! oVal:Make()
   UFlash( "login" ):Set( { ;
      "error" => oVal:GetFirstError(),  ;
      "user"  => oVal:Get( "username" ) ;
   } )
   URedirect( "/login" )
   RETURN
ENDIF

// Validated data available via oVal:Get( cKey ) or oVal:DataFields()
```

Typical pattern for JSON APIs:

```clipper
oVal := UValidateOrFail( {                  ;
   "name"  => "required|string|max:100",    ;
   "email" => "required|string|email",      ;
   "age"   => "required|integer|min:18"     ;
} )
IF oVal == NIL ; RETURN NIL ; ENDIF        // already responded 422

USendJson( _UserCreate( oVal:DataFields() ), 201 )
```

> 📖 Rules, modifiers, and advanced cases in [Validator](validator.md).

---

## 11. Quick helper reference

### Reading the request

```
UMethod()            UPath()            UQuery()
UGet(k,d)            UPost(k,d)         UParam(k,d)
UHeader(k,d)         UCookie(k,d)       UBody()
UJson()              UContentType()     UContentLength()
UFiles()             URequest()         UContext()
```

### Detect request type

```
UIsGet()   UIsPost()   UIsAjax()   UIsHttps()
UIsJson()  UIsForm()   UIsMultipart()   UWantsJson()
UScheme()  UIP()       UHost()          UPort()
```

### Validate input

```
UValidate(h)        UValidatePost(h)   UValidateGet(h)
UValidateParams(h)  UValidateJson(h)   UValidateOrFail(h)
UIsMail(s)  UIsNumeric(v)  UIsInteger(v)  UIsUrl(s)  UIsIp(s)
```

### Identity / session

```
USession()  USession(k)  USession(k,d)
UAuthUser(k,d)  UCurrentUser()  UHasRole(r,op)  UGetRoles()
UJwt(k,d)   UHasScope(s)
```

---

## Anti-patterns - what to avoid

### ❌ Capturing `oReq` in the codeblock

```clipper
// NO - oReq is not in the closure
oSrv:AddRouteGet( "x", "/x", {|oReq| oReq:Respond( {=>}, 200, "json" ) } )

// YES - use U* helpers
oSrv:AddRouteGet( "x", "/x", {|| USendJson( {=>} ) } )
```

### ❌ Mixing manual reading and validation

```clipper
// NO - verbose, inconsistent 400 errors
cName := UPost( "name", "" )
IF Empty( cName ) ; USendError( 422, "name required" ) ; RETURN ; ENDIF
IF Len( cName ) > 100 ; USendError( 422, "name too long" ) ; RETURN ; ENDIF

// YES - declarative, grouped errors, standard syntax
oVal := UValidateOrFail( { "name" => "required|string|max:100" } )
IF oVal == NIL ; RETURN NIL ; ENDIF
cName := oVal:Get( "name" )
```

### ❌ Comparing strings with `!=`

Harbour uses `SET EXACT OFF` by default — `!=` compares up to the length of the
shorter string. Always use `==`.

```clipper
IF UPath() != "/login"       // ⚠️ false match with "/lo"
IF UPath() == "/login"       // ✅ correct
```

### ❌ Converting everything to `Val()` without default

```clipper
// NO - Val("") is 0 but may hide bugs if the parameter is mandatory
nId := Val( UParam( "id" ) )

// YES - with explicit default or validation
nId := Val( UParam( "id", "0" ) )

// Or better:
oVal := UValidateParams( { "id" => "required|number|min:0" } )
```

