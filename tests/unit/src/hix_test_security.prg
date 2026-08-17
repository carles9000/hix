/*-----------------------------------------------------------
  File ......: hix_test_security.prg
  Author.....: Charly 9000
  Created....: 2026-07-16
  Description: Pentest battery — C1..C7 categories from
               docs/security/seguridad_objetivos.md.
               Boots a controlled THixServer on port 18099
               with hardened middleware config, fires real
               HTTP requests via HixTS_* client helpers,
               validates status + headers + body.
  Notes      : Gaps not yet closed (G1, G2, G3, G4, G5, G6)
               are marked and counted as failed, so the
               battery stays red until the underlying HIX
               issues are addressed.
 -----------------------------------------------------------*/
#include "fileio.ch"
#include "hix_const.ch"

#define SEC_PORT   18099

STATIC s_oSrvSec    := NIL
STATIC s_hCfgBackup := NIL
STATIC s_cApiKey    := "test-api-key-secret"
STATIC s_cJwtKey    := "test-jwt-key-secret"
STATIC s_bMfReadOnly := NIL

STATIC PROCEDURE _TLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", ;
                          hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[Security] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

// ============================================================
// Entry point
// ============================================================
FUNCTION HIX_TestSecurity_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _TLog( "=== HIX_TestSecurity_Run start ===" )

   _SecBootServer( hCtx )

   IF s_oSrvSec == NIL .OR. ! s_oSrvSec:lRunning
      HixTU_Check( hCtx, .F., "SEC: servidor de test no arranco - suite saltada", ;
                   "running", "not running" )
      _SecRestoreConfig()
      RETURN hCtx
   ENDIF

   IF ! HixTS_WaitReady( SEC_PORT, "/ping", 5 )
      HixTU_Check( hCtx, .F., "SEC: /ping no responde tras arranque - suite saltada", ;
                   "ready", "timeout" )
      _SecStopServer()
      _SecRestoreConfig()
      RETURN hCtx
   ENDIF

   _TLog( "Server ready on port " + hb_NToS( SEC_PORT ) )

   _RunC1_Headers(        hCtx )
   _RunC2_Methods(        hCtx )
   _RunC3_AuthZ(          hCtx )
   _RunC4_Injections(     hCtx )
   _RunC5_DoS(            hCtx )
   _RunC6_Errors(         hCtx )
   _RunC7_HostValidation( hCtx )

   _SecStopServer()
   _SecRestoreConfig()

   _SecLogResults( hCtx )

   _TLog( "=== HIX_TestSecurity_Run end total=" + hb_NToS( hCtx[ "total" ] ) + ;
          " pass=" + hb_NToS( hCtx[ "passed" ] ) + ;
          " fail=" + hb_NToS( hCtx[ "failed" ] ) + " ===" )

RETURN hCtx

