/*-----------------------------------------------------------
  File ......: hix_test_loader_cache.prg
  Author.....: Charly 9000
  Created....: 2026-11-10
  Modified...: 2026-11-10
  Version....: 1.0.0
  Description: Verifies the loader cache migration introduced in
               v2.4.8: HIX_Loaders() compiles www/loaders/*.prg
               into .cached/loaders/*.hrb (same convention as
               views), never writes .hrb.md5 sidecars, and
               purges legacy artifacts left in www/loaders/ by
               the previous scheme.
  Usage      : Invoked from tests/unit app CLI runner
               (group "Middleware" -> "LoaderCache").
  Notes      : Patches paths.root to a disposable tree under
               hb_dirbase() so the real www/loaders/ of the
               test runner stays untouched. Restores config
               and re-runs HIX_Loaders() at the end so other
               tests see the same s_aModules state as before.
 -----------------------------------------------------------*/
#include "hix_logger.ch"
#include "directry.ch"

STATIC s_cRoot       := "www_tm_loadcache"
STATIC s_cStubName   := "_hixtest_loader_cache_dummy.prg"
STATIC s_cStubFuncUp := "_HIXTESTLOADERCACHEDUMMY"

STATIC FUNCTION _LcBaseDir()
RETURN hb_DirBase() + s_cRoot + hb_ps() + "loaders" + hb_ps()

STATIC FUNCTION _LcCacheDir()
RETURN hb_DirBase() + ".cached" + hb_ps() + "loaders" + hb_ps()

STATIC FUNCTION _LcStubBody()
   LOCAL cBody := ""
   cBody += "FUNCTION _HixTestLoaderCacheDummy()" + hb_eol()
   cBody += "RETURN .T." + hb_eol()
RETURN cBody

STATIC PROCEDURE _LcMakeTree()
   LOCAL cRoot := hb_DirBase() + s_cRoot
   LOCAL cDir  := _LcBaseDir()
   IF ! hb_DirExists( cRoot ) ; hb_DirCreate( cRoot ) ; ENDIF
   IF ! hb_DirExists( hb_StrShrink( cDir, 1 ) )
      hb_DirCreate( hb_StrShrink( cDir, 1 ) )
   ENDIF
   hb_MemoWrit( cDir + s_cStubName, _LcStubBody() )
RETURN

STATIC PROCEDURE _LcCleanupTree()
   LOCAL cDir := _LcBaseDir()
   LOCAL cHrb := _LcCacheDir() + "_hixtest_loader_cache_dummy.hrb"

   // Remove the cached hrb this test created so other test runs start clean.
   IF hb_FileExists( cHrb )
      HIX_SafeErase( cHrb )
   ENDIF

   // Remove any legacy artifact the test may have seeded next to the prg.
   IF hb_FileExists( cDir + "_hixtest_loader_cache_dummy.hrb" )
      HIX_SafeErase( cDir + "_hixtest_loader_cache_dummy.hrb" )
   ENDIF
   IF hb_FileExists( cDir + "_hixtest_loader_cache_dummy.hrb.md5" )
      HIX_SafeErase( cDir + "_hixtest_loader_cache_dummy.hrb.md5" )
   ENDIF
   IF hb_FileExists( cDir + s_cStubName )
      HIX_SafeErase( cDir + s_cStubName )
   ENDIF

   HIX_SafeDirDelete( cDir )
   HIX_SafeDirDelete( hb_DirBase() + s_cRoot )
RETURN

STATIC FUNCTION _LcPatchConfig()
   LOCAL hBackup := hb_HClone( HIX_GetConfig() )
   LOCAL hCfg    := hb_HClone( HIX_GetConfig() )
   LOCAL hPaths

   hPaths := iif( hb_HHasKey( hCfg, "paths" ), hb_HClone( hCfg[ "paths" ] ), { => } )
   hPaths[ "root" ] := s_cRoot
   hCfg[ "paths" ]  := hPaths
   HIX_SetConfig( hCfg )
RETURN hBackup

