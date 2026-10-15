/*-----------------------------------------------------------
  File ......: hix_preamble.prg
  Author.....: Charly 9000
  Created....: 2026-10-13
  Modified...: 2026-10-13
  Version....: 1.0.0
  Description: HIX compile preamble. Rules prepended to the user
               PRG at compile time so TRY/CATCH/FINALLY, BLOCK,
               ? / ?? and Throw() are available without the user
               having to include anything.
  Usage      : cCode := HIX_CompilePreamble() + cUserCode
               nSkip := HIX_CompilePreambleLines()  // offset for line maps
  Notes      : Moved from hix_prepro.prg in Fase 2 of plan
               `.claude/plans/2026-10-12_1102 compile_view_migration.md`.
               Core of the compile subsystem — the view engine has
               its own, separate _HixViewPrgPreamble (do not merge).
               If you add or remove lines in HIX_CompilePreamble(),
               HIX_CompilePreambleLines() recounts automatically.
 -----------------------------------------------------------*/

#include "hix_const.ch"


// ============================================================
// HIX_CompilePreamble — preprocessor rules prepended to user code.
// Single compile pass (.T.) — the Harbour compiler resolves
// hbclass.ch and other includes without double-preprocessing.
// ============================================================
FUNCTION HIX_CompilePreamble()
RETURN ;
      "#xcommand TRY  => BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }" + hb_eol() + ;
      "#xcommand CATCH [<!oErr!>] => RECOVER [USING <oErr>] <-oErr->" + hb_eol() + ;
      "#xcommand FINALLY => ALWAYS" + hb_eol() + ;
      "#xtranslate Throw( <oErr> ) => ( Eval( ErrorBlock(), <oErr> ), Break( <oErr> ) )" + hb_eol() + ;
      "#xcommand BLOCK <into:TO,INTO> <o> [RAW] [ PARAMS [<v1>] [,<vn>] ] => " + ;
      "#pragma __cstream|<o>+= HIX_Block( %s [,<(v1)>][+','+<(vn)>] [, @<v1>][, @<vn>] )" + hb_eol() + ;
      "#xcommand BLOCK <into:TO,INTO> <o> [RAW] => #pragma __cstream|<o> += %s" + hb_eol() + ;
      "#xcommand ?  [<explist,...>] => UEcho( '<br>' [,<explist>] )" + hb_eol() + ;
      "#xcommand ?? [<explist,...>] => UEcho( [<explist>] )" + hb_eol()


// ============================================================
// HIX_CompilePreambleLines — count of preamble lines, for compensating
// the line-number offset the preamble introduces in compiled
// code. Dynamic count on first use; STATIC cache is safe because
// HIX_CompilePreamble() returns a compile-time constant.
// ============================================================
FUNCTION HIX_CompilePreambleLines()

   STATIC snLines := -1
   LOCAL cPre, i, n

   IF snLines == -1

      cPre := HIX_CompilePreamble()
      n := 0

      FOR i := 1 TO Len( cPre )

         IF SubStr( cPre, i, 1 ) == Chr( 10 )

            n++

         ENDIF

      NEXT

      snLines := n

   ENDIF

RETURN snLines
