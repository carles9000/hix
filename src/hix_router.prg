/*-----------------------------------------------------------
  File ......: hix_router.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-24
  Description: Dynamic HIX router — thread-safe, named routes, :param
               capture, middleware chaining.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER

#INCLUDE "hix_const.ch"
#INCLUDE "hix_logger.ch"

STATIC s_hRoutes     := NIL   // hash de rutas (preserva orden de inserción)
STATIC s_aRouteOrder := NIL   // nombres de ruta ordenados por especificidad desc
STATIC s_mtxRoutes   := NIL   // mutex solo para escrituras
STATIC s_hHandlers   := NIL   // handlers de error: { '404'=>b, '405'=>b }
STATIC s_oRouteDisp  := NIL   // dispatcher lazy para acciones tipo fichero
STATIC s_cRouteSource := ""   // origen actual (para bootlog): fichero JSON, "system", ""

// ============================================================
// _HixRouteSetSource — marca el "origen" que se registrara en el
// bootlog para las proximas llamadas a HIX_RouteAdd. Uso interno.
// ============================================================
FUNCTION _HixRouteSetSource( cSource )

   s_cRouteSource := iif( ValType( cSource ) == "C", cSource, "" )

RETURN NIL

// ============================================================
// HIX_RoutesLoad — inicializa el router y registra rutas del sistema.
// Llamar ANTES de THixServer:Start().
// ============================================================
FUNCTION HIX_RoutesLoad()

   IF s_hRoutes != NIL

      RETURN NIL  // Already initialized — idempotent to allow calling before Start()

   ENDIF

   s_hRoutes    := { => }
   s_aRouteOrder := {}
   s_mtxRoutes  := hb_mutexCreate()
   s_hHandlers  := { => }

   // ping: público (health checks de balanceadores + herramientas de carga
   // cross-origin). Manda CORS wildcard y responde a OPTIONS/preflight.
   HIX_RouteAdd( "hix.slow",        '/hix-slow',        {| oReq | ( hb_idleSleep( 3 ), oReq:Respond( { "status" => "ok", "time" => time() } ) ) }, "GET" )
   HIX_RouteAdd( "hix.ping",        HIX_PATH_PING,     {| oReq | _HixRoutePing( oReq ) }, "GET,OPTIONS" )
   // panel admin: solo si esta habilitado en config (admin.enabled=true)

   IF UConfig( "admin", "enabled", .T. )

      // endpoints admin: protegidos en prod por HIX_AdminCheck()
      HIX_RouteAdd( "hix.status",      HIX_PATH_STATUS,      {| oReq | iif( HIX_AdminCheck( oReq ), oReq:Respond( HIX_MetricsJson(), 200, "json" ), NIL ) },               "GET" )
      HIX_RouteAdd( "hix.bench_start", HIX_PATH_BENCH_START, {| oReq | iif( HIX_AdminCheck( oReq ), _HixSysBenchStart( oReq ), NIL ) },                                  "GET" )
      HIX_RouteAdd( "hix.bench_stop",  HIX_PATH_BENCH_STOP,  {| oReq | iif( HIX_AdminCheck( oReq ), oReq:Respond( '{"bench":"stop","metrics":' + HIX_MetricsJson() + '}', "json" ), NIL ) }, "GET" )
      HIX_RouteAdd( "hix.stop",        HIX_PATH_STOP,        {| oReq | iif( HIX_AdminCheck( oReq ), _HixSysStop( oReq ), NIL ) },                                        "GET" )
      HIX_RouteAdd( "hix.trace",       HIX_PATH_TRACE,       {| oReq | iif( HIX_AdminCheck( oReq ), _HixSysTrace( oReq ), NIL ) },                                       "GET,POST" )
      HIX_RouteAdd( "hix.cache_clear", HIX_PATH_CACHE_CLEAR, {| oReq | iif( HIX_AdminCheck( oReq ), _HixSysCacheClear( oReq ), NIL ) },                                  "GET" )
      HIX_RouteAdd( "hix.monitor",     HIX_PATH_MONITOR,     {| oReq | iif( HIX_AdminCheck( oReq ), _HixSysServeFile( oReq, "html\monitor.html", "html" ), NIL ) },      "GET" )
      HIX_RouteAdd( "hix.index",          HIX_PATH_INDEX,          {| oReq | iif( HIX_AdminCheck( oReq ), _HixSysIndex( oReq ), NIL ) }, "GET" )
      // auth admin: públicas
      HIX_RouteAdd( "hix.login",          HIX_PATH_LOGIN,          {| oReq | _HixRouteLogin( oReq ) },  "GET,POST" )
      HIX_RouteAdd( "hix.logout",         HIX_PATH_LOGOUT,         {| oReq | HIX_AdminLogout( oReq ) }, "GET" )
      HIX_RouteAdd( "hix.setup",          HIX_PATH_SETUP,          {| oReq | _HixRouteSetup( oReq ) },  "GET,POST" )
      // route management API
      HIX_RouteAdd( "hix.routes.add",     HIX_PATH_ROUTES_ADD,     {| oReq | iif( HIX_AdminCheck( oReq ), _HixSysRouteAdd( oReq ),       NIL ) }, "POST" )
      HIX_RouteAdd( "hix.routes.delete",  HIX_PATH_ROUTES_DELETE,  {| oReq | iif( HIX_AdminCheck( oReq ), _HixSysRouteDelete( oReq ),    NIL ) }, "POST" )
      HIX_RouteAdd( "hix.routes.reload",  HIX_PATH_ROUTES_RELOAD,  {| oReq | iif( HIX_AdminCheck( oReq ), _HixSysRouteReload( oReq ),    NIL ) }, "GET"  )
      HIX_RouteAdd( "hix.routes.list",    HIX_PATH_ROUTES_LIST,    {| oReq | iif( HIX_AdminCheck( oReq ), _HixSysRouteList( oReq, .F. ), NIL ) }, "GET" )
      HIX_RouteAdd( "hix.routes.listall", HIX_PATH_ROUTES_LISTALL, {| oReq | iif( HIX_AdminCheck( oReq ), _HixSysRouteList( oReq, .T. ), NIL ) }, "GET" )

   ENDIF

   l( "Router: " + hb_NToS( Len( s_hRoutes ) ) + " rutas sistema registradas" )

RETURN NIL

// HIX_RoutesIsInit — .T. si el router ya está inicializado.
// Usado por THixServer para decidir si encola o despacha directamente.
FUNCTION HIX_RoutesIsInit()
RETURN s_hRoutes != NIL

// ============================================================
// HIX_LoadRoutes — carga/recarga rutas desde <root>/routes/*.json
// Cada JSON es un array de objetos { name, pattern, action,
// method, middleware, scope }. Rutas duplicadas se sobreescriben
// y se listan al final como advertencias.
// Retorna número de rutas cargadas correctamente.
// ============================================================
FUNCTION HIX_LoadRoutes()

   LOCAL oCfg, cRoot, cRoutesDir, aFiles, aFile, cFile, cJson, xData
   LOCAL hRoute, cName, cPattern, cAction, cMethod, cMw, cScope
   LOCAL aErrors, nLoaded, nTotal, lDup, cErr

   aErrors := {}
   nLoaded := 0
   nTotal  := 0

   IF ! HIX_RoutesIsInit()

      HIX_RoutesLoad()

   ENDIF

   cRoot      := UConfig( "paths", "root", "www" )
   cRoutesDir := cRoot + hb_ps() + "routes"

   IF ! hb_vfDirExists( cRoutesDir )

      l( "HIX_LoadRoutes: directorio '" + cRoutesDir + "' no existe — sin rutas JSON" )
      RETURN 0

   ENDIF

   aFiles := hb_vfDirectory( cRoutesDir + hb_ps() + "*.json" )
   l( "HIX_LoadRoutes: " + hb_NToS( Len( aFiles ) ) + " fichero(s) en " + cRoutesDir )

   FOR EACH aFile IN aFiles

      cFile := cRoutesDir + hb_ps() + aFile[ 1 ]
      cJson := hb_MemoRead( cFile )

      IF Empty( cJson )

         lw( "HIX_LoadRoutes: fichero vacio: " + aFile[ 1 ] )
         LOOP

      ENDIF

      xData := NIL
      hb_jsonDecode( cJson, @xData )

      IF ValType( xData ) != "A"

         lw( "HIX_LoadRoutes: JSON invalido en " + aFile[ 1 ] + " (se espera array)" )
         LOOP

      ENDIF

      l( "HIX_LoadRoutes: [FILE] " + aFile[ 1 ] + " (" + hb_NToS( Len( xData ) ) + " rutas)" )
      _HixRouteSetSource( aFile[ 1 ] )

      FOR EACH hRoute IN xData

         IF ValType( hRoute ) != "H"

            lw( "HIX_LoadRoutes: [SKIP] entrada no es hash en " + aFile[ 1 ] )
            LOOP

         ENDIF

         cName    := _HGet( hRoute, "name",       "" )
         cPattern := _HGet( hRoute, "url",        "" )

         IF Empty( cPattern )

            cPattern := _HGet( hRoute, "pattern", "" )

         ENDIF

         cAction  := _HGet( hRoute, "action",     "" )
         cMethod  := _HGet( hRoute, "method",     "*" )
         cMw      := _HGet( hRoute, "middleware", "" )
         cScope   := _HGet( hRoute, "scope",      "" )

         nTotal++

         // Reservado: nombres hix.* son exclusivos del sistema

         IF Left( Lower( cName ), 4 ) == "hix."

            lw( "HIX_LoadRoutes: nombre reservado '" + cName + "' en " + aFile[ 1 ] + " — ignorado" )
            LOOP

         ENDIF

         // Detectar duplicado antes de registrar
         hb_mutexLock( s_mtxRoutes )
         lDup := hb_HHasKey( s_hRoutes, cName )
         hb_mutexUnlock( s_mtxRoutes )

         IF lDup

            AAdd( aErrors, "'" + cName + "' (" + cPattern + ") en " + aFile[ 1 ] )

         ENDIF

         l( "HIX_LoadRoutes: [ROUTE] " + PadR( cName, 32 ) + PadR( cMethod, 20 ) + cPattern + ;
            iif( Empty( cAction ), "", " -> " + cAction ) )

         IF HIX_RouteAdd( cName, cPattern, cAction, cMethod, cMw, cScope, NIL, .T. )

            nLoaded++

         ENDIF

      NEXT

   NEXT

   _HixRouteSetSource( "" )

   // Resumen de duplicados al final

   IF ! Empty( aErrors )

      lw( "HIX_LoadRoutes: Rutas duplicadas redefinidas (" + hb_NToS( Len( aErrors ) ) + "):" )

      FOR EACH cErr IN aErrors

         lw( "  DUPLICADO: " + cErr )

      NEXT

   ENDIF

   l( "HIX_LoadRoutes: " + hb_NToS( nLoaded ) + "/" + hb_NToS( nTotal ) + " rutas cargadas" )

RETURN nLoaded

// ============================================================
// HIX_RouteAdd — registra una ruta.
// cName    : identificador lógico único ("user.detail")
// cPattern : URL con :vars o regex directa ("/users/:id")
// bAction  : codeblock {|oReq|} o nombre de función (string)
// cMethod  : "GET" | "GET,POST" | "*" (default: "*")
// cMw      : nombre de función middleware — un solo nombre (opcional)
// cScope   : string libre pasado al contexto (opcional)
// uCargo   : dato libre pasado junto con hParams (opcional)
// lReplace : .T. sobreescribe si ya existe (default: .F. → retorna .F.)
// ============================================================
FUNCTION HIX_RouteAdd( cName, cPattern, bAction, cMethod, cMw, cScope, uCargo, lReplace )

   LOCAL cRegexp, aVarNames := {}, pCompiled, nScore, cBootCargo

   hb_default( @cMethod,  "*"  )
   hb_default( @cMw,      ""   )
   hb_default( @cScope,   ""   )
   hb_default( @uCargo,   NIL  )
   hb_default( @lReplace, .F.  )

   IF Empty( cName )

      le( "HIX_RouteAdd: route name is NIL or empty — ignored" )
      RETURN .F.

   ENDIF

   IF Empty( cPattern )

      le( "HIX_RouteAdd: pattern is NIL or empty for route '" + cName + "' — ignored" )
      RETURN .F.

   ENDIF

   cMethod := Upper( cMethod )

   // Normalizar método y añadir OPTIONS para CORS preflight

   IF cMethod == "*"

      cMethod := "GET,POST,PUT,DELETE,OPTIONS"
   ELSEIF ! "OPTIONS" $ cMethod
      cMethod += ",OPTIONS"

   ENDIF

   // Asegurar que el patrón empiece por /

   IF Left( cPattern, 1 ) != "/"

      cPattern := "/" + cPattern

   ENDIF

   // Convertir :vars a grupos regex y recoger nombres
   cRegexp := _HixPatternToRegexp( cPattern, @aVarNames )

   // Compilar regexp
   pCompiled := hb_regexComp( "^" + cRegexp + "$" )

   IF pCompiled == NIL

      lw( "HIX_RouteAdd: regexp inválida para '" + cName + "': " + cPattern )
      RETURN .F.

   ENDIF

   nScore := _HixRouteScore( cPattern )

   hb_mutexLock( s_mtxRoutes )

   IF hb_HHasKey( s_hRoutes, cName )

      IF ! lReplace

         hb_mutexUnlock( s_mtxRoutes )
         le( "Duplicate route name '" + cName + "' — ignored" )
         RETURN .F.

      ENDIF

      ld( "Ruta reemplazada: " + cName )
      _HixOrderRemove( cName )

   ENDIF

   s_hRoutes[ cName ] := { ;
      "pattern"    => cPattern,  ;
      "regexp"     => pCompiled, ;
      "action"     => bAction,   ;
      "method"     => cMethod,   ;
      "middleware" => cMw,       ;
      "scope"      => cScope,    ;
      "cargo"      => uCargo,    ;
      "varnames"   => aVarNames, ;
      "score"      => nScore     ;
      }
   _HixOrderInsert( cName, nScore )
   hb_mutexUnlock( s_mtxRoutes )

   // Skip rutas de sistema (hix.*) en el bootlog

   IF Left( Lower( cName ), 4 ) != "hix."

      cBootCargo := "type:" + ;
         iif( Empty( s_cRouteSource ), ;
         "compiled", ;
         "file[" + s_cRouteSource + "]" ) + ;
         ", route=[" + cPattern + "]" + ;
         ", method[" + cMethod + "]" + ;
         ", context:[" + cScope + "]"
      HIX_BootLogAdd( "routes", "init", .T., cName, cBootCargo )

   ENDIF

   ld( "Ruta registrada: [" + cMethod + "] " + cPattern + " → " + cName )

RETURN .T.

// Shortcuts eliminados — usar oServer:AddRouteGet/Post/Put/Delete()

// ============================================================
// HIX_RoutesSnapshot / HIX_RoutesRestore — for in-process test isolation.
// Snapshot clones the live route hash; restore replaces it.
// Both are mutex-protected.
// ============================================================
FUNCTION HIX_RoutesSnapshot()

   LOCAL hSnap

   hb_mutexLock( s_mtxRoutes )
   hSnap := { "routes" => hb_HClone( s_hRoutes ), "order" => AClone( s_aRouteOrder ) }
   hb_mutexUnlock( s_mtxRoutes )

RETURN hSnap

FUNCTION HIX_RoutesRestore( hSnap )

   hb_mutexLock( s_mtxRoutes )
   s_hRoutes    := hSnap[ "routes" ]
   s_aRouteOrder := hSnap[ "order" ]
   hb_mutexUnlock( s_mtxRoutes )

RETURN NIL

// HIX_RouteDelete — elimina una ruta en caliente.
// ============================================================
FUNCTION HIX_RouteDelete( cName )

   hb_mutexLock( s_mtxRoutes )

   IF hb_HHasKey( s_hRoutes, cName )

      hb_HDel( s_hRoutes, cName )
      _HixOrderRemove( cName )
      ld( "Ruta eliminada: " + cName )

   ENDIF

   hb_mutexUnlock( s_mtxRoutes )

RETURN NIL

// ============================================================
// HIX_RouteList — devuelve array de hashes para debug/monitor.
// ============================================================
FUNCTION HIX_RouteList()

   LOCAL aResult := {}, cName, hRoute, hItem
   LOCAL hRoutes

   // Router no inicializado (sin HIX_RoutesLoad() ni THixServer:Start()):
   // s_hRoutes y s_mtxRoutes siguen a NIL y hb_mutexLock()/hb_HKeys()
   // abortarian con "Argument error". Coherente con el resto de la API
   // publica del router, que ya comprueba HIX_RoutesIsInit().
   IF s_hRoutes == NIL

      RETURN aResult

   ENDIF

   hb_mutexLock( s_mtxRoutes )
   hRoutes := s_hRoutes
   hb_mutexUnlock( s_mtxRoutes )

   FOR EACH cName IN hb_HKeys( hRoutes )

      hRoute := hRoutes[ cName ]
      hItem  := { ;
         "name"    => cName,                              ;
         "pattern" => hRoute[ "pattern" ],                  ;
         "method"  => hRoute[ "method" ],                   ;
         "scope"   => hRoute[ "scope" ],                    ;
         "cargo"   => hb_HGetDef( hRoute, "cargo", NIL ) ;
         }
      AAdd( aResult, hItem )

   NEXT

RETURN aResult

// ============================================================
// HIX_RouteGroup — helper de agrupación sin magia.
// cPrefix     : prefijo de URL para todas las rutas del grupo
// cScope      : scope común (se aplica si la ruta no define uno)
// cMiddleware : middleware común (se prepende al de la ruta)
// bBlock      : codeblock {|oServer|} — recibe el objeto servidor
// oServer     : instancia THixServer pasada al bloque (puede ser NIL)
//
// Dentro de bBlock usar oServer:AddRoute*(). El grupo aplica
// prefijo + defaults a todas las rutas registradas dentro.
// ============================================================
FUNCTION HIX_RouteGroup( cPrefix, cMw, cScope, bBlock, oServer )

   LOCAL hOldRoutes, cName, hRoute, cNewPattern
   LOCAL aAdded := {}

   hb_default( @cPrefix, "" )
   hb_default( @cMw,     "" )
   hb_default( @cScope,  "" )

   // Snapshot antes del bloque para detectar rutas nuevas
   hb_mutexLock( s_mtxRoutes )
   hOldRoutes := hb_HClone( s_hRoutes )
   hb_mutexUnlock( s_mtxRoutes )

   Eval( bBlock, oServer )

   // Post-procesar rutas añadidas por el bloque
   hb_mutexLock( s_mtxRoutes )

   FOR EACH cName IN hb_HKeys( s_hRoutes )

      IF ! hb_HHasKey( hOldRoutes, cName )

         hRoute := s_hRoutes[ cName ]

         // Aplicar prefijo

         IF ! Empty( cPrefix )

            cNewPattern := cPrefix + hRoute[ "pattern" ]
            hRoute[ "pattern" ] := cNewPattern
            hRoute[ "regexp" ]  := hb_regexComp( "^" + _HixPatternToRegexp( cNewPattern, @hRoute[ "varnames" ] ) + "$" )

         ENDIF

         // Aplicar scope por defecto

         IF Empty( hRoute[ "scope" ] ) .AND. ! Empty( cScope )

            hRoute[ "scope" ] := cScope

         ENDIF

         // Aplicar middleware por defecto si la ruta no tiene

         IF Empty( hRoute[ "middleware" ] ) .AND. ! Empty( cMw )

            hRoute[ "middleware" ] := cMw

         ENDIF

         s_hRoutes[ cName ] := hRoute

      ENDIF

   NEXT

   hb_mutexUnlock( s_mtxRoutes )

RETURN NIL

// ============================================================
// HIX_RouteSetHandler — registra handler de error.
// cEvent : "404" | "405"
// bAction: codeblock {|oReq [, cAllowed]|}
// ============================================================
FUNCTION HIX_RouteSetHandler( cEvent, bAction )

   IF bAction == NIL

      IF hb_HHasKey( s_hHandlers, cEvent )

         hb_HDel( s_hHandlers, cEvent )

      ENDIF

   ELSE
      s_hHandlers[ cEvent ] := bAction
      ld( "Handler registrado: " + cEvent )

   ENDIF

RETURN NIL

// ============================================================
// HIX_RouteDispatch — punto de entrada principal desde el worker.
// Busca la ruta, ejecuta middleware y action.
// Gestiona 404/405 automáticamente.
// ============================================================
FUNCTION HIX_RouteDispatch( oReq )

   LOCAL hRoutes, aOrder, cName, hRoute, aMatches, hParams
   LOCAL lPathFound := .F., cAllowedMethods := ""

   hb_mutexLock( s_mtxRoutes )
   hRoutes := hb_HClone( s_hRoutes )
   aOrder  := AClone( s_aRouteOrder )
   hb_mutexUnlock( s_mtxRoutes )

   FOR EACH cName IN aOrder

      hRoute   := hRoutes[ cName ]
      aMatches := hb_regex( hRoute[ "regexp" ], oReq:cPath )

      IF ! Empty( aMatches )

         lPathFound := .T.

         IF _HixMethodAllowed( hRoute[ "method" ], oReq:cMethod )

            hParams := _HixBuildParams( hRoute[ "varnames" ], aMatches )

            IF ! _HixRunMiddleware( hRoute[ "middleware" ], hRoute[ "scope" ], oReq )

               RETURN .T.  // middleware cortó la cadena

            ENDIF

            _HixEvalAction( hRoute[ "action" ], oReq, hParams, cName )
            RETURN .T.
         ELSE
            // Acumular métodos permitidos para 405
            cAllowedMethods += iif( Empty( cAllowedMethods ), "", "," ) + hRoute[ "method" ]

         ENDIF

      ENDIF

   NEXT

   // 404 o 405

   IF lPathFound

      IF hb_HHasKey( s_hHandlers, "405" )

         HIX_SetRequest( oReq )
         HIX_SetContext( NIL )
         Eval( s_hHandlers[ "405" ], oReq, cAllowedMethods )
         IF ! oReq:lResponded .AND. ! Empty( oReq:cEchoBuffer )
            oReq:Respond( oReq:cEchoBuffer, oReq:nResponseStatus, oReq:cResponseMime )
            HIX_EchoClear()
         ENDIF
      ELSE
         oReq:lKeepAlive := .F.
         HIX_HttpError( oReq, 405, cAllowedMethods )

      ENDIF

   ELSE

      IF hb_HHasKey( s_hHandlers, "404" )

         HIX_SetRequest( oReq )
         HIX_SetContext( NIL )
         Eval( s_hHandlers[ "404" ], oReq )
         IF ! oReq:lResponded .AND. ! Empty( oReq:cEchoBuffer )
            oReq:Respond( oReq:cEchoBuffer, oReq:nResponseStatus, oReq:cResponseMime )
            HIX_EchoClear()
         ENDIF

      ELSEIF oReq:cPath == "/"

         HIX_SetRequest( oReq )
         oReq:Respond( HIX_HelloPage(), 200, "html" )

      ELSE
         oReq:lKeepAlive := .F.
         HIX_HttpError( oReq, 404 )

      ENDIF

   ENDIF

RETURN .T.

// ============================================================
// Helpers privados
// ============================================================

// Case-insensitive hash lookup — hb_jsonDecode may uppercase keys
// URoute( cName, param1, param2, ... ) — genera URL a partir del nombre de ruta
// Reemplaza los placeholders :param en orden con los argumentos recibidos.
// Valores no-string se convierten con UStr().
FUNCTION URoute( cName, ... )

   LOCAL hRoute, cUrl, i, nPos, nEnd
   LOCAL aAll  := hb_AParams()
   LOCAL aArgs := {}
   LOCAL j

   FOR j := 2 TO Len( aAll )

      AAdd( aArgs, aAll[ j ] )

   NEXT

   IF s_hRoutes == NIL .OR. ! hb_HHasKey( s_hRoutes, cName )

      lw( "URoute: ruta '" + cName + "' no encontrada" )
      RETURN ""

   ENDIF

   cUrl := s_hRoutes[ cName ][ "pattern" ]

   IF Len( aArgs ) < Len( s_hRoutes[ cName ][ "varnames" ] )

      lw( "URoute: ruta '" + cName + "' requiere " + ;
         hb_NToS( Len( s_hRoutes[ cName ][ "varnames" ] ) ) + " parámetro(s)" )
      RETURN ""

   ENDIF

   FOR i := 1 TO Len( aArgs )

      nPos := At( ":", cUrl )

      IF nPos == 0

         EXIT

      ENDIF

      nEnd := nPos

      DO WHILE nEnd < Len( cUrl ) .AND. SubStr( cUrl, nEnd + 1, 1 ) != "/"

         nEnd++

      ENDDO

      cUrl := Left( cUrl, nPos - 1 ) + UStr( aArgs[ i ] ) + SubStr( cUrl, nEnd + 1 )

   NEXT

RETURN cUrl

STATIC FUNCTION _HGet( h, cKey, xDef )

   LOCAL cK

   cKey := Lower( cKey )

   FOR EACH cK IN hb_HKeys( h )

      IF Lower( cK ) == cKey

         RETURN h[ cK ]

      ENDIF

   NEXT

RETURN xDef

// Convierte patrón con :vars a regexp y extrae nombres de variables
STATIC FUNCTION _HixPatternToRegexp( cPattern, aVarNames )

   LOCAL cResult := "", nPos := 1, nEnd, nClose, c, cVarName, lOptional, cConstraint

   aVarNames := {}

   DO WHILE nPos <= Len( cPattern )

      c := SubStr( cPattern, nPos, 1 )

      IF c == ":"

         nEnd := nPos + 1

         DO WHILE nEnd <= Len( cPattern )

            c := SubStr( cPattern, nEnd, 1 )

            IF ( c >= "a" .AND. c <= "z" ) .OR. ( c >= "A" .AND. c <= "Z" ) .OR. ;
                  ( c >= "0" .AND. c <= "9" ) .OR. c == "_"

               nEnd++
            ELSE
               EXIT

            ENDIF

         ENDDO

         cVarName    := SubStr( cPattern, nPos + 1, nEnd - nPos - 1 )
         cConstraint := "[^/]+"

         IF SubStr( cPattern, nEnd, 1 ) == "("

            nClose := hb_At( ")", cPattern, nEnd + 1 )

            IF nClose > nEnd

               cConstraint := SubStr( cPattern, nEnd + 1, nClose - nEnd - 1 )
               nEnd := nClose + 1

            ENDIF

         ENDIF

         lOptional := ( SubStr( cPattern, nEnd, 1 ) == "!" )

         IF lOptional

            IF Right( cResult, 1 ) == "/"

               cResult := Left( cResult, Len( cResult ) - 1 )

            ENDIF

            cResult += "(?:/(" + cConstraint + "))?/?"
            nEnd++
         ELSE
            cResult += "(" + cConstraint + ")"

         ENDIF

         AAdd( aVarNames, cVarName )
         nPos := nEnd
      ELSE
         cResult += c
         nPos++

      ENDIF

   ENDDO

RETURN cResult

// Comprueba si cMethod está permitido en cAllowed (comma-separated)
STATIC FUNCTION _HixMethodAllowed( cAllowed, cMethod )

   LOCAL aMethods := hb_ATokens( cAllowed, "," ), cM

   FOR EACH cM IN aMethods

      IF Upper( AllTrim( cM ) ) == Upper( AllTrim( cMethod ) )

         RETURN .T.

      ENDIF

   NEXT

RETURN .F.

// Construye hash de parámetros desde grupos regex.
// _N solo para grupos sin nombre (regex pura); :var siempre por nombre.
STATIC FUNCTION _HixBuildParams( aVarNames, aMatches )

   LOCAL hParams := { => }, i

   FOR i := 2 TO Len( aMatches )

      IF ( i - 1 ) > Len( aVarNames ) .OR. Empty( aVarNames[ i - 1 ] )

         hParams[ "_" + hb_NToS( i - 1 ) ] := iif( aMatches[ i ] == NIL, "", aMatches[ i ] )

      ENDIF

   NEXT

   FOR i := 1 TO Len( aVarNames )

      IF i + 1 <= Len( aMatches )

         hParams[ aVarNames[ i ] ] := iif( aMatches[ i + 1 ] == NIL, "", aMatches[ i + 1 ] )
      ELSE
         hParams[ aVarNames[ i ] ] := ""

      ENDIF

   NEXT

RETURN hParams

// Calls the middleware function for the route. Returns .F. if it cuts the chain.
// If MW returned .F. and did not respond: dispatch cOnFail route or send 403.
STATIC FUNCTION _HixRunMiddleware( cMw, cScope, oReq )

   LOCAL oCtx, oMw, lOk

   oCtx := THixContext():New( oReq, cMw, cScope )
   HIX_SetContext( oCtx )
   HIX_SetRequest( oReq )
   oReq:hData[ "_ctx" ] := oCtx

   IF Empty( cMw )

      RETURN .T.

   ENDIF

   oMw := UMiddleware():New( cMw, cMw )
   lOk := oMw:Run( oCtx )

   IF ! lOk .AND. ! oCtx:lHandled

      IF ! Empty( oCtx:cOnFail )

         _HixDispatchOnFail( oReq, oCtx:cOnFail )
      ELSE
         HIX_HttpError( oReq, 403 )

      ENDIF

   ELSEIF ! lOk .AND. oCtx:lHandled

      // Short-circuit flush: middleware wrote to the echo buffer via
      // USend*/HIX_Echo and cut the chain (RETURN .F.). _HixEvalAction
      // never runs, so mirror its final flush here to guarantee the
      // client receives the response.
      IF ! oReq:lResponded .AND. ! Empty( oReq:cEchoBuffer )

         oReq:Respond( oReq:cEchoBuffer, oReq:nResponseStatus, oReq:cResponseMime )
         HIX_EchoClear()

      ENDIF

   ENDIF