STATIC FUNCTION _LcPatchConfigNoCache()
   LOCAL hBackup := hb_HClone( HIX_GetConfig() )
   LOCAL hCfg    := hb_HClone( HIX_GetConfig() )
   LOCAL hPaths, hHixStyle

   hPaths := iif( hb_HHasKey( hCfg, "paths" ), hb_HClone( hCfg[ "paths" ] ), { => } )
   hPaths[ "root" ] := s_cRoot
   hCfg[ "paths" ]  := hPaths

   hHixStyle := iif( hb_HHasKey( hCfg, "hixstyle" ), hb_HClone( hCfg[ "hixstyle" ] ), { => } )
   hHixStyle[ "cache_disk" ] := .F.
   hCfg[ "hixstyle" ] := hHixStyle

   HIX_SetConfig( hCfg )
RETURN hBackup

FUNCTION HIX_TestLoaderCache_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _LcCleanupTree()

   _LcCaseCacheLocation( hCtx )
   _LcCasePurgeLegacy(   hCtx )
   _LcCaseMtimeRecompile( hCtx )
   _LcCaseNoCacheInMemory( hCtx )

   _LcCleanupTree()

   // Restore the real loader state so subsequent tests see s_aModules
   // populated from the runner's own www/loaders/.
   HIX_Loaders()

RETURN hCtx

// ------------------------------------------------------------
// Case A: compiling a fresh .prg places the .hrb in .cached/loaders/
// and never writes a .md5 sidecar; the user function is registered.
// ------------------------------------------------------------
STATIC PROCEDURE _LcCaseCacheLocation( hCtx )

   LOCAL hBackup
   LOCAL cHrbCache  := _LcCacheDir() + "_hixtest_loader_cache_dummy.hrb"
   LOCAL cHrbLegacy := _LcBaseDir()  + "_hixtest_loader_cache_dummy.hrb"
   LOCAL cMd5Cache  := _LcCacheDir() + "_hixtest_loader_cache_dummy.hrb.md5"
   LOCAL cMd5Legacy := _LcBaseDir()  + "_hixtest_loader_cache_dummy.hrb.md5"

   _LcMakeTree()
   hBackup := _LcPatchConfig()

   HIX_Loaders()

   HixTU_Check( hCtx, hb_FileExists( cHrbCache ), ;
      "LoaderCache A: hrb compilado en .cached/loaders/", ;
      ".T.", hb_ValToStr( hb_FileExists( cHrbCache ) ) )

   HixTU_Check( hCtx, ! hb_FileExists( cHrbLegacy ), ;
      "LoaderCache A: no hrb en www/loaders/", ;
      ".F.", hb_ValToStr( hb_FileExists( cHrbLegacy ) ) )

   HixTU_Check( hCtx, ! hb_FileExists( cMd5Cache ) .AND. ! hb_FileExists( cMd5Legacy ), ;
      "LoaderCache A: sin sidecar .hrb.md5", ;
      ".F.", hb_ValToStr( hb_FileExists( cMd5Cache ) .OR. hb_FileExists( cMd5Legacy ) ) )

   HixTU_Check( hCtx, HIX_LoaderIsUserFunc( s_cStubFuncUp ), ;
      "LoaderCache A: funcion del loader registrada", ;
      ".T.", hb_ValToStr( HIX_LoaderIsUserFunc( s_cStubFuncUp ) ) )

   HIX_SetConfig( hBackup )

RETURN

