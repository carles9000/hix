/*-----------------------------------------------------------
  File ......: hix_test_mw_system.prg
  Author.....: Charly 9000
  Created....: 2026-06-04
  Description: Integrated test — UMiddleware / UBaseMiddleware pipeline
 -----------------------------------------------------------*/
#include "hbclass.ch"
#include "hix_logger.ch"

// PUBLIC functions — called by string name from UMiddleware
FUNCTION TMwPass( oCtx )
   HB_SYMBOL_UNUSED( oCtx )
RETURN .T.

FUNCTION TMwFail( oCtx )
   oCtx:lHandled := .T.
RETURN .F.

FUNCTION TMwSetData( oCtx )
   oCtx:hData[ "visited" ] := .T.
RETURN .T.

FUNCTION TMwReadData( oCtx )
   oCtx:hData[ "chain" ] := hb_HGetDef( oCtx:hData, "chain", "" ) + "B"
RETURN .T.

FUNCTION TMwWriteData( oCtx )
   oCtx:hData[ "chain" ] := "A"
RETURN .T.

FUNCTION TMwCheckScope( oCtx )
   oCtx:hData[ "scope_seen" ] := oCtx:cScope
RETURN .T.

FUNCTION TMwFailSilent( oCtx )
   HB_SYMBOL_UNUSED( oCtx )
RETURN .F.

// Uses shared TMockRequest from hix_test_utils.prg

STATIC FUNCTION _RunComposite( oCtx )
   LOCAL o := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "TMwSetData", "data" ) )
   o:Add( UMiddleware():New( "TMwPass",    "pass" ) )
RETURN o:Run()

FUNCTION HIX_TestMwSystem_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   _MwsContext(     hCtx )
   _MwsUMiddleware( hCtx )
   _MwsUBase(       hCtx )
   _MwsLoader(      hCtx )
   _MwsCOnFail(     hCtx )
   _MwsSecHeaders(  hCtx )
   _MwsApiKey(      hCtx )
   _MwsReqLog(      hCtx )
   _MwsMaintenance( hCtx )
   _MwsBodyLimit(   hCtx )
RETURN hCtx

STATIC PROCEDURE _MwsContext( hCtx )
   LOCAL oReq, oCtx
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq, "MyMw", "admin" )
   HixTU_Check( hCtx, oCtx:cMw    == "MyMw",           "MwSys: cMw stored",       "MyMw",  oCtx:cMw )
   HixTU_Check( hCtx, oCtx:cScope == "admin",           "MwSys: cScope stored",    "admin", oCtx:cScope )
   HixTU_Check( hCtx, ValType( oCtx:hData ) == "H",     "MwSys: hData is hash",    "H",     ValType( oCtx:hData ) )
   HixTU_Check( hCtx, ! oCtx:lHandled,                  "MwSys: lHandled .F.",     ".F.",   hb_CStr( oCtx:lHandled ) )
   HixTU_Check( hCtx, oCtx:oReq == oReq,                "MwSys: oReq stored",      "same",  "same" )
   oCtx := THixContext():New( oReq )
   HixTU_Check( hCtx, oCtx:cMw    == "",                "MwSys: cMw default empty","",      oCtx:cMw )
   HixTU_Check( hCtx, oCtx:cScope == "",                "MwSys: cScope default empty","",   oCtx:cScope )
RETURN

