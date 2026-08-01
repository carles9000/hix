# 🎮 Controllers

## 📂 `<root>/controllers`

A **controller** in HIX is the unit of code that receives an HTTP request, processes it,
and returns a response. It is the bridge between a **route** (the URL) and the **business logic**
(models, database, external services).

While a route says *"when `GET /customer/:id` arrives, do something"*, the
controller is the *"something"* - the actual code that executes that intent.

> A controller in HIX **is not a mandatory class**. It can range from a single-line
> codeblock to a `.prg` file with classes and methods to implement a complete
> CRUD. Use the format that best fits the size of the endpoint.

---

## Request lifecycle

When an HTTP request arrives, HIX executes this sequence:

```
HTTP Request
   │
   ▼
┌──────────────────┐
│      Router      │  searches for route matching URL + method
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│    Middleware    │  chain of MWs (auth, CORS, RateLimit, Session...)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│    Controller    │  ← you are here
│  ─────────────   │
│  1. Data         │  UGet, UPost, UParam, UHeader, UCookie, UJson...
│     collection   │
│  2. Validation   │  UValidate, UValidatePost, UValidateParams...
│  3. Processing   │  models (TCustomers, TStates...), business logic
│  4. Output       │  UView, USendJson, URedirect, USendError
└────────┬─────────┘
         │
         ▼
HTTP Response
```

The controller is **stage 3**: the code that executes once the route has
been identified and middlewares have given the green light.

---

## How a controller is invoked from a route

The third parameter of `AddRouteXxx` (`bAction`) defines **which controller** executes.
HIX accepts several formats:

### 1. Inline codeblock

For trivial endpoints.

```clipper
oSrv:AddRouteGet( "ping", "/ping", {|| USendJson( { "ok" => .T. } ) } )
```

### 2. `.prg` file with `Main()`

Relative path to the web root (`www/`). HIX compiles on the fly and executes `Main()`.

```clipper
oSrv:AddRouteGet( "main", "/main", "controllers/main.prg" )
```

In the route configuration file inside `/routes`
```json
{ "name": "logout", "url": "/logout", "action": "controllers/logout.prg" }
```

### 3. Class method - `method@class.prg`

More professional variant to group actions of the same resource (CRUD).

```json
[
   { "name": "customer.search", "url": "/customer/search",     "method": "GET",  "action": "search@customer.prg" },
   { "name": "customer.show",   "url": "/customer/:id",        "method": "GET",  "action": "show@customer.prg"   },
   { "name": "customer.edit",   "url": "/customer/:id/edit",   "method": "GET",  "action": "edit@customer.prg"   },
   { "name": "customer.update", "url": "/customer/update",     "method": "POST", "action": "update@customer.prg" },
   { "name": "customer.create", "url": "/customer/create",     "method": "GET",  "action": "create@customer.prg" },
   { "name": "customer.store",  "url": "/customer",            "method": "POST", "action": "store@customer.prg"  },
   { "name": "customer.delete", "url": "/customer/delete",     "method": "POST", "action": "delete@customer.prg" }
]
```

> 📖 Complete route patterns in [Routes](../routes/routes.md).

---

## Simple format - `Main()`

A `.prg` file with a `Main()` function that executes the entire action. Real example:
the **login**.

### `controllers/login.prg` - display the form

```clipper
/*-----------------------------------------------------------
  File ......: login.prg
  Description: GET /login - loads flash error/username set by
               auth.prg on failed login.
  Usage      : GET /login
 -----------------------------------------------------------*/

FUNCTION Main()
   LOCAL oFlash
   LOCAL cError
   LOCAL cUser

   oFlash := UFlash( "login" )
   cError := oFlash:Get( "error" )
   cUser  := oFlash:Get( "user"  )
   oFlash:Save()

RETURN UView( "sys/login.view.html", cUser, cError )
```

### `controllers/auth.prg` - process the POST

Pattern **PRG** (Post / Redirect / Get): a POST never returns HTML, always
redirects. This prevents pressing F5 from re-submitting the form.

