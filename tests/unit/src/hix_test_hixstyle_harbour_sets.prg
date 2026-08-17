/*-----------------------------------------------------------
  File ......: hix_test_hixstyle_harbour_sets.prg
  Author.....: Charly 9000
  Created....: 2026-07-13
  Version....: 1.0.0
  Description: Integrated test - HIX_HarbourConfigApply()
               Verifies that Harbour Set(_SET_*) and RddSetDefault
               are applied from the "sets" and "dbf" sections of
               config.json. Uses HIX_ConfigAppSet() to inject the
               config in-memory (no physical JSON needed).
  Usage      : called from app.prg _TestGroups() as
               HIX_TestHixstyleHarbourSets_Run
  Notes      : Sets are global to the process; the test restores
               previous values on exit so it does not leak state
               to sibling tests.
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"
#include "set.ch"
#include "fileio.ch"

// -------------------------------------------------------
// Snapshot/restore helpers - Sets are process-global
// -------------------------------------------------------
STATIC FUNCTION _Snapshot()
   LOCAL hSnap := { => }
   hSnap["dateformat"] := Set( _SET_DATEFORMAT )
   hSnap["decimals"]   := Set( _SET_DECIMALS )
   hSnap["deleted"]    := Set( _SET_DELETED )
   hSnap["epoch"]      := Set( _SET_EPOCH )
   hSnap["exact"]      := Set( _SET_EXACT )
   hSnap["exclusive"]  := Set( _SET_EXCLUSIVE )
   hSnap["fixed"]      := Set( _SET_FIXED )
   hSnap["softseek"]   := Set( _SET_SOFTSEEK )
   hSnap["dbcodepage"] := Set( _SET_DBCODEPAGE )
   hSnap["lang"]       := HB_LANGSELECT()
   hSnap["rdd"]        := RddSetDefault()
RETURN hSnap

STATIC PROCEDURE _Restore( hSnap )
   Set( _SET_DATEFORMAT, hSnap["dateformat"] )
   Set( _SET_DECIMALS,   hSnap["decimals"] )
   Set( _SET_DELETED,    hSnap["deleted"] )
   Set( _SET_EPOCH,      hSnap["epoch"] )
   Set( _SET_EXACT,      hSnap["exact"] )
   Set( _SET_EXCLUSIVE,  hSnap["exclusive"] )
   Set( _SET_FIXED,      hSnap["fixed"] )
   Set( _SET_SOFTSEEK,   hSnap["softseek"] )
   Set( _SET_DBCODEPAGE, hSnap["dbcodepage"] )
   HB_LANGSELECT( hSnap["lang"] )
   RddSetDefault( hSnap["rdd"] )
RETURN

// -------------------------------------------------------
// Root
// -------------------------------------------------------
FUNCTION HIX_TestHixstyleHarbourSets_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL hSnap := _Snapshot()

   _Defaults(       hCtx )
   _CustomSets(     hCtx )
   _LangSpanish(    hCtx )
   _LangUnknown(    hCtx )
   _DbfRddCustom(   hCtx )

   _Restore( hSnap )
   HIX_ConfigAppSet( "sets", NIL )
   HIX_ConfigAppSet( "dbf",  NIL )

   _DumpFailures( hCtx )
RETURN hCtx

STATIC PROCEDURE _DumpFailures( hCtx )
   LOCAL hRes, nH, cOut := "=== HixstyleSets failures ===" + hb_eol()
   FOR EACH hRes IN hCtx["results"]
      IF hRes["status"] == "fail"
         cOut += hRes["name"] + " | expected=" + hRes["exp"] + " got=" + hRes["got"] + hb_eol()
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
// 1. Sin "sets" ni "dbf" -> defaults
// -------------------------------------------------------
STATIC PROCEDURE _Defaults( hCtx )
   HIX_ConfigAppSet( "sets", NIL )
   HIX_ConfigAppSet( "dbf",  NIL )

   HIX_HarbourConfigApply()

   HixTU_Check( hCtx, Set( _SET_DATEFORMAT ) == "dd/mm/yy", ;
      "Sets: dateformat default", "dd/mm/yy", Set( _SET_DATEFORMAT ) )
   HixTU_Check( hCtx, Set( _SET_DECIMALS ) == 2, ;
      "Sets: decimals default", "2", hb_NToS( Set( _SET_DECIMALS ) ) )
   HixTU_Check( hCtx, Set( _SET_DELETED ) == .F., ;
      "Sets: deleted default .F.", ".F.", iif( Set( _SET_DELETED ), ".T.", ".F." ) )
   HixTU_Check( hCtx, Set( _SET_EPOCH ) == 1900, ;
      "Sets: epoch default", "1900", hb_NToS( Set( _SET_EPOCH ) ) )
   HixTU_Check( hCtx, RddSetDefault() == "DBFCDX", ;
      "Dbf: rdd default DBFCDX", "DBFCDX", RddSetDefault() )
RETURN

// -------------------------------------------------------
// 2. Con "sets" custom
// -------------------------------------------------------
STATIC PROCEDURE _CustomSets( hCtx )
   HIX_ConfigAppSet( "sets", { ;
      "dateformat" => "yyyy-mm-dd", ;
      "decimals"   => 4, ;
      "deleted"    => .T., ;
      "epoch"      => 1980, ;
      "exact"      => .T., ;
      "softseek"   => .T., ;
      "language"   => "EN" ;
   } )
   HIX_ConfigAppSet( "dbf", NIL )

   HIX_HarbourConfigApply()

   HixTU_Check( hCtx, Set( _SET_DATEFORMAT ) == "yyyy-mm-dd", ;
      "Sets: dateformat custom", "yyyy-mm-dd", Set( _SET_DATEFORMAT ) )
   HixTU_Check( hCtx, Set( _SET_DECIMALS ) == 4, ;
      "Sets: decimals custom", "4", hb_NToS( Set( _SET_DECIMALS ) ) )
   HixTU_Check( hCtx, Set( _SET_DELETED ) == .T., ;
      "Sets: deleted custom .T.", ".T.", iif( Set( _SET_DELETED ), ".T.", ".F." ) )
   HixTU_Check( hCtx, Set( _SET_EPOCH ) == 1980, ;
      "Sets: epoch custom", "1980", hb_NToS( Set( _SET_EPOCH ) ) )
   HixTU_Check( hCtx, Set( _SET_EXACT ) == .T., ;
      "Sets: exact custom .T.", ".T.", iif( Set( _SET_EXACT ), ".T.", ".F." ) )
   HixTU_Check( hCtx, Set( _SET_SOFTSEEK ) == .T., ;
      "Sets: softseek custom .T.", ".T.", iif( Set( _SET_SOFTSEEK ), ".T.", ".F." ) )
RETURN

// -------------------------------------------------------
// 3. language=ES -> ESWIN codepage
// -------------------------------------------------------
STATIC PROCEDURE _LangSpanish( hCtx )
   HIX_ConfigAppSet( "sets", { "language" => "ES" } )
   HIX_ConfigAppSet( "dbf",  NIL )

   HIX_HarbourConfigApply()

   HixTU_Check( hCtx, Upper( Left( HB_LANGSELECT(), 2 ) ) == "ES", ;
      "Lang: HB_LANGSELECT ES", "ES", HB_LANGSELECT() )
   HixTU_Check( hCtx, Set( _SET_DBCODEPAGE ) == "ESWIN", ;
      "Lang: dbcodepage ES", "ESWIN", Set( _SET_DBCODEPAGE ) )
RETURN

// -------------------------------------------------------
// 4. language desconocido -> cae en EN
// -------------------------------------------------------
STATIC PROCEDURE _LangUnknown( hCtx )
   HIX_ConfigAppSet( "sets", { "language" => "XX" } )
   HIX_ConfigAppSet( "dbf",  NIL )

   HIX_HarbourConfigApply()

   HixTU_Check( hCtx, Upper( Left( HB_LANGSELECT(), 2 ) ) == "EN", ;
      "Lang: XX cae en EN", "EN", HB_LANGSELECT() )
   HixTU_Check( hCtx, Set( _SET_DBCODEPAGE ) == "EN", ;
      "Lang: XX dbcodepage EN", "EN", Set( _SET_DBCODEPAGE ) )
RETURN

// -------------------------------------------------------
// 5. dbf.rddname custom
// -------------------------------------------------------
STATIC PROCEDURE _DbfRddCustom( hCtx )
   HIX_ConfigAppSet( "sets", NIL )
   HIX_ConfigAppSet( "dbf",  { "rddname" => "DBFNTX" } )

   HIX_HarbourConfigApply()

   HixTU_Check( hCtx, RddSetDefault() == "DBFNTX", ;
      "Dbf: rdd custom DBFNTX", "DBFNTX", RddSetDefault() )
RETURN
