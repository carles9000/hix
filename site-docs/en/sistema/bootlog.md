# 📝 Boot Log

**HIX** captures in a **static thread-safe hash** everything that happens during
server startup: loaded configuration files, initialized subsystems, compiled loaders,
applied middlewares, and registered routes. This record remains accessible at runtime
for inspection, diagnostics, or to display it in an admin UI.

Each event is saved as an array of **4 elements**:

```harbour
{ cAction, lStatus, cValue, xCargo }
```

| Field     | Type | Meaning                                                           |
|-----------|------|-------------------------------------------------------------------|
| `cAction` | `C`  | Type of action: `"file"`, `"config"`, `"init"`, `"route"`, ...   |
| `lStatus` | `L`  | `.T.` if the operation succeeded, `.F.` if it failed              |
| `cValue`  | `C`  | Human-readable identifier of the resource (`myapp.prg`, `users.list`, ...) |
| `xCargo`  | `X`  | Free payload (error description, metadata, `NIL` by default)     |

---

## When do you need it?

- To **diagnose** why a module, middleware, or route didn't load.
- To expose the **startup status** to the team as JSON or a view.
- To verify at a glance that **all subsystems** (logger, proxy,
  firewall, access log, metrics, socket) started without errors.

---

## Sections

The hash is organized by **loading processes**. The standard sections are:

| Section       | Content                                                           |
|---------------|-------------------------------------------------------------------|
| `config`      | Loaded configuration files (`hix.json`, `www/config.json`, …)    |
| `server`      | Initialized subsystems: logger, proxy, firewall, access log, metrics… |
| `loaders`     | `.prg` files compiled and loaded from `www/loaders/`              |
| `middlewares` | Middlewares loaded from `www/middlewares/config.json`             |
| `routes`      | Registered routes (JSON or programmatic; excludes internal `hix.*`) |

You can add your own sections from code by calling `HIX_BootLogAdd`.

---

## Public API

```harbour
HIX_BootLog()                                          // complete hash (cloned)
HIX_BootLogSection( cKey )                             // array of a section
HIX_BootLogAdd( cKey, cAction, lStatus, cValue, xCargo ) // add event
HIX_BootLogReset()                                     // empty the hash
HIX_BootLogShow()                                      // dump to console formatted
HIX_BootLogAction( bAction )                           // callback on each Add
HIX_BootLogVerbose( lOn )                              // enable/disable verbose
HIX_BootLogIsVerbose()                                 // query the verbose flag
```

### `HIX_BootLog()`

Returns a **cloned copy** of the complete hash, thread-safe. Ideal for
sending as JSON:

```harbour
oSrv:AddRouteGet( "hix.boot", "/hix-boot", {|| USendJson( HIX_BootLog() ) } )
```

### `HIX_BootLogSection( cKey )`

