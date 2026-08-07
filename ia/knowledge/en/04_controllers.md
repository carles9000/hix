# Controllers

A controller is a `.prg` file under `www/controllers/` exposing functions that route actions dispatch to.

## Naming convention

Route action `users@list` → function `_UsersList()` in `www/controllers/users.prg` (leading underscore + PascalCase).

Alternative: function `UsersList()` (no underscore) also works — dispatcher tries both.

## Anatomy

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

## Rules

1. `LOCAL` first — always at the top of the function, before any executable code (Harbour compile error otherwise).
2. Respond with `U*` — never `oReq:Respond()`.
3. Return `NIL` — controllers return nothing meaningful; the U helper already sent the response.
4. Never long-running work — for streams use SSE (`USendStreamStart`).

## Reading input

    LOCAL cName := UPost( "name", "" )        // POST form / JSON body key
    LOCAL nPage := Val( UGet( "page", "1" ) ) // Query string ?page=N
    LOCAL nId   := Val( UParam( "id", "0" ) ) // Route :var
    LOCAL cAuth := UHeader( "Authorization", "" )
    LOCAL cJwt  := UCookie( "jwt", "" )
    LOCAL hBody := UJson()                    // Full JSON body as hash/array
    LOCAL cRaw  := UBody()                    // Raw body string

Type/negotiation helpers:

    UMethod()      UPath()      UQuery()
    UIsGet()       UIsPost()    UIsAjax()
    UIsJson()      UWantsJson() UIsForm()      UIsMultipart()
    UIsHttps()     UScheme()    UIP()  UHost()  UPort()

Uploads:

    LOCAL aFiles := UFiles()   // array of { "name", "data", "mime", "size" }

## Responding

    USendJson( xData )                // 200 JSON (hash, array, or already-encoded string)
    USendJson( xData, 201 )
    USendHtml( cHtml )
    USendHtml( cHtml, 201 )
    USendText( cText )
    USendEmpty()                      // 204
    USendError( 404, "Not found" )
    URedirect( "/login" )
    URedirect( "/perm", 301 )
    USendView( "users.list.view.html", { "aRows" => aRows } )

Buffered response (for fine-grained control):

    USetStatus( 201 )
    USetMime( "json" )
    USetHeader( "X-Request-Id", cReqId )
    UWrite( hb_jsonEncode( hResp ) )
    // dispatcher flushes when the action returns

## Error handling

    LOCAL oError

    TRY
       // risky code
    CATCH oError
       le( "Controller error: " + oError:description )
       RETURN USendError( 500, oError:description )
    END
    RETURN NIL

## Views

See `05_views.md`. Controllers pass a hash of variables to the template:

    USendView( "users.list.view.html", { "cTitle" => "Users", "aRows" => aRows } )
