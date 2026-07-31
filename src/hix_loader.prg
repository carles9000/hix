/*-----------------------------------------------------------
  File ......: hix_loader.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-27
  Description: Dynamic PRG loader for HIX. Compiles and loads all .prg
               files found in a directory at server startup, making their
               functions/classes globally accessible.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER
#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"
#INCLUDE "hix_hrb.ch"

#INCLUDE "directry.ch"

STATIC s_aModules  := {}

// Nombres (UPPER) de funciones publicas definidas en HRBs cargados
// dinamicamente. Los usa HIX_Trace_Out para compensar el offset de
// linea que introduce el preamble de _HixPreamble() al compilar.
STATIC s_hUserFuncs := { => }

// ============================================================
// HIX_Loaders — compiles and loads all .prg files in a directory.
// Returns the number of files successfully loaded.
// ============================================================
/* directry.ch
#define F_NAME          1
#define F_SIZE          2
#define F_DATE          3
#define F_TIME          4
#define F_ATTR          5
*/
FUNCTION HIX_Loaders()

   LOCAL cRoot    := UConfig( "paths", "root", "www" )
   LOCAL cDir     :=  hb_dirbase() + cRoot + hb_ps() + "loaders" + hb_ps()

   LOCAL n, aFiles, aItem, cFile, cExt, hItem, cFilePrg, cFileHrb, aInfo, nLenModules
   LOCAL aError   := {}
   LOCAL nPendent, nIteracio, lExit, lError, nOk, nKo, nModulesKo, oError
   LOCAL cErrText

   aFiles := Directory( cDir + "*.prg" )
   s_aModules := {}

   // Compile if is necesary prg files

   FOR EACH aItem IN aFiles

      hItem  := { => }
      cFile := aItem[ F_NAME ]


      // Si ! exiteix hrb o hrb mes vell que el prg -> compilo

      cFileHrb := cDir + HB_FNameExtSet( cFile ) + '.hrb'

      aInfo := Directory( cFileHrb )

      // Si HRB no existe, compilamos prg

      IF empty( aInfo )

         IF ! HIX_LoaderCompile( cDir, cFile, @hItem )

            Aadd( s_aModules, hItem  )

         ENDIF

      ELSE
         // Si HRB es mas viejo que prg -> compilamos

         IF dtos( aInfo[ 1 ][ F_DATE ] ) + aInfo[ 1 ][ F_TIME ] < dtos( aItem[ F_DATE ] ) + aItem[ F_TIME ]

            IF  ! HIX_LoaderCompile( cDir, cFile, @hItem  )

               Aadd( s_aModules, hItem  )

            ENDIF

         ENDIF

      ENDIF


   NEXT

   // Read HRB's

   aFiles   := Directory( cDir + "*.hrb" )

   FOR EACH aItem IN aFiles

      cFile := aItem[ F_NAME ]

      hItem := {  'file' => cFile, ;
         'msg' => '', ;
         'oHrb' =>  hb_Memoread( cDir + cFile ), ;
         'pSym' =>  NIL, ;
         'process' => .F., ;
         'loaded' => .F., ;
         'oError' => NIL, ;
         'error' => .F. }

      Aadd( s_aModules, hItem )

   NEXT

   nLenModules   := len( s_aModules )

   IF len( s_aModules ) == 0

      RETU .T.

   ENDIF

   // Load into memory HRB's

   nPendent   := nLenModules
   nIteracio   := 0
   lExit       := .F.
   lError    := .F.

   WHILE ! lExit

      nIteracio++
      nOk      := 0
      nKo      := 0
      nModulesKo := 0

      FOR n := 1 TO nLenModules

         IF ! s_aModules[ n ][ 'loaded' ] .AND. ! s_aModules[ n ][ 'process' ]

            lError := .F.

            try

               s_aModules[ n ][ 'pSym' ]  := hb_hrbLoad( 0x2, s_aModules[ n ][ 'oHrb' ] )

               s_aModules[ n ][ 'loaded' ]  := .T.
               s_aModules[ n ][ 'error' ]  := .F.
               s_aModules[ n ][ 'msg' ]   := ''

               _HixRegisterUserFuncs( s_aModules[ n ][ 'pSym' ] )

            catch oError

               s_aModules[ n ][ 'error' ]  := .T.
               s_aModules[ n ][ 'msg' ]   := oError:description
               s_aModules[ n ][ 'loaded' ] := .F.
               s_aModules[ n ][ 'oError' ] := oError

               lError := .T.

               nModulesKo++

            END

         ENDIF

      NEXT

      lExit     := !( nPendent > nModulesKo .AND. ( nModulesKo > 0 ) )
      nPendent    := nModulesKo

   END

   // TEST Show Proccess...

   nOk := 0

   FOR n := 1 TO nLenModules

      IF  s_aModules[ n ][ 'loaded' ]

         nOk++

         HIX_BootLogAdd( "loaders", "file", .T., s_aModules[ n ][ 'file' ] )

      ELSE

         oError := s_aModules[ n ][ 'oError' ]

         IF oError != NIL

            cErrText := _LoaderErrText( oError, s_aModules[ n ][ 'msg' ] )
            HIX_BootLogAdd( "loaders", "file", .F., s_aModules[ n ][ 'file' ], cErrText )
         ELSE

            HIX_BootLogAdd( "loaders", "file", .F., s_aModules[ n ][ 'file' ], ;
               iif( Empty( s_aModules[ n ][ 'msg' ] ), _( "BOOT_LOADER_LOAD_FAIL_NX" ), s_aModules[ n ][ 'msg' ] ) )

         ENDIF

      ENDIF

   NEXT

