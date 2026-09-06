/*-----------------------------------------------------------
  File ......: hix_server.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: THixServer — TCP accept loop, three worker pools
               (HTTP/WS/Others) and server lifecycle.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_VERSION_SERVER                "2.1"
#DEFINE HIX_SUBVERSION_SERVER             ""       // ".01"
#DEFINE HIX_LOG_MODULE HIX_MOD_SERVER
#DEFINE SW_SHOW                              5

#INCLUDE "hix_logger.ch"
#INCLUDE "hix_const.ch"
#INCLUDE "hix_external.ch"

#INCLUDE "hbssl.ch"



STATIC slStopRequested := .F.
STATIC slProxied       := .F.
STATIC snServerCount   := 0   // # instancias New() — la 1a posee globales, el resto no
STATIC sbLifecycle     := NIL // hook global {|cState, cLabel| ...} — nil = deshabilitado
STATIC slDormantHixstyle := .F. // www/config.json existe pero hixstyle.enabled=false


CLASS THixServer

   // Estado
   DATA hSocket       INIT NIL
   DATA oSrvSocket    INIT NIL
   DATA lRunning      INIT .F.
   DATA lStarted      INIT .F.
   DATA lOwnsGlobals  INIT .T.
   DATA hThread       INIT NIL
   // Pools
   DATA oPoolHTTP     INIT NIL
   DATA oPoolWS       INIT NIL
   DATA oPoolOtros    INIT NIL
   DATA oPoolHix      INIT NIL
   // Cola de rutas registradas antes de Start()
   DATA aRouteQueue   INIT {}
   // Dispatcher para rutas con accion de fichero (.prg/.hrb/.jpg...)
   // Si es NIL se crea automaticamente apuntando a "public/"
   DATA oDispatcher   INIT NIL
   // Handler de error de aplicacion: {|oErr, oReq| ...}
   DATA bOnError      INIT NIL
   // Callbacks WebSocket: {|oConn| ...} / {|oConn, cMsg, nOpcode| ...}
   DATA bOnWsConnect  INIT NIL
   DATA bOnWsMessage  INIT NIL
   DATA bOnWsClose    INIT NIL

   DATA bInit          INIT {| oSrv | ShowInit( oSrv ) }
   DATA bPreEnd        INIT {| oSrv | ShowPreEnd( oSrv ) }
   DATA bPostEnd       INIT {| oSrv | ShowPostEnd( oSrv ) }

   DATA lShowInfo       INIT .T.

   METHOD New( hOverrides )
   METHOD Start()
   METHOD Stop()
   METHOD SetFirewall( cFilter, cMode )

   // ---- API de rutas ----
   METHOD AddRoute( cName, cPattern, bAction, cMethod, cMw, cScope, uCargo )
   METHOD AddRouteGet(    cName, cPattern, bAction, cMw, cScope, uCargo )
   METHOD AddRoutePost(   cName, cPattern, bAction, cMw, cScope, uCargo )
   METHOD AddRoutePut(    cName, cPattern, bAction, cMw, cScope, uCargo )
   METHOD AddRouteDelete( cName, cPattern, bAction, cMw, cScope, uCargo )
   METHOD DeleteRoute( cName )
   METHOD AddRouteGroup( cPrefix, cMw, cScope, bBlock )
   METHOD SetRouteHandler( cEvent, bAction )
   METHOD RouteList()
   METHOD DenyDir(  cDir )
   METHOD AllowDir( cDir, lAllowExec )
   METHOD RoutePermissions()
   METHOD ShowRoutePermissions()

   HIDDEN:
   METHOD _Init()
   METHOD _InitPools()
   METHOD _BindListen()
   METHOD _AcceptLoop()
   METHOD _DestroyPools()
   METHOD _FlushRouteQueue()
   METHOD _GetDispatcher()

ENDCLASS

// New — hOverrides opcional. La configuracion vive en el hash global cargado por HIX_LoadConfig().
// La primera instancia del proceso es la duena de los globales (logger, metrics, access log).
// Las siguientes (sub-servers en tests, etc.) ponen lOwnsGlobals=.F. para no machacarlos.
// hOverrides: hash { cSection => { cKey => xVal, ... }, ... } — merge sobre la config global.
// Sub-servers ignoran hOverrides para no contaminar al server dueno.
METHOD New( hOverrides ) CLASS THixServer

   snServerCount++

   IF snServerCount > 1

      ::lOwnsGlobals := .F.

   ENDIF

   IF HB_ISHASH( hOverrides ) .AND. Len( hOverrides ) > 0 .AND. ::lOwnsGlobals

      HIX_LoadConfig()
      HIX_ConfigMerge( hOverrides )

   ENDIF

RETURN Self

// HIX_ConfigMerge — merge dos niveles sobre el hash global de config.
// Solo mutan las claves presentes en hOverrides; el resto queda intacto.
// Se usa desde THixServer:New(hOverrides) y es testeable directamente.
FUNCTION HIX_ConfigMerge( hOverrides )

   LOCAL hCfg, cSection, hSection, cKey

   IF ! HB_ISHASH( hOverrides ) .OR. Len( hOverrides ) == 0

      RETURN NIL

   ENDIF

   hCfg := HIX_GetConfig()

   IF ! HB_ISHASH( hCfg )

      hCfg := { => }

   ENDIF

   FOR EACH hSection IN hOverrides

      cSection := hSection:__enumKey()

      IF ! HB_ISHASH( hSection )

         LOOP

      ENDIF

      IF ! hb_HHasKey( hCfg, cSection )

         hCfg[ cSection ] := { => }

      ENDIF

      FOR EACH cKey IN hb_HKeys( hSection )

         hCfg[ cSection ][ cKey ] := hSection[ cKey ]

      NEXT

   NEXT

   HIX_SetConfig( hCfg )

RETURN NIL

// Start — no bloqueante. Lanza el accept loop en hilo propio.
METHOD Start( lModal ) CLASS THixServer

   LOCAL cDomain, cBanner, cAppCfg, cHost
   LOCAL nPort
   
   hb_default( @lModal, .t. )

   slStopRequested := .F.

   _LC( "start", "Init server..." )

   IF ! ::_Init()

      _LC( "off", "Init failed" )
      RETURN Self

   ENDIF

   // Aplicar sets Harbour + config.json ANTES de spawn de pools.
   // Los workers heredan el estado via hb_setClone (vm/thread.c:1109).

   IF UConfig( "hixstyle", "enabled", .F. )

      cAppCfg := UConfig( "paths", "root", "www" ) + "/config.json"

      IF ! File( cAppCfg )

         HIX_ConfigAppReset( HIX_ConfigAppDefaults() )

         IF HIX_ConfigAppSave( cAppCfg )

            HIX_BootLogAdd( "config", "file", .T., cAppCfg + " (auto-created)" )
         ELSE
            HIX_BootLogAdd( "config", "file", .F., "cannot create " + cAppCfg )

         ENDIF

      ELSE

         HIX_ConfigAppLoad( cAppCfg )

         // Backfill new default keys introduced in later versions
         // (non-destructive: never overwrites user values).

         IF HIX_ConfigAppMerge( HIX_ConfigAppDefaults() ) > 0

            HIX_ConfigAppSave( cAppCfg )
            HIX_BootLogAdd( "config", "file", .T., cAppCfg + " (merged defaults)" )
         ELSE
            HIX_BootLogAdd( "config", "file", .T., cAppCfg )

         ENDIF

      ENDIF

      HIX_HarbourConfigApply()

      HIX_KeysLoadFromAppConfig()

      HIX_LoadMiddleware()

   ENDIF

   _LC( "start", "Init pools..." )

   IF ! ::_InitPools()

      le( _( "SRV_ERR_POOLS_INIT" ) )
      _LC( "off", "Pools failed" )
      RETURN Self

   ENDIF

   nPort := UConfig( "server", "port", 80 )

   _LC( "start", "Bind & listen :" + hb_ntos( nPort ) )

   IF ! ::_BindListen()

      OutStd( _( "SRV_ERR_BIND_PORT", hb_ntos( nPort ) ) + hb_eol() )
      le( _( "SRV_LOG_BIND_PORT", hb_ntos( nPort ) ) )
      ::_DestroyPools()
      _LC( "off", "Bind failed" )
      RETURN Self

   ENDIF

   ::lStarted := .T.

   HIX_ZombieInit()

   ::lRunning := .T.

   _HixCheckDormantHixstyle()

   HIX_Loaders()

   IF ::lShowInfo .AND. ValType( ::bInit ) == "B"

      Eval( ::bInit, SELF )

   ENDIF

   // Independientemente de bInit y ShowInfo, ejecutamos si es necesario HIX_UserInit()
   HIX_UserInit()

   cHost   := UConfig( "server", "host", "localhost" )
   cDomain := iif( cHost == "0.0.0.0", "localhost", cHost )
   cBanner := " => " + cDomain

   IF nPort != 80

      cBanner += " : " + hb_ntos( nPort )

   ENDIF

   l( _( "SRV_LISTENING" ) + cBanner )

   ::hThread := hb_threadStart( {|| ::_AcceptLoop() } )

   IF ::lOwnsGlobals .AND. UConfig( "server", "autostart", .T. )

      HIX_Navigator()

   ENDIF

   HIX_MonitorStart( Self )

   _LC( "on", "Server On :" + hb_ntos( nPort ) )

   IF lModal
   
      // Espera ESC o parada interna (ej. /hix-stop)
      DO WHILE ::lRunning
         IF inkey( 0.5 ) == 27
            EXIT
         ENDIF
      ENDDO   
      
      ::Stop()  

   endif 

RETURN Self

// Stop — cierre ordenado completo. Espera que el accept loop termine.
METHOD Stop() CLASS THixServer

   LOCAL nT0

   IF ! ::lStarted

      IF ::lOwnsGlobals

         HIX_MetricsClose()
         HIX_AccessLogClose()
         HIX_ErrorLogClose()
         HIX_LoggerClose()

      ENDIF

      RETURN NIL

   ENDIF

   // Antes de cerrar conexiones...

   HIX_UserExit()

   IF ::lShowInfo .AND. ValType( ::bPreEnd ) == 'B'

      Eval( ::bPreEnd, SELF )

   ENDIF

   _LC( "stop", "Server stopping..." )
   l( _( "SRV_STOPPING" ) )

   ::lRunning := .F.

   IF ::lOwnsGlobals

      slStopRequested := .T.

   ENDIF

   _LC( "wait", "Joining accept loop..." )

   IF ::hThread != NIL

      nT0 := hb_MilliSeconds()
      hb_threadJoin( ::hThread )
      _LC( "wait", "Accept loop joined (" + _FmtElapsed( nT0 ) + ")" )
      ::hThread := NIL

   ENDIF

   _LC( "wait", "Stopping monitor..." )
   nT0 := hb_MilliSeconds()
   HIX_MonitorStop()
   _LC( "wait", "Monitor stopped (" + _FmtElapsed( nT0 ) + ")" )

   _LC( "stop", "Stopping pools..." )
   nT0 := hb_MilliSeconds()
   ::_DestroyPools()
   _LC( "stop", "Pools stopped (" + _FmtElapsed( nT0 ) + ")" )

   IF ::lOwnsGlobals

      HIX_MetricsClose()
      HIX_AccessLogClose()
      HIX_ErrorLogClose()
      HIX_LoggerClose()

   ENDIF

   _LC( "off", "Server Off" )

   IF ::lShowInfo .AND. ValType( ::bPostEnd ) == 'B'

      Eval( ::bPostEnd, SELF )

   ENDIF

RETURN Self

// ============================================================
// _Init — inicializa todos los subsistemas
// ============================================================
METHOD _Init() CLASS THixServer

   LOCAL oDisp
   LOCAL cDispatchMode
   LOCAL cRoot

   IF ::lOwnsGlobals

      HIX_BootLogReset()
      HIX_LoggerInit( "", HIX_LOG_DEBUG, .T. )
      l( _( "SRV_STARTING" ) )

      HIX_LoadConfig()
      HIX_BootLogAdd( "config", "file", .T., "hix.ini" )

      HIX_LoggerInit( _HixLogPath( UConfig( "log", "file", "hix.log" ) ), ;
         HIX_LogLevelFromStr( UConfig( "log", "level", "info" ) ), ;
         UConfig( "log", "console", .T. ), ;
         UConfig( "log", "max_size_mb", 10 ) * 1024 * 1024, ;
         UConfig( "log", "max_files", 0 ) )
      HIX_BootLogAdd( "server", "init", .T., ;
         "logger level=" + UConfig( "log", "level", "info" ) + ;
         " console=" + iif( UConfig( "log", "console", .T. ), "T", "F" ) )
   ELSE
      l( _( "SRV_STARTING_SHARED" ) )

   ENDIF

   slProxied := UConfig( "server", "mode", HIX_MODE_STANDALONE ) == HIX_MODE_PROXIED

   IF ::lOwnsGlobals

      HIX_ProxyInit( UConfig( "server", "trusted_proxies", "" ) )

      IF ! Empty( UConfig( "server", "trusted_proxies", "" ) )

         HIX_BootLogAdd( "server", "init", .T., ;
            "proxy trusted=" + UConfig( "server", "trusted_proxies", "" ) )

      ENDIF

      IF ! Empty( UConfig( "firewall", "filter", "" ) )

         HIX_FirewallSetup( UConfig( "firewall", "filter", "" ), ;
            UConfig( "firewall", "mode", "blacklist" ) )
         HIX_BootLogAdd( "server", "init", .T., ;
            "firewall mode=" + UConfig( "firewall", "mode", "blacklist" ) + ;
            " filter=" + _FwFilterDisplay( UConfig( "firewall", "filter", "" ) ) )

      ENDIF

      HIX_AccessLogInit( _HixLogPath( UConfig( "access_log", "file", "access.log" ) ), ;
         UConfig( "access_log", "enabled", .T. ) )
      HIX_BootLogAdd( "server", "init", .T., ;
         "access_log enabled=" + ;
         iif( UConfig( "access_log", "enabled", .T. ), "T", "F" ) + ;
         " file=" + UConfig( "access_log", "file", "access.log" ) )
      HIX_MetricsInit()
      HIX_BootLogAdd( "server", "init", .T., "metrics" )

   ENDIF

   IF UConfig( "hixstyle", "cache_ram", .F. )

      HIX_ViewCacheInit()
      HIX_BootLogAdd( "server", "init", .T., "view_cache_ram" )

   ENDIF

   HIX_SocketInit()
   HIX_BootLogAdd( "server", "init", .T., ;
      "socket ssl=" + iif( UConfig( "server", "ssl", .F. ), "T", "F" ) )
   HIX_RoutesLoad()
   ::_FlushRouteQueue()
   HIX_LoadRoutes()

   // Verify root directory exists — create it if missing
   cRoot := UConfig( "paths", "root", "www" )
   IF ! hb_DirExists( cRoot )
      hb_DirCreate( cRoot )
      HIX_BootLogAdd( "server", "init", .T., "root dir created: " + cRoot )
   ENDIF

   // Dispatcher como fallback segun dispatch_mode (routes = sin dispatcher)
   cDispatchMode := UConfig( "app", "dispatch_mode", "full" )

   IF cDispatchMode != "routes"

      oDisp := THixDispatcher():New( UConfig( "paths", "root", "www" ) )
      oDisp:nExecTimeout := UConfig( "server", "exec_timeout_ms", 30000 )
      oDisp:cDefaultPage := UConfig( "app", "default_page", "index.html" )
      oDisp:lExecPrg     := ( cDispatchMode != "static" )

      // hixstyle: whitelist estricta con "public" auto-permitida (zero-trust)

      IF UConfig( "hixstyle", "enabled", .F. )

         oDisp:AllowDir( "public", .F. )
         HIX_BootLogAdd( "server", "init", .T., ;
            "hixstyle acl whitelist=public (+usuario)" )

      ENDIF

      // Heredar ACL configurada antes de Start() via DenyDir/AllowDir
      // Acumulativo para no pisar el auto-allow de hixstyle.

      IF ::oDispatcher != NIL

         AEval( ::oDispatcher:aDenyDirs, {| c | oDisp:DenyDir( c ) } )

         IF ::oDispatcher:aAllowDirs != NIL

            AEval( ::oDispatcher:aAllowDirs, {| h | oDisp:AllowDir( h[ "dir" ], h[ "exec" ] ) } )

         ENDIF

      ENDIF

      ::oDispatcher := oDisp
      HIX_RouteSetHandler( "404", {| oReq | oDisp:Dispatch( oReq ) } )

   ENDIF

   IF ::lOwnsGlobals

      HIX_ErrorLogInit( UConfig( "paths", "errors", ".logs" ) )
      HIX_ErrorSysInit( UConfig( "app", "errorsys", "" ) )

   ENDIF

   // Error handler: bOnError personalizado, o HIX_ShowError por defecto

   IF ::bOnError != NIL

      HIX_SetErrorHandler( ::bOnError )
   ELSE
      HIX_SetErrorHandler( {| oErr, oReq | HIX_ShowError( oErr, oReq ) } )

   ENDIF

   // Registrar callbacks WebSocket si se han definido

   IF HB_ISBLOCK( ::bOnWsConnect )  .OR. HB_ISBLOCK( ::bOnWsMessage ) .OR. HB_ISBLOCK( ::bOnWsClose )

      HIX_WsSetCallbacks( ::bOnWsConnect, ::bOnWsMessage, ::bOnWsClose )

   ENDIF

   // Contexto SSL servidor
   ::oSrvSocket := THixSocket():New()

RETURN .T.

// ============================================================
METHOD _InitPools() CLASS THixServer

   ::oPoolHTTP  := THixPool():New( HIX_POOL_HTTP,  {| j | HIX_WorkerHTTP( j ) } )
   ::oPoolWS    := THixPool():New( HIX_POOL_WS,    {| j | HIX_WorkerWS( j ) } )
   ::oPoolOtros := THixPool():New( HIX_POOL_REST,  {| j | HIX_WorkerRest( j ) } )
   ::oPoolHix   := THixPool():New( HIX_POOL_HIX,   {| j | HIX_WorkerHTTP( j ) } )
   ::oPoolHTTP:Init()
   ::oPoolWS:Init()
   ::oPoolOtros:Init()
   ::oPoolHix:Init()

RETURN .T.

METHOD _BindListen() CLASS THixServer

   LOCAL hSock
   LOCAL cHost, cResolved, nPort, nMaxConn

   hSock := hb_socketOpen()

   IF hSock == NIL

      le( _( "SRV_ERR_SOCKET" ) )
      RETURN .F.

   ENDIF

   cHost     := UConfig( "server", "host", "localhost" )
   nPort     := UConfig( "server", "port", 80 )
   nMaxConn  := UConfig( "server", "maxconn", 1024 )
   cResolved := hb_socketResolveAddr( cHost, HB_SOCKET_AF_INET )

   IF Empty( cResolved )

      le( _( "SRV_ERR_RESOLVE", cHost ) )
      hb_socketClose( hSock )
      RETURN .F.

   ENDIF

   hb_socketSetReuseAddr( hSock, .T. )

   IF ! hb_socketBind( hSock, { HB_SOCKET_AF_INET, cResolved, nPort } )

      le( _( "SRV_ERR_BIND", hb_socketErrorString() ) )
      hb_socketClose( hSock )
      RETURN .F.

   ENDIF

   IF ! hb_socketListen( hSock, nMaxConn )

      le( _( "SRV_ERR_LISTEN", hb_socketErrorString() ) )
      hb_socketClose( hSock )
      RETURN .F.

   ENDIF

   ::hSocket := hSock

RETURN .T.

METHOD _AcceptLoop() CLASS THixServer

   LOCAL hConn, aAddr, cIP, cPeek, cTipo, oIO, lOk
   LOCAL lSSL       := UConfig( "server", "ssl", .F. )
   LOCAL nPeekBytes := UConfig( "detector", "peek_bytes", 512 )
   LOCAL nPeekMs    := UConfig( "detector", "peek_timeout_ms", 10 )

   DO WHILE ::lRunning

      hConn := hb_socketAccept( ::hSocket, @aAddr, 1000 )

      IF Empty( hConn )

         IF hb_socketGetError() != HB_SOCKET_ERR_TIMEOUT

            lw( "AcceptLoop: accept error " + hb_socketErrorString() )

         ENDIF

         IF slStopRequested

            EXIT

         ENDIF

         LOOP

      ENDIF

      cIP   := iif( HB_ISARRAY( aAddr ) .AND. Len( aAddr ) >= 2, hb_CStr( aAddr[ 2 ] ), "0.0.0.0" )

      IF ! HIX_FirewallCheck( cIP )

         lw( _( "SRV_FW_BLOCKED", cIP ) )
         hb_socketClose( hConn )
         LOOP

      ENDIF

      HIX_SocketConfigure( hConn )

      IF lSSL

         // SSL: handshake en el worker para no bloquear el accept loop
         lOk := ::oPoolHTTP:Dispatch( { hConn, cIP, ::oSrvSocket } )

         IF ! lOk

            lw( "AcceptLoop: pool full — dropping SSL connection from " + cIP )
            hb_socketClose( hConn )

         ENDIF

      ELSE
         cPeek := HIX_SocketPeek( hConn, nPeekBytes, nPeekMs )
         oIO   := THixIO():New( hConn )
         cTipo := iif( cPeek != NIL, HIX_DetectProtocol( cPeek ), HIX_CONN_HTTP )
         lOk   := .T.

         DO CASE

            CASE cTipo == HIX_CONN_HTTP

            IF HIX_IsHixPath( cPeek )

               lOk := ::oPoolHix:Dispatch( { oIO, cIP } )
            ELSE
               lOk := ::oPoolHTTP:Dispatch( { oIO, cIP } )

               ENDIF

            CASE cTipo == HIX_CONN_WS
               lOk := ::oPoolWS:Dispatch( { oIO, cIP } )
            CASE cTipo == HIX_CONN_SSE .OR. cTipo == HIX_CONN_LONGPOLL
               lOk := ::oPoolOtros:Dispatch( { oIO, cIP, cTipo } )
            OTHERWISE
               ld( "AcceptLoop: unknown protocol from " + cIP )
               HIX_ResponseRaw( oIO, hb_jsonEncode( { "error" => _( 'ERR_BAD_REQUEST' ) } ), "json", 400, .F. )
               oIO:Close()
               LOOP

         ENDCASE

         IF ! lOk

            lw( _( "SRV_POOL_FULL_503", cIP ) )
            HIX_ResponseRaw( oIO, '{"error":"Service Unavailable"}', "json", 503, .F. )
            oIO:Close()

         ENDIF

      ENDIF

   ENDDO

   ::lRunning := .F.
   l( _( "SRV_ACCEPT_ENDED" ) )

RETURN Self

METHOD _DestroyPools() CLASS THixServer

   l( _( "SRV_POOLS_DESTROY" ) )

   IF ::oPoolHTTP  != NIL ; ::oPoolHTTP:Stop()          ; ::oPoolHTTP  := NIL ; ENDIF
   IF ::oPoolWS    != NIL ; ::oPoolWS:Stop()            ; ::oPoolWS    := NIL ; ENDIF
   IF ::oPoolOtros != NIL ; ::oPoolOtros:Stop()         ; ::oPoolOtros := NIL ; ENDIF
   IF ::oPoolHix   != NIL ; ::oPoolHix:Stop()           ; ::oPoolHix   := NIL ; ENDIF
   IF ::hSocket    != NIL ; hb_socketClose( ::hSocket ) ; ::hSocket    := NIL ; ENDIF

   l( _( "SRV_POOLS_DESTROYED" ) )

RETURN Self

// ============================================================
// _FlushRouteQueue — vuelca las rutas encoladas antes de Start()
// ============================================================
METHOD _FlushRouteQueue() CLASS THixServer

   LOCAL aItem

   FOR EACH aItem IN ::aRouteQueue

      DO CASE

         CASE aItem[ 1 ] == "route"
            HIX_RouteAdd( aItem[ 2 ], aItem[ 3 ], aItem[ 4 ], aItem[ 5 ], aItem[ 6 ], aItem[ 7 ], aItem[ 8 ] )
         CASE aItem[ 1 ] == "group"
            HIX_RouteGroup( aItem[ 2 ], aItem[ 3 ], aItem[ 4 ], aItem[ 5 ], Self )

      ENDCASE

   NEXT

   ::aRouteQueue := {}

RETURN Self

// ============================================================
// API de rutas — encolan si el router no está listo, o añaden directamente
// ============================================================
METHOD AddRoute( cName, cPattern, bAction, cMethod, cMw, cScope, uCargo ) CLASS THixServer

   hb_default( @cMethod, "*" )
   hb_default( @cMw,     ""  )
   hb_default( @cScope,  ""  )

   IF ValType( bAction ) == "C" .AND. HIX_IsFilePath( bAction )

      IF uCargo == NIL ; uCargo := bAction ; ENDIF

      bAction := HIX_FileRoute( ::_GetDispatcher(), bAction )

   ENDIF

   IF HIX_RoutesIsInit()

      HIX_RouteAdd( cName, cPattern, bAction, cMethod, cMw, cScope, uCargo )
   ELSE
      AAdd( ::aRouteQueue, { "route", cName, cPattern, bAction, cMethod, cMw, cScope, uCargo } )

   ENDIF

RETURN Self

METHOD _GetDispatcher() CLASS THixServer

   IF ::oDispatcher == NIL

      ::oDispatcher := THixDispatcher():New( UConfig( "paths", "root", "www" ) )

   ENDIF

RETURN ::oDispatcher

METHOD DenyDir( cDir ) CLASS THixServer
RETURN ::_GetDispatcher():DenyDir( cDir )

METHOD AllowDir( cDir, lAllowExec ) CLASS THixServer
RETURN ::_GetDispatcher():AllowDir( cDir, lAllowExec )

// Retorna array de hashes para cada ruta de fichero con su estado de acceso.
// Cada item: { name, pattern, method, file, allowed, path }
METHOD RoutePermissions() CLASS THixServer

   LOCAL aList, hRoute, aResult, cFile, cPath, oDisp

   aList   := HIX_RouteList()
   aResult := {}
   oDisp   := ::_GetDispatcher()

   FOR EACH hRoute IN aList

      cFile := hb_HGetDef( hRoute, "cargo", NIL )

      IF ValType( cFile ) != "C"

         LOOP

      ENDIF

      cPath := oDisp:CheckPath( cFile )
      AAdd( aResult, { ;
         "name"    => hRoute[ "name" ],       ;
         "pattern" => hRoute[ "pattern" ],    ;
         "method"  => hRoute[ "method" ],     ;
         "file"    => cFile,                ;
         "allowed" => ( cPath != NIL ),     ;
         "path"    => hb_defaultValue( cPath, "" ) ;
         } )

   NEXT

RETURN aResult

// Muestra por consola la configuracion del dispatcher y los permisos de rutas.
METHOD ShowRoutePermissions() CLASS THixServer

   LOCAL aPerms, hP, oDisp, cLine, cAccess, nI, cDirs
   LOCAL cFmt := "%-22s %-28s %-14s %-30s %s"

   oDisp  := ::_GetDispatcher()
   aPerms := ::RoutePermissions()

   QQOut( HIX_CRLF )
   QQOut( _( "SRV_ACL_TITLE" ) + HIX_CRLF )
   QQOut( "  Root      : " + oDisp:cRoot + HIX_CRLF )
   QQOut( "  Exec PRG  : " + iif( oDisp:lExecPrg, _( "SRV_ACL_YES" ), _( "SRV_ACL_NO_BLOCKED" ) ) + HIX_CRLF )

   IF Empty( oDisp:aDenyDirs )

      QQOut( _( "SRV_ACL_DENY_NONE" ) + HIX_CRLF )
   ELSE
      cDirs := "" ; FOR nI := 1 TO Len( oDisp:aDenyDirs ) ; cDirs += iif( nI > 1, ", ", "" ) + oDisp:aDenyDirs[ nI ] ; NEXT
      QQOut( "  Deny dirs : " + cDirs + HIX_CRLF )

   ENDIF

   IF oDisp:aAllowDirs == NIL

      QQOut( _( "SRV_ACL_ALLOW_ALL" ) + HIX_CRLF )
   ELSE
      cDirs := ""

      FOR nI := 1 TO Len( oDisp:aAllowDirs )

         cDirs += iif( nI > 1, ", ", "" ) + oDisp:aAllowDirs[ nI ][ "dir" ] + ;
            iif( oDisp:aAllowDirs[ nI ][ "exec" ], "(exec)", "" )

      NEXT

      QQOut( "  Allow dirs: " + cDirs + HIX_CRLF )

   ENDIF

   QQOut( HIX_CRLF )

   IF Empty( aPerms )

      QQOut( _( "SRV_ACL_NO_FILE_ROUTES" ) + HIX_CRLF )
      RETURN Self

   ENDIF

   cLine := Replicate( "-", 110 ) + HIX_CRLF
   QQOut( _( "SRV_ACL_FILE_ROUTES" ) + HIX_CRLF )
   QQOut( cLine )
   QQOut( hb_StrFormat( cFmt, "Name", "Pattern", "Methods", "File", "Access" ) + HIX_CRLF )
   QQOut( cLine )

   FOR EACH hP IN aPerms

      cAccess := iif( hP[ "allowed" ], "OK", "DENIED" )
      QQOut( hb_StrFormat( cFmt, hP[ "name" ], hP[ "pattern" ], hP[ "method" ], hP[ "file" ], cAccess ) + HIX_CRLF )

   NEXT

   QQOut( cLine )

RETURN Self

METHOD AddRouteGet( cName, cPattern, bAction, cMw, cScope, uCargo ) CLASS THixServer
RETURN ::AddRoute( cName, cPattern, bAction, "GET",    cMw, cScope, uCargo )

METHOD AddRoutePost( cName, cPattern, bAction, cMw, cScope, uCargo ) CLASS THixServer
RETURN ::AddRoute( cName, cPattern, bAction, "POST",   cMw, cScope, uCargo )

METHOD AddRoutePut( cName, cPattern, bAction, cMw, cScope, uCargo ) CLASS THixServer
RETURN ::AddRoute( cName, cPattern, bAction, "PUT",    cMw, cScope, uCargo )

METHOD AddRouteDelete( cName, cPattern, bAction, cMw, cScope, uCargo ) CLASS THixServer
RETURN ::AddRoute( cName, cPattern, bAction, "DELETE", cMw, cScope, uCargo )

METHOD DeleteRoute( cName ) CLASS THixServer

   IF HIX_RoutesIsInit()

      HIX_RouteDelete( cName )

   ENDIF

RETURN Self

METHOD AddRouteGroup( cPrefix, cMw, cScope, bBlock ) CLASS THixServer

   IF HIX_RoutesIsInit()

      HIX_RouteGroup( cPrefix, cMw, cScope, bBlock, Self )
   ELSE
      AAdd( ::aRouteQueue, { "group", cPrefix, cMw, cScope, bBlock } )

   ENDIF

RETURN Self

METHOD SetRouteHandler( cEvent, bAction ) CLASS THixServer

   IF HIX_RoutesIsInit()

      HIX_RouteSetHandler( cEvent, bAction )
   ELSE
      lw( "SetRouteHandler ignorado: router no inicializado" )

   ENDIF

RETURN Self

METHOD SetFirewall( cFilter, cMode ) CLASS THixServer

   hb_default( @cMode, "blacklist" )
   HIX_FirewallSetup( cFilter, cMode )

RETURN Self

METHOD RouteList() CLASS THixServer
RETURN HIX_RouteList()

STATIC FUNCTION ShowInit( oSrv )

   LOCAL cHost    := UConfig( "server", "host", "localhost" )
   LOCAL nPort    := UConfig( "server", "port", 80 )   
   LOCAL cDomain  := iif( cHost == "0.0.0.0", "localhost", cHost )
   LOCAL cTitle   := "Hix server vrs. " + HIX_VERSION_SERVER + HIX_SUBVERSION_SERVER + " => Running on " + cDomain
   LOCAL cLang    := hb_oemtoansi(hb_langName()) + ', ' + hb_SetCodePage() + '/' + hb_cdpUniID( hb_SetCodePage() )
   LOCAL nRow, cI := ''
   
   if nPort <> 80 
      cTitle += ':' + ltrim(str(nPort))
   endif 
   
   AEval( rddList(), {| X | cI += iif( Empty( cI ), '', ', ' ) + X } )
   
	CLS 
	
	Setpos( 0, 0 )
	
	nRow 		:= Row()
	
	/*
		'    __  __        '
		'   / / / / (_)  __'  
		'  / /_/ / / / |/_/'  
		' / __  / / />  <  '  
		'/_/ /_/ /_/_/|_|  '
   */
	
	
	@nRow++, 0 say '    __  __'  COLOR 'B+'		
	@nRow-1,11 say '_'  COLOR 'B+'
	
	@nRow++, 0 say '   / / / /' COLOR 'B+'  		
	@nRow-1,10 say '(_)  __'  COLOR 'B+'
	
	@nRow++, 0 say '  / /_/ /'  COLOR 'B+'		
	@nRow-1, 9 say '/ / |/_/'  COLOR 'B+'
	
	@nRow++, 0 say ' / __  /' COLOR 'B+'		
	@nRow-1, 7 say '// />  <  '  COLOR 'B+'
	
	@nRow++, 0 say '/_/ /_/'  COLOR 'B+'		
	@nRow-1, 6 say '//_/_/|_|  '  COLOR 'B+' 	
	
	
	@nRow++, 0 say ' ' COLOR 'W+'
	@nRow++, 0 say cTitle  COLOR 'W+'        
	//@nRow++, 0 say Replicate( 	hb_UTF8ToStrBox('═'), len(cTitle) ) COLOR 'W+'    
	@nRow++, 0 say Replicate( '=', len(cTitle) ) COLOR 'W+'  
   
	

   HIX_Info( @nRow, 'Version HIX'			, 'HIX ' + HIX_VERSION_SERVER + HIX_SUBVERSION_SERVER + ' ' + HIX_DATECOMPILE() )
	HIX_Info( @nRow, 'Version Harbour'		, VERSION() + ' / ' + HB_BUILDDATE() )
	HIX_Info( @nRow, 'Version OpenSSL' 	, SSLEAY_VERSION( HB_SSLEAY_VERSION ) )
	HIX_Info( @nRow, 'Version Curl'    	, HIX_OptFunc( "CURL_VERSION",      "n/a (hbcurl not linked)" ) )
	HIX_Info( @nRow, 'Version HaruPdf' 	, HIX_OptFunc( "HPDF_VERSION_TEXT", "n/a (hbhpdf not linked)" ) )
	HIX_Info( @nRow, 'Version Compiler'	, HB_COMPILER() )
	HIX_Info( @nRow, 'RDD List' 			   , cI )
	HIX_Info( @nRow, 'RDD Default'        , RddSetDefault() )
	HIX_Info( @nRow, 'Language/Codepage' 	, cLang )
   
	nRow++
   
	HIX_Info( @nRow, 'Server startup at'  , DToC( date() ) + ' ' + time() )
	HIX_Info( @nRow, 'App Path'           , hb_dirbase() ) 
	HIX_Info( @nRow, 'App Name'           , UConfig( "server", "name", "HIX" ) ) 
	HIX_Info( @nRow, 'Root' 	            , UConfig( "paths", "root", "www" ) )
	HIX_Info( @nRow, 'HIX Style Active' 	, If( UConfig( "hixstyle", "enabled", .F. ), 'Yes', 'No' ) )
   
	@nRow++, 0 say '' 

   //QQOut( "Hix server vrs. " + HIX_VERSION_SERVER + " => Running on " + cDomain )
   
