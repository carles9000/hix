/*-----------------------------------------------------------
  File ......: hix_test_view_errors.prg
  Author.....: Charly 9000
  Created....: 2026-06-06
  Description: Integrated test — HIX_View_Viewer error scenarios
               (missing file, SetPrg sin argumentos).
 -----------------------------------------------------------*/
#include "fileio.ch"
#include "hix_const.ch"

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[ViewErrors] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

STATIC FUNCTION _MakeViewer2()
   LOCAL oView := HIX_View_Viewer():New()
   oView:lDebug           := .F.
   oView:lCache           := .F.
   oView:llSaveTranspiled := .F.
   oView:lStrictMode      := .F.
   oView:SetPathView( hb_DirBase() + "www" )
RETURN oView

FUNCTION HIX_TestViewErrors_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TLog( "=== HIX_TestViewErrors_Run start ===" )
   _VEMissingFile( hCtx )
   _VESetPrgEmpty( hCtx )
   _VEFactory( hCtx )
   _VEDevMode( hCtx )
   _VEProdMode( hCtx )
   _TLog( "=== HIX_TestViewErrors_Run end ===" )
RETURN hCtx

STATIC PROCEDURE _VEMissingFile( hCtx )
   LOCAL oView, oError, lCaught
   _TLog( "_VEMissingFile" )
   lCaught := .F.
   TRY
      oView := _MakeViewer2()
      oView:SetPrg( "/views/test/nonexistent_xxxxxx.html" )
      // SetPrg con fichero inexistente y sin cache llama HIX_DoErrorView que hace Break()
      // Si llega aqui sin error, forzamos fallo del test
      _TLog( "SetPrg file missing: no error raised (cFile=" + oView:cFile + ")" )
   CATCH oError
      lCaught := .T.
      _TLog( "SetPrg missing -> caught: " + oError:description )
   END
   HixTU_Check( hCtx, lCaught, "ViewErrors: SetPrg fichero inexistente lanza error", ".T.", iif( lCaught, ".T.", ".F." ) )
RETURN

STATIC PROCEDURE _VESetPrgEmpty( hCtx )
   LOCAL oView, oError, lCaught
   _TLog( "_VESetPrgEmpty" )
   lCaught := .F.
   TRY
      oView := _MakeViewer2()
      oView:SetPrg( "" )
      _TLog( "SetPrg empty: no error raised" )
   CATCH oError
      lCaught := .T.
      _TLog( "SetPrg empty -> caught: " + oError:description )
   END
   HixTU_Check( hCtx, lCaught, "ViewErrors: SetPrg('') lanza error 9011", ".T.", iif( lCaught, ".T.", ".F." ) )
RETURN


