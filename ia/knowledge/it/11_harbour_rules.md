# Linguaggio Harbour — Regole e Trappole

Cose non ovvie che fanno inciampare i nuovi arrivati che scrivono app HIX.

## `LOCAL` deve essere in cima

    FUNCTION Foo( cParam )
       LOCAL cResult          // ← ogni LOCAL qui
       LOCAL nCount           // ← prima di qualsiasi codice eseguibile
       LOCAL oError

       nCount := 0            // prima istruzione eseguibile
       TRY
          // ...
       CATCH oError
          // ...
       END
    RETURN cResult

`LOCAL` dopo qualsiasi istruzione = errore di compilazione.

`STATIC` a livello di file deve venire PRIMA del primo `FUNCTION`/`PROCEDURE`.

## Confronto tra stringhe — sempre `==`, mai `!=`

Il default `SET EXACT OFF` fa sì che `!=` faccia un confronto di prefisso:

    "abc" != "ab"   // .F. !!  ("ab" è prefisso di "abc")
    "abc" == "ab"   // .F.     corretto

Regola: usa `==` per l'uguaglianza. Usa `!Empty(str) .AND. str == other` per il confronto con guardia.

## Non esiste `hb_UnixTime()`

Non esiste — errore di linker. Usa:

    nNow := Int( hb_TToSec( hb_DateTime() ) )

## `hb_AIns` ha bisogno di 4 argomenti per crescere l'array

    hb_AIns( aArr, nPos, xVal, .T. )   // ← il .T. lo fa crescere
    hb_AIns( aArr, nPos )              // sbagliato — l'array non cresce, l'ultimo elemento va perso

## `hb_DirExists` e il backslash finale su Windows

    hb_DirExists( "C:\path\" )      // .F. anche se esiste!
    hb_DirExists( "C:\path"  )      // .T.

Togli il separatore finale prima di controllare:

    IF Right( cPath, 1 ) $ "\/"
       cPath := hb_StrShrink( cPath, 1 )
    ENDIF
    IF hb_DirExists( cPath )
       // ...
    ENDIF

## `TRY/CATCH/FINALLY`

    LOCAL oError

    TRY
       // rischioso
    CATCH oError
       le( "Errore: " + oError:description )
    FINALLY
       // viene eseguito sempre (cleanup)
    END

Definito tramite `#xcommand`:

    #xcommand TRY     => BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }
    #xcommand CATCH [<!oErr!>] => RECOVER [USING <oErr>] <-oErr->
    #xcommand FINALLY => ALWAYS

`oError` deve essere dichiarato LOCAL in cima alla funzione.

## Codeblock nelle action delle route

`bAction := {|| ... }` — senza parametri. La request è thread-local, letta tramite `U*`.

    // CORRETTO
    oSrv:AddRouteGet( "x", "/x", {|| USendJson( {=>} ) } )

    // SBAGLIATO — oReq non è nello scope della closure
    oSrv:AddRouteGet( "x", "/x", {|oReq| oReq:Respond( {=>}, 200, "json" ) } )

## Alias e case

Gli alias DBF devono essere UPPER quando referenziati con la sintassi alias:

    USE "data/users" ALIAS "USERS"
    ? USERS->name       // OK
    ? Users->name       // errore a runtime

## Letterale hash vs hash vuoto

    { => }             // hash vuoto (sintassi Harbour)
    { "k" => "v" }     // hash con una chiave
    { }                // array VUOTO (tipo diverso!)

`hb_HKeys(h)`, `hb_HValues(h)`, `hb_HHasKey(h,k)`, `hb_HGetDef(h,k,def)`.

## Numero ↔ stringa

    hb_NToS( 42 )       // "42"
    Val( "42" )         // 42
    Str( 3.14, 6, 2 )   // "  3.14"  (larghezza, decimali)
    LTrim( Str( n ) )   // numero senza spazi iniziali

## Data ↔ stringa

    DToC( d )           // usa SET DATE
    CToD( "31/12/2026" )
    hb_DToC( d, "YYYY-MM-DD" )
    Date()              // oggi

## Compilazione

`hbmk2` legge un file di progetto `.hbp`. Flag comuni:
- `-hbx=foo.hbx` — rigenera l'indice degli header (auto dopo i rename)
- `-gtwvw` / `-gtwin` — modalità GUI/console
- `-b` — informazioni di debug
- Path di inclusione tramite `-i<dir>`, librerie tramite `-l<name>`

Non modificare mai `.hbx` a mano — è auto-generato.

## Log / debug in HIX

    #include "hix_logger.ch"

    ld( "debug msg" )    // DEBUG
    l(  "info msg"  )    // INFO
    lw( "warn msg"  )    // WARN
    le( "err msg"   )    // ERROR

Inizializza una volta al boot:

    HIX_LoggerInit( "logs/app.log", HIX_LOG_DEBUG, .T. )   // .T. = anche su console

## Formato di output per i test runner

Se scrivi il tuo test harness parsato da un runner esterno, stampa esattamente:

    OutStd( hb_eol() + "Tests: " + hb_NToS(nTot) + " total | " + ;
            hb_NToS(nPass) + " passed | " + hb_NToS(nFail) + " failed" + hb_eol() )
    OutStd( "End test..." + hb_eol() )

La regex è `\d+ total \| \d+ passed \| \d+ failed`.