// ============================================================
// Bootstrap del servidor test con config endurecida
// ============================================================
STATIC PROCEDURE _SecBootServer( hCtx )
   LOCAL oSrv, hCfg, oErr

   HB_SYMBOL_UNUSED( hCtx )
   _TLog( "_SecBootServer" )

   HIX_LoadConfig()
   hCfg := HIX_GetConfig()

   s_hCfgBackup := { ;
      "server"    => hb_HClone( hCfg[ "server"    ] ), ;
      "paths"     => hb_HClone( hCfg[ "paths"     ] ), ;
      "detector"  => hb_HClone( hCfg[ "detector"  ] ), ;
      "pool_http" => hb_HClone( hCfg[ "pool_http" ] ), ;
      "pool_ws"   => hb_HClone( hCfg[ "pool_ws"   ] ), ;
      "pool_rest" => hb_HClone( hCfg[ "pool_rest" ] ), ;
      "monitor"   => hb_HClone( hCfg[ "monitor"   ] ), ;
      "app"       => hb_HClone( hCfg[ "app"       ] ), ;
      "firewall"  => hb_HClone( hCfg[ "firewall"  ] )  ;
   }

   hCfg[ "server"    ][ "host" ]             := "127.0.0.1"
   hCfg[ "server"    ][ "port" ]             := SEC_PORT
   hCfg[ "server"    ][ "maxconn" ]          := 32
   hCfg[ "server"    ][ "ssl" ]              := .F.
   hCfg[ "server"    ][ "autostart" ]        := .F.
   hCfg[ "server"    ][ "allowed_hosts" ]    := "127.0.0.1"     // C7 — Host allowlist (G3)
   hCfg[ "detector"  ][ "workers" ]          := 2
   hCfg[ "detector"  ][ "queue_size" ]       := 16
   hCfg[ "detector"  ][ "peek_timeout_ms" ]  := 200
   hCfg[ "detector"  ][ "peek_bytes" ]       := 512
   hCfg[ "pool_http" ][ "workers" ]          := 4
   hCfg[ "pool_http" ][ "queue_size" ]       := 32
   hCfg[ "pool_http" ][ "read_timeout_ms" ]  := 2000
   hCfg[ "pool_http" ][ "keep_alive" ]       := .F.
   hCfg[ "pool_http" ][ "keep_alive_max" ]   := 5
   hCfg[ "pool_ws"   ][ "workers" ]          := 2
   hCfg[ "pool_ws"   ][ "queue_size" ]       := 8
   hCfg[ "pool_rest" ][ "workers_sse" ]      := 1
   hCfg[ "pool_rest" ][ "workers_longpoll" ] := 1
   hCfg[ "pool_rest" ][ "queue_size" ]       := 8
   hCfg[ "pool_rest" ][ "stream_timeout_s" ] := 60
   hCfg[ "monitor"   ][ "enabled" ]          := .F.
   hCfg[ "firewall"  ][ "mode" ]             := "blacklist"
   hCfg[ "firewall"  ][ "filter" ]           := ""
   hCfg[ "app"       ][ "env" ]              := "prod"       // C6.1 — ejercita HIX_ErrorSysProd

   // Setup middlewares antes del arranque
   HIX_MwSecHeadersSetup( "default-src 'self'" )
   HIX_MwBodyLimitSetup( 1024 )                                  // 1 KB para el test C5.1
   HIX_MwRateLimitSetup( 5, 2 )                                   // 5 req por 2 s / IP -> C5.3
   HIX_MwApiKeySetup( { s_cApiKey } )
   HIX_MwMethodFilterSetup( { "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS" } )
   HIX_KeySet( "jwt", s_cJwtKey )

   TRY
      oSrv := THixServer():New()
      oSrv:bInit    := {|| NIL }
      oSrv:bPreEnd  := {|| NIL }
      oSrv:bPostEnd := {|| NIL }

      // Ruta base con SecHeaders (C1: headers HTTP)
      oSrv:AddRouteGet( "sec.ping", "/ping", ;
         {|| USendJson( { "ok" => .T. } ) }, ;
         "HIX_MwSecHeaders" )

      // Ruta dedicada al rate limit (C5.3)
      oSrv:AddRouteGet( "sec.rated", "/rated", ;
         {|| USendJson( { "ok" => .T. } ) }, ;
         "HIX_MwRateLimit" )

      // Ruta protegida con ApiKey
      oSrv:AddRouteGet( "sec.private", "/api/private", ;
         {|| USendJson( { "secret" => "shhh" } ) }, ;
         "HIX_MwApiKey" )

      // Ruta dedicada al Anomaly Detector (G5): el pre-check MW corta con 429
      // cuando la IP esta baneada; la accion devuelve siempre 401 para que el
      // post-hook (Record) llene el contador de la IP.
      oSrv:AddRouteGet( "sec.anom", "/api/anom", ;
         {|| USendJson( { "error" => "unauthorized" }, 401 ) }, ;
         "HIX_MwAnomaly" )

      // Ruta protegida con JWT
      oSrv:AddRouteGet( "sec.jwt", "/api/private-jwt", ;
         {|| USendJson( { "sub" => "user" } ) }, ;
         "HIX_MwJwt" )

      // Endpoint que refleja query param -> C4.2 XSS
      oSrv:AddRouteGet( "sec.search", "/buscar", ;
         {|| USendHtml( "<p>Resultados para " + UHtmlEncode( UGet( "q", "" ) ) + "</p>" ) } )

      // Endpoint que devuelve el query param SIN escapar -> control positivo XSS
      oSrv:AddRouteGet( "sec.echo.raw", "/echo-raw", ;
         {|| USendHtml( "<p>" + UGet( "q", "" ) + "</p>" ) } )

      // POST con body limit
      oSrv:AddRoutePost( "sec.upload", "/upload", ;
         {|| USendJson( { "size" => Len( UBody() ) } ) }, ;
         "HIX_MwBodyLimit" )

      // Endpoint que devuelve solo status para 405 test
      oSrv:AddRouteGet( "sec.only.get", "/only-get", ;
         {|| USendText( "get only" ) } )

      // Rutas para MethodFilter (G4)
      oSrv:AddRouteGet( "sec.mfilter", "/mfilter", ;
         {|| USendJson( { "ok" => .T. } ) }, ;
         "HIX_MwMethodFilter" )
      oSrv:AddRouteGet( "sec.mfilter.ro", "/mfilter-getonly", ;
         {|| USendJson( { "ok" => .T. } ) }, ;
         "HixTS_MwMfReadOnly" )
      oSrv:AddRoutePost( "sec.mfilter.ro.post", "/mfilter-getonly", ;
         {|| USendJson( { "ok" => .T. } ) }, ;
         "HixTS_MwMfReadOnly" )

      // Endpoint que fuerza crash -> C6.1 leak
      oSrv:AddRouteGet( "sec.crash", "/crash", ;
         {|| _SecCrashHandler() } )

      oSrv:Start( .F. )
      hb_idleSleep( 1.0 )

      s_oSrvSec := oSrv
      _TLog( "Server started lRunning=" + hb_ValToStr( oSrv:lRunning ) )
   CATCH oErr
      _TLog( "Boot exception: " + oErr:description )
      s_oSrvSec := NIL
   END