STATIC PROCEDURE _MwsUMiddleware( hCtx )
   LOCAL oReq, oCtx, oMw, lOk
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   oMw  := UMiddleware():New( {|o| HB_SYMBOL_UNUSED(o), .T. }, "cb_pass" )
   lOk  := oMw:Run( oCtx )
   HixTU_Check( hCtx, lOk, "MwSys: cb .T.", ".T.", hb_CStr( lOk ) )
   oMw  := UMiddleware():New( {|o| HB_SYMBOL_UNUSED(o), .F. }, "cb_fail" )
   lOk  := oMw:Run( oCtx )
   HixTU_Check( hCtx, ! lOk, "MwSys: cb .F.", ".F.", hb_CStr( lOk ) )
   oCtx := THixContext():New( oReq )
   oCtx:hData[ "visited" ] := .F.
   oMw  := UMiddleware():New( {|o| o:hData["visited"] := .T., .T. }, "cb_data" )
   oMw:Run( oCtx )
   HixTU_Check( hCtx, oCtx:hData[ "visited" ], "MwSys: cb modifica hData", ".T.", hb_CStr( oCtx:hData["visited"] ) )
   oCtx := THixContext():New( oReq )
   oMw  := UMiddleware():New( "TMwPass", "str_pass" )
   lOk  := oMw:Run( oCtx )
   HixTU_Check( hCtx, lOk, "MwSys: str .T.", ".T.", hb_CStr( lOk ) )
   oCtx := THixContext():New( oReq )
   oMw  := UMiddleware():New( "TMwFail", "str_fail" )
   lOk  := oMw:Run( oCtx )
   HixTU_Check( hCtx, ! lOk,         "MwSys: str .F.",         ".F.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, oCtx:lHandled, "MwSys: str lHandled .T.", ".T.", hb_CStr( oCtx:lHandled ) )
   oCtx := THixContext():New( oReq )
   oMw  := UMiddleware():New( "TMwSetData", "str_data" )
   oMw:Run( oCtx )
   HixTU_Check( hCtx, hb_HGetDef( oCtx:hData, "visited", .F. ), "MwSys: str sets hData", ".T.", hb_CStr( hb_HGetDef( oCtx:hData, "visited", .F. ) ) )
   oMw  := UMiddleware():New( NIL, "nil_func" )
   lOk  := oMw:Run( oCtx )
   HixTU_Check( hCtx, ! lOk, "MwSys: NIL func -> .F.", ".F.", hb_CStr( lOk ) )
   oMw  := UMiddleware():New( "TMwFunctionDoesNotExist_XYZ", "bad_name" )
   lOk  := oMw:Run( oCtx )
   HixTU_Check( hCtx, ! lOk, "MwSys: bad name -> .F.", ".F.", hb_CStr( lOk ) )
RETURN

STATIC PROCEDURE _MwsUBase( hCtx )
   LOCAL oReq, oCtx, o, lOk
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   o    := UBaseMiddleware():New( oCtx )
   lOk  := o:Run()
   HixTU_Check( hCtx, lOk, "MwSys: empty pipeline .T.", ".T.", hb_CStr( lOk ) )
   oCtx := THixContext():New( oReq )
   o    := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "TMwPass", "pass" ) )
   lOk  := o:Run()
   HixTU_Check( hCtx, lOk, "MwSys: single .T.", ".T.", hb_CStr( lOk ) )
   oCtx := THixContext():New( oReq )
   o    := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "TMwPass", "pass1" ) )
   o:Add( UMiddleware():New( "TMwPass", "pass2" ) )
   lOk  := o:Run()
   HixTU_Check( hCtx, lOk, "MwSys: two .T. -> .T.", ".T.", hb_CStr( lOk ) )
   oCtx := THixContext():New( oReq )
   o    := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "TMwFail", "fail" ) )
   o:Add( UMiddleware():New( "TMwSetData", "should_not_run" ) )
   lOk  := o:Run()
   HixTU_Check( hCtx, ! lOk, "MwSys: first .F. short-circuit", ".F.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, ! hb_HGetDef( oCtx:hData, "visited", .F. ), "MwSys: second not called", ".F.", hb_CStr( hb_HGetDef( oCtx:hData, "visited", .F. ) ) )
   oCtx := THixContext():New( oReq )
   o    := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "TMwWriteData", "write" ) )
   o:Add( UMiddleware():New( "TMwReadData",  "read"  ) )
   o:Run()
   HixTU_Check( hCtx, hb_HGetDef( oCtx:hData, "chain", "" ) == "AB", "MwSys: hData propaga", "AB", hb_HGetDef( oCtx:hData, "chain", "" ) )
   oCtx := THixContext():New( oReq, "TMwCheckScope", "editor" )
   o    := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "TMwCheckScope", "scope" ) )
   o:Run()
   HixTU_Check( hCtx, hb_HGetDef( oCtx:hData, "scope_seen", "" ) == "editor", "MwSys: cScope visible", "editor", hb_HGetDef( oCtx:hData, "scope_seen", "" ) )
   oCtx := THixContext():New( oReq )
   o    := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "TMwFail", "fail" ) )
   o:Run()
   HixTU_Check( hCtx, oCtx:lHandled, "MwSys: lHandled tras .F.", ".T.", hb_CStr( oCtx:lHandled ) )
   oCtx := THixContext():New( oReq )
   lOk  := _RunComposite( oCtx )
   HixTU_Check( hCtx, lOk, "MwSys: composite .T.", ".T.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, hb_HGetDef( oCtx:hData, "visited", .F. ), "MwSys: composite hData", ".T.", hb_CStr( hb_HGetDef( oCtx:hData, "visited", .F. ) ) )
RETURN

STATIC PROCEDURE _MwsLoader( hCtx )
   LOCAL lOk, nLoaded
   lOk     := HIX_MwLoad( "non_existent_middleware_xyz.hrb" )
   HixTU_Check( hCtx, ! lOk,        "MwSys: missing file -> .F.", ".F.", hb_CStr( lOk ) )
   nLoaded := HIX_MwLoadDir( "non_existent_dir_xyz" )
   HixTU_Check( hCtx, nLoaded == 0, "MwSys: missing dir -> 0",   "0",   hb_NToS( nLoaded ) )
RETURN

STATIC PROCEDURE _MwsCOnFail( hCtx )
   LOCAL oReq, oCtx, oMw, o, lOk
   oReq := TMockRequest():New()
   oMw  := UMiddleware():New( "TMwFailSilent", "fail", "/auth/login.prg" )
   HixTU_Check( hCtx, oMw:cOnFail == "/auth/login.prg", "MwSys: cOnFail stored", "/auth/login.prg", oMw:cOnFail )
   oCtx := THixContext():New( oReq )
   o    := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "TMwFailSilent", "fail", "/auth/login.prg" ) )
   lOk  := o:Run()
   HixTU_Check( hCtx, ! lOk,                             "MwSys: cOnFail pipeline .F.",    ".F.",             hb_CStr( lOk ) )
   HixTU_Check( hCtx, oCtx:cOnFail == "/auth/login.prg", "MwSys: cOnFail propagado",       "/auth/login.prg", oCtx:cOnFail )
   oCtx := THixContext():New( oReq )
   o    := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "TMwFailSilent", "fail" ) )
   o:Run()
   HixTU_Check( hCtx, oCtx:cOnFail == "", "MwSys: sin cOnFail ctx queda vacio", "", oCtx:cOnFail )
   oCtx         := THixContext():New( oReq )
   oCtx:cOnFail := "/existing.prg"
   o            := UBaseMiddleware():New( oCtx )
   o:Add( UMiddleware():New( "TMwFailSilent", "fail", "/new.prg" ) )
   o:Run()
   HixTU_Check( hCtx, oCtx:cOnFail == "/existing.prg", "MwSys: first cOnFail wins", "/existing.prg", oCtx:cOnFail )