RETU NIL

STATIC FUNCTION ShowPreEnd( oSrv )

   QOut( _( "SRV_SHUTDOWN_WAIT" ) )
   
RETU NIL

STATIC FUNCTION ShowPostEnd( oSrv )

   QOut( _( "SRV_SHUTDOWN_OK" ) )
   
RETU NIL
// ============================================================
// HIX_Navigator — opens the default browser at the server URL
// ============================================================

FUNCTION HIX_Navigator()

   LOCAL cHost := UConfig( "server", "host", "localhost" )
   LOCAL nPort := UConfig( "server", "port", 80 )
   LOCAL lSSL  := UConfig( "server", "ssl", .F. )
   LOCAL cUrl

   IF cHost == "0.0.0.0"

      cHost := "localhost"

   ENDIF

   cUrl := iif( lSSL, "https://", "http://" ) + cHost

   IF ( ! lSSL .AND. nPort != 80 ) .OR. ( lSSL .AND. nPort != 443 )

      cUrl += ":" + hb_ntos( nPort )

   ENDIF

   l( "Navigator: opening " + cUrl )
   WAPI_ShellExecute( NIL, "open", cUrl, NIL, NIL, SW_SHOW )

RETURN NIL


// ============================================================
// HIX_OptFunc — call an optional Harbour function by name.
// Returns cFallback if the function is not linked. Used to keep
// the boot banner rendering when optional contribs (hbcurl,
// hbhpdf) are absent.
// ============================================================
FUNCTION HIX_OptFunc( cName, cFallback )

   LOCAL xResult

   BEGIN SEQUENCE WITH {|oErr| Break( oErr ) }
      xResult := Do( cName )
   RECOVER
      xResult := cFallback
   END SEQUENCE

