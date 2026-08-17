/*-----------------------------------------------------------
  File ......: hix_test_resource.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — HIX Resource ID signing helpers
 -----------------------------------------------------------*/
#include "hix_logger.ch"

// Uses shared TMockRequest from hix_test_utils.prg

STATIC FUNCTION _TokenFromHtml( cHtml )
   LOCAL i, cToken
   i      := At( 'value="', cHtml )
   cToken := SubStr( cHtml, i + 7 )
RETURN Left( cToken, At( '"', cToken ) - 1 )

FUNCTION HIX_TestResource_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   HIX_KeySet( "resource", "test-resource-key" )
   _TestResHtml(          hCtx )
   _TestResGetDirect(     hCtx )
   _TestResGetAutoRead(   hCtx )
   _TestResAliases(       hCtx )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _TestResHtml( hCtx )
   LOCAL cHtml
   cHtml := HIX_ResourceHtml( "42" )
   HixTU_Check( hCtx, "<input" $ cHtml,             "Res T01: has <input tag",      "<input",        cHtml )
   HixTU_Check( hCtx, 'name="_resource_id"' $ cHtml,"Res T02: name=_resource_id",   "name=_resource_id", cHtml )
   HixTU_Check( hCtx, 'type="hidden"' $ cHtml,      "Res T03: type=hidden",         "type=hidden",   cHtml )
   HixTU_Check( hCtx, 'value="' $ cHtml,            "Res T04: value attribute",      "value=",        cHtml )
   cHtml := HIX_ResourceHtml( 99 )
   HixTU_Check( hCtx, "<input" $ cHtml,             "Res T05: numeric ID accepted",  "<input",        cHtml )
   cHtml := HIX_ResourceHtml( "" )
   HixTU_Check( hCtx, "<!--" $ cHtml,              "Res T06: empty ID -> comment",  "<!--",           cHtml )
   HixTU_Check( hCtx, !( "<input" $ cHtml ),       "Res T07: empty ID no <input",   "no <input",     cHtml )
RETURN

STATIC PROCEDURE _TestResGetDirect( hCtx )
   LOCAL cHtml, cToken, cId
   cHtml  := HIX_ResourceHtml( "user-123" )
   cToken := _TokenFromHtml( cHtml )
   cId    := HIX_GetResource( cToken )
   HixTU_Check( hCtx, cId == "user-123",  "Res T08: extracts user-123",      "user-123", cId )
   cHtml  := HIX_ResourceHtml( "42" )
   cToken := _TokenFromHtml( cHtml )
   cId    := HIX_GetResource( cToken )
   HixTU_Check( hCtx, cId == "42",        "Res T09: extracts '42'",           "42",       cId )
   cHtml  := HIX_ResourceHtml( "a|b|c" )
   cToken := _TokenFromHtml( cHtml )
   cId    := HIX_GetResource( cToken )
   HixTU_Check( hCtx, cId == "a|b|c",    "Res T10: pipe chars reconstructed","a|b|c",    cId )
   cId := HIX_GetResource( "" )
   HixTU_Check( hCtx, cId == "",          "Res T11: empty token -> ''",       "''",       cId )
   cId := HIX_GetResource( "not.a.valid.token" )
   HixTU_Check( hCtx, cId == "",          "Res T12: malformed token -> ''",   "''",       cId )
   HIX_KeySet( "resource", "other-key" )
   cId := HIX_GetResource( cToken )
   HixTU_Check( hCtx, cId == "",          "Res T13: wrong key -> ''",         "''",       cId )
   HIX_KeySet( "resource", "test-resource-key" )
RETURN

STATIC PROCEDURE _TestResGetAutoRead( hCtx )
   LOCAL cHtml, cToken, cId, oReq
   cHtml  := HIX_ResourceHtml( "doc-99" )
   cToken := _TokenFromHtml( cHtml )
   oReq := TMockRequest():New()
   oReq:hFormBody := { "_resource_id" => cToken }
   HIX_SetRequest( oReq )
   cId := HIX_GetResource()
   HixTU_Check( hCtx, cId == "doc-99", "Res T14: reads from POST body",    "doc-99", cId )
   oReq := TMockRequest():New()
   oReq:hQueryParams := { "_resource_id" => cToken }
   HIX_SetRequest( oReq )
   cId := HIX_GetResource()
   HixTU_Check( hCtx, cId == "doc-99", "Res T15: reads from GET params",   "doc-99", cId )
   oReq := TMockRequest():New()
   HIX_SetRequest( oReq )
   cId := HIX_GetResource()
   HixTU_Check( hCtx, cId == "",       "Res T16: no token anywhere -> ''", "''",     cId )
   HIX_SetRequest( NIL )
RETURN

STATIC PROCEDURE _TestResAliases( hCtx )
   LOCAL cHtml, cToken, cId
   cHtml  := UResourceToHtml( "item-7" )
   HixTU_Check( hCtx, 'name="_resource_id"' $ cHtml, "Res T17: UResourceToHtml ok", "name=_resource_id", cHtml )
   cToken := _TokenFromHtml( cHtml )
   cId    := UGetResource( cToken )
   HixTU_Check( hCtx, cId == "item-7", "Res T18: UGetResource extracts item-7", "item-7", cId )
RETURN