RETURN

STATIC PROCEDURE _MwsSecHeaders( hCtx )
   LOCAL oReq, oCtx, lOk, cCSP
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   lOk  := HIX_MwSecHeaders( oCtx )
   HixTU_Check( hCtx, lOk, "MwSys: SecHeaders .T.", ".T.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, hb_HGetDef( oReq:hExtraHeaders, "X-Frame-Options", "" ) == "DENY", "MwSys: X-Frame-Options DENY", "DENY", hb_HGetDef( oReq:hExtraHeaders, "X-Frame-Options", "" ) )
   HixTU_Check( hCtx, hb_HGetDef( oReq:hExtraHeaders, "X-Content-Type-Options", "" ) == "nosniff", "MwSys: X-Content-Type nosniff", "nosniff", hb_HGetDef( oReq:hExtraHeaders, "X-Content-Type-Options", "" ) )
   HixTU_Check( hCtx, hb_HGetDef( oReq:hExtraHeaders, "Strict-Transport-Security", "" ) == "max-age=31536000", "MwSys: Strict-Transport-Security", "max-age=31536000", hb_HGetDef( oReq:hExtraHeaders, "Strict-Transport-Security", "" ) )
   HixTU_Check( hCtx, hb_HGetDef( oReq:hExtraHeaders, "Content-Security-Policy", "" ) == "default-src 'self'", "MwSys: Content-Security-Policy", "default-src 'self'", hb_HGetDef( oReq:hExtraHeaders, "Content-Security-Policy", "" ) )
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   lOk  := Eval( HIX_MwSecHeadersFactory( "default-src 'none'" ), oCtx )
   cCSP := hb_HGetDef( oReq:hExtraHeaders, "Content-Security-Policy", "" )
   HixTU_Check( hCtx, lOk, "MwSys: SecHeaders Factory .T.", ".T.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, cCSP == "default-src 'none'", "MwSys: Factory CSP aplicado", "default-src 'none'", cCSP )
RETURN

STATIC PROCEDURE _MwsApiKey( hCtx )
   LOCAL oReq, oCtx, lOk, bMw
   HIX_MwApiKeySetup( { "secret-key-1", "secret-key-2" } )
   oReq := TMockRequest():New()
   oReq:hHeaders["x-api-key"] := "secret-key-1"
   oCtx := THixContext():New( oReq )
   lOk  := HIX_MwApiKey( oCtx )
   HixTU_Check( hCtx, lOk, "MwSys: ApiKey valida pasa", ".T.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, hb_HGetDef( oCtx:hData, "api_key", "" ) == "secret-key-1", "MwSys: hData[api_key]", "secret-key-1", hb_HGetDef( oCtx:hData, "api_key", "" ) )
   oReq := TMockRequest():New()
   oReq:hHeaders["x-api-key"] := "secret-key-2"
   oCtx := THixContext():New( oReq )
   HixTU_Check( hCtx, HIX_MwApiKey( oCtx ), "MwSys: ApiKey segunda key pasa", ".T.", ".F." )
   oReq := TMockRequest():New()
   oReq:hHeaders["x-api-key"] := "bad-key"
   oCtx := THixContext():New( oReq )
   lOk  := HIX_MwApiKey( oCtx )
   HixTU_Check( hCtx, ! lOk,               "MwSys: ApiKey mala rechazada", ".F.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, oReq:nStatus == 401, "MwSys: ApiKey 401",            "401", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oCtx:lHandled,       "MwSys: ApiKey lHandled .T.",   ".T.", hb_CStr( oCtx:lHandled ) )
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   lOk  := HIX_MwApiKey( oCtx )
   HixTU_Check( hCtx, ! lOk,               "MwSys: ApiKey sin header -> 401",".F.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, oReq:nStatus == 401, "MwSys: ApiKey sin header 401",  "401", hb_NToS( oReq:nStatus ) )
   bMw  := HIX_MwApiKeyFactory( { "factory-key" } )
   oReq := TMockRequest():New()
   oReq:hHeaders["x-api-key"] := "factory-key"
   oCtx := THixContext():New( oReq )
   lOk  := Eval( bMw, oCtx )
   HixTU_Check( hCtx, lOk, "MwSys: ApiKey Factory pasa", ".T.", hb_CStr( lOk ) )
   oReq := TMockRequest():New()
   oReq:hHeaders["x-api-key"] := "secret-key-1"
   oCtx := THixContext():New( oReq )
   lOk  := Eval( bMw, oCtx )
   HixTU_Check( hCtx, ! lOk, "MwSys: ApiKey Factory rechaza key global", ".F.", hb_CStr( lOk ) )
RETURN

STATIC PROCEDURE _MwsReqLog( hCtx )
   LOCAL oReq, oCtx, lOk
   oReq := TMockRequest():New()
   oReq:cMethod := "GET"
   oReq:cPath   := "/api/ping"
   oReq:cIP     := "10.0.0.1"
   oCtx := THixContext():New( oReq )
   lOk  := HIX_MwReqLog( oCtx )
   HixTU_Check( hCtx, lOk,             "MwSys: ReqLog .T.",        ".T.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, ! oCtx:lHandled,"MwSys: ReqLog lHandled .F.",".F.", hb_CStr( oCtx:lHandled ) )
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   lOk  := Eval( HIX_MwReqLogFactory( HIX_LOG_DEBUG ), oCtx )
   HixTU_Check( hCtx, lOk,             "MwSys: ReqLog Factory .T.", ".T.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, ! oCtx:lHandled,"MwSys: ReqLog Factory lHandled .F.",".F.", hb_CStr( oCtx:lHandled ) )
   oReq := TMockRequest():New()
   oReq:cMethod := "POST"
   oReq:cPath   := "/api/data"
   oCtx := THixContext():New( oReq )
   HixTU_Check( hCtx, HIX_MwReqLog( oCtx ), "MwSys: ReqLog POST pasa", ".T.", ".F." )
RETURN

STATIC PROCEDURE _MwsMaintenance( hCtx )
   LOCAL oReq, oCtx, lOk, cLockFile
   HIX_MwMaintenanceSetup( .F. )
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   lOk  := HIX_MwMaintenance( oCtx )
   HixTU_Check( hCtx, lOk,             "MwSys: Maint flag off pasa",  ".T.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, ! oCtx:lHandled,"MwSys: Maint lHandled .F.",   ".F.", hb_CStr( oCtx:lHandled ) )
   HIX_MwMaintenanceSetup( .T. )
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   lOk  := HIX_MwMaintenance( oCtx )
   HixTU_Check( hCtx, ! lOk,               "MwSys: Maint flag on -> 503", ".F.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, oReq:nStatus == 503, "MwSys: Maint 503",            "503", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oCtx:lHandled,       "MwSys: Maint lHandled .T.",   ".T.", hb_CStr( oCtx:lHandled ) )
   HIX_MwMaintenanceSetup( .F. )
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   HixTU_Check( hCtx, HIX_MwMaintenance( oCtx ), "MwSys: Maint toggle off pasa", ".T.", ".F." )
   cLockFile := hb_DirTemp() + "hix_tm_maint.lock"
   IF File( cLockFile ) ; FErase( cLockFile ) ; ENDIF
   HIX_MwMaintenanceSetup( .F., cLockFile )
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   HixTU_Check( hCtx, HIX_MwMaintenance( oCtx ), "MwSys: Maint file absent pasa", ".T.", ".F." )
   hb_MemoWrit( cLockFile, "" )
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   lOk  := HIX_MwMaintenance( oCtx )
   HixTU_Check( hCtx, ! lOk,               "MwSys: Maint file present -> 503", ".F.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, oReq:nStatus == 503, "MwSys: Maint file 503",           "503", hb_NToS( oReq:nStatus ) )
   IF File( cLockFile ) ; FErase( cLockFile ) ; ENDIF
   HIX_MwMaintenanceSetup( .F., "" )
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   lOk  := Eval( HIX_MwMaintenanceFactory( .T. ), oCtx )
   HixTU_Check( hCtx, ! lOk,               "MwSys: Maint Factory on -> 503", ".F.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, oReq:nStatus == 503, "MwSys: Maint Factory 503",       "503", hb_NToS( oReq:nStatus ) )
RETURN

STATIC PROCEDURE _MwsBodyLimit( hCtx )
   LOCAL oReq, oCtx, lOk
   HIX_MwBodyLimitSetup( 1024 )
   oReq := TMockRequest():New()
   oCtx := THixContext():New( oReq )
   lOk  := HIX_MwBodyLimit( oCtx )
   HixTU_Check( hCtx, lOk,             "MwSys: BodyLimit sin header pasa",".T.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, ! oCtx:lHandled,"MwSys: BodyLimit lHandled .F.",   ".F.", hb_CStr( oCtx:lHandled ) )
   oReq := TMockRequest():New()
   oReq:hHeaders["content-length"] := "512"
   oCtx := THixContext():New( oReq )
   HixTU_Check( hCtx, HIX_MwBodyLimit( oCtx ), "MwSys: BodyLimit 512<=1024 pasa", ".T.", ".F." )
   oReq := TMockRequest():New()
   oReq:hHeaders["content-length"] := "1024"
   oCtx := THixContext():New( oReq )
   HixTU_Check( hCtx, HIX_MwBodyLimit( oCtx ), "MwSys: BodyLimit exact limit pasa", ".T.", ".F." )
   oReq := TMockRequest():New()
   oReq:hHeaders["content-length"] := "1025"
   oCtx := THixContext():New( oReq )
   lOk  := HIX_MwBodyLimit( oCtx )
   HixTU_Check( hCtx, ! lOk,               "MwSys: BodyLimit 1025>1024 -> 413", ".F.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, oReq:nStatus == 413, "MwSys: BodyLimit 413",              "413", hb_NToS( oReq:nStatus ) )
   HixTU_Check( hCtx, oCtx:lHandled,       "MwSys: BodyLimit lHandled .T.",     ".T.", hb_CStr( oCtx:lHandled ) )
   oReq := TMockRequest():New()
   oReq:hHeaders["content-length"] := "100"
   oCtx := THixContext():New( oReq )
   lOk  := Eval( HIX_MwBodyLimitFactory( 50 ), oCtx )
   HixTU_Check( hCtx, ! lOk,               "MwSys: BodyLimit Factory 100>50 -> 413", ".F.", hb_CStr( lOk ) )
   HixTU_Check( hCtx, oReq:nStatus == 413, "MwSys: BodyLimit Factory 413",          "413", hb_NToS( oReq:nStatus ) )
   oReq := TMockRequest():New()
   oReq:hHeaders["content-length"] := "30"
   oCtx := THixContext():New( oReq )
   HixTU_Check( hCtx, Eval( HIX_MwBodyLimitFactory( 50 ), oCtx ), "MwSys: BodyLimit Factory 30<=50 pasa", ".T.", ".F." )
RETURN
