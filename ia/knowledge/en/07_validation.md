# Validation

Built-in validator with rule strings + auto 422 response.

## Quick flow

    LOCAL oVal := UValidateOrFail( { ;
       "name"  => "required|string|max:100",  ;
       "email" => "required|string|email",    ;
       "age"   => "required|integer|min:18|max:99" ;
    } )
    IF oVal == NIL ; RETURN NIL ; ENDIF   // 422 already sent

    LOCAL cName := oVal:Get( "name" )
    LOCAL nAge  := oVal:Get( "age" )    // already coerced to number

## Input sources

| Helper | Source |
|--------|--------|
| `UValidatePost( hRules )`    | POST form / JSON body |
| `UValidateGet( hRules )`     | Query string |
| `UValidateParams( hRules )`  | Query + route params merged |
| `UValidateJson( hRules )`    | Explicit JSON body |
| `UValidateOrFail( hRules )`  | POST — auto 422 if any rule fails |

All return a `THixValidator` (except `UValidateOrFail` which may return `NIL`).

## Rule vocabulary

    required            field must be present and non-empty
    string              value type is string
    integer             value is an integer (or coercible)
    numeric             any number (int or decimal)
    boolean             value is .T./.F. or coercible
    array               value is an array

    min:N               string: length >= N ; number: value >= N
    max:N               string: length <= N ; number: value <= N
    minlen:N            string length >= N
    maxlen:N            string length <= N
    between:N:M         number between N and M inclusive

    email               matches an email pattern
    url                 starts with http:// or https://
    ip                  IPv4 address
    regex:PATTERN       matches PCRE regex
    in:a,b,c            value in the given list
    notin:a,b           value not in the given list

    field               (marker) include in DataFields() output when valid

## Sanitisation (applied before validation)

    trim                AllTrim()
    lower               Lower()
    upper               Upper()

Combine with pipes:

    "email" => "required|trim|lower|email"
    "name"  => "required|trim|max:100"

## Manual error handling

    LOCAL oVal := UValidatePost( hRules )
    IF ! oVal:Make()
       USendJson( { "errors" => oVal:GetErrorsJson() }, 422 )
       RETURN NIL
    ENDIF

`GetErrorsJson()` returns a hash keyed by field name:

    { "email" => "not a valid email", "age" => "must be at least 18" }

## Accessing validated data

    oVal:Get( "name" )               // single field
    oVal:GetAll()                    // hash of all validated fields
    oVal:DataFields()                // hash of fields flagged with `field` rule
                                     // (useful for INSERT/UPDATE payloads)

## Custom rules

Extend by inheriting or wrapping. Simple approach — validate manually after the fact:

    LOCAL oVal := UValidatePost( hRules )
    IF ! oVal:Make()
       RETURN USendJson( { "errors" => oVal:GetErrorsJson() }, 422 )
    ENDIF

    IF ! _IsCorporateEmail( oVal:Get("email") )
       RETURN USendJson( { "errors" => { "email" => "domain not allowed" } }, 422 )
    ENDIF

## Common gotcha

Rules operate on the RAW input BEFORE sanitisation for existence checks. If you rely on `trim` to make a blank pass `required`, add `trim` first: `"required|trim|min:3"` won't help — `required` runs on `"   "` (non-empty) and passes. Order matters only for sanitisation vs. later rules. Test edge cases.
