# Controllers

Un controller es un fichero `.prg` bajo `www/controllers/` que expone funciones a las que las acciones de ruta despachan.

## Convención de nombres

Acción `users@list` → función `_UsersList()` en `www/controllers/users.prg` (guion bajo inicial + PascalCase).

Alternativa: la función `UsersList()` (sin guion bajo) también funciona — el dispatcher prueba ambas.

## Anatomía

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
          RETURN USendError( 404, "Usuario no encontrado" )
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

## Reglas

1. `LOCAL` primero — siempre al principio de la función, antes de cualquier código ejecutable (Harbour da error de compilación si no).
2. Responde con `U*` — nunca con `oReq:Respond()`.
3. Devuelve `NIL` — los controllers no retornan nada significativo; el helper `U*` ya envió la respuesta.
4. Nada de trabajo prolongado — para streams usa SSE (`USendStreamStart`).

## Leer entrada

    LOCAL cName := UPost( "name", "" )        // form POST / clave del body JSON
    LOCAL nPage := Val( UGet( "page", "1" ) ) // Query string ?page=N
    LOCAL nId   := Val( UParam( "id", "0" ) ) // :var de ruta
    LOCAL cAuth := UHeader( "Authorization", "" )
    LOCAL cJwt  := UCookie( "jwt", "" )
    LOCAL hBody := UJson()                    // Body JSON completo como hash/array
    LOCAL cRaw  := UBody()                    // Body en bruto

Helpers de tipo/negociación:

    UMethod()      UPath()      UQuery()
    UIsGet()       UIsPost()    UIsAjax()
    UIsJson()      UWantsJson() UIsForm()      UIsMultipart()
    UIsHttps()     UScheme()    UIP()  UHost()  UPort()

Subidas:

    LOCAL aFiles := UFiles()   // array de { "name", "data", "mime", "size" }

## Responder

    USendJson( xData )                // 200 JSON (hash, array o string ya codificado)
    USendJson( xData, 201 )
    USendHtml( cHtml )
    USendHtml( cHtml, 201 )
    USendText( cText )
    USendEmpty()                      // 204
    USendError( 404, "No encontrado" )
    URedirect( "/login" )
    URedirect( "/perm", 301 )
    USendView( "users.list.view.html", { "aRows" => aRows } )

Respuesta con buffer (control fino):

    USetStatus( 201 )
    USetMime( "json" )
    USetHeader( "X-Request-Id", cReqId )
    UWrite( hb_jsonEncode( hResp ) )
    // el dispatcher hace flush cuando la acción retorna

## Manejo de errores

    LOCAL oError

    TRY
       // código que puede fallar
    CATCH oError
       le( "Controller error: " + oError:description )
       RETURN USendError( 500, oError:description )
    END
    RETURN NIL

## Vistas

Ver `05_views.md`. El controller pasa un hash de variables a la plantilla:

    USendView( "users.list.view.html", { "cTitle" => "Usuarios", "aRows" => aRows } )
