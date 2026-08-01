# ✔️ HIX Validator - Complete tutorial

The **HIX** validator allows you to validate and clean HTTP input data in three ordered phases:
**cast** (type conversion), **validation** (rules), and **sanitization** (cleanup transformations).
Everything chains together with a rule syntax in strings separated by `|`.

---

## 1. Basic concept

```clipper
LOCAL oVal := UValidateOrFail( {
   "name"  => "required|string|max:100",
   "email" => "required|string|email",
   "age"   => "required|integer|min:18"
} )
IF oVal == NIL ; RETURN NIL ; ENDIF   // already responded 422

cName  := oVal:Get( "name" )
cEmail := oVal:Get( "email" )
nAge   := oVal:Get( "age" )           // type N, not string
```

`UValidateOrFail` is the shortest path: it executes `Make()`, and if there are errors it automatically
sends a JSON 422 and returns `NIL`. If it passes, it returns the validator object with values
already converted to the correct type.

---

## 2. Input sources

Each helper captures input data from a different source of the current request.

| Function | Primary source | Route params `:var` |
|---|---|---|
| `UValidatePost(hRules)` | POST body: form-urlencoded first, JSON as fallback | included |
| `UValidateGet(hRules)` | Query string (`?key=val`) | included |
| `UValidateJson(hRules)` | JSON body only | included |
| `UValidateOrFail(hRules)` | POST body — runs Make() and responds 422 if it fails | included |
| `UValidateParams(hRules)` | Alias for `UValidateGet` (backward compatibility) | included |

All accept a second optional parameter `hSanitate` (see section 6).

All helpers always merge route variables (`:id`, `:slug`...) into `hInput`
after reading the primary source. If the same key exists in both sources a
500 error is raised to surface the naming conflict early.

### UValidatePost vs UValidateJson

`UValidatePost` auto-detects the format: tries form-urlencoded first and, if
empty, falls back to JSON. It is the universal helper for endpoints that accept
both formats.

`UValidateJson` reads the body as JSON exclusively. If the body is not valid
JSON, `hInput` is left empty and any `required` fields fail with a normal 422.
Use it when the endpoint is a pure API that requires JSON.

```clipper
// Endpoint that accepts form AND json
oVal := UValidatePost( hRules )

// Pure API — JSON only
oVal := UValidateJson( hRules )
IF ! oVal:Make()
   USendJson( { "errors" => oVal:GetErrors() }, 422 )
   RETURN NIL
ENDIF
```

### UValidateGet — query string and route params

`UValidateGet` merges the query string with route variables into a single hash,
covering all GET endpoint scenarios in one call:

```clipper
// GET /products?page=2&q=book  (no :vars)
oVal := UValidateGet( { "page" => "optional|integer|min:1", "q" => "optional|string" } )

// GET /users/:id?expand=roles  (query + :id combined)
oVal := UValidateGet( { "id" => "required|integer|positive", "expand" => "optional|string" } )

// POST /resource/:id with JSON body  (body + :id combined)
oVal := UValidatePost( { "id" => "required|integer", "name" => "required|string" } )
```

---

## 3. Complete flow with Make()

When you need to control the error response manually:

```clipper
FUNCTION _UpdateUser()
   LOCAL oVal, hData

   oVal := UValidatePost( {
      "name"  => "required|string|max:100",
      "email" => "required|string|email"
   } )

   IF ! oVal:Make()
      // option A - standard JSON response
      USendJson( { "errors" => oVal:GetErrors() }, 422 )
      RETURN NIL

      // option B - only the first error
      USendError( 422, oVal:GetFirstError() )
      RETURN NIL
   ENDIF

   hData := oVal:Validated()   // hash with all validated fields
   // ... save hData ...
   USendJson( { "ok" => .T. } )
RETURN NIL
```

---

## 4. Validation rules

Rules are written separated by `|` in a string. Order matters: rules are evaluated
from left to right and stop at the first error on the field.

### Presence

| Rule | Description |
|---|---|
| `required` | The field must exist and not be empty |
| `optional` | If the field is empty, it is omitted without error. Must come first |

```clipper
// Required field
"name" => "required|string"

// Optional field - only validates if provided
"nickname" => "optional|string|max:50"
```

### Types (also perform cast, see section 5)