RETURN lOk

// Dispatches the cOnFail route using the same request object.
// The original headers, query params, and body remain accessible to the handler.
STATIC FUNCTION _HixDispatchOnFail( oReq, cOnFail )

   LOCAL cRoot

   cRoot := UConfig( "paths", "root", "www" )

   IF s_oRouteDisp == NIL

      s_oRouteDisp := THixDispatcher():New( cRoot )

   ENDIF

   oReq:cPath := cOnFail
   s_oRouteDisp:Dispatch( oReq )

RETURN NIL

// Evalúa la action: codeblock, nombre de función (string) o ruta de fichero
STATIC FUNCTION _HixEvalAction( bAction, oReq, hParams, cRouteName )

   LOCAL bFunc, cExt, cRoot, cPhysical, xResult, cPath
   LOCAL hClass, cFileName, nAt, cDir, cFileSpec

   hb_default( @cRouteName, "" )
   oReq:hParam          := hParams
   oReq:hData[ "_ctx" ] := HIX_GetContext()
   HIX_SetRequest( oReq )

   TRY

      IF ValType( bAction ) == "B"

         xResult := Eval( bAction, oReq )

         IF ! oReq:lResponded .AND. Empty( oReq:cEchoBuffer ) .AND. xResult != NIL

            // HIX_EchoAdd( hb_CStr( xResult ) )
            HIX_Echo( UStr( xResult ) )

         ENDIF

      ELSEIF ValType( bAction ) == "C" .AND. ! Empty( bAction )
         cExt := Lower( hb_FNameExt( bAction ) )

         IF ! Empty( cExt )

            // File path action — dispatch via extension
            cRoot := UConfig( "paths", "root", "www" )

            IF s_oRouteDisp == NIL

               s_oRouteDisp := THixDispatcher():New( cRoot )

            ENDIF

            // Parse method@class.prg notation (e.g. "controllers/index@customer.prg")
            cFileName := hb_FNameNameExt( bAction )
            nAt       := At( "@", cFileName )
            hClass    := NIL
            cFileSpec := bAction

            IF nAt > 0

               cDir             := hb_FNameDir( bAction )
               hClass           := { => }
               hClass[ "method" ] := Lower( Left( cFileName, nAt - 1 ) )
               hClass[ "class" ]  := hb_FNameName( SubStr( cFileName, nAt + 1 ) )
               cFileSpec        := cDir + SubStr( cFileName, nAt + 1 )
               cExt             := Lower( hb_FNameExt( cFileSpec ) )

            ENDIF

            cPhysical := s_oRouteDisp:cRoot + hb_ps() + hb_DirSepToOS( cFileSpec )

            IF ! hb_FileExists( cPhysical )

               lw( "Route action file not found: '" + cPhysical + "' in route '" + cRouteName + "'" )
               HIX_Throw( HIX_NewError( ;
                  "File not found in route '" + cRouteName + "'", ;
                  "Router", 500, "EvalAction" ) )

            ENDIF

            DO CASE

               CASE cExt == ".view"

                  cPath := hb_DirSepToOS( bAction )

               IF Left( cPath, 1 ) != '/' .AND. Left( cPath, 1 ) != '\'

                  cPath := hb_ps() + cPath

                  ENDIF

                  USendHtml( s_oRouteDisp:ExecuteView( cPath ) )     // Cura !!! cPath !

               CASE cExt == ".html" .OR. cExt == ".htm"
                  USendHtml( s_oRouteDisp:ExecuteHtml( cPhysical ) )
               CASE cExt == ".prg"
                  xResult := s_oRouteDisp:ExecutePrg( cPhysical, oReq, hClass )

               IF ! oReq:lResponded .AND. ! Empty( xResult )

                  USendHtml( xResult )

                  ENDIF

               CASE cExt == ".hrb"
                  xResult := s_oRouteDisp:ExecuteHrb( cPhysical )

               IF ! oReq:lResponded .AND. ! Empty( xResult )

                  USendHtml( xResult )

                  ENDIF

               OTHERWISE
                  s_oRouteDisp:ExecuteFile( cPhysical )

            ENDCASE

         ELSE
            // Sin extensión: si contiene separador de path es una ruta inválida

            IF "/" $ bAction .OR. "\" $ bAction

               lw( "Invalid route action (missing extension): '" + bAction + "' in route '" + cRouteName + "'" )
               HIX_Throw( HIX_NewError( ;
                  "Invalid route action '" + bAction + "' (missing extension) in route '" + cRouteName + "'", ;
                  "Router", 500, "EvalAction" ) )
            ELSE
               bFunc := &( "{|o|" + bAction + "(o)}" )
               Eval( bFunc, oReq )

            ENDIF

         ENDIF

      ENDIF

      FINALLY
      // Cierra areas DBF incluso si la ejecucion aborto por excepcion.
      HIX_CloseDbfAreas()

   END

   IF oReq:lStreaming

      IF ! Empty( oReq:cEchoBuffer )

         oReq:RespondChunk( oReq:cEchoBuffer )

      ENDIF

      oReq:RespondEnd()
      HIX_EchoClear()
   ELSEIF ! oReq:lResponded .AND. ! Empty( oReq:cEchoBuffer )
      oReq:Respond( oReq:cEchoBuffer, oReq:nResponseStatus, oReq:cResponseMime )
      HIX_EchoClear()

   ENDIF

