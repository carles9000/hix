# 🧨 Error handling

Anything that can fail (a database access, JSON parsing, division by zero, a
missing file) ends in a **Harbour error** (an object `oError` with
`description`, `subSystem`, `operation`, ...). Without explicit handling, the
worker executing the action dies, and the client receives an empty response or
the entire server crashes.

HIX exposes **two levels** of defense:

1. **TRY / CATCH** local — within a specific action, for failures you know can
   happen (database, network, parsing).
2. **Global handler** (`bOnError`) — safety net that catches any uncaught error,
   sends a coherent HTTP response to the client, and writes to `errors.log`.

```
GET /api/users/42
      │
      ▼
   action _UserGet()
      │
      ├─── TRY ──── DB error ──── CATCH ────────── USendError(500, ...)
      │                                                  │
      └─── other uncaught errors                         ▼
              │                                    client receives JSON
              ▼
        worker protect ─── bOnError(oErr, oReq) ─── HIX_ShowError
              │                                          │
              ▼                                          ▼
        logs + responds 500                   errors.log + render
```

---

## TRY / CATCH / FINALLY

Defined in `include/hix_const.ch`:

```clipper
TRY
   // code that may fail
CATCH oError
   // error handling
FINALLY
   // always executed (with or without error)
END
```

`oError` is always declared as `LOCAL` at the beginning of the function:

```clipper
FUNCTION _DbInsert( hData )
   LOCAL oError, lOk := .F.
   LOCAL oDbf

   TRY
      oDbf := UDbf():New( "customers" )
      
      oDbf:Append()
      oDbf:Save( hData )
      lOk := .T.
   CATCH oError
      le( "DB insert failed: " + oError:description )
      lOk := .F.
   FINALLY
      oDbf:Close()
   END

RETURN lOk
```

### Typical `oError` fields

| Field | Content |
|---|---|
| `oError:description` | Main error message |
| `oError:operation` | Function or operation that failed (`OPEN`, `JSONDECODE`, ...) |
| `oError:subSystem` | Subsystem (`DBFCDX`, `BASE`, `MEMIO`, ...) |
| `oError:subCode` | Numeric code — useful as HTTP status if in range |
| `oError:filename` | File involved |
| `oError:procName` | Function where it was triggered |
| `oError:procLine` | Line in the function |
| `oError:args` | Arguments passed to the failed function |
| `oError:cargo` | Free hash — HIX uses it for extra context (view code, line code, ...) |

---

## Patterns in actions

### Validation + database with controlled error

```clipper
FUNCTION _UserCreate()
   LOCAL oVal, oUsers, oError, nId := 0, cMsg := ""

   oVal := UValidateOrFail( { ;
      "name"  => "required|string|max:50",  ;
      "email" => "required|string|email"    ;
   } )
   IF oVal == NIL ; RETURN NIL ; ENDIF

   TRY
      oUsers := TUsers()
      nId    := oUsers:Insert( oVal:DataFields(), @cMsg )
   CATCH oError
      le( "Insert error: " + oError:description )
      RETURN USendError( 500, oError:description )
   END

   IF nId == 0
      RETURN USendError( 422, cMsg )
   ENDIF

   USendJson( { "id" => nId }, 201 )
RETURN NIL
```

### Parsing incoming JSON

```clipper
LOCAL hBody := UJson()
IF hBody == NIL
   RETURN USendError( 400, "Body is not valid JSON" )
ENDIF
```

`UJson` already returns `NIL` if it fails — you don't need an explicit TRY/CATCH.

### Access to optional file

```clipper
LOCAL oError, cContent := ""

TRY
   cContent := hb_MemoRead( cPath )
CATCH oError
   cContent := "(file not available)"
END

USendText( cContent )
```


---

## Global handler (`bOnError`)

Any error you **do not** catch with TRY/CATCH falls here. The server invokes it
with `(oError, oReq)`:

```clipper
oSrv:bOnError := {|oErr, oReq|
   le( "Uncaught error: " + oErr:description )
   HIX_HttpError( oReq, 500, oErr:description )
}
```

If you don't define `bOnError`, HIX uses its internal renderer (`HIX_ShowError` /
`HIX_ErrorSys`) that:

- **dev**: shows detailed HTML with stack, source line, and context.
- **prod**: shows generic 500 HTML with no internal detail.

See [Errorsys](errorsys.md) to customize the template.

### Automatically differentiate JSON / HTML

```clipper
oSrv:bOnError := {|oErr, oReq|
   IF HIX_WantsJson( oReq )
      oReq:Respond( { "error" => oErr:description }, 500, "json" )
   ELSE
      HIX_ShowError( oErr, oReq )    // delegates to internal renderer
   ENDIF
}
```

> `HIX_ShowError` already does this split internally: if `Accept` asks for
> JSON, it responds with JSON; if it asks for HTML, it renders the errorsys
> template.

---

## Explicit HTTP errors

Not every error is an exception. Many are expected situations:

```clipper
USendError( 404, "User does not exist" )
USendError( 403, "No permission" )
USendError( 422, "Invalid data" )
USendError( 429, "Too many attempts" )
```

`USendError` sends the status and body as JSON or HTML depending on `Accept`.
It's **the** way to respond with controlled errors from the action.

### Direct equivalent

`HIX_HttpError( oReq, nStatus, cMsg )` — receives the explicit `oReq`, useful
inside middlewares.

---

## Worker protect

Under the hood, each HTTP worker wraps the controller execution in
`HixWorkerProtect`: if the action throws an uncaught exception, protect:

1. Calls `bOnError` if defined.
2. If not, calls `HIX_ShowError`.
3. Logs the entry to `errors.log`.
4. Closes the connection cleanly — it doesn't kill the worker, only the request.

This is what prevents an error on a single URL from bringing down the entire
server.

---

## Error logging

`HIX_ShowError` always calls `_HixWriteErrorLog` before rendering. The
`errors.log` file (configured with `HIX_ErrorLogInit` or via
`[server] errors=.logs`) accumulates every error with timestamp and sequence.

```clipper
HIX_ErrorLogInit( ".logs" )      // dir where errors.log is written
```

For free logging outside the error flow, use the log helpers:

```clipper
ld( "Debug detail" )       // DEBUG
l(  "Info" )               // INFO
lw( "Warning" )            // WARN
le( "Error description" )  // ERROR
```

See the Logger module.