RETURN

STATIC PROCEDURE _SecLogResults( hCtx )
   LOCAL hRes
   FOR EACH hRes IN hCtx[ "results" ]
      _TLog( iif( hRes[ "status" ] == "pass", "[PASS] ", "[FAIL] " ) + hRes[ "name" ] + ;
             iif( hRes[ "status" ] == "fail", " | " + hRes[ "msg" ], "" ) )
   NEXT
RETURN

STATIC FUNCTION _SecCrashHandler()
   LOCAL nBoom := 1 / 0
   HB_SYMBOL_UNUSED( nBoom )
RETURN NIL

STATIC PROCEDURE _SecStopServer()
   IF s_oSrvSec != NIL
      TRY
         s_oSrvSec:Stop()
         hb_idleSleep( 0.3 )
      CATCH
      END
      s_oSrvSec := NIL
   ENDIF
RETURN

STATIC PROCEDURE _SecRestoreConfig()
   LOCAL hCfg, cKey
   IF s_hCfgBackup != NIL
      hCfg := HIX_GetConfig()
      FOR EACH cKey IN hb_HKeys( s_hCfgBackup )
         hCfg[ cKey ] := hb_HClone( s_hCfgBackup[ cKey ] )
      NEXT
      s_hCfgBackup := NIL
   ENDIF
RETURN

// ============================================================
// C1 — Headers HTTP y configuracion basica
// ============================================================
STATIC PROCEDURE _RunC1_Headers( hCtx )
   LOCAL hResp, cServer

   _TLog( "_RunC1_Headers" )
   hResp := HixTS_Get( SEC_PORT, "/ping", NIL )

   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 200, ;
      "C1.0 /ping responde 200", "200", hb_NToS( hResp[ "status" ] ) )

   HixTU_Check( hCtx, ;
      HixTS_Header( hResp, "X-Frame-Options" ) == "DENY", ;
      "C1.1 X-Frame-Options: DENY", "DENY", HixTS_Header( hResp, "X-Frame-Options" ) )

   HixTU_Check( hCtx, ;
      HixTS_Header( hResp, "X-Content-Type-Options" ) == "nosniff", ;
      "C1.2 X-Content-Type-Options: nosniff", "nosniff", HixTS_Header( hResp, "X-Content-Type-Options" ) )

   HixTU_Check( hCtx, ;
      "default-src" $ HixTS_Header( hResp, "Content-Security-Policy" ), ;
      "C1.3 CSP presente", "default-src ...", HixTS_Header( hResp, "Content-Security-Policy" ) )

   HixTU_Check( hCtx, ;
      ! HixTS_HasHeader( hResp, "X-Powered-By" ), ;
      "C1.5 X-Powered-By ausente", "ausente", "presente" )

   cServer := HixTS_Header( hResp, "Server" )
   HixTU_Check( hCtx, ;
      ! ( "/" $ cServer ) .OR. ! ( "2." $ cServer ), ;
      "C1.6 Server header sin version [gap G1]", "sin version", cServer )
RETURN

