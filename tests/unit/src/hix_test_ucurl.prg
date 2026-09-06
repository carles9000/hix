/*-----------------------------------------------------------
  File ......: hix_test_ucurl.prg
  Author.....: Charly 9000
  Created....: 2026-08-31
  Description: Integrated test — UCurl HTTP client wrapper
                (src/curl/ucurl.prg). Uses local peer server
                on port 8100 (started by app.prg). No internet
                required.
 -----------------------------------------------------------*/
#include "hbcurl.ch"
#include "hix_logger.ch"


FUNCTION HIX_TestUCurl_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   HIX_TestPeer_Ensure()

   _TUCurlGet( hCtx )
   _TUCurlPostForm( hCtx )
   _TUCurlVerbs( hCtx )
   _TUCurlErrorBody( hCtx )
   _TUCurlHeaders( hCtx )
   _TUCurlResetBetweenRuns( hCtx )
   _TUCurlEndIdempotent( hCtx )
   _TUCurlResponseHashSafe( hCtx )
   _TUCurlTimeout( hCtx )
   _TUCurlConnectorCompat( hCtx )
   _TUCurlVersionSymbol( hCtx )
   _TUCurlDownload( hCtx )
   _TUCurlUpload( hCtx )

RETURN hCtx

// ============================================================
// Helper — peer base URL
// ============================================================
STATIC FUNCTION _PeerUrl( cPath )
RETURN "http://127.0.0.1:" + hb_NToS( HixTU_PeerPort() ) + cPath

// ============================================================
// T01/T02 — GET simple and GET with query string built from hFields
// ============================================================
STATIC PROCEDURE _TUCurlGet( hCtx )

   LOCAL o, hResp, nRet

   // T01 — GET simple
   o := UCurl():New( _PeerUrl( "/ping" ), NIL, "GET" )
   nRet := o:Run()

   HixTU_Check( hCtx, nRet == HB_CURLE_OK, ;
      "UCurl T01: GET simple returns HB_CURLE_OK", "0", hb_NToS( nRet ) )

   HixTU_Check( hCtx, o:GetHttpCode() == 200, ;
      "UCurl T02: GET /ping -> 200", "200", hb_NToS( o:GetHttpCode() ) )

   HixTU_Check( hCtx, ! Empty( o:GetResponse() ), ;
      "UCurl T03: GET body not empty", "non-empty", "empty" )

   o:End()

   // T04 — GET with query string built from hFields
   o := UCurl():New( _PeerUrl( "/echo" ), { "k" => "v value", "n" => 42 }, "GET" )
   o:Run()
   hResp := hb_jsonDecode( o:GetResponse() )

   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. hResp[ "method" ] == "GET", ;
      "UCurl T04: /echo confirms GET verb", "GET", ;
      iif( HB_ISHASH( hResp ), hResp[ "method" ], "?" ) )

   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. "k=v%20value" $ hResp[ "query" ] .AND. "n=42" $ hResp[ "query" ], ;
      "UCurl T05: GET builds urlencoded query string", "k=v%20value&n=42", ;
      iif( HB_ISHASH( hResp ), hResp[ "query" ], "?" ) )

   o:End()

RETURN

// ============================================================
// T06/T07 — POST form-urlencoded with typed values (fix B8)
// ============================================================
STATIC PROCEDURE _TUCurlPostForm( hCtx )

   LOCAL o, hResp, cBody

   o := UCurl():New( _PeerUrl( "/echo" ), { ;
      "name"   => "Charly", ;
      "age"    => 42,       ;
      "active" => .T.,      ;
      "born"   => hb_SToD( "20260101" ) } )
   o:Run()

   hResp := hb_jsonDecode( o:GetResponse() )
   cBody := iif( HB_ISHASH( hResp ), hResp[ "body" ], "" )

   HixTU_Check( hCtx, "name=Charly" $ cBody, ;
      "UCurl T06: POST body contains name=Charly", "name=Charly", cBody )

   HixTU_Check( hCtx, "age=42" $ cBody, ;
      "UCurl T07: POST encodes numeric as '42' (not '42.00')", "age=42", cBody )

   HixTU_Check( hCtx, "active=true" $ cBody, ;
      "UCurl T08: POST encodes logical .T. as 'true'", "active=true", cBody )

   HixTU_Check( hCtx, "born=2026-01-01" $ cBody, ;
      "UCurl T09: POST encodes date as ISO 'yyyy-mm-dd'", "born=2026-01-01", cBody )

   o:End()

RETURN

