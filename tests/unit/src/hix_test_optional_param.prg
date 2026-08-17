/*-----------------------------------------------------------
  File ......: hix_test_optional_param.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — route optional parameters :id!
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"

// Module-level statics — file-local, no conflict
STATIC s_cOptLastId := ""
STATIC s_cOptLastX  := ""
STATIC s_cOptLastY  := ""

// Uses shared TMockRequest from hix_test_utils.prg

// PUBLIC handlers — called by router via string name
PROCEDURE HndOptUserId( oReq )
   s_cOptLastId := hb_HGetDef( oReq:hParam, "id", "__missing__" )
   oReq:Respond( "ok" )
RETURN

PROCEDURE HndOptXY( oReq )
   s_cOptLastX := hb_HGetDef( oReq:hParam, "x", "__missing__" )
   s_cOptLastY := hb_HGetDef( oReq:hParam, "y", "__missing__" )
   oReq:Respond( "ok" )
RETURN

STATIC FUNCTION _Dispatch( cPath )
   LOCAL oReq := TMockRequest():New( cPath, "GET" )
   HIX_RouteDispatch( oReq )
RETURN oReq

FUNCTION HIX_TestOptionalParam_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL oReq

   // Register routes with unique prefix to avoid conflicts
   HIX_RouteAdd( "top.req",   "/top_users/:id",  "HndOptUserId", "GET" )
   HIX_RouteAdd( "top.opt",   "/top_items/:id!", "HndOptUserId", "GET" )
   HIX_RouteAdd( "top.mixed", "/top_a/:x/b/:y!", "HndOptXY",     "GET" )

   // Required :id
   s_cOptLastId := ""
   oReq := _Dispatch( "/top_users/42" )
   HixTU_Check( hCtx, s_cOptLastId == "42",    "OptP: requerido /42 -> id=42",    "42",    s_cOptLastId )
   s_cOptLastId := ""
   oReq := _Dispatch( "/top_users/hello" )
   HixTU_Check( hCtx, s_cOptLastId == "hello", "OptP: requerido /hello -> id=hello","hello",s_cOptLastId )
   oReq := _Dispatch( "/top_users" )
   HixTU_Check( hCtx, oReq:nStatus == 404,     "OptP: requerido sin segmento -> 404","404", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( "/top_users/" )
   HixTU_Check( hCtx, oReq:nStatus == 404,     "OptP: requerido sin valor -> 404",  "404",  hb_NToS( oReq:nStatus ) )

   // Optional :id!
   s_cOptLastId := ""
   oReq := _Dispatch( "/top_items/99" )
   HixTU_Check( hCtx, s_cOptLastId == "99",    "OptP: opcional /99 -> id=99",     "99",    s_cOptLastId )
   s_cOptLastId := "__not_called__"
   oReq := _Dispatch( "/top_items" )
   HixTU_Check( hCtx, oReq:nStatus != 404,     "OptP: opcional /items matchea",   "!404",  hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, s_cOptLastId == "",      "OptP: opcional /items -> id=vacio","",      s_cOptLastId )
   s_cOptLastId := "__not_called__"
   oReq := _Dispatch( "/top_items/" )
   HixTU_Check( hCtx, oReq:nStatus != 404,     "OptP: opcional /items/ matchea",  "!404",  hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, s_cOptLastId == "",      "OptP: opcional /items/ -> id=vacio","",     s_cOptLastId )

   // Mixed :x required + :y! optional
   s_cOptLastX := "" ; s_cOptLastY := ""
   oReq := _Dispatch( "/top_a/1/b/2" )
   HixTU_Check( hCtx, s_cOptLastX == "1" .AND. s_cOptLastY == "2", "OptP: mixto /1/b/2 -> x=1 y=2", "x=1 y=2", "x=" + s_cOptLastX + " y=" + s_cOptLastY )
   s_cOptLastX := "" ; s_cOptLastY := "__not_called__"
   oReq := _Dispatch( "/top_a/1/b" )
   HixTU_Check( hCtx, oReq:nStatus != 404,                                         "OptP: mixto /1/b matchea",      "!404",    hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, s_cOptLastX == "1" .AND. s_cOptLastY == "", "OptP: mixto /1/b -> x=1 y=vacio", "x=1 y=", "x=" + s_cOptLastX + " y=" + s_cOptLastY )
   oReq := _Dispatch( "/top_a/b" )
   HixTU_Check( hCtx, oReq:nStatus == 404,                                         "OptP: mixto /a/b sin x -> 404", "404",     hb_NToS( oReq:nStatus ) )

   HB_SYMBOL_UNUSED( oReq )
RETURN hCtx
