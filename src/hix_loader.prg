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

// [A3.4.5] Mutex unico que protege s_aModules y s_hUserFuncs.
// Creado single-threaded en INIT PROCEDURE antes de cualquier worker.
STATIC s_mtxLoader := NIL

INIT PROCEDURE _HixLoaderInit()
   s_mtxLoader := hb_mutexCreate()
RETURN

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

   LOCAL cRoot     := UConfig( "paths", "root", "www" )
   LOCAL cDir      := hb_dirbase() + cRoot + hb_ps() + "loaders" + hb_ps()
   LOCAL cCacheDir := hb_dirbase() + ".cached" + hb_ps() + "loaders" + hb_ps()
   LOCAL lCacheDisk := UConfig( "hixstyle", "cache_disk", .T. )

   LOCAL n, aFiles, aItem, cFile, cExt, hItem, cFilePrg, cFileHrb, aInfo, nLenModules
   LOCAL aError   := {}
   LOCAL nPendent, nIteracio, lExit, lError, nOk, nKo, nModulesKo, oError
   LOCAL cErrText, hErr, hCmp
   // [A3.4.5] Trabajar con arrays locales; swap atomico al final para
   // que workers concurrentes vean siempre un estado coherente.
   LOCAL aWork     := {}
   LOCAL hNewFuncs := { => }

   // Cache dir: alineado con views (.cached/views). Solo .hrb, sin sidecar.
   // Solo creamos el directorio si vamos a persistir HRBs.
   IF lCacheDisk
      IF ! hb_DirExists( hb_StrShrink( cCacheDir, 1 ) )
         hb_DirBuild( hb_StrShrink( cCacheDir, 1 ) )
      ENDIF
   ENDIF

   // Limpieza one-shot de artefactos legacy en www/loaders/ (migracion del
   // esquema anterior donde se dejaban .hrb y .hrb.md5 junto al .prg).
   // Se hace siempre: limpia residuos independientemente del modo cache.
   _HixLoaderPurgeLegacy( cDir )

   IF lCacheDisk

      aFiles := Directory( cDir + "*.prg" )

      // Compile if is necesary prg files

      FOR EACH aItem IN aFiles

         hItem  := { => }
         cFile := aItem[ F_NAME ]


         // Si ! exiteix hrb o hrb mes vell que el prg -> compilo

         cFileHrb := cCacheDir + HB_FNameExtSet( cFile ) + '.hrb'

         aInfo := Directory( cFileHrb )

         // Si HRB no existe, compilamos prg

         IF empty( aInfo )

            IF ! HIX_LoaderCompile( cDir, cCacheDir, cFile, @hItem, lCacheDisk )

               Aadd( aWork, hItem  )

            ENDIF

         ELSE
            // Si HRB es mas viejo que prg -> compilamos (mtime-only, como views)

            IF dtos( aInfo[ 1 ][ F_DATE ] ) + aInfo[ 1 ][ F_TIME ] < dtos( aItem[ F_DATE ] ) + aItem[ F_TIME ]

               IF  ! HIX_LoaderCompile( cDir, cCacheDir, cFile, @hItem, lCacheDisk )

                  Aadd( aWork, hItem  )

               ENDIF

            ENDIF

         ENDIF


      NEXT

      // Read HRB's desde el cache

      aFiles   := Directory( cCacheDir + "*.hrb" )

      FOR EACH aItem IN aFiles

         cFile := aItem[ F_NAME ]

         hItem := {  'file' => cFile, ;
            'msg' => '', ;
            'oHrb' =>  hb_Memoread( cCacheDir + cFile ), ;
            'pSym' =>  NIL, ;
            'process' => .F., ;
            'loaded' => .F., ;
            'oError' => NIL, ;
            'error' => .F. }

         Aadd( aWork, hItem )

      NEXT

   ELSE

      // Modo sin cache en disco: compilar cada .prg en memoria y rellenar
      // aWork con los bytes HRB directamente — no se toca .cached/loaders/.

      aFiles := Directory( cDir + "*.prg" )

      FOR EACH aItem IN aFiles

         cFile := aItem[ F_NAME ]

         hItem := {  'file'    => HB_FNameExtSet( cFile ) + '.hrb', ;
            'msg'     => '', ;
            'oHrb'    => '', ;
            'pSym'    => NIL, ;
            'process' => .F., ;
            'loaded'  => .F., ;
            'oError'  => NIL, ;
            'hErr'    => NIL, ;
            'error'   => .F. }

         hCmp := HIX_CompileCodeFromFile( cDir + cFile )

         IF hCmp[ "ok" ]
            hItem[ 'oHrb' ] := hCmp[ "hrb" ]
         ELSE
            hItem[ 'hErr' ]   := hCmp[ "err" ]
            hItem[ 'oError' ] := HIX_CompileErrorFromHash( hCmp[ "err" ] )
            hItem[ 'error' ]  := .T.
            hItem[ 'process' ] := .T.
         ENDIF

         Aadd( aWork, hItem )

      NEXT

   ENDIF

   nLenModules   := len( aWork )

   IF len( aWork ) == 0

      // [A3.4.5] Swap atomico incluso para el caso vacio
      hb_mutexLock( s_mtxLoader )
      s_aModules   := aWork
      s_hUserFuncs := hNewFuncs
      hb_mutexUnlock( s_mtxLoader )

      HIX_BootLogAdd( "loaders", "mode", .T., iif( lCacheDisk, "cache_disk", "in-memory" ) )

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

      // [A3.4.7] Limite de seguridad: en una cadena lineal de N modulos se
      // necesitan como mucho N iteraciones. Si se supera, hay ciclo irresolvable.
      IF nIteracio > nLenModules + 1
         lw( "HIX_Loaders: dep circular detectada tras " + hb_NToS( nIteracio ) + " iteraciones — abortando" )
         EXIT
      ENDIF

      FOR n := 1 TO nLenModules

         IF ! aWork[ n ][ 'loaded' ] .AND. ! aWork[ n ][ 'process' ]

            lError := .F.

            try

               aWork[ n ][ 'pSym' ]  := hb_hrbLoad( 0x2, aWork[ n ][ 'oHrb' ] )

               aWork[ n ][ 'loaded' ]  := .T.
               aWork[ n ][ 'error' ]  := .F.
               aWork[ n ][ 'msg' ]   := ''

               // [A3.4.5] Recoger en hash local (thread-local, sin lock)
               _HixCollectUserFuncs( aWork[ n ][ 'pSym' ], hNewFuncs )

            catch oError

               aWork[ n ][ 'error' ]  := .T.
               aWork[ n ][ 'msg' ]   := oError:description
               aWork[ n ][ 'loaded' ] := .F.
               aWork[ n ][ 'oError' ] := oError

               lError := .T.

               nModulesKo++

            END

         ENDIF

      NEXT

      lExit     := !( nPendent > nModulesKo .AND. ( nModulesKo > 0 ) )
      nPendent    := nModulesKo

   END

   // [A3.4.7] Diagnosticar modulos que quedaron sin cargar (posible ciclo)
   FOR n := 1 TO nLenModules
      IF ! aWork[ n ][ 'loaded' ] .AND. ! aWork[ n ][ 'process' ] .AND. Empty( aWork[ n ][ 'oError' ] )
         lw( "HIX_Loaders: posible dep circular en: " + aWork[ n ][ 'file' ] )
      ENDIF
   NEXT

   // [A3.4.5] Swap atomico: los workers HTTP ven siempre un estado coherente.
   // El lock solo dura la doble asignacion, no la carga/compilacion.
   hb_mutexLock( s_mtxLoader )
   s_aModules   := aWork
   s_hUserFuncs := hNewFuncs
   hb_mutexUnlock( s_mtxLoader )

   HIX_BootLogAdd( "loaders", "mode", .T., iif( lCacheDisk, "cache_disk", "in-memory" ) )

   // TEST Show Proccess...

   nOk := 0

   FOR n := 1 TO nLenModules

      IF  s_aModules[ n ][ 'loaded' ]

         nOk++

         HIX_BootLogAdd( "loaders", "file", .T., s_aModules[ n ][ 'file' ] )

      ELSE

         oError := s_aModules[ n ][ 'oError' ]
         hErr   := iif( hb_HHasKey( s_aModules[ n ], 'hErr' ), s_aModules[ n ][ 'hErr' ], NIL )

         IF HB_ISHASH( hErr )
            // Compile failure — pass structured diagnostic hash so bootlog can
            // show line/code; downstream formatter handles the hash shape.
            HIX_BootLogAdd( "loaders", "file", .F., s_aModules[ n ][ 'file' ], hErr )
         ELSEIF oError != NIL

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

