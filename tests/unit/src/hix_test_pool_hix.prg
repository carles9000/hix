/*-----------------------------------------------------------
  File ......: hix_test_pool_hix.prg
  Author.....: Charly 9000
  Created....: 2026-07-02
  Description: Unit tests for pool_hix routing: HIX_IsHixPath()
               detector, pool_hix config section and THixPool
               instantiation with HIX_POOL_HIX type.
 -----------------------------------------------------------*/
#include "hix_const.ch"

STATIC FUNCTION _CRLF()
RETURN Chr(13) + Chr(10)

STATIC FUNCTION _ReqLine( cMethod, cPath )
RETURN cMethod + " " + cPath + " HTTP/1.1" + _CRLF()

FUNCTION HIX_TestPoolHix_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _TestConstant(    hCtx )
   _TestIsHixPath(   hCtx )
   _TestConfig(      hCtx )
   _TestPoolNew(     hCtx )
   _TestIntegration( hCtx )
RETURN hCtx

// --------------------------------------------------------------
// Constante del tipo de pool
// --------------------------------------------------------------
STATIC PROCEDURE _TestConstant( hCtx )
   HixTU_Check( hCtx, HIX_POOL_HIX == "HIX",                        ;
      "PoolHix: HIX_POOL_HIX == 'HIX'",   "HIX", HIX_POOL_HIX )
RETURN

// --------------------------------------------------------------
// HIX_IsHixPath() — detector de prefijo en el peek TCP
// --------------------------------------------------------------
STATIC PROCEDURE _TestIsHixPath( hCtx )
   LOCAL cPeek

   // Rutas hix: deben devolver .T.
   cPeek := _ReqLine( "GET",  "/hix-status" )
   HixTU_Check( hCtx, HIX_IsHixPath( cPeek ),                       ;
      "IsHixPath: GET /hix-status",   ".T.", iif( HIX_IsHixPath(cPeek), ".T.", ".F." ) )

   cPeek := _ReqLine( "POST", "/hix-login" )
   HixTU_Check( hCtx, HIX_IsHixPath( cPeek ),                       ;
      "IsHixPath: POST /hix-login",   ".T.", iif( HIX_IsHixPath(cPeek), ".T.", ".F." ) )

   cPeek := _ReqLine( "GET",  "/hix-routes/list" )
   HixTU_Check( hCtx, HIX_IsHixPath( cPeek ),                       ;
      "IsHixPath: nested /hix-routes/list", ".T.", iif( HIX_IsHixPath(cPeek), ".T.", ".F." ) )

   // Rutas no-hix: deben devolver .F.
   cPeek := _ReqLine( "GET", "/" )
   HixTU_Check( hCtx, ! HIX_IsHixPath( cPeek ),                     ;
      "IsHixPath: GET / -> .F.",     ".F.", iif( HIX_IsHixPath(cPeek), ".T.", ".F." ) )

   cPeek := _ReqLine( "GET", "/api/users" )
   HixTU_Check( hCtx, ! HIX_IsHixPath( cPeek ),                     ;
      "IsHixPath: /api/users -> .F.", ".F.", iif( HIX_IsHixPath(cPeek), ".T.", ".F." ) )

   cPeek := _ReqLine( "GET", "/hixzzz" )
   HixTU_Check( hCtx, ! HIX_IsHixPath( cPeek ),                     ;
      "IsHixPath: /hixzzz (sin dash) -> .F.", ".F.", iif( HIX_IsHixPath(cPeek), ".T.", ".F." ) )

   cPeek := _ReqLine( "GET", "/monitor" )
   HixTU_Check( hCtx, ! HIX_IsHixPath( cPeek ),                     ;
      "IsHixPath: /monitor (viejo) -> .F.", ".F.", iif( HIX_IsHixPath(cPeek), ".T.", ".F." ) )

   cPeek := _ReqLine( "GET", "/hix-monitor" )
   HixTU_Check( hCtx, HIX_IsHixPath( cPeek ),                       ;
      "IsHixPath: /hix-monitor -> .T.", ".T.", iif( HIX_IsHixPath(cPeek), ".T.", ".F." ) )

   // Buffers degenerados
   HixTU_Check( hCtx, ! HIX_IsHixPath( NIL ),                       ;
      "IsHixPath: NIL -> .F.",       ".F.", iif( HIX_IsHixPath(NIL), ".T.", ".F." ) )

   HixTU_Check( hCtx, ! HIX_IsHixPath( "" ),                        ;
      "IsHixPath: '' -> .F.",        ".F.", iif( HIX_IsHixPath(""), ".T.", ".F." ) )

   HixTU_Check( hCtx, ! HIX_IsHixPath( "GET" ),                     ;
      "IsHixPath: buffer corto -> .F.", ".F.", iif( HIX_IsHixPath("GET"), ".T.", ".F." ) )

   HixTU_Check( hCtx, ! HIX_IsHixPath( "malformed data no spaces" ),;
      "IsHixPath: sin request-line -> .F.", ".F.",                  ;
      iif( HIX_IsHixPath("malformed data no spaces"), ".T.", ".F." ) )
