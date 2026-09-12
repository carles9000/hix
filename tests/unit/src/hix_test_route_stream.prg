/*-----------------------------------------------------------
  File ......: hix_test_route_stream.prg
  Author.....: Charly 9000
  Created....: 2026-09-08
  Modified...: 2026-09-08
  Version....: 1.0.0
  Description: Regression + feature test for the per-route
               "stream": true flag introduced together with the
               server.stream_exec_timeout_ms config key. Verifies
               (a) the flag is stored in the route hash and
               surfaced by HIX_RouteList, (b) the dispatcher
               ExecutePrg honours an explicit nTimeoutMs override
               that ignores ::nExecTimeout, and (c) an explicit
               nTimeoutMs > 0 still aborts long-running handlers.
  Usage      : Runs as part of run_all_tests. Registered in
               tests/unit/app.hbp and dispatched from app.prg.
  Notes      : Uses shared TMockRequest from hix_test_utils.prg
               so dispatcher plumbing matches hix_test_abort.
 -----------------------------------------------------------*/
#include "hbclass.ch"
#include "hix_const.ch"


FUNCTION HIX_TestRouteStream_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   _RouteStreamFlagDefault( hCtx )
   _RouteStreamFlagExplicit( hCtx )
   _RouteStreamFlagRegression( hCtx )
   _DispatcherHonoursNTimeout( hCtx )
   _DispatcherZeroTimeoutBypasses( hCtx )
   HIX_MetricsClose()
RETURN hCtx


// -----------------------------------------------------------
// 1. Sin flag: la ruta se registra con stream=.F. por defecto
// -----------------------------------------------------------
STATIC PROCEDURE _RouteStreamFlagDefault( hCtx )
   LOCAL aList, hHit
   HIX_RouteAdd( "rs.plain", "/rs/plain", {|| NIL }, "GET" )
   aList := HIX_RouteList()
   hHit  := _FindRoute( aList, "rs.plain" )
   HixTU_Check( hCtx, hHit != NIL,                 "Stream: ruta plain registrada",     "found",  hb_CStr( hHit != NIL ) )
   HixTU_Check( hCtx, hHit != NIL .AND. ! hHit["stream"], "Stream: default stream=.F.",  ".F.",    hb_CStr( iif( hHit != NIL, hHit["stream"], "?" ) ) )
   HIX_RouteDelete( "rs.plain" )
RETURN

// -----------------------------------------------------------
// 2. Flag explicito: HIX_RouteAdd acepta lStream=.T. y se propaga
// -----------------------------------------------------------
STATIC PROCEDURE _RouteStreamFlagExplicit( hCtx )
   LOCAL aList, hHit
   HIX_RouteAdd( "rs.stream", "/rs/stream", {|| NIL }, "GET", "", "", NIL, .F., .T. )
   aList := HIX_RouteList()
   hHit  := _FindRoute( aList, "rs.stream" )
   HixTU_Check( hCtx, hHit != NIL,                "Stream: ruta stream registrada",   "found", hb_CStr( hHit != NIL ) )
   HixTU_Check( hCtx, hHit != NIL .AND. hHit["stream"], "Stream: flag propagado a .T.", ".T.",  hb_CStr( iif( hHit != NIL, hHit["stream"], "?" ) ) )
   HIX_RouteDelete( "rs.stream" )
RETURN

// -----------------------------------------------------------
// 3. Regresion: llamada legacy sin lStream no cambia comportamiento
// (misma llamada que rutas ya existentes en tests/router; nunca debe
//  aparecer stream=.T.)
// -----------------------------------------------------------
STATIC PROCEDURE _RouteStreamFlagRegression( hCtx )
   LOCAL aList, hHit
   HIX_RouteAdd( "rs.legacy", "/rs/legacy", {|oReq| oReq:Respond( "ok", 200, "text" ) }, "GET" )
   aList := HIX_RouteList()
   hHit  := _FindRoute( aList, "rs.legacy" )
   HixTU_Check( hCtx, hHit != NIL .AND. ! hHit["stream"], "Stream: legacy 4-arg RouteAdd -> stream=.F.", ".F.", hb_CStr( iif( hHit != NIL, hHit["stream"], "?" ) ) )
   HIX_RouteDelete( "rs.legacy" )
RETURN

