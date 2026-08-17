/*-----------------------------------------------------------
  File ......: hix_test_abort.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — HixShouldAbort() timeout mechanism
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"

// Uses shared TMockRequest from hix_test_utils.prg

FUNCTION HIX_TestAbort_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   _TestNoAbortOutsideTimeout( hCtx )
   _TestAbortOnTimeout(        hCtx )
   _TestNormalCompletionNoAbort( hCtx )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _TestNoAbortOutsideTimeout( hCtx )
   LOCAL lAbort
   lAbort := HixShouldAbort()
   HixTU_Check( hCtx, ! lAbort, "Abort: HixShouldAbort()=.F. fuera de contexto", ".F.", iif( lAbort, ".T.", ".F." ) )
RETURN

STATIC PROCEDURE _TestAbortOnTimeout( hCtx )
   LOCAL oDisp, hCfg, oCfgSave, oReq, oErr
   LOCAL cTmpDir, cPrgPath, cFlagFile
   LOCAL lGot504, cFlag

   cTmpDir   := hb_DirTemp() + "hix_tm_abort" + hb_ps()
   cPrgPath  := cTmpDir + "abort_loop.prg"
   cFlagFile := hb_DirTemp() + "abort_test.flag"

   IF ! hb_DirExists( cTmpDir ) ; hb_DirCreate( cTmpDir ) ; ENDIF
   IF hb_FileExists( cFlagFile ) ; hb_FileDelete( cFlagFile ) ; ENDIF

   hb_MemoWrit( cPrgPath, ;
      "FUNCTION Main()" + hb_eol() + ;
      "   LOCAL n" + hb_eol() + ;
      "   FOR n := 1 TO 10000" + hb_eol() + ;
      "      hb_idleSleep( 0.010 )" + hb_eol() + ;
      "      IF HixShouldAbort()" + hb_eol() + ;
      "         hb_MemoWrit( hb_DirTemp() + 'abort_test.flag', 'aborted' )" + hb_eol() + ;
      "         RETURN ''" + hb_eol() + ;
      "      ENDIF" + hb_eol() + ;
      "   NEXT" + hb_eol() + ;
      "   hb_MemoWrit( hb_DirTemp() + 'abort_test.flag', 'completed' )" + hb_eol() + ;
      "RETURN ''" + hb_eol() )

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )
   hCfg     := HIX_GetConfig()
   hCfg[ "app" ][ "env" ]  := "dev"
   hCfg[ "paths"    ][ "root" ] := hb_StrShrink( cTmpDir, 1 )

   oDisp              := THixDispatcher():New( hb_StrShrink( cTmpDir, 1 ) )
   oDisp:nExecTimeout := 300

   oReq := TMockRequest():New( "/abort_loop.prg", "GET" )

   lGot504 := .F.
   oErr    := NIL
   TRY
      oDisp:Dispatch( oReq )
   CATCH oErr
      lGot504 := ( ValType( oErr ) == "O" .AND. oErr:subCode == 504 )
   END

   HixTU_Check( hCtx, lGot504, "Abort: dispatcher lanza 504", ".T.", ;
           iif( lGot504, ".T.", hb_CStr( iif( ValType(oErr)=="O", oErr:subCode, "no-error" ) ) ) )

   hb_idleSleep( 0.8 )

   cFlag := AllTrim( hb_MemoRead( cFlagFile ) )
   HixTU_Check( hCtx, cFlag == "aborted", "Abort: hijo detecto HixShouldAbort()", "aborted", ;
           iif( Empty( cFlag ), "(flag vacio)", cFlag ) )

   HIX_SetConfig( oCfgSave )
   IF hb_FileExists( cPrgPath )  ; hb_FileDelete( cPrgPath )  ; ENDIF
   IF hb_FileExists( cFlagFile ) ; hb_FileDelete( cFlagFile ) ; ENDIF
   IF hb_DirExists( hb_StrShrink( cTmpDir, 1 ) ) ; hb_DirDelete( hb_StrShrink( cTmpDir, 1 ) ) ; ENDIF
RETURN

STATIC PROCEDURE _TestNormalCompletionNoAbort( hCtx )
   LOCAL oDisp, hCfg, oCfgSave, oReq, oErr
   LOCAL cTmpDir, cPrgPath, cFlagFile
   LOCAL lOk, cFlag

   cTmpDir   := hb_DirTemp() + "hix_tm_abort2" + hb_ps()
   cPrgPath  := cTmpDir + "normal_loop.prg"
   cFlagFile := hb_DirTemp() + "abort_normal.flag"

   IF ! hb_DirExists( cTmpDir ) ; hb_DirCreate( cTmpDir ) ; ENDIF
   IF hb_FileExists( cFlagFile ) ; hb_FileDelete( cFlagFile ) ; ENDIF

   hb_MemoWrit( cPrgPath, ;
      "FUNCTION Main()" + hb_eol() + ;
      "   LOCAL n, lAborted" + hb_eol() + ;
      "   lAborted := .F." + hb_eol() + ;
      "   FOR n := 1 TO 5" + hb_eol() + ;
      "      hb_idleSleep( 0.010 )" + hb_eol() + ;
      "      IF HixShouldAbort()" + hb_eol() + ;
      "         lAborted := .T." + hb_eol() + ;
      "         EXIT" + hb_eol() + ;
      "      ENDIF" + hb_eol() + ;
      "   NEXT" + hb_eol() + ;
      "   hb_MemoWrit( hb_DirTemp() + 'abort_normal.flag', iif( lAborted, 'aborted', 'ok' ) )" + hb_eol() + ;
      "RETURN ''" + hb_eol() )

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )
   hCfg     := HIX_GetConfig()
   hCfg[ "app" ][ "env" ]  := "dev"
   hCfg[ "paths"    ][ "root" ] := hb_StrShrink( cTmpDir, 1 )

   oDisp              := THixDispatcher():New( hb_StrShrink( cTmpDir, 1 ) )
   oDisp:nExecTimeout := 5000

   oReq := TMockRequest():New( "/normal_loop.prg", "GET" )

   lOk  := .F.
   oErr := NIL
   TRY
      oDisp:Dispatch( oReq )
      lOk := .T.
   CATCH oErr
   END

   HixTU_Check( hCtx, lOk, "Abort: ejecucion normal sin excepcion", ".T.", ;
           iif( lOk, ".T.", iif( ValType(oErr)=="O", hb_NToS(oErr:subCode), "error" ) ) )

   hb_idleSleep( 0.2 )

   cFlag := AllTrim( hb_MemoRead( cFlagFile ) )
   HixTU_Check( hCtx, cFlag == "ok", "Abort: sin timeout, hijo completo sin abort", "ok", ;
           iif( Empty( cFlag ), "(flag vacio)", cFlag ) )

   HIX_SetConfig( oCfgSave )
   IF hb_FileExists( cPrgPath )  ; hb_FileDelete( cPrgPath )  ; ENDIF
   IF hb_FileExists( cFlagFile ) ; hb_FileDelete( cFlagFile ) ; ENDIF
   IF hb_DirExists( hb_StrShrink( cTmpDir, 1 ) ) ; hb_DirDelete( hb_StrShrink( cTmpDir, 1 ) ) ; ENDIF
RETURN
