/*-----------------------------------------------------------
  File ......: hix_test_user_hooks.prg
  Author.....: Charly 9000
  Created....: 2026-07-13
  Modified...: 2026-07-13
  Version....: 1.0.0
  Description: Integrated test - USERINIT / USEREXIT hooks invoked
               by HIX_UserInit / HIX_UserExit at server startup /
               shutdown.
               Verifies:
                 1) hb_IsFunction resolves USERINIT and USEREXIT.
                 2) HIX_UserInit invokes USERINIT once.
                 3) HIX_UserExit invokes USEREXIT once.
                 4) HIX_UserInit is re-entrant across calls.
                 5) Exceptions raised inside USERINIT do not
                    propagate out of HIX_UserInit.
  Usage      : called from app.prg _TestGroups() as
               HIX_TestUserHooks_Run
  Notes      : USERINIT / USEREXIT are declared as top-level
               functions in this file so the runtime publishes
               them globally and hb_IsFunction() picks them up.
 -----------------------------------------------------------*/

#INCLUDE "hix_const.ch"
#INCLUDE "fileio.ch"

STATIC s_nInitCalls    := 0
STATIC s_nExitCalls    := 0
STATIC s_lThrowInInit  := .F.

FUNCTION HIX_TestUserHooks_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _Detection(          hCtx )
   _InvokeInit(         hCtx )
   _InvokeExit(         hCtx )
   _Reentrant(          hCtx )
   _ExceptionContained( hCtx )

   _DumpFailures( hCtx )

   RETURN hCtx

STATIC PROCEDURE _DumpFailures( hCtx )

   LOCAL hRes, nH, cOut := "=== UserHooks failures ===" + hb_eol()

   FOR EACH hRes IN hCtx[ "results" ]

      IF hRes[ "status" ] == "fail"

         cOut += hRes[ "name" ] + " | expected=" + hRes[ "exp" ] + " got=" + hRes[ "got" ] + hb_eol()

      ENDIF

   NEXT

   // OJO: hb_MemoWrit() trunca. info.txt es el log compartido de todos los
   // tests (_TLog anexa), asi que hay que anexar tambien aqui o se pierden
   // las trazas de todo lo ejecutado antes de UserHooks.
   nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )

   IF nH != NIL

      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, cOut )
      hb_vfClose( nH )

   ENDIF

   RETURN

// -------------------------------------------------------
// 1. Detection: USERINIT / USEREXIT visibles al runtime
// -------------------------------------------------------
STATIC PROCEDURE _Detection( hCtx )

   HixTU_Check( hCtx, hb_IsFunction( "USERINIT" ), ;
      "Detection: USERINIT resolvible", ".T.", ;
      iif( hb_IsFunction( "USERINIT" ), ".T.", ".F." ) )

   HixTU_Check( hCtx, hb_IsFunction( "USEREXIT" ), ;
      "Detection: USEREXIT resolvible", ".T.", ;
      iif( hb_IsFunction( "USEREXIT" ), ".T.", ".F." ) )

   RETURN

// -------------------------------------------------------
// 2. HIX_UserInit -> USERINIT
// -------------------------------------------------------
STATIC PROCEDURE _InvokeInit( hCtx )

   s_nInitCalls := 0
   HIX_UserInit()

   HixTU_Check( hCtx, s_nInitCalls == 1, ;
      "InvokeInit: HIX_UserInit ejecuta USERINIT una vez", ;
      "1", hb_ntos( s_nInitCalls ) )

   RETURN

// -------------------------------------------------------
// 3. HIX_UserExit -> USEREXIT
// -------------------------------------------------------
STATIC PROCEDURE _InvokeExit( hCtx )

   s_nExitCalls := 0
   HIX_UserExit()

   HixTU_Check( hCtx, s_nExitCalls == 1, ;
      "InvokeExit: HIX_UserExit ejecuta USEREXIT una vez", ;
      "1", hb_ntos( s_nExitCalls ) )

   RETURN

// -------------------------------------------------------
// 4. Reentrancia: 3 llamadas -> 3 ejecuciones
// -------------------------------------------------------
STATIC PROCEDURE _Reentrant( hCtx )

   s_nInitCalls := 0
   HIX_UserInit()
   HIX_UserInit()
   HIX_UserInit()

   HixTU_Check( hCtx, s_nInitCalls == 3, ;
      "Reentrant: 3 llamadas ejecutan 3 veces USERINIT", ;
      "3", hb_ntos( s_nInitCalls ) )

   RETURN

// -------------------------------------------------------
// 5. Excepción dentro de USERINIT no escapa a HIX_UserInit
// -------------------------------------------------------
STATIC PROCEDURE _ExceptionContained( hCtx )

   LOCAL lPropagated := .F.
   LOCAL oError

   s_nInitCalls    := 0
   s_lThrowInInit  := .T.

   TRY
      HIX_UserInit()
   CATCH oError
      lPropagated := .T.
   END

   s_lThrowInInit := .F.

   HixTU_Check( hCtx, ! lPropagated, ;
      "ExceptionContained: HIX_UserInit atrapa excepción de USERINIT", ;
      "no-throw", iif( lPropagated, "throw", "no-throw" ) )

   HixTU_Check( hCtx, s_nInitCalls == 1, ;
      "ExceptionContained: USERINIT corrió antes del error", ;
      "1", hb_ntos( s_nInitCalls ) )

   RETURN

// ------------------------------------------------------------------
// Funciones globales que HIX_UserInit / HIX_UserExit resuelven vía
// hb_IsFunction. Deben ser top-level (no STATIC) para que el runtime
// las publique en la tabla global de símbolos.
// ------------------------------------------------------------------
FUNCTION USERINIT()

   LOCAL oErr

   s_nInitCalls++

   IF s_lThrowInInit
      oErr := ErrorNew()
      oErr:description := "forced test error"
      Break( oErr )
   ENDIF

   RETURN NIL

FUNCTION USEREXIT()

   s_nExitCalls++

   RETURN NIL
