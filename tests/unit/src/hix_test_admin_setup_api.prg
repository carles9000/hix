/*-----------------------------------------------------------
  File ......: hix_test_admin_setup_api.prg
  Author.....: Charly 9000
  Created....: 2026-11-04
  Description: Integrated test - HIX_AdminSetupApi() JSON endpoint
               POST /hix-setup-api (admin credentials bootstrap)
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hix_const.ch"
#include "hbclass.ch"

FUNCTION HIX_TestAdminSetupApi_Run()

   LOCAL hCtx     := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL oCfgSave

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )

   HIX_MetricsInit()

   TRY

      _TestPathConst( hCtx )
      _TestSuccessJson( hCtx )
      _TestAlreadyConfigured( hCtx )
      _TestUserEmpty( hCtx )
      _TestPasswordShort( hCtx )
      _TestHmacSignature( hCtx )
      _TestSuccessFormBody( hCtx )

   FINALLY

      // Restore in-memory config + re-save disk so tests/unit/hix.json
      // queda limpio para el siguiente run.
      HIX_SetConfig( oCfgSave )
      HIX_SaveConfig()

   END

   HIX_MetricsClose()

RETURN hCtx

STATIC PROCEDURE _TestPathConst( hCtx )

   HixTU_Check( hCtx, HIX_PATH_SETUP_API == "/hix-setup-api", ;
      "SetupApi: HIX_PATH_SETUP_API constant", "/hix-setup-api", HIX_PATH_SETUP_API )

RETURN

STATIC PROCEDURE _TestSuccessJson( hCtx )

   LOCAL oMock, hCfg, hResp

   _ClearAdminCreds()

   oMock := TMockReq():New( "POST", HIX_PATH_SETUP_API, "" )
   oMock:cBody := '{"user":"admin","password":"secret1"}'
   oMock:hHeaders[ "content-type" ] := "application/json"

   HIX_AdminSetupApi( oMock )

   HixTU_Check( hCtx, oMock:nStatus == 201, ;
      "SetupApi: success → 201", "201", hb_NToS( oMock:nStatus ) )
   HixTU_Check( hCtx, oMock:cMime == "json", ;
      "SetupApi: success response is JSON", "json", oMock:cMime )

   hResp := hb_jsonDecode( oMock:cBodyResp )
   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. hb_HGetDef( hResp, "ok", .F. ), ;
      "SetupApi: success body ok=true", ".T.", ;
      iif( HB_ISHASH( hResp ), hb_CStr( hb_HGetDef( hResp, "ok", "?" ) ), "no-hash" ) )
   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. hb_HGetDef( hResp, "user", "" ) == "admin", ;
      "SetupApi: success body user=admin", "admin", ;
      iif( HB_ISHASH( hResp ), hb_HGetDef( hResp, "user", "?" ), "no-hash" ) )

   hCfg := HIX_GetConfig()
   HixTU_Check( hCtx, hCfg[ "admin" ][ "user" ] == "admin", ;
      "SetupApi: hCfg admin.user written", "admin", hCfg[ "admin" ][ "user" ] )
   HixTU_Check( hCtx, ! Empty( hCfg[ "admin" ][ "password" ] ), ;
      "SetupApi: hCfg admin.password non-empty", "non-empty", ;
      iif( Empty( hCfg[ "admin" ][ "password" ] ), "(empty)", "ok" ) )
   HixTU_Check( hCtx, ! Empty( hCfg[ "admin" ][ "secret" ] ), ;
      "SetupApi: hCfg admin.secret non-empty", "non-empty", ;
      iif( Empty( hCfg[ "admin" ][ "secret" ] ), "(empty)", "ok" ) )

RETURN

STATIC PROCEDURE _TestAlreadyConfigured( hCtx )

   LOCAL oMock, hResp

   // Rellenar credenciales a mano para forzar el branch 409.
   HIX_GetConfig()[ "admin" ][ "user"     ] := "admin"
   HIX_GetConfig()[ "admin" ][ "password" ] := "deadbeef"
   HIX_GetConfig()[ "admin" ][ "secret"   ] := "cafebabe"

   oMock := TMockReq():New( "POST", HIX_PATH_SETUP_API, "" )
   oMock:cBody := '{"user":"other","password":"newpass"}'
   oMock:hHeaders[ "content-type" ] := "application/json"

   HIX_AdminSetupApi( oMock )

   HixTU_Check( hCtx, oMock:nStatus == 409, ;
      "SetupApi: already configured → 409", "409", hb_NToS( oMock:nStatus ) )

   hResp := hb_jsonDecode( oMock:cBodyResp )
   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. hb_HGetDef( hResp, "error", "" ) == "already_configured", ;
      "SetupApi: body error=already_configured", "already_configured", ;
      iif( HB_ISHASH( hResp ), hb_HGetDef( hResp, "error", "?" ), "no-hash" ) )

RETURN

STATIC PROCEDURE _TestUserEmpty( hCtx )

   LOCAL oMock, hResp

   _ClearAdminCreds()

   oMock := TMockReq():New( "POST", HIX_PATH_SETUP_API, "" )
   oMock:cBody := '{"user":"","password":"secret1"}'
   oMock:hHeaders[ "content-type" ] := "application/json"

   HIX_AdminSetupApi( oMock )

   HixTU_Check( hCtx, oMock:nStatus == 422, ;
      "SetupApi: user vacío → 422", "422", hb_NToS( oMock:nStatus ) )

   hResp := hb_jsonDecode( oMock:cBodyResp )
   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. hb_HGetDef( hResp, "error", "" ) == "user_empty", ;
      "SetupApi: body error=user_empty", "user_empty", ;
      iif( HB_ISHASH( hResp ), hb_HGetDef( hResp, "error", "?" ), "no-hash" ) )

RETURN

STATIC PROCEDURE _TestPasswordShort( hCtx )

   LOCAL oMock, hResp

   _ClearAdminCreds()

   oMock := TMockReq():New( "POST", HIX_PATH_SETUP_API, "" )
   oMock:cBody := '{"user":"admin","password":"ab"}'
   oMock:hHeaders[ "content-type" ] := "application/json"

   HIX_AdminSetupApi( oMock )

   HixTU_Check( hCtx, oMock:nStatus == 422, ;
      "SetupApi: password <6 → 422", "422", hb_NToS( oMock:nStatus ) )

   hResp := hb_jsonDecode( oMock:cBodyResp )
   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. hb_HGetDef( hResp, "error", "" ) == "password_short", ;
      "SetupApi: body error=password_short", "password_short", ;
      iif( HB_ISHASH( hResp ), hb_HGetDef( hResp, "error", "?" ), "no-hash" ) )

RETURN

STATIC PROCEDURE _TestHmacSignature( hCtx )

   LOCAL oMock, hCfg, cPass, cExpected

   cPass := "myPlainPwd42"

   _ClearAdminCreds()

   oMock := TMockReq():New( "POST", HIX_PATH_SETUP_API, "" )
   oMock:cBody := '{"user":"charly","password":"' + cPass + '"}'
   oMock:hHeaders[ "content-type" ] := "application/json"

   HIX_AdminSetupApi( oMock )

   hCfg := HIX_GetConfig()
   cExpected := Lower( hb_HMAC_SHA256( cPass, hCfg[ "admin" ][ "secret" ] ) )

   HixTU_Check( hCtx, hCfg[ "admin" ][ "password" ] == cExpected, ;
      "SetupApi: password = HMAC_SHA256(plain, secret)", cExpected, hCfg[ "admin" ][ "password" ] )

RETURN

STATIC PROCEDURE _TestSuccessFormBody( hCtx )

   LOCAL oMock, hResp

   _ClearAdminCreds()

   oMock := TMockReq():New( "POST", HIX_PATH_SETUP_API, "" )
   oMock:cBody := "user=admin&password=secret1"
   oMock:hHeaders[ "content-type" ] := "application/x-www-form-urlencoded"

   HIX_AdminSetupApi( oMock )

   HixTU_Check( hCtx, oMock:nStatus == 201, ;
      "SetupApi: form-urlencoded → 201", "201", hb_NToS( oMock:nStatus ) )

   hResp := hb_jsonDecode( oMock:cBodyResp )
   HixTU_Check( hCtx, HB_ISHASH( hResp ) .AND. hb_HGetDef( hResp, "ok", .F. ), ;
      "SetupApi: form body ok=true", ".T.", ;
      iif( HB_ISHASH( hResp ), hb_CStr( hb_HGetDef( hResp, "ok", "?" ) ), "no-hash" ) )

RETURN

STATIC PROCEDURE _ClearAdminCreds()

   LOCAL hCfg := HIX_GetConfig()

   IF ! hb_HHasKey( hCfg, "admin" )
      hCfg[ "admin" ] := { => }
   ENDIF
   hCfg[ "admin" ][ "user"     ] := ""
   hCfg[ "admin" ][ "password" ] := ""
   hCfg[ "admin" ][ "secret"   ] := ""

RETURN
