/*-----------------------------------------------------------
  File ......: hix_test_ssl.prg
  Author.....: Charly 9000
  Created....: 2026-06-09
  Description: Integrated SSL/TLS test battery.
               Suite 1  — SSL config defaults (server.ssl / certs)
               Suite 2  — THixSocket ctx init (bad/good certs)
               Suite 3  — THixIO SSL propagation
               Suite 4  — HTTPS integration (real server + curl)
               Suite 5  — HTTP headers over TLS
               Suite 6  — TLS: 404, JSON, clean stop
               Prereq   : run make_test_cert.bat once to generate certs.
 -----------------------------------------------------------*/
#include "hbssl.ch"
#include "fileio.ch"

#define SSL_PORT   18443
#define SSL_CERT   "hix_test.crt"
#define SSL_KEY    "hix_test.key"
#define CURL_BASE  "https://127.0.0.1:" + hb_NToS( SSL_PORT )

STATIC s_oSrvSSL     := NIL
STATIC s_hCfgBackup  := NIL   // snapshot de config para restaurar tras el test
STATIC s_cCurlBin    := NIL   // cache de la ruta a curl.exe (NIL = sin resolver)

STATIC PROCEDURE _TLog( cMsg )
   LOCAL cDir := hb_DirBase() + "traces" + hb_ps()
   LOCAL nH
   IF ! hb_vfDirExists( cDir )
      hb_vfDirMake( cDir )
   ENDIF
   nH := hb_vfOpen( cDir + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[SSL] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

// ============================================================
STATIC FUNCTION _CfgTrace( cWhen )
   LOCAL hCfg := HIX_GetConfig()
   LOCAL cInfo := iif( hCfg == NIL, "NIL", ;
      "port=" + hb_NToS( hCfg[ "server" ][ "port" ] ) + ;
      " lSSL=" + hb_ValToStr( hCfg[ "server" ][ "ssl" ] ) )
   _TLog( "GlobalConfig [" + cWhen + "]: " + cInfo )
RETURN NIL

FUNCTION HIX_TestSSL_Run()
   LOCAL hCtx      := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL lHasCerts := File( hb_DirBase() + SSL_CERT ) .AND. File( hb_DirBase() + SSL_KEY )

   _TLog( "=== HIX_TestSSL_Run start ===" )
   _CfgTrace( "inicio" )
   _SslConfigDefaults( hCtx )
   _SslCtxFiles(       hCtx, lHasCerts )
   _SslIOLayer(        hCtx )
   IF lHasCerts
      _SslServerStart( hCtx )
      _CfgTrace( "post-Start" )
      IF s_oSrvSSL != NIL
         IF Empty( _CurlBin() )
            HixTU_Check( hCtx, .F., "SSL: curl.exe no localizado — tests HTTPS saltados", "curl.exe", "missing" )
            HixTM_Note( "curl.exe no encontrado: tests HTTPS saltados", "warn" )
         ELSE
            _SslHttpsGet(     hCtx )
            _SslHttpsHeaders( hCtx )
            _SslHttpsExtra(   hCtx )
         ENDIF
         _SslServerStop(   hCtx )
         _CfgTrace( "post-Stop" )
      ELSE
         HixTU_Check( hCtx, .F., "SSL: servidor SSL no arranco — tests de integracion saltados", "running", "nil" )
      ENDIF
   ELSE
      HixTU_Check( hCtx, .F., "SSL: certificados no encontrados — ejecutar make_test_cert.bat", "certs ok", "missing" )
   ENDIF
   _CfgTrace( "final" )
   _TLog( "=== HIX_TestSSL_Run end ===" )
RETURN hCtx

// ============================================================
// Suite 1 — SSL defaults en el hash global
// ============================================================
STATIC PROCEDURE _SslConfigDefaults( hCtx )
   LOCAL oCfgSave, hCfg, lSSL, cPriv, cPub
   _TLog( "_SslConfigDefaults" )

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )

   hCfg  := HIX_GetConfig()
   hCfg[ "server" ][ "ssl" ]          := .F.
   hCfg[ "server" ][ "cert_private" ] := ""
   hCfg[ "server" ][ "cert_public" ]  := ""
   lSSL  := HIX_GetConfig( "server", "ssl" )
   cPriv := HIX_GetConfig( "server", "cert_private" )
   cPub  := HIX_GetConfig( "server", "cert_public" )
   HixTU_Check( hCtx, lSSL == .F.,  "SSL: default server.ssl=.F.",          ".F.", iif( lSSL, ".T.", ".F." ) )
   HixTU_Check( hCtx, cPriv == "",  "SSL: default server.cert_private=''",  "''",  cPriv )
   HixTU_Check( hCtx, cPub  == "",  "SSL: default server.cert_public=''",   "''",  cPub  )

   hCfg[ "server" ][ "ssl" ]          := .T.
   hCfg[ "server" ][ "cert_private" ] := "server.key"
   hCfg[ "server" ][ "cert_public" ]  := "server.crt"
   lSSL  := HIX_GetConfig( "server", "ssl" )
   cPriv := HIX_GetConfig( "server", "cert_private" )
   cPub  := HIX_GetConfig( "server", "cert_public" )
   HixTU_Check( hCtx, lSSL,                     "SSL: config asignar ssl=.T.",            ".T.", iif( lSSL, ".T.", ".F." ) )
   HixTU_Check( hCtx, cPriv == "server.key",    "SSL: config cert_private asignada",     "server.key", cPriv )
   HixTU_Check( hCtx, cPub  == "server.crt",    "SSL: config cert_public asignada",      "server.crt", cPub )

   HIX_SetConfig( oCfgSave )