RETURN xResult

FUNCTION HIX_Version() ; RETU HIX_VERSION_SERVER
FUNCTION HIX_SubVersion() ; RETU HIX_SUBVERSION_SERVER

// Normaliza el filtro del firewall para mostrarlo en el bootlog:
// acepta espacios o comas como separadores y devuelve una lista
// canonica separada por ", " (mas legible en el dump).

STATIC FUNCTION _FwFilterDisplay( cFilter )

   LOCAL aTok, cTok, cOut := ""

   IF Empty( cFilter )

      RETURN ""

   ENDIF

   aTok := hb_ATokens( StrTran( cFilter, ",", " " ), " " )

   FOR EACH cTok IN aTok

      IF ! Empty( cTok )

         cOut += iif( Empty( cOut ), "", ", " ) + cTok

      ENDIF

   NEXT

RETURN cOut

// Construye la ruta de un log a partir de paths.log + nombre.
// Si cFile ya contiene separador (path explicito) se devuelve tal cual.
STATIC FUNCTION _HixLogPath( cFile )

   LOCAL cDir

   IF Empty( cFile ) .OR. "/" $ cFile .OR. "\" $ cFile

      RETURN cFile

   ENDIF

   cDir := UConfig( "paths", "log", ".logs" )

   IF Empty( cDir )

      RETURN cFile

   ENDIF

   IF Right( cDir, 1 ) != "/" .AND. Right( cDir, 1 ) != "\"

      cDir += hb_ps()

   ENDIF