| Rule | Description |
|---|---|
| `string` | Converts to string and does `AllTrim` |
| `integer` | Converts to integer; fails if not an integer number |
| `numeric` / `decimal` | Converts to number; accepts decimals |
| `boolean` / `bool` | Converts to logical `.T.`/`.F.` |
| `date` | Converts to Harbour date from `YYYY-MM-DD` |
| `positive` | The value must be `N > 0` |

### Length and range

| Rule | Applies to | Description |
|---|---|---|
| `min:N` | string: length >= N / number: value >= N | |
| `max:N` | string: length <= N / number: value <= N | |
| `minlen:N` | string | length >= N (independent of type) |
| `maxlen:N` | string | length <= N |
| `between:N,M` | string or number | between N and M (length or value) |

```clipper
"title"    => "required|string|min:3|max:200"
"price"    => "required|numeric|min:0|max:9999"
"score"    => "required|integer|between:1,10"
```

### Format

| Rule | Description |
|---|---|
| `email` | Valid email format |
| `url` | Starts with `http://` or `https://` |
| `ip` | Valid IPv4 (four octets 0-255) |
| `regex:PATTERN` | The value must match the Harbour regular expression |

```clipper
"email"    => "required|string|email"
"web"      => "optional|string|url"
"subnet"   => "required|ip"
"code"     => "required|regex:[A-Z]{3}[0-9]{4}"
```

### Lists

| Rule | Description |
|---|---|
| `in:a,b,c` | The value must be in the list |
| `notin:a,b,c` | The value must not be in the list |

```clipper
"role"     => "required|string|in:admin,editor,viewer"
"status"   => "required|string|notin:deleted,banned"
```

### Dates

| Rule | Description |
|---|---|
| `mindate:YYYY-MM-DD` | The date must be >= the indicated date |
| `maxdate:YYYY-MM-DD` | The date must be <= the indicated date |

```clipper
"birthday" => "required|date|maxdate:2010-01-01"
"start"    => "required|date|mindate:2026-01-01"
```

### Confirmation

| Rule | Description |
|---|---|
| `confirmed` | Looks for a `<field>_confirmation` field in the input and compares it |

```clipper
// The form must send "password" and "password_confirmation"
"password" => "required|string|min:8|confirmed"
```

### Rules with custom codeblock

When no standard rule fits, you can pass a codeblock directly:

```clipper
oVal := UValidatePost( {
   "username" => { "required|string",
                   "Username",   // label for the error message
                   "",           // default value
                   {|v| iif( _UserExists(v), "User already exists", .T. ) }
                 }
} )
```

The codeblock receives the value and must return:
- `.T.` if the validation passes
- `.F.` if it fails (generic message)
- `C` with the error message if it fails (custom message)

---

## 5. Type cast (phase 1)

Cast converts the value from HTTP string to the correct Harbour type **before** validating.
This means that after `Make()`, `oVal:Get("age")` returns an `N`, not a `C`.

| Cast rule | Conversion |
|---|---|
| `string` | `AllTrim( UStr(v) )` |
| `integer` | `Val(v)` truncated to integer |
| `numeric` / `decimal` | `Val(v)` with decimal point |
| `boolean` / `bool` | `"1","true","yes","on",".t."` → `.T.`; rest → `.F.` |
| `date` | `"YYYY-MM-DD"` or `"YYYY/MM/DD"` → Harbour date |

**Cast and validation can be combined**:

```clipper
// "integer" converts AND validates it is an integer
"qty"  => "required|integer|min:1|max:999"

// "boolean" converts; without required, an unchecked checkbox will be .F.
"active" => "boolean"
```

---

## 6. Sanitization (phase 3)

Sanitization runs **after** all validations have passed. It is defined in
the second parameter of the helper (`hSanitate`):

```clipper
oVal := UValidatePost(
   { "name" => "required|string", "bio" => "optional|string" },
   { "name" => "trim|upper",      "bio" => "trim|strip_tags" }
)
```

> **Note:** Sanitization tokens written inline in the rule string
> (`"required|string|trim|upper"`) are silently ignored by the engine.
> The only way to apply sanitization is through the `hSanitate` second
> parameter. The `string` cast applies `AllTrim()` internally, but
> `upper`/`lower`/etc. require `hSanitate`.

### Available transformations

