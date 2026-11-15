/*-----------------------------------------------------------
  File ......: hix_test_ws_detector.prg
  Author.....: Charly 9000
  Created....: 2026-09-07
  Description: Unit test — WebSocket protocol detection through
               HIX_DetectProtocol( cPeek ). Reproduces the
               "WS behind Cloudflare" bug by feeding synthetic
               request buffers truncated at the OLD peek_bytes
               (512), and validates the fix by feeding the same
               request truncated at the NEW peek_bytes (2048).
  Notes      : Pure function test — no sockets, deterministic.
 -----------------------------------------------------------*/
#include "hix_const.ch"

#define OLD_PEEK_BYTES 512
#define NEW_PEEK_BYTES 2048
#define CRLF ( Chr(13) + Chr(10) )

FUNCTION HIX_TestWsDetector_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _TestCloudflareRequestBothConfigs( hCtx )
   _TestPlainWsRequest( hCtx )
   _TestMixedCaseUpgrade( hCtx )
   _TestPlainHttp( hCtx )
   _TestEmptyPeek( hCtx )

RETURN hCtx

// --------------------------------------------------------------------
// Helper: sintetiza un request estilo Cloudflare al origen.
// Los headers CF-* + X-Forwarded-* + Cookie hinchan las cabeceras
// hasta empujar "Upgrade: websocket" MÁS ALLÁ del byte 512.
// --------------------------------------------------------------------
STATIC FUNCTION _CloudflareRequest()

   LOCAL cReq

   cReq := "GET /ws HTTP/1.1" + CRLF
   cReq += "Host: hix.example.com" + CRLF
   cReq += "CF-Ray: 8a7b6c5d4e3f2a1b-MAD" + CRLF
   cReq += 'CF-Visitor: {"scheme":"https"}' + CRLF
   cReq += "CF-Connecting-IP: 203.0.113.42" + CRLF
   cReq += "CF-IPCountry: ES" + CRLF
   cReq += "CDN-Loop: cloudflare" + CRLF
   cReq += "X-Forwarded-For: 203.0.113.42, 172.68.1.1" + CRLF
   cReq += "X-Forwarded-Proto: https" + CRLF
   cReq += "X-Forwarded-Host: hix.example.com" + CRLF
   cReq += "X-Real-IP: 203.0.113.42" + CRLF
   cReq += "Accept-Language: es-ES,es;q=0.9,en;q=0.8,ca;q=0.7" + CRLF
   cReq += "Accept-Encoding: gzip, deflate, br, zstd" + CRLF
   cReq += "Accept: */*" + CRLF
   cReq += "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " + ;
           "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36" + CRLF
   cReq += "Cookie: session_id=" + Replicate( "a", 128 ) + ;
           "; csrf_token=" + Replicate( "b", 96 ) + ;
           "; pref=" + Replicate( "c", 64 ) + CRLF
   // Aquí, sobre byte ~700, llega el token que el detector busca.
   cReq += "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" + CRLF
   cReq += "Sec-WebSocket-Version: 13" + CRLF
   cReq += "Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits" + CRLF
   cReq += "Connection: Upgrade" + CRLF
   cReq += "Upgrade: websocket" + CRLF
   cReq += CRLF

RETURN cReq

// --------------------------------------------------------------------
// El corazón del test: MISMO request, DOS configs de peek_bytes.
// Config antigua (512 B)  -> el token no llega  -> detecta HTTP  (BUG)
// Config nueva  (2048 B)  -> el token sí llega  -> detecta WS    (FIX)
// --------------------------------------------------------------------
STATIC PROCEDURE _TestCloudflareRequestBothConfigs( hCtx )

   LOCAL cReq, cPeekOld, cPeekNew, cTipoOld, cTipoNew, nOffset

   cReq := _CloudflareRequest()

   // Sanity: el request completo contiene el token
   nOffset := At( "upgrade: websocket", Lower( cReq ) )
   HixTU_Check( hCtx, nOffset > OLD_PEEK_BYTES, ;
      "Detector: token 'upgrade: websocket' cae más allá del byte " + hb_NToS( OLD_PEEK_BYTES ), ;
      "> " + hb_NToS( OLD_PEEK_BYTES ), hb_NToS( nOffset ) )

   HixTU_Check( hCtx, nOffset <= NEW_PEEK_BYTES, ;
      "Detector: token cabe dentro del byte " + hb_NToS( NEW_PEEK_BYTES ), ;
      "<= " + hb_NToS( NEW_PEEK_BYTES ), hb_NToS( nOffset ) )

   // Config ANTIGUA — peek_bytes 512 → detector NO ve el token → HTTP (bug)
   cPeekOld := Left( cReq, OLD_PEEK_BYTES )
   cTipoOld := HIX_DetectProtocol( cPeekOld )
   HixTU_Check( hCtx, cTipoOld == HIX_CONN_HTTP, ;
      "Detector (peek_bytes=512, CONFIG ANTIGUA): request Cloudflare -> HTTP (BUG reproducido)", ;
      HIX_CONN_HTTP, cTipoOld )

   // Config NUEVA — peek_bytes 2048 → detector SÍ ve el token → WS (fix)
   cPeekNew := Left( cReq, NEW_PEEK_BYTES )
   cTipoNew := HIX_DetectProtocol( cPeekNew )
   HixTU_Check( hCtx, cTipoNew == HIX_CONN_WS, ;
      "Detector (peek_bytes=2048, CONFIG NUEVA): request Cloudflare -> WS (FIX aplicado)", ;
      HIX_CONN_WS, cTipoNew )

