/*-----------------------------------------------------------
  File ......: hix_test_dispatcher.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — THixDispatcher
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"

// Uses shared TMockRequest from hix_test_utils.prg

STATIC FUNCTION _Dispatch( oDisp, cPath )
   LOCAL oReq := TMockRequest():New( cPath, "GET" )
   LOCAL oErr
   TRY
      oDisp:Dispatch( oReq )
   CATCH oErr
      IF ! oReq:lResponded
         oReq:nStatus    := iif( ValType( oErr:subCode ) == "N" .AND. oErr:subCode > 0, oErr:subCode, 500 )
         oReq:lResponded := .T.
         oReq:cBody      := oErr:description
      ENDIF
   END
RETURN oReq

STATIC FUNCTION _TmpRoot()
   LOCAL cRoot := hb_DirTemp() + "hix_tm_disp" + hb_ps()
   LOCAL cHrb, cClassPrg
   IF ! hb_DirExists( cRoot ) ; hb_DirCreate( cRoot ) ; ENDIF
   hb_MemoWrit( cRoot + "page.prg",   "FUNCTION page()" + hb_eol() + "RETURN '<h1>Test</h1>'" )
   cHrb := hb_CompileFromBuf( "FUNCTION main()" + hb_eol() + "RETURN '<b>hrb ok</b>'", .T., "-n", "-q2" )
   hb_MemoWrit( cRoot + "app.hrb",    cHrb )
   hb_MemoWrit( cRoot + "index.html", "<html/>"  )
   hb_MemoWrit( cRoot + "base.htm",   "<html/>"  )
   hb_MemoWrit( cRoot + "style.css",  "body{}"   )
   hb_MemoWrit( cRoot + "main.js",    "var x=1;" )
   hb_MemoWrit( cRoot + "logo.png",   ""         )
   cClassPrg := '#include "hbclass.ch"' + hb_eol() + ;
                "CLASS TestCtrl" + hb_eol() + ;
                "   DATA oReq" + hb_eol() + ;
                "   METHOD New( oReq )" + hb_eol() + ;
                "   METHOD Hello()" + hb_eol() + ;
                "   METHOD Bye()" + hb_eol() + ;
                "ENDCLASS" + hb_eol() + ;
                "METHOD New( oReq ) CLASS TestCtrl" + hb_eol() + ;
                "   ::oReq := oReq" + hb_eol() + ;
                "RETURN Self" + hb_eol() + ;
                "METHOD Hello() CLASS TestCtrl" + hb_eol() + ;
                "RETURN '<h1>class hello</h1>'" + hb_eol() + ;
                "METHOD Bye() CLASS TestCtrl" + hb_eol() + ;
                "RETURN '<h1>class bye</h1>'" + hb_eol() + ;
                "FUNCTION Main( cClass )" + hb_eol() + ;
                "RETURN TestCtrl" + hb_eol()
   hb_MemoWrit( cRoot + "ctrl.prg", cClassPrg )
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

FUNCTION HIX_TestDispatcher_Run()
   LOCAL hCtx   := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cTmpRoot
   HIX_MetricsInit()
   HIX_ZombieInit()
   cTmpRoot := _TmpRoot()
   _DispExecMethods(     hCtx, cTmpRoot )
   _DispSecurity(        hCtx )
   _DispNotFound(        hCtx )
   _DispExtensions(      hCtx, cTmpRoot )
   _DispNormalization(   hCtx, cTmpRoot )
   _DispRootNorm(        hCtx )
   _DispModeBlocked(     hCtx, cTmpRoot )
   _DispDefaultPage(     hCtx, cTmpRoot )
   _DispClassDispatch(   hCtx, cTmpRoot )
   _DispViewHtml(        hCtx )
   _CleanTmpRoot( cTmpRoot )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _DispExecMethods( hCtx, cTmpRoot )
   LOCAL oDisp, cHtml, cContent, lThrew, oE
   oDisp := THixDispatcher():New( "public" )
   oDisp:nExecTimeout := 0
   cHtml  := cTmpRoot + "index.html"
   lThrew := .F.
   TRY
      oDisp:ExecutePrg( "C:\noexiste.prg" )
   CATCH oE
      lThrew := .T.
   END
   HixTU_Check( hCtx, lThrew, "Disp: ExecutePrg error si no existe", ".T.", iif( lThrew, ".T.", ".F." ) )
   HixTU_Check( hCtx, oDisp:ExecuteFile( "C:\noexiste.css" ) == "", "Disp: ExecuteFile '' si no existe", "", oDisp:ExecuteFile( "C:\noexiste.css" ) )
   cContent := oDisp:ExecuteHtml( cHtml )
   HixTU_Check( hCtx, cContent == "<html/>", "Disp: ExecuteHtml devuelve contenido", "<html/>", cContent )
   HixTU_Check( hCtx, oDisp:ExecuteHtml( "C:\noexiste.html" ) == "", "Disp: ExecuteHtml '' si no existe", "", oDisp:ExecuteHtml( "C:\noexiste.html" ) )
RETURN

STATIC PROCEDURE _DispSecurity( hCtx )
   LOCAL oDisp, oReq
   oDisp := THixDispatcher():New( "public" )
   oDisp:nExecTimeout := 0
   oReq := _Dispatch( oDisp, "/../etc/passwd" )
   HixTU_Check( hCtx, oReq:nStatus == 403, "Disp: path traversal /../ -> 403",      "403", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( oDisp, "/../../secret.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 403, "Disp: path traversal /../../ -> 403",   "403", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( oDisp, "/normal/../secret" )
   HixTU_Check( hCtx, oReq:nStatus == 403, "Disp: path traversal /normal/../ -> 403","403", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _DispNotFound( hCtx )
   LOCAL oDisp, oReq
   oDisp := THixDispatcher():New( "public" )
   oDisp:nExecTimeout := 0
   oReq := _Dispatch( oDisp, "/no_existe.html" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "Disp: /no_existe.html -> 404", "404", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( oDisp, "/carpeta/tampoco.js" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "Disp: /carpeta/tampoco.js -> 404", "404", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _DispExtensions( hCtx, cRoot )
   LOCAL oDisp, oReq
   oDisp := THixDispatcher():New( cRoot )
   oDisp:nExecTimeout := 0
   oReq := _Dispatch( oDisp, "/page.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "<h1>Test</h1>" .AND. oReq:cMime == "html", "Disp: .prg -> 200 html", "html/<h1>Test</h1>", oReq:cMime + "/" + oReq:cBody )
   oReq := _Dispatch( oDisp, "/app.hrb" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "<b>hrb ok</b>", "Disp: .hrb -> 200 ejecuta", "<b>hrb ok</b>", oReq:cBody )
   oReq := _Dispatch( oDisp, "/index.html" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cMime == "html" .AND. oReq:cBody == "<html/>", "Disp: .html -> 200", "html/<html/>", oReq:cMime + "/" + oReq:cBody )
   oReq := _Dispatch( oDisp, "/base.htm" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cMime == "html" .AND. oReq:cBody == "<html/>", "Disp: .htm -> 200 html", "html/<html/>", oReq:cMime + "/" + oReq:cBody )
   oReq := _Dispatch( oDisp, "/style.css" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cMime == "css" .AND. oReq:cBody == "body{}", "Disp: .css -> 200 css", "css/body{}", oReq:cMime + "/" + oReq:cBody )
   oReq := _Dispatch( oDisp, "/main.js" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cMime == "js" .AND. oReq:cBody == "var x=1;", "Disp: .js -> 200 js", "js/var x=1;", oReq:cMime + "/" + oReq:cBody )
   oReq := _Dispatch( oDisp, "/logo.png" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cMime == "image/png", "Disp: .png -> 200 image/png", "image/png", oReq:cMime )
RETURN

STATIC PROCEDURE _DispNormalization( hCtx, cRoot )
   LOCAL oDisp, oReq
   oDisp := THixDispatcher():New( cRoot )
   oDisp:nExecTimeout := 0
   oReq := _Dispatch( oDisp, "//index.html" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Disp: //index.html normaliza -> 200", "200", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( oDisp, "index.html" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Disp: sin / inicial -> 200",          "200", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _DispRootNorm( hCtx )
   LOCAL cRoot, oDisp
   cRoot  := hb_DirTemp() + "hix_tm_disp" + hb_ps()
   oDisp  := THixDispatcher():New( cRoot )
   oDisp:nExecTimeout := 0
   HixTU_Check( hCtx, Right( oDisp:cRoot, 1 ) != hb_ps(), "Disp: cRoot sin trailing sep", "sin " + hb_ps(), Right( oDisp:cRoot, 1 ) )
RETURN

STATIC PROCEDURE _DispModeBlocked( hCtx, cRoot )
   LOCAL oDisp, oReq
   oDisp := THixDispatcher():New( cRoot )
   oDisp:nExecTimeout := 0
   oDisp:lExecPrg     := .F.
   oReq := _Dispatch( oDisp, "/page.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 403, "Disp: .prg con lExecPrg=.F. -> 403", "403", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( oDisp, "/app.hrb" )
   HixTU_Check( hCtx, oReq:nStatus == 403, "Disp: .hrb con lExecPrg=.F. -> 403", "403", hb_NToS( oReq:nStatus ) )
   oDisp:lExecPrg := .T.
   oReq := _Dispatch( oDisp, "/index.html" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Disp: html con lExecPrg toggle -> 200", "200", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _DispDefaultPage( hCtx, cRoot )
   LOCAL oDisp, oReq
   oDisp := THixDispatcher():New( cRoot )
   oDisp:nExecTimeout := 0
   oDisp:cDefaultPage := "index.html"
   oReq := _Dispatch( oDisp, "/" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "<html/>", "Disp: / -> index.html -> 200", "200/<html/>", hb_NToS( oReq:nStatus ) + "/" + oReq:cBody )
   oReq := _Dispatch( oDisp, "/noexiste/" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "Disp: dir inexistente/ -> 404", "404", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _DispViewHtml( hCtx )
   LOCAL oDisp, cWww, cPath, cContent

   // www absoluto del exe de tests — lHixStyle=.F. por ini (hixstyle.enabled=false)
   // Con lHixStyle=.F.: base UView = www/, strip solo www -> URL /views/test/simple.view.html
   cWww := hb_DirBase() + "www"
   IF Right( cWww, 1 ) == hb_ps()
      cWww := hb_StrShrink( cWww, 1 )
   ENDIF

   oDisp := THixDispatcher():New( cWww )
   oDisp:nExecTimeout := 0

   // .view.html -> UView con ruta relativa a www/ (incluye views/ en la URL)
   cPath    := cWww + hb_ps() + "views" + hb_ps() + "test" + hb_ps() + "simple.view.html"
   cContent := oDisp:ExecuteHtml( cPath )
   HixTU_Check( hCtx, "Hello" $ cContent, ;
      "Disp: .view.html renderiza con lHixStyle=.F.", ;
      "Hello en output", ;
      iif( "Hello" $ cContent, "found", "not found: " + Left( cContent, 80 ) ) )

   // Plain .html -> Memoread, sin UView
   cPath    := cWww + hb_ps() + "views" + hb_ps() + "test" + hb_ps() + "plain.html"
   cContent := oDisp:ExecuteHtml( cPath )
   HixTU_Check( hCtx, ! Empty( cContent ), ;
      "Disp: .html plain lee contenido raw", ;
      "no vacio", iif( ! Empty( cContent ), "ok", "empty" ) )

RETURN

STATIC PROCEDURE _DispClassDispatch( hCtx, cRoot )
   LOCAL oDisp, oReq
   oDisp := THixDispatcher():New( cRoot )
   oDisp:nExecTimeout := 0
   oReq := _Dispatch( oDisp, "/hello@ctrl.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Disp: hello@ctrl.prg -> 200", "200", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "<h1>class hello</h1>", "Disp: hello@ctrl.prg body", "<h1>class hello</h1>", oReq:cBody )
   oReq := _Dispatch( oDisp, "/bye@ctrl.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 200, "Disp: bye@ctrl.prg -> 200", "200", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody == "<h1>class bye</h1>", "Disp: bye@ctrl.prg body", "<h1>class bye</h1>", oReq:cBody )
   oReq := _Dispatch( oDisp, "/hello@noexiste.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 404, "Disp: metodo@noexiste.prg -> 404", "404", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( oDisp, "/inexistente@ctrl.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 500, "Disp: metodo_inexistente@ctrl -> 500", "500", hb_NToS( oReq:nStatus ) )
   oReq := _Dispatch( oDisp, "/page.prg" )
   HixTU_Check( hCtx, oReq:nStatus == 200 .AND. oReq:cBody == "<h1>Test</h1>", "Disp: page.prg sin @ -> 200", "200/<h1>Test</h1>", hb_NToS( oReq:nStatus ) + "/" + oReq:cBody )
RETURN