// ============================================================
// T10/T11 — PUT and DELETE via CUSTOMREQUEST (fix B4)
// ============================================================
STATIC PROCEDURE _TUCurlVerbs( hCtx )

   LOCAL o, hResp

   // PUT
   o := UCurl():New( _PeerUrl( "/echo" ), { "x" => "1" }, "PUT" )
   o:Run()
   hResp := hb_jsonDecode( o:GetResponse() )

   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. hResp[ "method" ] == "PUT", ;
      "UCurl T10: PUT verb reaches peer as PUT (fix B4)", "PUT", ;
      iif( HB_ISHASH( hResp ), hResp[ "method" ], "?" ) )

   o:End()

   // DELETE
   o := UCurl():New( _PeerUrl( "/echo" ), NIL, "DELETE" )
   o:Run()
   hResp := hb_jsonDecode( o:GetResponse() )

   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. hResp[ "method" ] == "DELETE", ;
      "UCurl T11: DELETE verb reaches peer as DELETE (fix B4)", "DELETE", ;
      iif( HB_ISHASH( hResp ), hResp[ "method" ], "?" ) )

   o:End()

RETURN

// ============================================================
// T12/T13 — HTTP 4xx keeps body (fix B9)
// ============================================================
STATIC PROCEDURE _TUCurlErrorBody( hCtx )

   LOCAL o

   o := UCurl():New( _PeerUrl( "/status/404" ), NIL, "GET" )
   o:Run()

   HixTU_Check( hCtx, o:GetHttpCode() == 404, ;
      "UCurl T12: /status/404 -> HttpCode 404", "404", hb_NToS( o:GetHttpCode() ) )

   HixTU_Check( hCtx, ! Empty( o:GetResponse() ), ;
      "UCurl T13: 404 response body preserved (fix B9)", ;
      "non-empty", "empty" )

   o:End()

RETURN

// ============================================================
// T14 — AddHeader + T15 AddHeaderHash reach the peer
// ============================================================
STATIC PROCEDURE _TUCurlHeaders( hCtx )

   LOCAL o, hResp, hHeaders

   // T14 — AddHeader
   o := UCurl():New( _PeerUrl( "/echo" ), NIL, "GET" )
   o:AddHeader( "X-Test-Str: hello" )
   o:Run()
   hResp    := hb_jsonDecode( o:GetResponse() )
   hHeaders := iif( HB_ISHASH( hResp ), hResp[ "headers" ], { => } )

   HixTU_Check( hCtx, hb_HHasKey( hHeaders, "x-test-str" ) .AND. hHeaders[ "x-test-str" ] == "hello", ;
      "UCurl T14: AddHeader(str) reaches peer", "hello", ;
      hb_HGetDef( hHeaders, "x-test-str", "?" ) )

   o:End()

   // T15 — AddHeaderHash
   o := UCurl():New( _PeerUrl( "/echo" ), NIL, "GET" )
   o:AddHeaderHash( { "X-A" => "aa", "X-B" => "bb" } )
   o:Run()
   hResp    := hb_jsonDecode( o:GetResponse() )
   hHeaders := iif( HB_ISHASH( hResp ), hResp[ "headers" ], { => } )

   HixTU_Check( hCtx, hb_HGetDef( hHeaders, "x-a", "" ) == "aa" .AND. hb_HGetDef( hHeaders, "x-b", "" ) == "bb", ;
      "UCurl T15: AddHeaderHash sets multiple headers", "aa/bb", ;
      hb_HGetDef( hHeaders, "x-a", "?" ) + "/" + hb_HGetDef( hHeaders, "x-b", "?" ) )

   o:End()

RETURN

// ============================================================
// T16 — Reset per-Run: response/error cleared between calls
// ============================================================
STATIC PROCEDURE _TUCurlResetBetweenRuns( hCtx )

   LOCAL o

   // First: 404 sets cError
   o := UCurl():New( _PeerUrl( "/status/404" ), NIL, "GET" )
   o:Run()

   HixTU_Check( hCtx, ! Empty( o:GetError() ), ;
      "UCurl T16a: first Run (404) populates cError", "non-empty", "empty" )

   // Second: same instance, hit /ping -> should be clean
   o:cUrl := _PeerUrl( "/ping" )
   o:Run()

   HixTU_Check( hCtx, o:GetHttpCode() == 200 .AND. Empty( o:GetError() ), ;
      "UCurl T16b: second Run resets cError (fix)", "empty", o:GetError() )

   o:End()

RETURN

