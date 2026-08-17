/*-----------------------------------------------------------
  File ......: hix_test_mw_flush.prg
  Author.....: Charly 9000
  Created....: 2026-07-21
  Modified...: 2026-07-21
  Version....: 1.0.0
  Description: Regression test — verifies the short-circuit flush
               in _HixEvalMiddleware. When a middleware writes to
               the echo buffer via USend* and cuts the chain with
               lHandled=.T. + RETURN .F., the router must still
               emit the response (previously the buffer was lost
               because _HixEvalAction never ran).
  Usage      : Invoked from tests.master app CLI runner
  Notes      : Uses TMockRequest from hix_test_utils.prg
 -----------------------------------------------------------*/
#include "hix_logger.ch"

// ------------------------------------------------------------
// Public middleware — writes via USendJson and cuts the chain.
// Must be public so UMiddleware:Run can resolve it by name.
// ------------------------------------------------------------
FUNCTION MwFlushDenyJson( oCtx )

   USendJson( { "error" => "denied_by_mw", "code" => "TEST_401" }, 401 )
   oCtx:lHandled := .T.

RETURN .F.

// ------------------------------------------------------------
// Public middleware — cuts the chain without touching the buffer.
// Verifies the 403 fallback still applies (regression guard).
// ------------------------------------------------------------
FUNCTION MwFlushSilentDeny( oCtx )

   HB_SYMBOL_UNUSED( oCtx )

RETURN .F.

// ------------------------------------------------------------
// Public action — used by the "allowed" route. Should never
// run in the deny cases; presence lets us confirm short-circuit.
// ------------------------------------------------------------
FUNCTION MwFlushAction( oReq )

   oReq:Respond( "action_ran", 200, "text" )

RETURN NIL

STATIC FUNCTION _Dispatch( cPath )
   LOCAL oReq := TMockRequest():New( cPath, "GET" )
   HIX_RouteDispatch( oReq )
RETURN oReq

FUNCTION HIX_TestMwFlush_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   HIX_RouteAdd( "mwflush.deny",   "/mwflush/deny",   ;
      {|oR| MwFlushAction( oR ) }, "GET", "MwFlushDenyJson"   )
   HIX_RouteAdd( "mwflush.silent", "/mwflush/silent", ;
      {|oR| MwFlushAction( oR ) }, "GET", "MwFlushSilentDeny" )

   _MwFlushCaseJson(   hCtx )
   _MwFlushCaseSilent( hCtx )

   HIX_RouteDelete( "mwflush.deny"   )
   HIX_RouteDelete( "mwflush.silent" )

RETURN hCtx

// ------------------------------------------------------------
// Case A: middleware wrote to the echo buffer via USendJson
// and cut the chain. Router must flush the buffer.
// ------------------------------------------------------------
STATIC PROCEDURE _MwFlushCaseJson( hCtx )

   LOCAL oReq, hBody

   oReq := _Dispatch( "/mwflush/deny" )

   HixTU_Check( hCtx, oReq:lResponded, ;
      "MwFlush: responded", ".T.", iif( oReq:lResponded, ".T.", ".F." ) )
   HixTU_Check( hCtx, oReq:nStatus == 401, ;
      "MwFlush: status 401", "401", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cMime == "json", ;
      "MwFlush: mime json", "json", oReq:cMime )

   hBody := NIL
   hb_jsonDecode( oReq:cBody, @hBody )
   HixTU_Check( hCtx, ValType( hBody ) == "H", ;
      "MwFlush: body is JSON hash", "H", ValType( hBody ) )
   IF ValType( hBody ) == "H"
      HixTU_Check( hCtx, hb_HGetDef( hBody, "code", "" ) == "TEST_401", ;
         "MwFlush: body.code", "TEST_401", hb_HGetDef( hBody, "code", "" ) )
      HixTU_Check( hCtx, hb_HGetDef( hBody, "error", "" ) == "denied_by_mw", ;
         "MwFlush: body.error", "denied_by_mw", hb_HGetDef( hBody, "error", "" ) )
   ENDIF

   HixTU_Check( hCtx, oReq:cBody != "action_ran", ;
      "MwFlush: action did not run", "not action_ran", oReq:cBody )

RETURN

// ------------------------------------------------------------
// Case B: middleware cut the chain without writing anything.
// The default 403 fallback must still fire — no regression.
// ------------------------------------------------------------
STATIC PROCEDURE _MwFlushCaseSilent( hCtx )

   LOCAL oReq := _Dispatch( "/mwflush/silent" )

   HixTU_Check( hCtx, oReq:lResponded, ;
      "MwFlush silent: responded", ".T.", iif( oReq:lResponded, ".T.", ".F." ) )
   HixTU_Check( hCtx, oReq:nStatus == 403, ;
      "MwFlush silent: status 403", "403", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oReq:cBody != "action_ran", ;
      "MwFlush silent: action did not run", "not action_ran", oReq:cBody )

RETURN
