/*-----------------------------------------------------------
  File ......: hix_test_viewperf.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-06-18
  Description: Benchmark — view cache modes performance comparison.
               Measures ms/iter for: no cache, disk cache, RAM cache,
               pure HTML — on both simple and complex templates.
               Results written to traces/info.txt.
 -----------------------------------------------------------*/
#include "fileio.ch"
#include "hix_const.ch"

#define BENCH_ITERS  500

STATIC PROCEDURE _BLog( cMsg )
   LOCAL nH := hb_vfOpen( hb_DirBase() + "traces" + hb_ps() + "info.txt", hb_bitOr( FO_WRITE, FO_CREAT ) )
   IF nH != NIL
      hb_vfSeek( nH, 0, FS_END )
      hb_vfWrite( nH, "[ViewPerf] " + cMsg + hb_eol() )
      hb_vfClose( nH )
   ENDIF
RETURN

// --------------------------------------------------------- //

FUNCTION HIX_TestViewPerf_Run()
   LOCAL hCtx      := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }
   LOCAL cTmpDir, nBase
   LOCAL aNoCache, aDiskCache, aRamCache, aPureHtml
   LOCAL aCxNoCache, aCxDiskCache, aCxRamCache

   _BLog( "=== HIX_TestViewPerf_Run start ===" )
   _BLog( "Iters=" + hb_NToS( BENCH_ITERS ) )

   cTmpDir := _BSetup()

   IF Empty( cTmpDir )
      HixTU_Check( hCtx, .F., "ViewPerf: setup tmpdir", "ok", "failed to create tmpdir" )
      RETURN hCtx
   ENDIF

   // --- Simple template (1x @if, 3x {{ }}) ---
   _BLog( "" )
   _BLog( ">>> SIMPLE TEMPLATE (bench.html)" )
   aNoCache   := _BenchNoCache(   hCtx, cTmpDir, "bench.html" )
   aDiskCache := _BenchDiskCache( hCtx, cTmpDir, "bench.html" )
   aRamCache  := _BenchRamCache(  hCtx, cTmpDir, "bench.html" )
   aPureHtml  := _BenchPureHtml(  hCtx, cTmpDir )

   nBase := iif( aPureHtml[1] > 0, aPureHtml[1], 1 )
   _BLog( "" )
   _BLog( "=== Simple template results (N=" + hb_NToS( BENCH_ITERS ) + ") ===" )
   _BLog( PadR( "Scenario",     20 ) + PadL( "Total(ms)", 10 ) + PadL( "ms/iter", 10 ) + PadL( "Factor", 10 ) )
   _BLog( Replicate( "-", 50 ) )
   _BLog( _BRow( "No cache",   aNoCache,   nBase ) )
   _BLog( _BRow( "Disk cache", aDiskCache, nBase ) )
   _BLog( _BRow( "RAM cache",  aRamCache,  nBase ) )
   _BLog( _BRow( "Pure HTML",  aPureHtml,  nBase ) )
   _BLog( Replicate( "=", 50 ) )

   // --- Complex template (@if/@elseif/@else, @for, nested @if, 8x {{ }}) ---
   _BLog( "" )
   _BLog( ">>> COMPLEX TEMPLATE (bench_complex.html)" )
   aCxNoCache   := _BenchNoCache(   hCtx, cTmpDir, "bench_complex.html" )
   aCxDiskCache := _BenchDiskCache( hCtx, cTmpDir, "bench_complex.html" )
   aCxRamCache  := _BenchRamCache(  hCtx, cTmpDir, "bench_complex.html" )

   nBase := iif( aPureHtml[1] > 0, aPureHtml[1], 1 )
   _BLog( "" )
   _BLog( "=== Complex template results (N=" + hb_NToS( BENCH_ITERS ) + ") ===" )
   _BLog( PadR( "Scenario",     20 ) + PadL( "Total(ms)", 10 ) + PadL( "ms/iter", 10 ) + PadL( "Factor", 10 ) )
   _BLog( Replicate( "-", 50 ) )
   _BLog( _BRow( "No cache",   aCxNoCache,   nBase ) )
   _BLog( _BRow( "Disk cache", aCxDiskCache, nBase ) )
   _BLog( _BRow( "RAM cache",  aCxRamCache,  nBase ) )
   _BLog( Replicate( "=", 50 ) )

   _BCleanup( cTmpDir )
   _BLog( "=== HIX_TestViewPerf_Run end ===" )
RETURN hCtx

// --------------------------------------------------------- //

STATIC FUNCTION _BRow( cLabel, aRes, nBase )
   LOCAL nFactor := iif( nBase > 0, aRes[1] / nBase, 0 )
RETURN PadR( cLabel, 20 ) + ;
       PadL( hb_NToS( aRes[1] ), 10 ) + ;
       PadL( LTrim( Str( aRes[2], 10, 2 ) ), 10 ) + ;
       PadL( LTrim( Str( nFactor, 10, 1 ) ) + "x", 10 )

// --------------------------------------------------------- //