// ============================================================
// T17 — End() is idempotent (fix B3)
// ============================================================
STATIC PROCEDURE _TUCurlEndIdempotent( hCtx )

   LOCAL o, oErr, lOk := .T.

   o := UCurl():New( _PeerUrl( "/ping" ), NIL, "GET" )
   o:Run()

   TRY
      o:End()
      o:End()   // second call must not crash
   CATCH oErr
      lOk := .F.
   END

   HixTU_Check( hCtx, lOk, ;
      "UCurl T17: End() idempotent (fix B3)", ".T.", hb_CStr( lOk ) )

RETURN

// ============================================================
// T18 — GetResponseHash always returns hash-safe value (fix B10)
// ============================================================
STATIC PROCEDURE _TUCurlResponseHashSafe( hCtx )

   LOCAL o, xResp

   o := UCurl():New( _PeerUrl( "/ping" ), NIL, "GET" )
   o:Run()
   xResp := o:GetResponseHash()

   HixTU_Check( hCtx, HB_ISHASH( xResp ), ;
      "UCurl T18: GetResponseHash returns hash", ".T.", hb_CStr( HB_ISHASH( xResp ) ) )

   o:End()

   // Non-JSON body scenario: force cResponse to non-JSON manually
   o := UCurl():New( _PeerUrl( "/ping" ), NIL, "GET" )
   o:Run()
   o:cResponse := "not a json string"
   xResp := o:GetResponseHash()

   HixTU_Check( hCtx, HB_ISHASH( xResp ), ;
      "UCurl T19: GetResponseHash on non-JSON returns empty hash (fix B10)", ;
      ".T.", hb_CStr( HB_ISHASH( xResp ) ) )

   o:End()

RETURN

// ============================================================
// T20 — hOptions timeout honored (dead port fails fast)
// ============================================================
STATIC PROCEDURE _TUCurlTimeout( hCtx )

   LOCAL o, nStart, nElapsed

   // Port 9 is discard — connection should be refused fast.
   // With timeout=1 the whole call must complete in <3s regardless.
   o := UCurl():New( "http://127.0.0.1:9/nowhere", NIL, "GET", ;
      { "HB_CURLOPT_TIMEOUT" => 1 } )

   nStart := Seconds()
   o:Run()
   nElapsed := Seconds() - nStart

   HixTU_Check( hCtx, nElapsed < 3, ;
      "UCurl T20: timeout=1 completes in <3s", "<3s", hb_NToS( nElapsed ) )

   HixTU_Check( hCtx, ! Empty( o:GetError() ), ;
      "UCurl T21: dead port yields cError", "non-empty", "empty" )

   o:End()

RETURN

// ============================================================
// T22 — Compat: connector.prg-style call pattern still works
// ============================================================
STATIC PROCEDURE _TUCurlConnectorCompat( hCtx )

   LOCAL o, nRet

   // Exactly the pattern from z/exemples_curl/connector.prg
   o := UCurl():New( _PeerUrl( "/echo" ), { "field" => "value" }, NIL, {=>} )
   o:AddHeader( "Authorization: Bearer test-token" )
   nRet := o:Run()

   HixTU_Check( hCtx, nRet == 0 .AND. o:GetHttpCode() == 200, ;
      "UCurl T22: connector.prg pattern (New 4-args + AddHeader + Run) still works", ;
      "0/200", hb_NToS( nRet ) + "/" + hb_NToS( o:GetHttpCode() ) )

   o:End()

RETURN

// ============================================================
// T23 — CURL_VERSION symbol pulled into the exe (fixes banner
//        showing "n/a (hbcurl not linked)"). Uses HIX_OptFunc
//        exactly like hix_server.prg boot banner does.
// ============================================================
STATIC PROCEDURE _TUCurlVersionSymbol( hCtx )

   LOCAL cVer  := HIX_OptFunc( "CURL_VERSION", "n/a" )
   LOCAL cVer2 := HIX_OptFunc( "HPDF_VERSION_TEXT", "n/a" )

   HixTU_Check( hCtx, cVer != "n/a" .AND. ! Empty( cVer ), ;
      "UCurl T23: CURL_VERSION resolved (boot banner fix)", ;
      "libcurl/x.y.z", cVer )

   HixTU_Check( hCtx, cVer2 != "n/a" .AND. ! Empty( cVer2 ), ;
      "UCurl T23b: HPDF_VERSION_TEXT resolved (boot banner fix)", ;
      "2.x.x", cVer2 )

RETURN