// ============================================================
// C2 — Metodos HTTP no permitidos
// ============================================================
STATIC PROCEDURE _RunC2_Methods( hCtx )
   LOCAL hResp

   _TLog( "_RunC2_Methods" )

   hResp := HixTS_Custom( SEC_PORT, "TRACE", "/ping", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] >= 400 .AND. hResp[ "status" ] < 500, ;
      "C2.1 TRACE rechazado (4xx)", "4xx", hb_NToS( hResp[ "status" ] ) )

   hResp := HixTS_Custom( SEC_PORT, "CONNECT", "/ping", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] >= 400 .AND. hResp[ "status" ] < 500, ;
      "C2.2 CONNECT rechazado (4xx)", "4xx", hb_NToS( hResp[ "status" ] ) )

   hResp := HixTS_Custom( SEC_PORT, "TRACK", "/ping", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] >= 400 .AND. hResp[ "status" ] < 500, ;
      "C2.3 TRACK rechazado (4xx)", "4xx", hb_NToS( hResp[ "status" ] ) )

   hResp := HixTS_Custom( SEC_PORT, "PUT", "/only-get", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 405, ;
      "C2.4 PUT sobre ruta solo-GET -> 405", "405", hb_NToS( hResp[ "status" ] ) )

   // C2.5 — MethodFilter global: GET permitido pasa a la accion (mw en cadena)
   hResp := HixTS_Get( SEC_PORT, "/mfilter", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 200 .AND. '"ok"' $ hResp[ "body" ], ;
      "C2.5 MethodFilter: GET permitido pasa [G4]", ;
      "200+ok", hb_NToS( hResp[ "status" ] ) + " / " + Left( hResp[ "body" ], 60 ) )

   // C2.6 — MethodFilterFactory por ruta: allow-list {GET,HEAD} rechaza POST
   hResp := HixTS_Custom( SEC_PORT, "POST", "/mfilter-getonly", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 405 .AND. "method_not_allowed" $ hResp[ "body" ], ;
      "C2.6 MethodFilter factory: POST rechazado [G4]", ;
      "405+method_not_allowed", hb_NToS( hResp[ "status" ] ) + " / " + Left( hResp[ "body" ], 60 ) )
RETURN

// ============================================================
// C3 — Autenticacion y autorizacion
// ============================================================
STATIC PROCEDURE _RunC3_AuthZ( hCtx )
   LOCAL hResp, hHdr

   _TLog( "_RunC3_AuthZ" )

   // C3.1 endpoint privado sin credencial
   hResp := HixTS_Get( SEC_PORT, "/api/private", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 401, ;
      "C3.1 /api/private sin X-Api-Key -> 401", "401", hb_NToS( hResp[ "status" ] ) )

   // Con X-Api-Key valida
   hHdr := { "X-Api-Key" => s_cApiKey }
   hResp := HixTS_Get( SEC_PORT, "/api/private", hHdr )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 200, ;
      "C3.1b /api/private con X-Api-Key valida -> 200", "200", hb_NToS( hResp[ "status" ] ) )

   // JWT sin token
   hResp := HixTS_Get( SEC_PORT, "/api/private-jwt", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 401, ;
      "C3.2 /api/private-jwt sin token -> 401", "401", hb_NToS( hResp[ "status" ] ) )

   // JWT malformado
   hHdr := { "Authorization" => "Bearer not.a.valid.jwt" }
   hResp := HixTS_Get( SEC_PORT, "/api/private-jwt", hHdr )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 401, ;
      "C3.3 JWT malformado -> 401", "401", hb_NToS( hResp[ "status" ] ) )

   // JWT firma invalida (payload valido, sig random)
   hHdr := { "Authorization" => "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.badsig1234" }
   hResp := HixTS_Get( SEC_PORT, "/api/private-jwt", hHdr )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 401, ;
      "C3.4 JWT firma invalida -> 401", "401", hb_NToS( hResp[ "status" ] ) )

   // C3.5 Path traversal
   hResp := HixTS_Get( SEC_PORT, "/../etc/passwd", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 403 .OR. hResp[ "status" ] == 400, ;
      "C3.5 path traversal /../etc/passwd -> 403", "403|400", hb_NToS( hResp[ "status" ] ) )

   hResp := HixTS_Get( SEC_PORT, "/static/..%2fhix.json", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] >= 400, ;
      "C3.5b path traversal encoded -> 4xx", "4xx", hb_NToS( hResp[ "status" ] ) )
