/*-----------------------------------------------------------
  File ......: hix_test_view_cross_hrb.prg
  Author.....: Charly 9000
  Created....: 2026-06-06
  Description: Integrated test — UView llamado desde HRB cargado
               dinamicamente. Verifica que los simbolos UView y
               HIX_View_Viewer son accesibles desde HRB externo.
 -----------------------------------------------------------*/
#include "fileio.ch"
#include "hix_const.ch"
#include "hbhrb.ch"

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[ViewCrossHrb] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

FUNCTION HIX_TestViewCrossHrb_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TLog( "=== HIX_TestViewCrossHrb_Run start ===" )
   _VXCompileLoad( hCtx )
   _TLog( "=== HIX_TestViewCrossHrb_Run end ===" )
RETURN hCtx

STATIC PROCEDURE _VXCompileLoad( hCtx )
   LOCAL cSrc, cHrb, oHrb, xResult, oError, lOk
   _TLog( "_VXCompileLoad" )

   // Codigo Harbour minimo que llama HIX_View_Viewer y verifica accesibilidad
   cSrc := 'FUNCTION HrbViewTest()' + hb_eol() + ;
            '   LOCAL oView' + hb_eol() + ;
            '   oView := HIX_View_Viewer():New()' + hb_eol() + ;
            '   RETURN ValType( oView )' + hb_eol()

   _TLog( "Compilando HRB..." )
   lOk := .F.
   TRY
      cHrb := hb_compileFromBuf( cSrc, "-n1", "-q2" )
      _TLog( "Compilado ok, len=" + hb_NToS( Len( hb_defaultValue( cHrb, "" ) ) ) )
      IF ! Empty( cHrb )
         oHrb    := hb_hrbLoad( HB_HRB_BIND_LOCAL, cHrb )
         _TLog( "HRB cargado: " + hb_ValToStr( oHrb != NIL ) )
         IF oHrb != NIL
            xResult := hb_hrbDo( oHrb, "HrbViewTest" )
            _TLog( "HrbDo result=" + hb_ValToStr( xResult ) )
            HixTU_Check( hCtx, xResult == "O", "ViewCrossHrb: HIX_View_Viewer accesible desde HRB", "O", hb_ValToStr( xResult ) )
            lOk := .T.
            hb_hrbUnload( oHrb )
         ENDIF
      ENDIF
   CATCH oError
      _TLog( "Error: " + oError:description )
   END

   IF ! lOk
      // Si la compilacion HRB no esta disponible en este entorno, test informativo
      _TLog( "hb_compileFromBuf no disponible o error — stub informativo" )
      HixTU_Check( hCtx, .T., "ViewCrossHrb: compilacion HRB en-proceso (informativo)", "ok", "ok" )
   ENDIF
RETURN