RETURN NIL

// ============================================================
// Handlers internos de rutas del sistema
// ============================================================

STATIC FUNCTION _HixSysBenchStart( oReq )

   l( "=== BENCH START ===" )
   HIX_MetricsReset()
   oReq:Respond( { "bench" => "start" } )

RETURN NIL

STATIC FUNCTION _HixSysStop( oReq )

   oReq:lKeepAlive := .F.
   oReq:Respond( { "status" => "stopping" } )
   HIX_ServerRequestStop()

RETURN NIL

STATIC FUNCTION _HixSysTrace( oReq )

   LOCAL cMod, lOn, hState, cKey, cJson, lFirst

   cMod := oReq:QueryParam( "mod" )

   IF ! Empty( cMod )

      lOn := oReq:QueryParam( "on", "1" ) == "1"

      IF cMod == "all"

         HIX_TraceAll( lOn )
      ELSE
         HIX_TraceSet( cMod, lOn )

      ENDIF

   ENDIF

   hState := HIX_TraceGetAll()
   cJson  := "{"
   lFirst := .T.

   FOR EACH cKey IN hb_HKeys( hState )

      IF ! lFirst ; cJson += "," ; ENDIF

      cJson += Chr( 34 ) + cKey + Chr( 34 ) + ":" + iif( hState[ cKey ], "true", "false" )
      lFirst := .F.

   NEXT

   cJson += "}"
   oReq:Respond( cJson, 200, "json" )