Returns the array of a specific section (or `{}` if it doesn't exist):

```harbour
aRoutes := HIX_BootLogSection( "routes" )
FOR EACH aItem IN aRoutes
   ? aItem[3], aItem[4]     // cValue, xCargo
NEXT
```

### `HIX_BootLogAdd( cKey, cAction, lStatus, cValue, xCargo )`

Adds an entry. `lStatus` defaults to `.T.`; `xCargo` defaults to `NIL`.
If `lStatus == .F.` and `xCargo == NIL`, it is replaced with a localized
placeholder (`BOOT_ERR_NO_DESC`) so the UI doesn't see `NIL` in errors.

```harbour
HIX_BootLogAdd( "loaders", "file", .T., "myapp.prg" )
HIX_BootLogAdd( "loaders", "file", .F., "bad.prg", oErr:description )
```

### `HIX_BootLogReset()`

Empties the hash. It is called automatically at the start of `_Init()` if the process
owns the globals.

### `HIX_BootLogShow()`

Dumps the content to console with human-readable format, in logical order
(`config → server → loaders → middlewares → routes`):

```
=== HIX Boot Log ===
[config]
  OK  file     hix.json
  OK  file     www/config.json
[server]
  OK  init     logger level=info console=T
  OK  init     access_log enabled=T file=access.log
  OK  init     metrics
  OK  init     socket ssl=F
[loaders]
  OK  file     myapp.prg
  ERR file     bad.prg  -> Unterminated string 'x, HB_COMPILEFROMBUF
[middlewares]
  OK  file     cors.prg
  OK  config   session: cookie=hix_sess ttl=3600 storage=memory
[routes]
  OK  init     users.list  -> type:compiled, route=[/users], method[GET,OPTIONS], context:[]
  OK  init     admin.edit  -> type:file[api.json], route=[/admin/:id], method[GET,POST,OPTIONS], context:[admin]
====================
```

### `HIX_BootLogAction( bAction )`

Registers a **codeblock** that executes **each time** an entry is added
to the boot log. The codeblock receives the five fields of the newly
inserted entry:

```harbour
{| cKey, cAction, lStatus, cValue, xCargo | ... }
```

It's useful for:

- **Forwarding** each event to the logger (`l()`/`lw()`/`le()`) in real time.
- **Reporting** errors to an external system (Sentry, webhook, e-mail).
- **Updating a live UI** during startup (progress bar,
  admin panel).

Pass `NIL` to disable it. Returns the previous codeblock in case you need to
restore it.

**Example - forward to logger with a helper function:**

```harbour
// On server startup
HIX_BootLogAction( {|cKey, cAction, lStatus, cValue, xCargo| ;
   MyBootLog( cKey, cAction, lStatus, cValue, xCargo ) } )

// Helper function in your app
FUNCTION MyBootLog( cKey, cAction, lStatus, cValue, xCargo )
   _t( "[BOOT/" + cKey + "] " + cAction + " " + ;
       iif( lStatus, "OK", "ERR" ) + " " + cValue + ;
       iif( xCargo == NIL, "", " -> " + hb_CStr( xCargo ) ) )
RETURN NIL
```

Each entry added to the boot log triggers `MyBootLog()` with the event data;
the function formats them and sends them to `_t()` (trace), which can
dump them to console, file, or wherever you decide.

> The callback is invoked **outside the internal mutex** so as not to block other
> writes. Still, keep the codeblock **fast** - it executes synchronously
> during startup.

### `HIX_BootLogVerbose( lOn )` / `HIX_BootLogIsVerbose()`

Enables or queries detailed mode (reserved for extensive records like
per-route entries). Returns the previous value.

---

## Format of `xCargo` by section

### Loaders (errors)

When a `.prg`/`.hrb` fails, `xCargo` contains:

```
<oError:description>, <oError:operation>
```

Real example:

```
ERR file     no_symbol.hrb  -> Unknown or unregistered function symbol, ZDUMMY
```

If the error has no `operation`, only the description appears. If there's
no capturable exception, it defaults to the internal message (`BOOT_LOADER_LOAD_FAIL_NX`).

### Middlewares

- `file` on success → `xCargo` = `NIL`
- `file` on error → `xCargo` = `"compile failed"`, `"handle NIL"` or
  `oErr:description`
- `config` (session/csrf setup) → `xCargo` = `NIL` and the description goes in
  `cValue`

### Routes

Each registered route (except internal `hix.*` ones) generates:

```
type:<type>, route=[<url>], method[<methods>], context:[<scope>]
```

Where `type` is:

- `compiled` - the route was registered from code (for example with
  `AddRouteGet`).
- `file[<name.json>]` - the route was loaded from `www/routes/<name.json>`.

### Server

Subsystems are registered as `cAction = "init"` and `cValue` describes the
resource with its key parameters (`logger level=info console=T`,
`firewall mode=blacklist filter=…`, `socket ssl=T`, etc.).

---

## Exposing the boot log to the user

Since the hash is serializable, the most straightforward way is an HTTP route:

```harbour
// Raw JSON endpoint
oSrv:AddRouteGet( "hix.boot", "/hix-boot", ;
   {|| USendJson( HIX_BootLog() ) } )

// Specific section
oSrv:AddRouteGet( "hix.boot.routes", "/hix-boot/routes", ;
   {|| USendJson( HIX_BootLogSection( "routes" ) ) } )

// Tabulated HTML view
oSrv:AddRouteGet( "hix.boot.html", "/hix-boot.html", ;
   {|| USendView( "hix/bootlog.html", { "hLog" => HIX_BootLog() } ) } )
```

These routes should be protected with `HixMwAdmin` or the session middleware
you use in your admin panel.

---

## Example - custom section

You can use your own section to record events during your application's startup:

```harbour
PROCEDURE Main()
   LOCAL oSrv := THixServer():New()

   oSrv:bInit := {||
      HIX_BootLogAdd( "app", "init", .T., "warmup cache" )
      IF ! _LoadCatalog()
         HIX_BootLogAdd( "app", "init", .F., "catalog", "corrupted file" )
      ENDIF
   }

   oSrv:Start()
   IF oSrv:hThread != NIL
      hb_threadJoin( oSrv:hThread )
   ENDIF
RETURN
```

Your `app` section will appear at the end of the dump and also in the hash returned
by `HIX_BootLog()`.
