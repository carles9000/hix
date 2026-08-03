/*-----------------------------------------------------------
  File ......: hix_dispatcher.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-24
  Description: THixDispatcher — resolves HTTP request to a physical file
               and dispatches by extension (.html, .prg, .hrb).
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_DISPATCHER

#INCLUDE "hix_const.ch"
#INCLUDE "hix_logger.ch"
#INCLUDE "hbhrb.ch"

STATIC s_hAbortMx  := NIL
STATIC s_hAbortMap := NIL

CLASS THixDispatcher

   DATA cRoot        INIT ""
   DATA nExecTimeout INIT 30000   // ms; 0 = sin limite
   DATA cDefaultPage INIT "index.html"   // pagina por defecto en directorio
   DATA lExecPrg     INIT .T.            // .F. = bloquea ejecucion .prg/.hrb
   DATA aDenyDirs    INIT {}             // subdirs bloqueadas (relativas al root)
   DATA aAllowDirs   INIT NIL            // NIL=sin whitelist; array de hashes {dir,exec}

   METHOD New( cRoot )
   METHOD Dispatch( oReq )
   METHOD DenyDir(   cDir )
   METHOD AllowDir(  cDir, lAllowExec )
   METHOD CheckPath( cSpec )   // NIL=bloqueado, string=path fisico resuelto
   METHOD GetACL()             // hash con la configuracion ACL actual

   METHOD ExecutePrg(  cPath )
   METHOD ExecuteHrb(  cPath )
   METHOD ExecuteHtml( cPath )
   METHOD ExecuteView( cPath )
   METHOD ExecuteFile( cPath )

ENDCLASS

// ------------------------------------------------------------
METHOD New( cRoot ) CLASS THixDispatcher

   ::cRoot := hb_DirSepToOS( AllTrim( hb_defaultValue( cRoot, "public" ) ) )

   DO WHILE Right( ::cRoot, 1 ) == hb_ps()

      ::cRoot := Left( ::cRoot, Len( ::cRoot ) - 1 )

   ENDDO

RETURN Self

// ------------------------------------------------------------
METHOD DenyDir( cDir ) CLASS THixDispatcher

   LOCAL cNorm := Lower( AllTrim( hb_DirSepToOS( cDir ) ) )

   DO WHILE Right( cNorm, 1 ) == hb_ps()

      cNorm := Left( cNorm, Len( cNorm ) - 1 )

   ENDDO

   IF ! Empty( cNorm ) .AND. AScan( ::aDenyDirs, {| x | x == cNorm } ) == 0

      AAdd( ::aDenyDirs, cNorm )

   ENDIF

RETURN Self

// ------------------------------------------------------------
// Whitelist de carpetas accesibles por URL directa. Con lAllowExec=.T. la
// carpeta ejecuta PRG/HRB incluso si dispatch_mode="static" desactiva el flag
// global lExecPrg. Llamadas sucesivas hacen upgrade del flag exec (nunca
// downgrade): AllowDir("x") + AllowDir("x",.T.) queda con exec=.T.
METHOD AllowDir( cDir, lAllowExec ) CLASS THixDispatcher

   LOCAL cNorm := Lower( AllTrim( hb_DirSepToOS( cDir ) ) )
   LOCAL nPos

   hb_default( @lAllowExec, .F. )

   DO WHILE Right( cNorm, 1 ) == hb_ps()

      cNorm := Left( cNorm, Len( cNorm ) - 1 )

   ENDDO

   IF Empty( cNorm )

      RETURN Self

   ENDIF

   IF ::aAllowDirs == NIL

      ::aAllowDirs := {}

   ENDIF

   nPos := AScan( ::aAllowDirs, {| h | h[ "dir" ] == cNorm } )

   IF nPos == 0

      AAdd( ::aAllowDirs, { "dir" => cNorm, "exec" => lAllowExec } )
   ELSE
      ::aAllowDirs[ nPos ][ "exec" ] := ::aAllowDirs[ nPos ][ "exec" ] .OR. lAllowExec

   ENDIF

RETURN Self

// ------------------------------------------------------------
// Comprueba si cSpec esta permitido segun el ACL del dispatcher.
// Retorna el path fisico resuelto, o NIL si esta bloqueado.
METHOD CheckPath( cSpec ) CLASS THixDispatcher
RETURN _HixResolveFilePath( Self, cSpec )

// ------------------------------------------------------------
// Retorna un hash con la configuracion ACL actual del dispatcher.
METHOD GetACL() CLASS THixDispatcher

   LOCAL aAllow := NIL, hEntry

   IF ::aAllowDirs != NIL

      aAllow := {}

      FOR EACH hEntry IN ::aAllowDirs

         AAdd( aAllow, { "dir" => hEntry[ "dir" ], "exec" => hEntry[ "exec" ] } )

      NEXT

   ENDIF

RETURN { ;
      "root"       => ::cRoot,                                    ;
      "exec_prg"   => ::lExecPrg,                                 ;
      "deny_dirs"  => ::aDenyDirs,                                ;
      "allow_dirs" => iif( aAllow == NIL, "(all)", aAllow )       ;
      }

// ------------------------------------------------------------
/* Aqui podem fer control dels zombies, que son programes que s'han executat
   mes del temps permes i poden haber acabat o encara estar funcionant.

Tipo A — Zombie temporal:
  HRB lento pero finito. Tardó 45s, timeout era 30s.
  Morirá solo. Consume CPU y memoria temporalmente.
  → No es peligroso si hay pocos

Tipo B — Zombie eterno:
  HRB con loop infinito. Nunca morirá.
  Consume 1 thread del OS + stack HVM para siempre.
  → Es el peligroso. Acumulación garantizada.
*/

