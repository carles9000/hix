/*-----------------------------------------------------------
  File ......: hix_test_multipart.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — multipart/form-data parsing
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"
#include "fileio.ch"

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[Multipart] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

// Uses shared TMockIO from hix_test_utils.prg

STATIC FUNCTION CRLF()
RETURN Chr(13) + Chr(10)

STATIC FUNCTION _BuildMultipart( cBoundary, aParts )
   LOCAL cBody := ""
   LOCAL aPart, cDisp
   FOR EACH aPart IN aParts
      cBody += "--" + cBoundary + CRLF()
      cDisp := 'Content-Disposition: form-data; name="' + aPart[1] + '"'
      IF ! Empty( aPart[2] )
         cDisp += '; filename="' + aPart[2] + '"'
      ENDIF
      cBody += cDisp + CRLF()
      IF ! Empty( aPart[3] )
         cBody += "Content-Type: " + aPart[3] + CRLF()
      ENDIF
      cBody += CRLF() + aPart[4] + CRLF()
   NEXT
   cBody += "--" + cBoundary + "--" + CRLF()
RETURN cBody

STATIC FUNCTION _MakeReq( cBoundary, cBody )
   LOCAL cHeaders
   cHeaders := "POST /upload HTTP/1.1" + CRLF() + ;
               "Host: localhost" + CRLF() + ;
               "Content-Type: multipart/form-data; boundary=" + cBoundary + CRLF() + ;
               "Content-Length: " + hb_NToS( Len( cBody ) ) + CRLF() + ;
               CRLF()
RETURN cHeaders

STATIC FUNCTION _ParseReq( cBoundary, cBody )
   LOCAL oIO, oReq
   oIO  := TMockIO():New( _MakeReq( cBoundary, cBody ), cBody )
   oReq := THixRequest():New( oIO, "127.0.0.1" )
   oReq:Read()
RETURN oReq

FUNCTION HIX_TestMultipart_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TLog( "=== HIX_TestMultipart_Run start ===" )
   _MultiDeteccion(  hCtx )
   _MultiCampoTexto( hCtx )
   _MultiFichero(    hCtx )
   _MultiMixto(      hCtx )
   _MultiEdgeCases(  hCtx )
   _TLog( "=== HIX_TestMultipart_Run end ===" )
RETURN hCtx

STATIC PROCEDURE _MultiDeteccion( hCtx )
   LOCAL oReq, cBoundary, oIO2, oReq2
   cBoundary := "----Boundary123"
   oReq := _ParseReq( cBoundary, _BuildMultipart( cBoundary, { { "campo", "", "", "valor" } } ) )
   HixTU_Check( hCtx, oReq:IsMultipart(), "Multi: IsMultipart .T.", ".T.", iif( oReq:IsMultipart(), ".T.", ".F." ) )
   oIO2  := TMockIO():New( "POST /x HTTP/1.1" + CRLF() + "Content-Type: application/json" + CRLF() + "Content-Length: 2" + CRLF() + CRLF(), "{}" )
   oReq2 := THixRequest():New( oIO2, "127.0.0.1" )
   oReq2:Read()
   HixTU_Check( hCtx, ! oReq2:IsMultipart(), "Multi: IsMultipart .F. con JSON", ".F.", iif( oReq2:IsMultipart(), ".T.", ".F." ) )
   oReq := _ParseReq( cBoundary, "" )
   HixTU_Check( hCtx, oReq:MultipartBoundary() == cBoundary, "Multi: MultipartBoundary() correcto", cBoundary, oReq:MultipartBoundary() )
RETURN

STATIC PROCEDURE _MultiCampoTexto( hCtx )
   LOCAL cBoundary, cBody, oReq, aFiles
   cBoundary := "----Simple"
   cBody     := _BuildMultipart( cBoundary, { { "titulo", "", "", "Mi titulo" } } )
   oReq      := _ParseReq( cBoundary, cBody )
   aFiles    := oReq:MultipartFiles()
   HixTU_Check( hCtx, Len( aFiles ) == 1,              "Multi: 1 parte",          "1",        hb_NToS( Len( aFiles ) ) )
   HixTU_Check( hCtx, aFiles[1]["name"] == "titulo",   "Multi: name=titulo",      "titulo",   aFiles[1]["name"] )
   HixTU_Check( hCtx, aFiles[1]["filename"] == "",      "Multi: filename vacio",   "",         aFiles[1]["filename"] )
   HixTU_Check( hCtx, aFiles[1]["data"] == "Mi titulo","Multi: data=Mi titulo",   "Mi titulo",aFiles[1]["data"] )
   HixTU_Check( hCtx, oReq:FormBody()[ "titulo" ] == "Mi titulo", "Multi: FormBody titulo", "Mi titulo", hb_defaultValue( oReq:FormBody()[ "titulo" ], "" ) )
RETURN

STATIC PROCEDURE _MultiFichero( hCtx )
   LOCAL cBoundary, cBody, oReq, aFiles
   cBoundary := "----FileBoundary"
   cBody     := _BuildMultipart( cBoundary, { ;
      { "archivo", "foto.jpg", "image/jpeg", "JFIF_DATA_FAKE" } ;
   } )
   oReq   := _ParseReq( cBoundary, cBody )
   aFiles := oReq:MultipartFiles()
   HixTU_Check( hCtx, Len( aFiles ) == 1,                   "Multi: 1 fichero",         "1",             hb_NToS( Len( aFiles ) ) )
   HixTU_Check( hCtx, aFiles[1]["filename"] == "foto.jpg",  "Multi: filename=foto.jpg", "foto.jpg",      aFiles[1]["filename"] )
   HixTU_Check( hCtx, aFiles[1]["mime"] == "image/jpeg",    "Multi: mime=image/jpeg",   "image/jpeg",    aFiles[1]["mime"] )
   HixTU_Check( hCtx, aFiles[1]["data"] == "JFIF_DATA_FAKE","Multi: data ok",           "JFIF_DATA_FAKE",aFiles[1]["data"] )
   HixTU_Check( hCtx, aFiles[1]["size"] == Len( "JFIF_DATA_FAKE" ), "Multi: size ok",   hb_NToS(Len("JFIF_DATA_FAKE")), hb_NToS(aFiles[1]["size"]) )
RETURN

STATIC PROCEDURE _MultiMixto( hCtx )
   LOCAL cBoundary, cBody, oReq, aFiles
   cBoundary := "----Mixed"
   cBody     := _BuildMultipart( cBoundary, { ;
      { "descripcion", "", "",           "Un texto"   }, ;
      { "imagen",      "img.png", "image/png", "PNG_BYTES"  }, ;
      { "autor",       "", "",           "Carles"      }  ;
   } )
   oReq   := _ParseReq( cBoundary, cBody )
   aFiles := oReq:MultipartFiles()
   HixTU_Check( hCtx, Len( aFiles ) == 3,                   "Multi: 3 partes mixtas",       "3",       hb_NToS( Len( aFiles ) ) )
   HixTU_Check( hCtx, aFiles[2]["filename"] == "img.png",   "Multi: fichero filename",       "img.png", aFiles[2]["filename"] )
   HixTU_Check( hCtx, oReq:FormBody()[ "autor" ] == "Carles","Multi: FormBody autor",        "Carles",  hb_defaultValue( oReq:FormBody()[ "autor" ], "" ) )
RETURN

STATIC PROCEDURE _MultiEdgeCases( hCtx )
   LOCAL cBoundary, cBody, oReq, aFiles
   cBoundary := "----Empty"
   oReq      := _ParseReq( cBoundary, "" )
   aFiles    := oReq:MultipartFiles()
   HixTU_Check( hCtx, Len( aFiles ) == 0, "Multi: body vacio => 0 partes", "0", hb_NToS( Len( aFiles ) ) )
   cBoundary := "----Multi"
   cBody     := _BuildMultipart( cBoundary, { ;
      { "foto1", "a.jpg", "image/jpeg", "AAA" }, ;
      { "foto2", "b.jpg", "image/jpeg", "BBB" }  ;
   } )
   oReq   := _ParseReq( cBoundary, cBody )
   aFiles := oReq:MultipartFiles()
   HixTU_Check( hCtx, Len( aFiles ) == 2, "Multi: 2 ficheros", "2", hb_NToS( Len( aFiles ) ) )
   HixTU_Check( hCtx, aFiles[1]["name"] == "foto1" .AND. aFiles[2]["name"] == "foto2", "Multi: nombres foto1/foto2", "foto1,foto2", aFiles[1]["name"] + "," + aFiles[2]["name"] )
   cBoundary := "----NoCT"
   cBody     := _BuildMultipart( cBoundary, { { "campo", "file.txt", "", "contenido" } } )
   oReq      := _ParseReq( cBoundary, cBody )
   aFiles    := oReq:MultipartFiles()
   HixTU_Check( hCtx, aFiles[1]["mime"] == "text/plain", "Multi: sin CT => text/plain", "text/plain", aFiles[1]["mime"] )
RETURN
