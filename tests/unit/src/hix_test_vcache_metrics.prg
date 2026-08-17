/*-----------------------------------------------------------
  File ......: hix_test_vcache_metrics.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-06-18
  Description: Unit test — view RAM cache metrics (vcache_entries,
               vcache_bytes, vcache_hits, vcache_misses).
               Sets up config with hixstyle.cache_ram=.T.,
               renders a template twice and verifies counters.
 -----------------------------------------------------------*/
#include "hbclass.ch"
#include "fileio.ch"
#include "hix_const.ch"

STATIC PROCEDURE _VLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[VCacheM] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

// --------------------------------------------------------- //

FUNCTION HIX_TestVCacheMetrics_Run()
   LOCAL hCtx       := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL oPrevConfig
   LOCAL cViewDir, cViewFile

   HIX_LoadConfig()
   oPrevConfig := hb_HClone( HIX_GetConfig() )

   _VLog( "=== HIX_TestVCacheMetrics_Run start ===" )

   // Temp views dir inside tests.master working dir
   cViewDir  := hb_DirBase() + "hix_vcmtest" + hb_ps() + "views" + hb_ps()
   cViewFile := cViewDir + "vcmtest.html"

   _VMkDirs( cViewDir )
   hb_MemoWrit( cViewFile, ;
      "@args cLabel = 'x'" + hb_eol() + ;
      "<p>{{ cLabel }}</p>" + hb_eol() )

   // Set up config with HixStyle + RAM cache enabled
   HIX_MetricsInit()
   HIX_ViewCacheInit()
   _VApplyConfig( "hix_vcmtest" )

   _VTestMiss(       hCtx )
   _VTestHit(        hCtx )
   _VTestEntries(    hCtx )
   _VTestBytes(      hCtx )
   _VTestClear(      hCtx )

   // Restore
   HIX_ViewCacheClear()
   HIX_SetConfig( oPrevConfig )
   hb_FileDelete( cViewFile )
   hb_DirDelete( hb_StrShrink( cViewDir, 1 ) )
   hb_DirDelete( hb_DirBase() + "hix_vcmtest" )

   _VLog( "=== HIX_TestVCacheMetrics_Run end ===" )
RETURN hCtx

// --------------------------------------------------------- //

STATIC PROCEDURE _VTestMiss( hCtx )
   LOCAL cHtml, nMiss
   _VLog( "_VTestMiss" )
   nMiss := HIX_MetricGet( HIXM_VCACHE_MISSES )
   cHtml := UView( "/vcmtest.html", "hello" )
   HixTU_Check( hCtx, ! Empty( cHtml ),                          "VCache: miss renders ok",     "!empty", iif( Empty( cHtml ), "empty", "ok" ) )
   HixTU_Check( hCtx, HIX_MetricGet( HIXM_VCACHE_MISSES ) > nMiss, "VCache: miss counter +1",  ">prev",  hb_NToS( HIX_MetricGet( HIXM_VCACHE_MISSES ) ) )
   _VLog( "miss=" + hb_NToS( HIX_MetricGet( HIXM_VCACHE_MISSES ) ) )
RETURN

STATIC PROCEDURE _VTestHit( hCtx )
   LOCAL cHtml, nHit
   _VLog( "_VTestHit" )
   nHit  := HIX_MetricGet( HIXM_VCACHE_HITS )
   cHtml := UView( "/vcmtest.html", "hello" )
   HixTU_Check( hCtx, ! Empty( cHtml ),                        "VCache: hit renders ok",  "!empty", iif( Empty( cHtml ), "empty", "ok" ) )
   HixTU_Check( hCtx, HIX_MetricGet( HIXM_VCACHE_HITS ) > nHit, "VCache: hit counter +1", ">prev",  hb_NToS( HIX_MetricGet( HIXM_VCACHE_HITS ) ) )
   _VLog( "hits=" + hb_NToS( HIX_MetricGet( HIXM_VCACHE_HITS ) ) )
RETURN

STATIC PROCEDURE _VTestEntries( hCtx )
   LOCAL nEntries := HIX_MetricGet( HIXM_VCACHE_ENTRIES )
   _VLog( "_VTestEntries entries=" + hb_NToS( nEntries ) )
   HixTU_Check( hCtx, nEntries == 1, "VCache: entries=1 after one view", "1", hb_NToS( nEntries ) )
RETURN

STATIC PROCEDURE _VTestBytes( hCtx )
   LOCAL nBytes := HIX_MetricGet( HIXM_VCACHE_BYTES )
   _VLog( "_VTestBytes bytes=" + hb_NToS( nBytes ) )
   HixTU_Check( hCtx, nBytes > 0, "VCache: bytes>0", ">0", hb_NToS( nBytes ) )
RETURN

STATIC PROCEDURE _VTestClear( hCtx )
   LOCAL nEntries, nBytes
   _VLog( "_VTestClear" )
   HIX_ViewCacheClear()
   nEntries := HIX_MetricGet( HIXM_VCACHE_ENTRIES )
   nBytes   := HIX_MetricGet( HIXM_VCACHE_BYTES )
   HixTU_Check( hCtx, nEntries == 0, "VCache: entries=0 after clear", "0", hb_NToS( nEntries ) )
   HixTU_Check( hCtx, nBytes   == 0, "VCache: bytes=0 after clear",   "0", hb_NToS( nBytes   ) )
   _VLog( "after clear: entries=" + hb_NToS( nEntries ) + " bytes=" + hb_NToS( nBytes ) )
RETURN

// --------------------------------------------------------- //

STATIC PROCEDURE _VApplyConfig( cRoot )
   LOCAL hCfg := HIX_GetConfig()
   hCfg[ "paths"    ][ "root" ]             := cRoot
   hCfg[ "hixstyle" ][ "enabled" ]          := .T.
   hCfg[ "hixstyle" ][ "cache_ram" ]        := .T.
   hCfg[ "hixstyle" ][ "cache_disk" ]       := .F.
   hCfg[ "hixstyle" ][ "trace" ]            := .F.
RETURN

STATIC PROCEDURE _VMkDirs( cPath )
   LOCAL cParts, cBuild, cPart
   cParts := hb_ATokens( hb_StrShrink( cPath, 1 ), hb_ps() )
   cBuild := ""
   FOR EACH cPart IN cParts
      cBuild += cPart + hb_ps()
      IF ! hb_DirExists( hb_StrShrink( cBuild, 1 ) )
         hb_DirCreate( hb_StrShrink( cBuild, 1 ) )
      ENDIF
   NEXT
RETURN