RETURN

// --------------------------------------------------------------
// Sección pool_hix en la config
// --------------------------------------------------------------
STATIC PROCEDURE _TestConfig( hCtx )
   LOCAL hCfg, hSec

   hCfg := HIX_GetConfig()

   HixTU_Check( hCtx, hb_HHasKey( hCfg, "pool_hix" ),               ;
      "Config: seccion pool_hix presente", ".T.",                   ;
      iif( hb_HHasKey( hCfg, "pool_hix" ), ".T.", ".F." ) )

   IF ! hb_HHasKey( hCfg, "pool_hix" ) ; RETURN ; ENDIF
   hSec := hCfg[ "pool_hix" ]

   HixTU_Check( hCtx, hb_HHasKey( hSec, "workers" ) .AND. hSec[ "workers" ] == 4, ;
      "Config: pool_hix.workers default = 4", "4",                  ;
      hb_NToS( hb_HGetDef( hSec, "workers", 0 ) ) )

   HixTU_Check( hCtx, hb_HHasKey( hSec, "queue_size" ) .AND. hSec[ "queue_size" ] == 64, ;
      "Config: pool_hix.queue_size default = 64", "64",             ;
      hb_NToS( hb_HGetDef( hSec, "queue_size", 0 ) ) )

   HixTU_Check( hCtx, hb_HHasKey( hSec, "read_timeout_ms" ) .AND. hSec[ "read_timeout_ms" ] == 2000, ;
      "Config: pool_hix.read_timeout_ms default = 2000", "2000",    ;
      hb_NToS( hb_HGetDef( hSec, "read_timeout_ms", 0 ) ) )
RETURN

// --------------------------------------------------------------
// THixPool con tipo HIX_POOL_HIX lee sus DATA de la sección correcta
// --------------------------------------------------------------
STATIC PROCEDURE _TestPoolNew( hCtx )
   LOCAL oPool, hCfg

   hCfg := HIX_GetConfig()
   hCfg[ "pool_hix" ][ "workers" ]    := 3
   hCfg[ "pool_hix" ][ "queue_size" ] := 17

   oPool := THixPool():New( HIX_POOL_HIX, {| j | HB_SYMBOL_UNUSED( j ) } )

   HixTU_Check( hCtx, oPool:cTipo == HIX_POOL_HIX,                  ;
      "Pool: cTipo == HIX_POOL_HIX", HIX_POOL_HIX, oPool:cTipo )

   HixTU_Check( hCtx, oPool:nWorkers == 3,                          ;
      "Pool: nWorkers leido de pool_hix.workers", "3",              ;
      hb_NToS( oPool:nWorkers ) )

   HixTU_Check( hCtx, oPool:nQueueMax == 17,                        ;
      "Pool: nQueueMax leido de pool_hix.queue_size", "17",         ;
      hb_NToS( oPool:nQueueMax ) )

   // Restaurar defaults para no ensuciar tests posteriores
   hCfg[ "pool_hix" ][ "workers" ]    := 4
   hCfg[ "pool_hix" ][ "queue_size" ] := 64
RETURN

