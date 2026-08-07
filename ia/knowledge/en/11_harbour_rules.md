# Harbour Language — Rules & Gotchas

Non-obvious things that trip up newcomers writing HIX apps.

## `LOCAL` must be at the top

    FUNCTION Foo( cParam )
       LOCAL cResult          // ← every LOCAL here
       LOCAL nCount           // ← before any executable code
       LOCAL oError

       nCount := 0            // first executable statement
       TRY
          // ...
       CATCH oError
          // ...
       END
    RETURN cResult

`LOCAL` after any statement = compile error.

`STATIC` at file level must come BEFORE the first `FUNCTION`/`PROCEDURE`.

## String comparison — always `==`, never `!=`

Default `SET EXACT OFF` makes `!=` do a prefix compare:

    "abc" != "ab"   // .F. !!  ("ab" is a prefix of "abc")
    "abc" == "ab"   // .F.     correct

Rule: use `==` for equality. Use `!Empty(str) .AND. str == other` for guarded compare.

## No `hb_UnixTime()`

Does not exist — linker error. Use:

    nNow := Int( hb_TToSec( hb_DateTime() ) )

## `hb_AIns` needs 4 args to grow the array

    hb_AIns( aArr, nPos, xVal, .T. )   // ← the .T. makes it grow
    hb_AIns( aArr, nPos )              // wrong — array doesn't grow, last element lost

## `hb_DirExists` and trailing backslash on Windows

    hb_DirExists( "C:\path\" )      // .F. even if it exists!
    hb_DirExists( "C:\path"  )      // .T.

Strip trailing separator before checking:

    IF Right( cPath, 1 ) $ "\/"
       cPath := hb_StrShrink( cPath, 1 )
    ENDIF
    IF hb_DirExists( cPath )
       // ...
    ENDIF

## `TRY/CATCH/FINALLY`

    LOCAL oError

    TRY
       // risky
    CATCH oError
       le( "Error: " + oError:description )
    FINALLY
       // always runs (cleanup)
    END

Defined via `#xcommand`:

    #xcommand TRY     => BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }
    #xcommand CATCH [<!oErr!>] => RECOVER [USING <oErr>] <-oErr->
    #xcommand FINALLY => ALWAYS

`oError` must be declared LOCAL at the top of the function.

## Codeblocks in route actions

`bAction := {|| ... }` — no parameter. Request is thread-local, read via `U*`.

    // CORRECT
    oSrv:AddRouteGet( "x", "/x", {|| USendJson( {=>} ) } )

    // WRONG — oReq not in closure scope
    oSrv:AddRouteGet( "x", "/x", {|oReq| oReq:Respond( {=>}, 200, "json" ) } )

## Aliases and case

DBF aliases must be UPPER when referenced with alias syntax:

    USE "data/users" ALIAS "USERS"
    ? USERS->name       // OK
    ? Users->name       // runtime error

## Hash literal vs empty hash

    { => }             // empty hash (Harbour syntax)
    { "k" => "v" }     // one-key hash
    { }                // empty ARRAY (different type!)

`hb_HKeys(h)`, `hb_HValues(h)`, `hb_HHasKey(h,k)`, `hb_HGetDef(h,k,def)`.

## Number ↔ string

    hb_NToS( 42 )       // "42"
    Val( "42" )         // 42
    Str( 3.14, 6, 2 )   // "  3.14"  (width, decimals)
    LTrim( Str( n ) )   // number with no leading spaces

## Date ↔ string

    DToC( d )           // uses SET DATE
    CToD( "31/12/2026" )
    hb_DToC( d, "YYYY-MM-DD" )
    Date()              // today

## Compilation

`hbmk2` reads a `.hbp` project file. Common flags:
- `-hbx=foo.hbx` — regenerate the header index (auto after renames)
- `-gtwvw` / `-gtwin` — GUI/console mode
- `-b` — debug info
- Include paths via `-i<dir>`, libs via `-l<name>`

Never edit `.hbx` manually — it is auto-generated.

## Logs / debugging in HIX

    #include "hix_logger.ch"

    ld( "debug msg" )    // DEBUG
    l(  "info msg"  )    // INFO
    lw( "warn msg"  )    // WARN
    le( "err msg"   )    // ERROR

Init once at boot:

    HIX_LoggerInit( "logs/app.log", HIX_LOG_DEBUG, .T. )   // .T. = also to console

## Format-of-output for test runners

If you write your own test harness parsed by an outer runner, print exactly:

    OutStd( hb_eol() + "Tests: " + hb_NToS(nTot) + " total | " + ;
            hb_NToS(nPass) + " passed | " + hb_NToS(nFail) + " failed" + hb_eol() )
    OutStd( "End test..." + hb_eol() )

The regex is `\d+ total \| \d+ passed \| \d+ failed`.
