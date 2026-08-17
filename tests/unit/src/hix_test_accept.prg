/*-----------------------------------------------------------
  File ......: hix_test_accept.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — content negotiation (Accept header)
 -----------------------------------------------------------*/
#include "hix_logger.ch"

// Uses shared TMockIO from hix_test_utils.prg

STATIC FUNCTION _CRLF()
RETURN Chr(13) + Chr(10)

STATIC FUNCTION _MakeAcceptReq( cMethod, cPath, hExtra )
   LOCAL cReq, cKey, oIO, oReq
   hb_default( @cMethod, "GET" )
   hb_default( @cPath,   "/" )
   hb_default( @hExtra, {=>} )
   cReq := cMethod + " " + cPath + " HTTP/1.1" + _CRLF()
   FOR EACH cKey IN hb_HKeys( hExtra )
      cReq += cKey + ": " + hExtra[ cKey ] + _CRLF()
   NEXT
   cReq += _CRLF()
   oIO  := TMockIO():New( cReq, "" )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
RETURN oReq

STATIC FUNCTION _ContentTypeFromResp( oReq )
   LOCAL cWritten, nPos, cLine, nEnd
   cWritten := oReq:oIO:cWritten
   nPos     := At( "Content-Type: ", cWritten )
   IF nPos == 0
      RETURN ""
   ENDIF
   cLine := SubStr( cWritten, nPos + 14 )
   nEnd  := At( _CRLF(), cLine )
   IF nEnd > 0
      cLine := Left( cLine, nEnd - 1 )
   ENDIF
RETURN AllTrim( cLine )

FUNCTION HIX_TestAccept_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   _TestWantsJson(      hCtx )
   _TestRespondInfer(   hCtx )
   _TestRespondExplicit( hCtx )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _TestWantsJson( hCtx )
   LOCAL oReq

   oReq := _MakeAcceptReq( "GET", "/page" )
   HixTU_Check( hCtx, ! HIX_WantsJson( oReq ), "Accept: sin Accept -> no JSON",                  ".F.", ".T." )

   oReq := _MakeAcceptReq( "GET", "/page", { "Accept" => "text/html, */*" } )
   HixTU_Check( hCtx, ! HIX_WantsJson( oReq ), "Accept: text/html -> no JSON",                   ".F.", ".T." )

   oReq := _MakeAcceptReq( "GET", "/page", { "Accept" => "application/json" } )
   HixTU_Check( hCtx, HIX_WantsJson( oReq ),   "Accept: application/json -> quiere JSON",         ".T.", ".F." )

   oReq := _MakeAcceptReq( "GET", "/page", { "Accept" => "text/html, application/json" } )
   HixTU_Check( hCtx, HIX_WantsJson( oReq ),   "Accept: mixto con json -> quiere JSON",           ".T.", ".F." )

   oReq := _MakeAcceptReq( "GET", "/page", { "X-Requested-With" => "XMLHttpRequest" } )
   HixTU_Check( hCtx, HIX_WantsJson( oReq ),   "Accept: X-Requested-With:XHR -> quiere JSON",    ".T.", ".F." )

   oReq := _MakeAcceptReq( "GET", "/api/users" )
   HixTU_Check( hCtx, HIX_WantsJson( oReq ),   "Accept: ruta /api/ -> quiere JSON",               ".T.", ".F." )

   oReq := _MakeAcceptReq( "GET", "/apifoo" )
   HixTU_Check( hCtx, ! HIX_WantsJson( oReq ), "Accept: /apifoo (sin /) -> no quiere JSON",       ".F.", ".T." )
RETURN