RETURN NIL

STATIC FUNCTION _HixSysServeFile( oReq, cRelPath, cMime )

   LOCAL cBody := hb_MemoRead( hb_DirBase() + cRelPath )

   IF Empty( cBody )

      oReq:Respond( { "error" => _( 'ERR_FILE_NOT_FOUND' ) }, 404 )
   ELSE
      oReq:Respond( cBody, cMime )

   ENDIF

RETURN NIL

STATIC FUNCTION _HixSysCacheClear( oReq )

   LOCAL cRoot, nDeleted

   cRoot    := hb_DirBase() + ".cached" + hb_ps() + "views"
   nDeleted := _HixCacheDeleteDir( cRoot )
   l( "Cache clear: " + hb_NToS( nDeleted ) + " ficheros eliminados" )
   oReq:Respond( { "status" => "ok", "deleted" => nDeleted, "path" => cRoot } )

RETURN NIL

STATIC FUNCTION _HixCacheDeleteDir( cDir )

   LOCAL aItems, aItem, nCount := 0, cFull, cExt, cName

   aItems := hb_vfDirectory( cDir + hb_ps() + "*", "D" )

   FOR EACH aItem IN aItems

      cName := aItem[ 1 ]   // F_NAME
      cFull := cDir + hb_ps() + cName

      IF "D" $ aItem[ 5 ]   // F_ATTR

         IF cName != "." .AND. cName != ".."

            nCount += _HixCacheDeleteDir( cFull )

         ENDIF

      ELSE
         cExt := Lower( hb_FNameExt( cName ) )

         IF cExt == ".hrb" .OR. ( cExt == ".prg" .AND. Left( cName, 2 ) == "__" )

            hb_vfErase( cFull )
            nCount++

         ENDIF

      ENDIF

   NEXT

