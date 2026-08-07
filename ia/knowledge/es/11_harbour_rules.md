# Harbour — Reglas y trampas

Cosas no obvias que hacen tropezar a los recién llegados escribiendo apps HIX.

## `LOCAL` al principio

    FUNCTION Foo( cParam )
       LOCAL cResult          // ← cada LOCAL aquí
       LOCAL nCount           // ← antes de cualquier código ejecutable
       LOCAL oError

       nCount := 0            // primera sentencia ejecutable
       TRY
          // ...
       CATCH oError
          // ...
       END
    RETURN cResult

`LOCAL` después de cualquier sentencia = error de compilación.

`STATIC` a nivel fichero debe ir ANTES del primer `FUNCTION`/`PROCEDURE`.

## Comparación de strings — siempre `==`, nunca `!=`

El default `SET EXACT OFF` hace que `!=` compare por prefijo:

    "abc" != "ab"   // .F. !!  ("ab" es prefijo de "abc")
    "abc" == "ab"   // .F.     correcto

Regla: usa `==` para igualdad. Para comparación protegida: `!Empty(str) .AND. str == other`.

## No existe `hb_UnixTime()`

No existe — error de linker. Usa:

    nNow := Int( hb_TToSec( hb_DateTime() ) )

## `hb_AIns` necesita 4 args para crecer el array

    hb_AIns( aArr, nPos, xVal, .T. )   // ← el .T. hace que crezca
    hb_AIns( aArr, nPos )              // mal — no crece, se pierde el último elemento

## `hb_DirExists` y la barra final en Windows

    hb_DirExists( "C:\path\" )      // .F. aunque exista!
    hb_DirExists( "C:\path"  )      // .T.

Quita el separador final antes de chequear:

    IF Right( cPath, 1 ) $ "\/"
       cPath := hb_StrShrink( cPath, 1 )
    ENDIF
    IF hb_DirExists( cPath )
       // ...
    ENDIF

## `TRY/CATCH/FINALLY`

    LOCAL oError

    TRY
       // arriesgado
    CATCH oError
       le( "Error: " + oError:description )
    FINALLY
       // siempre corre (cleanup)
    END

Definido vía `#xcommand`:

    #xcommand TRY     => BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }
    #xcommand CATCH [<!oErr!>] => RECOVER [USING <oErr>] <-oErr->
    #xcommand FINALLY => ALWAYS

`oError` debe declararse LOCAL al principio de la función.

## Codeblocks en acciones de ruta

`bAction := {|| ... }` — sin parámetro. El request es thread-local, se lee vía `U*`.

    // CORRECTO
    oSrv:AddRouteGet( "x", "/x", {|| USendJson( {=>} ) } )

    // MAL — oReq no está en el closure
    oSrv:AddRouteGet( "x", "/x", {|oReq| oReq:Respond( {=>}, 200, "json" ) } )

## Alias y caja

Los alias DBF deben ir en MAYÚSCULAS cuando se referencian con sintaxis de alias:

    USE "data/users" ALIAS "USERS"
    ? USERS->name       // OK
    ? Users->name       // error en runtime

## Literal de hash vs hash vacío

    { => }             // hash vacío (sintaxis Harbour)
    { "k" => "v" }     // hash de una clave
    { }                // ARRAY vacío (¡tipo distinto!)

`hb_HKeys(h)`, `hb_HValues(h)`, `hb_HHasKey(h,k)`, `hb_HGetDef(h,k,def)`.

## Número ↔ string

    hb_NToS( 42 )       // "42"
    Val( "42" )         // 42
    Str( 3.14, 6, 2 )   // "  3.14"  (ancho, decimales)
    LTrim( Str( n ) )   // número sin espacios delante

## Fecha ↔ string

    DToC( d )           // usa SET DATE
    CToD( "31/12/2026" )
    hb_DToC( d, "YYYY-MM-DD" )
    Date()              // hoy

## Compilación

`hbmk2` lee un fichero de proyecto `.hbp`. Flags comunes:
- `-hbx=foo.hbx` — regenera el índice de cabeceras (auto tras renames)
- `-gtwvw` / `-gtwin` — modo GUI/consola
- `-b` — info de debug
- Include paths con `-i<dir>`, libs con `-l<name>`

Nunca edites `.hbx` a mano — se auto-genera.

## Logs / debug en HIX

    #include "hix_logger.ch"

    ld( "debug msg" )    // DEBUG
    l(  "info msg"  )    // INFO
    lw( "warn msg"  )    // WARN
    le( "err msg"   )    // ERROR

Init una vez al arrancar:

    HIX_LoggerInit( "logs/app.log", HIX_LOG_DEBUG, .T. )   // .T. = también a consola

## Formato-de-salida para runners de tests

Si escribes tu propio harness parseado por un runner externo, imprime exacto:

    OutStd( hb_eol() + "Tests: " + hb_NToS(nTot) + " total | " + ;
            hb_NToS(nPass) + " passed | " + hb_NToS(nFail) + " failed" + hb_eol() )
    OutStd( "End test..." + hb_eol() )

El regex es `\d+ total \| \d+ passed \| \d+ failed`.