```clipper
/*-----------------------------------------------------------
  File ......: auth.prg
  Description: Login controller - validates credentials and
               starts a session.
  Usage      : POST /login  (form fields: username, password)
 -----------------------------------------------------------*/

#include "hbclass.ch"

FUNCTION Main()
   LOCAL oVal, oSess, hUser

   // 1. Validate input
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

   // 2. Search user in the model
   hUser := ModelUser( oVal:Get( "username" ), oVal:Get( "password" ) )

   // 3. Response - always redirect
   IF ValType( hUser ) == "H"
      oSess := USession()
      oSess:Set( UMwConfig( "auth", "session_user_key" ), hUser )
      oSess:Save()
      URedirect( UMwConfig( "auth", "redirect_accept" ) )
   ELSE
      UFlash( "login" ):Set( { ;
         "error" => "Invalid username or password", ;
         "user"  => oVal:Get( "username" )              ;
      } )
      URedirect( UMwConfig( "auth", "redirect_login" ) )
   ENDIF

RETURN

#include '/models/modeluser.prg'
```

### `controllers/logout.prg` - destroy session

```clipper
PROCEDURE Main(...)
   LOCAL oSess := USession()
   oSess:Destroy()
   URedirect( "/login" )
RETURN
```

> 💡 **PRG Pattern**: after a `POST` never return HTML - always `URedirect` with
> flash messages. In JSON APIs it is different: there you respond with JSON directly.

---

## CRUD format - `method@class.prg`

When a resource has multiple actions (search, edit, create, delete, etc.), they are all
grouped in a class. HIX calls the method indicated in the route.

Typical header with the routing table for the resource:

```clipper
/*
 | Route Name      | URL              | Method | Function         | Description    |
 | --------------- | ---------------- | ------ | ---------------- | -------------- |
 | customer.search | /customer/search | GET    | search@customer  | Search         |
 | customer.show   | /customer/:id    | GET    | show@customer    | Show one       |
 | customer.edit   | /customer/:id/edit | GET  | edit@customer    | Edit form      |
 | customer.update | /customer/update | POST   | update@customer  | Update         |
 | customer.create | /customer/create | GET    | create@customer  | Create form    |
 | customer.store  | /customer        | POST   | store@customer   | Store new      |
 | customer.delete | /customer/delete | POST   | delete@customer  | Delete         |
*/

#include 'hbclass.ch'

CLASS Customer

   METHOD New()        CONSTRUCTOR
   METHOD End()

   METHOD Search()
   METHOD Show()
   METHOD Edit()
   METHOD Update()
   METHOD Create()
   METHOD Store()
   METHOD Delete()
   METHOD Destroy()

ENDCLASS

METHOD New() CLASS Customer
RETU Self

METHOD End() CLASS Customer
RETU Self
```

---

## 1. Data collection from the request

Inside the controller you use the `U*` helpers to read any request data
without needing to pass `oReq`: the dispatcher leaves it in the current thread.

| Source | Helper | Example |
|---|---|---|
| Route variable `:var` | `UParam(k, def)` | `UParam("id")` |
| Query string `?k=v` | `UGet(k, def)` | `UGet("page", "1")` |
| POST body (form or JSON) | `UPost(k, def)` | `UPost("first")` |
| Parsed JSON body | `UJson()` | `hData := UJson()` |
| Raw body | `UBody()` | `cRaw := UBody()` |
| HTTP header | `UHeader(k, def)` | `UHeader("X-Api-Key")` |
| Cookie | `UCookie(name, def)` | `UCookie("auth_token")` |
| Multipart uploads | `UFiles()` | `aFiles := UFiles()` |
| Session | `USession(k, def)` | `USession("user")` |
| Signed resource ID | `UGetResource()` | `cId := UGetResource()` |
| HTTP method | `UMethod()` | `IF UMethod() == "POST"` |
| Request URL | `UPath()`, `UQuery()` | |
| Client IP / host | `UIP()`, `UHost()` | |

Example from the Fenix `main.prg` controller, which reads the user from the session via
`URequest():hData`:

```clipper
PROCEDURE Main(...)
   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Unknown", "roles" => {=>} } )
   LOCAL cName := hUser['name']
   LOCAL cKey, cRoles := ''

   FOR EACH cKey IN hUser["roles"]
      cRoles += cKey:__enumKey() + " "
   NEXT

   IF Empty( cRoles ) ; cRoles := "(none)" ; ENDIF

RETU UView( 'main.view.html', cName, hUser, cRoles )
```

