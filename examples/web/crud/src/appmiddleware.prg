/*-----------------------------------------------------------
  File ......: appmiddleware.prg
  Author.....: Charly 9000
  Created....: 2026-05-25
  Modified...: 2026-05-25
  Version....: 1.0.0
  Description: Data-driven middleware loader.
               Reads middleware.json, compiles each listed .prg
               to HRB at startup and keeps handles loaded for
               the lifetime of the process (BIND_LOCAL).
  Usage      : AppMiddlewareLoad( "www/middlewares/middleware.json" )
               // Then AppConfig("setup","auth","...") works as usual.
 -----------------------------------------------------------*/

#include "hix_const.ch"
#include "hix_hrb.ch"

STATIC s_aHandles := {=>}

FUNCTION AppMiddlewareLoad( cJsonFile )
   LOCAL hJson, aLoad, cDir, cFile, oHrb, pHandle, oErr

   IF ! AppConfigLoad( cJsonFile )
      OutStd( "AppMiddlewareLoad: failed to read " + cJsonFile + hb_eol() )
      RETURN .F.
   ENDIF

   hJson := AppConfigRaw()
   aLoad := hb_HGetDef( hJson, "load", {} )

   IF Empty( aLoad )
      RETURN .T.
   ENDIF

   cDir := hb_FNameDir( cJsonFile )

   FOR EACH cFile IN aLoad

      oHrb := HIX_CompileFile( cDir + cFile )

      IF Empty( oHrb )
         OutStd( "AppMiddlewareLoad: compile failed -> " + cFile + hb_eol() )
         LOOP
      ENDIF

      TRY
         pHandle := hb_hrbLoad( HB_HRB_BIND_LOCAL, oHrb )
      CATCH oErr
         OutStd( "AppMiddlewareLoad: load failed -> " + cFile + ": " + oErr:description + hb_eol() )
         LOOP
      END

      IF pHandle != NIL
         s_aHandles[ Lower( cFile ) ] := pHandle
         OutStd( "AppMiddlewareLoad: loaded -> " + cFile + hb_eol() )
      ENDIF

   NEXT

RETURN .T.

FUNCTION AppMiddlewareUnload( cFile )
   LOCAL cKey := Lower( cFile )

   IF ! hb_HHasKey( s_aHandles, cKey )
      RETURN .F.
   ENDIF

   hb_hrbUnload( s_aHandles[ cKey ] )
   hb_HDel( s_aHandles, cKey )

RETURN .T.