// ============================================================
// T24-T27 — Download: GET /file/N streamed straight to disk
// ============================================================
STATIC PROCEDURE _TUCurlDownload( hCtx )

   LOCAL o, cLocal, nCode, nSize
   LOCAL cDownloaded, nExpected := 2048

   cLocal := hb_DirBase() + "traces" + hb_ps() + "ucurl_dl.bin"
   IF hb_FileExists( cLocal ) ; hb_FileDelete( cLocal ) ; ENDIF

   o     := UCurl():New()
   nCode := o:Download( _PeerUrl( "/file/" + hb_NToS( nExpected ) ), cLocal )

   HixTU_Check( hCtx, nCode == 200, ;
      "UCurl T24: Download /file/2048 -> 200", "200", hb_NToS( nCode ) )

   HixTU_Check( hCtx, hb_FileExists( cLocal ), ;
      "UCurl T25: Download creates local file", ".T.", hb_CStr( hb_FileExists( cLocal ) ) )

   nSize := iif( hb_FileExists( cLocal ), hb_FSize( cLocal ), 0 )
   HixTU_Check( hCtx, nSize == nExpected, ;
      "UCurl T26: Downloaded file size matches", hb_NToS( nExpected ), hb_NToS( nSize ) )

   cDownloaded := iif( hb_FileExists( cLocal ), hb_MemoRead( cLocal ), "" )
   HixTU_Check( hCtx, cDownloaded == Replicate( "X", nExpected ), ;
      "UCurl T27: Downloaded content matches expected bytes", "XXX... (2048 X)", ;
      "len=" + hb_NToS( Len( cDownloaded ) ) )

   o:End()
   IF hb_FileExists( cLocal ) ; hb_FileDelete( cLocal ) ; ENDIF

RETURN

// ============================================================
// T28-T32 — Upload PUT and POST: send local file, verify size
// ============================================================
STATIC PROCEDURE _TUCurlUpload( hCtx )

   LOCAL o, cLocal, nCode, cPayload, hResp

   cPayload := Replicate( "ABCDEFGH", 512 )   // 4096 bytes deterministic
   cLocal   := hb_DirBase() + "traces" + hb_ps() + "ucurl_ul.bin"
   hb_MemoWrit( cLocal, cPayload )

   // ----- PUT (streamed via UL_FILE_SETUP) -----
   o     := UCurl():New()
   nCode := o:Upload( _PeerUrl( "/upload" ), cLocal, "PUT" )
   hResp := hb_jsonDecode( o:GetResponse() )

   HixTU_Check( hCtx, nCode == 200, ;
      "UCurl T28: Upload PUT -> 200", "200", hb_NToS( nCode ) )

   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. hResp[ "method" ] == "PUT", ;
      "UCurl T29: Upload PUT verb reaches peer", "PUT", ;
      iif( HB_ISHASH( hResp ), hResp[ "method" ], "?" ) )

   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. hResp[ "size" ] == Len( cPayload ), ;
      "UCurl T30: PUT body size matches source file", hb_NToS( Len( cPayload ) ), ;
      iif( HB_ISHASH( hResp ), hb_NToS( hResp[ "size" ] ), "?" ) )

   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. ;
                      hResp[ "first" ] == Left( cPayload, 16 ) .AND. ;
                      hResp[ "last"  ] == Right( cPayload, 16 ), ;
      "UCurl T31: PUT body bytes intact (first+last 16 match)", ;
      Left( cPayload, 16 ) + "..." + Right( cPayload, 16 ), ;
      iif( HB_ISHASH( hResp ), hResp[ "first" ] + "..." + hResp[ "last" ], "?" ) )

   o:End()

   // ----- POST (raw body via POSTFIELDS) -----
   o     := UCurl():New()
   nCode := o:Upload( _PeerUrl( "/upload" ), cLocal, "POST" )
   hResp := hb_jsonDecode( o:GetResponse() )

   HixTU_Check( hCtx, nCode == 200 .AND. HB_ISHASH( hResp ) .AND. ;
                      hResp[ "method" ] == "POST" .AND. ;
                      hResp[ "size" ] == Len( cPayload ), ;
      "UCurl T32: Upload POST works with same payload", ;
      "POST/" + hb_NToS( Len( cPayload ) ), ;
      iif( HB_ISHASH( hResp ), hResp[ "method" ] + "/" + hb_NToS( hResp[ "size" ] ), "?" ) )

   o:End()

   // Missing local file -> nCode=0 + cError populated
   o     := UCurl():New()
   nCode := o:Upload( _PeerUrl( "/upload" ), "z:\\nope\\missing.xxx", "PUT" )

   HixTU_Check( hCtx, nCode == 0 .AND. ! Empty( o:GetError() ), ;
      "UCurl T33: Upload of missing file returns 0 + cError", "0/error", ;
      hb_NToS( nCode ) + "/" + o:GetError() )

   o:End()

   IF hb_FileExists( cLocal ) ; hb_FileDelete( cLocal ) ; ENDIF

RETURN
