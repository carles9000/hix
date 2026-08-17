/*-----------------------------------------------------------
  File ......: hix_test_proxied.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — modo proxied X-Forwarded-For / X-Real-IP
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hbclass.ch"

// Uses shared TMockIO from hix_test_utils.prg

STATIC FUNCTION _MakeRequest( cPath, cExtraHeaders )
   LOCAL cCRLF := Chr(13) + Chr(10)
   hb_default( @cExtraHeaders, "" )
RETURN "GET " + cPath + " HTTP/1.1" + cCRLF + ;
       "Host: localhost" + cCRLF + ;
       "Connection: close" + cCRLF + ;
       cExtraHeaders + ;
       cCRLF

STATIC FUNCTION _ParseRequest( cRaw, cIP, lProxied )
   LOCAL oIO, oReq
   hb_default( @lProxied, .F. )
   oIO  := TMockIO():New( cRaw )
   oReq := THixRequest():New( oIO, cIP, lProxied )
   oReq:Read()
RETURN oReq

FUNCTION HIX_TestProxied_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_ProxyInit( "127.0.0.1" )
   _ProxiedSin( hCtx )
   _ProxiedCon( hCtx )
RETURN hCtx

STATIC PROCEDURE _ProxiedSin( hCtx )
   LOCAL oReq
   oReq := _ParseRequest( ;
      _MakeRequest( "/ip", "X-Forwarded-For: 9.8.7.6" + Chr(13)+Chr(10) ), ;
      "127.0.0.1", .F. )
   HixTU_Check( hCtx, oReq:cIP == "127.0.0.1", "Proxied: sin proxied XFF ignorado", "127.0.0.1", oReq:cIP )
   oReq := _ParseRequest( ;
      _MakeRequest( "/ip", "X-Real-IP: 5.5.5.5" + Chr(13)+Chr(10) ), ;
      "127.0.0.1", .F. )
   HixTU_Check( hCtx, oReq:cIP == "127.0.0.1", "Proxied: sin proxied X-Real-IP ignorado", "127.0.0.1", oReq:cIP )
RETURN

STATIC PROCEDURE _ProxiedCon( hCtx )
   LOCAL oReq, cCRLF
   cCRLF := Chr(13) + Chr(10)
   oReq  := _ParseRequest( _MakeRequest( "/ip" ), "127.0.0.1", .T. )
   HixTU_Check( hCtx, oReq:cIP == "127.0.0.1",    "Proxied: con proxied sin headers cIP TCP", "127.0.0.1", oReq:cIP )
   HixTU_Check( hCtx, oReq:RealIP() == "127.0.0.1","Proxied: sin headers RealIP==TCP",         "127.0.0.1", oReq:RealIP() )
   oReq := _ParseRequest( ;
      _MakeRequest( "/ip", "X-Forwarded-For: 9.8.7.6" + cCRLF ), ;
      "127.0.0.1", .T. )
   HixTU_Check( hCtx, oReq:cIP == "127.0.0.1",    "Proxied: cIP TCP no cambia con XFF", "127.0.0.1", oReq:cIP )
   HixTU_Check( hCtx, oReq:RealIP() == "9.8.7.6", "Proxied: RealIP==XFF value",         "9.8.7.6",   oReq:RealIP() )
   oReq := _ParseRequest( ;
      _MakeRequest( "/ip", "X-Real-IP: 5.5.5.5" + cCRLF ), ;
      "127.0.0.1", .T. )
   HixTU_Check( hCtx, oReq:RealIP() == "5.5.5.5", "Proxied: RealIP==X-Real-IP", "5.5.5.5", oReq:RealIP() )
   oReq := _ParseRequest( ;
      _MakeRequest( "/ip", "X-Forwarded-For: 1.1.1.1, 10.0.0.2" + cCRLF ), ;
      "127.0.0.1", .T. )
   HixTU_Check( hCtx, oReq:RealIP() == "1.1.1.1", "Proxied: multi-hop primera IP", "1.1.1.1", oReq:RealIP() )
   oReq := _ParseRequest( ;
      _MakeRequest( "/ip", ;
         "X-Forwarded-For: 2.2.2.2" + cCRLF + ;
         "X-Real-IP: 3.3.3.3" + cCRLF ), ;
      "127.0.0.1", .T. )
   HixTU_Check( hCtx, oReq:RealIP() == "2.2.2.2", "Proxied: XFF prioridad sobre X-Real-IP", "2.2.2.2", oReq:RealIP() )
   oReq := _ParseRequest( ;
      _MakeRequest( "/ip", "X-Forwarded-For: 9.9.9.9" + cCRLF ), ;
      "8.8.8.8", .T. )
   HixTU_Check( hCtx, oReq:RealIP() == "8.8.8.8", "Proxied: no-trusted XFF ignorado", "8.8.8.8", oReq:RealIP() )
RETURN
