/*-----------------------------------------------------------
  File ......: hix_test_proxy.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — reverse proxy helpers
               (HIX_IsTrustedProxy, HIX_ParseForwarded, RealIP/Scheme/RealHost)
 -----------------------------------------------------------*/
#include "hix_logger.ch"

// Uses shared TMockIO from hix_test_utils.prg

STATIC FUNCTION _CRLF()
RETURN Chr(13) + Chr(10)

STATIC FUNCTION _MakeReqPx( cPath, cExtraHeaders )
   LOCAL cH, cCRLF
   cCRLF := _CRLF()
   hb_default( @cPath,         "/" )
   hb_default( @cExtraHeaders, "" )
   cH := "GET " + cPath + " HTTP/1.1" + cCRLF + ;
         "Host: localhost" + cCRLF + ;
         cExtraHeaders + ;
         cCRLF
RETURN cH

STATIC FUNCTION _ParseReqPx( cRaw, cIP, lRead )
   LOCAL oIO, oReq
   hb_default( @cIP,  "127.0.0.1" )
   hb_default( @lRead, .T.        )
   oIO  := TMockIO():New( cRaw, "" )
   oReq := THixRequest():New( oIO, cIP, .T. )
   IF lRead ; oReq:Read() ; ENDIF
RETURN oReq

FUNCTION HIX_TestProxy_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   _TestPxTrustedProxy(    hCtx )
   _TestPxParseForwarded(  hCtx )
   _TestPxRealIP(          hCtx )
   _TestPxScheme(          hCtx )
   _TestPxRealHost(        hCtx )
   _TestPxForwardedHeader( hCtx )
   _TestPxChainAndSpoof(   hCtx )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _TestPxTrustedProxy( hCtx )
   HIX_ProxyInit( "127.0.0.1 10.0.0.0/8" )
   HixTU_Check( hCtx, HIX_IsTrustedProxy( "127.0.0.1" ), "Proxy T01: 127.0.0.1 trusted",        ".T.", ".F." )
   HixTU_Check( hCtx, ! HIX_IsTrustedProxy( "8.8.8.8" ), "Proxy T02: 8.8.8.8 not trusted",       ".F.", ".T." )
   HixTU_Check( hCtx, HIX_IsTrustedProxy( "10.5.0.1" ),  "Proxy T03: CIDR 10/8 acepta 10.5.0.1", ".T.", ".F." )
   HIX_ProxyInit( "127.0.0.1" )
RETURN

STATIC PROCEDURE _TestPxParseForwarded( hCtx )
   LOCAL hRes
   hRes := HIX_ParseForwarded( "for=1.2.3.4;proto=https;host=example.com;by=10.0.0.1" )
   HixTU_Check( hCtx, hb_HGetDef( hRes, "for",   "" ) == "1.2.3.4",    "Proxy T04a: for=1.2.3.4",    "1.2.3.4",    hb_HGetDef( hRes, "for",   "" ) )
   HixTU_Check( hCtx, hb_HGetDef( hRes, "proto", "" ) == "https",       "Proxy T04b: proto=https",    "https",      hb_HGetDef( hRes, "proto", "" ) )
   HixTU_Check( hCtx, hb_HGetDef( hRes, "host",  "" ) == "example.com", "Proxy T04c: host=example.com","example.com",hb_HGetDef( hRes, "host",  "" ) )
   hRes := HIX_ParseForwarded( 'for="1.2.3.4";proto="http"' )
   HixTU_Check( hCtx, hb_HGetDef( hRes, "for", "" ) == "1.2.3.4", "Proxy T04d: for entre comillas", "1.2.3.4", hb_HGetDef( hRes, "for", "" ) )
   hRes := HIX_ParseForwarded( "for=[::1];proto=http" )
   HixTU_Check( hCtx, hb_HGetDef( hRes, "for", "" ) == "::1", "Proxy T04e: for IPv6 brackets", "::1", hb_HGetDef( hRes, "for", "" ) )
   hRes := HIX_ParseForwarded( "for=1.2.3.4:8080" )
   HixTU_Check( hCtx, hb_HGetDef( hRes, "for",  "" ) == "1.2.3.4", "Proxy T04f: IPv4:port -> IP",   "1.2.3.4", hb_HGetDef( hRes, "for",  "" ) )
   HixTU_Check( hCtx, hb_HGetDef( hRes, "port", "" ) == "8080",    "Proxy T04g: IPv4:port -> port", "8080",    hb_HGetDef( hRes, "port", "" ) )
RETURN