RETURN

// ============================================================
// Suite 2 — THixSocket ctx init (malos y buenos certificados)
// ============================================================
STATIC PROCEDURE _SslCtxFiles( hCtx, lHasCerts )
   LOCAL oSock, hCfg, oCfgSave
   _TLog( "_SslCtxFiles lHasCerts=" + hb_ValToStr( lHasCerts ) )

   HIX_LoadConfig()
   oCfgSave := hb_HClone( HIX_GetConfig() )

   // SSL=.F.: no se inicializa SSL_CTX
   hCfg := HIX_GetConfig()
   hCfg[ "server" ][ "ssl" ] := .F.
   oSock := THixSocket():New()
   HixTU_Check( hCtx, oSock:hSSLCtx == NIL, "SSL: THixSocket sin SSL -> hSSLCtx=NIL", "NIL", iif( oSock:hSSLCtx == NIL, "NIL", "noNIL" ) )
   HixTU_Check( hCtx, ! oSock:lUseSSL,      "SSL: THixSocket sin SSL -> lUseSSL=.F.", ".F.", iif( oSock:lUseSSL, ".T.", ".F." ) )

   // SSL=.T. + ficheros inexistentes -> hSSLCtx=NIL (sin crash)
   hCfg[ "server" ][ "ssl" ]          := .T.
   hCfg[ "server" ][ "cert_private" ] := "no_existe.key"
   hCfg[ "server" ][ "cert_public" ]  := "no_existe.crt"
   oSock := THixSocket():New()
   HixTU_Check( hCtx, oSock:hSSLCtx == NIL, "SSL: cert inexistente -> hSSLCtx=NIL (sin crash)", "NIL", iif( oSock:hSSLCtx == NIL, "NIL", "noNIL" ) )
   HixTU_Check( hCtx, oSock:lUseSSL,        "SSL: lUseSSL=.T. aunque ctx fallo",                ".T.", iif( oSock:lUseSSL, ".T.", ".F." ) )

   IF lHasCerts
      // SSL=.T. + ficheros reales -> hSSLCtx != NIL
      hCfg[ "server" ][ "ssl" ]          := .T.
      hCfg[ "paths"  ][ "certs" ]        := hb_DirBase()
      hCfg[ "server" ][ "cert_private" ] := SSL_KEY
      hCfg[ "server" ][ "cert_public" ]  := SSL_CERT
      oSock := THixSocket():New()
      HixTU_Check( hCtx, oSock:hSSLCtx != NIL, "SSL: certs validos -> hSSLCtx!=NIL", "noNIL", iif( oSock:hSSLCtx == NIL, "NIL", "noNIL" ) )
      HixTU_Check( hCtx, oSock:lUseSSL,        "SSL: certs validos -> lUseSSL=.T.",  ".T.",   iif( oSock:lUseSSL, ".T.", ".F." ) )
   ELSE
      HixTU_Check( hCtx, .T., "SSL: ctx con certs reales — saltado (sin certificados)", "skip", "skip" )
      HixTU_Check( hCtx, .T., "SSL: lUseSSL con certs reales — saltado",               "skip", "skip" )
   ENDIF

   HIX_SetConfig( oCfgSave )
