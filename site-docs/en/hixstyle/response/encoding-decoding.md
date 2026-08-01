# 🔤 Encoding / Decoding

When data crosses the barrier between server and client
(HTML, URL, JSON, header, body multipart), you need to **encode** or
**decode** special characters. If you do it wrong:

- A user's `<script>` ends up executing in another browser → **XSS**.
- An `&` in a URL breaks the query string.
- A `ñ` incorrectly encoded shows up as `Ã±` on the client.
- A binary without base64 corrupts the JSON.

HIX exposes helpers for each typical case and reuses standard Harbour
functions where it makes sense.

---

## HTML

### `UHtmlEncode( cText )`

Escapes the 5 dangerous characters: `& < > " '`.

```clipper
UHtmlEncode( '<script>alert("x")</script>' )
// → "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"

UHtmlEncode( "Pérez & Sons" )
// → "Pérez &amp; Sons"      (& → &amp;)
```

#### When to use it

Always when you insert **user input** inside HTML:

```clipper
LOCAL cName := UPost( "name", "" )

// BAD - user can inject <script>
USendHtml( "<h1>Hello " + cName + "</h1>" )

// GOOD - escaped
USendHtml( "<h1>Hello " + UHtmlEncode( cName ) + "</h1>" )
```

> In `.view.html` templates, the engine **does not escape automatically** - the
> `{{ expr }}` rule evaluates the expression and prints it as-is. If what you
> put in comes from the user, call `UHtmlEncode` inside the expression:
> `{{ UHtmlEncode( cName ) }}`.

### Characters allowed without escaping

- Letters and digits.
- Spaces, normal punctuation (`. , ; : ! ?`).
- Accented characters (`ñ á é í ó ú`) - as long as the page is in UTF-8.

### The inverse - decoding HTML entities

There is no specific helper in HIX. Standard Harbour can do it with
`hb_StrReplace` by inverting the hash, but **you shouldn't need to** -
if your DB stores plain text, already-escaped entities won't appear.

---

## URL

To encode values in query strings or paths, use Harbour's functions:

```clipper
hb_URLEncode( "Pérez & Sons" )
// → "P%C3%A9rez%20%26%20Sons"

hb_URLDecode( "P%C3%A9rez%20%26%20Sons" )
// → "Pérez & Sons"
```

### When to use it

When you build URLs with dynamic data:

```clipper
LOCAL cName := "Pérez & Sons"
LOCAL cUrl  := "/search?q=" + hb_URLEncode( cName )
URedirect( cUrl )
```

> HIX **automatically decodes** `UGet()` / `UPost()` / `UParam()` -
> there's nothing extra to do when reading.

---

## JSON

### Encode → string

```clipper
hb_jsonEncode( hData )
```

Converts hash/array/scalar to a valid JSON string. This is what
`USendJson` uses internally:

```clipper
USendJson( { "ok" => .T., "user" => "Carles" } )
// equivalent to:
USetMime( "json" )
UWrite( hb_jsonEncode( { "ok" => .T., "user" => "Carles" } ) )
```

#### Supported types

| Harbour | JSON |
|---|---|
| Hash `{=>}` | object `{...}` |
| Array `{}` | array `[...]` |
| String | `"..."` |
| Number | number |
| `.T.` / `.F.` | `true` / `false` |
| `NIL` | `null` |
| Date | `"YYYY-MM-DDTHH:MM:SSZ"` ISO 8601 |

### Decode → hash/array

```clipper
hb_jsonDecode( cJson, @xData )
```

Returns how many characters it consumed (0 if it failed). More practical from
an action:

```clipper
hData := UJson()    // NIL if the body is not valid JSON
```

```clipper
FUNCTION _ApiCreate()
   LOCAL hBody := UJson()

   IF hBody == NIL
      RETURN USendError( 400, "Body is not JSON" )
   ENDIF

   USendJson( { "received" => hBody } )
RETURN NIL
```

---

## UTF-8

### Explicit conversion

| Harbour function | What it does |
|---|---|
| `hb_StrToUtf8( c )` | Converts from local codepage → UTF-8 |
| `hb_Utf8ToStr( c )` | Converts UTF-8 → local codepage |
| `hb_cdpSelect( "UTF8" )` | Changes process codepage |

