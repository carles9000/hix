/*-----------------------------------------------------------
  File ......: hix_test_load_routes.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — HIX_LoadRoutes and route management API
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"

// Uses shared TMockRequest from hix_test_utils.prg

// PUBLIC action functions — called by router via string name
FUNCTION LrAction1( oReq )
   oReq:Respond( "lr_action_1", 200, "text" )
RETURN NIL

FUNCTION LrAction2( oReq )
   oReq:Respond( "lr_action_2", 200, "text" )
RETURN NIL

FUNCTION LrReplace( oReq )
   oReq:Respond( "lr_replaced", 200, "text" )
RETURN NIL

FUNCTION LrWithVar( oReq )
   oReq:Respond( oReq:hParam[ "id" ], 200, "text" )
RETURN NIL

FUNCTION LrScopeCheck( oReq )
   LOCAL oCtx := hb_HGetDef( oReq:hData, "_ctx", NIL )
   oReq:Respond( iif( oCtx != NIL, oCtx:cScope, "no_scope" ), 200, "text" )
RETURN NIL

STATIC FUNCTION _RoutesDir()
RETURN "www" + hb_ps() + "routes"

STATIC FUNCTION _Dispatch( cPath, cMethod )
   LOCAL oReq := TMockRequest():New( cPath, hb_defaultValue( cMethod, "GET" ) )
   HIX_RouteDispatch( oReq )
RETURN oReq

STATIC FUNCTION _DispatchPost( cPath, hBody )
   LOCAL oReq := TMockRequest():New( cPath, "POST" )
   oReq:cRawBody := hb_jsonEncode( hBody )
   HIX_RouteDispatch( oReq )
RETURN oReq

STATIC PROCEDURE _WriteRouteJson( cFilename, aRoutes )
   LOCAL cDir := _RoutesDir()
   IF ! hb_DirExists( cDir ) ; hb_DirCreate( cDir ) ; ENDIF
   hb_MemoWrit( cDir + hb_ps() + cFilename, hb_jsonEncode( aRoutes ) )
RETURN

STATIC PROCEDURE _DeleteRouteJson( cFilename )
   LOCAL cPath := _RoutesDir() + hb_ps() + cFilename
   IF hb_FileExists( cPath ) ; hb_vfErase( cPath ) ; ENDIF
RETURN

STATIC PROCEDURE _CleanupRoutesDir()
   LOCAL cDir, aFiles, aFile
   cDir   := _RoutesDir()
   aFiles := hb_vfDirectory( cDir + hb_ps() + "*.json" )
   FOR EACH aFile IN aFiles
      hb_vfErase( cDir + hb_ps() + aFile[1] )
   NEXT
   hb_vfDirRemove( cDir )
RETURN

FUNCTION HIX_TestLoadRoutes_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cDir
   cDir := _RoutesDir()
   IF ! hb_DirExists( "www" ) ; hb_DirCreate( "www" ) ; ENDIF
   IF ! hb_DirExists( cDir  ) ; hb_DirCreate( cDir  ) ; ENDIF
   _LrLoadNoDir(       hCtx )
   _LrLoadEmptyFile(   hCtx )
   _LrLoadInvalidJSON( hCtx )
   _LrLoadBasic(       hCtx )
   _LrLoadMethods(     hCtx )
   _LrLoadURLVars(     hCtx )
   _LrLoadScope(       hCtx )
   _LrLoadDuplicates(  hCtx )
   _LrLoadMultiFiles(  hCtx )
   _LrApiAdd(          hCtx )
   _LrApiDelete(       hCtx )
   _LrApiReload(       hCtx )
   _CleanupRoutesDir()
RETURN hCtx

STATIC PROCEDURE _LrLoadNoDir( hCtx )
   LOCAL nLoaded, cDir, cBak
   cDir    := _RoutesDir()
   cBak    := "www" + hb_ps() + "routes_bak_" + hb_NToS( Int(Seconds()) )
   hb_vfRename( cDir, cBak )
   nLoaded := HIX_LoadRoutes()
   HixTU_Check( hCtx, nLoaded == 0, "LR: dir inexistente -> 0", "0", hb_NToS( nLoaded ) )
   hb_vfRename( cBak, cDir )
RETURN

STATIC PROCEDURE _LrLoadEmptyFile( hCtx )
   LOCAL nLoaded
   hb_MemoWrit( _RoutesDir() + hb_ps() + "s2_empty.json", "" )
   nLoaded := HIX_LoadRoutes()
   HixTU_Check( hCtx, nLoaded == 0, "LR: JSON vacio -> 0 (no crash)", "0", hb_NToS( nLoaded ) )
   _DeleteRouteJson( "s2_empty.json" )
RETURN

STATIC PROCEDURE _LrLoadInvalidJSON( hCtx )
   LOCAL nLoaded
   hb_MemoWrit( _RoutesDir() + hb_ps() + "s3_bad.json", '{"name":"x"}' )
   nLoaded := HIX_LoadRoutes()
   HixTU_Check( hCtx, nLoaded == 0, "LR: JSON no-array -> 0 (no crash)", "0", hb_NToS( nLoaded ) )
   _DeleteRouteJson( "s3_bad.json" )
RETURN

STATIC PROCEDURE _LrLoadBasic( hCtx )
   LOCAL nLoaded, oReq, aList, nIdx
   _WriteRouteJson( "s4_basic.json", { ;
      { "name" => "lr4.a1", "url" => "/lr4/a1", "action" => "LrAction1", "method" => "GET" }, ;
      { "name" => "lr4.a2", "url" => "/lr4/a2", "action" => "LrAction2", "method" => "GET" }  ;
   } )
   nLoaded := HIX_LoadRoutes()
   HixTU_Check( hCtx, nLoaded >= 2, "LR: retorna >= 2 cargadas", ">=2", hb_NToS( nLoaded ) )
   aList := HIX_RouteList()
   nIdx  := AScan( aList, {|h| h["name"] == "lr4.a1" } )
   HixTU_Check( hCtx, nIdx > 0, "LR: lr4.a1 en RouteList", ">0", hb_NToS( nIdx ) )
   nIdx := AScan( aList, {|h| h["name"] == "lr4.a2" } )
   HixTU_Check( hCtx, nIdx > 0, "LR: lr4.a2 en RouteList", ">0", hb_NToS( nIdx ) )
   oReq := _Dispatch( "/lr4/a1" )
   HixTU_Check( hCtx, oReq:nStatus == 200,           "LR: dispatch /lr4/a1 -> 200",      "200",        hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "lr_action_1",   "LR: body LrAction1 correcto",      "lr_action_1",oReq:cBody )
   oReq := _Dispatch( "/lr4/a2" )
   HixTU_Check( hCtx, oReq:nStatus == 200,           "LR: dispatch /lr4/a2 -> 200",      "200",        hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "lr_action_2",   "LR: body LrAction2 correcto",      "lr_action_2",oReq:cBody )
   _DeleteRouteJson( "s4_basic.json" )
RETURN

STATIC PROCEDURE _LrLoadMethods( hCtx )
   LOCAL nLoaded, oReq
   _WriteRouteJson( "s5_methods.json", { ;
      { "name" => "lr5.get_only",  "url" => "/lr5/get",  "action" => "LrAction1", "method" => "GET"      }, ;
      { "name" => "lr5.post_only", "url" => "/lr5/post", "action" => "LrAction1", "method" => "POST"     }, ;
      { "name" => "lr5.multi",     "url" => "/lr5/multi","action" => "LrAction1", "method" => "GET,POST" }, ;
      { "name" => "lr5.star",      "url" => "/lr5/star", "action" => "LrAction1", "method" => "*"        }  ;
   } )
   nLoaded := HIX_LoadRoutes()
   HixTU_Check( hCtx, nLoaded >= 4, "LR: 4 rutas methods cargadas", ">=4", hb_NToS( nLoaded ) )
   oReq := _Dispatch( "/lr5/get", "GET"  )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: GET en GET-only -> 200",  "200", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr5/get", "POST" )
   HixTU_Check( hCtx, oReq:nStatus == 405, "LR: POST en GET-only -> 405", "405", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr5/post", "POST" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: POST en POST-only -> 200", "200", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr5/post", "GET" )
   HixTU_Check( hCtx, oReq:nStatus == 405, "LR: GET en POST-only -> 405", "405", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr5/multi", "GET"    )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: GET en GET,POST -> 200",     "200", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr5/multi", "POST"   )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: POST en GET,POST -> 200",    "200", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr5/multi", "DELETE" )
   HixTU_Check( hCtx, oReq:nStatus == 405, "LR: DELETE en GET,POST -> 405",  "405", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr5/star", "GET"    )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: GET en * -> 200",    "200", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr5/star", "DELETE" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: DELETE en * -> 200", "200", hb_NToS( oReq:nStatus ) )
   _DeleteRouteJson( "s5_methods.json" )
RETURN

STATIC PROCEDURE _LrLoadURLVars( hCtx )
   LOCAL nLoaded, oReq
   _WriteRouteJson( "s6_vars.json", { ;
      { "name" => "lr6.var",   "url" => "/lr6/item/:id",      "action" => "LrWithVar", "method" => "GET" }, ;
      { "name" => "lr6.regex", "url" => "/lr6/code/([0-9]+)", "action" => "LrAction1", "method" => "GET" }  ;
   } )
   nLoaded := HIX_LoadRoutes()
   HixTU_Check( hCtx, nLoaded >= 2, "LR: URLVars 2 rutas", ">=2", hb_NToS( nLoaded ) )
   oReq := _Dispatch( "/lr6/item/42" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: :id status 200",     "200", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "42",  "LR: :id captura '42'",   "42",  oReq:cBody )
   oReq := _Dispatch( "/lr6/item/abc" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: :id acepta string -> 200", "200", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "abc", "LR: :id captura 'abc'",        "abc", oReq:cBody )
   oReq := _Dispatch( "/lr6/item" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "LR: path sin var -> 404", "404", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr6/code/999" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: regex [0-9]+ -> 200",       "200", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr6/code/abc" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "LR: regex rechaza letras -> 404","404", hb_NToS( oReq:nStatus ) )
   _DeleteRouteJson( "s6_vars.json" )
RETURN

STATIC PROCEDURE _LrLoadScope( hCtx )
   LOCAL nLoaded, aList, nIdx, hItem, oReq
   _WriteRouteJson( "s7_scope.json", { ;
      { "name" => "lr7.scoped", "url" => "/lr7/scoped", "action" => "LrScopeCheck", "method" => "GET", "scope" => "api.v1" }  ;
   } )
   nLoaded := HIX_LoadRoutes()
   HixTU_Check( hCtx, nLoaded >= 1, "LR: scope 1 ruta cargada", ">=1", hb_NToS( nLoaded ) )
   aList := HIX_RouteList()
   nIdx  := AScan( aList, {|h| h["name"] == "lr7.scoped" } )
   hItem := iif( nIdx > 0, aList[nIdx], {=>} )
   HixTU_Check( hCtx, hb_HGetDef( hItem, "scope", "" ) == "api.v1", "LR: scope 'api.v1' guardado", "api.v1", hb_HGetDef( hItem, "scope", "" ) )
   oReq := _Dispatch( "/lr7/scoped" )
   HixTU_Check( hCtx, oReq:nStatus == 200,    "LR: dispatch scope ruta -> 200",    "200",   hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "api.v1", "LR: LrScopeCheck devuelve scope",   "api.v1",oReq:cBody )
   _DeleteRouteJson( "s7_scope.json" )
RETURN

STATIC PROCEDURE _LrLoadDuplicates( hCtx )
   LOCAL nBefore, nAfter, oReq
   HIX_RouteAdd( "lr8.dup", "/lr8/dup", {|oR| oR:Respond( "original", 200, "text" ) }, "GET" )
   oReq := _Dispatch( "/lr8/dup" )
   HixTU_Check( hCtx, oReq:cBody == "original", "LR: version original activa", "original", oReq:cBody )
   _WriteRouteJson( "s8_dup.json", { ;
      { "name" => "lr8.dup",     "url" => "/lr8/dup",     "action" => "LrReplace", "method" => "GET" }, ;
      { "name" => "lr8.new_one", "url" => "/lr8/new_one", "action" => "LrAction1", "method" => "GET" }  ;
   } )
   nBefore := Len( HIX_RouteList() )
   nAfter  := HIX_LoadRoutes()
   HB_SYMBOL_UNUSED( nBefore )
   HixTU_Check( hCtx, nAfter >= 2, "LR: dup carga >= 2", ">=2", hb_NToS( nAfter ) )
   oReq := _Dispatch( "/lr8/dup" )
   HixTU_Check( hCtx, oReq:cBody == "lr_replaced", "LR: ruta sobreescrita nueva accion", "lr_replaced", oReq:cBody )
   oReq := _Dispatch( "/lr8/new_one" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: nueva ruta del JSON -> 200", "200", hb_NToS( oReq:nStatus ) )
   _DeleteRouteJson( "s8_dup.json" )
RETURN

STATIC PROCEDURE _LrLoadMultiFiles( hCtx )
   LOCAL nLoaded, oReq
   _WriteRouteJson( "s9_file_a.json", { ;
      { "name" => "lr9.from_a1", "url" => "/lr9/fa1", "action" => "LrAction1", "method" => "GET" }, ;
      { "name" => "lr9.from_a2", "url" => "/lr9/fa2", "action" => "LrAction1", "method" => "GET" }  ;
   } )
   _WriteRouteJson( "s9_file_b.json", { ;
      { "name" => "lr9.from_b1", "url" => "/lr9/fb1", "action" => "LrAction2", "method" => "GET" }, ;
      { "name" => "lr9.from_b2", "url" => "/lr9/fb2", "action" => "LrAction2", "method" => "GET" }  ;
   } )
   nLoaded := HIX_LoadRoutes()
   HixTU_Check( hCtx, nLoaded >= 4, "LR: >= 4 rutas de 2 ficheros", ">=4", hb_NToS( nLoaded ) )
   oReq := _Dispatch( "/lr9/fa1" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: ruta file_a disponible", "200", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr9/fb1" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: ruta file_b disponible", "200", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr9/fb2" )
   HixTU_Check( hCtx, oReq:cBody == "lr_action_2", "LR: accion file_b correcta", "lr_action_2", oReq:cBody )
   _DeleteRouteJson( "s9_file_a.json" )
   _DeleteRouteJson( "s9_file_b.json" )
RETURN

STATIC PROCEDURE _LrApiAdd( hCtx )
   LOCAL oReq, hBody, hResp
   hBody := { "name" => "lr10.api_add", "url" => "/lr10/api_add", "action" => "LrAction1", "method" => "GET" }
   oReq  := _DispatchPost( "/hix-routes/add", hBody )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: ApiAdd nueva -> 200", "200", hb_NToS( oReq:nStatus ) )
   hResp := NIL
   hb_jsonDecode( oReq:cBody, @hResp )
   HixTU_Check( hCtx, ValType( hResp ) == "H" .AND. hb_HGetDef( hResp, "ok", .F. ), "LR: ApiAdd {ok:true}", "true", hb_ValToStr( hb_HGetDef( hResp, "ok", .F. ) ) )
   oReq := _Dispatch( "/lr10/api_add" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: ruta creada accesible", "200", hb_NToS( oReq:nStatus ) )
   hBody := { "name" => "lr10.api_add", "url" => "/lr10/api_add", "action" => "LrAction2", "method" => "GET" }
   oReq  := _DispatchPost( "/hix-routes/add", hBody )
   HixTU_Check( hCtx, oReq:nStatus == 409, "LR: ApiAdd dup -> 409", "409", hb_NToS( oReq:nStatus ) )
   hResp := NIL
   hb_jsonDecode( oReq:cBody, @hResp )
   HixTU_Check( hCtx, ValType( hResp ) == "H" .AND. ! hb_HGetDef( hResp, "ok", .T. ), "LR: ApiAdd dup -> {ok:false}", "false", hb_ValToStr( hb_HGetDef( hResp, "ok", .T. ) ) )
   oReq := _Dispatch( "/lr10/api_add" )
   HixTU_Check( hCtx, oReq:cBody == "lr_action_1", "LR: dup no sobreescribe accion", "lr_action_1", oReq:cBody )
   oReq := TMockRequest():New( "/hix-routes/add", "POST" )
   oReq:cRawBody := "not_json"
   HIX_RouteDispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 400, "LR: ApiAdd body invalido -> 400", "400", hb_NToS( oReq:nStatus ) )
   oReq := _DispatchPost( "/hix-routes/add", { "name" => "lr10.api_var", "url" => "/lr10/user/:id", "action" => "LrWithVar", "method" => "GET" } )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: ApiAdd ruta :var -> 200", "200", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/lr10/user/99" )
   HixTU_Check( hCtx, oReq:cBody == "99", "LR: ApiAdd ruta :var dispatch id=99", "99", oReq:cBody )
RETURN

STATIC PROCEDURE _LrApiDelete( hCtx )
   LOCAL oReq, hResp
   HIX_RouteAdd( "lr11.to_del", "/lr11/to_del", {|oR| oR:Respond( "alive" ) }, "GET" )
   oReq := _Dispatch( "/lr11/to_del" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: ApiDel ruta existe antes", "200", hb_NToS( oReq:nStatus ) )
   oReq := _DispatchPost( "/hix-routes/delete", { "name" => "lr11.to_del" } )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: ApiDel eliminar existente -> 200", "200", hb_NToS( oReq:nStatus ) )
   hResp := NIL
   hb_jsonDecode( oReq:cBody, @hResp )
   HixTU_Check( hCtx, ValType( hResp ) == "H" .AND. hb_HGetDef( hResp, "ok", .F. ), "LR: ApiDel {ok:true}", "true", hb_ValToStr( hb_HGetDef( hResp, "ok", .F. ) ) )
   oReq := _Dispatch( "/lr11/to_del" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "LR: ApiDel ruta eliminada -> 404", "404", hb_NToS( oReq:nStatus ) )
   oReq := _DispatchPost( "/hix-routes/delete", { "name" => "lr11.nonexistent" } )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: ApiDel inexistente -> 200 idempotente", "200", hb_NToS( oReq:nStatus ) )
   oReq := _DispatchPost( "/hix-routes/delete", { "x" => "y" } )
   HixTU_Check( hCtx, oReq:nStatus == 400, "LR: ApiDel sin name -> 400", "400", hb_NToS( oReq:nStatus ) )
   oReq := TMockRequest():New( "/hix-routes/delete", "POST" )
   oReq:cRawBody := "bad"
   HIX_RouteDispatch( oReq )
   HixTU_Check( hCtx, oReq:nStatus == 400, "LR: ApiDel body invalido -> 400", "400", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _LrApiReload( hCtx )
   LOCAL oReq, hResp, nLoaded
   _WriteRouteJson( "s12_reload.json", { ;
      { "name" => "lr12.from_reload", "url" => "/lr12/reload_check", "action" => "LrAction1", "method" => "GET" }  ;
   } )
   oReq := _Dispatch( "/hix-routes/reload", "GET" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: ApiReload GET -> 200", "200", hb_NToS( oReq:nStatus ) )
   hResp := NIL
   hb_jsonDecode( oReq:cBody, @hResp )
   HixTU_Check( hCtx, ValType( hResp ) == "H", "LR: ApiReload respuesta es JSON", "H", ValType( hResp ) )
   HixTU_Check( hCtx, hb_HGetDef( hResp, "ok", .F. ), "LR: ApiReload {ok:true}", "true", hb_ValToStr( hb_HGetDef( hResp, "ok", .F. ) ) )
   nLoaded := hb_HGetDef( hResp, "total_loaded", -1 )
   HixTU_Check( hCtx, nLoaded >= 1, "LR: ApiReload total_loaded >= 1", ">=1", hb_NToS( nLoaded ) )
   oReq := _Dispatch( "/lr12/reload_check" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "LR: ruta via reload accesible", "200", hb_NToS( oReq:nStatus ) )
   _DeleteRouteJson( "s12_reload.json" )
RETURN
