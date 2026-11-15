/*-----------------------------------------------------------
  File ......: hix_dbg.prg
  Author.....: Charly 9000
  Created....: 2026-08-27
  Description: Dedicated diagnostic trace file with its own
               mutex, independent from the main HIX logger. Use
               to instrument code paths without contending on
               the main logger mutex or polluting hix.log.
  Usage      : HIX_Dbg( "any string" ) — appends a timestamped
               line to `dbg.log` in the process CWD. Thread-safe.
 -----------------------------------------------------------*/

#include "fileio.ch"

STATIC s_hMtx     := NIL
STATIC s_cFile    := "dbg.log"
STATIC s_lEnabled := .F.                    // default OFF — zero cost in hot paths

FUNCTION HIX_Dbg( cMsg )

   LOCAL cLine, hFile

   //  Fast-path: one boolean check when disabled. NEVER touch mutex/disk
   //  unless someone explicitly enabled tracing. This keeps HIX_Dbg calls
   //  scattered in hot paths (pool Acquire/Release, connection Close, etc.)
   //  effectively free in production and benchmarks.
   IF ! s_lEnabled
      RETU NIL
   ENDIF

   IF s_hMtx == NIL
      s_hMtx := hb_mutexCreate()
   ENDIF

   cLine := hb_TSToStr( hb_DateTime(), .T. ) + " [tid=" + ;
      hb_ntos( hb_threadId( hb_threadSelf() ) ) + "] " + ;
      hb_defaultValue( cMsg, "" ) + hb_eol()

   hb_mutexLock( s_hMtx )

   hFile := hb_vfOpen( s_cFile, FO_CREAT + FO_WRITE + FO_SHARED )

   IF hFile != NIL

      hb_vfSeek( hFile, 0, FS_END )
      hb_vfWrite( hFile, cLine )
      hb_vfClose( hFile )

   ENDIF

   hb_mutexUnlock( s_hMtx )

RETURN NIL

FUNCTION HIX_DbgSetFile( cFile )

   IF s_hMtx == NIL
      s_hMtx := hb_mutexCreate()
   ENDIF

   hb_mutexLock( s_hMtx )
   s_cFile := hb_defaultValue( cFile, "dbg.log" )
   hb_mutexUnlock( s_hMtx )

RETURN NIL

FUNCTION HIX_DbgReset()

   IF s_hMtx == NIL
      s_hMtx := hb_mutexCreate()
   ENDIF

   hb_mutexLock( s_hMtx )
   HIX_SafeErase( s_cFile )
   hb_mutexUnlock( s_hMtx )

RETURN NIL


//  Enable/disable runtime tracing. Default is OFF: HIX_Dbg() early-returns
//  without touching mutex or disk. Turn ON only in tests or when actively
//  diagnosing. Callers that want traces (functional tests, ad-hoc debug)
//  should call HIX_DbgEnable() explicitly.
FUNCTION HIX_DbgEnable( lOn )
   LOCAL lPrev := s_lEnabled
   s_lEnabled := hb_defaultValue( lOn, .T. )
RETURN lPrev

FUNCTION HIX_DbgEnabled()
RETURN s_lEnabled