RETURN nOk == nLenModules

// -------------------------------------------- //

FUNCTION HIX_GetLoaders() ; RETURN s_aModules

// -------------------------------------------- //

// Devuelve .T. si cName corresponde a una funcion publica definida en
// alguno de los HRBs cargados dinamicamente por el loader. Case-insensitive.
FUNCTION HIX_LoaderIsUserFunc( cName )

   IF cName == NIL ; RETURN .F. ; ENDIF

RETURN hb_HHasKey( s_hUserFuncs, Upper( AllTrim( cName ) ) )

// -------------------------------------------- //

// Registra en s_hUserFuncs todas las funciones publicas del HRB para
// que HIX_Trace_Out pueda compensar el offset de linea del preamble.
STATIC FUNCTION _HixRegisterUserFuncs( pHrb )

   LOCAL aFuncs, cFunc

   IF pHrb == NIL ; RETURN NIL ; ENDIF

   TRY
      aFuncs := hb_hrbGetFunList( pHrb, HB_HRB_FUNC_PUBLIC )
   CATCH
      RETURN NIL
   END

   IF ! HB_ISARRAY( aFuncs ) ; RETURN NIL ; ENDIF

   FOR EACH cFunc IN aFuncs
      s_hUserFuncs[ Upper( cFunc ) ] := .T.
   NEXT

RETURN NIL

// -------------------------------------------- //

STATIC FUNCTION HIX_LoaderCompile( cDir, cFile, hItem )

   LOCAL oHrb, oErr, cFileNoExt

   hItem := {  'file' => cFile, ;
      'msg' => '', ;
      'oHrb' =>  '', ;
      'pSym' =>  NIL, ;
      'process' => .T., ;
      'loaded' => .F., ;
      'oError' => NIL, ;
      'error' => .F. }

   TRY

      oHrb := HIX_CompileFile( cDir + cFile )

   CATCH oErr

      hItem[ 'oError' ] := oErr

      RETURN .F.

   END

   IF Empty( oHrb  )           // Fals positiu

      oErr := ErrorNew()

      oErr:description := _( "BOOT_LOADER_FALSE_POS" )
      // oErr:operation := ''

      hItem[ 'oError' ] := oErr

      RETURN .F.

   ENDIF

   // Si compilamos el prg, salvamos el hrb en disco

   cFileNoExt := HB_FNameExtSet( cFile )

   hb_memowrit( cDir + cFileNoExt + '.hrb', oHrb )

   RETU .T.