// ============================================================
// Suite A: HIX_ErrorView factory
// ============================================================
STATIC PROCEDURE _VEFactory( hCtx )
   LOCAL oErr, hC
   _TLog( "_VEFactory" )

   // 9010: file not found -> HTTP 404
   oErr := HIX_ErrorView( NIL, 9010, "File not found: test.prg", 5, "bad line", "hix_view_viewer" )
   hC   := oErr:cargo
   HixTU_Check( hCtx, oErr:subCode         == 404,              "9010 subCode=404",          "404",             hb_NToS( oErr:subCode ) )
   HixTU_Check( hCtx, hC["view_code"]       == 9010,            "9010 cargo view_code=9010", "9010",            hb_NToS( hC["view_code"] ) )
   HixTU_Check( hCtx, hC["process"]        == "Load",           "9010 cargo process=Load",   "Load",            hC["process"] )
   HixTU_Check( hCtx, hC["system"]         == "View",           "9010 cargo system=View",    "View",            hC["system"] )
   HixTU_Check( hCtx, hC["module"]         == "hix_view_viewer","9010 cargo module",         "hix_view_viewer", hC["module"] )
   HixTU_Check( hCtx, oErr:subSystem       == "Load",           "9010 subSystem=Load",       "Load",            hb_CStr( oErr:subSystem ) )
   HixTU_Check( hCtx, hC["line"]           == 5,                "9010 cargo line=5",         "5",               hb_NToS( hC["line"] ) )
   HixTU_Check( hCtx, hC["line_code"]      == "bad line",       "9010 cargo line_code",      "bad line",        hC["line_code"] )
   HixTU_Check( hCtx, oErr:description == "File not found: test.prg", "9010 description", "File not found: test.prg", oErr:description )

   // 9011: no source -> HTTP 500
   oErr := HIX_ErrorView( NIL, 9011, "SetPrg: No file or code", NIL, NIL, "hix_view_viewer" )
   HixTU_Check( hCtx, oErr:subCode              == 500,  "9011 subCode=500",      "500",  hb_NToS( oErr:subCode ) )
   HixTU_Check( hCtx, oErr:cargo["view_code"]   == 9011, "9011 view_code",        "9011", hb_NToS( oErr:cargo["view_code"] ) )
   HixTU_Check( hCtx, oErr:cargo["process"]     == "Load","9011 process=Load",    "Load", oErr:cargo["process"] )
   HixTU_Check( hCtx, oErr:subSystem            == "Load","9011 subSystem=Load",  "Load", hb_CStr( oErr:subSystem ) )

   // 9001: parser -> HTTP 500
   oErr := HIX_ErrorView( NIL, 9001, "Unclosed directive", 3, "{{ bad", "hix_view_parser" )
   HixTU_Check( hCtx, oErr:subCode              == 500,            "9001 subCode=500",       "500",             hb_NToS( oErr:subCode ) )
   HixTU_Check( hCtx, oErr:cargo["view_code"]   == 9001,           "9001 view_code",         "9001",            hb_NToS( oErr:cargo["view_code"] ) )
   HixTU_Check( hCtx, oErr:subSystem            == "Parser",       "9001 subSystem=Parser",  "Parser",          hb_CStr( oErr:subSystem ) )
   HixTU_Check( hCtx, oErr:cargo["module"]      == "hix_view_parser","9001 module",          "hix_view_parser", oErr:cargo["module"] )

   // 9002: transpile -> HTTP 500
   oErr := HIX_ErrorView( NIL, 9002, "Syntax error in @args", 0, "@args bad", "hix_view_transpile" )
   HixTU_Check( hCtx, oErr:subCode              == 500,                 "9002 subCode=500",         "500",               hb_NToS( oErr:subCode ) )
   HixTU_Check( hCtx, oErr:subSystem            == "Transpile",         "9002 subSystem=Transpile", "Transpile",         hb_CStr( oErr:subSystem ) )
   HixTU_Check( hCtx, oErr:cargo["module"]      == "hix_view_transpile","9002 module",              "hix_view_transpile",oErr:cargo["module"] )

   // 9004: execute -> HTTP 500
   oErr := HIX_ErrorView( NIL, 9004, "Runtime error in HRB", NIL, NIL, "hix_view_viewer" )
   HixTU_Check( hCtx, oErr:subCode   == 500,      "9004 subCode=500",       "500",     hb_NToS( oErr:subCode ) )
   HixTU_Check( hCtx, oErr:subSystem == "Execute", "9004 subSystem=Execute", "Execute", hb_CStr( oErr:subSystem ) )

   // 9005: Prg block -> HTTP 500
   oErr := HIX_ErrorView( NIL, 9005, "Error in PRG block", NIL, NIL, "hix_view_transpile" )
   HixTU_Check( hCtx, oErr:subCode   == 500,        "9005 subCode=500",         "500",       hb_NToS( oErr:subCode ) )
   HixTU_Check( hCtx, oErr:subSystem == "Prg block", "9005 subSystem=Prg block", "Prg block", hb_CStr( oErr:subSystem ) )

   // 9006: Prg transpiled -> HTTP 500
   oErr := HIX_ErrorView( NIL, 9006, "Error in transpiled PRG", NIL, NIL, "hix_view_transpile" )
   HixTU_Check( hCtx, oErr:subCode   == 500,             "9006 subCode=500",             "500",            hb_NToS( oErr:subCode ) )
   HixTU_Check( hCtx, oErr:subSystem == "Prg transpiled", "9006 subSystem=Prg transpiled","Prg transpiled", hb_CStr( oErr:subSystem ) )

   // 9009: recursion -> HTTP 500
   oErr := HIX_ErrorView( NIL, 9009, "use @view inside template", NIL, NIL, "hix_view" )
   HixTU_Check( hCtx, oErr:subCode              == 500,           "9009 subCode=500",         "500",          hb_NToS( oErr:subCode ) )
   HixTU_Check( hCtx, oErr:subSystem            == "View recursion","9009 subSystem=recursion","View recursion",hb_CStr( oErr:subSystem ) )
   HixTU_Check( hCtx, oErr:cargo["module"]      == "hix_view",    "9009 module=hix_view",     "hix_view",     oErr:cargo["module"] )

   // 9999: unknown -> HTTP 500, subSystem=View, module=""
   oErr := HIX_ErrorView( NIL, 9999, "Unknown view error" )
   HixTU_Check( hCtx, oErr:subCode         == 500,  "9999 subCode=500",    "500",  hb_NToS( oErr:subCode ) )
   HixTU_Check( hCtx, oErr:subSystem       == "View","9999 subSystem=View", "View", hb_CStr( oErr:subSystem ) )
   HixTU_Check( hCtx, oErr:cargo["module"] == "",    "9999 module empty",   "",     oErr:cargo["module"] )

   // sin cModule: module queda vacio
   oErr := HIX_ErrorView( NIL, 9001, "Sin modulo" )
   HixTU_Check( hCtx, oErr:cargo["module"] == "", "module defaults to empty", "", oErr:cargo["module"] )

   // aCode siempre array
   oErr := HIX_ErrorView( NIL, 9001, "test" )
   HixTU_Check( hCtx, ValType( oErr:cargo["aCode"] ) == "A", "aCode is array", "A", ValType( oErr:cargo["aCode"] ) )

