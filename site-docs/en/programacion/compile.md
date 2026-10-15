# ⚙️ Compile subsystem — `HIX_Compile*`

HIX exposes a unified subsystem for compiling and executing dynamic Harbour
code from within your application. It is the path used internally by the
dispatcher (dynamically loaded `.prg` files), loaders, middlewares and the
view engine. It is also available for your own controllers when you need to
compile or execute a `.prg` or a pre-compiled HRB at response time.

> 🧭 **Introduced in v2.3.12**, consolidated in **v2.4.0** as the only
> compilation path in the lib. The former `HIX_CompileFile` was removed
> in v2.4.0.

---

## Why a subsystem

Before v2.3.12 there were two separate paths: one for pure compile
(`HIX_CompileFile` + `hb_CompileFromBuf`) and another for compile+run, with
different error contracts and stack walkers specific to each caller. The
result: duplicated code, hard-to-propagate errors and asymmetric boot logs
between loaders and dispatcher.

v2.4.0 consolidates all those paths (dispatcher, loaders, middleware
loader, view engine) on a **single hash contract**:

```
{ ok, phase, hrb, err, diagnostics, preambleLines, where }
```

- `ok` — boolean, `.T.` if the final phase produced no error.
- `phase` — which phase execution stopped at: `"compile"`, `"load"`, `"run"`.
- `hrb` — bytes of the HRB resulting from compile (if compile phase passed).
- `err` — normalised error hash (see below). `NIL` if `ok=.T.`.
- `diagnostics` — array of secondary diagnostics (warnings, lines, ...).
- `preambleLines` — number of preamble lines injected (adjusts `line` in `err`).
- `where` — compile location info (filename, etc.).

---

## Public API

All functions **never propagate `Break`**: they return the hash with
`ok=.F.` and `err` populated if something fails. You never need to wrap
them in `TRY/CATCH`.

### `HIX_CompileCode( cSource [, hOpts] [, cFilename] )`

Compiles a `.prg` source in memory. Typical options in `hOpts`:
`{ "virtualName" => "my_module", "runtime" => .F. }`. `cFilename`
labels the error when compile fails.

```clipper
LOCAL hRes := HIX_CompileCode( "FUNCTION Foo() ; RETURN 42" )
IF ! hRes["ok"]
   le( "Compile failed: " + hRes["err"]["description"] )
   RETURN NIL
ENDIF
// hRes["hrb"] contains the HRB ready to execute
```

### `HIX_CompileCodeFromFile( cPath )`

Compile-only wrapper from disk. Returns the same hash. This is the path
used by the dispatcher and loaders to compile persisted `.prg` files.

```clipper
LOCAL hRes := HIX_CompileCodeFromFile( "www/controllers/my_action.prg" )
IF ! hRes["ok"]
   USendError( 500, "Compile: " + hRes["err"]["description"] )
   RETURN NIL
ENDIF
```

### `HIX_CompileRunPrg( cPath [, ...args] )`

Compile + execute in one step. Also captures runtime errors, not just
compile errors. Returns the same contract hash — `phase` will be
`"compile"` if it failed while compiling and `"run"` if it failed
while executing.

```clipper
LOCAL hRes := HIX_CompileRunPrg( "scripts/report.prg", nUserId, cPeriod )
IF ! hRes["ok"]
   // Same shape whether it was a compile or runtime error
   USendError( 500, hRes["err"]["description"] )
   RETURN NIL
ENDIF
```

### `HIX_CompileRunHrb( cHrbBytes [, cVirtualName [, ...args]] )`

Executes an already compiled HRB (bytes). Useful when you have the `.hrb`
in cache or generated it with `HIX_CompileCode` and saved it to disk.
Internally uses `HB_HRB_BIND_FORCELOCAL` to avoid collisions with other
loaded HRBs.

```clipper
LOCAL cHrb := hb_MemoRead( "cache/report.hrb" )
LOCAL hRes := HIX_CompileRunHrb( cHrb, "report", nUserId )
```

### `HIX_CompileLastError()`

Returns a snapshot of the last runtime error captured by the subsystem.
**`THREAD STATIC`** — a thread only sees its own errors. Useful when you
have called `HIX_CompileRunPrg` and need the full stack apart from the
`err` already in the hash.