#DEFINE HIX_ZOMBIE_WARN      5    // avisar en logs
#DEFINE HIX_ZOMBIE_THROTTLE 10   // rechazar nuevas ejecuciones PRG/HRB
#DEFINE HIX_ZOMBIE_CRITICAL 20   // rechazar TODAS las requests dinámicas
// ------------------------------------------------------------
METHOD Dispatch( oReq ) CLASS THixDispatcher

   LOCAL cPath, cPhysical, cExt, cResult, cMime, cEtag, nZ, lIsIndex, lDirExists
   LOCAL hClass, nAt, cFileName, cDir, cIndexBase
   LOCAL tBefore, nMs, cCompressed
   LOCAL cRelDir, cEntry, nI

   cPath := oReq:cPath

   cPath := StrTran( cPath, "\", "/" )

   DO WHILE "//" $ cPath

      cPath := StrTran( cPath, "//", "/" )

   ENDDO

   IF Empty( cPath ) .OR. Left( cPath, 1 ) != "/"

      cPath := "/" + cPath

   ENDIF

   IF ".." $ cPath

      lw( _( "DISP_PATH_TRAVERSAL", cPath ) )
      HIX_HttpError( oReq, 403 )
      RETURN Self

   ENDIF

   IF _HixHixstylePublicOn()

      cPath := _HixApplyHixstylePrefix( cPath )

   ENDIF

   cPhysical := ::cRoot + hb_DirSepToOS( cPath )

   // Directorio relativo (sin la barra inicial de cPath) para checks ACL.
   // Normalizar separadores a OS: la URL trae "/" pero aDenyDirs/aAllowDirs
   // guardan entradas con hb_ps() (backslash en Windows).
   cRelDir := Lower( hb_DirSepToOS( hb_FNameDir( SubStr( cPath, 2 ) ) ) )

   DO WHILE Right( cRelDir, 1 ) == hb_ps() .OR. Right( cRelDir, 1 ) == "/"

      cRelDir := Left( cRelDir, Len( cRelDir ) - 1 )

   ENDDO

   // Check DenyDirs: blacklist explicita (se comprueba antes que whitelist)

   IF ! Empty( ::aDenyDirs )

      FOR nI := 1 TO Len( ::aDenyDirs )

         cEntry := ::aDenyDirs[ nI ]

         IF cRelDir == cEntry .OR. Left( cRelDir, Len( cEntry ) + 1 ) == cEntry + hb_ps()

            lw( "Dispatch: directorio denegado [" + cPath + "]" )
            HIX_HttpError( oReq, 403 )
            RETURN Self

         ENDIF

      NEXT

   ENDIF

   // Check AllowDirs (whitelist): si esta activa, solo pasan carpetas listadas.
   // Excepciones: raiz "/" (para el hello page e index) y prefijos hixstyle ya
   // reescritos a "public/*".

   IF ::aAllowDirs != NIL .AND. ! Empty( cRelDir )

      IF ! _HixWhitelistMatch( ::aAllowDirs, cRelDir )

         lw( "Dispatch: directorio no en whitelist [" + cPath + "]" )
         HIX_HttpError( oReq, 403 )
         RETURN Self

      ENDIF

   ENDIF

   lIsIndex   := .F.
   cIndexBase := NIL
   cDir       := iif( Right( cPhysical, 1 ) == hb_ps(), Left( cPhysical, Len( cPhysical ) - 1 ), cPhysical )
   lDirExists := hb_DirExists( cDir )

   IF lDirExists

      IF Right( cPath, 1 ) != "/"

         // Redirigir a la URL con barra final para que los paths relativos funcionen
         oReq:Respond( "", 301, "html", { "Location" => cPath + "/" } )
         RETURN Self

      ENDIF

      IF Right( cPhysical, 1 ) != hb_ps()

         cPhysical += hb_ps()

      ENDIF

      cIndexBase := Left( cPhysical, Len( cPhysical ) - 1 )  // dir sin trailing sep
      cPhysical  += ::cDefaultPage
      lIsIndex   := .T.
      
   ELSEIF Right( cPath, 1 ) == "/"

      IF Right( cPhysical, 1 ) != hb_ps()

         cPhysical += hb_ps()

      ENDIF

      cIndexBase := Left( cPhysical, Len( cPhysical ) - 1 )  // dir sin trailing sep
      cPhysical  += ::cDefaultPage
      lIsIndex   := .T.

   ENDIF

   IF lIsIndex .AND. ! hb_FileExists( cPhysical )

      cPhysical := hb_FNameDir( cPhysical ) + "index.prg"

   ENDIF

   IF lIsIndex .AND. ! hb_FileExists( cPhysical )

      IF cPath == "/"

         oReq:Respond( HIX_HelloPage(), 200, "html" )
         
      ELSE
      
         HIX_HttpError( oReq, 404 )

      ENDIF

      RETURN Self

   ENDIF

   // Detectar notacion metodo@clase.prg
   hClass    := NIL
   cFileName := hb_FNameNameExt( cPhysical )
   nAt       := At( "@", cFileName )

   IF nAt > 0

      cDir   := hb_FNameDir( cPhysical )
      hClass := { => }
      hClass[ "method" ] := Lower( Left( cFileName, nAt - 1 ) )
      hClass[ "class" ]  := hb_FNameName( SubStr( cFileName, nAt + 1 ) )
      cPhysical        := cDir + SubStr( cFileName, nAt + 1 )

   ENDIF

   IF ! hb_FileExists( cPhysical )

      IF _HixHixstylePublicOn()

         cDir := _HixTryPublicFallback( ::cRoot, cPath )

         IF cDir != NIL

            cPhysical := cDir

         ENDIF

      ENDIF

   ENDIF

   IF ! hb_FileExists( cPhysical )

      ld( "Fichero no encontrado: " + cPhysical )
      HIX_HttpError( oReq, 404 )
      RETURN Self

   ENDIF

   cExt := Lower( hb_FNameExt( cPhysical ) )



   nZ := HIX_ZombieCount()

   DO CASE

      CASE nZ >= HIX_ZOMBIE_CRITICAL
         lw( _( "DISP_ZOMBIE_CRITICAL", nZ ) )
         HIX_HttpError( oReq, 503 )
         RETURN ''

      CASE nZ >= HIX_ZOMBIE_THROTTLE
// Solo rechazar ejecuciones dinámicas, servir estáticos normal

      IF cExt == ".prg" .OR. cExt == ".hrb"

         lw( "THROTTLE: " + hb_NToS( nZ ) + " zombies. Rechazando PRG/HRB." )
         HIX_HttpError( oReq, 503, _( 'ERR_TOO_MANY_PENDING' ) )
         RETURN ''

         ENDIF

      CASE nZ >= HIX_ZOMBIE_WARN
         lw( "WARN: " + hb_NToS( nZ ) + " zombies activos." )

   ENDCASE

// -----------------------------------------------------------------

   cMime := 'html'

   DO CASE

      CASE cExt == ".prg"

      IF ! ::lExecPrg .AND. ! _HixExecAllowedForRelDir( ::aAllowDirs, cRelDir )

         HIX_HttpError( oReq, 403 )
         RETURN Self

         ENDIF

         cResult := ::ExecutePrg( cPhysical, oReq, hClass )

      CASE cExt == ".hrb"

      IF ! ::lExecPrg .AND. ! _HixExecAllowedForRelDir( ::aAllowDirs, cRelDir )

         HIX_HttpError( oReq, 403 )
         RETURN Self

         ENDIF

         cResult := ::ExecuteHrb( cPhysical )

      CASE cExt == ".html" .OR. cExt == ".htm"

         // tBefore := hb_DateTime()
         tBefore := hb_Milliseconds()
         cResult := ::ExecuteHtml( cPhysical )
         // nMs     := Int( ( hb_DateTime() - tBefore ) * 86400000 )
         nMs     := hb_Milliseconds() - tBefore
         HIX_MetricTimingStat( nMs, oReq:cPath )

      CASE cExt == ".view"

         tBefore := hb_Milliseconds()

         cResult := ::ExecuteView( cPath  )           // ex. /views/index.view, no www/views/index.view
         nMs     := hb_Milliseconds() - tBefore
         HIX_MetricTimingStat( nMs, oReq:cPath )

      OTHERWISE
         cMime := _HixMimeFromExt( cExt )
         cEtag := _HixFileETag( cPhysical )

      IF oReq:Header( "if-none-match" ) == cEtag

         ld( "304 Not Modified: " + cPhysical )
         oReq:Respond( "", 304, cMime, { "ETag" => cEtag } )
         RETURN Self

         ENDIF

         // tBefore := hb_DateTime()
         tBefore := hb_Milliseconds()

      IF hb_FSize( cPhysical ) > HIX_CHUNK_THRESHOLD

         ld( "Chunked [" + cExt + "]: " + cPhysical )

         IF _HixCanGzip( cMime, oReq )

            cResult     := hb_MemoRead( cPhysical )
            cCompressed := HIX_GzipCompress( cResult )

            IF cCompressed != NIL

               ld( "Gzip large [" + cExt + "]: " + cPhysical )
               oReq:Respond( cCompressed, 200, cMime, { ;
                  "ETag"             => cEtag,             ;
                  "Cache-Control"    => _HixCacheControl(), ;
                  "Content-Encoding" => "gzip",             ;
                  "Vary"             => "Accept-Encoding" } )
            ELSE
               oReq:RespondStart( cMime, 200, { "ETag" => cEtag, "Cache-Control" => _HixCacheControl() } )
               _HixStreamFile( oReq, cPhysical )
               oReq:RespondEnd()

            ENDIF

         ELSE
            oReq:RespondStart( cMime, 200, { "ETag" => cEtag, "Cache-Control" => _HixCacheControl() } )
            _HixStreamFile( oReq, cPhysical )
            oReq:RespondEnd()

         ENDIF

      ELSE
         cResult := ::ExecuteFile( cPhysical )
         ld( "Dispatch OK [" + cExt + "]: " + cPhysical )
         oReq:Respond( cResult, 200, cMime, { ;
            "ETag"          => cEtag,               ;
            "Cache-Control" => _HixCacheControl() } )

         ENDIF

         // nMs := Int( ( hb_DateTime() - tBefore ) * 86400000 )
         nMs     := hb_Milliseconds() - tBefore
         HIX_MetricTimingStat( nMs, oReq:cPath )

         RETURN Self

   ENDCASE

   ld( "Dispatch OK [" + cExt + "]: " + cPhysical )

   IF ! Empty( cResult )

      HIX_Echo( cResult )

   ENDIF

   IF oReq:lStreaming

      // IF ! Empty( oReq:cEchoBuffer )
      oReq:RespondChunk( oReq:cEchoBuffer )
      // ENDIF
      oReq:RespondEnd()
      
   ELSEIF ! oReq:lResponded
   
      oReq:Respond( HIX_EchoGet(), HIX_GetStatus(), HIX_GetMime() )

   ENDIF

   HIX_EchoClear()

RETURN Self

// ------------------------------------------------------------
// Compila el .prg en memoria y lo ejecuta con timeout.
// Error de compilacion: responde 500 directamente (no escapa al worker).
// Error de runtime: propaga via HIX_Throw al worker HTTP.
// ------------------------------------------------------------
METHOD ExecutePrg( cPath, oReq, hClass ) CLASS THixDispatcher

   LOCAL oHrb
   LOCAL oError, cHtml

   TRY

      oHrb := HIX_CompileFile( cPath )

   CATCH oError

      HIX_Throw( oError )

   END

   // Puede que no de error per no se genera hrb

   IF empty( oHrb )

      HIX_Throw( HIX_NewError( ;
         "Compile error ", ;
         "Dispatcher", 500, "Compiler" ) )
      RETU ''

   ENDIF


   cHtml := _HixExecWithTimeout( oHrb, ::nExecTimeout, cPath, hClass, oReq )

RETURN cHtml

// ------------------------------------------------------------
METHOD ExecuteHrb( cPath ) CLASS THixDispatcher

   LOCAL oHrb

   l( "ExecuteHrb: " + cPath )
   oHrb := hb_MemoRead( cPath )

RETURN _HixExecWithTimeout( oHrb, ::nExecTimeout, cPath )

// ------------------------------------------------------------
METHOD ExecuteHtml( cPath ) CLASS THixDispatcher

   LOCAL oView, cHtml, lCache, lDebug, oError

   IF ! hb_FileExists( cPath )

      RETURN ""

   ENDIF

   lCache := UConfig( "hixstyle", "cache_disk", .T. )
   lDebug := UConfig( "hixstyle", "trace",      .F. )

   TRY

      oView                  := HIX_View_Viewer():New()
      oView:lCache           := lCache
      oView:lDebug           := lDebug
      oView:lStrictMode      := .T.
      oView:llSaveTranspiled := .F.
      oView:SetPathView( hb_FNameDir( cPath ) )
      oView:SetPrg( hb_FNameNameExt( cPath ) )
      cHtml := oView:Render()
      
   CATCH oError
   
      HIX_EchoClear()
      HIX_Throw( oError )
      FINALLY
      HIX_CloseDbfAreas()

   END

RETURN cHtml

// ------------------------------------------------------------

METHOD ExecuteView( cPath ) CLASS THixDispatcher

   LOCAL cHtml := ""

   TRY

      cHtml := UView( cPath )
      
   FINALLY
   
      HIX_CloseDbfAreas()

   END

RETURN cHtml

// ------------------------------------------------------------
METHOD ExecuteFile( cPath ) CLASS THixDispatcher

   LOCAL cMask := '.view.html'
   LOCAL cUrlPath

   l( "ExecuteFile: " + cPath )



   IF Lower( hb_FNameExt( cPath ) ) == ".html"

      IF Substr( cPath, 1, len( ::cRoot ) ) == ::cRoot

         cUrlPath := StrTran( SubStr( cPath, Len( ::cRoot ) + 1 ), hb_ps(), "/" )

         IF Left( cUrlPath, 1 ) != "/" ; cUrlPath := "/" + cUrlPath ; ENDIF

         RETURN UView( cUrlPath )

      ENDIF

   ENDIF

RETURN hb_MemoRead( cPath )

// ============================================================
// Helpers internos
// ============================================================



// ------------------------------------------------------------
// Ejecuta bExec en un sub-hilo con limite de nMs milisegundos.
// nMs <= 0 -> ejecucion directa sin limite.
// Timeout:  HIX_Throw con "Dispatcher"/504.
// Error en bExec: re-lanza via HIX_Throw.
// ------------------------------------------------------------
STATIC FUNCTION _HixExecWithTimeout( oHrb, nMs, cPath, hClass, oReq )

   LOCAL hMutex, aShared, tStart, hThread, nChildId

   hb_default( @cPath, "" )

   // Vincular oReq al hilo padre para que HIX_EchoGet/GetMime/GetStatus lean
   // del objeto compartido tras el mutex (tanto en path directa como con timeout)
   HIX_SetRequest( oReq )
   HIX_EchoClear()



   IF nMs <= 0

      IF hClass == NIL

         RETURN _HixRunHrb( oHrb, cPath )
      ELSE
         RETURN _HixRunHrbClass( oHrb, cPath, hClass )

      ENDIF

   ENDIF

   // Path con timeout: hijo ejecuta en hilo separado, padre espera por mutex.
   // Estado (buffer/mime/status) vive en oReq — referencia compartida.

   hMutex  := hb_mutexCreate()
   aShared := { NIL, NIL, NIL }     // { return_value, oError, zombie_id }
   tStart  := hb_DateTime()

   // Bloquear ANTES de lanzar el hilo para evitar notificacion perdida
   hb_mutexLock( hMutex )
   hThread  := hb_threadStart( {|| _HixThreadExec( oHrb, hMutex, aShared, hClass, oReq, cPath ) } )
   nChildId := hb_threadId( hThread )
   _HixAbortMapSet( nChildId, .F. )

   IF ! hb_mutexSubscribe( hMutex, nMs / 1000 )

      // Timeout: senalizar abort al hijo, registrar zombie, lanzar 504
      _HixAbortMapSet( nChildId, .T. )
      aShared[ 3 ] := HIX_ZombieAdd( cPath, nMs, tStart )
      hb_mutexUnlock( hMutex )
      lw( "Timeout [" + hb_NToS( nMs ) + "ms]: " + cPath )
      HIX_Throw( HIX_NewError( ;
         "Execution timeout after " + hb_NToS( nMs ) + "ms", ;
         "Dispatcher", 504, "Execute" ) )

   ENDIF

   // Hijo termino normalmente: limpiar abort map y continuar
   hb_mutexUnlock( hMutex )
   _HixAbortMapDel( nChildId )

   IF aShared[ 2 ] != NIL

      HIX_Throw( aShared[ 2 ] )

   ENDIF

RETURN UStr( aShared[ 1 ] )

// ------------------------------------------------------------
// Hilo de ejecucion: captura resultado o error en aShared
// y notifica al padre via hMutex.
// Debe ser funcion nombrada: los codeblocks no admiten
// BEGIN/RECOVER ni LOCAL.
// ------------------------------------------------------------
STATIC FUNCTION _HixThreadExec( oHrb, hMutex, aShared, hClass, oReq, cPath )

   LOCAL xR, oE

   HIX_SetRequest( oReq )

   TRY

      IF hClass == NIL

         xR := _HixRunHrb( oHrb, cPath )
      ELSE

         xR := _HixRunHrbClass( oHrb, cPath, hClass )

      ENDIF

   CATCH oE

   END

   // Limpiar propia entrada del abort map antes de notificar al padre
   _HixAbortMapDel( hb_threadId() )

   hb_mutexLock( hMutex )
   aShared[ 1 ] := xR
   aShared[ 2 ] := oE
   hb_mutexNotify( hMutex )
   hb_mutexUnlock( hMutex )
   HIX_ZombieDead( aShared[ 3 ] )

RETURN NIL

// Carga, ejecuta y descarga un HRB.
// Fase 1 (load): error = HRB corrupto/vacio -> retorna "" sin relanzar.
// Fase 2 (exec): error = runtime -> relanza via HIX_Throw al worker HTTP.
STATIC FUNCTION _HixRunHrb( oHrb, cPath  )

   LOCAL pHandle, cHtml, oError, oMyErr, bPrevErr

   pHandle  := NIL
   cHtml    := ""
   oError     := NIL
   bPrevErr := NIL

   TRY

      pHandle := hb_hrbLoad( HB_HRB_BIND_LOCAL, oHrb )

   CATCH oError
   
      _d( oError )
      
      oMyErr := HIX_NewError( ;
         oError:description, ;
         "_HixRunHrb", 500, oError:operation, cPath )
         
      _HixCopyErrorLine( oError, oMyErr )

      HIX_Throw( oMyErr )

   END


   TRY

      bPrevErr := ErrorBlock( {| oErr | _HixCaptureRuntimeLine( oErr ), Break( oErr ) } )

      cHtml := hb_HrbDo( pHandle )
      cHtml := UStr( cHtml )

   CATCH oError
   
      _d( oError )

      oMyErr := HIX_NewError( ;
         oError:description, ;
         "_HixRunHrb", 500, oError:operation, cPath )
      _HixCopyErrorLine( oError, oMyErr )

      HIX_Throw( oMyErr )

      FINALLY

      IF bPrevErr != NIL

         ErrorBlock( bPrevErr )

      ENDIF

      IF !Empty( pHandle )

         hb_hrbUnload( pHandle )
         pHandle := nil

      ENDIF

      HIX_CloseDbfAreas()

   END

RETURN cHtml

// ------------------------------------------------------------
// _HixCaptureRuntimeLine — se instala como ErrorBlock durante
// la ejecucion del HRB. Captura ProcLine() del stack en el
// instante del throw (antes del unwind) y lo guarda en
// oErr:cargo["line"] para que sobreviva a HIX_NewError.
// Resta el offset del preamble para dar la linea real del PRG.
// ------------------------------------------------------------
STATIC FUNCTION _HixCaptureRuntimeLine( oErr )

   LOCAL nLine := 0
   LOCAL nLvl, nCandidate, cName
   LOCAL hCargo

   FOR nLvl := 1 TO 15

      cName := ProcName( nLvl )
      nCandidate := ProcLine( nLvl )

      IF nCandidate > 0 .AND. !( "_HIXCAPTURERUNTIMELINE" $ Upper( cName ) ) ;
            .AND. !( "_HIXRUNHRB" $ Upper( cName ) ) ;
            .AND. !( "(B)" $ Upper( cName ) )

         nLine := nCandidate
         EXIT

      ENDIF

   NEXT

   IF nLine > 0

      nLine -= HIX_PreambleLines()

      IF nLine < 1

         nLine := 0

      ENDIF

   ENDIF

   IF nLine > 0

      hCargo := iif( ValType( oErr:cargo ) == "H", oErr:cargo, { => } )
      hCargo[ "line" ] := nLine
      oErr:cargo := hCargo

   ENDIF

RETURN NIL

// ------------------------------------------------------------
// _HixCopyErrorLine — propaga la linea del error original al nuevo
// error envuelto. Prueba :ProcLine y :Line con TRY, y siempre deja
// una copia en cargo["line"] para que el renderer errorsys la lea
// sin depender de si la clase de error expone el metodo.
// ------------------------------------------------------------
STATIC FUNCTION _HixCopyErrorLine( oSrc, oDst )

   LOCAL nLine := 0
   LOCAL hCargo

   IF ValType( oSrc:cargo ) == "H" .AND. hb_HHasKey( oSrc:cargo, "line" ) ;
         .AND. ValType( oSrc:cargo[ "line" ] ) == "N"

      nLine := oSrc:cargo[ "line" ]

   ENDIF

   IF nLine == 0

      TRY

         IF ValType( oSrc:ProcLine ) == "N"

            nLine := oSrc:ProcLine

         ENDIF

      CATCH

      END

   ENDIF

   IF nLine == 0

      TRY

         IF ValType( oSrc:Line ) == "N"

            nLine := oSrc:Line

         ENDIF

      CATCH

      END

   ENDIF

   IF nLine > 0

      TRY

         oDst:ProcLine := nLine
         
      CATCH

      END

      hCargo := iif( ValType( oDst:cargo ) == "H", oDst:cargo, { => } )
      hCargo[ "line" ] := nLine
      oDst:cargo := hCargo

   ENDIF

RETURN NIL

// ------------------------------------------------------------
// Ejecuta un HRB en modo clase: Main(cClass) devuelve la clase,
// se instancia con :New(oReq) y se llama el metodo indicado.
// Convención PRG: FUNCTION Main(cClass) ; RETURN MiClase
// ------------------------------------------------------------
STATIC FUNCTION _HixRunHrbClass( oHrb, cPath, hClass )

   LOCAL pHandle, cHtml, oError, o, lAuth, oClass, lIsMethod

   pHandle     := NIL
   cHtml       := ""


   // Load HRB module...

   TRY

      pHandle := hb_hrbLoad( HB_HRB_BIND_LOCAL, oHrb )

   CATCH oError
   
      // oError:cFilename := cPath
      HIX_Throw( oError )

   END

   // Load Class

   TRY

      oClass := hb_hrbDo( pHandle, hClass[ 'class' ] )

   CATCH oError
      
      HIX_Throw( oError )

   END


   IF valtype( oClass ) != 'O'

      IF !Empty( pHandle )

         hb_hrbUnload( pHandle )
         pHandle := nil

      ENDIF

      RETU ''

   ENDIF


   // Load methods...

   lIsMethod := __objHasMethod( oClass, 'NEW' )

   IF ! lIsMethod

      HIX_Throw( HIX_NewError( ;
         "No exist method constructor new()", ;
         "_HixRunHrbClass", 504, "Compiler", cPath ) )

   ENDIF

   o := __ObjSendMsg( oClass, 'NEW' )

   // Xec if exist data lAuthorization

   IF __objHasData( o, "AUTHORIZATION" )

      lAuth := o:lAuthorization
      
   ELSE
   
      lAuth := .T.

   ENDIF

   // Load method execute

   lIsMethod := __objHasMethod( oClass, hClass[ 'method' ] )


   IF  lIsMethod

      IF lAuth

         TRY

            cHtml := __ObjSendMsg( oClass, hClass[ 'method' ] )

            cHtml := UStr( cHtml )
         CATCH oError
            // oError:cFilename := cPath
            HIX_Throw( oError )
            FINALLY
            HIX_CloseDbfAreas()

         END

         IF __objHasMethod( oClass, 'DESTROY' )

            __ObjSendMsg( oClass, 'DESTROY' )

         ENDIF

         IF __objHasMethod( oClass, 'END' )

            __ObjSendMsg( oClass, 'END' )

         ENDIF

      ELSE

         RETU ''

      ENDIF

   ENDIF

   // Unload from memory (nil instances first so GC does not access unloaded HRB)

   o      := NIL
   oClass := NIL
   hb_hrbUnload( pHandle )
   pHandle := NIL

   IF ! lIsMethod

      HIX_Throw( HIX_NewError( ;
         "No exist method " + hClass[ 'method' ], ;
         "_HixRunHrbClass", 0, "Execute", cPath ) )

   ENDIF

RETURN cHtml

// ------------------------------------------------------------
// HIX_PrgRoute — crea un codeblock para registrar rutas que
// apuntan a ficheros .prg con notacion metodo@clase.prg
// Uso: oRouter:Add("GET", "/path", HIX_PrgRoute(oDisp, "controllers/update@product.prg"))
// ------------------------------------------------------------
FUNCTION HIX_PrgRoute( oDisp, cSpec )

   LOCAL hClass := NIL
   LOCAL nAt, cFileName, cDir, cFile
   LOCAL lClass := .F.

   cFileName := hb_FNameNameExt( cSpec )
   nAt       := At( "@", cFileName )

   IF nAt > 0

      cDir   := hb_FNameDir( cSpec )
      hClass := { => }
      hClass[ "method" ] := Lower( Left( cFileName, nAt - 1 ) )
      hClass[ "class" ]  := hb_FNameName( SubStr( cFileName, nAt + 1 ) )
      cFile  := cDir + SubStr( cFileName, nAt + 1 )
      lClass := .T.
   ELSE
      cFile := cSpec

   ENDIF

RETURN {| oCtx | oDisp:ExecutePrg( cFile, oCtx:oReq, hClass ) }

// ------------------------------------------------------------
// Returns Cache-Control header value based on environment.
// dev → no-store (browser never caches, changes visible immediately)
// prod → public, max-age=3600
STATIC FUNCTION _HixCacheControl()
RETURN iif( UConfig( "app", "env", "dev" ) == "dev", "no-store", "public, max-age=3600" )

STATIC FUNCTION _HixCanGzip( cMime, oReq )
RETURN UConfig( "server", "gzip", .F. ) .AND. ;
      HIX_GzipShouldCompress( cMime ) .AND. ;
      "gzip" $ Lower( oReq:Header( "accept-encoding", "" ) )

STATIC FUNCTION _HixFileETag( cPath )

   LOCAL tsModif, nSize, cTag

   nSize := hb_vfSize( cPath )
   hb_vfTimeGet( cPath, @tsModif )

   cTag := hb_NToS( nSize ) + "-" + hb_TSToStr( tsModif, .T. )
   // cTag := hb_MD5( cTag )

RETURN '"' + cTag + '"'

// ------------------------------------------------------------
// _HixStreamFile — sirve un fichero en trozos chunked sin cargarlo en RAM
// ------------------------------------------------------------
STATIC FUNCTION _HixStreamFile( oReq, cPath )

   LOCAL nHandle, cBuf, nRead

   nHandle := FOpen( cPath )

   IF nHandle < 0 ; RETURN NIL ; ENDIF

   DO WHILE .T.

      cBuf  := Space( HIX_CHUNK_SIZE )
      nRead := FRead( nHandle, @cBuf, HIX_CHUNK_SIZE )

      IF nRead <= 0 ; EXIT ; ENDIF

      oReq:RespondChunk( Left( cBuf, nRead ) )

   ENDDO

   FClose( nHandle )

RETURN NIL

FUNCTION HIX_HelloPage()

   LOCAL cHtml := ''
   LOCAL cVersion :=  HIX_Version()

   BLOCK TO cHtml RAW PARAMS cVersion
<!DOCTYPE html>
<html>
<head>
   <meta charset='utf-8'>
   <title>HIX</title>  
   <link rel='shortcut icon' type='image/png' href='https://raw.githubusercontent.com/carles9000/hix/refs/heads/main/resources/images/hix.ico' />
   <link href="https://fonts.googleapis.com/css2?family=BBH+Sans+Bartle&family=Saira+Stencil+One&display=swap" rel="stylesheet">  
    

   <meta name="description" content="Code in xBase, deploy on the web"> 
   <meta name="keywords" content="HIX, httpd2, harbour, web">
   <meta name="Author" content="Carles Aubia Floresvi">
   <meta name="Generator" content="HIX">	

   <meta property="og:type" content="software">
   <meta property="og:url" content="https://github.com/carles9000/hix">
   <meta property="og:site_name" content="HIX">
   <meta property="og:title" content="HIX">
   <meta property="og:description" content="Code in xBase, deploy on the web">
   <meta property="og:image" content="https://raw.githubusercontent.com/carles9000/hix/refs/heads/main/resources/images/logo240.png">    
  
   <style>
       html, body {
         margin: 0;
         padding: 0;
         height: 100%;      
         font-family: 'Saira Stencil One', sans-serif;
       }
       .container {
         display: flex;
         justify-content: center;
         align-items: center;
         height: 100vh;
         background-color: #f0f0f0;
       }
       .content {
         display: flex;
         flex-direction: column;
         align-items: center;         
       }
       .row {
         display: flex;
         align-items: center;
         gap: 20px;
       }
       .logo {
         width: 100px;
         height: 100px;                     
         background-size: cover;
         background-repeat: no-repeat;
       }
       
       .logo img {
         width:100px;
       }
       
       .text {
         font-size: 4.2em;
         color: #333;	  
       }
       
       .subtitle {
         font-family: system-ui;
         color: gray;
         font-size: 1.5rem;
       }
      span { font-size: 2rem; }   
   </style>
</head>
<body>
  <div class="container">
    <div class="content">
      <div class="row">
        <div class="logo">           
           <img src='https://raw.githubusercontent.com/carles9000/hix/refs/heads/main/resources/images/logo240.png' alt='Logo HIX'>                
        </div>
        <div class="text">HIX <span>2.0</span></div>
      </div>
      <div class="subtitle">Server is running...</div>
    </div>
  </div>
</body>
</html> 
   ENDTEXT


   RETU cHtml


STATIC FUNCTION _HixMimeFromExt( cExt )

   DO CASE

      CASE cExt == ".css"                      ; RETURN "css"
      CASE cExt == ".js"                       ; RETURN "js"
      CASE cExt == ".json"                     ; RETURN "json"
      CASE cExt == ".txt"                      ; RETURN "text"
      CASE cExt == ".png"                      ; RETURN "image/png"
      CASE cExt == ".jpg" .OR. cExt == ".jpeg" ; RETURN "image/jpeg"
      CASE cExt == ".gif"                      ; RETURN "image/gif"
      CASE cExt == ".svg"                      ; RETURN "image/svg+xml"
      CASE cExt == ".ico"                      ; RETURN "image/x-icon"
      CASE cExt == ".pdf"                      ; RETURN "application/pdf"
      CASE cExt == ".woff"                     ; RETURN "font/woff"
      CASE cExt == ".woff2"                    ; RETURN "font/woff2"

   ENDCASE

RETURN "application/octet-stream"

// ============================================================
// HIX_IsFilePath — .T. si cAction tiene extension de fichero conocida
// ============================================================
FUNCTION HIX_IsFilePath( cAction )

   LOCAL cExt := Lower( hb_FNameExt( AllTrim( cAction ) ) )

RETURN cExt == ".prg"  .OR. cExt == ".hrb"  .OR. ;
      cExt == ".html" .OR. cExt == ".htm"  .OR. ;
      cExt == ".jpg"  .OR. cExt == ".jpeg" .OR. ;
      cExt == ".png"  .OR. cExt == ".gif"  .OR. ;
      cExt == ".svg"  .OR. cExt == ".css"  .OR. ;
      cExt == ".js"   .OR. cExt == ".pdf"

// ============================================================
// HIX_FileRoute — codeblock de accion para un fichero fisico.
//
// cSpec puede ser:
// "views/hello.prg"         -> ExecutePrg en subcarpeta
// "widget.hrb"              -> ExecuteHrb (binario precompilado)
// "home.html"               -> ExecuteHtml + Respond
// "logo.jpg"                -> ExecuteFile + Respond con MIME correcto
// "get@customer.prg"        -> ExecutePrg con notacion metodo@clase
// "custo/get@customer.prg"  -> idem en subcarpeta
//
// El dispatcher recibe la ruta relativa a su cRoot.
// Uso interno: llamado por THixServer:AddRoute cuando detecta extension.
// ============================================================
FUNCTION HIX_FileRoute( oDisp, cSpec )

   LOCAL hClass, cFileName, nAt, cDir, cFile, cExt

   cFileName := hb_FNameNameExt( cSpec )
   nAt       := At( "@", cFileName )
   hClass    := NIL
   cFile     := cSpec

   IF nAt > 0

      cDir             := hb_FNameDir( cSpec )
      hClass           := { => }
      hClass[ "method" ] := Lower( Left( cFileName, nAt - 1 ) )
      hClass[ "class" ]  := hb_FNameName( SubStr( cFileName, nAt + 1 ) )
      cFile            := cDir + SubStr( cFileName, nAt + 1 )

   ENDIF

   cExt := Lower( hb_FNameExt( cFile ) )

   DO CASE

      CASE cExt == ".prg" .OR. cExt == ".hrb"
         RETURN {| oReq | _HixExecFileAction( oDisp, cFile, hClass, oReq, .T. ) }
      CASE cExt == ".html" .OR. cExt == ".htm"
         RETURN {| oReq | _HixServeFileStatic( oDisp, cFile, "html", oReq, .T. ) }
      OTHERWISE
         RETURN {| oReq | _HixServeFileStatic( oDisp, cFile, _HixMimeFromExt( cExt ), oReq, .T. ) }

   ENDCASE

RETURN NIL

// Resuelve cSpec a path fisico validando sandbox y ACL del dispatcher.
// Retorna el path absoluto, o NIL si debe bloquearse (403).
// Paths absolutos (X:... / /...) saltan el sandbox: responsabilidad del dev.
STATIC FUNCTION _HixResolveFilePath( oDisp, cSpec, lSkipDeny )

   LOCAL cPhysical, cNormRoot, cRelative, cRelDir, cEntry, nI, cAlt
   LOCAL lPublic

   IF lSkipDeny == NIL ; lSkipDeny := .F. ; ENDIF

   lPublic := _HixHixstylePublicOn()

   // Detectar path absoluto: drive letter o slash inicial

   IF ( Len( cSpec ) >= 2 .AND. SubStr( cSpec, 2, 1 ) == ":" ) .OR. ;
         Left( cSpec, 1 ) == "/" .OR. Left( cSpec, 1 ) == "\"

      RETURN hb_PathNormalize( hb_DirSepToOS( cSpec ) )

   ENDIF

   // Hixstyle public: reescribir prefijo de assets (/images, /css, ...)

   IF lPublic

      cSpec := _HixApplyHixstylePrefix( "/" + cSpec )

      IF Left( cSpec, 1 ) == "/"

         cSpec := SubStr( cSpec, 2 )

      ENDIF

   ENDIF

   // Construir y normalizar path relativo al root
   cPhysical := hb_PathNormalize( hb_DirSepToOS( oDisp:cRoot + hb_ps() + cSpec ) )
   cNormRoot := hb_PathNormalize( hb_DirSepToOS( oDisp:cRoot ) )

   IF Right( cNormRoot, 1 ) != hb_ps()

      cNormRoot += hb_ps()

   ENDIF

   // Check traversal: el path debe quedar dentro del root

   IF Lower( Left( cPhysical, Len( cNormRoot ) ) ) != Lower( cNormRoot )

      lw( "FileRoute: path traversal bloqueado [" + cSpec + "]" )
      RETURN NIL

   ENDIF

   // Directorio relativo del fichero (lowercase, sin sep final)
   cRelative := SubStr( cPhysical, Len( cNormRoot ) + 1 )
   cRelDir   := Lower( hb_FNameDir( cRelative ) )

   DO WHILE Right( cRelDir, 1 ) == hb_ps() .OR. Right( cRelDir, 1 ) == "/"

      cRelDir := Left( cRelDir, Len( cRelDir ) - 1 )

   ENDDO

   // Check DenyDirs: bloquear si coincide o es subdir de una entrada denegada

   IF ! lSkipDeny

      FOR nI := 1 TO Len( oDisp:aDenyDirs )

         cEntry := oDisp:aDenyDirs[ nI ]

         IF cRelDir == cEntry .OR. Left( cRelDir, Len( cEntry ) + 1 ) == cEntry + hb_ps()

            lw( "FileRoute: directorio denegado [" + cSpec + "]" )
            RETURN NIL

         ENDIF

      NEXT

   ENDIF

   // Check AllowDirs (whitelist): si esta activa solo pasan los directorios listados.
   // lSkipDeny=.T. (llamadas desde rutas registradas via HIX_FileRoute) bypasea
   // tambien la whitelist para que AddRouteGet(...,"controllers/x.prg") funcione
   // aunque "controllers" no este permitido para acceso URL directo.

   IF ! lSkipDeny .AND. oDisp:aAllowDirs != NIL

      IF _HixWhitelistMatch( oDisp:aAllowDirs, cRelDir )

         IF lPublic .AND. ! hb_FileExists( cPhysical )

            cAlt := _HixTryPublicFallback( oDisp:cRoot, "/" + cSpec )

            IF cAlt != NIL ; RETURN cAlt ; ENDIF

         ENDIF

         RETURN cPhysical

      ENDIF

      lw( "FileRoute: directorio no en whitelist [" + cSpec + "]" )
      RETURN NIL

   ENDIF

   IF lPublic .AND. ! hb_FileExists( cPhysical )

      cAlt := _HixTryPublicFallback( oDisp:cRoot, "/" + cSpec )

      IF cAlt != NIL ; RETURN cAlt ; ENDIF

   ENDIF

RETURN cPhysical

// Ejecuta un .prg o .hrb y responde si el script no lo hizo via U*.
STATIC FUNCTION _HixExecFileAction( oDisp, cFile, hClass, oReq, lSkipDeny )

   LOCAL cPhysical, cResult, cExt, oErr

   cPhysical := _HixResolveFilePath( oDisp, cFile, lSkipDeny )

   IF cPhysical == NIL

      HIX_HttpError( oReq, 403 )
      RETURN NIL

   ENDIF

   IF ! hb_FileExists( cPhysical )

      HIX_HttpError( oReq, 404 )
      RETURN NIL

   ENDIF

   cExt    := Lower( hb_FNameExt( cPhysical ) )
   cResult := ""
   oErr    := NIL

   BEGIN SEQUENCE WITH {| e | Break( e ) }

      IF cExt == ".hrb"

         cResult := oDisp:ExecuteHrb( cPhysical )
      ELSE

         cResult := oDisp:ExecutePrg( cPhysical, oReq, hClass )

      ENDIF

   RECOVER USING oErr
      HIX_Throw( oErr )

   END SEQUENCE



   IF ! Empty( cResult )

      HIX_Echo( cResult )

   ENDIF

   IF oReq:lStreaming

      // IF ! Empty( oReq:cEchoBuffer )
      oReq:RespondChunk( oReq:cEchoBuffer )
      // ENDIF
      oReq:RespondEnd()
   ELSEIF ! oReq:lResponded
      oReq:Respond( HIX_EchoGet(), HIX_GetStatus(), HIX_GetMime() )

   ENDIF

   HIX_EchoClear()

RETURN NIL

// Sirve un fichero estatico (html, jpg, png...) con MIME correcto.
STATIC FUNCTION _HixServeFileStatic( oDisp, cFile, cMime, oReq, lSkipDeny )

   LOCAL cPhysical := _HixResolveFilePath( oDisp, cFile, lSkipDeny )

   IF cPhysical == NIL

      HIX_HttpError( oReq, 403 )
      RETURN NIL

   ENDIF

   IF ! hb_FileExists( cPhysical )

      HIX_HttpError( oReq, 404 )
      RETURN NIL

   ENDIF

   oReq:Respond( oDisp:ExecuteFile( cPhysical ), 200, cMime )

RETURN NIL

// ============================================================
// Abort map — permite que el hijo sepa si debe abortar tras timeout.
// LIMITACION: solo funciona si el PRG llama HixShouldAbort().
// En el futuro, si Harbour soporta hb_threadKill, reemplazar.
// ============================================================

STATIC FUNCTION _HixAbortMapInit()

   IF s_hAbortMx == NIL

      s_hAbortMx  := hb_mutexCreate()
      s_hAbortMap := hb_Hash()

   ENDIF

RETURN NIL

STATIC FUNCTION _HixAbortMapSet( nId, lVal )

   _HixAbortMapInit()
   hb_mutexLock( s_hAbortMx )
   s_hAbortMap[ nId ] := lVal
   hb_mutexUnlock( s_hAbortMx )

RETURN NIL

STATIC FUNCTION _HixAbortMapGet( nId )

   LOCAL lVal := .F.

   IF s_hAbortMx == NIL ; RETURN .F. ; ENDIF

   hb_mutexLock( s_hAbortMx )
   lVal := hb_HGetDef( s_hAbortMap, nId, .F. )
   hb_mutexUnlock( s_hAbortMx )

RETURN lVal

STATIC FUNCTION _HixAbortMapDel( nId )

   IF s_hAbortMx == NIL ; RETURN NIL ; ENDIF

   hb_mutexLock( s_hAbortMx )
   hb_HDel( s_hAbortMap, nId )
   hb_mutexUnlock( s_hAbortMx )

RETURN NIL

// ============================================================
// HixShouldAbort() — API para que un PRG detecte timeout cooperativamente.
//
// ** PENDIENTE DE IMPLEMENTAR **
// Con HB_HRB_BIND_LOCAL los HRBs compilados en runtime no pueden llamar
// funciones del exe host, por lo que esta API no es accesible desde
// los PRGs de usuario. Para implementarla se necesita un mecanismo
// alternativo que no requiera llamadas al host (p.ej. fichero flag,
// variable compartida via hb_threadLocalData, o cambio de binding).
// ============================================================
FUNCTION HixShouldAbort()
RETURN _HixAbortMapGet( hb_threadId() )

// ============================================================
// Hixstyle public assets — helpers
//
// Cuando `hixstyle.enabled=true` + `hixstyle.public=true`, los
// recursos estaticos se resuelven bajo `<root>/public/`:
//
// 1. Prefijos conocidos ({images,img,css,js,fonts,assets}) se
// reescriben directamente: /images/x.jpg -> public/images/x.jpg
// 2. Cualquier otro path que no exista en <root>/ pero si en
// <root>/public/ se sirve como fallback.
// ============================================================
STATIC FUNCTION _HixHixstylePublicOn()
RETURN UConfig( "hixstyle", "enabled", .F. ) .AND. ;
      UConfig( "hixstyle", "public",  .T. )

STATIC FUNCTION _HixApplyHixstylePrefix( cPath )

   STATIC saPrefixes := { "images", "img", "css", "js", "fonts", "assets" }
   LOCAL cRest, nSep, cFirst

   IF Empty( cPath ) .OR. Left( cPath, 1 ) != "/"

      RETURN cPath

   ENDIF

   cRest := SubStr( cPath, 2 )
   nSep  := At( "/", cRest )

   IF nSep == 0

      RETURN cPath

   ENDIF

   cFirst := Lower( Left( cRest, nSep - 1 ) )

   IF AScan( saPrefixes, {| c | c == cFirst } ) > 0

      RETURN "/public" + cPath

   ENDIF

RETURN cPath

// Devuelve .T. si cRelDir (relativo al root, lowercase, sin sep final) esta
// cubierto por alguna entrada de la whitelist (match exacto o subdir).
STATIC FUNCTION _HixWhitelistMatch( aAllow, cRelDir )

   LOCAL nI, cEntry

   IF aAllow == NIL

      RETURN .T.   // sin whitelist activa: no filtra

   ENDIF

   FOR nI := 1 TO Len( aAllow )

      cEntry := aAllow[ nI ][ "dir" ]

      IF cRelDir == cEntry .OR. Left( cRelDir, Len( cEntry ) + 1 ) == cEntry + hb_ps()

         RETURN .T.

      ENDIF

   NEXT

RETURN .F.

// Devuelve .T. si cRelDir esta en whitelist con flag exec=.T. — usado para
// permitir PRG/HRB en una carpeta puntual aunque dispatch_mode="static" haya
// desactivado ::lExecPrg globalmente.
STATIC FUNCTION _HixExecAllowedForRelDir( aAllow, cRelDir )

   LOCAL nI, cEntry

   IF aAllow == NIL

      RETURN .F.

   ENDIF

   FOR nI := 1 TO Len( aAllow )

      cEntry := aAllow[ nI ][ "dir" ]

      IF cRelDir == cEntry .OR. Left( cRelDir, Len( cEntry ) + 1 ) == cEntry + hb_ps()

         RETURN aAllow[ nI ][ "exec" ]

      ENDIF

   NEXT

RETURN .F.

STATIC FUNCTION _HixTryPublicFallback( cRoot, cPath )

   LOCAL cPub

   IF Empty( cPath ) .OR. Left( cPath, 1 ) != "/"

      RETURN NIL

   ENDIF

   IF Lower( Left( cPath, 8 ) ) == "/public/"

      RETURN NIL

   ENDIF

   cPub := cRoot + hb_DirSepToOS( "/public" + cPath )

   IF hb_FileExists( cPub )

      RETURN cPub

   ENDIF

RETURN NIL