RETURN


// ============================================================
// Suite B: HIX_ErrorSys — modo dev
// ============================================================
STATIC PROCEDURE _VEDevMode( hCtx )
   LOCAL oCfgSave, hCfg, oErr, cHtml
   _TLog( "_VEDevMode" )

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )
   hCfg     := HIX_GetConfig()
   hCfg[ "app" ][ "env" ] := "dev"

   // 9010: todos los campos obligatorios
   oErr  := HIX_ErrorView( NIL, 9010, "File not found: missing.prg", 0, "", "hix_view_viewer" )
   cHtml := HIX_ErrorSys( oErr )
   HixTU_Check( hCtx, At( "View Code",       cHtml ) > 0, "9010 HTML: 'View Code' label",          "found", "not found" )
   HixTU_Check( hCtx, At( "9010",            cHtml ) > 0, "9010 HTML: value '9010'",                "found", "not found" )
   HixTU_Check( hCtx, At( "HTTP Code",       cHtml ) > 0, "9010 HTML: 'HTTP Code' label",           "found", "not found" )
   HixTU_Check( hCtx, At( "404",             cHtml ) > 0, "9010 HTML: value '404'",                 "found", "not found" )
   HixTU_Check( hCtx, At( "Module",          cHtml ) > 0, "9010 HTML: 'Module' label",              "found", "not found" )
   HixTU_Check( hCtx, At( "hix_view_viewer", cHtml ) > 0, "9010 HTML: module name",                 "found", "not found" )
   HixTU_Check( hCtx, At( "Load",            cHtml ) > 0, "9010 HTML: process 'Load'",              "found", "not found" )
   HixTU_Check( hCtx, At( "missing.prg",     cHtml ) > 0, "9010 HTML: description contains filename","found", "not found" )

   // 9001 con nLine y cLine_Code
   oErr  := HIX_ErrorView( NIL, 9001, "Unclosed tag directive", 12, "{{ unclosed", "hix_view_parser" )
   cHtml := HIX_ErrorSys( oErr )
   HixTU_Check( hCtx, At( "Parser",          cHtml ) > 0, "9001 HTML: process 'Parser'",  "found", "not found" )
   HixTU_Check( hCtx, At( "9001",            cHtml ) > 0, "9001 HTML: value '9001'",       "found", "not found" )
   HixTU_Check( hCtx, At( "hix_view_parser", cHtml ) > 0, "9001 HTML: module name",        "found", "not found" )
   HixTU_Check( hCtx, At( "Line",            cHtml ) > 0, "9001 HTML: 'Line' label",       "found", "not found" )
   HixTU_Check( hCtx, At( "12",              cHtml ) > 0, "9001 HTML: line number 12",     "found", "not found" )
   HixTU_Check( hCtx, At( "Code",            cHtml ) > 0, "9001 HTML: 'Code' label",       "found", "not found" )
   HixTU_Check( hCtx, At( "{{ unclosed",     cHtml ) > 0, "9001 HTML: cLineCode value",    "found", "not found" )
   HixTU_Check( hCtx, At( "500",             cHtml ) > 0, "9001 HTML: HTTP code 500",      "found", "not found" )

   // 9001 con aCode: linea resaltada
   oErr := HIX_ErrorView( NIL, 9001, "Render error", 4, "{{ bad }}", "hix_view_transpile" )
   oErr:cargo[ "aCode" ] := { "<p>Line 1</p>", "<p>Line 2</p>", "<p>Line 3</p>", ;
                               "{{ bad }}", "<p>Line 5</p>", "<p>Line 6</p>", "<p>Line 7</p>" }
   cHtml := HIX_ErrorSys( oErr )
   HixTU_Check( hCtx, At( "line_error", cHtml ) > 0, "aCode HTML: line_error span present",  "found", "not found" )
   HixTU_Check( hCtx, At( "0004",       cHtml ) > 0, "aCode HTML: highlighted line number",   "found", "not found" )

   HIX_SetConfig( oCfgSave )

   // error generico sin cargo hash
   oErr             := ErrorNew()
   oErr:description := "Unhandled runtime exception"
   oErr:subSystem   := "VMRT"
   oErr:subCode     := 0
   cHtml            := HIX_ErrorSys( oErr )
   HixTU_Check( hCtx, At( "Unhandled runtime exception", cHtml ) > 0, "generic error: description in HTML", "found", "not found" )
   HixTU_Check( hCtx, ! Empty( cHtml ),                               "generic error: HTML non-empty",      "non-empty", "empty" )

   // NIL error: safe fallback
   cHtml := HIX_ErrorSys( NIL )
   HixTU_Check( hCtx, ! Empty( cHtml ), "NIL error: returns non-empty HTML", "non-empty", "empty" )

