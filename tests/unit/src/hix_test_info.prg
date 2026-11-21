/*-----------------------------------------------------------
  File ......: hix_test_info.prg
  Author.....: Charly 9000
  Created....: 2026-11-03
  Description: Integrated test - HIX_InfoHash() + /hix-info endpoint
               path constant + POST /hix-setup 409 UX (v2.4.5)
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hix_const.ch"
#include "hbclass.ch"

FUNCTION HIX_TestInfo_Run()
   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   HIX_MetricsInit()
   _TestInfoPathConst( hCtx )
   _TestInfoHashShape( hCtx )
   _TestInfoHashVersions( hCtx )
   _TestInfoHashRdd( hCtx )
   _TestInfoHashLanguage( hCtx )
   _TestInfoHashServer( hCtx )
   _TestSetup409AlreadyConfigured( hCtx )
   HIX_MetricsClose()
RETURN hCtx

STATIC PROCEDURE _TestInfoPathConst( hCtx )
   HixTU_Check( hCtx, HIX_PATH_INFO == "/hix-info", ;
      "Info: HIX_PATH_INFO constant", "/hix-info", HIX_PATH_INFO )
RETURN

STATIC PROCEDURE _TestInfoHashShape( hCtx )
   LOCAL hInfo := HIX_InfoHash()

   HixTU_Check( hCtx, ValType( hInfo ) == "H", ;
      "Info: HIX_InfoHash returns hash", "H", ValType( hInfo ) )
   HixTU_Check( hCtx, hb_HHasKey( hInfo, "versions" ), ;
      "Info: has 'versions' section", ".T.", hb_CStr( hb_HHasKey( hInfo, "versions" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hInfo, "rdd" ), ;
      "Info: has 'rdd' section", ".T.", hb_CStr( hb_HHasKey( hInfo, "rdd" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hInfo, "language" ), ;
      "Info: has 'language' section", ".T.", hb_CStr( hb_HHasKey( hInfo, "language" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hInfo, "server" ), ;
      "Info: has 'server' section", ".T.", hb_CStr( hb_HHasKey( hInfo, "server" ) ) )
RETURN

STATIC PROCEDURE _TestInfoHashVersions( hCtx )
   LOCAL hVer := HIX_InfoHash()[ "versions" ]

   HixTU_Check( hCtx, ValType( hVer ) == "H", ;
      "Info: versions is hash", "H", ValType( hVer ) )
   HixTU_Check( hCtx, hb_HHasKey( hVer, "hix" ),      "Info: versions.hix",      ".T.", hb_CStr( hb_HHasKey( hVer, "hix" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hVer, "harbour" ),  "Info: versions.harbour",  ".T.", hb_CStr( hb_HHasKey( hVer, "harbour" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hVer, "openssl" ),  "Info: versions.openssl",  ".T.", hb_CStr( hb_HHasKey( hVer, "openssl" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hVer, "curl" ),     "Info: versions.curl",     ".T.", hb_CStr( hb_HHasKey( hVer, "curl" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hVer, "harupdf" ),  "Info: versions.harupdf",  ".T.", hb_CStr( hb_HHasKey( hVer, "harupdf" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hVer, "compiler" ), "Info: versions.compiler", ".T.", hb_CStr( hb_HHasKey( hVer, "compiler" ) ) )
   HixTU_Check( hCtx, "HIX " $ hVer[ "hix" ], ;
      "Info: versions.hix starts with 'HIX '", ".T.", hb_CStr( "HIX " $ hVer[ "hix" ] ) )
RETURN

STATIC PROCEDURE _TestInfoHashRdd( hCtx )
   LOCAL hRdd := HIX_InfoHash()[ "rdd" ]

   HixTU_Check( hCtx, ValType( hRdd ) == "H",         "Info: rdd is hash",         "H",   ValType( hRdd ) )
   HixTU_Check( hCtx, hb_HHasKey( hRdd, "list" ),     "Info: rdd.list",            ".T.", hb_CStr( hb_HHasKey( hRdd, "list" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hRdd, "default" ),  "Info: rdd.default",         ".T.", hb_CStr( hb_HHasKey( hRdd, "default" ) ) )
   HixTU_Check( hCtx, ! Empty( hRdd[ "list" ] ),      "Info: rdd.list non-empty",  "non-empty", hRdd[ "list" ] )
   HixTU_Check( hCtx, ! Empty( hRdd[ "default" ] ),   "Info: rdd.default non-empty", "non-empty", hRdd[ "default" ] )
RETURN

STATIC PROCEDURE _TestInfoHashLanguage( hCtx )
   LOCAL hLang := HIX_InfoHash()[ "language" ]

   HixTU_Check( hCtx, ValType( hLang ) == "H",            "Info: language is hash",     "H",   ValType( hLang ) )
   HixTU_Check( hCtx, hb_HHasKey( hLang, "name" ),        "Info: language.name",        ".T.", hb_CStr( hb_HHasKey( hLang, "name" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hLang, "codepage" ),    "Info: language.codepage",    ".T.", hb_CStr( hb_HHasKey( hLang, "codepage" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hLang, "cdpuni" ),      "Info: language.cdpuni",      ".T.", hb_CStr( hb_HHasKey( hLang, "cdpuni" ) ) )
RETURN

STATIC PROCEDURE _TestInfoHashServer( hCtx )
   LOCAL hSrv := HIX_InfoHash()[ "server" ]

   HixTU_Check( hCtx, ValType( hSrv ) == "H",                 "Info: server is hash",                 "H",   ValType( hSrv ) )
   HixTU_Check( hCtx, hb_HHasKey( hSrv, "startup" ),          "Info: server.startup",                 ".T.", hb_CStr( hb_HHasKey( hSrv, "startup" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hSrv, "app_path" ),         "Info: server.app_path",                ".T.", hb_CStr( hb_HHasKey( hSrv, "app_path" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hSrv, "app_name" ),         "Info: server.app_name",                ".T.", hb_CStr( hb_HHasKey( hSrv, "app_name" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hSrv, "root" ),             "Info: server.root",                    ".T.", hb_CStr( hb_HHasKey( hSrv, "root" ) ) )
   HixTU_Check( hCtx, hb_HHasKey( hSrv, "hixstyle_active" ),  "Info: server.hixstyle_active",         ".T.", hb_CStr( hb_HHasKey( hSrv, "hixstyle_active" ) ) )
   HixTU_Check( hCtx, ValType( hSrv[ "hixstyle_active" ] ) == "L", ;
      "Info: server.hixstyle_active is logical", "L", ValType( hSrv[ "hixstyle_active" ] ) )
RETURN

STATIC PROCEDURE _TestSetup409AlreadyConfigured( hCtx )
   LOCAL oCfgSave, hCfg, oMock

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )

   hCfg := HIX_GetConfig()
   IF ! hb_HHasKey( hCfg, "admin" )
      hCfg[ "admin" ] := { => }
   ENDIF
   hCfg[ "admin" ][ "user"     ] := "admin"
   hCfg[ "admin" ][ "password" ] := "deadbeef"
   hCfg[ "admin" ][ "secret"   ] := "cafebabe"

   oMock := TMockReq():New( "POST", HIX_PATH_SETUP, "" )
   oMock:cBody := "user=admin&password=secret1&password2=secret1"
   oMock:hHeaders[ "content-type" ] := "application/x-www-form-urlencoded"

   HIX_AdminSetupPost( oMock )

   HixTU_Check( hCtx, oMock:lResponded, ;
      "Info/Setup: 409 - oReq:Respond llamado", ".T.", hb_CStr( oMock:lResponded ) )
   HixTU_Check( hCtx, oMock:nStatus == 409, ;
      "Info/Setup: 409 cuando admin ya configurado", "409", hb_NToS( oMock:nStatus ) )
   HixTU_Check( hCtx, oMock:cMime == "html", ;
      "Info/Setup: respuesta 409 es HTML", "html", oMock:cMime )
   HixTU_Check( hCtx, ! Empty( oMock:cBodyResp ), ;
      "Info/Setup: body 409 no vacio", "non-empty", iif( Empty( oMock:cBodyResp ), "(vacio)", "ok" ) )

   HIX_SetConfig( oCfgSave )
RETURN