RETURN nCount

// ============================================================
// /hix-ping — health endpoint with baked-in CORS wildcard so
// browser tools (load testers, dashboards) hosted on any origin
// can reach it without extra middleware config. Also answers the
// OPTIONS preflight so custom-header requests work.
// ============================================================

STATIC FUNCTION _HixRoutePing( oReq )

   LOCAL hHeaders := { ;
      "Access-Control-Allow-Origin"  => "*", ;
      "Access-Control-Allow-Methods" => "GET,OPTIONS", ;
      "Access-Control-Allow-Headers" => "Content-Type,Accept,Authorization" }

   IF oReq:cMethod == "OPTIONS"
      oReq:Respond( "", 204, NIL, hHeaders )
   ELSE
      oReq:Respond( ;
         { "status" => "ok", "server" => "HIX/" + HIX_Version(), "now" => hb_TToS( hb_DateTime() ) }, ;
         200, NIL, hHeaders )
   ENDIF

RETURN NIL

// ============================================================
// Dispatchers GET/POST para rutas de auth admin
// ============================================================

STATIC FUNCTION _HixRouteLogin( oReq )

   IF oReq:cMethod == "POST"

      HIX_AdminLoginPost( oReq )
   ELSE
      HIX_AdminLoginGet( oReq )

   ENDIF

