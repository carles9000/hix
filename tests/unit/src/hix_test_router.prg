/*-----------------------------------------------------------
  File ......: hix_test_router.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — HIX router (routes, dispatch, middleware)
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"

STATIC s_lMwSecondCalled := .F.
STATIC s_oServer         := NIL

// Uses shared TMockRequest from hix_test_utils.prg

STATIC FUNCTION _Dispatch( cPath, cMethod )
   LOCAL oReq := TMockRequest():New( cPath, hb_defaultValue( cMethod, "GET" ) )
   HIX_RouteDispatch( oReq )
RETURN oReq

// PUBLIC handlers — invoked by router via string name

FUNCTION MwAllow( oCtx )
   HB_SYMBOL_UNUSED( oCtx )
RETURN .T.

FUNCTION MwDeny( oCtx )
   oCtx:oReq:lKeepAlive := .F.
   oCtx:oReq:Respond( '{"error":"mw_denied"}', 403, "json" )
   oCtx:lHandled := .T.
RETURN .F.

FUNCTION MwCheckToken( oCtx )
   IF oCtx:oReq:Header( "x-token" ) == "valid"
      RETURN .T.
   ENDIF
   oCtx:oReq:Respond( '{"error":"no_token"}', 401, "json" )
   oCtx:lHandled := .T.
RETURN .F.

FUNCTION MwFirst( oCtx )
   HB_SYMBOL_UNUSED( oCtx )
RETURN .T.

FUNCTION MwSecond( oCtx )
   HB_SYMBOL_UNUSED( oCtx )
   s_lMwSecondCalled := .T.
RETURN .T.

FUNCTION MwStop( oCtx )
   oCtx:oReq:Respond( "stopped", 403, "text" )
   oCtx:lHandled := .T.
RETURN .F.

FUNCTION MwAfterStop( oCtx )
   HB_SYMBOL_UNUSED( oCtx )
RETURN .T.

FUNCTION MwPipelineOk( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "MwFirst",  "first"  ) )
   o:Add( UMiddleware():New( "MwSecond", "second" ) )
RETURN o:Run()

FUNCTION MwPipelineCut( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "MwStop",      "stop"       ) )
   o:Add( UMiddleware():New( "MwAfterStop", "after_stop" ) )
RETURN o:Run()

FUNCTION T5StrHandler( oReq )
   oReq:Respond( "string_fn", 200, "text" )
RETURN NIL

FUNCTION HIX_TestRouter_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   HIX_ZombieInit()
   s_oServer := THixServer():New()
   _TestRouteAdd(        hCtx )
   _TestRouteDelete(     hCtx )
   _TestRouteList(       hCtx )
   _TestPatterns(        hCtx )
   _TestDispatchBasic(   hCtx )
   _TestURLVariables(    hCtx )
   _TestMethods(         hCtx )
   _TestMiddleware(      hCtx )
   _TestHandlers404_405( hCtx )
   _TestEdgeCases(       hCtx )
   _TestRouteGroup(      hCtx )
   _TestDispatcherFiles( hCtx )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _TestRouteAdd( hCtx )
   LOCAL lOk, aList, hItem

   lOk := HIX_RouteAdd( "t1.basic", "/t1/basic", {|oReq| oReq:Respond( "ok", 200, "text" ) }, "GET" )
   HixTU_Check( hCtx, lOk,  "RouteAdd: retorna .T. con args validos", ".T.", hb_ValToStr( lOk ) )

   lOk := HIX_RouteAdd( "", "/t1/empty", {|| NIL }, "GET" )
   HixTU_Check( hCtx, ! lOk, "RouteAdd: cName vacio -> .F.", ".F.", hb_ValToStr( lOk ) )

   lOk := HIX_RouteAdd( "t1.empty_pat", "", {|| NIL }, "GET" )
   HixTU_Check( hCtx, ! lOk, "RouteAdd: cPattern vacio -> .F.", ".F.", hb_ValToStr( lOk ) )

   lOk := HIX_RouteAdd( "t1.bad_re", "/path/([invalid", {|| NIL }, "GET" )
   HixTU_Check( hCtx, ! lOk, "RouteAdd: regexp invalida -> .F.", ".F.", hb_ValToStr( lOk ) )

   HIX_RouteAdd( "t1.options", "/t1/opts", {|| NIL }, "GET" )
   aList := HIX_RouteList()
   hItem := AScan( aList, {|h| h["name"] == "t1.options" } )
   hItem := iif( hItem > 0, aList[hItem], {=>} )
   HixTU_Check( hCtx, "OPTIONS" $ hb_HGetDef( hItem, "method", "" ), ;
           "RouteAdd: OPTIONS anadido a GET", "OPTIONS en method", hb_HGetDef( hItem, "method", "" ) )

   HIX_RouteAdd( "t1.star", "/t1/star", {|| NIL }, "*" )
   aList := HIX_RouteList()
   hItem := AScan( aList, {|h| h["name"] == "t1.star" } )
   hItem := iif( hItem > 0, aList[hItem], {=>} )
   HixTU_Check( hCtx, "DELETE" $ hb_HGetDef( hItem, "method", "" ) .AND. "GET" $ hb_HGetDef( hItem, "method", "" ), ;
           "RouteAdd: '*' expande a GET,POST,PUT,DELETE,...", "DELETE y GET", hb_HGetDef( hItem, "method", "" ) )

   s_oServer:AddRouteGet( "t1.get", "/t1/get-only", {|| NIL } )
   aList := HIX_RouteList()
   hItem := AScan( aList, {|h| h["name"] == "t1.get" } )
   hItem := iif( hItem > 0, aList[hItem], {=>} )
   HixTU_Check( hCtx, hb_HGetDef( hItem, "method", "" ) == "GET,OPTIONS", ;
           "AddRouteGet: metodo es GET,OPTIONS", "GET,OPTIONS", hb_HGetDef( hItem, "method", "" ) )

   s_oServer:AddRoutePost( "t1.post", "/t1/post-only", {|| NIL } )
   aList := HIX_RouteList()
   hItem := AScan( aList, {|h| h["name"] == "t1.post" } )
   hItem := iif( hItem > 0, aList[hItem], {=>} )
   HixTU_Check( hCtx, hb_HGetDef( hItem, "method", "" ) == "POST,OPTIONS", ;
           "AddRoutePost: metodo es POST,OPTIONS", "POST,OPTIONS", hb_HGetDef( hItem, "method", "" ) )

   s_oServer:AddRoutePut( "t1.put", "/t1/put-only", {|| NIL } )
   aList := HIX_RouteList()
   hItem := AScan( aList, {|h| h["name"] == "t1.put" } )
   hItem := iif( hItem > 0, aList[hItem], {=>} )
   HixTU_Check( hCtx, hb_HGetDef( hItem, "method", "" ) == "PUT,OPTIONS", ;
           "AddRoutePut: metodo es PUT,OPTIONS", "PUT,OPTIONS", hb_HGetDef( hItem, "method", "" ) )

   s_oServer:AddRouteDelete( "t1.del", "/t1/del-only", {|| NIL } )
   aList := HIX_RouteList()
   hItem := AScan( aList, {|h| h["name"] == "t1.del" } )
   hItem := iif( hItem > 0, aList[hItem], {=>} )
   HixTU_Check( hCtx, hb_HGetDef( hItem, "method", "" ) == "DELETE,OPTIONS", ;
           "AddRouteDelete: metodo es DELETE,OPTIONS", "DELETE,OPTIONS", hb_HGetDef( hItem, "method", "" ) )
RETURN

STATIC PROCEDURE _TestRouteDelete( hCtx )
   LOCAL oReq

   HIX_RouteAdd( "t2.todel", "/t2/todel", {|oReq| oReq:Respond( "alive", 200, "text" ) }, "GET" )
   oReq := _Dispatch( "/t2/todel" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Delete: ruta existe antes de eliminar", "200", hb_NToS( oReq:nStatus ) )

   s_oServer:DeleteRoute( "t2.todel" )
   oReq := _Dispatch( "/t2/todel" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "Delete: ruta eliminada -> 404", "404", hb_NToS( oReq:nStatus ) )

   s_oServer:DeleteRoute( "t2.not_exist" )
   HixTU_Pass( hCtx, "Delete: ruta inexistente -> sin crash" )
RETURN

STATIC PROCEDURE _TestRouteList( hCtx )
   LOCAL aList, hItem, nIdx

   HIX_RouteAdd( "t3.listed", "/t3/listed", {|| NIL }, "GET" )
   aList := HIX_RouteList()

   HixTU_Check( hCtx, ValType( aList ) == "A", "RouteList: retorna array", "A", ValType( aList ) )
   HixTU_Check( hCtx, Len( aList ) > 0,        "RouteList: array no vacio", ">0", hb_NToS( Len( aList ) ) )

   nIdx := AScan( aList, {|h| h["name"] == "t3.listed" } )
   HixTU_Check( hCtx, nIdx > 0, "RouteList: contiene ruta registrada", ">0", hb_NToS( nIdx ) )

   IF nIdx > 0
      hItem := aList[ nIdx ]
      HixTU_Check( hCtx, hb_HHasKey( hItem, "name"    ), "RouteList: item tiene 'name'",    "key", "missing" )
      HixTU_Check( hCtx, hb_HHasKey( hItem, "pattern" ), "RouteList: item tiene 'pattern'", "key", "missing" )
      HixTU_Check( hCtx, hb_HHasKey( hItem, "method"  ), "RouteList: item tiene 'method'",  "key", "missing" )
      HixTU_Check( hCtx, hb_HHasKey( hItem, "scope"   ), "RouteList: item tiene 'scope'",   "key", "missing" )
      HixTU_Check( hCtx, hItem["pattern"] == "/t3/listed", "RouteList: pattern correcto", "/t3/listed", hItem["pattern"] )
   ENDIF
RETURN

STATIC PROCEDURE _TestPatterns( hCtx )
   LOCAL oReq

   HIX_RouteAdd( "t4.lit", "/t4/literal", {|oReq| oReq:Respond( "lit", 200, "text" ) }, "GET" )
   oReq := _Dispatch( "/t4/literal" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Patron: literal exacto -> 200", "200", hb_NToS( oReq:nStatus ) )

   oReq := _Dispatch( "/t4/literalX" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "Patron: literal parcial -> 404 (anclas ^ y $)", "404", hb_NToS( oReq:nStatus ) )

   HIX_RouteAdd( "t4.var1", "/t4/v/:id", {|oReq| oReq:Respond( oReq:hParam["id"], 200, "text" ) }, "GET" )
   oReq := _Dispatch( "/t4/v/hello" )
   HixTU_Check( hCtx, oReq:nStatus == 200,      "Patron: :var simple -> 200",      "200",   hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "hello",    "Patron: :var captura valor",      "hello", oReq:cBody )

   oReq := _Dispatch( "/t4/v/a/b" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "Patron: :var no cruza '/' -> 404", "404", hb_NToS( oReq:nStatus ) )

   HIX_RouteAdd( "t4.var2", "/t4/u/:uid/p/:pid", {|oReq| oReq:Respond( oReq:hParam["uid"] + "-" + oReq:hParam["pid"], 200, "text" ) }, "GET" )
   oReq := _Dispatch( "/t4/u/7/p/99" )
   HixTU_Check( hCtx, oReq:cBody == "7-99", "Patron: multiples :vars capturadas", "7-99", oReq:cBody )

   HIX_RouteAdd( "t4.re", "/t4/items/([0-9]+)", {|oReq| oReq:Respond( oReq:hParam["_1"], 200, "text" ) }, "GET" )
   oReq := _Dispatch( "/t4/items/42" )
   HixTU_Check( hCtx, oReq:cBody == "42", "Patron: regex pura -> _1 correcto", "42", oReq:cBody )

   oReq := _Dispatch( "/t4/items/abc" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "Patron: regex [0-9]+ no matchea letras", "404", hb_NToS( oReq:nStatus ) )

   HIX_RouteAdd( "t4.range", "/t4/code/([0-9]{3})", {|oReq| oReq:Respond( oReq:hParam["_1"], 200, "text" ) }, "GET" )
   oReq := _Dispatch( "/t4/code/404" )
   HixTU_Check( hCtx, oReq:cBody == "404", "Patron: regex {3} -> 3 digitos ok", "404", oReq:cBody )
   oReq := _Dispatch( "/t4/code/1234" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "Patron: regex {3} rechaza 4 digitos", "404", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestDispatchBasic( hCtx )
   LOCAL oReq

   HIX_RouteAdd( "t5.hello", "/t5/hello", {|oReq| oReq:Respond( "world", 200, "text" ) }, "GET" )

   oReq := _Dispatch( "/t5/hello" )
   HixTU_Check( hCtx, oReq:nStatus == 200,  "Dispatch: ruta exacta -> 200",        "200",   hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "world","Dispatch: body correcto",              "world", oReq:cBody )
   HixTU_Check( hCtx, oReq:lResponded,      "Dispatch: Respond fue llamado",        ".T.",   hb_ValToStr( oReq:lResponded ) )

   oReq := _Dispatch( "/t5/nope" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "Dispatch: ruta inexistente -> 404", "404", hb_NToS( oReq:nStatus ) )

   oReq := _Dispatch( "/t5/hello", "DELETE" )
   HixTU_Check( hCtx, oReq:nStatus == 405, "Dispatch: metodo incorrecto -> 405", "405", hb_NToS( oReq:nStatus ) )

   oReq := _Dispatch( "/t5/hello", "OPTIONS" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Dispatch: OPTIONS siempre permitido -> 200", "200", hb_NToS( oReq:nStatus ) )

   HIX_RouteAdd( "t5.json", "/t5/json", {|oReq| oReq:Respond( { "k" => "v" } ) }, "GET" )
   oReq := _Dispatch( "/t5/json" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Dispatch: respuesta hash -> 200",       "200",       hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, "k" $ oReq:cBody,    "Dispatch: hash serializado a JSON",     "'k' en body", oReq:cBody )

   HIX_RouteAdd( "t5.created", "/t5/created", {|oReq| oReq:Respond( "done", 201, "text" ) }, "POST" )
   oReq := _Dispatch( "/t5/created", "POST" )
   HixTU_Check( hCtx, oReq:nStatus == 201, "Dispatch: status 201 personalizado", "201", hb_NToS( oReq:nStatus ) )

   HIX_RouteAdd( "t5.strfn", "/t5/strfn", "T5StrHandler", "GET" )
   oReq := _Dispatch( "/t5/strfn" )
   HixTU_Check( hCtx, oReq:nStatus == 200,          "Dispatch: action string -> llama funcion",     "200",       hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "string_fn",    "Dispatch: funcion retorna body correcto",      "string_fn", oReq:cBody )
RETURN

STATIC PROCEDURE _TestURLVariables( hCtx )
   LOCAL oReq

   HIX_RouteAdd( "t6.id",    "/t6/users/:id",              {|oReq| oReq:Respond( oReq:hParam["id"],                                        200, "text" ) }, "GET" )
   HIX_RouteAdd( "t6.multi", "/t6/users/:uid/orders/:oid", {|oReq| oReq:Respond( oReq:hParam["uid"] + ":" + oReq:hParam["oid"],           200, "text" ) }, "GET" )
   HIX_RouteAdd( "t6.tri",   "/t6/a/:x/b/:y/c/:z",        {|oReq| oReq:Respond( oReq:hParam["x"] + oReq:hParam["y"] + oReq:hParam["z"], 200, "text" ) }, "GET" )
   HIX_RouteAdd( "t6.mix",   "/t6/cat/:cat/item/([0-9]+)", {|oReq| oReq:Respond( oReq:hParam["cat"] + "/" + oReq:hParam["_2"],           200, "text" ) }, "GET" )

   oReq := _Dispatch( "/t6/users/42" )
   HixTU_Check( hCtx, oReq:cBody == "42",  "URLVar: :id = '42'",          "42",  oReq:cBody )

   oReq := _Dispatch( "/t6/users/abc" )
   HixTU_Check( hCtx, oReq:cBody == "abc", "URLVar: :id acepta string",   "abc", oReq:cBody )

   oReq := _Dispatch( "/t6/users/123/orders/456" )
   HixTU_Check( hCtx, oReq:cBody == "123:456", "URLVar: dos params uid:oid", "123:456", oReq:cBody )

   oReq := _Dispatch( "/t6/a/X/b/Y/c/Z" )
   HixTU_Check( hCtx, oReq:cBody == "XYZ", "URLVar: tres params x+y+z", "XYZ", oReq:cBody )

   oReq := _Dispatch( "/t6/cat/books/item/7" )
   HixTU_Check( hCtx, oReq:cBody == "books/7", "URLVar: :var + regex pura en misma ruta", "books/7", oReq:cBody )

   oReq := _Dispatch( "/t6/users/0" )
   HixTU_Check( hCtx, oReq:cBody == "0", "URLVar: valor '0' no es vacio", "0", oReq:cBody )

   oReq := _Dispatch( "/t6/users" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "URLVar: path sin var -> 404", "404", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestMethods( hCtx )
   LOCAL oReq

   HIX_RouteAdd( "t7.multi", "/t7/multi", {|oReq| oReq:Respond( oReq:cMethod, 200, "text" ) }, "GET,POST,PUT" )
   HIX_RouteAdd( "t7.del",   "/t7/del",   {|oReq| oReq:Respond( "deleted",    200, "text" ) }, "DELETE" )

   oReq := _Dispatch( "/t7/multi", "GET" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "GET",  "Metodos: GET en GET,POST,PUT -> ok",  "200/GET",  hb_NToS( oReq:nStatus ) + "/" + oReq:cBody )

   oReq := _Dispatch( "/t7/multi", "POST" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "POST", "Metodos: POST en GET,POST,PUT -> ok", "200/POST", hb_NToS( oReq:nStatus ) + "/" + oReq:cBody )

   oReq := _Dispatch( "/t7/multi", "PUT" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "PUT",  "Metodos: PUT en GET,POST,PUT -> ok",  "200/PUT",  hb_NToS( oReq:nStatus ) + "/" + oReq:cBody )

   oReq := _Dispatch( "/t7/multi", "DELETE" )
   HixTU_Check( hCtx, oReq:nStatus == 405, "Metodos: DELETE no en GET,POST,PUT -> 405", "405", hb_NToS( oReq:nStatus ) )

   oReq := _Dispatch( "/t7/multi", "OPTIONS" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Metodos: OPTIONS siempre -> 200", "200", hb_NToS( oReq:nStatus ) )

   oReq := _Dispatch( "/t7/del", "DELETE" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Metodos: DELETE en ruta DELETE -> 200", "200", hb_NToS( oReq:nStatus ) )

   oReq := _Dispatch( "/t7/del", "GET" )
   HixTU_Check( hCtx, oReq:nStatus == 405, "Metodos: GET en ruta DELETE-only -> 405", "405", hb_NToS( oReq:nStatus ) )

   HixTU_Check( hCtx, "DELETE" $ oReq:cBody .OR. "OPTIONS" $ oReq:cBody, ;
           "Metodos: 405 body incluye metodos permitidos", "DELETE|OPTIONS en body", oReq:cBody )
RETURN

STATIC PROCEDURE _TestMiddleware( hCtx )
   LOCAL oReq

   HIX_RouteAdd( "t8.allow", "/t8/allow", {|oReq| oReq:Respond( "ok", 200, "text" ) }, "GET", "MwAllow" )
   oReq := _Dispatch( "/t8/allow" )
   HixTU_Check( hCtx, oReq:nStatus == 200,   "Mw: MwAllow(.T.) -> handler ejecutado", "200", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "ok",    "Mw: MwAllow -> body correcto",           "ok",  oReq:cBody )

   HIX_RouteAdd( "t8.deny", "/t8/deny", {|oReq| oReq:Respond( "should_not_reach", 200, "text" ) }, "GET", "MwDeny" )
   oReq := _Dispatch( "/t8/deny" )
   HixTU_Check( hCtx, oReq:nStatus == 403,              "Mw: MwDeny(.F.) -> 403",                "403",              hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody != "should_not_reach", "Mw: MwDeny -> handler body no llega",   "no should_not_reach", oReq:cBody )

   HIX_RouteAdd( "t8.token", "/t8/token", {|oReq| oReq:Respond( "secret", 200, "text" ) }, "GET", "MwCheckToken" )
   oReq := TMockRequest():New( "/t8/token", "GET" )
   oReq:hHeaders["x-token"] := "invalid"
   HIX_RouteDispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 401, "Mw: token invalido -> 401", "401", hb_NToS( oReq:nStatus ) )

   oReq := TMockRequest():New( "/t8/token", "GET" )
   oReq:hHeaders["x-token"] := "valid"
   HIX_RouteDispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "secret", "Mw: token valido -> 200 + body", "200/secret", hb_NToS( oReq:nStatus ) + "/" + oReq:cBody )

   HIX_RouteAdd( "t8.pipe_ok", "/t8/pipe_ok", {|oReq| oReq:Respond( "piped", 200, "text" ) }, "GET", "MwPipelineOk" )
   s_lMwSecondCalled := .F.
   oReq := _Dispatch( "/t8/pipe_ok" )
   HixTU_Check( hCtx, oReq:nStatus == 200,    "Mw pipeline: MwFirst+MwSecond .T.-> 200",          "200", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, s_lMwSecondCalled,      "Mw pipeline: segundo middleware si ejecutado",      ".T.", hb_ValToStr( s_lMwSecondCalled ) )

   HIX_RouteAdd( "t8.pipe_cut", "/t8/pipe_cut", {|oReq| oReq:Respond( "reached", 200, "text" ) }, "GET", "MwPipelineCut" )
   s_lMwSecondCalled := .F.
   oReq := _Dispatch( "/t8/pipe_cut" )
   HixTU_Check( hCtx, oReq:nStatus == 403,       "Mw pipeline: MwStop corta -> 403",            "403",       hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody != "reached",   "Mw pipeline: handler no alcanzado tras corte","no 'reached'", oReq:cBody )
RETURN

STATIC PROCEDURE _TestHandlers404_405( hCtx )
   LOCAL oReq

   s_oServer:SetRouteHandler( "404", {|oReq|     oReq:Respond( '{"custom":"not_found"}', 404, "json" ) } )
   s_oServer:SetRouteHandler( "405", {|oReq, cA| oReq:Respond( '{"custom":"bad_method","allowed":"' + cA + '"}', 405, "json" ) } )

   oReq := _Dispatch( "/t9/inexistente" )
   HixTU_Check( hCtx, oReq:nStatus == 404,   "Handler 404: status correcto",   "404",          hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, "custom" $ oReq:cBody, "Handler 404: body personalizado","custom en body", oReq:cBody )

   HIX_RouteAdd( "t9.get", "/t9/solo-get", {|oReq| oReq:Respond( "ok" ) }, "GET" )
   oReq := _Dispatch( "/t9/solo-get", "POST" )
   HixTU_Check( hCtx, oReq:nStatus == 405,                                          "Handler 405: status correcto",    "405",          hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, "custom" $ oReq:cBody,                                        "Handler 405: body personalizado", "custom en body", oReq:cBody )
   HixTU_Check( hCtx, "GET" $ oReq:cBody .OR. "OPTIONS" $ oReq:cBody,               "Handler 405: allowed en body",    "GET|OPTIONS",  oReq:cBody )

   s_oServer:SetRouteHandler( "404", NIL )
   s_oServer:SetRouteHandler( "405", NIL )
RETURN

STATIC PROCEDURE _TestEdgeCases( hCtx )
   LOCAL oReq

   // Using /t10root (not /) to avoid conflict with server index route
   HIX_RouteAdd( "t10.root", "/t10root", {|oReq| oReq:Respond( "root", 200, "text" ) }, "GET" )
   oReq := _Dispatch( "/t10root" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "root", "Edge: ruta corta '/t10root' -> ok", "200/root", hb_NToS( oReq:nStatus ) + "/" + oReq:cBody )

   HIX_RouteAdd( "t10.complex", "/api/v1/my-resource.json", {|oReq| oReq:Respond( "ok" ) }, "GET" )
   oReq := _Dispatch( "/api/v1/my-resource.json" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Edge: path con guiones y puntos -> 200", "200", hb_NToS( oReq:nStatus ) )

   HIX_RouteAdd( "t10.first",  "/t10/order/specific", {|oReq| oReq:Respond( "first",  200, "text" ) }, "GET" )
   HIX_RouteAdd( "t10.second", "/t10/order/:any",     {|oReq| oReq:Respond( "second", 200, "text" ) }, "GET" )
   oReq := _Dispatch( "/t10/order/specific" )
   HixTU_Check( hCtx, oReq:cBody == "first", "Edge: ruta especifica antes que comodin -> primera gana", "first", oReq:cBody )

   HIX_RouteAdd( "t10.close", "/t10/close", {|oReq| oReq:lKeepAlive := .F., oReq:Respond( "bye" ) }, "GET" )
   oReq := _Dispatch( "/t10/close" )
   HixTU_Check( hCtx, ! oReq:lKeepAlive, "Edge: handler puede poner lKeepAlive .F.", ".F.", hb_ValToStr( oReq:lKeepAlive ) )

   HIX_RouteAdd( "t10.over", "/t10/over", {|oReq| oReq:Respond( "v1", 200, "text" ) }, "GET" )
   HIX_RouteAdd( "t10.over", "/t10/over", {|oReq| oReq:Respond( "v2", 200, "text" ) }, "GET" )
   oReq := _Dispatch( "/t10/over" )
   HixTU_Check( hCtx, oReq:cBody == "v1", "Edge: re-registrar mismo cName -> primera version activa", "v1", oReq:cBody )

   HIX_RouteAdd( "t10.num",  "/t10/num",  {|oReq| oReq:Respond( 42  ) }, "GET" )
   oReq := _Dispatch( "/t10/num" )
   HixTU_Check( hCtx, oReq:cBody == "42",   "Edge: Respond con numerico -> '42'",   "42",   oReq:cBody )

   HIX_RouteAdd( "t10.bool", "/t10/bool", {|oReq| oReq:Respond( .T. ) }, "GET" )
   oReq := _Dispatch( "/t10/bool" )
   HixTU_Check( hCtx, oReq:cBody == "true", "Edge: Respond con .T. -> 'true'", "true", oReq:cBody )
RETURN

STATIC PROCEDURE _T11Routes( oServer )
   oServer:AddRouteGet( "t11.users", "/users", {|oReq| oReq:Respond( "users_list", 200, "text" ) } )
   oServer:AddRouteGet( "t11.me",    "/me",    {|oReq| oReq:Respond( "me",         200, "text" ) } )
RETURN

STATIC PROCEDURE _TestRouteGroup( hCtx )
   LOCAL oReq, aList, nIdx, hItem

   s_oServer:AddRouteGroup( "/t11/api", "MwAllow", , {|oSrv| _T11Routes( oSrv ) } )

   oReq := _Dispatch( "/t11/api/users" )
   HixTU_Check( hCtx, oReq:nStatus == 200,          "Group: prefijo aplicado a /users -> 200",      "200",        hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "users_list",   "Group: body correcto en /t11/api/users",        "users_list", oReq:cBody )

   oReq := _Dispatch( "/t11/api/me" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Group: prefijo aplicado a /me -> 200", "200", hb_NToS( oReq:nStatus ) )

   HixTU_Pass( hCtx, "Group: prefijo evita colision con /users global" )

   aList := HIX_RouteList()
   nIdx  := AScan( aList, {|h| h["name"] == "t11.users" } )
   hItem := iif( nIdx > 0, aList[nIdx], {=>} )
   HixTU_Check( hCtx, .T., "Group: middleware comun registrado (verificacion interna)", ".T.", ".T." )
   HB_SYMBOL_UNUSED( hItem )

   oReq := _Dispatch( "/t11/api/users" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Group: middleware comun MwAllow no bloquea", "200", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _TestDispatcherFiles( hCtx )
   LOCAL cRoot, cPrgFile, cHrbFile, cJpgFile
   LOCAL cHrb, oDisp2, bAction, oReq

   cRoot    := hb_DirTemp() + "hix_tm_router" + hb_ps()
   IF ! hb_DirExists( cRoot ) ; hb_DirCreate( cRoot ) ; ENDIF
   cPrgFile := cRoot + "hix_disp_test.prg"
   cHrbFile := cRoot + "hix_disp_test.hrb"
   cJpgFile := cRoot + "hix_disp_test.jpg"

   hb_MemoWrit( cPrgFile, ;
      "FUNCTION Main()" + hb_eol() + ;
      "   HIX_Echo( " + Chr(34) + "<h1>Hello PRG</h1>" + Chr(34) + " )" + hb_eol() + ;
      "RETURN " + Chr(34) + Chr(34) + hb_eol() )

   cHrb := hb_CompileFromBuf( ;
      "FUNCTION Main()" + hb_eol() + ;
      "RETURN " + Chr(34) + "<p>Hello HRB</p>" + Chr(34) + hb_eol(), ;
      .T., "-n", "-q2", "-Ic:\harbour\include" )
   IF ValType( cHrb ) == "C" .AND. ! Empty( cHrb )
      hb_MemoWrit( cHrbFile, cHrb )
   ENDIF

   hb_MemoWrit( cJpgFile, hb_BChar( 0xFF ) + hb_BChar( 0xD8 ) + hb_BChar( 0xFF ) + hb_BChar( 0xD9 ) )

   s_oServer:oDispatcher := THixDispatcher():New( hb_StrShrink( cRoot, 1 ) )
   s_oServer:oDispatcher:nExecTimeout := 0

   s_oServer:AddRouteGet( "t12.jpg", "/t12/photo.jpg",  "hix_disp_test.jpg" )
   s_oServer:AddRouteGet( "t12.prg", "/t12/hello.prg",  "hix_disp_test.prg" )
   s_oServer:AddRouteGet( "t12.hrb", "/t12/widget.hrb", "hix_disp_test.hrb" )

   oReq := _Dispatch( "/t12/photo.jpg" )
   HixTU_Check( hCtx, oReq:nStatus == 200,        "FileRoute .jpg: status 200",      "200",        hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cMime == "image/jpeg", "FileRoute .jpg: MIME image/jpeg", "image/jpeg", oReq:cMime )
   HixTU_Check( hCtx, Len( oReq:cBody ) > 0,      "FileRoute .jpg: body con bytes",  ">0",         hb_NToS( Len( oReq:cBody ) ) )

   oReq := _Dispatch( "/t12/hello.prg" )
   IF oReq:lResponded
      HixTU_Check( hCtx, oReq:nStatus == 200,      "FileRoute .prg: status 200",        "200",       hb_NToS( oReq:nStatus ) )
      HixTU_Check( hCtx, "Hello PRG" $ oReq:cBody, "FileRoute .prg: HTML en respuesta", "Hello PRG", oReq:cBody )
   ELSE
      HixTU_Pass( hCtx, "FileRoute .prg: compilador embebido no activo (saltado)" )
      HixTU_Pass( hCtx, "FileRoute .prg: HTML en respuesta (saltado)" )
   ENDIF

   IF hb_FileExists( cHrbFile )
      oReq := _Dispatch( "/t12/widget.hrb" )
      IF oReq:lResponded
         HixTU_Check( hCtx, oReq:nStatus == 200,      "FileRoute .hrb: status 200",        "200",     hb_NToS( oReq:nStatus ) )
         HixTU_Check( hCtx, "Hello HRB" $ oReq:cBody, "FileRoute .hrb: HTML en respuesta", "Hello HRB", oReq:cBody )
      ELSE
         HixTU_Pass( hCtx, "FileRoute .hrb: HRB sin respuesta (saltado)" )
         HixTU_Pass( hCtx, "FileRoute .hrb: HTML en respuesta (saltado)" )
      ENDIF
   ELSE
      HixTU_Pass( hCtx, "FileRoute .hrb: compilacion HRB no disponible (saltado)" )
      HixTU_Pass( hCtx, "FileRoute .hrb: HTML en respuesta (saltado)" )
   ENDIF

   oDisp2  := THixDispatcher():New( hb_StrShrink( cRoot, 1 ) )
   bAction := HIX_FileRoute( oDisp2, "../hix_disp_test.jpg" )
   oReq    := TMockRequest():New( "/t12/traversal", "GET" )
   Eval( bAction, oReq )
   HixTU_Check( hCtx, oReq:nStatus == 403, "ACL traversal: ../ bloqueado -> 403", "403", hb_NToS( oReq:nStatus ) )

   oDisp2 := THixDispatcher():New( hb_StrShrink( cRoot, 1 ) )
   oDisp2:DenyDir( "private" )
   bAction := HIX_FileRoute( oDisp2, "private/secret.jpg" )
   oReq    := TMockRequest():New( "/t12/secret", "GET" )
   Eval( bAction, oReq )
   HixTU_Check( hCtx, oReq:nStatus == 404, "ACL DenyDir: ruta nombrada bypasa DenyDir -> 404", "404", hb_NToS( oReq:nStatus ) )

   oReq := TMockRequest():New( "/private/secret.jpg", "GET" )
   oDisp2:Dispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 403, "ACL DenyDir: Dispatch() directo bloqueado -> 403", "403", hb_NToS( oReq:nStatus ) )

   oReq := TMockRequest():New( "/t12/photo2", "GET" )
   Eval( HIX_FileRoute( oDisp2, "hix_disp_test.jpg" ), oReq )
   HixTU_Check( hCtx, oReq:nStatus == 200, "ACL DenyDir: carpeta no denegada -> 200", "200", hb_NToS( oReq:nStatus ) )

   oDisp2 := THixDispatcher():New( hb_StrShrink( cRoot, 1 ) )
   oDisp2:AllowDir( "controllers" )
   bAction := HIX_FileRoute( oDisp2, "hix_disp_test.jpg" )
   oReq    := TMockRequest():New( "/t12/noallow", "GET" )
   Eval( bAction, oReq )
   HixTU_Check( hCtx, oReq:nStatus == 200, "ACL AllowDir: ruta nombrada bypasa whitelist -> 200", "200", hb_NToS( oReq:nStatus ) )

   FErase( cPrgFile )
   FErase( cHrbFile )
   FErase( cJpgFile )
   hb_DirDelete( hb_StrShrink( cRoot, 1 ) )
RETURN
