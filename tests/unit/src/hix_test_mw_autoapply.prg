/*-----------------------------------------------------------
  File ......: hix_test_mw_autoapply.prg
  Author.....: Charly 9000
  Created....: 2026-07-21
  Modified...: 2026-07-21
  Version....: 1.0.0
  Description: Integration test — verifies that HIX_LoadMiddleware()
               auto-applies the setup sections declared in
               www/middlewares/config.json for cors, ratelimit,
               methodfilter and jwt middlewares.
  Usage      : Invoked from tests.master app CLI runner
  Notes      : Writes a temp www/middlewares/config.json,
               calls HIX_LoadMiddleware(), reads back through the
               HIX_Mw*Config() getters, and restores state.
 -----------------------------------------------------------*/
#include "hix_logger.ch"

STATIC FUNCTION _MwDir()
RETURN "www" + hb_ps() + "middlewares"

STATIC PROCEDURE _WriteMwConfig( hConfig )
   LOCAL cDir := _MwDir()
   IF ! hb_DirExists( "www" ) ; hb_DirCreate( "www" ) ; ENDIF
   IF ! hb_DirExists( cDir  ) ; hb_DirCreate( cDir  ) ; ENDIF
   hb_MemoWrit( cDir + hb_ps() + "config.json", hb_jsonEncode( hConfig ) )
RETURN

STATIC PROCEDURE _CleanupMwDir()
   LOCAL cDir, cFile
   cDir  := _MwDir()
   cFile := cDir + hb_ps() + "config.json"
   IF hb_FileExists( cFile ) ; hb_vfErase( cFile ) ; ENDIF
   hb_vfDirRemove( cDir )
RETURN

FUNCTION HIX_TestMwAutoApply_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _MwCaseFull(       hCtx )
   _MwCaseJwtKeyRef(  hCtx )
   _MwCaseAbsentKeep( hCtx )

   _CleanupMwDir()

RETURN hCtx

// ------------------------------------------------------------
// Case A: full setup section -> the four getters return the
// exact values written in the JSON.
// ------------------------------------------------------------
STATIC PROCEDURE _MwCaseFull( hCtx )

   LOCAL hCors, hRl, hMf, hJwt
   LOCAL aMethods

   _WriteMwConfig( { ;
      "load"  => {}, ;
      "setup" => { ;
         "cors" => { ;
            "origin"  => "https://example.test", ;
            "methods" => "GET,POST,PATCH", ;
            "headers" => "Content-Type,X-Custom" ;
         }, ;
         "ratelimit" => { ;
            "ip_per_min" => 42, ;
            "window_s"   => 30  ;
         }, ;
         "methodfilter" => { ;
            "methods" => { "GET", "POST", "OPTIONS" } ;
         }, ;
         "jwt" => { ;
            "key" => "T3st-JwT-Key", ;
            "exp" => 900 ;
         } ;
      } ;
   } )

   HIX_LoadMiddleware()

   hCors := HIX_MwCorsConfig()
   HixTU_Check( hCtx, hCors[ "origin" ] == "https://example.test",  ;
      "MwAutoApply: cors.origin",  "https://example.test", hCors[ "origin" ] )
   HixTU_Check( hCtx, hCors[ "methods" ] == "GET,POST,PATCH",       ;
      "MwAutoApply: cors.methods", "GET,POST,PATCH",      hCors[ "methods" ] )
   HixTU_Check( hCtx, hCors[ "headers" ] == "Content-Type,X-Custom", ;
      "MwAutoApply: cors.headers", "Content-Type,X-Custom", hCors[ "headers" ] )

   hRl := HIX_MwRateLimitConfig()
   HixTU_Check( hCtx, hRl[ "max" ]      == 42, ;
      "MwAutoApply: ratelimit.max",      "42", hb_NToS( hRl[ "max" ] ) )
   HixTU_Check( hCtx, hRl[ "window_s" ] == 30, ;
      "MwAutoApply: ratelimit.window_s", "30", hb_NToS( hRl[ "window_s" ] ) )

   hMf      := HIX_MwMethodFilterConfig()
   aMethods := hMf[ "methods" ]
   HixTU_Check( hCtx, Len( aMethods ) == 3, ;
      "MwAutoApply: methodfilter len",  "3", hb_NToS( Len( aMethods ) ) )
   HixTU_Check( hCtx, AScan( aMethods, {|c| c == "GET" } ) > 0, ;
      "MwAutoApply: methodfilter has GET",  ">0",  ;
      hb_NToS( AScan( aMethods, {|c| c == "GET" } ) ) )
   HixTU_Check( hCtx, AScan( aMethods, {|c| c == "OPTIONS" } ) > 0, ;
      "MwAutoApply: methodfilter has OPTIONS",  ">0",  ;
      hb_NToS( AScan( aMethods, {|c| c == "OPTIONS" } ) ) )

   hJwt := HIX_MwJwtConfig()
   HixTU_Check( hCtx, hJwt[ "exp" ] == 900, ;
      "MwAutoApply: jwt.exp", "900", hb_NToS( hJwt[ "exp" ] ) )
   HixTU_Check( hCtx, hJwt[ "key" ] == "T3st-JwT-Key", ;
      "MwAutoApply: jwt.key", "T3st-JwT-Key", hJwt[ "key" ] )

RETURN

// ------------------------------------------------------------
// Case B: jwt.key_ref must resolve via the HIX_Keys store.
// ------------------------------------------------------------
STATIC PROCEDURE _MwCaseJwtKeyRef( hCtx )

   LOCAL hJwt

   HIX_KeySet( "jwt_test_alias", "RefResolved-XYZ" )

   _WriteMwConfig( { ;
      "load"  => {}, ;
      "setup" => { ;
         "jwt" => { ;
            "key_ref" => "jwt_test_alias", ;
            "exp"     => 1800 ;
         } ;
      } ;
   } )

   HIX_LoadMiddleware()

   hJwt := HIX_MwJwtConfig()
   HixTU_Check( hCtx, hJwt[ "key" ] == "RefResolved-XYZ", ;
      "MwAutoApply: jwt.key_ref resolved", "RefResolved-XYZ", hJwt[ "key" ] )
   HixTU_Check( hCtx, hJwt[ "exp" ] == 1800, ;
      "MwAutoApply: jwt.exp after key_ref", "1800", hb_NToS( hJwt[ "exp" ] ) )

RETURN

// ------------------------------------------------------------
// Case C: sections absent from JSON must not overwrite state
// left by a previous load.
// ------------------------------------------------------------
STATIC PROCEDURE _MwCaseAbsentKeep( hCtx )

   LOCAL hCors, hRl, hMf

   _WriteMwConfig( { ;
      "load"  => {}, ;
      "setup" => { => } ;
   } )

   HIX_LoadMiddleware()

   hCors := HIX_MwCorsConfig()
   HixTU_Check( hCtx, hCors[ "origin" ] == "https://example.test", ;
      "MwAutoApply: cors.origin kept when absent", ;
      "https://example.test", hCors[ "origin" ] )

   hRl := HIX_MwRateLimitConfig()
   HixTU_Check( hCtx, hRl[ "max" ] == 42, ;
      "MwAutoApply: ratelimit.max kept when absent", ;
      "42", hb_NToS( hRl[ "max" ] ) )

   hMf := HIX_MwMethodFilterConfig()
   HixTU_Check( hCtx, Len( hMf[ "methods" ] ) == 3, ;
      "MwAutoApply: methodfilter kept when absent", ;
      "3", hb_NToS( Len( hMf[ "methods" ] ) ) )

RETURN
