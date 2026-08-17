/*-----------------------------------------------------------
  File ......: hix_test_config_autocreate.prg
  Author.....: Charly 9000
  Created....: 2026-07-13
  Modified...: 2026-07-13
  Version....: 1.0.0
  Description: Integrated test - config.json autocreate + merge.
               Exercises HIX_ConfigAppDefaults / Reset / Save /
               Load / Merge in isolation (no server bootstrap).
               Verifies:
                 1) Autocreate: writes defaults when file missing.
                 2) Round-trip: save + load recovers same values.
                 3) No-overwrite: user values survive merge.
                 4) Backfill: missing default keys are injected.
  Usage      : called from app.prg _TestGroups() as
               HIX_TestConfigAutocreate_Run
  Notes      : Uses hb_DirTemp() for temp files. Cleans up on exit.
 -----------------------------------------------------------*/

#INCLUDE "hix_logger.ch"
#INCLUDE "fileio.ch"

STATIC FUNCTION _TmpFile()
RETURN hb_DirTemp() + "hix_autocfg_" + hb_ntos( hb_MilliSeconds() ) + ".json"

FUNCTION HIX_TestConfigAutocreate_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _Autocreate(  hCtx )
   _RoundTrip(   hCtx )
   _NoOverwrite( hCtx )
   _Backfill(    hCtx )

   HIX_ConfigAppSet( "sets", NIL )
   HIX_ConfigAppSet( "dbf",  NIL )

   _DumpFailures( hCtx )

RETURN hCtx

STATIC PROCEDURE _DumpFailures( hCtx )

   LOCAL hRes, nH, cOut := "=== ConfigAutocreate failures ===" + hb_eol()

   FOR EACH hRes IN hCtx[ "results" ]

      IF hRes[ "status" ] == "fail"

         cOut += hRes[ "name" ] + " | expected=" + hRes[ "exp" ] + " got=" + hRes[ "got" ] + hb_eol()

      ENDIF

   NEXT

   // Anexar, nunca hb_MemoWrit(): info.txt es el log compartido de todos
   // los tests y truncarlo borra las trazas de los que ya han corrido.
   nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )

   IF nH != NIL

      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, cOut )
      hb_vfClose( nH )

   ENDIF

RETURN

// -------------------------------------------------------
// 1. Autocreate: file missing -> defaults saved to disk
// -------------------------------------------------------
STATIC PROCEDURE _Autocreate( hCtx )

   LOCAL cFile := _TmpFile()
   LOCAL cRaw, hDisk, lOk

   IF File( cFile ) ; FErase( cFile ) ; ENDIF

   HIX_ConfigAppReset( HIX_ConfigAppDefaults() )
   lOk := HIX_ConfigAppSave( cFile )

   HixTU_Check( hCtx, lOk, ;
      "Autocreate: save returns .T.", ".T.", iif( lOk, ".T.", ".F." ) )

   HixTU_Check( hCtx, File( cFile ), ;
      "Autocreate: file exists after save", "exists", iif( File( cFile ), "exists", "missing" ) )

   cRaw := hb_MemoRead( cFile )

   HixTU_Check( hCtx, ! Empty( cRaw ), ;
      "Autocreate: file not empty", "non-empty", "len=" + hb_ntos( Len( cRaw ) ) )

   IF hb_jsonDecode( cRaw, @hDisk ) == 0 .OR. ! HB_ISHASH( hDisk )

      HixTU_Check( hCtx, .F., "Autocreate: JSON decode", "hash", "parse-error" )

      IF File( cFile ) ; FErase( cFile ) ; ENDIF

      RETURN

   ENDIF

   HixTU_Check( hCtx, hb_HHasKey( hDisk, "sets" ), ;
      "Autocreate: section [sets] present", "yes", iif( hb_HHasKey( hDisk, "sets" ), "yes", "no" ) )

   HixTU_Check( hCtx, hb_HHasKey( hDisk, "dbf" ), ;
      "Autocreate: section [dbf] present", "yes", iif( hb_HHasKey( hDisk, "dbf" ), "yes", "no" ) )

   HixTU_Check( hCtx, hDisk[ "sets" ][ "language" ] == "EN", ;
      "Autocreate: sets.language default", "EN", hb_CStr( hDisk[ "sets" ][ "language" ] ) )

   HixTU_Check( hCtx, hDisk[ "dbf" ][ "rddname" ] == "DBFCDX", ;
      "Autocreate: dbf.rddname default", "DBFCDX", hb_CStr( hDisk[ "dbf" ][ "rddname" ] ) )

   IF File( cFile ) ; FErase( cFile ) ; ENDIF

RETURN