// [A3.4.5] Devuelve snapshot inmutable (copia shallow) bajo lock breve.
// El llamador recibe su propia copia y no puede corromper s_aModules.
FUNCTION HIX_GetLoaders()

   LOCAL aSnap

   hb_mutexLock( s_mtxLoader )
   aSnap := AClone( s_aModules )
   hb_mutexUnlock( s_mtxLoader )

RETURN aSnap

// -------------------------------------------- //

// Devuelve .T. si cName corresponde a una funcion publica definida en
// alguno de los HRBs cargados dinamicamente por el loader. Case-insensitive.
// [A3.4.5] Lock de lectura para s_hUserFuncs (workers HTTP lo llaman concurrentemente).
FUNCTION HIX_LoaderIsUserFunc( cName )

   LOCAL lRes

   IF cName == NIL ; RETURN .F. ; ENDIF

   hb_mutexLock( s_mtxLoader )
   lRes := hb_HHasKey( s_hUserFuncs, Upper( AllTrim( cName ) ) )
   hb_mutexUnlock( s_mtxLoader )

RETURN lRes

// -------------------------------------------- //

// [A3.4.5] Rellena hFuncs (hash local caller-owned) con las funciones publicas
// del HRB. Se llama desde HIX_Loaders() antes del swap atomico — no necesita
// lock porque hFuncs es local al hilo que ejecuta HIX_Loaders().
STATIC FUNCTION _HixCollectUserFuncs( pHrb, hFuncs )

   LOCAL aFuncs, cFunc

   IF pHrb == NIL ; RETURN NIL ; ENDIF

   TRY
      aFuncs := hb_hrbGetFunList( pHrb, HB_HRB_FUNC_PUBLIC )
   CATCH
      RETURN NIL
   END

   IF ! HB_ISARRAY( aFuncs ) ; RETURN NIL ; ENDIF

   FOR EACH cFunc IN aFuncs
      hFuncs[ Upper( cFunc ) ] := .T.
   NEXT