// ------------------------------------------------------------
// Case B: legacy .hrb and .hrb.md5 found in www/loaders/ must be
// purged on startup (auto-cleanup from the old scheme).
// ------------------------------------------------------------
STATIC PROCEDURE _LcCasePurgeLegacy( hCtx )

   LOCAL hBackup
   LOCAL cDir       := _LcBaseDir()
   LOCAL cHrbLegacy := cDir + "_hixtest_loader_cache_dummy.hrb"
   LOCAL cMd5Legacy := cDir + "_hixtest_loader_cache_dummy.hrb.md5"

   _LcCleanupTree()
   _LcMakeTree()

   // Seed legacy artifacts next to the .prg (simulate pre-v2.4.8 state).
   hb_MemoWrit( cHrbLegacy, "LEGACY_HRB_PLACEHOLDER" )
   hb_MemoWrit( cMd5Legacy, hb_MD5( "LEGACY_HRB_PLACEHOLDER" ) )

   hBackup := _LcPatchConfig()
   HIX_Loaders()

   HixTU_Check( hCtx, ! hb_FileExists( cHrbLegacy ), ;
      "LoaderCache B: legacy .hrb en www/loaders/ purgado", ;
      ".F.", hb_ValToStr( hb_FileExists( cHrbLegacy ) ) )

   HixTU_Check( hCtx, ! hb_FileExists( cMd5Legacy ), ;
      "LoaderCache B: legacy .hrb.md5 en www/loaders/ purgado", ;
      ".F.", hb_ValToStr( hb_FileExists( cMd5Legacy ) ) )

   HIX_SetConfig( hBackup )

RETURN

// ------------------------------------------------------------
// Case C: when the cached .hrb is older than the source .prg, the
// loader must recompile and overwrite the cached copy.
// ------------------------------------------------------------
STATIC PROCEDURE _LcCaseMtimeRecompile( hCtx )

   LOCAL hBackup
   LOCAL cHrbCache := _LcCacheDir() + "_hixtest_loader_cache_dummy.hrb"
   LOCAL tOld      := hb_DateTime() - 1  /* 1 day ago */
   LOCAL aInfoPre, aInfoPost
   LOCAL lRecompiled

   _LcCleanupTree()
   _LcMakeTree()

   hBackup := _LcPatchConfig()
   HIX_Loaders()   // first pass — creates the cached hrb

   HixTU_Check( hCtx, hb_FileExists( cHrbCache ), ;
      "LoaderCache C: hrb compilado en primera pasada", ;
      ".T.", hb_ValToStr( hb_FileExists( cHrbCache ) ) )

   // Backdate the cached hrb so its mtime is older than the .prg.
   hb_vfTimeSet( cHrbCache, tOld )
   aInfoPre := Directory( cHrbCache )

   // Second pass: mtime mismatch must trigger recompile.
   HIX_Loaders()
   aInfoPost := Directory( cHrbCache )

   lRecompiled := ! Empty( aInfoPost ) .AND. ;
      ( DToS( aInfoPost[ 1 ][ F_DATE ] ) + aInfoPost[ 1 ][ F_TIME ] ) > ;
      ( DToS( aInfoPre[  1 ][ F_DATE ] ) + aInfoPre[  1 ][ F_TIME ] )

   HixTU_Check( hCtx, lRecompiled, ;
      "LoaderCache C: hrb antiguo recompilado por mtime", ;
      ".T.", hb_ValToStr( lRecompiled ) )

   HIX_SetConfig( hBackup )

RETURN

// ------------------------------------------------------------
// Case D: hixstyle.cache_disk = .F. — loader compila en memoria,
// no persiste nada en .cached/loaders/, pero la funcion queda
// registrada igualmente.
// ------------------------------------------------------------
STATIC PROCEDURE _LcCaseNoCacheInMemory( hCtx )

   LOCAL hBackup
   LOCAL cHrbCache := _LcCacheDir() + "_hixtest_loader_cache_dummy.hrb"

   _LcCleanupTree()
   _LcMakeTree()

   // Asegurar que no hay HRB residual de pasadas anteriores.
   IF hb_FileExists( cHrbCache )
      HIX_SafeErase( cHrbCache )
   ENDIF

   hBackup := _LcPatchConfigNoCache()
   HIX_Loaders()

   HixTU_Check( hCtx, ! hb_FileExists( cHrbCache ), ;
      "LoaderCache D: sin cache_disk no se crea hrb en .cached/loaders/", ;
      ".F.", hb_ValToStr( hb_FileExists( cHrbCache ) ) )

   HixTU_Check( hCtx, HIX_LoaderIsUserFunc( s_cStubFuncUp ), ;
      "LoaderCache D: funcion registrada tras compile in-memory", ;
      ".T.", hb_ValToStr( HIX_LoaderIsUserFunc( s_cStubFuncUp ) ) )

   HIX_SetConfig( hBackup )

RETURN
