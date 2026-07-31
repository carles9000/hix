/*-----------------------------------------------------------
  File ......: hix_admin.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-11
  Description: Admin endpoint protection with signed cookie session.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_CONFIG

#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"

// ============================================================
// HIX_AdminCheck — punto de entrada para todos los endpoints admin.
// Retorna .T. si autorizado, .F. si redirigió.
// ============================================================
FUNCTION HIX_AdminCheck( oReq )

   IF UConfig( "app", "env", "dev" ) != "prod"

      RETURN .T.

   ENDIF

   IF ! _HixAdminHasCredentials()

      oReq:Redirect( HIX_PATH_SETUP )
      RETURN .F.

   ENDIF

   IF ! _HixAdminVerify( oReq:Cookie( "hix_admin", "" ), ;
         UConfig( "admin", "secret", "" ), ;
         UConfig( "session", "lifetime", 60 ) )

      oReq:Redirect( HIX_PATH_LOGIN + "?next=" + oReq:cPath )
      RETURN .F.

   ENDIF

RETURN .T.

// ============================================================
// HIX_AdminLoginGet — GET /hix-login
// ============================================================
FUNCTION HIX_AdminLoginGet( oReq )

   LOCAL cNext := oReq:QueryParam( "next", HIX_PATH_STATUS )

   oReq:Respond( _HixAdminLoginPage( "", cNext ), 200, "html" )

RETURN NIL

// ============================================================
// HIX_AdminLoginPost — POST /hix-login
// ============================================================
FUNCTION HIX_AdminLoginPost( oReq )

   LOCAL hForm := oReq:FormBody()
   LOCAL cUser := AllTrim( hb_HGetDef( hForm, "user",     "" ) )
   LOCAL cPass := hb_HGetDef( hForm, "password", "" )
   LOCAL cNext := hb_HGetDef( hForm, "next",     HIX_PATH_STATUS )
   LOCAL cAdminUser, cAdminPass, cAdminSecret, nMinutes
   LOCAL nTs, cSign, cCookieVal

   IF ! _HixAdminHasCredentials()

      oReq:Redirect( HIX_PATH_SETUP )
      RETURN NIL

   ENDIF

   cAdminUser   := UConfig( "admin", "user",            "" )
   cAdminPass   := UConfig( "admin", "password",        "" )
   cAdminSecret := UConfig( "admin", "secret",          "" )
   nMinutes     := UConfig( "session", "lifetime", 60 )

   IF Lower( cUser ) == Lower( cAdminUser ) .AND. ;
         Lower( hb_MD5( cPass ) ) == Lower( cAdminPass )

      nTs        := _HixNowSecs()
      cSign      := _HixAdminSign( cAdminSecret, nTs )
      cCookieVal := hb_NToS( nTs ) + ":" + cSign
      HIX_SetCookie( oReq, "hix_admin", cCookieVal, nMinutes * 60 )
      oReq:Redirect( iif( Empty( cNext ), HIX_PATH_STATUS, cNext ) )
      
   ELSE
   
      lw( _( "ADMIN_LOGIN_FAILED", cUser ) )
      oReq:Respond( _HixAdminLoginPage( _( 'ADMIN_ERR_CREDENTIALS' ), cNext ), 401, "html" )

   ENDIF

RETURN NIL

// ============================================================
// HIX_AdminLogout — GET /hix-logout
// ============================================================
FUNCTION HIX_AdminLogout( oReq )

   HIX_SetCookie( oReq, "hix_admin", "", - 1 )
   oReq:Redirect( HIX_PATH_LOGIN )

RETURN NIL

// ============================================================
// HIX_AdminSetupGet — GET /hix-setup
// ============================================================
FUNCTION HIX_AdminSetupGet( oReq )

   IF _HixAdminHasCredentials()

      oReq:Redirect( HIX_PATH_LOGIN )
      RETURN NIL

   ENDIF

   oReq:Respond( _HixAdminSetupPage( "" ), 200, "html" )

RETURN NIL

// ============================================================
// HIX_AdminSetupPost — POST /hix-setup
// ============================================================
FUNCTION HIX_AdminSetupPost( oReq )

   LOCAL hForm := oReq:FormBody()
   LOCAL cUser := AllTrim( hb_HGetDef( hForm, "user",      "" ) )
   LOCAL cPass := hb_HGetDef( hForm, "password",  "" )
   LOCAL cPass2 := hb_HGetDef( hForm, "password2", "" )
   LOCAL cErr  := ""
   LOCAL hCfg

   IF _HixAdminHasCredentials()

      oReq:Redirect( HIX_PATH_LOGIN )
      RETURN NIL

   ENDIF

   DO CASE

      CASE Empty( cUser )   ; cErr := _( 'ADMIN_ERR_USER_EMPTY' )
      CASE Len( cPass ) < 6 ; cErr := _( 'ADMIN_ERR_PASSWORD_SHORT' )
      CASE cPass != cPass2  ; cErr := _( 'ADMIN_ERR_PASSWORD_MISMATCH' )

   ENDCASE

   IF ! Empty( cErr )

      oReq:Respond( _HixAdminSetupPage( cErr ), 422, "html" )
      RETURN NIL

   ENDIF

   hCfg := HIX_GetConfig()
   hCfg[ "admin" ][ "user" ]     := cUser
   hCfg[ "admin" ][ "password" ] := Lower( hb_MD5( cPass ) )
   hCfg[ "admin" ][ "secret" ]   := Lower( hb_MD5( hb_TToS( hb_DateTime() ) + cUser + cPass ) )
   HIX_SaveConfig()

   l( "Admin configurado para usuario: " + cUser )
   oReq:Redirect( HIX_PATH_LOGIN )

RETURN NIL

// ============================================================
// Internos
// ============================================================

STATIC FUNCTION _HixAdminHasCredentials()
RETURN ! Empty( UConfig( "admin", "user", "" ) ) .AND. ! Empty( UConfig( "admin", "password", "" ) )

STATIC FUNCTION _HixNowSecs()
RETURN ( Date() - hb_SToD( "19700101" ) ) * 86400 + Int( Seconds() )

STATIC FUNCTION _HixAdminSign( cSecret, nTs )
RETURN Lower( hb_MD5( cSecret + "|" + hb_NToS( nTs ) ) )

STATIC FUNCTION _HixAdminVerify( cCookie, cSecret, nMinutes )

   LOCAL aParts, nTs, nNow, cExpected

   IF Empty( cCookie ) .OR. Empty( cSecret )

      RETURN .F.

   ENDIF

   aParts := hb_ATokens( cCookie, ":" )

   IF Len( aParts ) < 2

      RETURN .F.

   ENDIF

   nTs       := Val( aParts[ 1 ] )
   cExpected := _HixAdminSign( cSecret, nTs )

   IF cExpected != aParts[ 2 ]

      RETURN .F.

   ENDIF

   IF nMinutes > 0

      nNow := _HixNowSecs()

      IF nNow - nTs > nMinutes * 60

         RETURN .F.

      ENDIF

   ENDIF

RETURN .T.

// ============================================================
// HTML — páginas autocontenidas sin CDN
// ============================================================

STATIC FUNCTION _HixAdminCss()

   LOCAL cHtml := ''

BLOCK TO cHtml RAW
<style>
   * { margin:0;padding:0;box-sizing:border-box }
  
   body { 
      font-family:system-ui,sans-serif;
      background:#f0f4f8;
      display:flex;
      align-items:center;
      justify-content:center;
      min-height:100vh
   }
   
   .card { 
      background:#fff;
      border-radius:8px;
      box-shadow:0 2px 12px rgba(0,0,0,.1);
      padding:2rem;
      width:100%;
      max-width:380px;
      box-shadow: 5px 5px 5px lightgray;
   }
   
   h1 { 
      font-size:1.4rem;
      font-weight:700;
      color:#2d3748;
      margin-bottom:1.5rem;
      text-align:center;
   }
   
   label { 
      display:block;
      font-size:.85rem;
      color:#4a5568;
      margin-bottom:.25rem;
      margin-top:.75rem;
   }
   
   input { 
      width:100%;
      padding:.55rem .75rem;
      border:1px solid #cbd5e0;
      border-radius:5px;
      font-size:.95rem;
      outline:none;
   }
   
   input:focus { 
      border-color:#667eea;
   }
   
   button { 
      width:100%;
      margin-top:1.25rem;
      padding:.65rem;
      background:#667eea;
      color:#fff;
      border:none;
      border-radius:5px;
      font-size:1rem;
      font-weight:600;
      cursor:pointer 
   }
   
   button:hover { background:#5a67d8 }
   
   .err { 
      background:#fff5f5;
      color:#c53030;
      border:1px solid #fed7d7;
      border-radius:5px;
      padding:.6rem .75rem;
      margin-bottom:.75rem;
      font-size:.875rem
   }
   
   .logo { 
      text-align:center;
      font-size:1.8rem;
      font-weight:700;
      color:#667eea;
      margin-bottom:.25rem
   }
   
   .sub { 
      text-align:center;
      font-size:.8rem;
      color:#a0aec0;
      margin-bottom:1.5rem 
   }
</style>
ENDTEXT 

RETURN cHtml 

STATIC FUNCTION _HixAdminLoginPage( cError, cNext )
   LOCAL cErr  := ""
   LOCAL cHtml := ''
   LOCAL cCss  := _HixAdminCss() 

   hb_default( @cNext, HIX_PATH_STATUS )
   
   IF ! Empty( cError )
      cErr := "<div class='err'>" + UHtmlEncode( cError ) + "</div>"
   ENDIF
   
   BLOCK TO cHtml RAW PARAMS cCss, cErr, cNext   
<!DOCTYPE html>
<html>
<head>
   <meta charset='utf-8'>
   <title>HIX Admin</title>
   <$ cCss $>
</head>
<body>
   <div class='card'>
   <div class='logo'>HIX</div>
   <div class='sub'><$ _( 'ADMIN_PANEL_TITLE' ) $></div>
   <$ cErr $>
   <form method='POST' action='/hix-login'>
      <input type='hidden' name='next' value='<$ UHtmlEncode( cNext ) $>'>
      
      <label><$ _( 'ADMIN_LABEL_USER' ) $></label>
      <input type='text' name='user' autocomplete='username' autofocus>
      
      <label><$ _( 'ADMIN_LABEL_PASSWORD' ) $></label>
      <input type='password' name='password' autocomplete='current-password'>
      
      <button type='submit'><$ _( 'ADMIN_BTN_LOGIN' ) $></button>
   </form>
   </div>
</body>
</html>     
   ENDTEXT 

RETURN cHtml    
    

STATIC FUNCTION _HixAdminSetupPage( cError )
   LOCAL cErr := ""
   LOCAL cHtml := ''
   LOCAL cCss  := _HixAdminCss()    
   
   IF ! Empty( cError )
      cErr := "<div class='err'>" + UHtmlEncode( cError ) + "</div>"
   ENDIF
   
BLOCK TO cHtml RAW PARAMS cCss, cErr
<!DOCTYPE html>
<html>
<head>   
   <meta charset='utf-8'>
   <title>HIX Admin</title>
   <$ cCss $>
</head>
<body>
<div class='card'>
   <div class='logo'>HIX</div>
   <div class='sub'><$ _( 'ADMIN_SETUP_TITLE' ) $></div>
   <$ cErr $>
   <form method='POST' action='/hix-setup'>
   
      <label><$ _( 'ADMIN_LABEL_USER' ) $></label>
      <input type='text' name='user' autocomplete='username' autofocus>
      
      <label><$ _( 'ADMIN_LABEL_PASSWORD' ) $></label>
      <input type='password' name='password' autocomplete='new-password'>
      
      <label><$ _( 'ADMIN_LABEL_CONFIRM_PASSWORD' ) $></label>
      <input type='password' name='password2' autocomplete='new-password'>
      
      <button type='submit'><$ _( 'ADMIN_BTN_CREATE' ) $></button>
   </form>
</div>
</body>
</html>
ENDTEXT 

RETURN cHtml 