STATIC FUNCTION _BSetup()
   LOCAL cDir := hb_DirTemp() + "hix_vperf" + hb_ps()

   hb_DirCreate( cDir )
   IF ! hb_DirExists( hb_StrShrink( cDir, 1 ) )
      RETURN ""
   ENDIF

   // Simple: @args + 1x @if + 3x {{ }}
   hb_MemoWrit( cDir + "bench.html", ;
      "@args cTitle = 'Test', cUser = 'World', nCount = 0" + hb_eol() + ;
      '<div class="bench">' + hb_eol() + ;
      "  <h1>{{ cTitle }}</h1>" + hb_eol() + ;
      "  <p>Hello, {{ cUser }}!</p>" + hb_eol() + ;
      "@if nCount > 0" + hb_eol() + ;
      "  <span>Count: {{ hb_NToS(nCount) }}</span>" + hb_eol() + ;
      "@endif" + hb_eol() + ;
      "  <ul><li>A</li><li>B</li><li>C</li></ul>" + hb_eol() + ;
      "</div>" + hb_eol() )

   // Complex: @if/@elseif/@else/@endif + @for/@next + nested @if + 8x {{ }}
   hb_MemoWrit( cDir + "bench_complex.html", ;
      "@args cTitle = 'Test', cUser = 'World', nCount = 0" + hb_eol() + ;
      '<div class="bench-complex">' + hb_eol() + ;
      "  <h1>{{ cTitle }}</h1>" + hb_eol() + ;
      "@if nCount > 5" + hb_eol() + ;
      "  <p>User: {{ Upper(cUser) }} | High count: {{ hb_NToS(nCount) }}</p>" + hb_eol() + ;
      "@elseif nCount > 0" + hb_eol() + ;
      "  <p>User: {{ cUser }} | Count: {{ hb_NToS(nCount) }}</p>" + hb_eol() + ;
      "@else" + hb_eol() + ;
      "  <p>User: {{ cUser }}</p>" + hb_eol() + ;
      "@endif" + hb_eol() + ;
      "  <ul>" + hb_eol() + ;
      "@for nI := 1 TO 5" + hb_eol() + ;
      "    <li>{{ hb_NToS(nI) }}: {{ cTitle + '-' + hb_NToS(nI) }}</li>" + hb_eol() + ;
      "@next" + hb_eol() + ;
      "  </ul>" + hb_eol() + ;
      "@if nCount > 0" + hb_eol() + ;
      "  <footer><span>Total: {{ hb_NToS(nCount * 2) }}</span></footer>" + hb_eol() + ;
      "@endif" + hb_eol() + ;
      "</div>" + hb_eol() )

   // Pure HTML: no markers at all
   hb_MemoWrit( cDir + "plain.html", ;
      '<div class="bench">' + hb_eol() + ;
      "  <h1>Static Title</h1>" + hb_eol() + ;
      "  <p>Hello, World!</p>" + hb_eol() + ;
      "  <ul><li>A</li><li>B</li><li>C</li></ul>" + hb_eol() + ;
      "</div>" + hb_eol() )

RETURN cDir

STATIC PROCEDURE _BCleanup( cDir )
   hb_FileDelete( cDir + "bench.html" )
   hb_FileDelete( cDir + "bench.hrb" )
   hb_FileDelete( cDir + "bench_complex.html" )
   hb_FileDelete( cDir + "bench_complex.hrb" )
   hb_FileDelete( cDir + "plain.html" )
   hb_DirDelete( hb_StrShrink( cDir, 1 ) )
RETURN

// --------------------------------------------------------- //

STATIC FUNCTION _MakeViewer( cDir, lCache )
   LOCAL oView := HIX_View_Viewer():New()
   oView:lDebug           := .F.
   oView:lCache           := lCache
   oView:llSaveTranspiled := .F.
   oView:lStrictMode      := .F.
   oView:SetPathView( cDir )
RETURN oView

// --------------------------------------------------------- //

STATIC FUNCTION _BenchNoCache( hCtx, cDir, cFile )
   LOCAL oView, i, nT0, nT1, cHtml, oError, cHrb
   LOCAL nTotal := 0, nPer := 0

   cHrb := hb_FNameExtSet( cFile, ".hrb" )
   hb_FileDelete( cDir + cHrb )

   TRY
      oView := _MakeViewer( cDir, .F. )
      oView:SetPrg( cFile )
      oView:Render( "T", "U", 3 )
   CATCH oError
      HixTU_Check( hCtx, .F., "ViewPerf: NoCache warmup [" + cFile + "]", "ok", oError:description )
      RETURN { 0, 0 }
   END

   nT0 := hb_MilliSeconds()
   FOR i := 1 TO BENCH_ITERS
      TRY
         oView := _MakeViewer( cDir, .F. )
         oView:SetPrg( cFile )
         cHtml := oView:Render( "T", "U", 3 )
      CATCH oError
      END
   NEXT
   nT1 := hb_MilliSeconds()

   nTotal := nT1 - nT0
   nPer   := nTotal / BENCH_ITERS

   _BLog( "No cache [" + cFile + "]: " + hb_NToS( nTotal ) + "ms, " + LTrim( Str( nPer, 10, 2 ) ) + "ms/iter" )
   HixTU_Check( hCtx, ! Empty( cHtml ), "ViewPerf: NoCache [" + cFile + "]", "!empty", iif( Empty( cHtml ), "empty", "ok" ) )