// -------------------------------------------------------
// 2. Round-trip: save + load recovers same values
// -------------------------------------------------------
STATIC PROCEDURE _RoundTrip( hCtx )

   LOCAL cFile := _TmpFile()
   LOCAL xSets

   IF File( cFile ) ; FErase( cFile ) ; ENDIF

   HIX_ConfigAppReset( HIX_ConfigAppDefaults() )
   HIX_ConfigAppSet( "sets", { "language" => "ES", "decimals" => 4 } )
   HIX_ConfigAppSave( cFile )

   HIX_ConfigAppReset( { => } )
   HIX_ConfigAppLoad( cFile )

   xSets := HIX_ConfigApp( "sets", NIL )

   HixTU_Check( hCtx, HB_ISHASH( xSets ), ;
      "RoundTrip: sets is hash after load", "H", ValType( xSets ) )

   IF ! HB_ISHASH( xSets ) ; RETURN ; ENDIF

   HixTU_Check( hCtx, xSets[ "language" ] == "ES", ;
      "RoundTrip: language persisted", "ES", hb_CStr( xSets[ "language" ] ) )

   HixTU_Check( hCtx, xSets[ "decimals" ] == 4, ;
      "RoundTrip: decimals persisted", "4", hb_CStr( xSets[ "decimals" ] ) )

   IF File( cFile ) ; FErase( cFile ) ; ENDIF

RETURN

// -------------------------------------------------------
// 3. No-overwrite: user values survive merge with defaults
// -------------------------------------------------------
STATIC PROCEDURE _NoOverwrite( hCtx )

   LOCAL nAdded

   HIX_ConfigAppReset( { ;
      "sets" => { "language" => "ES", "decimals" => 6 }, ;
      "dbf"  => { "rddname"  => "DBFNTX" }               ;
      } )

   nAdded := HIX_ConfigAppMerge( HIX_ConfigAppDefaults() )

   HixTU_Check( hCtx, HIX_ConfigApp( "sets" )[ "language" ] == "ES", ;
      "NoOverwrite: user language kept", "ES", hb_CStr( HIX_ConfigApp( "sets" )[ "language" ] ) )

   HixTU_Check( hCtx, HIX_ConfigApp( "sets" )[ "decimals" ] == 6, ;
      "NoOverwrite: user decimals kept", "6", hb_ntos( HIX_ConfigApp( "sets" )[ "decimals" ] ) )

   HixTU_Check( hCtx, HIX_ConfigApp( "dbf" )[ "rddname" ] == "DBFNTX", ;
      "NoOverwrite: user rddname kept", "DBFNTX", hb_CStr( HIX_ConfigApp( "dbf" )[ "rddname" ] ) )

   HixTU_Check( hCtx, hb_HHasKey( HIX_ConfigApp( "sets" ), "dateformat" ), ;
      "NoOverwrite: missing default key added", "yes", ;
      iif( hb_HHasKey( HIX_ConfigApp( "sets" ), "dateformat" ), "yes", "no" ) )

   HixTU_Check( hCtx, nAdded > 0, ;
      "NoOverwrite: merge reports keys added", ">0", hb_ntos( nAdded ) )

RETURN

// -------------------------------------------------------
// 4. Backfill: partial file on disk gets defaults injected
// -------------------------------------------------------
STATIC PROCEDURE _Backfill( hCtx )

   LOCAL cFile := _TmpFile()
   LOCAL nAdded

   IF File( cFile ) ; FErase( cFile ) ; ENDIF

   hb_MemoWrit( cFile, '{ "sets": { "language": "FR" } }' )

   HIX_ConfigAppReset( { => } )
   HIX_ConfigAppLoad( cFile )
   nAdded := HIX_ConfigAppMerge( HIX_ConfigAppDefaults() )

   HixTU_Check( hCtx, HIX_ConfigApp( "sets" )[ "language" ] == "FR", ;
      "Backfill: legacy language kept", "FR", hb_CStr( HIX_ConfigApp( "sets" )[ "language" ] ) )

   HixTU_Check( hCtx, hb_HHasKey( HIX_ConfigApp( "sets" ), "epoch" ), ;
      "Backfill: default epoch injected", "yes", ;
      iif( hb_HHasKey( HIX_ConfigApp( "sets" ), "epoch" ), "yes", "no" ) )

   HixTU_Check( hCtx, HB_ISHASH( HIX_ConfigApp( "dbf", NIL ) ), ;
      "Backfill: [dbf] section injected", "hash", ValType( HIX_ConfigApp( "dbf", NIL ) ) )

   HixTU_Check( hCtx, nAdded > 0, ;
      "Backfill: merge added keys", ">0", hb_ntos( nAdded ) )

   IF File( cFile ) ; FErase( cFile ) ; ENDIF

RETURN