```clipper
LOCAL hLast := HIX_CompileLastError()
IF hLast != NIL
   ld( "aStack: " + hb_ValToExp( hLast["aStack"] ) )
ENDIF
```

---

## Normalised `err` shape

The error hash inside `hRes["err"]` always has the same keys, whether from
compile or runtime. **Compile** produces the subset:

| Key           | Meaning                                          |
|---------------|--------------------------------------------------|
| `kind`        | `"compile"` or `"runtime"`                       |
| `severity`    | `"error"`, `"warning"`                           |
| `code`        | Numeric code (preprocessor, parser)              |
| `description` | Main message — ready to show to the user         |
| `file`        | Source file where the error was detected         |
| `line`        | Line (already adjusted by `preambleLines`)       |
| `lineCode`    | Exact snippet of the failing line                |

**Runtime** adds full Harbour context:

| Additional key | Meaning                                            |
|----------------|----------------------------------------------------|
| `operation`    | Function/operation that failed                     |
| `args`         | Arguments passed when it crashed                   |
| `subsystem`    | `oError:subSystem`                                 |
| `genCode`      | `oError:genCode` (generic Harbour code)            |
| `subCode`      | `oError:subCode`                                   |
| `osCode`       | OS code if applicable                              |
| `filename`     | Runtime error file                                 |
| `stack`        | Stack trace as text                                |
| `aStack`       | Stack trace as structured array                    |

---

## Example — controller executing a dynamic script

```clipper
FUNCTION _RunUserScript()
   LOCAL cPath := "www/scripts/" + UParam( "name" ) + ".prg"
   LOCAL hRes

   IF ! hb_FileExists( cPath )
      RETURN USendError( 404, "Script not found" )
   ENDIF

   hRes := HIX_CompileRunPrg( cPath, USession( "user_id" ) )

   IF ! hRes["ok"]
      le( "Script failed [" + hRes["phase"] + "]: " + hRes["err"]["description"] )
      RETURN USendJson( { ;
         "ok"    => .F.,                       ;
         "phase" => hRes["phase"],             ;
         "error" => hRes["err"]["description"],;
         "line"  => hRes["err"]["line"]        ;
      }, 500 )
   ENDIF

   USendJson( { "ok" => .T. } )
RETURN NIL
```

---

## Enriched boot log

From v2.4.0 onwards, when a **loader** or **middleware** fails to compile
during startup, the boot log dumps line, code and snippet instead of just
the message. No configuration required — automatic because the loader uses
`HIX_CompileCodeFromFile` and translates its hash directly to the logger.

Typical format:

```
[loader] fail: www/loaders/stats.prg
   line: 42  (code: 2007)
   >>  LOCAL x = y + z        // = instead of :=
   description: Syntax error
```

---

## When not to use it

- **Do not** call `HIX_CompileRunPrg` in your hot path for scripts that
  never change — it compiles every time. Save the HRB with `HIX_CompileCode`
  + an `.md5` as cache and use `HIX_CompileRunHrb` afterwards. That is
  exactly what the view engine does internally.
- **Do not** use this subsystem to evaluate simple expressions. For that
  Harbour already has `&(cExpr)` (macro-eval). Compile is designed for
  full `.prg` blocks with `FUNCTION`/`PROCEDURE`.
- **Do not** rely on `err` carrying `aStack` when `kind=="compile"`.
  The stack only makes sense for runtime errors.

---

## Changes from previous versions

| Before v2.3.12                       | From v2.4.0 onwards                             |
|--------------------------------------|-------------------------------------------------|
| `HIX_CompileFile( cPath )`           | **Removed.** Use `HIX_CompileCodeFromFile( cPath )` for compile-only or `HIX_CompileRunPrg( cPath )` for compile+run. |
| `hb_CompileFromBuf` direct           | Encapsulated in `HIX_CompileFromBuf` (low-level, internal use of `HIX_CompileCode`) |
| `oError:operation == "line:N"`       | `oError:operation == "line N"`. Official source is `oErr:cargo["line"]` |
| `src/hix_prepro.prg`                 | Removed. `TRY/CATCH/FINALLY` directives now live in `src/include/hix_const.ch`. |

See [changes/2.4.0.md](https://github.com/carles9000/hix.pro/blob/main/changes/2.4.0.md)
for the complete list of breaking changes and the migration audit trail.
