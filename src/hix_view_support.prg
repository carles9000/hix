/*-----------------------------------------------------------
  File ......: hix_view_support.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: UView_Css / UView_Js — CSS and JS asset helpers for HIX
               Style views.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
 
FUNCTION UView_Css( cCss )

   LOCAL lHixStyle  := UConfig( "hixstyle", "enabled", .F. )
   LOCAL lDebug   := UConfig( "hixstyle", "trace",   .F. )
   LOCAL cPathCss, cRefCss
   LOCAL cFile, cCode, oError

   hb_default( @cCss, '' )

   IF lHixStyle

      cPathCss  := HIX_GetRootAbsolute()  + '/public/css/'
      cRefCss  := HIX_GetRoot() + '/public/css/'
      cRefCss  := '/public/css/'
   ELSE
      cPathCss := HIX_GetRootAbsolute() + hb_ps()
      cRefCss  := '/'

   ENDIF


   IF lDebug

      _t( '>> PathCss: ' + cPathCss )
      _t( '>> PathRef: ' + cRefCss )

   ENDIF

   cFile := UOsFileName( cPathCss +  cCss )


   IF ! FILE ( cFile )

      oError := HIX_NewError( ;
         "Loader CSS. File not Found: " + cRefCss + cCss, ;
         '*', 404, "CSS", cCss )

      HIX_Throw( oError )

      RETU NIL

   ENDIF

   RETU  '<link href="' + cRefCss + cCss + '" rel="stylesheet">'

// --------------------------------------------------------------- //

FUNCTION UView_Js( cJs )

   LOCAL lHixStyle  := UConfig( "hixstyle", "enabled", .F. )
   LOCAL lDebug   := UConfig( "hixstyle", "trace",   .F. )
   LOCAL cPathJs, cRefJs
   LOCAL cFile, cCode, oError

   hb_default( @cJs, '' )

   IF lHixStyle

      cPathJs  := HIX_GetRootAbsolute()  + '/public/js/'
      cRefJs  := '/public/js/'
   ELSE
      cPathJs := HIX_GetRootAbsolute() + hb_ps()
      cRefJs  := '/'

   ENDIF


   IF lDebug

      _t( '>> PathJs: ' + cPathJs )
      _t( '>> PathRef: ' + cRefJs )

   ENDIF

   cFile := UOsFileName( cPathJs +  cJs )


   IF ! FILE ( cFile )

      oError := HIX_NewError( ;
         "Loader JS. File not Found: " + cRefJs + cJs, ;
         '*', 404, "CSS", cJs )

      HIX_Throw( oError )

      RETU NIL

   ENDIF

   RETU '<script src="' + cRefJs + cJs + '"></script>'
// retu '<script>' + hb_memoread( cFile ) + '</script>'
