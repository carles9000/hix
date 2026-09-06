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

STATIC s_hMtx  := NIL
STATIC s_cFile := "dbg.log"

FUNCTION HIX_Dbg( cMsg )

   LOCAL cLine, hFile

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
   hb_vfErase( s_cFile )
   hb_mutexUnlock( s_hMtx )

RETURN NIL