RETURN { nTotal, nPer }

// --------------------------------------------------------- //

STATIC FUNCTION _BenchDiskCache( hCtx, cDir, cFile )
   LOCAL oView, i, nT0, nT1, cHtml, oError, cHrb
   LOCAL nTotal := 0, nPer := 0

   cHrb := hb_FNameExtSet( cFile, ".hrb" )
   hb_FileDelete( cDir + cHrb )
   TRY
      oView := _MakeViewer( cDir, .T. )
      oView:SetPrg( cFile )
      oView:Render( "T", "U", 3 )
   CATCH oError
      HixTU_Check( hCtx, .F., "ViewPerf: DiskCache warmup [" + cFile + "]", "ok", oError:description )
      RETURN { 0, 0 }
   END

   nT0 := hb_MilliSeconds()
   FOR i := 1 TO BENCH_ITERS
      TRY
         oView := _MakeViewer( cDir, .T. )
         oView:SetPrg( cFile )
         cHtml := oView:Render( "T", "U", 3 )
      CATCH oError
      END
   NEXT
   nT1 := hb_MilliSeconds()

   nTotal := nT1 - nT0
   nPer   := nTotal / BENCH_ITERS

   _BLog( "Disk cache [" + cFile + "]: " + hb_NToS( nTotal ) + "ms, " + LTrim( Str( nPer, 10, 2 ) ) + "ms/iter" )
   HixTU_Check( hCtx, ! Empty( cHtml ), "ViewPerf: DiskCache [" + cFile + "]", "!empty", iif( Empty( cHtml ), "empty", "ok" ) )
RETURN { nTotal, nPer }

// --------------------------------------------------------- //

STATIC FUNCTION _BenchRamCache( hCtx, cDir, cFile )
   LOCAL oView, i, nT0, nT1, cHtml, oError, oHrbCached
   LOCAL nTotal := 0, nPer := 0

   TRY
      oView := _MakeViewer( cDir, .F. )
      oView:SetPrg( cFile )
      oView:Render( "T", "U", 3 )
      oHrbCached := oView:oHrb
   CATCH oError
      HixTU_Check( hCtx, .F., "ViewPerf: RamCache precompile [" + cFile + "]", "ok", oError:description )
      RETURN { 0, 0 }
   END

   IF Empty( oHrbCached )
      HixTU_Check( hCtx, .F., "ViewPerf: RamCache HRB not nil [" + cFile + "]", "oHrb", "empty" )
      RETURN { 0, 0 }
   ENDIF

   nT0 := hb_MilliSeconds()
   FOR i := 1 TO BENCH_ITERS
      TRY
         oView := _MakeViewer( cDir, .F. )
         oView:SetHrb( NIL, oHrbCached )
         cHtml := oView:Render( "T", "U", 3 )
      CATCH oError
      END
   NEXT
   nT1 := hb_MilliSeconds()

   nTotal := nT1 - nT0
   nPer   := nTotal / BENCH_ITERS

   _BLog( "RAM cache [" + cFile + "]: " + hb_NToS( nTotal ) + "ms, " + LTrim( Str( nPer, 10, 2 ) ) + "ms/iter" )
   HixTU_Check( hCtx, ! Empty( cHtml ), "ViewPerf: RamCache [" + cFile + "]", "!empty", iif( Empty( cHtml ), "empty", "ok" ) )
RETURN { nTotal, nPer }

// --------------------------------------------------------- //

STATIC FUNCTION _BenchPureHtml( hCtx, cDir )
   LOCAL oView, i, nT0, nT1, cHtml, oError
   LOCAL nTotal := 0, nPer := 0

   _BLog( "--- Pure HTML (warmup) ---" )

   TRY
      oView := _MakeViewer( cDir, .F. )
      oView:SetPrg( "plain.html" )
      oView:Render()
   CATCH oError
      HixTU_Check( hCtx, .F., "ViewPerf: PureHtml warmup", "ok", oError:description )
      RETURN { 0, 0 }
   END

   _BLog( "--- Pure HTML (timing " + hb_NToS( BENCH_ITERS ) + " iters) ---" )
   nT0 := hb_MilliSeconds()
   FOR i := 1 TO BENCH_ITERS
      TRY
         oView := _MakeViewer( cDir, .F. )
         oView:SetPrg( "plain.html" )
         cHtml := oView:Render()
      CATCH oError
      END
   NEXT
   nT1 := hb_MilliSeconds()

   nTotal := nT1 - nT0
   nPer   := nTotal / BENCH_ITERS

   _BLog( "Pure HTML: " + hb_NToS( nTotal ) + "ms total, " + LTrim( Str( nPer, 10, 2 ) ) + "ms/iter" )
   HixTU_Check( hCtx, ! Empty( cHtml ), "ViewPerf: PureHtml renders ok", "!empty", iif( Empty( cHtml ), "empty", "ok" ) )
RETURN { nTotal, nPer }