RETURN NIL

STATIC FUNCTION _HixRouteSetup( oReq )

   IF oReq:cMethod == "POST"

      HIX_AdminSetupPost( oReq )
   ELSE
      HIX_AdminSetupGet( oReq )

   ENDIF

RETURN NIL

// ============================================================
// _HixSysIndex — GET /hix-index
// Página admin con listado de todas las rutas registradas.
// ============================================================
STATIC FUNCTION _HixSysIndex( oReq )

   LOCAL aRoutes := HIX_RouteList()
   LOCAL hRoute, cRows := "", cMethods, cPattern, cName, lHasGet, cBadge, cAction
   LOCAL cEol := Chr( 10 )

   FOR EACH hRoute IN aRoutes

      cName    := hRoute[ "name" ]
      cPattern := hRoute[ "pattern" ]
      cMethods := hRoute[ "method" ]
      // Quitar OPTIONS (siempre auto-añadido, no interesa mostrarlo)
      cMethods := StrTran( cMethods, ",OPTIONS", "" )
      cMethods := StrTran( cMethods, "OPTIONS,", "" )
      cMethods := StrTran( cMethods, "OPTIONS",  "" )

      lHasGet  := "GET" $ Upper( cMethods )
      cBadge   := _HixMethodBadges( cMethods )
      cAction  := iif( lHasGet, "<a href='" + UHtmlEncode( cPattern ) + "' target='_blank' class='btn'>Open</a>", "<span class='na'>—</span>" )

      cRows += "<tr>" + ;
         "<td class='name'>" + UHtmlEncode( cName ) + "</td>" + ;
         "<td>" + cBadge + "</td>" + ;
         "<td class='pat'>" + UHtmlEncode( cPattern ) + "</td>" + ;
         "<td>" + cAction + "</td>" + ;
         "</tr>" + cEol

   NEXT

   oReq:Respond( _HixIndexPage( cRows, Len( aRoutes ) ), 200, "html" )

RETURN NIL

STATIC FUNCTION _HixMethodBadges( cMethods )

   LOCAL aMethods := hb_ATokens( cMethods, "," ), cM, cOut := ""
   LOCAL hColors := { "GET" => "#38a169", "POST" => "#3182ce", "PUT" => "#d69e2e", ;
      "DELETE" => "#e53e3e", "PATCH" => "#805ad5" }
   LOCAL cColor

   FOR EACH cM IN aMethods

      cM := AllTrim( cM )

      IF Empty( cM ) ; LOOP ; ENDIF

      cColor := iif( hb_HHasKey( hColors, Upper( cM ) ), hColors[ Upper( cM ) ], "#718096" )
      cOut += "<span class='badge' style='background:" + cColor + "'>" + UHtmlEncode( cM ) + "</span>"

   NEXT

RETURN cOut

// ============================================================
// Handlers de la API de gestión de rutas
// ============================================================