> 📖 Complete catalog of helpers in
> [U* Helper Map](../../programacion/mapa-helpers.md).

---

## 2. Validation

Before processing any data, you must validate it. HIX includes an integrated validator
with declarative syntax and extended format `{ "rules", "Label", "default" }`.

### Extended rule format

```clipper
oVal := UValidatePost( { ;
   "username" => { "required|min:3|max:30", "Username", "" }, ;
   "password" => { "required|min:4",        "Password", "" }  ;
} )
```

- `"required|min:3|max:30"` - rule string separated by `|`
- `"Username"` - human label used in error messages
- `""` - default value if not provided

### Typical pattern - Validate + Flash + Redirect

```clipper
METHOD Update() CLASS Customer

   LOCAL cId := UGetResource()        // Signed ID of the record
   LOCAL oVal, nId, cError, lSuccess
   LOCAL oCustomers

   // Validate the resource_id (single-field validator)
   IF Empty( cId )
      RETU URedirect( URoute( 'main' ) )
   ENDIF

   oVal := UValidatorOne( 'Id', cId, "required|number|min:0" )
   IF oVal:Fails()
      RETU URedirect( URoute( 'customer.search' ) )
   ENDIF
   nId := oVal:Get()

   // Validate form fields
   oVal := UValidatePost( {                                    ;
      "_deleted" => "required|logic|resume",                   ;
      "first"    => "required|string|max:20|field",            ;
      "last"     => "required|string|max:20|field",            ;
      "street"   => "required|string|max:30|field",            ;
      "city"     => "required|string|max:30|field",            ;
      "state"    => "required|string|max:2|field",             ;
      "zip"      => "required|string|max:10|field",            ;
      "hiredate" => "required|date|field",                     ;
      "married"  => "logic|field",                             ;
      "age"      => "required|numeric|max:70|field",           ;
      "notes"    => "string|escapedfield"                      ;
   }, { 'dummy' => 'upper|trim', 'first' => 'lower' } )

   IF ! oVal:Make()
      UFlash( "customer" ):Set( {                ;
         "type"    => 'danger',                  ;
         "message" => 'Validation error',        ;
         "errors"  => oVal:GetErrors(),          ;
         "input"   => oVal:Resume()              ;
      } )
      RETU URedirect( URoute( 'customer.edit', nId ) )
   ENDIF

   // ... continues with processing
```

### Useful rule modifiers

| Suffix | Effect |
|---|---|
| `\|field` | Include the field in `oVal:DataFields()` (hash ready for insert/update) |
| `\|escapedfield` | Same + escapes HTML of the value |
| `\|resume` | Include it in `oVal:Resume()` (to fill the form if there is an error) |

### Key methods of `oVal`

| Method | Purpose |
|---|---|
| `Make()` | Runs validation; returns `.T./.F.` |
| `Fails()` | `.T.` if failed |
| `Get(k)` | Validated value of a field |
| `GetErrors()` | Hash with errors per field |
| `GetFirstError()` | First error as string (useful for flash on logins) |
| `DataFields()` | Hash with fields marked `\|field` (for `Insert/Update`) |
| `Resume()` | Hash with all fields (to fill the form on return) |

> 📖 Complete rules, sanitization, and advanced cases in [Validator](validator.md).

---

## 3. Processing - business logic

The controller orchestrates, not implements. It calls **models** (`TCustomers`, `TStates`,
`ModelUser`, etc.) that encapsulate all data logic.

```clipper
METHOD Show() CLASS Customer

   LOCAL oVal, oCustomers, oStates, oFlash
   LOCAL hRow      := {=>}
   LOCAL hMessage  := {=>}
   LOCAL lFound

   // 1. Validate the id
   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id", "" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( 'id' ) == 0
      UFlash( "customer" ):Set( {                ;
         "errors"  => oVal:GetErrors(),          ;
         "message" => "Validation error",        ;
         "input"   => oVal:Resume()              ;
      } )
      RETURN URedirect( URoute( 'customer.search' ) )
   ENDIF

   // 2. Search in the model
   oCustomers := TCustomers()
   lFound := oCustomers:GetRecno( oVal:Get( 'id' ), @hRow, NIL, .T. )

   IF lFound
      // Enrich with related data
      oStates := TStates()
      oStates:Seek( hRow[ 'state' ], NIL, 'code' )
      hRow[ 'state_txt' ] := oStates:FieldGet( 'name' )

      // Retrieve flash from previous operations
      oFlash := UFlash( 'customer' )
      hMessage[ 'type'    ] := oFlash:Get( 'type'    )
      hMessage[ 'message' ] := oFlash:Get( 'message' )
   ELSE
      hRow := oCustomers:Blank( .T. )
      hRow[ 'state_txt' ] := ''
   ENDIF

   // 3. Output - render view
RETU UView( 'masters/customer/show.html', lFound, hRow, hMessage )
```

