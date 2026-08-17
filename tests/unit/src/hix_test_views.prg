/*-----------------------------------------------------------
  File ......: hix_test_views.prg
  Author.....: Charly 9000
  Created....: 2026-06-06
  Description: Integrated test — HIX_View_Viewer render pipeline
               (pure HTML, @args + {{ var }} interpolation).
               View files live in tests.master/www/views/test/
 -----------------------------------------------------------*/
#include "fileio.ch"
#include "hix_const.ch"

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[Views] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

// Crea un viewer apuntando a tests.master/www
STATIC FUNCTION _MakeViewer()
   LOCAL oView := HIX_View_Viewer():New()
   oView:lDebug           := .F.
   oView:lCache           := .F.
   oView:llSaveTranspiled := .F.
   oView:lStrictMode      := .F.
   oView:SetPathView( hb_DirBase() + "www" )
RETURN oView

FUNCTION HIX_TestViews_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TLog( "=== HIX_TestViews_Run start ===" )
   _TLog( "DirBase=" + hb_DirBase() )
   _ViewsNew(       hCtx )
   _ViewsPlainHtml( hCtx )
   _ViewsTemplate(  hCtx )
   _TLog( "=== HIX_TestViews_Run end ===" )
RETURN hCtx

STATIC PROCEDURE _ViewsNew( hCtx )
   LOCAL oView, oError
   _TLog( "_ViewsNew" )
   TRY
      oView := HIX_View_Viewer():New()
      HixTU_Check( hCtx, ValType( oView ) == "O",   "Views: New devuelve objeto",      "O", ValType( oView ) )
      HixTU_Check( hCtx, oView:lError     == .F.,   "Views: New -> lError=.F.",        ".F.", iif( oView:lError, ".T.", ".F." ) )
      HixTU_Check( hCtx, oView:lCache     == .T.,   "Views: New -> lCache=.T. default",".T.", iif( oView:lCache, ".T.", ".F." ) )
   CATCH oError
      _TLog( "New error: " + oError:description )
      HixTU_Check( hCtx, .F., "Views: New sin crash", "ok", oError:description )
   END
RETURN

STATIC PROCEDURE _ViewsPlainHtml( hCtx )
   LOCAL oView, cHtml, oError
   _TLog( "_ViewsPlainHtml" )
   TRY
      oView := _MakeViewer()
      oView:SetPrg( "/views/test/plain.html" )
      _TLog( "SetPrg done, cFile=" + oView:cFile )
      cHtml := oView:Render()
      _TLog( "Render result type=" + ValType( cHtml ) + " len=" + hb_NToS( Len( hb_defaultValue( cHtml, "" ) ) ) )
      HixTU_Check( hCtx, ValType( cHtml ) == "C",          "Views: Plain HTML -> tipo C",             "C",  ValType( cHtml ) )
      HixTU_Check( hCtx, ! Empty( cHtml ),                 "Views: Plain HTML -> contenido no vacio", "!empty", iif( Empty( cHtml ), "empty", "ok" ) )
      HixTU_Check( hCtx, "Hello from plain view" $ cHtml,  "Views: Plain HTML -> contiene texto",     "texto", iif( "Hello from plain view" $ cHtml, "ok", "no" ) )
   CATCH oError
      _TLog( "PlainHtml error: " + oError:description )
      HixTU_Check( hCtx, .F., "Views: Plain HTML render", "ok", oError:description )
   END
RETURN

STATIC PROCEDURE _ViewsTemplate( hCtx )
   LOCAL oView, cHtml, oError
   _TLog( "_ViewsTemplate" )
   TRY
      oView := _MakeViewer()
      oView:SetPrg( "/views/test/simple.view.html" )
      _TLog( "SetPrg done, cFile=" + oView:cFile )
      cHtml := oView:Render( "Claude", "red" )
      _TLog( "Render result type=" + ValType( cHtml ) + " content=" + hb_defaultValue( cHtml, "(nil)" ) )
      HixTU_Check( hCtx, ValType( cHtml ) == "C",  "Views: Template -> tipo C",              "C",      ValType( cHtml ) )
      HixTU_Check( hCtx, ! Empty( cHtml ),         "Views: Template -> contenido no vacio",  "!empty", iif( Empty( cHtml ), "empty", "ok" ) )
      HixTU_Check( hCtx, "Claude" $ cHtml,         "Views: Template -> cName=Claude",        "Claude", iif( "Claude" $ cHtml, "ok", cHtml ) )
      HixTU_Check( hCtx, "red"    $ cHtml,         "Views: Template -> cColor=red",          "red",    iif( "red"    $ cHtml, "ok", cHtml ) )
   CATCH oError
      _TLog( "Template error: " + oError:description )
      HixTU_Check( hCtx, .F., "Views: Template render", "ok", oError:description )
   END
RETURN
