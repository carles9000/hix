/*-----------------------------------------------------------
  File ......: hix_test_view_code_err.prg
  Author.....: Charly 9000
  Created....: 2026-06-06
  Description: Integrated test — HIX_View_Viewer runtime errors inside
               {{ expr }} expressions. @prg/@if suites omitted: they
               trigger hb_CompileFromBuf() which calls exit() on invalid
               syntax and kills the server process (uncatchable).
 -----------------------------------------------------------*/
#include "fileio.ch"
#include "hix_const.ch"

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[ViewCodeErr] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

STATIC FUNCTION _MakeVCEViewer()
   LOCAL oView := HIX_View_Viewer():New()
   oView:lDebug           := .F.
   oView:lCache           := .F.
   oView:llSaveTranspiled := .F.
   oView:lStrictMode      := .F.
   oView:SetPathView( hb_DirBase() + "www" )
RETURN oView

STATIC FUNCTION _RunVCE( cTemplate )
   LOCAL oErr, oView
   oErr := NIL
   TRY
      oView := _MakeVCEViewer()
      oView:SetPrg( "/views/test/" + cTemplate )
      oView:Render()
   CATCH oErr
   END
RETURN oErr

STATIC PROCEDURE _CheckVCE( hCtx, cLabel, oErr, nViewCode, cModule, lNeedLine, lNeedCode, lNeedACode )
   LOCAL hC, nLine, cLineCode, aCode, cVC, cMod
   hb_default( @lNeedLine,  .T. )
   hb_default( @lNeedCode,  .T. )
   hb_default( @lNeedACode, .T. )

   HixTU_Check( hCtx, ValType( oErr ) == "O",        cLabel + ": error es objeto",  "O",  ValType( oErr ) )
   IF ValType( oErr ) != "O"
      HixTU_Fail( hCtx, cLabel + ": view_code",   hb_NToS( nViewCode ), "no obj" )
      HixTU_Fail( hCtx, cLabel + ": module",      cModule,               "no obj" )
      IF lNeedLine  ; HixTU_Fail( hCtx, cLabel + ": line>0",    ">0",     "no obj" ) ; ENDIF
      IF lNeedCode  ; HixTU_Fail( hCtx, cLabel + ": line_code", "!empty", "no obj" ) ; ENDIF
      IF lNeedACode ; HixTU_Fail( hCtx, cLabel + ": aCode",     "A",      "no obj" ) ; ENDIF
      RETURN
   ENDIF
   HixTU_Check( hCtx, ValType( oErr:cargo ) == "H", cLabel + ": cargo es hash",    "H",  ValType( oErr:cargo ) )
   IF ValType( oErr:cargo ) != "H"
      HixTU_Fail( hCtx, cLabel + ": view_code",   hb_NToS( nViewCode ), "no cargo" )
      HixTU_Fail( hCtx, cLabel + ": module",      cModule,               "no cargo" )
      IF lNeedLine  ; HixTU_Fail( hCtx, cLabel + ": line>0",    ">0",     "no cargo" ) ; ENDIF
      IF lNeedCode  ; HixTU_Fail( hCtx, cLabel + ": line_code", "!empty", "no cargo" ) ; ENDIF
      IF lNeedACode ; HixTU_Fail( hCtx, cLabel + ": aCode",     "A",      "no cargo" ) ; ENDIF
      RETURN
   ENDIF
   hC        := oErr:cargo
   nLine     := hb_HGetDef( hC, "line",      0  )
   cLineCode := hb_HGetDef( hC, "line_code", "" )
   aCode     := hb_HGetDef( hC, "aCode",     {} )
   cVC       := hb_NToS( hb_HGetDef( hC, "view_code", 0 ) )
   cMod      := hb_HGetDef( hC, "module",    "" )
   HixTU_Check( hCtx, hb_HGetDef( hC, "view_code", 0 ) == nViewCode, cLabel + ": view_code=" + hb_NToS( nViewCode ), hb_NToS( nViewCode ), cVC )
   HixTU_Check( hCtx, cMod == cModule,                                cLabel + ": module=" + cModule,                  cModule,              cMod )
   IF lNeedLine
      HixTU_Check( hCtx, ValType( nLine ) == "N" .AND. nLine > 0,    cLabel + ": line>0", ">0", hb_NToS( iif( ValType(nLine)=="N", nLine, -1 ) ) )
   ENDIF
   IF lNeedCode
      HixTU_Check( hCtx, ! Empty( cLineCode ), cLabel + ": line_code !empty", "!empty", iif( Empty(cLineCode), "empty", "ok" ) )
   ENDIF
   IF lNeedACode
      HixTU_Check( hCtx, ValType( aCode ) == "A" .AND. Len( aCode ) > 0, cLabel + ": aCode A+len>0", "A+len>0", ;
                   iif( ValType(aCode)!="A", "not array", "len=" + hb_NToS(Len(aCode)) ) )
   ENDIF
RETURN