RETURN

// ============================================================
// Suite 3 — THixIO propagacion SSL
// ============================================================
STATIC PROCEDURE _SslIOLayer( hCtx )
   LOCAL oIO
   _TLog( "_SslIOLayer" )
   // THixIO sin SSL: defaults
   oIO := THixIO():New( NIL )
   HixTU_Check( hCtx, ! oIO:lUseSSL,       "SSL: THixIO default lUseSSL=.F.",    ".F.", iif( oIO:lUseSSL, ".T.", ".F." ) )
   HixTU_Check( hCtx, oIO:hSSLSession == NIL, "SSL: THixIO default hSSLSession=NIL","NIL", iif( oIO:hSSLSession == NIL, "NIL", "noNIL" ) )
   HixTU_Check( hCtx, ! oIO:lConnClosed,   "SSL: THixIO default lConnClosed=.F.", ".F.", iif( oIO:lConnClosed, ".T.", ".F." ) )
RETURN

// ============================================================
// Suite 4 — Arrancar servidor HTTPS real
// ============================================================
STATIC PROCEDURE _SslServerStart( hCtx )
   LOCAL oSrv, hCfg
   _TLog( "_SslServerStart" )

   HIX_LoadConfig()
   hCfg := HIX_GetConfig()

   // Snapshot completo de las secciones que vamos a mutar, para restaurar en _SslServerStop
   s_hCfgBackup := { ;
      "server"    => hb_HClone( hCfg[ "server"    ] ), ;
      "paths"     => hb_HClone( hCfg[ "paths"     ] ), ;
      "detector"  => hb_HClone( hCfg[ "detector"  ] ), ;
      "pool_http" => hb_HClone( hCfg[ "pool_http" ] ), ;
      "pool_ws"   => hb_HClone( hCfg[ "pool_ws"   ] ), ;
      "pool_rest" => hb_HClone( hCfg[ "pool_rest" ] ), ;
      "monitor"   => hb_HClone( hCfg[ "monitor"   ] )  ;
   }
   hCfg[ "server"     ][ "host" ]             := "127.0.0.1"
   hCfg[ "server"     ][ "port" ]             := SSL_PORT
   hCfg[ "server"     ][ "maxconn" ]          := 32
   hCfg[ "server"     ][ "ssl" ]              := .T.
   hCfg[ "paths"      ][ "certs" ]            := hb_DirBase()
   hCfg[ "server"     ][ "cert_private" ]     := SSL_KEY
   hCfg[ "server"     ][ "cert_public" ]      := SSL_CERT
   hCfg[ "server"     ][ "autostart" ]        := .F.
   hCfg[ "detector"   ][ "workers" ]          := 2
   hCfg[ "detector"   ][ "queue_size" ]       := 16
   hCfg[ "detector"   ][ "peek_timeout_ms" ]  := 200
   hCfg[ "detector"   ][ "peek_bytes" ]       := 512
   hCfg[ "pool_http"  ][ "workers" ]          := 4
   hCfg[ "pool_http"  ][ "queue_size" ]       := 32
   hCfg[ "pool_http"  ][ "read_timeout_ms" ]  := 2000
   hCfg[ "pool_http"  ][ "keep_alive" ]       := .F.
   hCfg[ "pool_http"  ][ "keep_alive_max" ]   := 5
   hCfg[ "pool_ws"    ][ "workers" ]          := 2
   hCfg[ "pool_ws"    ][ "queue_size" ]       := 8
   hCfg[ "pool_ws"    ][ "ping_interval_s" ]  := 30
   hCfg[ "pool_ws"    ][ "ping_timeout_s" ]   := 10
   hCfg[ "pool_rest" ][ "workers_sse" ]      := 1
   hCfg[ "pool_rest" ][ "workers_longpoll" ] := 1
   hCfg[ "pool_rest" ][ "queue_size" ]       := 8
   hCfg[ "pool_rest" ][ "stream_timeout_s" ] := 3600
   hCfg[ "monitor"    ][ "alert_pct" ]        := 75
   hCfg[ "monitor"    ][ "enabled" ]          := .F.

   oSrv := THixServer():New()
   oSrv:bInit    := {|| NIL }
   oSrv:bPreEnd  := {|| NIL }
   oSrv:bPostEnd := {|| NIL }
   oSrv:AddRouteGet( "ping_ssl", "/ping-ssl", {|| USendText( "pong-ssl" ) } )
   oSrv:AddRouteGet( "hello",    "/hello",    {|| USendText( "hello-ssl" ) } )
   oSrv:AddRouteGet( "json_ssl", "/json-ssl", {|| USendJson( { "status" => "ok", "ssl" => .T. } ) } )

   oSrv:Start( .F. )
   hb_idleSleep( 1.2 )

   s_oSrvSSL := oSrv
   _TLog( "Server started lRunning=" + hb_ValToStr( oSrv:lRunning ) )
   HixTU_Check( hCtx, oSrv:lRunning, "SSL: servidor HTTPS arrancado en puerto " + hb_NToS( SSL_PORT ), ".T.", iif( oSrv:lRunning, ".T.", ".F." ) )
