/*-----------------------------------------------------------
  File ......: appconfig.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: App config loader — reads a JSON file once at
               startup and exposes values via AppConfig().
  Usage      : AppConfigLoad( "www/config/keys.json" )
               AppConfig( "auth", "session_user_key" )
 -----------------------------------------------------------*/

STATIC s_hConfig     := NIL
STATIC s_hFlatConfig := NIL

FUNCTION AppConfigLoad( cFile )
   LOCAL cJson := hb_MemoRead( cFile )
   IF Empty( cJson )
      RETURN .F.
   ENDIF
   hb_jsonDecode( cJson, @s_hConfig )
RETURN ValType( s_hConfig ) == "H"

FUNCTION AppConfigRaw()
RETURN s_hConfig

FUNCTION AppConfigFlatLoad( cFile )
   LOCAL cJson := hb_MemoRead( cFile )
   IF Empty( cJson )
      RETURN .F.
   ENDIF
   hb_jsonDecode( cJson, @s_hFlatConfig )
RETURN ValType( s_hFlatConfig ) == "H"

FUNCTION AppConfigGet( cKey, xDef )
   hb_default( @xDef, NIL )
   IF s_hFlatConfig == NIL
      RETURN xDef
   ENDIF
RETURN hb_HGetDef( s_hFlatConfig, cKey, xDef )

FUNCTION AppConfig( cSection, cGroup, cKey, xDef )
   LOCAL hCursor
   hb_default( @xDef, NIL )
   IF s_hConfig == NIL
      RETURN xDef
   ENDIF
   hCursor := hb_HGetDef( s_hConfig, cSection, NIL )
   IF ValType( hCursor ) != "H"
      RETURN xDef
   ENDIF
   hCursor := hb_HGetDef( hCursor, cGroup, NIL )
   IF ValType( hCursor ) != "H"
      RETURN xDef
   ENDIF
RETURN hb_HGetDef( hCursor, cKey, xDef )
