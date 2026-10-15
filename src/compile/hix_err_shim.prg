/*-----------------------------------------------------------
  File ......: hix_err_shim.prg
  Author.....: Charly 9000
  Created....: 2026-10-13
  Modified...: 2026-10-13
  Version....: 1.0.0
  Description: Compile-subsystem error shim. Converts the hash
               returned by HIX_CompileCode (new unified API)
               into a classic Harbour error object so legacy
               consumers (HIX_ErrorView / HIX_ErrorSysDev /
               HIX_Throw) keep working during the migration
               to the unified hash API.
  Usage      : oError := HIX_CompileErrorFromHash( hErr )
  Notes      : hErr must come from HIX_CompileCode or a per-item
               element of its "diagnostics" / "err" field.
               The whole hash is attached as oError:cargo so
               HIX_ErrorSysDev can read line / lineCode / aStack
               directly without going through the error class.
               Fase 1 of plan `.claude/plans/2026-10-12_1102
               compile_view_migration.md`.
 -----------------------------------------------------------*/

#include "hix_const.ch"
#include "error.ch"


// ============================================================
// HIX_CompileErrorFromHash — build an oError from a compile
// diagnostics hash. Preserves the hash under oError:cargo for
// downstream consumers that already know how to read it.
// ============================================================
FUNCTION HIX_CompileErrorFromHash( hErr )

   LOCAL oErr
   LOCAL cDesc, cCode, cFile, nLine, cSev

   IF ! HB_ISHASH( hErr )
      RETURN HIX_NewError( "Invalid compile hash", "Compile", 1, "ErrShim" )
   ENDIF

   cDesc := HB_HGetDef( hErr, "description", "" )
   cCode := HB_HGetDef( hErr, "code",        "" )
   cFile := HB_HGetDef( hErr, "file",        "" )
   nLine := HB_HGetDef( hErr, "line",        0  )
   cSev  := HB_HGetDef( hErr, "severity",    "" )

   oErr             := ErrorNew()
   oErr:SubSystem   := "Compile"
   oErr:SubCode     := 0
   oErr:GenCode     := EG_SYNTAX
   oErr:Severity    := iif( cSev == "warning", ES_WARNING, ES_ERROR )
   oErr:Description := cDesc
   oErr:Operation   := cCode
   oErr:FileName    := cFile
   oErr:cargo       := hErr

   IF nLine > 0
      TRY
         oErr:ProcLine := nLine
      CATCH
      END
   ENDIF

RETURN oErr
