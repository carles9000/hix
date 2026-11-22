/*-----------------------------------------------------------
  File ......: hix_test_http_framing.prg
  Author.....: Charly 9000
  Created....: 2026-11-22
  Description: Claim 3 — HTTP framing strict. 15 asserts covering
               F1 (duplicate Content-Length), F2 (CL validation),
               F3 (Transfer-Encoding rejection), F4 (body truncation).
 -----------------------------------------------------------*/
#include "hix_const.ch"

#define CRLF ( Chr(13) + Chr(10) )

STATIC FUNCTION _HFMake( cExtraHeaders, cMethod )
   LOCAL cRaw
   hb_default( @cExtraHeaders, "" )
   hb_default( @cMethod,       "POST" )
   cRaw := cMethod + " / HTTP/1.1" + CRLF
   cRaw += "Host: localhost" + CRLF
   cRaw += cExtraHeaders
   cRaw += CRLF
RETURN cRaw

STATIC FUNCTION _HFParse( cRaw, cBody )
   LOCAL oIO, oReq
   hb_default( @cBody, "" )
   oIO  := TMockIO():New( cRaw, cBody )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
RETURN oReq

FUNCTION HIX_TestHttpFraming_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   _HFF1Duplicates(      hCtx )
   _HFF2ContentLength(   hCtx )
   _HFF3TransferEncoding( hCtx )
   _HFF4Truncation(      hCtx )
RETURN hCtx

// --- F1: Content-Length duplicado → 400 ----------------------
STATIC PROCEDURE _HFF1Duplicates( hCtx )
   LOCAL oReq, cRaw

   cRaw := _HFMake( "Content-Length: 5" + CRLF + "Content-Length: 5" + CRLF )
   oReq := _HFParse( cRaw, "hello" )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_BADREQ, ;
      "F1 T01: dup Content-Length -> BADREQ", ;
      hb_NToS( HIX_REQ_ERR_BADREQ ), hb_NToS( oReq:nReadError ) )

   cRaw := _HFMake( "Content-Length: 10, 10" + CRLF )
   oReq := _HFParse( cRaw, "0123456789" )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_BADREQ, ;
      "F1 T02: Content-Length with comma -> BADREQ", ;
      hb_NToS( HIX_REQ_ERR_BADREQ ), hb_NToS( oReq:nReadError ) )

   cRaw := _HFMake( "Content-Length: 5" + CRLF )
   oReq := _HFParse( cRaw, "hello" )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_NONE, ;
      "F1 T03: single Content-Length -> OK (control)", ;
      hb_NToS( HIX_REQ_ERR_NONE ), hb_NToS( oReq:nReadError ) )
RETURN

// --- F2: Content-Length inválido ----------------------------
STATIC PROCEDURE _HFF2ContentLength( hCtx )
   LOCAL oReq, cRaw

   cRaw := _HFMake( "Content-Length: abc" + CRLF )
   oReq := _HFParse( cRaw, "" )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_BADREQ, ;
      "F2 T04: non-digit Content-Length -> BADREQ", ;
      hb_NToS( HIX_REQ_ERR_BADREQ ), hb_NToS( oReq:nReadError ) )

   cRaw := _HFMake( "Content-Length: -5" + CRLF )
   oReq := _HFParse( cRaw, "" )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_BADREQ, ;
      "F2 T05: negative Content-Length -> BADREQ", ;
      hb_NToS( HIX_REQ_ERR_BADREQ ), hb_NToS( oReq:nReadError ) )

   cRaw := _HFMake( "Content-Length: 0x10" + CRLF )
   oReq := _HFParse( cRaw, "" )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_BADREQ, ;
      "F2 T06: hex Content-Length -> BADREQ", ;
      hb_NToS( HIX_REQ_ERR_BADREQ ), hb_NToS( oReq:nReadError ) )

   cRaw := _HFMake( "Content-Length: " + CRLF )
   oReq := _HFParse( cRaw, "" )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_BADREQ, ;
      "F2 T07: empty Content-Length -> BADREQ", ;
      hb_NToS( HIX_REQ_ERR_BADREQ ), hb_NToS( oReq:nReadError ) )

   cRaw := _HFMake( "", "GET" )
   oReq := _HFParse( cRaw, "" )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_NONE, ;
      "F2 T08: GET without Content-Length -> OK (control)", ;
      hb_NToS( HIX_REQ_ERR_NONE ), hb_NToS( oReq:nReadError ) )

   cRaw := _HFMake( "Content-Length: 1000000000" + CRLF )
   oReq := _HFParse( cRaw, "" )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_TOOLARGE, ;
      "F2 T09: oversized Content-Length -> TOOLARGE", ;
      hb_NToS( HIX_REQ_ERR_TOOLARGE ), hb_NToS( oReq:nReadError ) )