Best practices:

- **Thin controller, fat model.** Persistence and complex rules live in the
  model (`TCustomers:Insert`, `:Update`, `:Delete`, ...), not in the controller.
- **One action = one HTTP intent.** If a method does three things, they usually are
  three distinct actions.
- **Errors with `URedirect` + flash** in HTML forms; **`USendError(n, txt)`
  + `RETURN`** in JSON APIs.
- **Load models at the end**: `#include 'models/tcustomers.prg'` at the close of the
  file so they compile together with the controller.

---

## 4. Output - send the response

The final step of the controller sends the response to the client.

### Strategy by endpoint type

| Endpoint type | Pattern |
|---|---|
| GET that renders HTML | `RETURN UView( "path/view.html", arg1, arg2, ... )` |
| POST that modifies data | `URedirect( URoute( "destination" ) )` + flash |
| REST API | `USendJson( hash [, nStatus] )` |
| DELETE success (API) | `USendEmpty()` (204) |
| HTTP error (API) | `USendError( nStatus, cDetail )` |

### Views - `UView`

`UView` renders a template `.html` with the Mambo engine. Positional arguments
are passed as-is to the template (declared with `@args`).

```clipper
// GET /customer/:id/edit
METHOD Edit() CLASS Customer

   LOCAL oVal, oCustomers, oStates, lFound, oFlash
   LOCAL aStates  := {}
   LOCAL hMessage := {=>}
   LOCAL hRow     := {=>}
   LOCAL hErrors  := {=>}
   LOCAL hInput

   oVal := UValidateParams( { "id" => { "required|number|min:0", "Id" } } )
   IF ! oVal:Make()
      RETU URedirect( URoute( 'customer.search' ) )
   ENDIF

   // Retrieve flash if we come from a POST with error
   oFlash := UFlash( 'customer' )
   hMessage[ 'type'    ] := oFlash:Get( 'type'    )
   hMessage[ 'message' ] := oFlash:Get( 'message' )
   hInput                := oFlash:Get( 'input'   )
   hErrors               := oFlash:Get( 'errors', {=>} )

   // Load combos
   oStates := TStates()
   aStates := oStates:LoadAll()

   // If there is input (we come from an Update with error), repaint the form with the data
   IF ! Empty( hInput )
      RETU UView( 'masters/customer/edit.html', 'edit', .T., hInput, aStates, hMessage, hErrors )
   ENDIF

   oCustomers := TCustomers()
   lFound := oCustomers:GetRecno( oVal:Get( 'id' ), @hRow, NIL, .T. )

   IF ! lFound
      hRow := oCustomers:Blank( .T. )
   ENDIF

RETU UView( 'masters/customer/edit.html', 'edit', lFound, hRow, aStates, hMessage, hErrors )
```

### Redirects with `URoute`

Always use `URoute( cName, ... )` instead of literals - so if the URL changes
you only touch it in the route definition.

```clipper
URedirect( URoute( 'customer.show', nId ) )       // -> /customer/42
URedirect( URoute( 'customer.search' ) )          // -> /customer/search
```

### Flash messages

Messages that are stored in the session and consumed only once on the next request.
Essential for maintaining messages across a `URedirect`.

```clipper
// After a successful POST
UFlash( "customer" ):Set( { ;
   "type"    => 'success',                                        ;
   "message" => 'Customer ' + LTrim( Str( nId ) ) + ' was updated!' ;
} )
RETU URedirect( URoute( 'customer.show', nId ) )
```

### JSON APIs

When the endpoint is a REST API instead of a web form:

```clipper
// Simple JSON response
USendJson( { "id" => 42, "name" => "Carles" } )

// With custom status
USendJson( { "id" => nNewId }, 201 )

// Error
USendError( 404, "Product not found" )

// DELETE success
USendEmpty()
```