// -------------------------------------------- //

STATIC FUNCTION oError2Msg( oError )

   RETU   oError:subsystem + "/" + ;
      HIX_ErrDescCode( oError:genCode ) + ;
      "(" + LTRIM( STR( oError:genCode ) ) + ") " + ;
      LTRIM( STR( oError:subcode ) )

// -------------------------------------------- //

// Devuelve un texto de error legible priorizando description; si no,
// usa msg guardado o compone un texto con subsystem/genCode.

STATIC FUNCTION _LoaderErrText( oError, cMsg )

   LOCAL cDesc, cOp

   IF oError != NIL

      cDesc := hb_CStr( oError:description )
      cOp   := hb_CStr( oError:operation )

      IF ! Empty( cDesc )

         RETURN cDesc + iif( Empty( cOp ), "", ", " + cOp )

      ENDIF

      RETURN oError2Msg( oError )

   ENDIF

   IF ! Empty( cMsg )

      RETURN cMsg

   ENDIF

RETURN _( "BOOT_LOADER_LOAD_FAIL" )

// -------------------------------------------- //

STATIC FUNC HIX_ErrDescCode( nCode )

   LOCAL cI := NIL

   IF nCode > 0 .AND. nCode <= 41

      cI := { "ARG", "BOUND", "STROVERFLOW", "NUMOVERFLOW", "ZERODIV", "NUMERR", "SYNTAX", "COMPLEXITY", ; // 1,  2,  3,  4,  5,  6,  7,  8
         NIL, NIL, "MEM", "NOFUNC", "NOMETHOD", "NOVAR", "NOALIAS", "NOVARMETHOD", ; // 9, 10, 11, 12, 13, 14, 15, 16
         "BADALIAS", "DUPALIAS", NIL, "CREATE", "OPEN", "CLOSE", "READ", "WRITE", ; // 17, 18, 19, 20, 21, 22, 23, 24
         "PRINT", NIL, NIL, NIL, NIL, "UNSUPPORTED", "LIMIT", "CORRUPTION", ; // 25, 26 - 29, 30, 31, 32
         "DATATYPE", "DATAWIDTH", "NOTABLE", "NOORDER", "SHARED", "UNLOCKED", "READONLY", "APPENDLOCK", ; // 33, 34, 35, 36, 37, 38, 39, 40
         "LOCK"    }[ nCode ]                                                                                            // 41

   ENDIF

   RETU IF( cI == NIL, "", "EG_" + cI )

// -------------------------------------------- //


// User hook llamado desde THixServer:Start() tras cargar los loaders.
// Debe ser NO bloqueante: cualquier bucle o socket sin timeout aquí
// retrasa el arranque del servidor.

FUNCTION HIX_UserInit()

   LOCAL oError

   IF hb_IsFunction( "USERINIT" )

      _t( ">> Execute init()" )

      TRY

         Do( "USERINIT" )
      CATCH oError
         _t( ">> Error: " + oError:description )

      END

   ENDIF

RETURN NIL

// -------------------------------------------------- //

// User hook llamado desde THixServer:Stop() antes de cerrar sockets.
// Debe ser NO bloqueante: si se cuelga bloquea el shutdown del server.
FUNCTION HIX_UserExit()

   LOCAL oError

   IF hb_IsFunction( "USEREXIT" )

      _t( ">> Execute user exit()" )

      TRY

         Do( "USEREXIT" )
      CATCH oError
         _t( ">> Error: " + oError:description )

      END

   ENDIF

RETURN NIL
