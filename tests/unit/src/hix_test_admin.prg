/*-----------------------------------------------------------
  File ......: hix_test_admin.prg
  Author.....: Charly 9000
  Created....: 2026-11-21
  Description: Admin login + cookie session + legacy PBKDF2 migration.
               Covers Claim 5 of the v2.5 external review:
               - HIX_PasswordHash (PBKDF2 600k) replaces HMAC-SHA256
               - HIX_ConstantEq on cookie signature verification
               - Transparent upgrade of legacy v2.5.0 records on first login
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "hix_const.ch"
#include "hbclass.ch"

FUNCTION HIX_TestAdmin_Run()

   LOCAL hCtx     := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL oCfgSave

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )

   HIX_MetricsInit()

   TRY

      _TestLoginOk(          hCtx )
      _TestLoginBadPassword( hCtx )
      _TestLoginBadUser(     hCtx )
      _TestLegacyUpgrade(    hCtx )
      _TestCookieValid(      hCtx )
      _TestCookieTampered(   hCtx )

   FINALLY

      HIX_SetConfig( oCfgSave )
      HIX_SaveConfig()

   END

   HIX_MetricsClose()

RETURN hCtx

// ============================================================
// Login con credenciales correctas (formato nuevo PBKDF2)
// ============================================================
STATIC PROCEDURE _TestLoginOk( hCtx )

   LOCAL oMock, cLocation

   _SetupFresh( "charly", "correcto-7" )

   oMock := TMockReq():New( "POST", "/hix-login", "" )
   oMock:cBody := "user=charly&password=correcto-7"
   oMock:hHeaders[ "content-type" ] := "application/x-www-form-urlencoded"

   HIX_AdminLoginPost( oMock )

   HixTU_Check( hCtx, oMock:nStatus == 302, ;
      "Admin: login OK → 302 redirect", "302", hb_NToS( oMock:nStatus ) )

   cLocation := hb_HGetDef( oMock:hExtraHeaders, "Location", "" )
   HixTU_Check( hCtx, ! Empty( cLocation ), ;
      "Admin: login OK emite Location", "non-empty", ;
      iif( Empty( cLocation ), "(empty)", "ok" ) )

   HixTU_Check( hCtx, hb_HHasKey( oMock:hExtraHeaders, "Set-Cookie" ), ;
      "Admin: login OK emite Set-Cookie hix_admin", "yes", ;
      iif( hb_HHasKey( oMock:hExtraHeaders, "Set-Cookie" ), "yes", "no" ) )

RETURN

// ============================================================
// Password incorrecto
// ============================================================
STATIC PROCEDURE _TestLoginBadPassword( hCtx )

   LOCAL oMock

   _SetupFresh( "charly", "correcto-7" )

   oMock := TMockReq():New( "POST", "/hix-login", "" )
   oMock:cBody := "user=charly&password=incorrecto"
   oMock:hHeaders[ "content-type" ] := "application/x-www-form-urlencoded"

   HIX_AdminLoginPost( oMock )

   HixTU_Check( hCtx, oMock:nStatus == 401, ;
      "Admin: password incorrecto → 401", "401", hb_NToS( oMock:nStatus ) )

RETURN

// ============================================================
// User incorrecto
// ============================================================
STATIC PROCEDURE _TestLoginBadUser( hCtx )

   LOCAL oMock

   _SetupFresh( "charly", "correcto-7" )

   oMock := TMockReq():New( "POST", "/hix-login", "" )
   oMock:cBody := "user=otro&password=correcto-7"
   oMock:hHeaders[ "content-type" ] := "application/x-www-form-urlencoded"

   HIX_AdminLoginPost( oMock )

   HixTU_Check( hCtx, oMock:nStatus == 401, ;
      "Admin: user incorrecto → 401", "401", hb_NToS( oMock:nStatus ) )

RETURN

// ============================================================
// Legacy upgrade: montar config v2.5.0 → login OK upgradea a PBKDF2
// ============================================================
STATIC PROCEDURE _TestLegacyUpgrade( hCtx )

   LOCAL oMock, hCfg, cPass, cLegacySecret, cLegacyHash

   cPass         := "LegacyPass42"
   cLegacySecret := "deadbeefcafebabedeadbeefcafebabe"
   cLegacyHash   := Lower( hb_HMAC_SHA256( cPass, cLegacySecret ) )

   _ClearAdmin()
   hCfg := HIX_GetConfig()
   hCfg[ "admin" ][ "user"     ] := "charly"
   hCfg[ "admin" ][ "password" ] := cLegacyHash
   hCfg[ "admin" ][ "secret"   ] := cLegacySecret

   // Precondiciones del estado legacy
   HixTU_Check( hCtx, ! hb_HHasKey( hCfg[ "admin" ], "passhash" ), ;
      "Legacy: estado inicial sin passhash", "no-key", ;
      iif( hb_HHasKey( hCfg[ "admin" ], "passhash" ), "PRESENT", "ok" ) )

   oMock := TMockReq():New( "POST", "/hix-login", "" )
   oMock:cBody := "user=charly&password=" + cPass
   oMock:hHeaders[ "content-type" ] := "application/x-www-form-urlencoded"

   HIX_AdminLoginPost( oMock )

   // Login acepta la credencial legacy
   HixTU_Check( hCtx, oMock:nStatus == 302, ;
      "Legacy: login con password HMAC-SHA256 → 302", "302", hb_NToS( oMock:nStatus ) )

   // Config ha migrado
   hCfg := HIX_GetConfig()
   HixTU_Check( hCtx, hb_HHasKey( hCfg[ "admin" ], "passhash" ) .AND. ;
                      Len( hCfg[ "admin" ][ "passhash" ] ) == 64, ;
      "Legacy: passhash PBKDF2 escrito tras upgrade", "64-hex", ;
      hb_NToS( Len( hb_HGetDef( hCfg[ "admin" ], "passhash", "" ) ) ) )

   HixTU_Check( hCtx, ! hb_HHasKey( hCfg[ "admin" ], "password" ), ;
      "Legacy: admin.password borrado tras upgrade", "removed", ;
      iif( hb_HHasKey( hCfg[ "admin" ], "password" ), "STILL-PRESENT", "ok" ) )

   HixTU_Check( hCtx, hb_HGetDef( hCfg[ "admin" ], "passalg", "" ) == "PBKDF2-SHA256", ;
      "Legacy: passalg = PBKDF2-SHA256", "PBKDF2-SHA256", ;
      hb_HGetDef( hCfg[ "admin" ], "passalg", "?" ) )

   HixTU_Check( hCtx, hCfg[ "admin" ][ "secret" ] != cLegacySecret, ;
      "Legacy: secret rotado tras upgrade (invalida cookies previas)", "rotated", ;
      iif( hCfg[ "admin" ][ "secret" ] == cLegacySecret, "SAME", "ok" ) )

RETURN

// ============================================================
// HIX_AdminCheck con cookie válida
// ============================================================
STATIC PROCEDURE _TestCookieValid( hCtx )

   LOCAL oMockLogin, oMockCheck, cCookie, aCookies, cSetCookie, cCookieVal

   _SetupFresh( "charly", "correcto-7" )

   oMockLogin := TMockReq():New( "POST", "/hix-login", "" )
   oMockLogin:cBody := "user=charly&password=correcto-7"
   oMockLogin:hHeaders[ "content-type" ] := "application/x-www-form-urlencoded"

   HIX_AdminLoginPost( oMockLogin )

   // Extraer valor de Set-Cookie
   cSetCookie := oMockLogin:hExtraHeaders[ "Set-Cookie" ]
   IF ValType( cSetCookie ) == "A"
      cSetCookie := cSetCookie[ 1 ]
   ENDIF

   cCookieVal := _ParseCookieValue( cSetCookie, "hix_admin" )

   HixTU_Check( hCtx, ! Empty( cCookieVal ), ;
      "Cookie: valor extraído tras login", "non-empty", ;
      iif( Empty( cCookieVal ), "(empty)", "ok" ) )

   // Request autenticada
   oMockCheck := TMockReq():New( "GET", "/hix-status", "" )
   oMockCheck:hHeaders[ "cookie" ] := "hix_admin=" + cCookieVal

   HixTU_Check( hCtx, HIX_AdminCheck( oMockCheck ), ;
      "Cookie: AdminCheck con firma válida → .T.", ".T.", ;
      iif( HIX_AdminCheck( oMockCheck ), ".T.", ".F." ) )

   HB_SYMBOL_UNUSED( aCookies )
   HB_SYMBOL_UNUSED( cCookie )

RETURN

// ============================================================
// HIX_AdminCheck con cookie firma manipulada
// ============================================================
STATIC PROCEDURE _TestCookieTampered( hCtx )

   LOCAL oMockLogin, oMockCheck, cSetCookie, cCookieVal, cTampered, aParts

   _SetupFresh( "charly", "correcto-7" )

   oMockLogin := TMockReq():New( "POST", "/hix-login", "" )
   oMockLogin:cBody := "user=charly&password=correcto-7"
   oMockLogin:hHeaders[ "content-type" ] := "application/x-www-form-urlencoded"

   HIX_AdminLoginPost( oMockLogin )

   cSetCookie := oMockLogin:hExtraHeaders[ "Set-Cookie" ]
   IF ValType( cSetCookie ) == "A"
      cSetCookie := cSetCookie[ 1 ]
   ENDIF

   cCookieVal := _ParseCookieValue( cSetCookie, "hix_admin" )

   // Mutar el último char del hash (hex) → firma inválida
   aParts := hb_ATokens( cCookieVal, ":" )
   IF Len( aParts ) >= 2
      aParts[ 2 ] := Left( aParts[ 2 ], Len( aParts[ 2 ] ) - 1 ) + ;
                     iif( Right( aParts[ 2 ], 1 ) == "0", "1", "0" )
      cTampered := aParts[ 1 ] + ":" + aParts[ 2 ]
   ELSE
      cTampered := "0:0"
   ENDIF

   oMockCheck := TMockReq():New( "GET", "/hix-status", "" )
   oMockCheck:hHeaders[ "cookie" ] := "hix_admin=" + cTampered

   HixTU_Check( hCtx, ! HIX_AdminCheck( oMockCheck ), ;
      "Cookie: AdminCheck con firma manipulada → .F.", ".F.", ;
      iif( HIX_AdminCheck( oMockCheck ), "BYPASS!", ".F.(ok)" ) )

RETURN

// ============================================================
// Helpers
// ============================================================

STATIC PROCEDURE _ClearAdmin()

   LOCAL hCfg := HIX_GetConfig()
   LOCAL aKeys := { "password", "passhash", "passalg", "passiter", "salt" }
   LOCAL cKey

   IF ! hb_HHasKey( hCfg, "admin" )
      hCfg[ "admin" ] := { => }
   ENDIF
   hCfg[ "admin" ][ "user"   ] := ""
   hCfg[ "admin" ][ "secret" ] := ""

   FOR EACH cKey IN aKeys
      IF hb_HHasKey( hCfg[ "admin" ], cKey )
         hb_HDel( hCfg[ "admin" ], cKey )
      ENDIF
   NEXT

RETURN

STATIC PROCEDURE _SetupFresh( cUser, cPass )

   LOCAL oMock

   _ClearAdmin()

   oMock := TMockReq():New( "POST", "/hix-setup-api", "" )
   oMock:cBody := '{"user":"' + cUser + '","password":"' + cPass + '"}'
   oMock:hHeaders[ "content-type" ] := "application/json"

   HIX_AdminSetupApi( oMock )

RETURN

// Extrae el valor de un Set-Cookie para un nombre dado.
// cSetCookie: "hix_admin=123:abc; Path=/; HttpOnly; SameSite=Lax; Max-Age=3600"
STATIC FUNCTION _ParseCookieValue( cSetCookie, cName )

   LOCAL cPrefix := cName + "="
   LOCAL nStart, nSemi

   nStart := At( cPrefix, cSetCookie )
   IF nStart == 0
      RETURN ""
   ENDIF
   nStart += Len( cPrefix )

   nSemi := At( ";", SubStr( cSetCookie, nStart ) )
   IF nSemi == 0
      RETURN SubStr( cSetCookie, nStart )
   ENDIF

RETURN SubStr( cSetCookie, nStart, nSemi - 1 )