RETURN


// ============================================================
// Suite C: HIX_ErrorSys — modo prod
// ============================================================
STATIC PROCEDURE _VEProdMode( hCtx )
   LOCAL oCfgSave, hCfg, oErr, cHtml
   _TLog( "_VEProdMode" )

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )
   hCfg     := HIX_GetConfig()
   hCfg[ "app" ][ "env" ] := "prod"

   // 9010 -> pagina 404, sin tabla dev
   oErr  := HIX_ErrorView( NIL, 9010, "File not found" )
   cHtml := HIX_ErrorSys( oErr )
   HixTU_Check( hCtx, At( "404",       cHtml ) > 0, "9010 prod: HTML contiene '404'", "found", "not found" )
   HixTU_Check( hCtx, At( "View Code", cHtml ) == 0, "9010 prod: sin tabla dev",      "not found", iif( At( "View Code", cHtml ) > 0, "found", "not found" ) )

   // 9001 -> pagina 500, sin tabla dev
   oErr  := HIX_ErrorView( NIL, 9001, "Parse error" )
   cHtml := HIX_ErrorSys( oErr )
   HixTU_Check( hCtx, At( "500",       cHtml ) > 0, "9001 prod: HTML contiene '500'", "found", "not found" )
   HixTU_Check( hCtx, At( "View Code", cHtml ) == 0, "9001 prod: sin tabla dev",      "not found", iif( At( "View Code", cHtml ) > 0, "found", "not found" ) )

   // 9011 -> pagina 500
   oErr  := HIX_ErrorView( NIL, 9011, "No source" )
   cHtml := HIX_ErrorSys( oErr )
   HixTU_Check( hCtx, At( "500", cHtml ) > 0, "9011 prod: HTML contiene '500'", "found", "not found" )

   // error con subCode HTTP real (503)
   oErr         := ErrorNew()
   oErr:subCode := 503
   oErr:cargo   := NIL
   cHtml        := HIX_ErrorSys( oErr )
   HixTU_Check( hCtx, At( "503", cHtml ) > 0, "503 HTTP prod: HTML contiene '503'", "found", "not found" )

   // NIL en prod -> pagina 500
   cHtml := HIX_ErrorSys( NIL )
   HixTU_Check( hCtx, At( "500", cHtml ) > 0, "NIL prod: HTML contiene '500'", "found", "not found" )

   HIX_SetConfig( oCfgSave )

RETURN
