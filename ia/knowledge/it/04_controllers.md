# Controller

Un controller è un file `.prg` sotto `www/controllers/` che espone funzioni a cui le action delle route dispatchano.

## Convenzione di naming

Action di route `users@list` → funzione `_UsersList()` in `www/controllers/users.prg` (underscore iniziale + PascalCase).

Alternativa: la funzione `UsersList()` (senza underscore) funziona anch'essa — il dispatcher prova entrambe.

## Anatomia

    /*-----------------------------------------------------------
      File ......: users.prg
      Author.....: Charly 9000
      Created....: 2026-08-01
      Description: Users controller (list, create, show, update, delete)
    -----------------------------------------------------------*/

    #include "hix_const.ch"
    #include "hix_logger.ch"

    FUNCTION _UsersList()
       LOCAL aRows := UsersModelList()
       USendJson( aRows )
    RETURN NIL

    FUNCTION _UsersShow()
       LOCAL nId  := Val( UParam( "id", "0" ) )
       LOCAL hRow := UsersModelGet( nId )

       IF Empty( hRow )
          RETURN USendError( 404, "User not found" )
       ENDIF
    RETURN USendJson( hRow )

    FUNCTION _UsersCreate()
       LOCAL oVal := UValidateOrFail( { ;
          "name"  => "required|string|max:100", ;
          "email" => "required|string|email"    ;
       } )
       IF oVal == NIL ; RETURN NIL ; ENDIF

       LOCAL nId := UsersModelCreate( oVal:Get("name"), oVal:Get("email") )
    RETURN USendJson( { "id" => nId }, 201 )

## Regole

1. `LOCAL` per primo — sempre in cima alla funzione, prima di qualsiasi codice eseguibile (errore di compilazione Harbour altrimenti).
2. Rispondi con `U*` — mai `oReq:Respond()`.
3. Ritorna `NIL` — i controller non ritornano nulla di significativo; l'helper U ha già inviato la risposta.
4. Mai lavori lunghi — per gli stream usa SSE (`USendStreamStart`).

## Lettura dell'input

    LOCAL cName := UPost( "name", "" )        // campo POST form / JSON body
    LOCAL nPage := Val( UGet( "page", "1" ) ) // query string ?page=N
    LOCAL nId   := Val( UParam( "id", "0" ) ) // route :var
    LOCAL cAuth := UHeader( "Authorization", "" )
    LOCAL cJwt  := UCookie( "jwt", "" )
    LOCAL hBody := UJson()                    // body JSON intero come hash/array
    LOCAL cRaw  := UBody()                    // body raw come stringa

Helper di tipo/negoziazione:

    UMethod()      UPath()      UQuery()
    UIsGet()       UIsPost()    UIsAjax()
    UIsJson()      UWantsJson() UIsForm()      UIsMultipart()
    UIsHttps()     UScheme()    UIP()  UHost()  UPort()

Upload:

    LOCAL aFiles := UFiles()   // array di { "name", "data", "mime", "size" }

## Rispondere

    USendJson( xData )                // 200 JSON (hash, array, o stringa già codificata)
    USendJson( xData, 201 )
    USendHtml( cHtml )
    USendHtml( cHtml, 201 )
    USendText( cText )
    USendEmpty()                      // 204
    USendError( 404, "Not found" )
    URedirect( "/login" )
    URedirect( "/perm", 301 )
    USendView( "users.list.view.html", { "aRows" => aRows } )

Risposta bufferizzata (per controllo fine-grained):

    USetStatus( 201 )
    USetMime( "json" )
    USetHeader( "X-Request-Id", cReqId )
    UWrite( hb_jsonEncode( hResp ) )
    // il dispatcher fa il flush quando l'action ritorna

## Gestione degli errori

    LOCAL oError

    TRY
       // codice rischioso
    CATCH oError
       le( "Controller error: " + oError:description )
       RETURN USendError( 500, oError:description )
    END
    RETURN NIL

## View

Vedi `05_views.md`. I controller passano un hash di variabili al template:

    USendView( "users.list.view.html", { "cTitle" => "Users", "aRows" => aRows } )
