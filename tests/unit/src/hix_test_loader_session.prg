/*-----------------------------------------------------------
  File ......: hix_test_loader_session.prg
  Author.....: Charly 9000
  Created....: 2026-10-18
  Modified...: 2026-10-18
  Version....: 1.0.0
  Description: Verifies that HIX_LoadMiddleware() propagates
               hix.json > session { prefix, crypt, seed, gc_days }
               to HIX_MwSessionSetup(). Prior to v2.4.3 those four
               keys were parsed by hix_mw_loader but never passed
               through, so "crypt": true was a silent no-op
               (session payloads stayed in plaintext on disk).
  Usage      : Invoked from tests/unit app CLI runner
               (group "Middleware" -> "LoaderSession").
  Notes      : Writes a temp www/middlewares/config.json,
               patches the global config with session settings,
               calls HIX_LoadMiddleware(), reads HIX_MwSessionConfig()
               and restores state.
 -----------------------------------------------------------*/
#include "hix_logger.ch"

STATIC FUNCTION _LsMwDir()
RETURN "www" + hb_ps() + "middlewares"

STATIC PROCEDURE _LsWriteMwConfig( hConfig )
   LOCAL cDir := _LsMwDir()
   IF ! hb_DirExists( "www" ) ; hb_DirCreate( "www" ) ; ENDIF
   IF ! hb_DirExists( cDir  ) ; hb_DirCreate( cDir  ) ; ENDIF
   hb_MemoWrit( cDir + hb_ps() + "config.json", hb_jsonEncode( hConfig ) )
RETURN

STATIC PROCEDURE _LsCleanupMwDir()
   LOCAL cDir, cFile
   cDir  := _LsMwDir()
   cFile := cDir + hb_ps() + "config.json"
   IF hb_FileExists( cFile ) ; HIX_SafeErase( cFile ) ; ENDIF
   HIX_SafeDirDelete( cDir )
RETURN

// Patch the global config with explicit session + paths sections,
// returning the previous config so the caller can restore it.
STATIC FUNCTION _LsPatchConfig( cPrefix, lCrypt, cSeed, nGcDays, cSessionPath )
   LOCAL hBackup := hb_HClone( HIX_GetConfig() )
   LOCAL hCfg    := hb_HClone( HIX_GetConfig() )
   LOCAL hPaths, hSess

   hPaths := iif( hb_HHasKey( hCfg, "paths" ), hb_HClone( hCfg[ "paths" ] ), { => } )
   hPaths[ "session" ] := cSessionPath
   hCfg[ "paths" ] := hPaths

   hSess := { ;
      "storage"  => "memory", ;
      "prefix"   => cPrefix,  ;
      "crypt"    => lCrypt,   ;
      "seed"     => cSeed,    ;
      "gc_days"  => nGcDays   }
   hCfg[ "session" ] := hSess

   HIX_SetConfig( hCfg )
RETURN hBackup

FUNCTION HIX_TestLoaderSession_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _LsCaseAllFields(   hCtx )
   _LsCaseEmptyPrefix( hCtx )
   _LsCaseSeedBool(    hCtx )

   _LsCleanupMwDir()

RETURN hCtx

// ------------------------------------------------------------
// Case A: hix.json > session with all four fields set must
// propagate to HIX_MwSessionConfig() verbatim.
// Regression: the pre-v2.4.3 loader passed only 4 args to
// HIX_MwSessionSetup; prefix/crypt/seed/gc_days were ignored.
// ------------------------------------------------------------
STATIC PROCEDURE _LsCaseAllFields( hCtx )

   LOCAL hBackup, hSess
   LOCAL cTmpSess := hb_DirTemp() + "hix_tm_loader_sess"

   hBackup := _LsPatchConfig( "lx_", .T., "semilla_test_a", 7, cTmpSess )

   _LsWriteMwConfig( { ;
      "load"  => {}, ;
      "setup" => { ;
         "session" => { ;
            "cookie"  => "HIXSID_TEST", ;
            "ttl"     => 120, ;
            "max"     => 50,  ;
            "storage" => "memory" ;
         } ;
      } ;
   } )

   HIX_LoadMiddleware()

   hSess := HIX_MwSessionConfig()

   HixTU_Check( hCtx, hSess[ "prefix" ] == "lx_", ;
      "LoaderSession A: prefix propagated", "lx_", hSess[ "prefix" ] )

   HixTU_Check( hCtx, hSess[ "crypt" ] == .T., ;
      "LoaderSession A: crypt=true propagated", ".T.", hb_CStr( hSess[ "crypt" ] ) )

   HixTU_Check( hCtx, hSess[ "gc_days" ] == 7, ;
      "LoaderSession A: gc_days propagated", "7", hb_NToS( hSess[ "gc_days" ] ) )

   HixTU_Check( hCtx, hSess[ "seed_set" ] == .T., ;
      "LoaderSession A: seed propagated (non-empty)", ".T.", hb_CStr( hSess[ "seed_set" ] ) )

   HixTU_Check( hCtx, hSess[ "path" ] == cTmpSess, ;
      "LoaderSession A: paths.session propagated", cTmpSess, hSess[ "path" ] )

   HixTU_Check( hCtx, hSess[ "storage" ] == "memory", ;
      "LoaderSession A: storage from middleware setup", "memory", hSess[ "storage" ] )

   HixTU_Check( hCtx, hSess[ "ttl" ] == 120, ;
      "LoaderSession A: ttl from middleware setup", "120", hb_NToS( hSess[ "ttl" ] ) )

   HIX_SetConfig( hBackup )