RETURN

// --- F3: Transfer-Encoding de entrada → 501 ------------------
STATIC PROCEDURE _HFF3TransferEncoding( hCtx )
   LOCAL oReq, cRaw

   cRaw := _HFMake( "Transfer-Encoding: chunked" + CRLF )
   oReq := _HFParse( cRaw, "" )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_TE_UNSUPPORTED, ;
      "F3 T10: TE: chunked -> TE_UNSUPPORTED", ;
      hb_NToS( HIX_REQ_ERR_TE_UNSUPPORTED ), hb_NToS( oReq:nReadError ) )
   HixTU_Check( hCtx, ! oReq:lKeepAlive, ;
      "F3 T10b: TE: chunked -> keep-alive OFF", ".F.", hb_ValToStr( oReq:lKeepAlive ) )

   cRaw := _HFMake( "Transfer-Encoding: identity" + CRLF )
   oReq := _HFParse( cRaw, "" )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_TE_UNSUPPORTED, ;
      "F3 T11: TE: identity -> TE_UNSUPPORTED (strict)", ;
      hb_NToS( HIX_REQ_ERR_TE_UNSUPPORTED ), hb_NToS( oReq:nReadError ) )

   cRaw := _HFMake( "Content-Length: 10" + CRLF + "Transfer-Encoding: chunked" + CRLF )
   oReq := _HFParse( cRaw, "0123456789" )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_BADREQ, ;
      "F3 T12: TE + CL conflict -> BADREQ (smuggling defense)", ;
      hb_NToS( HIX_REQ_ERR_BADREQ ), hb_NToS( oReq:nReadError ) )
RETURN

// --- F4: Body truncado --------------------------------------
STATIC PROCEDURE _HFF4Truncation( hCtx )
   LOCAL oIO, oReq, cRaw, cBody500, cBody1000, cRead

   cBody500  := Replicate( "A", 500 )
   cBody1000 := Replicate( "B", 1000 )

   // T13: CL=1000 pero mock solo tiene 500 bytes → TRUNCATED
   cRaw := _HFMake( "Content-Length: 1000" + CRLF )
   oIO  := TMockIO():New( cRaw, cBody500 )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   cRead := oReq:ReadBody()
   HixTU_Check( hCtx, Len( cRead ) == 500, ;
      "F4 T13: truncated body returns 500 bytes", "500", hb_NToS( Len( cRead ) ) )
   HixTU_Check( hCtx, oReq:nReadError == HIX_REQ_ERR_TRUNCATED, ;
      "F4 T13b: truncated -> TRUNCATED error", ;
      hb_NToS( HIX_REQ_ERR_TRUNCATED ), hb_NToS( oReq:nReadError ) )
   HixTU_Check( hCtx, ! oReq:lKeepAlive, ;
      "F4 T13c: truncated -> keep-alive OFF", ".F.", hb_ValToStr( oReq:lKeepAlive ) )

   // T14: CL=1000, body exacto 1000
   cRaw := _HFMake( "Content-Length: 1000" + CRLF )
   oIO  := TMockIO():New( cRaw, cBody1000 )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   cRead := oReq:ReadBody()
   HixTU_Check( hCtx, Len( cRead ) == 1000 .AND. oReq:nReadError == HIX_REQ_ERR_NONE, ;
      "F4 T14: exact 1000 bytes -> OK, no error", "1000/none", ;
      hb_NToS( Len( cRead ) ) + "/" + hb_NToS( oReq:nReadError ) )

   // T15: body llega completo y coincide byte a byte con el payload
   cRaw := _HFMake( "Content-Length: 1000" + CRLF )
   oIO  := TMockIO():New( cRaw, cBody1000 )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   cRead := oReq:ReadBody()
   HixTU_Check( hCtx, cRead == cBody1000, ;
      "F4 T15: body matches exact payload", "match", ;
      iif( cRead == cBody1000, "match", "diff(" + hb_NToS( Len( cRead ) ) + ")" ) )
RETURN