| Rule | Description |
|---|---|
| `trim` | `AllTrim()` - removes spaces at the beginning and end |
| `ltrim` | `LTrim()` - only spaces on the left |
| `rtrim` | `RTrim()` - only spaces on the right |
| `upper` | `Upper()` |
| `lower` | `Lower()` |
| `strip_tags` | Removes HTML tags (`<tag>` → `""`) |
| `slug` | Converts to URL-safe slug: `"My Title"` → `"my-title"` |
| `nl2br` | Converts line breaks to `<br>` |
| `escape` | Encodes HTML characters (`<`, `>`, `&`, `"`) |
| `abs` | Absolute value of a number |
| `round:N` | Rounds a number to N decimal places |

```clipper
"title"   => "required|string|trim|slug"      // "My Article!" -> "my-article"
"content" => "required|string|trim|strip_tags"
"price"   => "required|numeric|abs|round:2"
"email"   => "required|string|trim|lower|email"
```

---

## 7. Special markers

### `field` and `escapedfield`

Mark fields that should be included in `oVal:DataFields()`. Useful for re-filling
HTML forms after a validation error.

```clipper
oVal := UValidatePost( {
   "name"  => "required|string|max:100|field",
   "email" => "required|string|email|escapedfield"   // HTML-encoded
} )

// If validation fails, the original data is available
hData := oVal:DataFields()  // { "name" => "Carles", "email" => "c&lt;a&gt;@..." }
```

### `resume`

Marks fields that should be included in `oVal:Resume()`. Used to re-fill forms
by returning the data (already cast) to the template even when there is an error.

```clipper
"name"  => "required|string|max:100|resume"
"email" => "required|string|email|resume"

// Resume includes the marked fields with the value already converted to the correct type.
// Without resume markers, Resume() returns the original untranslated input hash.
hResume := oVal:Resume()
```

---

## 8. Read the validated data

After a successful `Make()`:

| Method | Description |
|---|---|
| `oVal:Get(cKey)` | Value of a field; `NIL` if it does not exist |
| `oVal:Get(cKey, xDef)` | Value of a field with default |
| `oVal:Validated()` | Complete hash with all validated fields |
| `oVal:Validated(aFields)` | Hash filtered to the indicated fields |
| `oVal:DataFields()` | Hash of fields marked with `field`/`escapedfield` |
| `oVal:Resume()` | Hash for re-filling forms (see `resume` marker) |

```clipper
// Get individual fields
cName  := oVal:Get( "name" )
nAge   := oVal:Get( "age", 0 )

// Get all validated fields
hAll   := oVal:Validated()

// Get only the fields of interest
hSaved := oVal:Validated( { "name", "email", "age" } )
```

---

## 9. Handling errors

| Method | Returns | Description |
|---|---|---|
| `oVal:Passes()` | `L` | `.T.` if there are no errors |
| `oVal:Fails()` | `L` | `.T.` if there are any errors |
| `oVal:IsValid()` | `L` | Alias of `Passes()` |
| `oVal:GetErrors()` | `H` | Hash `{ "field" => "message" }` |
| `oVal:GetFirstError()` | `C` | Message of the first error |
| `oVal:GetErrorsJson()` | `C` | `GetErrors()` serialized as JSON |
| `oVal:GetErrorsTxt()` | `C` | HTML table with the errors |
| `oVal:SendErrors(nStatus)` | - | Responds JSON `{ errors }` with the indicated status |
| `oVal:Formatter()` | `H` | Hash `{ "success", "errors" }` ready for JSON |

```clipper
// Standard JSON error response
IF oVal:Fails()
   USendJson( oVal:Formatter(), 422 )
   RETURN NIL
ENDIF

// Only the first error (for simple responses)
IF oVal:Fails()
   USendError( 422, oVal:GetFirstError() )
   RETURN NIL
ENDIF

// Errors per field (for AJAX with per-field feedback)
IF oVal:Fails()
   USendJson( { "errors" => oVal:GetErrors() }, 422 )
   RETURN NIL
ENDIF
```

---

## 10. Labels and defaults on fields

The rule of a field can be an array of up to 4 elements:

```
{ "rules", "Label", defaultValue, codeblock }
```

```clipper
oVal := UValidatePost( {
   "name"  => { "required|string|max:100", "Full name" },
   "age"   => { "required|integer|min:18", "Age", 0 },
   "token" => { "required|string", "Token", NIL,
                {|v| iif( HIX_TokenValid(v, 3600), .T., "Token expired" ) }
              }
} )
```

- The second element is the label that appears in error messages.
- The third is the default value when the field does not exist in the input.
- The fourth is a custom validation codeblock.

---

## 11. Validate a single value

`UValidatorOne` validates a single value without needing to build a hash:

