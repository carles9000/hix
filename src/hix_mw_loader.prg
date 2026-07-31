/*-----------------------------------------------------------
  File ......: hix_mw_loader.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-24
  Description: Dynamic middleware loader for HIX. Reads middlewares/config.json,
               compiles each listed .prg to HRB and stores handles for the
               process lifetime.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_ROUTER

#INCLUDE "hix_logger.ch"
#INCLUDE "hbhrb.ch"

STATIC s_aHandles  := {}    // handles from HIX_MwLoad/HIX_MwLoadDir
STATIC s_hHandles  := { => }  // handles from HIX_LoadMiddleware (keyed by filename)
STATIC s_hMwSetup  := { => }  // "setup" section from config.json
STATIC s_hAppConfig := { => } // flat app config from HIX_LoadConfigApp()

// ============================================================
// HIX_LoadConfigApp — carga un fichero JSON plano como config de app.
// Sin argumento usa <root>/config.json.
// Los valores quedan accesibles via HIX_AppConfig(cKey, xDef).
// ============================================================
FUNCTION HIX_LoadConfigApp( cFile )

   LOCAL cRoot, cJson, hData

   IF ValType( cFile ) != "C" .OR. Empty( cFile )

      cRoot := UConfig( "paths", "root", "www" )
      cFile := cRoot + hb_ps() + "config.json"

   ENDIF

   IF ! hb_FileExists( cFile )

      l( "HIX_LoadConfigApp: fichero no encontrado — " + cFile )
      RETURN .F.

   ENDIF

   cJson := hb_MemoRead( cFile )

   IF Empty( cJson )

      lw( "HIX_LoadConfigApp: fichero vacio — " + cFile )
      RETURN .F.

   ENDIF

   hData := NIL
   hb_jsonDecode( cJson, @hData )

   IF ValType( hData ) != "H"

      lw( "HIX_LoadConfigApp: JSON invalido en " + cFile )
      RETURN .F.

   ENDIF

   s_hAppConfig := hData
   HIX_BootLogAdd( "config", "load", .T., cFile, hb_NToS( Len( hData ) ) + " keys" )
   l( "HIX_LoadConfigApp: cargado " + cFile )

RETURN .T.

// ============================================================
// HIX_AppConfig — lee un valor del config plano de la app.
// ============================================================
FUNCTION HIX_AppConfig( cKey, xDef )

   hb_default( @xDef, NIL )

   IF Empty( s_hAppConfig )

      RETURN xDef

   ENDIF

RETURN _MwHGet( s_hAppConfig, cKey, xDef )

// ============================================================
// HIX_LoadMiddleware — data-driven loader.
// Reads <root>/middlewares/config.json, compiles each .prg listed
// in "load", stores the "setup" section for HIX_MwConfig().
// Returns number of middlewares loaded successfully.
// ============================================================
FUNCTION HIX_LoadMiddleware()

   LOCAL cRoot, cMwDir, cConfigFile, cJson, hConfig
   LOCAL aLoad, hSetup, cFile, cPhysical, oHrb, pHandle, oErr
   LOCAL nLoaded, nTotal

   nLoaded := 0
   nTotal  := 0

   cRoot       := UConfig( "paths", "root", "www" )
   cMwDir      := cRoot + hb_ps() + "middlewares" + hb_ps()
   cConfigFile := cMwDir + "config.json"

   IF ! hb_FileExists( cConfigFile )

      l( "HIX_LoadMiddleware: config.json no encontrado en " + cMwDir )
      RETURN 0

   ENDIF

   cJson := hb_MemoRead( cConfigFile )

   IF Empty( cJson )

      lw( "HIX_LoadMiddleware: config.json vacio" )
      RETURN 0

   ENDIF

   hConfig := NIL
   hb_jsonDecode( cJson, @hConfig )

   IF ValType( hConfig ) != "H"

      lw( "HIX_LoadMiddleware: JSON invalido en config.json (se espera objeto)" )
      RETURN 0

   ENDIF

   // Guardar seccion "setup" para HIX_MwConfig()
   hSetup := _MwHGet( hConfig, "setup", { => } )

   IF ValType( hSetup ) == "H"

      s_hMwSetup := hSetup

   ENDIF

   // Apply declarative setup sections before any HRB load. Auto-apply
   // must run even when "load" is empty so config-only projects still
   // wire their MW STATICs from JSON.
   _MwApplySession(      s_hMwSetup )
   _MwApplyCsrf(         s_hMwSetup )
   _MwApplyCors(         s_hMwSetup )
   _MwApplyRateLimit(    s_hMwSetup )
   _MwApplyMethodFilter( s_hMwSetup )
   _MwApplyJwt(          s_hMwSetup )

   aLoad := _MwHGet( hConfig, "load", {} )

   IF ValType( aLoad ) != "A" .OR. Empty( aLoad )

      l( "HIX_LoadMiddleware: sin middlewares en 'load'" )
      RETURN 0

   ENDIF

   HIX_BootLogAdd( "middlewares", "scan", .T., cMwDir, hb_NToS( Len( aLoad ) ) + " file(s)" )

   FOR EACH cFile IN aLoad

      IF ValType( cFile ) != "C" .OR. Empty( cFile )

         LOOP

      ENDIF

      nTotal++
      cPhysical := cMwDir + cFile

      oHrb := HIX_CompileFile( cPhysical )

      IF Empty( oHrb )

         lw( "HIX_LoadMiddleware: compile failed -> " + cFile )
         HIX_BootLogAdd( "middlewares", "file", .F., cFile, _( "BOOT_LOADER_COMPILE_FAIL" ) )
         LOOP

      ENDIF

      pHandle := NIL
      oErr    := NIL

      TRY

         pHandle := hb_hrbLoad( HB_HRB_BIND_LOCAL, oHrb )
      CATCH oErr
         lw( "HIX_LoadMiddleware: load failed -> " + cFile + ": " + oErr:description )
         HIX_BootLogAdd( "middlewares", "file", .F., cFile, oErr:description )
         LOOP

      END

      IF pHandle == NIL

         lw( "HIX_LoadMiddleware: handle NIL -> " + cFile )
         HIX_BootLogAdd( "middlewares", "file", .F., cFile, _( "BOOT_LOADER_HANDLE_NIL" ) )
         LOOP

      ENDIF

      s_hHandles[ Lower( cFile ) ] := pHandle
      HIX_BootLogAdd( "middlewares", "file", .T., cFile )
      nLoaded++

   NEXT

   HIX_BootLogAdd( "middlewares", "summary", .T., hb_NToS( nLoaded ) + "/" + hb_NToS( nTotal ) + " loaded" )
   l( "HIX_LoadMiddleware: " + hb_NToS( nLoaded ) + "/" + hb_NToS( nTotal ) + " cargados" )

RETURN nLoaded

// ============================================================
// Aplica setup/session desde el hash de configuracion
// ============================================================
STATIC FUNCTION _MwApplySession( hSetup )

   LOCAL hSess, cCookie, nTtl, nMax, cStorage

   hSess := _MwHGet( hSetup, "session", NIL )

   IF ValType( hSess ) != "H"

      RETURN NIL

   ENDIF

   cCookie  := _MwHGet( hSess, "cookie",  "" )
   nTtl     := _MwHGet( hSess, "ttl",     0  )
   nMax     := _MwHGet( hSess, "max",     0  )
   cStorage := _MwHGet( hSess, "storage", "" )
   HIX_MwSessionSetup( cCookie, nTtl, nMax, cStorage )
   HIX_BootLogAdd( "middlewares", "config", .T., ;
      "session: cookie=" + cCookie + " ttl=" + hb_NToS( nTtl ) + " storage=" + cStorage )

RETURN NIL

// ============================================================
// Aplica setup/csrf desde el hash de configuracion
// ============================================================
STATIC FUNCTION _MwApplyCsrf( hSetup )

   LOCAL hCsrf, cRedirect

   hCsrf := _MwHGet( hSetup, "csrf", NIL )

   IF ValType( hCsrf ) != "H"

      RETURN NIL

   ENDIF

   cRedirect := _MwHGet( hCsrf, "redirect", "" )
   HIX_MwCsrfSetup( cRedirect )
   HIX_BootLogAdd( "middlewares", "config", .T., "csrf: redirect=" + cRedirect )

RETURN NIL

// ============================================================
// Aplica setup/cors desde el hash de configuracion
// ============================================================
STATIC FUNCTION _MwApplyCors( hSetup )

   LOCAL hCors, cOrigin, cMethods, cHeaders

   hCors := _MwHGet( hSetup, "cors", NIL )

   IF ValType( hCors ) != "H"

      RETURN NIL

   ENDIF

   cOrigin  := _MwHGet( hCors, "origin",  "" )
   cMethods := _MwHGet( hCors, "methods", "" )
   cHeaders := _MwHGet( hCors, "headers", "" )
   HIX_MwCorsSetup( cOrigin, cMethods, cHeaders )
   HIX_BootLogAdd( "middlewares", "config", .T., ;
      "cors: origin=" + cOrigin + " methods=" + cMethods )

RETURN NIL

// ============================================================
// Aplica setup/ratelimit desde el hash de configuracion
// ============================================================
STATIC FUNCTION _MwApplyRateLimit( hSetup )

   LOCAL hRl, nMax, nWin

   hRl := _MwHGet( hSetup, "ratelimit", NIL )

   IF ValType( hRl ) != "H"

      RETURN NIL

   ENDIF

   nMax := _MwHGet( hRl, "ip_per_min", 0  )
   nWin := _MwHGet( hRl, "window_s",   60 )

   IF nMax <= 0

      RETURN NIL

   ENDIF

   HIX_MwRateLimitSetup( nMax, nWin )
   HIX_BootLogAdd( "middlewares", "config", .T., ;
      "ratelimit: max=" + hb_NToS( nMax ) + " window_s=" + hb_NToS( nWin ) )

RETURN NIL

// ============================================================
// Aplica setup/methodfilter desde el hash de configuracion
// ============================================================
STATIC FUNCTION _MwApplyMethodFilter( hSetup )

   LOCAL hMf, aMethods

   hMf := _MwHGet( hSetup, "methodfilter", NIL )

   IF ValType( hMf ) != "H"

      RETURN NIL

   ENDIF

   aMethods := _MwHGet( hMf, "methods", NIL )

   IF ValType( aMethods ) != "A" .OR. Empty( aMethods )

      RETURN NIL

   ENDIF

   HIX_MwMethodFilterSetup( aMethods )
   HIX_BootLogAdd( "middlewares", "config", .T., ;
      "methodfilter: methods=" + hb_NToS( Len( aMethods ) ) )

RETURN NIL

// ============================================================
// Aplica setup/jwt desde el hash de configuracion.
// key_ref tiene prioridad sobre key -- resuelve via HIX_KeyGet.
// ============================================================
STATIC FUNCTION _MwApplyJwt( hSetup )

   LOCAL hJwt, cKey, cKeyRef, nExp

   hJwt := _MwHGet( hSetup, "jwt", NIL )

   IF ValType( hJwt ) != "H"

      RETURN NIL

   ENDIF

   cKey    := _MwHGet( hJwt, "key",     "" )
   cKeyRef := _MwHGet( hJwt, "key_ref", "" )
   nExp    := _MwHGet( hJwt, "exp",      0 )

   IF ! Empty( cKeyRef )

      cKey := HIX_KeyGet( cKeyRef, cKey )

   ENDIF

   HIX_MwJwtSetup( cKey, nExp )
   HIX_BootLogAdd( "middlewares", "config", .T., ;
      "jwt: key_ref=" + cKeyRef + " exp=" + hb_NToS( nExp ) )

RETURN NIL

// ============================================================
// HIX_MwConfig — accede a la seccion "setup" de config.json.
// cSection : primer nivel  (ej. "auth")
// cKey     : segundo nivel (ej. "redirect_login")
// xDef     : valor por defecto si no existe
//
// HIX_MwConfig( "auth", "redirect_login" ) -> "/login"
// ============================================================
FUNCTION HIX_MwConfig( cSection, cKey, xDef )

   LOCAL hSection

   hb_default( @xDef, "" )

   IF Empty( s_hMwSetup )

      RETURN xDef

   ENDIF

   hSection := _MwHGet( s_hMwSetup, cSection, NIL )

   IF ValType( hSection ) != "H"

      RETURN xDef

   ENDIF

RETURN _MwHGet( hSection, cKey, xDef )

// ============================================================
// HIX_MwUnload — descarga un middleware cargado por HIX_LoadMiddleware.
// ============================================================
FUNCTION HIX_MwUnload( cFile )

   LOCAL cKey := Lower( cFile )

   IF ! hb_HHasKey( s_hHandles, cKey )

      RETURN .F.

   ENDIF

   hb_hrbUnload( s_hHandles[ cKey ] )
   hb_HDel( s_hHandles, cKey )

RETURN .T.

// ============================================================
// HIX_MwLoad — loads a single pre-compiled .hrb middleware file.
// Returns .T. on success, .F. on error.
// ============================================================
FUNCTION HIX_MwLoad( cFile )

   LOCAL pHandle, oErr

   IF ! File( cFile )

      lw( "HIX_MwLoad: file not found — " + cFile )
      RETURN .F.

   ENDIF

   TRY

      pHandle := hb_hrbLoad( HB_HRB_BIND_LOCAL, cFile )
   CATCH oErr
      lw( "HIX_MwLoad: exception loading '" + cFile + "': " + oErr:description )
      RETURN .F.

   END

   IF pHandle == NIL

      lw( "HIX_MwLoad: failed to load — " + cFile )
      RETURN .F.

   ENDIF

   AAdd( s_aHandles, pHandle )
   l( "HIX_MwLoad: loaded — " + cFile )

RETURN .T.

// ============================================================
// HIX_MwLoadDir — loads all .hrb files in a directory.
// Returns the number of files successfully loaded.
// ============================================================
FUNCTION HIX_MwLoadDir( cDir )

   LOCAL aFiles, cFile, nLoaded := 0

   hb_default( @cDir, "middlewares" )

   IF Right( cDir, 1 ) != hb_ps()

      cDir += hb_ps()

   ENDIF

   aFiles := hb_DirScan( cDir + "*.hrb" )

   IF Empty( aFiles )

      ld( "HIX_MwLoadDir: no .hrb files found in " + cDir )
      RETURN 0

   ENDIF

   FOR EACH cFile IN aFiles

      IF HIX_MwLoad( cDir + cFile[ 1 ] )

         nLoaded++

      ENDIF

   NEXT

   l( "HIX_MwLoadDir: " + hb_NToS( nLoaded ) + " middleware(s) loaded from " + cDir )

RETURN nLoaded

// ============================================================
// Helper privado — lookup case-insensitive en hash JSON
// ============================================================
STATIC FUNCTION _MwHGet( h, cKey, xDef )

   LOCAL cK

   cKey := Lower( cKey )

   FOR EACH cK IN hb_HKeys( h )

      IF Lower( cK ) == cKey

         RETURN h[ cK ]

      ENDIF

   NEXT

RETURN xDef