RETURN

// ============================================================
// C4 — Inyecciones
// ============================================================
STATIC PROCEDURE _RunC4_Injections( hCtx )
   LOCAL hResp

   _TLog( "_RunC4_Injections" )

   // C4.2 XSS reflejado — la ruta /buscar usa UHtmlEncode
   hResp := HixTS_Get( SEC_PORT, "/buscar?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 200 .AND. ! ( "<script>" $ hResp[ "body" ] ), ;
      "C4.2 XSS reflejado escapado (/buscar)", "sin <script>", ;
      iif( "<script>" $ hResp[ "body" ], "contiene <script>", "ok" ) )

   HixTU_Check( hCtx, ;
      "&lt;script&gt;" $ hResp[ "body" ], ;
      "C4.2b XSS reflejado: entidades HTML presentes", "&lt;script&gt;", "no encontrado" )

   // Control positivo: /echo-raw NO escapa -> demuestra que UHtmlEncode marca la diferencia
   hResp := HixTS_Get( SEC_PORT, "/echo-raw?q=%3Cscript%3E", NIL )
   HixTU_Check( hCtx, ;
      "<script>" $ hResp[ "body" ], ;
      "C4.2c control: /echo-raw devuelve <script> sin escapar (esperado)", "<script>", "no" )

   // C4.4 path traversal en file endpoint — cubierto por C3.5

   // C4.5 CRLF injection en query param (no hay ruta que lo refleje en header, skip)
RETURN

// ============================================================
// C5 — Resiliencia / DoS
// ============================================================
STATIC PROCEDURE _RunC5_DoS( hCtx )
   LOCAL hResp, cBig, i, n429

   _TLog( "_RunC5_DoS" )

   // C5.1 Body > bodylimit (config 1024 bytes)
   cBig  := Replicate( "x", 4096 )
   hResp := HixTS_Post( SEC_PORT, "/upload", cBig, NIL, NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 413, ;
      "C5.1 body 4KB > 1KB limit -> 413", "413", hb_NToS( hResp[ "status" ] ) )

   // C5.1b Body dentro del limite pasa
   cBig  := Replicate( "y", 512 )
   hResp := HixTS_Post( SEC_PORT, "/upload", cBig, NIL, NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 200, ;
      "C5.1b body 512B < 1KB limit -> 200", "200", hb_NToS( hResp[ "status" ] ) )

   // C5.3 Rate limit (5 req / 2 s) contra ruta dedicada /rated
   hb_idleSleep( 2.1 )                            // ventana limpia
   n429 := 0
   FOR i := 1 TO 10
      hResp := HixTS_Get( SEC_PORT, "/rated", NIL )
      IF hResp[ "status" ] == 429 ; n429++ ; ENDIF
   NEXT
   HixTU_Check( hCtx, ;
      n429 > 0, ;
      "C5.3 rate limit: al menos un 429 tras 10 req rapidas", ">0", hb_NToS( n429 ) )

   // C5.4 Slowloris — enviar cabecera parcial, esperar mas que read_timeout_ms (2 s)
   hb_idleSleep( 2.1 )                            // reset rate limit
   hResp := HixTS_Raw( SEC_PORT, "GET /ping HTTP/1.0" + Chr( 13 ) + Chr( 10 ) + "Host: 127.0.0.1" + Chr( 13 ) + Chr( 10 ), 4000 )
   HixTU_Check( hCtx, ;
      hResp[ "error" ] != NIL .OR. hResp[ "status" ] >= 400, ;
      "C5.4 conexion sin CRLF final -> cerrada o 4xx (read_timeout)", ;
      "closed|4xx", ;
      iif( hResp[ "error" ] != NIL, hResp[ "error" ], hb_NToS( hResp[ "status" ] ) ) )
RETURN

