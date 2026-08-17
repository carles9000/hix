/*-----------------------------------------------------------
  File ......: hix_test_gzip.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — Gzip (HIX_GzipCompress/ShouldCompress)
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "fileio.ch"

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[Gzip] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

STATIC FUNCTION _ReadU32LE( cBytes )
RETURN hb_BCode( SubStr( cBytes, 1, 1 ) ) + ;
       hb_BCode( SubStr( cBytes, 2, 1 ) ) * 256 + ;
       hb_BCode( SubStr( cBytes, 3, 1 ) ) * 65536 + ;
       hb_BCode( SubStr( cBytes, 4, 1 ) ) * 16777216

FUNCTION HIX_TestGzip_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TLog( "=== HIX_TestGzip_Run start ===" )
   _GzipShouldCompress( hCtx )
   _GzipCompress(       hCtx )
   _GzipConfig(         hCtx )
   _TLog( "=== HIX_TestGzip_Run end ===" )
RETURN hCtx

STATIC PROCEDURE _GzipShouldCompress( hCtx )
   HixTU_Check( hCtx, HIX_GzipShouldCompress( "text/html" ),               "Gzip: text/html -> .T.",              ".T.", ".F." )
   HixTU_Check( hCtx, HIX_GzipShouldCompress( "application/json" ),        "Gzip: application/json -> .T.",       ".T.", ".F." )
   HixTU_Check( hCtx, HIX_GzipShouldCompress( "text/html; charset=utf-8" ),"Gzip: text/html;charset -> .T.",      ".T.", ".F." )
   HixTU_Check( hCtx, HIX_GzipShouldCompress( "application/javascript" ),  "Gzip: application/javascript -> .T.", ".T.", ".F." )
   HixTU_Check( hCtx, HIX_GzipShouldCompress( "text/css" ),                "Gzip: text/css -> .T.",               ".T.", ".F." )
   HixTU_Check( hCtx, HIX_GzipShouldCompress( "image/svg+xml" ),           "Gzip: image/svg+xml -> .T.",          ".T.", ".F." )
   HixTU_Check( hCtx, ! HIX_GzipShouldCompress( "image/png" ),             "Gzip: image/png -> .F.",              ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_GzipShouldCompress( "image/jpeg" ),            "Gzip: image/jpeg -> .F.",             ".F.", ".T." )
   HixTU_Check( hCtx, ! HIX_GzipShouldCompress( "application/octet-stream" ), "Gzip: octet-stream -> .F.",        ".F.", ".T." )
RETURN

STATIC PROCEDURE _GzipCompress( hCtx )
   LOCAL cData, cGzip, nCrcExpected, nCrcGot, nSizeGot

   HixTU_Check( hCtx, HIX_GzipCompress( "" ) == NIL, "Gzip: empty -> NIL", "NIL", "non-NIL" )

   cData := "Hello World"
   cGzip := HIX_GzipCompress( cData )
   HixTU_Check( hCtx, cGzip != NIL, "Gzip: non-empty -> non-NIL", "non-NIL", "NIL" )
   IF cGzip == NIL ; RETURN ; ENDIF

   HixTU_Check( hCtx, hb_BCode( SubStr( cGzip, 1, 1 ) ) == 31,  "Gzip: magic byte 1 (0x1f)", "31", hb_NToS( hb_BCode( SubStr( cGzip, 1, 1 ) ) ) )
   HixTU_Check( hCtx, hb_BCode( SubStr( cGzip, 2, 1 ) ) == 139, "Gzip: magic byte 2 (0x8b)", "139", hb_NToS( hb_BCode( SubStr( cGzip, 2, 1 ) ) ) )
   HixTU_Check( hCtx, hb_BCode( SubStr( cGzip, 3, 1 ) ) == 8,   "Gzip: compression method=8", "8", hb_NToS( hb_BCode( SubStr( cGzip, 3, 1 ) ) ) )

   nSizeGot := _ReadU32LE( SubStr( cGzip, Len( cGzip ) - 3, 4 ) )
   HixTU_Check( hCtx, nSizeGot == Len( cData ), "Gzip: isize=Len(original)", hb_NToS( Len(cData) ), hb_NToS( nSizeGot ) )

   nCrcExpected := hb_CRC32( cData, 0 )
   IF nCrcExpected < 0 ; nCrcExpected += 4294967296 ; ENDIF
   nCrcGot := _ReadU32LE( SubStr( cGzip, Len( cGzip ) - 7, 4 ) )
   HixTU_Check( hCtx, nCrcGot == nCrcExpected, "Gzip: crc32 correcto", hb_NToS( nCrcExpected ), hb_NToS( nCrcGot ) )

   cData := Replicate( "ABCDEFGHIJ", 200 )
   cGzip := HIX_GzipCompress( cData )
   HixTU_Check( hCtx, cGzip != NIL .AND. Len( cGzip ) < Len( cData ), "Gzip: output < input para datos compresibles", "smaller", "not smaller" )
RETURN

STATIC PROCEDURE _GzipConfig( hCtx )
   LOCAL lGzip, nMin, cFile, hCfg, oCfgSave

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )

   lGzip := HIX_GetConfig( "server", "gzip" )
   nMin  := HIX_GetConfig( "server", "gzip_min_size" )
   HixTU_Check( hCtx, lGzip,            "Gzip: default server.gzip=.T.",          ".T.",  iif(lGzip,".T.",".F.") )
   HixTU_Check( hCtx, nMin == 2048,     "Gzip: default server.gzip_min_size=2048","2048", hb_NToS(nMin) )

   // Override via hash mutation + persist/reload round-trip
   cFile := hb_DirTemp() + "hix_tm_gzip_" + hb_NToS( Int(Seconds()) ) + ".json"
   hCfg  := HIX_GetConfig()
   hCfg[ "server" ][ "gzip" ]          := .F.
   hCfg[ "server" ][ "gzip_min_size" ] := 4096
   HIX_SaveConfig( hCfg, cFile )
   HIX_LoadConfig( cFile )
   lGzip := HIX_GetConfig( "server", "gzip" )
   nMin  := HIX_GetConfig( "server", "gzip_min_size" )
   HixTU_Check( hCtx, ! lGzip,          "Gzip: JSON gzip=.F. round-trip",         ".F.",  iif(lGzip,".T.",".F.") )
   HixTU_Check( hCtx, nMin == 4096,     "Gzip: JSON gzip_min_size=4096",          "4096", hb_NToS(nMin) )
   hb_vfErase( cFile )

   HIX_SetConfig( oCfgSave )
RETURN