RETURN

// --------------------------------------------------------------------
// Caso no-proxy: request WS puro, headers minimalistas. Ambos peek
// bytes lo detectan correctamente. Regresión: el fix no rompe esto.
// --------------------------------------------------------------------
STATIC PROCEDURE _TestPlainWsRequest( hCtx )

   LOCAL cReq, cTipoOld, cTipoNew

   cReq := "GET /ws HTTP/1.1" + CRLF + ;
           "Host: localhost" + CRLF + ;
           "Upgrade: websocket" + CRLF + ;
           "Connection: Upgrade" + CRLF + ;
           "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" + CRLF + ;
           "Sec-WebSocket-Version: 13" + CRLF + CRLF

   cTipoOld := HIX_DetectProtocol( Left( cReq, OLD_PEEK_BYTES ) )
   cTipoNew := HIX_DetectProtocol( Left( cReq, NEW_PEEK_BYTES ) )

   HixTU_Check( hCtx, cTipoOld == HIX_CONN_WS, ;
      "Detector: WS puro con peek_bytes=512 -> WS", HIX_CONN_WS, cTipoOld )
   HixTU_Check( hCtx, cTipoNew == HIX_CONN_WS, ;
      "Detector: WS puro con peek_bytes=2048 -> WS", HIX_CONN_WS, cTipoNew )

RETURN

// --------------------------------------------------------------------
// Casing mixto: la implementación aplica Lower() al peek antes de
// buscar el token, así que UpGrAdE debe detectarse igual.
// --------------------------------------------------------------------
STATIC PROCEDURE _TestMixedCaseUpgrade( hCtx )

   LOCAL cReq, cTipo

   cReq := "GET /ws HTTP/1.1" + CRLF + ;
           "Host: localhost" + CRLF + ;
           "UpGrAdE: WebSocket" + CRLF + ;
           "Connection: Upgrade" + CRLF + CRLF

   cTipo := HIX_DetectProtocol( cReq )
   HixTU_Check( hCtx, cTipo == HIX_CONN_WS, ;
      "Detector: 'UpGrAdE: WebSocket' (mixed case) -> WS", HIX_CONN_WS, cTipo )

RETURN

// --------------------------------------------------------------------
// HTTP normal: sin Upgrade. Debe seguir siendo HTTP en ambos peek.
// --------------------------------------------------------------------
STATIC PROCEDURE _TestPlainHttp( hCtx )

   LOCAL cReq, cTipo

   cReq := "GET / HTTP/1.1" + CRLF + ;
           "Host: localhost" + CRLF + ;
           "Accept: text/html" + CRLF + CRLF

   cTipo := HIX_DetectProtocol( cReq )
   HixTU_Check( hCtx, cTipo == HIX_CONN_HTTP, ;
      "Detector: HTTP GET / -> HTTP", HIX_CONN_HTTP, cTipo )

RETURN

// --------------------------------------------------------------------
// Buffer vacío: UNKNOWN (equivalente a peek con nRead <= 0).
// --------------------------------------------------------------------
STATIC PROCEDURE _TestEmptyPeek( hCtx )

   LOCAL cTipo := HIX_DetectProtocol( "" )
   HixTU_Check( hCtx, cTipo == HIX_CONN_UNKNOWN, ;
      "Detector: peek vacío -> UNKNOWN", HIX_CONN_UNKNOWN, cTipo )

RETURN
