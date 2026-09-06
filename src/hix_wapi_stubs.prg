/*-----------------------------------------------------------
  File ......: hix_wapi_stubs.prg
  Author.....: Charly 9000
  Created....: 2026-08-23
  Modified...: 2026-08-23
  Version....: 1.0.0
  Description: Cross-platform stubs for symbols normally provided
               by Windows-linked contribs (hbwin, hbcurl, hbhpdf).
               Compiled only on non-Windows targets so the HIX
               library links on Linux/Unix without those contribs.
               On Windows the real contrib symbols win.
  Usage      : Linked automatically via hix_server.hbp. Callers use
               the same signatures on both platforms — on Linux
               they get placeholder values instead of the real ones.
  Notes      : Match contrib signatures exactly. Keep behaviour
               safe and side-effect free — logging goes to stdout.
 -----------------------------------------------------------*/

PROCEDURE Hix_WapiStubs_Dummy()
RETURN

#ifndef __PLATFORM__WINDOWS

FUNCTION WAPI_OutputDebugString( cMessage )

   IF HB_ISSTRING( cMessage )
      OutStd( cMessage )
   ENDIF

RETURN NIL


FUNCTION WAPI_ShellExecute( nHwnd, cVerb, cFile, cParams, cDir, nShow )

   LOCAL cTarget := iif( HB_ISSTRING( cFile ), cFile, "" )
   LOCAL cOpener

   HB_SYMBOL_UNUSED( nHwnd )
   HB_SYMBOL_UNUSED( cVerb )
   HB_SYMBOL_UNUSED( cParams )
   HB_SYMBOL_UNUSED( cDir )
   HB_SYMBOL_UNUSED( nShow )

   IF Empty( cTarget )
      RETURN 0
   ENDIF

#ifdef __PLATFORM__DARWIN
   cOpener := "open"
#else
   cOpener := "xdg-open"
#endif

   // Fire and forget: redirect stdio and background so we don't block
   // the caller or spam the console if no display is available.
   hb_run( cOpener + " " + cTarget + " >/dev/null 2>&1 &" )

RETURN 0

// Note: Curl_version / HPDF_VERSION_TEXT are NOT stubbed here on
// purpose. If we defined them, the static linker would resolve
// HB_FUN_CURL_VERSION from libhix_server.a and never pull the real
// one from libhbcurl.a. Callers must probe with Type() and fall back.

#endif