RETURN cDir + cFile

// Detecta si la request-line del peek pide un path bajo /hix-.
// Se usa desde el accept loop para enrutar al pool_hix.
FUNCTION HIX_IsHixPath( cPeek )

   LOCAL nStart, nEnd, cPath

   IF cPeek == NIL .OR. Len( cPeek ) < 8

      RETURN .F.

   ENDIF

   nStart := At( " ", cPeek )

   IF nStart == 0

      RETURN .F.

   ENDIF

   nEnd := At( " ", SubStr( cPeek, nStart + 1 ) )

   IF nEnd == 0

      RETURN .F.

   ENDIF

   cPath := SubStr( cPeek, nStart + 1, nEnd - 1 )

RETURN hb_LeftEq( cPath, "/hix-" )

// ============================================================
// _HixCheckDormantHixstyle -- flags projects that ship www/config.json
// but have hixstyle.enabled=false. Callers can consult the flag via
// HIX_HixstyleDormant() to add contextual hints (e.g. on 403).
// ============================================================
STATIC FUNCTION _HixCheckDormantHixstyle()

   LOCAL cRoot, cCfg

   slDormantHixstyle := .F.

   IF UConfig( "hixstyle", "enabled", .F. )

      RETURN .F.

   ENDIF

   cRoot := UConfig( "paths", "root", "www" )
   cCfg  := cRoot + "/config.json"

   IF hb_FileExists( cCfg )

      slDormantHixstyle := .T.
      lw( _( "HIXSTYLE_DORMANT_WARN", cCfg ) )
      HIX_BootLogAdd( "server", "hixstyle", .F., "dormant", ;
         _( "HIXSTYLE_DORMANT_LOG" ) )

   ENDIF

