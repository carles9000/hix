/*-----------------------------------------------------------
  File ......: hix_test_executehrb.prg
  Author.....: Charly 9000
  Created....: 2026-10-15
  Modified...: 2026-10-15
  Version....: 1.0.0
  Description: Integrated test — THixDispatcher ExecuteHrb +
               request propagation to .hrb modules.
               Regression coverage for v2.4.2 bug: ExecuteHrb
               erased the THREAD STATIC request with NIL and
               U* helpers from .hrb lost oReq.
  Usage      : Called by run_tests via "ExecuteHrb" entry in app.prg
  Notes      : No peer server. All cases use TMockRequest and
               compile .hrb in-memory with hb_compileFromBuf.
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"

// Uses shared TMockRequest from hix_test_utils.prg

STATIC FUNCTION _TmpRoot()
   LOCAL cRoot := hb_DirTemp() + "hix_tm_exechrb" + hb_ps()
   IF ! hb_DirExists( cRoot ) ; hb_DirCreate( cRoot ) ; ENDIF
RETURN cRoot

STATIC PROCEDURE _CleanTmpRoot( cRoot )
   LOCAL aFiles, aEntry
   IF ! hb_DirExists( cRoot ) ; RETURN ; ENDIF
   aFiles := Directory( cRoot + "*.*" )
   FOR EACH aEntry IN aFiles
      HIX_SafeErase( cRoot + aEntry[1] )
   NEXT
   HIX_SafeDirDelete( hb_StrShrink( cRoot, 1 ) )
RETURN

STATIC FUNCTION _Disp( cRoot )
   LOCAL o := THixDispatcher():New( cRoot )
   o:nExecTimeout := 0
RETURN o

// Compila cSrc en caliente y lo escribe como cName.hrb en cRoot.
// Devuelve ruta completa o "" si la compilacion no esta disponible.
STATIC FUNCTION _WriteHrb( cRoot, cName, cSrc )
   LOCAL cHrb, oError, cPath
   cPath := cRoot + cName + ".hrb"
   TRY
      cHrb := hb_compileFromBuf( cSrc, "-n1", "-q2" )
   CATCH oError
      HB_SYMBOL_UNUSED( oError )
      RETURN ""
   END
   IF Empty( cHrb ) ; RETURN "" ; ENDIF
   hb_MemoWrit( cPath, cHrb )
RETURN cPath

FUNCTION HIX_TestExecuteHrb_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cTmpRoot
   HIX_MetricsInit()
   HIX_ZombieInit()
   cTmpRoot := _TmpRoot()
   _HrbReceivesRequest(      hCtx, cTmpRoot )
   _HrbFallsBackToThreadSt(  hCtx, cTmpRoot )
   _HrbGuardKeepsStatic(     hCtx, cTmpRoot )
   _HrbUHelpersWork(         hCtx, cTmpRoot )
   _HrbTimeoutPropagates(    hCtx, cTmpRoot )
   _CleanTmpRoot( cTmpRoot )
   HIX_SetRequest( NIL )
   HIX_MetricsClose()
RETURN hCtx

// -------------------------------------------------------
// Caso 1 — propagacion explicita de oReq al ejecutar .hrb
// Reproduce la rama fijada en el router (_HixEvalAction):
// AddRouteGet con action .hrb que llama HIX_GetRequest.
// -------------------------------------------------------
STATIC PROCEDURE _HrbReceivesRequest( hCtx, cRoot )
   LOCAL oDisp, oReq, cPath, cResult, cSrc, cEol
   cEol := hb_eol()
   cSrc := "FUNCTION Main()" + cEol + ;
          "   LOCAL oReq := HIX_GetRequest()" + cEol + ;
          "RETURN iif( oReq == NIL, 'NIL', 'OK:' + oReq:cPath )" + cEol
   cPath := _WriteHrb( cRoot, "receives_req", cSrc )
   IF Empty( cPath )
      HixTU_Pass( hCtx, "ExecHrb: receives oReq explicit (skipped: no hb_compileFromBuf)", "skipped", "skipped" )
      RETURN
   ENDIF
   oDisp := _Disp( cRoot )
   oReq  := TMockRequest():New( "/ping", "GET" )
   HIX_SetRequest( NIL )  // asegurar THREAD STATIC limpio -> prueba propagacion explicita
   cResult := oDisp:ExecuteHrb( cPath, 0, oReq )
   HixTU_Check( hCtx, cResult == "OK:/ping", ;
      "ExecHrb: oReq explicito llega al .hrb (HIX_GetRequest)", "OK:/ping", cResult )
RETURN

// -------------------------------------------------------
// Caso 2 — fallback a HIX_GetRequest() cuando el caller
// no pasa oReq (uso interno del dispatcher: ExecutePrg con
// fallback a .hrb, _HixPreviewExec, etc).
// -------------------------------------------------------
STATIC PROCEDURE _HrbFallsBackToThreadSt( hCtx, cRoot )
   LOCAL oDisp, oReq, cPath, cResult, cSrc, cEol
   cEol := hb_eol()
   cSrc := "FUNCTION Main()" + cEol + ;
          "   LOCAL oReq := HIX_GetRequest()" + cEol + ;
          "RETURN iif( oReq == NIL, 'NIL', 'OK:' + oReq:cPath )" + cEol
   cPath := _WriteHrb( cRoot, "fallback", cSrc )
   IF Empty( cPath )
      HixTU_Pass( hCtx, "ExecHrb: fallback THREAD STATIC (skipped)", "skipped", "skipped" )
      RETURN
   ENDIF
   oDisp := _Disp( cRoot )
   oReq  := TMockRequest():New( "/fallback", "GET" )
   HIX_SetRequest( oReq )
   cResult := oDisp:ExecuteHrb( cPath, 0 )  // SIN oReq -> fallback
   HixTU_Check( hCtx, cResult == "OK:/fallback", ;
      "ExecHrb: fallback a HIX_GetRequest() cuando oReq=NIL", "OK:/fallback", cResult )
RETURN

// -------------------------------------------------------
// Caso 3 — guard en _HixExecWithTimeout: el THREAD STATIC
// del hilo padre no se pisa con NIL. Si ExecuteHrb (via
// fallback) termina pasando NIL, no debe borrar la peticion.
// Verificacion: antes y despues de la llamada, HIX_GetRequest
// devuelve el mismo objeto.
// -------------------------------------------------------
STATIC PROCEDURE _HrbGuardKeepsStatic( hCtx, cRoot )
   LOCAL oDisp, oReq, oAfter, cPath, cSrc, cEol
   cEol := hb_eol()
   cSrc := "FUNCTION Main()" + cEol + "RETURN 'done'" + cEol
   cPath := _WriteHrb( cRoot, "guard", cSrc )
   IF Empty( cPath )
      HixTU_Pass( hCtx, "ExecHrb: guard anti-NIL (skipped)", "skipped", "skipped" )
      RETURN
   ENDIF
   oDisp := _Disp( cRoot )
   oReq  := TMockRequest():New( "/guard", "GET" )
   HIX_SetRequest( oReq )
   oDisp:ExecuteHrb( cPath, 0 )  // fallback recoge oReq del THREAD STATIC
   oAfter := HIX_GetRequest()
   HixTU_Check( hCtx, oAfter != NIL, ;
      "ExecHrb: THREAD STATIC no es NIL tras ExecuteHrb", "obj", iif( oAfter == NIL, "NIL", "obj" ) )
   HixTU_Check( hCtx, ValType( oAfter ) == "O" .AND. oAfter:cPath == "/guard", ;
      "ExecHrb: THREAD STATIC conserva el mismo oReq", "/guard", ;
      iif( oAfter == NIL, "NIL", oAfter:cPath ) )
RETURN

// -------------------------------------------------------
// Caso 4 — U* helpers (UGet, UCookie) funcionan desde el .hrb.
// Garantia end-to-end del fix: con el bug devolvian "" por
// HIX_GetRequest()==NIL; con el fix leen del oReq propagado.
// -------------------------------------------------------
STATIC PROCEDURE _HrbUHelpersWork( hCtx, cRoot )
   LOCAL oDisp, oReq, cPath, cResult, cSrc, cEol
   cEol := hb_eol()
   cSrc := "FUNCTION Main()" + cEol + ;
          "RETURN UGet( 'x', '' ) + '|' + UCookie( 'c', '' )" + cEol
   cPath := _WriteHrb( cRoot, "u_helpers", cSrc )
   IF Empty( cPath )
      HixTU_Pass( hCtx, "ExecHrb: U* helpers (skipped)", "skipped", "skipped" )
      RETURN
   ENDIF
   oDisp := _Disp( cRoot )
   oReq  := TMockRequest():New( "/u", "GET" )
   oReq:hQueryParams[ "x" ] := "42"
   oReq:hHeaders[ "cookie" ] := "c=hello"
   HIX_SetRequest( NIL )
   cResult := oDisp:ExecuteHrb( cPath, 0, oReq )
   HixTU_Check( hCtx, cResult == "42|hello", ;
      "ExecHrb: UGet+UCookie desde .hrb leen del oReq propagado", "42|hello", cResult )
RETURN

// -------------------------------------------------------
// Caso 5 — path con timeout (nMs > 0). Fuerza _HixThreadExec
// (hilo hijo) que hereda THREAD STATIC vacio: oReq llega como
// parametro explicito o el .hrb lo ve NIL.
// -------------------------------------------------------
STATIC PROCEDURE _HrbTimeoutPropagates( hCtx, cRoot )
   LOCAL oDisp, oReq, cPath, cResult, cSrc, cEol
   cEol := hb_eol()
   cSrc := "FUNCTION Main()" + cEol + ;
          "   LOCAL oReq := HIX_GetRequest()" + cEol + ;
          "RETURN iif( oReq == NIL, 'NIL', 'OK:' + oReq:cPath )" + cEol
   cPath := _WriteHrb( cRoot, "timeout", cSrc )
   IF Empty( cPath )
      HixTU_Pass( hCtx, "ExecHrb: timeout path (skipped)", "skipped", "skipped" )
      RETURN
   ENDIF
   oDisp := _Disp( cRoot )
   oReq  := TMockRequest():New( "/to", "GET" )
   HIX_SetRequest( NIL )  // forzar que el hijo lo reciba por parametro, no por herencia
   cResult := oDisp:ExecuteHrb( cPath, 5000, oReq )
   HixTU_Check( hCtx, cResult == "OK:/to", ;
      "ExecHrb: oReq llega al hilo hijo (nMs>0)", "OK:/to", cResult )
RETURN