STATIC PROCEDURE _TestRespondInfer( hCtx )
   LOCAL oReq, cCT

   oReq := _MakeAcceptReq( "GET", "/page" )
   oReq:Respond( { "ok" => .T. } )
   cCT := _ContentTypeFromResp( oReq )
   HixTU_Check( hCtx, "application/json" $ cCT, "Infer: hash sin tipo -> JSON",             "application/json", cCT )

   oReq := _MakeAcceptReq( "GET", "/page" )
   oReq:Respond( { "a", "b" } )
   cCT := _ContentTypeFromResp( oReq )
   HixTU_Check( hCtx, "application/json" $ cCT, "Infer: array sin tipo -> JSON",            "application/json", cCT )

   oReq := _MakeAcceptReq( "GET", "/page", { "Accept" => "application/json" } )
   oReq:Respond( "<h1>Hola</h1>" )
   cCT := _ContentTypeFromResp( oReq )
   HixTU_Check( hCtx, "application/json" $ cCT, "Infer: string + Accept:json -> JSON",      "application/json", cCT )

   oReq := _MakeAcceptReq( "GET", "/page", { "Accept" => "text/html" } )
   oReq:Respond( "<h1>Hola</h1>" )
   cCT := _ContentTypeFromResp( oReq )
   HixTU_Check( hCtx, "text/html" $ cCT,        "Infer: string + Accept:html -> HTML",      "text/html",        cCT )

   oReq := _MakeAcceptReq( "GET", "/page" )
   oReq:Respond( "<h1>Hola</h1>" )
   cCT := _ContentTypeFromResp( oReq )
   HixTU_Check( hCtx, "text/html" $ cCT,        "Infer: string sin Accept -> HTML",         "text/html",        cCT )

   oReq := _MakeAcceptReq( "GET", "/api/items" )
   oReq:Respond( "[]" )
   cCT := _ContentTypeFromResp( oReq )
   HixTU_Check( hCtx, "application/json" $ cCT, "Infer: ruta /api/ sin tipo -> JSON",       "application/json", cCT )

   oReq := _MakeAcceptReq( "GET", "/data", { "X-Requested-With" => "XMLHttpRequest" } )
   oReq:Respond( "{}" )
   cCT := _ContentTypeFromResp( oReq )
   HixTU_Check( hCtx, "application/json" $ cCT, "Infer: XHR sin tipo -> JSON",              "application/json", cCT )
RETURN

STATIC PROCEDURE _TestRespondExplicit( hCtx )
   LOCAL oReq, cCT

   oReq := _MakeAcceptReq( "GET", "/page", { "Accept" => "text/html" } )
   oReq:Respond( "{}", 200, "json" )
   cCT := _ContentTypeFromResp( oReq )
   HixTU_Check( hCtx, "application/json" $ cCT, "Explicit: json explicito, Accept:html -> JSON", "application/json", cCT )

   oReq := _MakeAcceptReq( "GET", "/page", { "Accept" => "application/json" } )
   oReq:Respond( "<h1>X</h1>", 200, "html" )
   cCT := _ContentTypeFromResp( oReq )
   HixTU_Check( hCtx, "text/html" $ cCT,        "Explicit: html explicito, Accept:json -> HTML", "text/html",        cCT )

   oReq := _MakeAcceptReq( "GET", "/page" )
   oReq:Respond( "hola", 200, "text" )
   cCT := _ContentTypeFromResp( oReq )
   HixTU_Check( hCtx, "text/plain" $ cCT,       "Explicit: text explicito -> text/plain",         "text/plain",       cCT )

   oReq := _MakeAcceptReq( "GET", "/page" )
   oReq:Respond( { "x" => 1 }, 200, "html" )
   cCT := _ContentTypeFromResp( oReq )
   HixTU_Check( hCtx, "text/html" $ cCT,        "Explicit: hash tipo html -> HTML Content-Type",  "text/html",        cCT )

   oReq := _MakeAcceptReq( "GET", "/notfound" )
   oReq:Respond( { "error" => "Not Found" }, 404 )
   cCT := _ContentTypeFromResp( oReq )
   HixTU_Check( hCtx, "application/json" $ cCT, "Explicit: hash 404 -> JSON",                    "application/json", cCT )
RETURN