RETURN slDormantHixstyle

// ============================================================
// HIX_HixstyleDormant -- .T. si el arranque detecto www/config.json
// pero hixstyle.enabled=false. Consultado por HIX_HttpError para
// pintar un hint amistoso en 403 (solo en app.env=dev).
// ============================================================
FUNCTION HIX_HixstyleDormant()
RETURN slDormantHixstyle

static function HIX_Info( nRow, cCode, cValue, nCol )

   hb_default( @nCol, 25 )

	// 254  ■
	// 251  √
	// 175  »
   
	@nRow++, 1  SAY Chr( 175 ) + ' ' + cCode      COLOR CLR_SAY_GET   // »
	@nRow - 1  , nCol SAY cValue COLOR CLR_SAY_INFO
	
retu nil 

// --------------------------------------------------------- //

FUNCTION HIX_ServerRequestStop()

   slStopRequested := .T.

RETURN NIL

// Hook global de lifecycle: se invoca en puntos clave de Start()/Stop().
// bBlock recibe (cState, cLabel). cState: "start"|"on"|"stop"|"off"|"wait"|"info".
// Se aplica a todos los servers del proceso (principal + sub-servers).
FUNCTION HIX_SetLifecycleHook( bBlock )

   sbLifecycle := bBlock

RETURN NIL