RETURN

// ------------------------------------------------------------
// Case B: an empty "prefix" in hix.json must not overwrite the
// current prefix with "". The loader treats Empty(prefix) as
// "keep the built-in" by passing NIL to HIX_MwSessionSetup.
// ------------------------------------------------------------
STATIC PROCEDURE _LsCaseEmptyPrefix( hCtx )

   LOCAL hBackup, hSess
   LOCAL cTmpSess := hb_DirTemp() + "hix_tm_loader_sess"

   // First pass: install a known prefix.
   hBackup := _LsPatchConfig( "ANCHOR_", .F., "", 3, cTmpSess )
   _LsWriteMwConfig( { ;
      "load"  => {}, ;
      "setup" => { ;
         "session" => { ;
            "cookie" => "HIXSID_TEST", "ttl" => 60, "max" => 10, "storage" => "memory" ;
         } ;
      } ;
   } )
   HIX_LoadMiddleware()
   HIX_SetConfig( hBackup )

   // Second pass: prefix="" in hix.json must preserve the previous value.
   hBackup := _LsPatchConfig( "", .F., "", 3, cTmpSess )
   _LsWriteMwConfig( { ;
      "load"  => {}, ;
      "setup" => { ;
         "session" => { ;
            "cookie" => "HIXSID_TEST", "ttl" => 60, "max" => 10, "storage" => "memory" ;
         } ;
      } ;
   } )
   HIX_LoadMiddleware()

   hSess := HIX_MwSessionConfig()

   HixTU_Check( hCtx, hSess[ "prefix" ] == "ANCHOR_", ;
      "LoaderSession B: empty prefix keeps previous value", ;
      "ANCHOR_", hSess[ "prefix" ] )

   HIX_SetConfig( hBackup )

RETURN

// ------------------------------------------------------------
// Case C: crypt=false explicit must be propagated (not just
// defaulted). Covers the inverse of case A.
// ------------------------------------------------------------
STATIC PROCEDURE _LsCaseSeedBool( hCtx )

   LOCAL hBackup, hSess
   LOCAL cTmpSess := hb_DirTemp() + "hix_tm_loader_sess"

   hBackup := _LsPatchConfig( "cx_", .F., "seed_c_only", 14, cTmpSess )

   _LsWriteMwConfig( { ;
      "load"  => {}, ;
      "setup" => { ;
         "session" => { ;
            "cookie" => "HIXSID_TEST", "ttl" => 60, "max" => 10, "storage" => "memory" ;
         } ;
      } ;
   } )

   HIX_LoadMiddleware()

   hSess := HIX_MwSessionConfig()

   HixTU_Check( hCtx, hSess[ "crypt" ] == .F., ;
      "LoaderSession C: crypt=false explicit propagated", ".F.", hb_CStr( hSess[ "crypt" ] ) )

   HixTU_Check( hCtx, hSess[ "gc_days" ] == 14, ;
      "LoaderSession C: gc_days=14 propagated", "14", hb_NToS( hSess[ "gc_days" ] ) )

   HixTU_Check( hCtx, hSess[ "seed_set" ] == .T., ;
      "LoaderSession C: seed propagated", ".T.", hb_CStr( hSess[ "seed_set" ] ) )

   HIX_SetConfig( hBackup )

RETURN