STATIC PROCEDURE _TestPxRealIP( hCtx )
   LOCAL oReq, cCRLF
   cCRLF := _CRLF()
   HIX_ProxyInit( "127.0.0.1" )
   oReq := _ParseReqPx( _MakeReqPx( "/", "X-Forwarded-For: 4.5.6.7" + cCRLF ), "127.0.0.1" )
   HixTU_Check( hCtx, oReq:RealIP() == "4.5.6.7", "Proxy T05: trusted => RealIP()=XFF", "4.5.6.7", oReq:RealIP() )
   oReq := _ParseReqPx( _MakeReqPx( "/", "X-Forwarded-For: 4.5.6.7" + cCRLF ), "9.9.9.9" )
   HixTU_Check( hCtx, oReq:RealIP() == "9.9.9.9", "Proxy T06: non-trusted => RealIP()=TCP", "9.9.9.9", oReq:RealIP() )
RETURN

STATIC PROCEDURE _TestPxScheme( hCtx )
   LOCAL oReq, cCRLF
   cCRLF := _CRLF()
   HIX_ProxyInit( "127.0.0.1" )
   oReq := _ParseReqPx( _MakeReqPx( "/", "X-Forwarded-Proto: https" + cCRLF ), "127.0.0.1" )
   HixTU_Check( hCtx, oReq:Scheme() == "https", "Proxy T07: X-Forwarded-Proto:https -> https", "https", oReq:Scheme() )
   HixTU_Check( hCtx, oReq:IsHttps(),           "Proxy T07b: IsHttps() .T.",                   ".T.",   ".F." )
   oReq := _ParseReqPx( _MakeReqPx( "/" ), "127.0.0.1" )
   HixTU_Check( hCtx, oReq:Scheme() == "http",  "Proxy T08: sin proto -> http",                "http",  oReq:Scheme() )
   HixTU_Check( hCtx, ! oReq:IsHttps(),         "Proxy T08b: IsHttps() .F.",                   ".F.",   ".T." )
RETURN

STATIC PROCEDURE _TestPxRealHost( hCtx )
   LOCAL oReq, cCRLF
   cCRLF := _CRLF()
   HIX_ProxyInit( "127.0.0.1" )
   oReq := _ParseReqPx( _MakeReqPx( "/", "X-Forwarded-Host: example.com" + cCRLF ), "127.0.0.1" )
   HixTU_Check( hCtx, oReq:RealHost() == "example.com", "Proxy T09: RealHost() = X-Forwarded-Host", "example.com", oReq:RealHost() )
   oReq := _ParseReqPx( _MakeReqPx( "/" ), "127.0.0.1" )
   HixTU_Check( hCtx, oReq:RealHost() == "localhost",   "Proxy T09b: RealHost() = Host header",     "localhost",   oReq:RealHost() )
RETURN

STATIC PROCEDURE _TestPxForwardedHeader( hCtx )
   LOCAL oReq, cCRLF
   cCRLF := _CRLF()
   HIX_ProxyInit( "127.0.0.1" )
   oReq := _ParseReqPx( _MakeReqPx( "/", ;
      "Forwarded: for=5.6.7.8;proto=https;host=api.example.com" + cCRLF + ;
      "X-Forwarded-For: 1.2.3.4" + cCRLF ), "127.0.0.1" )
   HixTU_Check( hCtx, oReq:RealIP()   == "5.6.7.8",        "Proxy T10a: Forwarded precede a XFF",  "5.6.7.8",        oReq:RealIP() )
   HixTU_Check( hCtx, oReq:Scheme()   == "https",           "Proxy T10b: Forwarded proto=https",    "https",           oReq:Scheme() )
   HixTU_Check( hCtx, oReq:RealHost() == "api.example.com", "Proxy T10c: Forwarded host=api...",    "api.example.com", oReq:RealHost() )
RETURN

STATIC PROCEDURE _TestPxChainAndSpoof( hCtx )
   LOCAL oReq, cCRLF
   cCRLF := _CRLF()
   HIX_ProxyInit( "127.0.0.1 10.0.0.0/8" )
   oReq := _ParseReqPx( _MakeReqPx( "/", "X-Forwarded-For: 2.3.4.5, 10.0.0.1, 127.0.0.1" + cCRLF ), "127.0.0.1" )
   HixTU_Check( hCtx, oReq:RealIP() == "2.3.4.5", "Proxy T11: XFF chain -> primer IP no-proxy", "2.3.4.5", oReq:RealIP() )
   oReq := _ParseReqPx( _MakeReqPx( "/", "X-Forwarded-For: 1.1.1.1" + cCRLF ), "9.9.9.9" )
   HixTU_Check( hCtx, oReq:RealIP() == "9.9.9.9", "Proxy T12: XFF spoof ignorado (no-trusted)", "9.9.9.9", oReq:RealIP() )
RETURN