// POST /hix-routes/add — body JSON con definición de ruta.
// Retorna {"ok":false} si la ruta ya existe (no sobreescribe).
STATIC FUNCTION _HixSysRouteAdd( oReq )

   LOCAL hBody, cName, cPattern, cAction, cMethod, cMw, cScope, lOk

   hBody := oReq:JsonBody()

   IF ValType( hBody ) != "H"

      oReq:Respond( { "ok" => .F., "error" => "invalid JSON body" }, 400 )
      RETURN NIL

   ENDIF

   cName    := _HGet( hBody, "name",       "" )
   cPattern := _HGet( hBody, "url",        "" )

   IF Empty( cPattern )

      cPattern := _HGet( hBody, "pattern", "" )

   ENDIF

   cAction  := _HGet( hBody, "action",     "" )
   cMethod  := _HGet( hBody, "method",     "*" )
   cMw      := _HGet( hBody, "middleware", "" )
   cScope   := _HGet( hBody, "scope",      "" )

   // Reservado: nombres hix.* son exclusivos del sistema

   IF Left( Lower( cName ), 4 ) == "hix."

      oReq:Respond( { "ok" => .F., "error" => "reserved name — hix.* is for system routes", "name" => cName }, 400 )
      RETURN NIL

   ENDIF

   // lReplace=.F. (default): retorna .F. si ya existe
   lOk := HIX_RouteAdd( cName, cPattern, cAction, cMethod, cMw, cScope )

   IF lOk

      oReq:Respond( { "ok" => .T., "name" => cName } )
   ELSE
      oReq:Respond( { "ok" => .F., "error" => "duplicate or invalid route", "name" => cName }, 409 )

   ENDIF

RETURN NIL

// POST /hix-routes/delete — body JSON { "name": "route.name" }.
STATIC FUNCTION _HixSysRouteDelete( oReq )

   LOCAL hBody, cName

   hBody := oReq:JsonBody()

   IF ValType( hBody ) != "H"

      oReq:Respond( { "ok" => .F., "error" => "invalid JSON body" }, 400 )
      RETURN NIL

   ENDIF

   cName := _HGet( hBody, "name", "" )

   IF Empty( cName )

      oReq:Respond( { "ok" => .F., "error" => "name required" }, 400 )
      RETURN NIL

   ENDIF

   HIX_RouteDelete( cName )
   oReq:Respond( { "ok" => .T., "name" => cName } )

RETURN NIL

// GET /hix-routes/reload — borra rutas de aplicación y recarga routes/*.json.
STATIC FUNCTION _HixSysRouteReload( oReq )

   LOCAL nLoaded, cName, aDeleted

   // Recoger nombres de rutas de aplicacion (sin hix.*)
   hb_mutexLock( s_mtxRoutes )
   aDeleted := {}

   FOR EACH cName IN hb_HKeys( s_hRoutes )

      IF !( Left( cName, 4 ) == "hix." )

         AAdd( aDeleted, cName )

      ENDIF

   NEXT

   // Borrar en el hash original (no reemplazar el puntero) y sincronizar order array

   FOR EACH cName IN aDeleted

      hb_HDel( s_hRoutes, cName )
      _HixOrderRemove( cName )

   NEXT

   hb_mutexUnlock( s_mtxRoutes )

   nLoaded := HIX_LoadRoutes()

   oReq:Respond( { ;
      "ok"            => .T.,           ;
      "total_deleted" => Len( aDeleted ), ;
      "total_loaded"  => nLoaded         ;
      } )

RETURN NIL

// GET /hix-routes/list    — solo rutas de aplicación (sin prefijo sys.)
// GET /hix-routes/listall — todas las rutas incluidas las de sistema
STATIC FUNCTION _HixSysRouteList( oReq, lAll )

   LOCAL cHtml := '', cLine, aNames, cName, hRoute
   LOCAL cAction, cMethod, cMw, cTitle
   LOCAL cEol := Chr( 10 )

   hb_default( @lAll, .F. )

   aNames := {}

   FOR EACH cName IN hb_HKeys( s_hRoutes )

      IF lAll .OR. !( Left( cName, 4 ) == "hix." )

         AAdd( aNames, cName )

      ENDIF

   NEXT

   ASort( aNames )

   cTitle := iif( lAll, "HIX Routes — All", "HIX Routes — Application" )

   cLine := PadR( "NAME", 32 ) + PadR( "METHOD", 12 ) + PadR( "PATTERN", 36 ) + PadR( "MIDDLEWARE", 20 ) + "ACTION" + cEol
   cLine += Replicate( "-", 120 ) + cEol

   FOR EACH cName IN aNames

      hRoute  := s_hRoutes[ cName ]
      cMethod := hb_HGetDef( hRoute, "method",     "*"  )
      cAction := hb_HGetDef( hRoute, "action",     ""   )
      cMw     := hb_HGetDef( hRoute, "middleware", ""   )

      IF ValType( cAction ) != "C" ; cAction := "{codeblock}" ; ENDIF

      cLine += PadR( cName,              32 ) + ;
         PadR( cMethod,            12 ) + ;
         PadR( hRoute[ "pattern" ],  36 ) + ;
         PadR( cMw,               20 ) + ;
         cAction + cEol

   NEXT

   BLOCK TO cHtml RAW PARAMS cTitle, cLine, aNames 
<!DOCTYPE html>
<html>
<head>
   <meta charset='utf-8'>
   <title><$ cTitle $></title>
   <style>
      body { 
         font-family:system-ui,sans-serif;
         background:#f0f4f8;
         padding:2rem 
      }
      h1 { 
         font-size:1.3rem;
         color:#2d3748;
         margin-bottom:1rem
      }
      pre {
         background:#fff;
         border-radius:8px;
         padding:1.5rem;
         font-size:.82rem;
         box-shadow:0 2px 12px rgba(0,0,0,.08);
         overflow-x:auto;
         white-space:pre
      }
   </style>
</head>
<body>
   <h1><$ cTitle + " (" + hb_NToS( Len( aNames ) ) + ")"$></h1>
   <pre><$ cLine $></pre>
   </body></html>
   ENDTEXT 
   
/*   
   cHtml := "<!DOCTYPE html><html><head><meta charset='utf-8'>" + cEol + ;
      "<title>" + cTitle + "</title>" + cEol + ;
      "<style>body{font-family:system-ui,sans-serif;background:#f0f4f8;padding:2rem}" + cEol + ;
      "h1{font-size:1.3rem;color:#2d3748;margin-bottom:1rem}" + cEol + ;
      "pre{background:#fff;border-radius:8px;padding:1.5rem;font-size:.82rem;" + cEol + ;
      "box-shadow:0 2px 12px rgba(0,0,0,.08);overflow-x:auto;white-space:pre}</style></head>" + cEol + ;
      "<body><h1>" + cTitle + " (" + hb_NToS( Len( aNames ) ) + ")</h1>" + cEol + ;
      "<pre>" + cLine + "</pre>" + cEol + ;
      "</body></html>"
*/

   oReq:Respond( cHtml, 200, "html" )

RETURN NIL

STATIC FUNCTION _HixIndexPage( cRows, nTotal )

   LOCAL cEol := Chr( 10 )
   LOCAL cHtml := ''
   
   BLOCK TO cHtml RAW PARAMS cRows, nTotal 