```clipper
LOCAL cTexto := "Niño"    // local codepage (CP1252 / ISO-8859-1)
LOCAL cUtf8  := hb_StrToUtf8( cTexto )    // "Ni\xc3\xb1o"
```

### When it matters

- **HIX works in UTF-8 by default** - strings that come from the HTTP body,
  URLs, headers, JSON, are already in UTF-8.
- If you read data from an old DBF with local codepage (CP850, CP1252),
  convert it with `hb_StrToUtf8` before putting it in the response.
- `UDbf:Row( lToStringWeb := .T. )` already does the conversion to UTF-8 if you
  pass `lToUtf8` in the constructor. See [UDbf](../models/udbf.md).

```clipper
LOCAL oDbf := UDbf():New( "customers", .T., .T. )  // lToUtf8=.T.
oDbf:Open()
USendJson( oDbf:Row( .T. ) )    // already comes in UTF-8
```

---

## Base64

For binary data inside JSON, URL or signed cookies:

```clipper
hb_Base64Encode( cBinary )
// → "SGVsbG8gV29ybGQ="

hb_Base64Decode( cEncoded )
// → "Hello World"
```

### Example - image embed in JSON

```clipper
LOCAL cBytes := hb_MemoRead( "logo.png" )

USendJson( { ;
   "name"      => "logo.png",       ;
   "mime"      => "image/png",      ;
   "data_b64"  => hb_Base64Encode( cBytes ) ;
} )
```

### Example - signed cookie

```clipper
LOCAL cPayload := hb_jsonEncode( { "uid" => 42, "exp" => _Now() + 3600 } )
LOCAL cSig     := hb_HMAC( cPayload, "secret-key" )
LOCAL cToken   := hb_Base64Encode( cPayload + "." + cSig )

USetCookie( "auth", cToken, 3600 )
```

---

## URL-safe Base64

For tokens in URLs, **without** `+ / =`:

```clipper
LOCAL cToken := hb_Base64Encode( cBin )

// Convert to URL-safe
cToken := StrTran( cToken, "+", "-" )
cToken := StrTran( cToken, "/", "_" )
cToken := StrTran( cToken, "=", ""  )    // no padding
```

This is the convention used by JWT. To reverse it, undo the `StrTran`s and
re-add padding until a multiple of 4.

---

## Quick comparison

| Case | Use |
|---|---|
| Insert text into HTML | `UHtmlEncode` |
| Build URL with data | `hb_URLEncode` |
| Respond with JSON | `USendJson` (calls `hb_jsonEncode`) |
| Read JSON from body | `UJson()` |
| Text to UTF-8 | `hb_StrToUtf8` |
| Binary in ASCII string | `hb_Base64Encode` |
| Hash signature | `hb_HMAC` / `hb_MD5` / `hb_SHA256` |

---

## Common errors

| Symptom | Cause |
|---|---|
| `Ã±` in the browser | The server sent CP1252 but the page declares `charset=utf-8` |
| `<script>` executes from user input | You didn't call `UHtmlEncode` before inlining |
| `%20` appears literal in a URL | It was encoded twice (`hb_URLEncode` on already-encoded data) |
| JSON with `"\u00f1"` instead of `ñ` | Incorrect client decoding - JSON with `\uXXXX` is valid and equivalent |
| Corrupted binary cookie | You forgot `hb_Base64Encode` - the cookie does not accept raw `\0` or `;` |

---

## Best practices

1. **Escape at output, not at input.** Store the raw text in the DB.
   Only escape when you build the HTML / URL / JSON output.
2. **Don't mix encodings.**
3. **Don't reinvent escapes.** `UHtmlEncode` covers the 5 standard OWASP
   characters - don't add more by hand.
4. **JSON is already safe.** `hb_jsonEncode` escapes correctly - you don't
   need `UHtmlEncode` on data that's already going through JSON.
5. **Base64 ≠ encryption.** Base64 only changes the representation; any
   attacker can decode it. For secrets, encrypt for real.

