/*-----------------------------------------------------------
  File ......: hix_test_chunked.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — Chunked Transfer Encoding
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"
#include "fileio.ch"

// Uses shared TMockIO from hix_test_utils.prg

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[Chunked] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

STATIC FUNCTION _ChunkCRLF()
RETURN Chr(13) + Chr(10)

STATIC FUNCTION _MakeChunkReq( cMethod, cPath )
   LOCAL cH
   hb_default( @cMethod, "GET" )
   hb_default( @cPath,   "/"  )
   cH := cMethod + " " + cPath + " HTTP/1.1" + _ChunkCRLF() + ;
         "Host: localhost"     + _ChunkCRLF() + ;
         _ChunkCRLF()
RETURN cH

FUNCTION HIX_TestChunked_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TLog( "=== HIX_TestChunked_Run start ===" )
   _TestWriteChunk(      hCtx )
   _TestStreamHeaders(   hCtx )
   _TestRespondChunked(  hCtx )
   _TestRespondStream(   hCtx )
   _TLog( "=== HIX_TestChunked_Run end ===" )
RETURN hCtx

STATIC PROCEDURE _TestWriteChunk( hCtx )
   LOCAL oIO, cCRLF, cData, cExpected

   cCRLF := _ChunkCRLF()
   oIO   := TMockIO():New()

   cData     := "Hola mundo"
   oIO:WriteChunk( cData )
   cExpected := hb_NumToHex( Len( cData ) ) + cCRLF + cData + cCRLF
   HixTU_Check( hCtx, oIO:cWritten == cExpected, "Chunk: WriteChunk formato hex CRLF data CRLF", cExpected, oIO:cWritten )

   oIO := TMockIO():New()
   oIO:WriteChunkEnd()
   HixTU_Check( hCtx, oIO:cWritten == "0" + cCRLF + cCRLF, "Chunk: WriteChunkEnd = 0 CRLF CRLF", "0"+cCRLF+cCRLF, oIO:cWritten )

   oIO := TMockIO():New()
   oIO:WriteChunk( "" )
   HixTU_Check( hCtx, oIO:cWritten == "", "Chunk: WriteChunk vacio no escribe", "", oIO:cWritten )
RETURN

STATIC PROCEDURE _TestStreamHeaders( hCtx )
   LOCAL oIO, oReq, cOut

   oIO  := TMockIO():New( _MakeChunkReq( "GET", "/stream" ) )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   oReq:RespondStart( "html", 200 )
   cOut := oIO:cWritten

   HixTU_Check( hCtx, "Transfer-Encoding: chunked" $ cOut, "Chunk: headers tienen Transfer-Encoding: chunked", "Transfer-Encoding: chunked", "(no encontrado)" )
   HixTU_Check( hCtx, !( "Content-Length" $ cOut ),        "Chunk: headers chunked sin Content-Length",        "(ausente)", iif( "Content-Length" $ cOut, "presente", "(ausente)" ) )
   HixTU_Check( hCtx, "text/html" $ cOut,                  "Chunk: Content-Type text/html",                    "text/html", "(no encontrado)" )
RETURN

STATIC PROCEDURE _TestRespondChunked( hCtx )
   LOCAL oIO, oReq, cOut, cCRLF
   LOCAL cP1, cP2, cP3, cExpBody

   cCRLF := _ChunkCRLF()
   cP1   := "<html>"
   cP2   := "<body>Hola</body>"
   cP3   := "</html>"

   oIO  := TMockIO():New( _MakeChunkReq( "GET", "/chunks" ) )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
   oReq:RespondStart( "html", 200 )
   oReq:RespondChunk( cP1 )
   oReq:RespondChunk( cP2 )
   oReq:RespondChunk( cP3 )
   oReq:RespondEnd()

   cOut := oIO:cWritten

   cExpBody := hb_NumToHex( Len(cP1) ) + cCRLF + cP1 + cCRLF + ;
               hb_NumToHex( Len(cP2) ) + cCRLF + cP2 + cCRLF + ;
               hb_NumToHex( Len(cP3) ) + cCRLF + cP3 + cCRLF + ;
               "0" + cCRLF + cCRLF
   HixTU_Check( hCtx, cExpBody $ cOut,   "Chunk: body 3 chunks + terminador", "(chunks + 0 CRLF CRLF)", iif( cExpBody $ cOut, "ok", "incorrecto" ) )
   HixTU_Check( hCtx, ! oReq:lStreaming, "Chunk: lStreaming=.F. tras RespondEnd", ".F.", iif( oReq:lStreaming, ".T.", ".F." ) )
RETURN

STATIC PROCEDURE _TestRespondStream( hCtx )
   LOCAL oIO, oReq, cOut, cCRLF

   cCRLF := _ChunkCRLF()

   oIO  := TMockIO():New( _MakeChunkReq( "GET", "/stream2" ) )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()

   oReq:RespondStream( "text", {|oR|
      oR:RespondChunk( "linea1" + Chr(10) )
      oR:RespondChunk( "linea2" + Chr(10) )
      RETURN NIL
   }, 200 )

   cOut := oIO:cWritten
   HixTU_Check( hCtx, "Transfer-Encoding: chunked" $ cOut,               "Chunk: RespondStream envia chunked",    "Transfer-Encoding: chunked", "(no encontrado)" )
   HixTU_Check( hCtx, "linea1" $ cOut .AND. "linea2" $ cOut,             "Chunk: RespondStream envia ambas lineas","linea1+linea2",              iif( "linea1" $ cOut .AND. "linea2" $ cOut, "ok", "faltan" ) )
   HixTU_Check( hCtx, "0" + cCRLF + cCRLF $ cOut,                        "Chunk: RespondStream cierra con 0 CRLF","0"+cCRLF+cCRLF,              "(no encontrado)" )
RETURN
