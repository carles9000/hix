# Loaders and user hooks

**HIX** can dynamically load user code when the server starts.
Any `.prg` file located in `www/loaders/` is compiled to `.hrb`, loaded into memory,
and its functions become **globally accessible** from any route,
middleware, controller, or view.

In addition to loading, HIX defines two **lifecycle hooks**:

| Hook       | When it executes                                | Used for                          |
|------------|--------------------------------------------------|--------------------------------------|
| `USERINIT` | After loading the loaders, before accepting traffic | Opening connections, caching data, etc. |
| `USEREXIT` | When stopping the server, before closing sockets     | Closing connections, flushing buffers    |

Both are optional: if they do not exist, HIX does nothing. If they do, they are
invoked automatically.

---

## When do you need it?

- To **load application code** without recompiling the HIX library.
- To **initialize resources** that your app needs to be available on the first
  request (DB pool, in-memory caches, index warmup, etc.).
- To **release resources** cleanly when the server stops
  (close handles, flush custom logs, close open sockets).

---

## Directory `www/loaders/`

```
www/
└─ loaders/
   ├─ 00_bootstrap.prg     ← definitions of USERINIT / USEREXIT
   ├─ helpers.prg          ← utility functions
   ├─ tcustomers.prg       ← models, classes, etc.
   └─ …
```

Rules:

- Each `.prg` is compiled **only once** to `.hrb` (which is saved in the
  same directory alongside the `.prg`).
- On subsequent boots, HIX **recompiles only** those `.prg` files whose mtime is
  later than the corresponding `.hrb`. Already up-to-date `.hrb` files are loaded
  directly.
- Alphabetical order of the filename defines the load attempt order. If there are
  **cross-dependencies** between modules, HIX iterates through several passes
  until it resolves them all.
- Symbols are published with `hb_hrbLoad( 0x2, ... )` (BIND_LAZY), so
  they become available to the rest of the server.

Each attempt (success or failure) is recorded in the **Boot Log** under the
`"loaders"` section:

```
[loaders]
  OK  file     00_bootstrap.prg
  OK  file     tcustomers.prg
  ERR file     bad.prg  -> Unterminated string 'x, HB_COMPILEFROMBUF
```

See [Boot Log](bootlog.md) to inspect the results from code or expose them as JSON.

---

## Complete lifecycle

This is the exact order of events when starting and stopping the server:

```
THixServer:Start()
   │
   ├─ HIX_Loaders()        ← compiles and loads www/loaders/*.prg
   │
   ├─ Eval( ::bInit, SELF ) ← optional callback from the programmer (bInit)
   │
   ├─ HIX_UserInit()        ← invokes USERINIT() if hb_IsFunction("USERINIT")
   │
   └─ (opens port, accepts connections)

THixServer:Stop()
   │
   ├─ HIX_UserExit()        ← invokes USEREXIT() if hb_IsFunction("USEREXIT")
   │
   └─ (closes sockets, stops workers)
```

`USERINIT` runs **before** the server accepts the first request:
everything you prepare there will be available when traffic arrives.
`USEREXIT` runs **before** closing sockets, so you can still use the network if needed
(for example, to send a shutdown notification).

---

## Hooks `USERINIT` / `USEREXIT`

### How to declare them

They are declared as **top-level FUNCTION** (never `STATIC`) in any
`.prg` file in `www/loaders/`. They must be global so that `hb_IsFunction()`
resolves them.

```harbour
// www/loaders/00_bootstrap.prg

FUNCTION USERINIT()

   l( "Application initializing..." )
   _OpenDbConnection()
   _LoadCachesIntoMemory()

RETURN NIL

FUNCTION USEREXIT()

   l( "Application shutting down..." )
   _CloseDbConnection()

RETURN NIL
```

### Critical rules

- **They must be non-blocking.** An infinite loop, a socket without timeout,
  or a lock that doesn't release **delays startup** (in `USERINIT`) or
  **hangs shutdown** (in `USEREXIT`).
- **Exceptions are contained.** HIX wraps both hooks in an internal
  `TRY/CATCH`: if `USERINIT` throws, the error is traced and the
  server continues starting. The same applies to `USEREXIT`.
- **They are reentrant.** If for any reason you call `HIX_UserInit()` multiple
  times, `USERINIT()` executes each time. There is no guard for "execute only once".
- **`USERINIT` runs on the server's main thread**, before the
  accept loop. Any `STATIC` you assign becomes accessible from workers
  through public accessors.

### Example — DB connection pool

```harbour
// www/loaders/00_bootstrap.prg

STATIC s_oDbPool := NIL

FUNCTION UserDbPool()
RETURN s_oDbPool

FUNCTION USERINIT()

   LOCAL oErr

   TRY
      s_oDbPool := MyDbPool():New( "postgres://…", 8 )
      s_oDbPool:Warmup()
      l( "DB pool ready (8 connections)" )
   CATCH oErr
      le( "Could not initialize DB pool: " + oErr:description )
      // do not rethrow - server starts anyway
   END

RETURN NIL

FUNCTION USEREXIT()

   IF s_oDbPool != NIL
      s_oDbPool:CloseAll()
      s_oDbPool := NIL
   ENDIF

RETURN NIL
```

From any route:

```harbour
oSrv:AddRouteGet( "users", "/users", {||
   LOCAL oDb := UserDbPool()
   USendJson( oDb:Query( "SELECT id, name FROM users" ) )
} )
```

---

## Public API

```harbour
HIX_Loaders()        // compiles and loads www/loaders/*.prg. Returns .T. if all ok
HIX_GetLoaders()     // array with the status of each loaded module
HIX_UserInit()       // invokes USERINIT() if it exists. Internal TRY/CATCH
HIX_UserExit()       // invokes USEREXIT() if it exists. Internal TRY/CATCH
```

HIX calls these functions automatically during `Start()` / `Stop()`.
They are not usually called manually — but they are public in case you need
to do manual warm-up from a test or a CLI.

### Structure of a module (`HIX_GetLoaders()`)

Each entry in the returned array is a hash with these fields:

| Field     | Type | Meaning                                |
|-----------|------|--------------------------------------------|
| `file`    | `C`  | Filename (e.g., `tcustomers.hrb`)  |
| `loaded`  | `L`  | `.T.` if `hb_hrbLoad` succeeded           |
| `error`   | `L`  | `.T.` if compilation or load failed         |
| `msg`     | `C`  | Error description if `error == .T.`    |
| `oError`  | `O`  | Harbour error object (or `NIL`)       |
| `oHrb`    | `C`  | Binary contents of the `.hrb`               |
| `pSym`    | `P`  | Symbolic pointer to the loaded module        |
| `process` | `L`  | `.T.` if the `.prg` was (re)compiled now |

---

## Diagnosis

If something is not loading as expected:

1. **Check the Boot Log:** `HIX_BootLogShow()` to console, or
   `HIX_BootLogSection( "loaders" )` from code. Each `.prg` appears with
   OK/ERR and, in case of error, the exact description.
2. **Verify the hook is published:** `hb_IsFunction( "USERINIT" )`
   should return `.T.`. If it returns `.F.`, check that the function is
   declared as a top-level `FUNCTION` (not `STATIC`) in some `.prg`
   file in `www/loaders/`.
3. **Errors in `USERINIT` do not crash the server:** even though the server
   continues starting, the exception is recorded in the trace (`_t()`). See
   [Tracing](traceando.md) to read it.
4. **Regenerate `.hrb`:** if you suspect the cached `.hrb` is
   corrupted, delete it — HIX will recompile it from the `.prg` on the next
   boot.
