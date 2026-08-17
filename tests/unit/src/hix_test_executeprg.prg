/*-----------------------------------------------------------
  File ......: hix_test_executeprg.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — THixDispatcher ExecutePrg
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"

// Uses shared TMockRequest from hix_test_utils.prg

STATIC FUNCTION _TmpRoot()
   LOCAL cRoot := hb_DirTemp() + "hix_tm_execprg" + hb_ps()
   LOCAL cEol  := hb_eol()
   IF ! hb_DirExists( cRoot ) ; hb_DirCreate( cRoot ) ; ENDIF
   hb_MemoWrit( cRoot + "page.prg",    "FUNCTION page()"   + cEol + "RETURN '<h1>Test</h1>'" )
   hb_MemoWrit( cRoot + "empty_s.prg", "FUNCTION page()"   + cEol + "RETURN ''" )
   hb_MemoWrit( cRoot + "nil.prg",     "FUNCTION page()"   + cEol + "RETURN NIL" )
   hb_MemoWrit( cRoot + "num.prg",     "FUNCTION page()"   + cEol + "RETURN 42" )
   hb_MemoWrit( cRoot + "badrun.prg",  "FUNCTION page()"   + cEol + ;
                                        "LOCAL x := NIL"   + cEol + ;
                                        "RETURN x:Foo()" )
   hb_MemoWrit( cRoot + "empty.prg",   "FUNCTION page()" + cEol + "RETURN NIL" + cEol )
RETURN cRoot

STATIC PROCEDURE _CleanTmpRoot( cRoot )
   LOCAL aFiles, aEntry
   IF ! hb_DirExists( cRoot ) ; RETURN ; ENDIF
   aFiles := Directory( cRoot + "*.*" )
   FOR EACH aEntry IN aFiles
      FErase( cRoot + aEntry[1] )
   NEXT
   hb_DirDelete( hb_StrShrink( cRoot, 1 ) )
RETURN

STATIC FUNCTION _Disp( cRoot )
   LOCAL o := THixDispatcher():New( cRoot )
   o:nExecTimeout := 0
RETURN o

STATIC FUNCTION _MockDispatch( oDisp, cPath )
   LOCAL oReq := TMockRequest():New( cPath, "GET" )
   oDisp:Dispatch( oReq )
RETURN oReq

FUNCTION HIX_TestExecutePrg_Run()
   LOCAL hCtx   := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cTmpRoot
   HIX_MetricsInit()
   HIX_ZombieInit()
   cTmpRoot := _TmpRoot()
   _ExecRetornos( hCtx, cTmpRoot )
   _ExecErrores(  hCtx, cTmpRoot )
   _ExecDispatch( hCtx, cTmpRoot )
   _CleanTmpRoot( cTmpRoot )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _ExecRetornos( hCtx, cRoot )
   LOCAL oDisp := _Disp( cRoot )
   LOCAL cResult
   cResult := oDisp:ExecutePrg( cRoot + "page.prg" )
   HixTU_Check( hCtx, cResult == "<h1>Test</h1>", "ExecPrg: valido -> HTML",  "<h1>Test</h1>", cResult )
   cResult := oDisp:ExecutePrg( cRoot + "empty_s.prg" )
   HixTU_Check( hCtx, cResult == "",              "ExecPrg: retorna '' -> ''", "''",            cResult )
   cResult := oDisp:ExecutePrg( cRoot + "nil.prg" )
   HixTU_Check( hCtx, cResult == "",              "ExecPrg: retorna NIL -> ''","''",            cResult )
   cResult := oDisp:ExecutePrg( cRoot + "num.prg" )
   HixTU_Check( hCtx, cResult == "42",            "ExecPrg: retorna num -> '42'","'42'",        cResult )
RETURN

STATIC PROCEDURE _ExecErrores( hCtx, cRoot )
   LOCAL oDisp  := _Disp( cRoot )
   LOCAL cResult, oErr
   cResult := ""
   oErr    := NIL
   BEGIN SEQUENCE WITH {|e| Break(e)}
      cResult := oDisp:ExecutePrg( "C:\no_existe_nunca.prg" )
   RECOVER USING oErr
   END SEQUENCE
   HixTU_Check( hCtx, oErr != NIL, "ExecPrg: fichero no existe -> lanza", "lanzado", iif( oErr == NIL, "no lanzado", "lanzado" ) )
   TRY
      cResult := oDisp:ExecutePrg( cRoot + "empty.prg" )
      HixTU_Check( hCtx, cResult == "", "ExecPrg: NIL -> ''", "''", cResult )
   CATCH oErr
      HixTU_Fail( hCtx, "ExecPrg: NIL -> ''", "''", "lanzado: " + oErr:description )
   END
   oErr    := NIL
   cResult := ""
   BEGIN SEQUENCE WITH {|e| Break(e)}
      cResult := oDisp:ExecutePrg( cRoot + "badrun.prg" )
   RECOVER USING oErr
   END SEQUENCE
   HixTU_Check( hCtx, oErr != NIL,            "ExecPrg: error runtime -> lanza",      "lanzado", iif( oErr == NIL, "no lanzado", "lanzado" ) )
   HixTU_Check( hCtx, ValType( oErr ) == "O", "ExecPrg: error runtime -> obj Error",  "O",        ValType( oErr ) )
   HB_SYMBOL_UNUSED( cResult )
RETURN

STATIC PROCEDURE _ExecDispatch( hCtx, cRoot )
   LOCAL oDisp := _Disp( cRoot )
   LOCAL oReq
   oReq := _MockDispatch( oDisp, "/page.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 200,              "ExecDisp: .prg -> 200",       "200",           hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "<h1>Test</h1>",   "ExecDisp: .prg body correcto","<h1>Test</h1>", oReq:cBody )
   HixTU_Check( hCtx, oReq:cMime == "html",             "ExecDisp: .prg mime 'html'",  "html",          oReq:cMime )
RETURN