### Chunked streaming (SSE, downloads)

```clipper
USendStreamStart( "text/event-stream", 200, ;
   { "Cache-Control" => "no-cache", "X-Accel-Buffering" => "no" } )

DO WHILE lRunning
   USendChunk( "data: " + hb_jsonEncode( hMsg ) + hb_eol() + hb_eol() )
   hb_idleSleep( 1 )
ENDDO

USendStreamEnd()
```

---

## Complete pattern - CRUD Customer

Combines everything: validation, model, flash, redirect, views. Real implementation of
the **`Store`** method (create) from Fenix:

```clipper
METHOD Store() CLASS Customer

   LOCAL oVal, oCustomers, oStates, cError, lSuccess, nRecno

   // 1. Validation
   oVal := UValidatePost( {                                ;
      "first"    => "required|string|max:20|field",        ;
      "last"     => "required|string|max:20|field",        ;
      "street"   => "required|string|max:30|field",        ;
      "city"     => "required|string|max:30|field",        ;
      "state"    => "required|string|max:2|field",         ;
      "zip"      => "required|string|max:10|field",        ;
      "hiredate" => "required|date|field",                 ;
      "married"  => "logic|field",                         ;
      "age"      => "required|numeric|max:70|field",       ;
      "notes"    => "string|escapedfield"                  ;
   }, { 'first' => 'lower' } )

   IF ! oVal:Make()
      UFlash( "customer" ):Set( {              ;
         "type"    => 'danger',                ;
         "message" => 'Validation error',      ;
         "errors"  => oVal:GetErrors(),        ;
         "input"   => oVal:Resume()            ;
      } )
      RETU URedirect( URoute( 'customer.create' ) )
   ENDIF

   // 2. Processing - insert in the model
   oCustomers := TCustomers()
   lSuccess := oCustomers:Insert( oVal:DataFields(), @cError, @nRecno )

   // 3. Output - redirect based on result
   IF lSuccess
      UFlash( "customer" ):Set( {                                            ;
         "type"    => 'success',                                             ;
         "message" => 'Customer ' + LTrim( Str( nRecno ) ) + ' was created!' ;
      } )
      RETU URedirect( URoute( 'customer.show', nRecno ) )
   ENDIF

   UFlash( "customer" ):Set( {              ;
      "type"    => 'danger',                ;
      "message" => cError,                  ;
      "errors"  => {=>},                    ;
      "input"   => oVal:Resume()            ;
   } )
RETU URedirect( URoute( 'customer.create' ) )
```

And at the end of the file, the models that the controller uses:

```clipper
#include 'models/tcustomers.prg'
#include 'models/tstates.prg'
```

---

## Best practices

1. **One file per resource.** `customer.prg` groups all actions for the
   `customer` resource. RESTful method names: `Search`, `Show`, `Edit`, `Update`,
   `Create`, `Store`, `Delete`.

2. **PRG pattern (Post / Redirect / Get).** A POST never returns HTML - always
   redirects (success or failure). This prevents re-submissions when pressing F5.

3. **Flash + URoute to maintain state.** Messages, errors, and input are passed
   between requests with `UFlash(formId):Set({...})` before the `URedirect( URoute(...) )`.

4. **Signed resource IDs.** In edit/delete forms use `UGetResource()`
   instead of passing IDs in the clear - prevents manual HTML modification.

5. **`LOCAL` at the beginning.** Harbour requires all `LOCAL` declarations before
   any executable statement. Do not declare LOCAL inside IFs.

6. **Validate first, process later.** If validation fails, flash + redirect
   (web) or `USendJson(...,422)` (API). Abort as soon as possible.

7. **Routing table in the controller header.** The comment block at the
   beginning of the class documents all resource URLs at a glance.

8. **Logic out of the controller.** The `Txxx` classes (models) implement
   `:Insert`, `:Update`, `:Delete`, `:GetRecno`, `:Blank`, etc. The controller only
   orchestrates them.

9. **Centralize URLs and redirects in configuration.** `UMwConfig( "auth", "redirect_login" )`
   lets you change destinations without touching code.

10. **`#include 'models/xxx.prg'`** at the end of the controller so the models compile
    together with the file.