RETURN

// ============================================================
// Suite 5 — HTTPS GET requests
// ============================================================
STATIC PROCEDURE _SslHttpsGet( hCtx )
   LOCAL cResp
   _TLog( "_SslHttpsGet" )

   cResp := _HttpsGet( "/ping-ssl" )
   _TLog( "ping-ssl resp=" + cResp )
   HixTU_Check( hCtx, "pong-ssl" $ cResp, "SSL: HTTPS GET /ping-ssl -> pong-ssl",  "pong-ssl", cResp )

   cResp := _HttpsGet( "/hello" )
   _TLog( "hello resp=" + cResp )
   HixTU_Check( hCtx, "hello-ssl" $ cResp, "SSL: HTTPS GET /hello -> hello-ssl", "hello-ssl", cResp )

   cResp := _HttpsGet( "/json-ssl" )
   _TLog( "json-ssl resp=" + cResp )
   HixTU_Check( hCtx, "{" $ cResp,      "SSL: HTTPS GET /json-ssl devuelve JSON",        "{",    cResp )
   HixTU_Check( hCtx, "status" $ cResp, "SSL: HTTPS GET /json-ssl campo status presente","status", cResp )
RETURN

// ============================================================
// Suite 6 — HTTP headers via TLS
// ============================================================
STATIC PROCEDURE _SslHttpsHeaders( hCtx )
   LOCAL cResp, cHeaders
   _TLog( "_SslHttpsHeaders" )

   cHeaders := _HttpsHead( "/ping-ssl" )
   _TLog( "headers=" + cHeaders )
   HixTU_Check( hCtx, "HTTP/" $ cHeaders,       "SSL: respuesta incluye status line HTTP/", "HTTP/",   cHeaders )
   HixTU_Check( hCtx, "200" $ cHeaders,         "SSL: /ping-ssl status 200",               "200",     cHeaders )

   cHeaders := _HttpsHead( "/json-ssl" )
   HixTU_Check( hCtx, "application/json" $ Lower( cHeaders ), "SSL: /json-ssl Content-Type application/json", "application/json", Lower( cHeaders ) )
RETURN