// ============================================================
// C6 — Errores y filtrado de informacion
// ============================================================
STATIC PROCEDURE _RunC6_Errors( hCtx )
   LOCAL hResp, cBody

   _TLog( "_RunC6_Errors" )

   // C6.1 stacktrace leak — depende de env=prod (gap G2)
   hResp := HixTS_Get( SEC_PORT, "/crash", NIL )
   cBody := hResp[ "body" ]
   HixTU_Check( hCtx, ;
      hResp[ "status" ] >= 500, ;
      "C6.1a /crash devuelve 5xx", "5xx", hb_NToS( hResp[ "status" ] ) )

   HixTU_Check( hCtx, ;
      ! ( "hix_test_security.prg" $ cBody ) .AND. ;
      ! ( "SubSystem" $ cBody ) .AND. ;
      ! ( "Operation" $ cBody ), ;
      "C6.1b /crash no filtra file/subsystem/operation [gap G2]", ;
      "sin file/subsystem/operation", ;
      iif( "SubSystem" $ cBody, "contiene SubSystem", ;
      iif( "Operation" $ cBody, "contiene Operation", "contiene fichero .prg" ) ) )

   // C6.2 404 no revela stack
   hb_idleSleep( 2.1 )
   hResp := HixTS_Get( SEC_PORT, "/ruta/inexistente/xxxxx", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 404, ;
      "C6.2 ruta inexistente -> 404", "404", hb_NToS( hResp[ "status" ] ) )

   // C6.3 405 lleva Allow (verificar Content-Type existe al menos)
   hResp := HixTS_Custom( SEC_PORT, "POST", "/only-get", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 405, ;
      "C6.3 POST /only-get -> 405", "405", hb_NToS( hResp[ "status" ] ) )

   // C6.4/C6.5/C6.6 — Anomaly Detector [G5]
   // Habilitamos ahora (threshold=3 mal / window=2s / ban=2s) para no
   // interferir con C3 (que fue rapida y ya paso su ventana) y para
   // que C6.6 no tenga que dormir demasiado esperando expiracion.
   HIX_MwAnomalySetup( 3, 2, 2 )

   // C6.4 — 3 requests sin X-Api-Key: los 3 devuelven 401 (llena umbral)
   HixTU_Check( hCtx, ;
      HixTS_Get( SEC_PORT, "/api/anom", NIL )[ "status" ] == 401, ;
      "C6.4a anomaly: 1er 401 registrado [G5]", "401", "distinto" )
   HixTU_Check( hCtx, ;
      HixTS_Get( SEC_PORT, "/api/anom", NIL )[ "status" ] == 401, ;
      "C6.4b anomaly: 2o 401 registrado [G5]", "401", "distinto" )
   HixTU_Check( hCtx, ;
      HixTS_Get( SEC_PORT, "/api/anom", NIL )[ "status" ] == 401, ;
      "C6.4c anomaly: 3er 401 dispara ban [G5]", "401", "distinto" )

   // C6.5 — 4a peticion desde misma IP: 429 + body temporarily_blocked
   hResp := HixTS_Get( SEC_PORT, "/api/anom", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 429 .AND. "temporarily_blocked" $ hResp[ "body" ], ;
      "C6.5 anomaly: IP banned -> 429 temporarily_blocked [G5]", ;
      "429+temporarily_blocked", ;
      hb_NToS( hResp[ "status" ] ) + " / " + Left( hResp[ "body" ], 60 ) )

   // C6.6 — tras expirar el ban (2s), la IP puede pedir otra vez -> 401
   hb_idleSleep( 3 )
   hResp := HixTS_Get( SEC_PORT, "/api/anom", NIL )
   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 401, ;
      "C6.6 anomaly: ban expirado -> 401 de nuevo [G5]", "401", hb_NToS( hResp[ "status" ] ) )
RETURN

// ============================================================
// C7 — Host header validation [gap G3]
// ============================================================
STATIC PROCEDURE _RunC7_HostValidation( hCtx )
   LOCAL hResp

   _TLog( "_RunC7_HostValidation" )

   hResp := HixTS_Get( SEC_PORT, "/ping", { "Host" => "evil.example.com" } )

   HixTU_Check( hCtx, ;
      hResp[ "status" ] == 400 .OR. hResp[ "status" ] == 403, ;
      "C7.1 Host arbitrario rechazado [gap G3]", "400|403", hb_NToS( hResp[ "status" ] ) )
RETURN

// ============================================================
// Wrapper que enlaza el factory allow-list {GET,HEAD} como
// funcion nominal (el router acepta solo nombre string en cMw)
// ============================================================
FUNCTION HixTS_MwMfReadOnly( oCtx )
   IF s_bMfReadOnly == NIL
      s_bMfReadOnly := HIX_MwMethodFilterFactory( { "GET", "HEAD" } )
   ENDIF
RETURN Eval( s_bMfReadOnly, oCtx )