<!DOCTYPE html>
<html>
<head>
   <meta charset='utf-8'>
   <title>HIX Routes</title>
   <style>
      * { margin:0;padding:0;box-sizing:border-box}
      body { font-family:system-ui,sans-serif;background:#f0f4f8;padding:2rem}
      h1 { font-size:1.4rem;font-weight:700;color:#2d3748;margin-bottom:.25rem}
      .sub { font-size:.85rem;color:#a0aec0;margin-bottom:1.5rem}
      .logo { font-size:1.6rem;font-weight:700;color:#667eea;margin-bottom:.1rem}
      table { 
         width:100%;border-collapse:collapse;
         background:#fff;
         border-radius:8px;
         box-shadow:0 2px 12px rgba(0,0,0,.08);
         overflow:hidden
      }
      thead { background:#667eea;color:#fff}
      th { 
         padding:.65rem 1rem;
         text-align:left;
         font-size:.8rem;
         font-weight:600;
         letter-spacing:.05em;
         text-transform:uppercase
      }
      td { padding:.6rem 1rem;font-size:.875rem;border-bottom:1px solid #e2e8f0;vertical-align:middle}
      tr:last-child td { border-bottom:none }
      tr:hover td { background:#f7fafc }
      td.name { font-family:monospace;font-size:.8rem;color:#4a5568}
      td.pat { font-family:monospace;font-weight:600;color:#2d3748 }
      .badge { 
         display:inline-block;
         padding:.15rem .45rem;
         border-radius:3px;color:#fff;
         font-size:.7rem;
         font-weight:700;
         margin-right:.2rem
      }
      .btn { 
         display:inline-block;
         padding:.3rem .75rem;
         background:#667eea;
         color:#fff;
         border-radius:4px;
         text-decoration:none;
         font-size:.8rem;
         font-weight:600
      }
      .btn:hover { background:#5a67d8 }
      .na { color:#cbd5e0 }
      .topbar { display:flex;align-items:center;justify-content:space-between;margin-bottom:1.5rem}
      .topbar a { font-size:.85rem;color:#667eea;text-decoration:none}
      .topbar a:hover { text-decoration:underline }
   </style>
   </head>
   <body>
      <div class='topbar'>
         <div>
            <div class='logo'>HIX</div>
            <div class='sub'>Routes Panel — <$ hb_NToS( nTotal ) $>register</div>
         </div>
         <div><a href='/hix-status'>Status</a> &nbsp; <a href='/hix-logout'>Logout</a></div>
      </div>
      <table>
         <thead>
            <tr>
               <th>Name</th><th>Method</th><th>Pattern</th><th>Action</th>
            </tr>
         </thead>
         <tbody>
            <$ cRows $>
         </tbody>
      </table>
   </body>
</html>    
   ENDTEXT 
   
RETURN cHtml 
   
/*
RETURN "<!DOCTYPE html><html><head><meta charset='utf-8'>" + cEol + ;
      "<title>HIX — Rutas</title>" + cEol + ;
      "<style>" + cEol + ;
      "*{margin:0;padding:0;box-sizing:border-box}" + cEol + ;
      "body{font-family:system-ui,sans-serif;background:#f0f4f8;padding:2rem}" + cEol + ;
      "h1{font-size:1.4rem;font-weight:700;color:#2d3748;margin-bottom:.25rem}" + cEol + ;
      ".sub{font-size:.85rem;color:#a0aec0;margin-bottom:1.5rem}" + cEol + ;
      ".logo{font-size:1.6rem;font-weight:700;color:#667eea;margin-bottom:.1rem}" + cEol + ;
      "table{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;" + cEol + ;
      "  box-shadow:0 2px 12px rgba(0,0,0,.08);overflow:hidden}" + cEol + ;
      "thead{background:#667eea;color:#fff}" + cEol + ;
      "th{padding:.65rem 1rem;text-align:left;font-size:.8rem;font-weight:600;letter-spacing:.05em;text-transform:uppercase}" + cEol + ;
      "td{padding:.6rem 1rem;font-size:.875rem;border-bottom:1px solid #e2e8f0;vertical-align:middle}" + cEol + ;
      "tr:last-child td{border-bottom:none}" + cEol + ;
      "tr:hover td{background:#f7fafc}" + cEol + ;
      "td.name{font-family:monospace;font-size:.8rem;color:#4a5568}" + cEol + ;
      "td.pat{font-family:monospace;font-weight:600;color:#2d3748}" + cEol + ;
      ".badge{display:inline-block;padding:.15rem .45rem;border-radius:3px;color:#fff;" + cEol + ;
      "  font-size:.7rem;font-weight:700;margin-right:.2rem}" + cEol + ;
      ".btn{display:inline-block;padding:.3rem .75rem;background:#667eea;color:#fff;" + cEol + ;
      "  border-radius:4px;text-decoration:none;font-size:.8rem;font-weight:600}" + cEol + ;
      ".btn:hover{background:#5a67d8}" + cEol + ;
      ".na{color:#cbd5e0}" + cEol + ;
      ".topbar{display:flex;align-items:center;justify-content:space-between;margin-bottom:1.5rem}" + cEol + ;
      ".topbar a{font-size:.85rem;color:#667eea;text-decoration:none}" + cEol + ;
      ".topbar a:hover{text-decoration:underline}" + cEol + ;
      "</style></head><body>" + cEol + ;
      "<div class='topbar'>" + cEol + ;
      "  <div><div class='logo'>HIX</div><div class='sub'>Panel de rutas — " + hb_NToS( nTotal ) + " rutas registradas</div></div>" + cEol + ;
      "  <div><a href='/hix-status'>Estado</a> &nbsp; <a href='/hix-logout'>Salir</a></div>" + cEol + ;
      "</div>" + cEol + ;
      "<table><thead><tr>" + cEol + ;
      "  <th>Nombre</th><th>Método</th><th>Patrón</th><th>Acción</th>" + cEol + ;
      "</tr></thead><tbody>" + cEol + ;
      cRows + ;
      "</tbody></table></body></html>"
*/
// ============================================================
// Route specificity helpers
// ============================================================

// Score: literal segment = 10, :param segment = 1.
// Higher score = more specific = matched first.
STATIC FUNCTION _HixRouteScore( cPattern )

   LOCAL aSegs, cSeg, nScore := 0

   aSegs := hb_ATokens( cPattern, "/" )

   FOR EACH cSeg IN aSegs

      IF ! Empty( cSeg )

         nScore += iif( Left( cSeg, 1 ) == ":", 1, 10 )

      ENDIF

   NEXT

RETURN nScore

// Insert cName into s_aRouteOrder at the position that keeps scores descending.
// Called inside mutex lock.
STATIC FUNCTION _HixOrderInsert( cName, nScore )

   LOCAL i, hR

   FOR i := 1 TO Len( s_aRouteOrder )

      hR := hb_HGetDef( s_hRoutes, s_aRouteOrder[ i ], NIL )

      IF hR == NIL ; LOOP ; ENDIF

      IF hR[ "score" ] < nScore

         hb_AIns( s_aRouteOrder, i, cName, .T. )
         RETURN NIL

      ENDIF

   NEXT

   AAdd( s_aRouteOrder, cName )

RETURN NIL

// Remove cName from s_aRouteOrder. Called inside mutex lock.
STATIC FUNCTION _HixOrderRemove( cName )

   LOCAL i := AScan( s_aRouteOrder, cName )

   IF i > 0

      hb_ADel( s_aRouteOrder, i )
      ASize( s_aRouteOrder, Len( s_aRouteOrder ) - 1 )

   ENDIF

RETURN NIL