// ============================================================
// Suite 7 — 404 + extra cases
// ============================================================
STATIC PROCEDURE _SslHttpsExtra( hCtx )
   LOCAL cResp, cHeaders
   _TLog( "_SslHttpsExtra" )

   // 404 path
   cResp := _HttpsGet( "/ruta-que-no-existe" )
   _TLog( "404 resp=" + cResp )
   HixTU_Check( hCtx, "Not Found" $ cResp .OR. "404" $ cResp, "SSL: ruta inexistente -> 404 Not Found", "Not Found|404", cResp )

   // Segundo GET al mismo servidor (keep-alive desactivado = nueva conexion)
   cResp := _HttpsGet( "/ping-ssl" )
   HixTU_Check( hCtx, "pong-ssl" $ cResp, "SSL: segundo GET /ping-ssl -> pong-ssl (nueva conexion)", "pong-ssl", cResp )

   // HEAD sobre ruta inexistente devuelve 404 en cabeceras
   cHeaders := _HttpsHead( "/no-existe" )
   HixTU_Check( hCtx, "404" $ cHeaders, "SSL: HEAD /no-existe -> 404 en cabeceras", "404", cHeaders )
RETURN

// ============================================================
// Suite 8 — Parada limpia
// ============================================================
STATIC PROCEDURE _SslServerStop( hCtx )
   LOCAL hCfg, cKey
   _TLog( "_SslServerStop" )
   IF s_oSrvSSL != NIL
      s_oSrvSSL:Stop()
      hb_idleSleep( 0.3 )
      HixTU_Check( hCtx, ! s_oSrvSSL:lRunning, "SSL: servidor detenido limpiamente", ".F.", iif( s_oSrvSSL:lRunning, ".T.", ".F." ) )
      s_oSrvSSL := NIL
   ENDIF
   // Restauracion completa desde el snapshot: evita que 'ssl', 'keep_alive',
   // 'peek_timeout_ms', certs, etc. contaminen tests posteriores.
   IF s_hCfgBackup != NIL
      hCfg := HIX_GetConfig()
      FOR EACH cKey IN hb_HKeys( s_hCfgBackup )
         hCfg[ cKey ] := hb_HClone( s_hCfgBackup[ cKey ] )
      NEXT
      s_hCfgBackup := NIL
   ENDIF
RETURN

// ============================================================
// Helpers curl
// ============================================================
// Localiza curl.exe probando, en orden:
//   1. El bundled del repo (..\bin\curl\curl.exe) — si algun dia se incluye.
//   2. %SystemRoot%\System32\curl.exe — de serie en Windows 10 1803 (abril
//      2018) y posteriores; es el caso normal en una maquina actual.
//   3. Git for Windows, que trae su propio curl.
//   4. Cualquier curl.exe accesible desde el PATH.
// Si ninguno responde, devuelve "" y los tests HTTPS se marcan como saltados.
STATIC FUNCTION _CurlBin()
   LOCAL cTry, cOut := "", cErr := ""
   LOCAL aTry

   IF s_cCurlBin == NIL
      s_cCurlBin := ""
      aTry := { ;
         hb_DirBase() + ".." + hb_ps() + "bin" + hb_ps() + "curl" + hb_ps() + "curl.exe", ;
         GetEnv( "SystemRoot" ) + hb_ps() + "System32" + hb_ps() + "curl.exe", ;
         GetEnv( "ProgramFiles" ) + hb_ps() + "Git" + hb_ps() + "mingw64" + hb_ps() + "bin" + hb_ps() + "curl.exe" }
      FOR EACH cTry IN aTry
         IF ! Empty( cTry ) .AND. File( cTry )
            s_cCurlBin := cTry
            EXIT
         ENDIF
      NEXT
      IF Empty( s_cCurlBin ) .AND. hb_processRun( "curl.exe --version", , @cOut, @cErr ) == 0
         s_cCurlBin := "curl.exe"   // disponible en el PATH
      ENDIF
      _TLog( "curl bin=" + iif( Empty( s_cCurlBin ), "<no encontrado>", s_cCurlBin ) )
   ENDIF
RETURN s_cCurlBin

STATIC FUNCTION _Curl( cArgs, cPath )
   LOCAL cOut := "", cErr := ""
   LOCAL cBin := _CurlBin()
   IF Empty( cBin )
      RETURN ""
   ENDIF
   hb_processRun( '"' + cBin + '" ' + cArgs + " " + CURL_BASE + cPath, , @cOut, @cErr )
RETURN cOut

STATIC FUNCTION _HttpsGet( cPath )
RETURN _Curl( "-sk --max-time 5", cPath )

STATIC FUNCTION _HttpsHead( cPath )
RETURN _Curl( "-ski --max-time 5", cPath )