```clipper
oVal := UValidatorOne( "Email", cEmail, "required|string|email" )
IF oVal:Fails()
   USendError( 422, oVal:GetFirstError() )
   RETURN NIL
ENDIF
```

---

## 12. Add fields on the fly

You can enrich a validator after creating it with `Add()`:

```clipper
oVal := UValidatePost( { "name" => "required|string" } )
oVal:Add( { "extra" => "optional|integer" }, UGet("extra") )
oVal:Make()
```

---

## 13. Complete patterns

### API REST - create resource

```clipper
FUNCTION _ProductCreate()
   LOCAL oVal, hProd

   oVal := UValidateOrFail( {
      "name"        => { "required|string|max:200|trim",     "Name" },
      "price"       => { "required|numeric|min:0|round:2",   "Price" },
      "stock"       => { "required|integer|min:0",           "Stock" },
      "category_id" => { "required|integer|positive",        "Category" },
      "active"      => { "boolean",                          "Active" }
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF

   hProd := oVal:Validated( { "name", "price", "stock", "category_id", "active" } )
   // ... insert hProd in DB ...

   USendJson( { "id" => nNewId }, 201 )
RETURN NIL
```

### HTML form with re-fill

```clipper
FUNCTION _RegisterPost()
   LOCAL oVal

   oVal := UValidatePost( {
      "username" => "required|string|min:3|max:50|trim|lower|resume",
      "email"    => "required|string|email|trim|lower|resume",
      "password" => "required|string|min:8|confirmed"
   } )

   IF ! oVal:Make()
      // save flash with errors and form data
      LOCAL oFlash := UFlash( "register" )
      oFlash:Set( "errors",  oVal:GetErrors() )
      oFlash:Set( "data",    oVal:Resume() )
      oFlash:Save()
      URedirect( "/register" )
      RETURN NIL
   ENDIF

   // ... create user ...
   URedirect( "/dashboard" )
RETURN NIL
```

```clipper
FUNCTION _RegisterGet()
   LOCAL oFlash  := UFlash( "register" )
   LOCAL hErrors := oFlash:Get( "errors", {=>} )
   LOCAL hData   := oFlash:Get( "data",   {=>} )
   USendView( "auth/register.view.html", {
      "hErrors"   => hErrors,
      "cUsername" => hb_HGetDef( hData, "username", "" ),
      "cEmail"    => hb_HGetDef( hData, "email",    "" )
   } )
RETURN NIL
```

### Validate query string for paginated search

```clipper
FUNCTION _ProductList()
   LOCAL oVal, nPage, nLimit, cQ

   oVal := UValidateGet( {
      "page"  => { "optional|integer|min:1",    "Page",  1 },
      "limit" => { "optional|integer|between:1,100", "Limit", 20 },
      "q"     => { "optional|string|max:200|trim", "Search", "" }
   } )
   oVal:Make()   // never fails (all optional with defaults)

   nPage  := oVal:Get( "page" )
   nLimit := oVal:Get( "limit" )
   cQ     := oVal:Get( "q" )

   // ... query DB ...
   USendJson( { "page" => nPage, "limit" => nLimit, "results" => aResults } )
RETURN NIL
```

### Validation with custom rule against DB

```clipper
FUNCTION _ChangeEmail()
   LOCAL oVal

   oVal := UValidateOrFail( {
      "email" => { "required|string|email|trim|lower",
                   "Email",
                   "",
                   {|v| iif( _EmailTaken(v), "The email is already registered", .T. ) }
                 }
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF

   cEmail := oVal:Get( "email" )
   // ... update email ...
   USendJson( { "ok" => .T. } )
RETURN NIL

STATIC FUNCTION _EmailTaken( cEmail )
   // query DB and return .T. if the email already exists
RETURN .F.
```

---

## 14. Quick rule reference

```
-- Presence --
required       optional

-- Types / cast --
string         integer        numeric/decimal
boolean/bool   date           positive

-- Range --
min:N          max:N
minlen:N       maxlen:N
between:N,M

-- Format --
email          url            ip
regex:PATTERN

-- Lists --
in:a,b,c       notin:a,b,c

-- Dates --
mindate:YYYY-MM-DD   maxdate:YYYY-MM-DD

-- Cross-field --
confirmed      (field_confirmation must match)

-- Sanitization (inline or in hSanitate) --
trim    ltrim   rtrim   upper   lower
strip_tags      slug    nl2br   escape
abs             round:N

-- Markers --
field          escapedfield   resume
```