STATIC PROCEDURE _LC( cState, cLabel )

   IF sbLifecycle != NIL

      TRY

         Eval( sbLifecycle, cState, cLabel )
      CATCH

      END

   ENDIF

RETURN

// Formatea ms transcurridos desde nT0 a "0.3s" o "1234ms".
STATIC FUNCTION _FmtElapsed( nT0 )

   LOCAL nMs := hb_MilliSeconds() - nT0

   IF nMs < 1000

      RETURN LTrim( Str( nMs, 0, 0 ) ) + "ms"

   ENDIF

RETURN LTrim( Str( nMs / 1000, 0, 1 ) ) + "s"

FUNCTION HIX_ServerIsRunning()
RETURN ! slStopRequested

FUNCTION HIX_IsProxied()
RETURN slProxied

// --------------------------------------------------------- //

#pragma BEGINDUMP

#include <string.h>
#include <stdio.h>
#include <hbapi.h>
#include <hbapiitm.h>

#ifdef _MSC_VER
#pragma warning( disable : 4996 )
#endif

HB_FUNC( HIX_DATECOMPILE )
{
   char * pszVersion = ( char * ) hb_xgrab( 80 );
   char szDate[ 12 ] = { 0 }, szTime[ 9 ] = { 0 };
   int year = 0, month = 0, day = 0, hour = 0, minute = 0;
   const char * months[] = {
      "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
   };

   memcpy( szDate, __DATE__, sizeof( szDate ) - 1 );
   memcpy( szTime, __TIME__, sizeof( szTime ) - 1 );

   sscanf( szDate + 7, "%d", &year );
   sscanf( szDate + 4, "%d", &day );

   for( month = 0; month < 12; ++month )
   {
      if( strncmp( szDate, months[ month ], 3 ) == 0 )
         break;
   }
   month += 1;

   sscanf( szTime, "%d:%d", &hour, &minute );

   hb_snprintf( pszVersion, 80, "(r%02d%02d%02d%02d%02d)", year % 100, month, day, hour, minute );

   hb_retc_buffer( pszVersion );
}

#pragma ENDDUMP