// --------------------------------------------------------------
// Integración HTTP — THixServer real, dos rutas, verifica que
// /hix-* pasa por pool_hix y las demás por pool_http.
// --------------------------------------------------------------
STATIC PROCEDURE _TestIntegration( hCtx )
   LOCAL oSrv, cResp, nStatus
   LOCAL nPort := 18099
   LOCAL hCfg, nOldPort, lOldAutostart, lOldSSL
   LOCAL nBefHix, nAftHix, nBefHttp, nAftHttp

   // Guarda defensiva: forzar recarga limpia de config para no heredar
   // mutaciones de tests anteriores (ssl=.T., keep_alive=.F., detector ms, etc.).
   HIX_LoadConfig( , .T. )
   hCfg          := HIX_GetConfig()
   nOldPort      := hCfg[ "server" ][ "port" ]
   lOldAutostart := hCfg[ "server" ][ "autostart" ]
   lOldSSL       := hCfg[ "server" ][ "ssl" ]

   hCfg[ "server" ][ "port" ]      := nPort
   hCfg[ "server" ][ "autostart" ] := .F.
   hCfg[ "server" ][ "ssl" ]       := .F.

   oSrv := THixServer():New()
   oSrv:lShowInfo := .F.
   oSrv:AddRouteGet( "tph.ping",   "/hix-ping-test", {|| USendJson( { "ok" => .T., "pool" => "hix"  } ) } )
   oSrv:AddRouteGet( "tph.normal", "/normal-test",   {|| USendJson( { "ok" => .T., "pool" => "http" } ) } )
   oSrv:Start( .F. )
   hb_idleSleep( 0.3 )

   HixTU_Check( hCtx, oSrv:oPoolHix != NIL,                          ;
      "Integracion: oPoolHix creado", "!=NIL",                       ;
      iif( oSrv:oPoolHix == NIL, "NIL", "obj" ) )

   HixTU_Check( hCtx, oSrv:oPoolHTTP != NIL,                         ;
      "Integracion: oPoolHTTP creado", "!=NIL",                      ;
      iif( oSrv:oPoolHTTP == NIL, "NIL", "obj" ) )

   IF oSrv:oPoolHix == NIL .OR. oSrv:oPoolHTTP == NIL
      oSrv:Stop()
      hCfg[ "server" ][ "port" ]      := nOldPort
      hCfg[ "server" ][ "autostart" ] := lOldAutostart
      hCfg[ "server" ][ "ssl" ]       := lOldSSL
      RETURN
   ENDIF

   // GET /hix-ping-test — debe encolarse en pool_hix
   nBefHix  := oSrv:oPoolHix:nDispatched
   nBefHttp := oSrv:oPoolHTTP:nDispatched
   cResp    := _TcpGet( nPort, "/hix-ping-test" )
   hb_idleSleep( 0.2 )   // dar tiempo al worker a procesar
   nStatus  := HixTU_PeerStatus( cResp )
   nAftHix  := oSrv:oPoolHix:nDispatched
   nAftHttp := oSrv:oPoolHTTP:nDispatched

   HixTU_Check( hCtx, nStatus == 200,                                ;
      "Integracion: GET /hix-ping-test -> 200", "200", hb_NToS( nStatus ) )

   HixTU_Check( hCtx, nAftHix > nBefHix,                             ;
      "Integracion: pool_hix nDispatched++", ">0",                   ;
      hb_NToS( nAftHix - nBefHix ) )

   HixTU_Check( hCtx, nAftHttp == nBefHttp,                          ;
      "Integracion: pool_http intacto en /hix-ping-test", "=0",      ;
      hb_NToS( nAftHttp - nBefHttp ) )

   // GET /normal-test — debe encolarse en pool_http
   nBefHix  := oSrv:oPoolHix:nDispatched
   nBefHttp := oSrv:oPoolHTTP:nDispatched
   cResp    := _TcpGet( nPort, "/normal-test" )
   hb_idleSleep( 0.2 )
   nStatus  := HixTU_PeerStatus( cResp )
   nAftHix  := oSrv:oPoolHix:nDispatched
   nAftHttp := oSrv:oPoolHTTP:nDispatched

   HixTU_Check( hCtx, nStatus == 200,                                ;
      "Integracion: GET /normal-test -> 200", "200", hb_NToS( nStatus ) )

   HixTU_Check( hCtx, nAftHix == nBefHix,                            ;
      "Integracion: pool_hix intacto en /normal-test", "=0",         ;
      hb_NToS( nAftHix - nBefHix ) )

   HixTU_Check( hCtx, nAftHttp > nBefHttp,                           ;
      "Integracion: pool_http nDispatched++", ">0",                  ;
      hb_NToS( nAftHttp - nBefHttp ) )

   // Cleanup
   oSrv:DeleteRoute( "tph.ping" )
   oSrv:DeleteRoute( "tph.normal" )
   oSrv:Stop()

   hCfg[ "server" ][ "port" ]      := nOldPort
   hCfg[ "server" ][ "autostart" ] := lOldAutostart
   hCfg[ "server" ][ "ssl" ]       := lOldSSL
RETURN

// TCP GET a puerto arbitrario — HTTP/1.0 + Connection: close
STATIC FUNCTION _TcpGet( nPort, cPath )
   LOCAL oSock, cBuf, nRead, cResp, nTimeout, cReq

   cReq  := "GET " + cPath + " HTTP/1.0" + _CRLF()
   cReq  += "Host: 127.0.0.1" + _CRLF()
   cReq  += "Connection: close" + _CRLF()
   cReq  += _CRLF()

   oSock := hb_socketOpen()
   IF ! hb_socketConnect( oSock, { HB_SOCKET_AF_INET, "127.0.0.1", nPort }, 3000 )
      hb_socketClose( oSock )
      RETURN ""
   ENDIF

   hb_socketSend( oSock, cReq, Len( cReq ), 0, 3000 )

   cResp    := ""
   nTimeout := 3000
   DO WHILE .T.
      cBuf  := Space( 8192 )
      nRead := hb_socketRecv( oSock, @cBuf, 8192, 0, nTimeout )
      IF nRead <= 0 ; EXIT ; ENDIF
      cResp    += Left( cBuf, nRead )
      nTimeout := 500
   ENDDO

   hb_socketClose( oSock )
RETURN cResp