// -----------------------------------------------------------
// 4. Dispatcher: nTimeoutMs explicito prevalece sobre ::nExecTimeout
//    Handler duerme 2 s; ::nExecTimeout=5000 (permite acabar) pero
//    nTimeoutMs=300 debe abortar con 504. Prueba fina del override.
// -----------------------------------------------------------
STATIC PROCEDURE _DispatcherHonoursNTimeout( hCtx )
   LOCAL oDisp, oCfgSave, hCfg, oReq, oErr
   LOCAL cTmpDir, cPrgPath
   LOCAL lGot504

   cTmpDir  := hb_DirTemp() + "hix_tm_rs_a" + hb_ps()
   cPrgPath := cTmpDir + "sleep_loop.prg"
   IF ! hb_DirExists( cTmpDir ) ; hb_DirCreate( cTmpDir ) ; ENDIF

   hb_MemoWrit( cPrgPath, ;
      "FUNCTION Main()" + hb_eol() + ;
      "   LOCAL n" + hb_eol() + ;
      "   FOR n := 1 TO 200" + hb_eol() + ;
      "      hb_idleSleep( 0.010 )" + hb_eol() + ;
      "      IF HixShouldAbort() ; RETURN '' ; ENDIF" + hb_eol() + ;
      "   NEXT" + hb_eol() + ;
      "RETURN ''" + hb_eol() )

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )
   hCfg     := HIX_GetConfig()
   hCfg[ "app"   ][ "env"  ] := "dev"
   hCfg[ "paths" ][ "root" ] := hb_StrShrink( cTmpDir, 1 )

   oDisp := THixDispatcher():New( hb_StrShrink( cTmpDir, 1 ) )
   oDisp:nExecTimeout := 5000

   oReq := TMockRequest():New( "/sleep_loop.prg", "GET" )

   lGot504 := .F.
   oErr    := NIL
   TRY
      oDisp:ExecutePrg( hb_StrShrink( cTmpDir, 1 ) + hb_ps() + "sleep_loop.prg", oReq, NIL, 300 )
   CATCH oErr
      lGot504 := ( ValType( oErr ) == "O" .AND. oErr:subCode == 504 )
   END

   HixTU_Check( hCtx, lGot504, "Stream: nTimeoutMs=300 override abort 504", ".T.", ;
           iif( lGot504, ".T.", hb_CStr( iif( ValType(oErr)=="O", oErr:subCode, "no-error" ) ) ) )

   HIX_SetConfig( oCfgSave )
   IF hb_FileExists( cPrgPath ) ; hb_FileDelete( cPrgPath ) ; ENDIF
   IF hb_DirExists( hb_StrShrink( cTmpDir, 1 ) ) ; hb_DirDelete( hb_StrShrink( cTmpDir, 1 ) ) ; ENDIF
RETURN

// -----------------------------------------------------------
// 5. Dispatcher: nTimeoutMs=0 salta el timeout aunque ::nExecTimeout
//    sea corto. Simula stream_exec_timeout_ms=0 en ruta stream:true.
// -----------------------------------------------------------
STATIC PROCEDURE _DispatcherZeroTimeoutBypasses( hCtx )
   LOCAL oDisp, oCfgSave, hCfg, oReq, oErr
   LOCAL cTmpDir, cPrgPath
   LOCAL lOk

   cTmpDir  := hb_DirTemp() + "hix_tm_rs_b" + hb_ps()
   cPrgPath := cTmpDir + "quick.prg"
   IF ! hb_DirExists( cTmpDir ) ; hb_DirCreate( cTmpDir ) ; ENDIF

   // Handler que tarda 200 ms -- excederia nExecTimeout=100 si no se
   // sobreescribiese con nTimeoutMs=0.
   hb_MemoWrit( cPrgPath, ;
      "FUNCTION Main()" + hb_eol() + ;
      "   hb_idleSleep( 0.200 )" + hb_eol() + ;
      "RETURN 'done'" + hb_eol() )

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )
   hCfg     := HIX_GetConfig()
   hCfg[ "app"   ][ "env"  ] := "dev"
   hCfg[ "paths" ][ "root" ] := hb_StrShrink( cTmpDir, 1 )

   oDisp := THixDispatcher():New( hb_StrShrink( cTmpDir, 1 ) )
   oDisp:nExecTimeout := 100

   oReq := TMockRequest():New( "/quick.prg", "GET" )

   lOk  := .F.
   oErr := NIL
   TRY
      oDisp:ExecutePrg( hb_StrShrink( cTmpDir, 1 ) + hb_ps() + "quick.prg", oReq, NIL, 0 )
      lOk := .T.
   CATCH oErr
   END

   HixTU_Check( hCtx, lOk, "Stream: nTimeoutMs=0 anula ::nExecTimeout", ".T.", ;
           iif( lOk, ".T.", iif( ValType(oErr)=="O", hb_NToS(oErr:subCode), "error" ) ) )

   HIX_SetConfig( oCfgSave )
   IF hb_FileExists( cPrgPath ) ; hb_FileDelete( cPrgPath ) ; ENDIF
   IF hb_DirExists( hb_StrShrink( cTmpDir, 1 ) ) ; hb_DirDelete( hb_StrShrink( cTmpDir, 1 ) ) ; ENDIF
RETURN

// -----------------------------------------------------------
// Helper: busca una ruta por nombre en HIX_RouteList()
// -----------------------------------------------------------
STATIC FUNCTION _FindRoute( aList, cName )
   LOCAL hItem
   FOR EACH hItem IN aList
      IF hItem[ "name" ] == cName ; RETURN hItem ; ENDIF
   NEXT
RETURN NIL
