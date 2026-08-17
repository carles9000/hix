/*-----------------------------------------------------------
  File ......: hix_test_server.prg
  Author.....: Charly 9000
  Created....: 2026-06-06
  Description: Integrated test — THixServer API (no bind/listen)
 -----------------------------------------------------------*/
#include "fileio.ch"
#include "hix_const.ch"

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[Server] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

FUNCTION HIX_TestServer_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   // El router solo se inicializa al arrancar un THixServer. En modo --cli
   // ningun servidor ha arrancado todavia cuando corre este test, asi que
   // s_hRoutes seguiria a NIL y HIX_RouteList() abortaria con "Argument error".
   // HIX_RoutesLoad() es idempotente: deja el test independiente del orden.
   HIX_RoutesLoad()
   _TLog( "=== HIX_TestServer_Run start ===" )
   _SrvNew(    hCtx )
   _SrvState(  hCtx )
   _SrvRoutes( hCtx )
   _SrvOps(    hCtx )
   _TLog( "=== HIX_TestServer_Run end ===" )
RETURN hCtx

STATIC PROCEDURE _SrvNew( hCtx )
   LOCAL oSrv
   _TLog( "_SrvNew" )
   oSrv := THixServer():New()
   _TLog( "lRunning=" + hb_ValToStr( oSrv:lRunning ) )
   HixTU_Check( hCtx, oSrv:lRunning  == .F., "Server: New -> lRunning=.F.",  ".F.", iif( oSrv:lRunning,  ".T.", ".F." ) )
   HixTU_Check( hCtx, oSrv:lStarted  == .F., "Server: New -> lStarted=.F.",  ".F.", iif( oSrv:lStarted,  ".T.", ".F." ) )
   HixTU_Check( hCtx, ValType( oSrv:aRouteQueue ) == "A", "Server: New -> aRouteQueue es array", "A", ValType( oSrv:aRouteQueue ) )
RETURN

STATIC PROCEDURE _SrvState( hCtx )
   _TLog( "_SrvState" )
   _TLog( "IsRunning=" + hb_ValToStr( HIX_ServerIsRunning() ) )
   HixTU_Check( hCtx, HIX_ServerIsRunning(), "Server: HIX_ServerIsRunning() .T.", ".T.", ".F." )
   HixTU_Check( hCtx, ! HIX_IsProxied(),     "Server: HIX_IsProxied() .F.",       ".F.", ".T." )
RETURN

STATIC PROCEDURE _SrvRoutes( hCtx )
   LOCAL oSrv, aList, nBefore
   _TLog( "_SrvRoutes" )
   oSrv    := THixServer():New()
   aList   := HIX_RouteList()
   nBefore := Len( aList )
   _TLog( "nBefore=" + hb_NToS( nBefore ) )

   oSrv:AddRouteGet(    "test.srv.g1", "/test-srv-g1", {|| NIL } )
   oSrv:AddRoutePost(   "test.srv.p1", "/test-srv-p1", {|| NIL } )
   oSrv:AddRoutePut(    "test.srv.u1", "/test-srv-u1", {|| NIL } )
   oSrv:AddRouteDelete( "test.srv.d1", "/test-srv-d1", {|| NIL } )

   aList := HIX_RouteList()
   _TLog( "nAfter=" + hb_NToS( Len( aList ) ) )

   HixTU_Check( hCtx, Len( aList ) >= nBefore + 4, "Server: AddRoute GET/POST/PUT/DELETE agrega 4 rutas", ">=+4", hb_NToS( Len( aList ) - nBefore ) )
   HixTU_Check( hCtx, ValType( aList ) == "A",      "Server: RouteList() es array", "A", ValType( aList ) )

   // Limpiar rutas de test
   oSrv:DeleteRoute( "test.srv.g1" )
   oSrv:DeleteRoute( "test.srv.p1" )
   oSrv:DeleteRoute( "test.srv.u1" )
   oSrv:DeleteRoute( "test.srv.d1" )
   _TLog( "rutas test eliminadas" )
RETURN

STATIC PROCEDURE _SrvOps( hCtx )
   LOCAL oSrv, oError
   _TLog( "_SrvOps" )
   oSrv := THixServer():New()

   // SetFirewall no crash
   TRY
      oSrv:SetFirewall( "192.168.0.0/24", "blacklist" )
      HixTU_Check( hCtx, .T., "Server: SetFirewall no crash", "ok", "ok" )
   CATCH oError
      _TLog( "SetFirewall error: " + oError:description )
      HixTU_Check( hCtx, .F., "Server: SetFirewall no crash", "ok", oError:description )
   END

   // DenyDir / AllowDir no crash
   TRY
      oSrv:DenyDir(  "private/" )
      oSrv:AllowDir( "public/"  )
      HixTU_Check( hCtx, .T., "Server: DenyDir/AllowDir no crash", "ok", "ok" )
   CATCH oError
      _TLog( "DenyDir error: " + oError:description )
      HixTU_Check( hCtx, .F., "Server: DenyDir/AllowDir no crash", "ok", oError:description )
   END
RETURN