RETURN NIL

// -------------------------------------------- //

// Borra artefactos legacy (.hrb y .hrb.md5) que el esquema anterior dejaba
// dentro de www/loaders/. Se ejecuta una vez al arrancar; solo toca ficheros
// generados — no hay riesgo de perder trabajo del usuario.
STATIC FUNCTION _HixLoaderPurgeLegacy( cDir )

   LOCAL aList, aItem, nCount := 0

   aList := Directory( cDir + "*.hrb" )
   FOR EACH aItem IN aList
      IF FErase( cDir + aItem[ F_NAME ] ) == 0
         nCount++
      ENDIF
   NEXT

   aList := Directory( cDir + "*.hrb.md5" )
   FOR EACH aItem IN aList
      IF FErase( cDir + aItem[ F_NAME ] ) == 0
         nCount++
      ENDIF
   NEXT

   IF nCount > 0
      l( "Loaders: purgados " + hb_NToS( nCount ) + ;
         " artefactos legacy de " + cDir )
   ENDIF

RETURN nCount

// -------------------------------------------- //

STATIC FUNCTION HIX_LoaderCompile( cDir, cCacheDir, cFile, hItem, lCacheDisk )

   LOCAL oHrb, oErr, cFileNoExt, hCmp

   hb_default( @lCacheDisk, .T. )

   hItem := {  'file' => cFile, ;
      'msg' => '', ;
      'oHrb' =>  '', ;
      'pSym' =>  NIL, ;
      'process' => .T., ;
      'loaded' => .F., ;
      'oError' => NIL, ;
      'hErr'   => NIL, ;
      'error' => .F. }

   hCmp := HIX_CompileCodeFromFile( cDir + cFile )

   IF ! hCmp[ "ok" ]
      hItem[ 'hErr' ]   := hCmp[ "err" ]
      hItem[ 'oError' ] := HIX_CompileErrorFromHash( hCmp[ "err" ] )
      RETURN .F.
   ENDIF

   oHrb := hCmp[ "hrb" ]

   IF Empty( oHrb )           // Defensive: compile ok but no bytes
      oErr := ErrorNew()
      oErr:description := _( "BOOT_LOADER_FALSE_POS" )
      hItem[ 'oError' ] := oErr
      RETURN .F.
   ENDIF

   cFileNoExt := HB_FNameExtSet( cFile )

   IF lCacheDisk
      // Guardamos el .hrb en .cached/loaders/ (misma convencion que views).
      // Invalidacion por mtime: no sidecar, no hash.
      hb_memowrit( cCacheDir + cFileNoExt + '.hrb', oHrb )
   ENDIF

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