FUNCTION HIX_TestViewCodeErr_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TLog( "=== HIX_TestViewCodeErr_Run start ===" )
   _VCERuntime9004(    hCtx )
   _VCEPrgRuntime9004( hCtx )
   _VCEParser9001(     hCtx )
   _TLog( "=== HIX_TestViewCodeErr_Run end ===" )
RETURN hCtx

// Suite 1: {{ expr }} runtime errors — macro eval does NOT call hb_CompileFromBuf().
// Suite 2: @prg runtime — syntax is VALID so hb_CompileFromBuf() succeeds; errors
//          are load-time (NOFUNC) or runtime (ZERODIV), both catchable.
// Suite 3: parser 9001 unclosed {{ }} — caught before any compilation (strict mode).
// Excluded: @prg SYNTAX errors (hb_CompileFromBuf exits on invalid syntax).
STATIC PROCEDURE _VCERuntime9004( hCtx )
   LOCAL oErr
   _TLog( "_VCERuntime9004" )

   oErr := _RunVCE( "err_divzero.html" )
   HixTU_Check( hCtx, ValType( oErr ) == "O" .AND. ValType( oErr:cargo ) == "H", ;
                "ZERODIV: error capturado", "O+H", iif( ValType(oErr)=="O", ValType(oErr:cargo), "no obj" ) )
   _CheckVCE( hCtx, "ZERODIV", oErr, 9004, "hix_view_viewer", .T., .T., .T. )

   oErr := _RunVCE( "err_nofunc.html" )
   HixTU_Check( hCtx, ValType( oErr ) == "O" .AND. ValType( oErr:cargo ) == "H", ;
                "NOFUNC: error capturado", "O+H", iif( ValType(oErr)=="O", ValType(oErr:cargo), "no obj" ) )
   _CheckVCE( hCtx, "NOFUNC", oErr, 9004, "hix_view_viewer", .F., .F., .F. )

   oErr := _RunVCE( "err_nilaccess.html" )
   HixTU_Check( hCtx, ValType( oErr ) == "O" .AND. ValType( oErr:cargo ) == "H", ;
                "TYPEERR: error capturado", "O+H", iif( ValType(oErr)=="O", ValType(oErr:cargo), "no obj" ) )
   _CheckVCE( hCtx, "TYPEERR", oErr, 9004, "hix_view_viewer", .T., .T., .T. )
RETURN

STATIC PROCEDURE _VCEPrgRuntime9004( hCtx )
   LOCAL oErr
   _TLog( "_VCEPrgRuntime9004" )

   oErr := _RunVCE( "err_prg_nofunc.html" )
   HixTU_Check( hCtx, ValType( oErr ) == "O" .AND. ValType( oErr:cargo ) == "H", ;
                "PRG-NOFUNC: error capturado", "O+H", iif( ValType(oErr)=="O", ValType(oErr:cargo), "no obj" ) )
   _CheckVCE( hCtx, "PRG-NOFUNC", oErr, 9004, "hix_view_viewer", .F., .F., .F. )

   oErr := _RunVCE( "err_prg_divzero.html" )
   HixTU_Check( hCtx, ValType( oErr ) == "O" .AND. ValType( oErr:cargo ) == "H", ;
                "PRG-ZERODIV: error capturado", "O+H", iif( ValType(oErr)=="O", ValType(oErr:cargo), "no obj" ) )
   _CheckVCE( hCtx, "PRG-ZERODIV", oErr, 9004, "hix_view_viewer", .T., .T., .T. )
RETURN

STATIC PROCEDURE _VCEParser9001( hCtx )
   LOCAL oErr, oView
   _TLog( "_VCEParser9001" )

   oErr := NIL
   TRY
      oView := _MakeVCEViewer()
      oView:lStrictMode := .T.
      oView:SetPrg( "/views/test/err_parse_unclosed.html" )
      oView:Render()
   CATCH oErr
   END
   HixTU_Check( hCtx, ValType( oErr ) == "O" .AND. ValType( oErr:cargo ) == "H", ;
                "PARSE: error capturado", "O+H", iif( ValType(oErr)=="O", ValType(oErr:cargo), "no obj" ) )
   _CheckVCE( hCtx, "PARSE", oErr, 9001, "hix_view_parser", .T., .T., .T. )
   IF ValType( oErr ) == "O" .AND. ValType( oErr:cargo ) == "H"
      HixTU_Check( hCtx, oErr:cargo["line"] == 3, "PARSE: line=3", "3", ;
                   hb_NToS( iif( ValType( oErr:cargo["line"] ) == "N", oErr:cargo["line"], -1 ) ) )
      HixTU_Check( hCtx, ValType( oErr:cargo["aCode"] ) == "A" .AND. Len( oErr:cargo["aCode"] ) >= 3, ;
                   "PARSE: aCode >= 3 lineas", ">=3", ;
                   iif( ValType( oErr:cargo["aCode"] ) == "A", hb_NToS( Len( oErr:cargo["aCode"] ) ), "not A" ) )
   ENDIF
RETURN
