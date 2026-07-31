/*-----------------------------------------------------------
  File ......: hix_view.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: UView() — main view rendering entry point, compiles and
               executes .view.html templates.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#INCLUDE "hix_const.ch"
#INCLUDE "hix_hrb.ch"

// Global view cache: cViewKey -> { "hrb" => oHrb, "mtime" => tMtime }
STATIC s_hViewCache   := NIL
STATIC s_hViewMtx     := NIL
STATIC s_nVCacheBytes := 0

FUNCTION HIX_ViewCacheInit()

   s_hViewCache   := { => }
   s_hViewMtx     := hb_mutexCreate()
   s_nVCacheBytes := 0

RETURN NIL

FUNCTION HIX_ViewCacheClear()

   IF s_hViewMtx != NIL

      hb_mutexLock( s_hViewMtx )
      s_hViewCache   := { => }
      s_nVCacheBytes := 0
      hb_mutexUnlock( s_hViewMtx )
      HIX_MetricSet( HIXM_VCACHE_ENTRIES, 0 )
      HIX_MetricSet( HIXM_VCACHE_BYTES,   0 )

   ENDIF

RETURN NIL

STATIC FUNCTION _ViewCacheGet( cKey, cFile )

   LOCAL hEntry, tNow, tCached, oHrb, nEntries, nBytes, lHit

   IF s_hViewMtx == NIL ; RETURN NIL ; ENDIF

   lHit := .F.
   tNow := hb_vfTimeGet( cFile )
   hb_mutexLock( s_hViewMtx )

   IF hb_HHasKey( s_hViewCache, cKey )

      hEntry  := s_hViewCache[ cKey ]
      tCached := hEntry[ "mtime" ]

      IF tNow == tCached

         oHrb := hEntry[ "hrb" ]
         lHit := .T.
      ELSE
         s_nVCacheBytes -= Len( hEntry[ "hrb" ] )
         hb_HDel( s_hViewCache, cKey )

      ENDIF

   ENDIF

   nEntries := Len( s_hViewCache )
   nBytes   := s_nVCacheBytes
   hb_mutexUnlock( s_hViewMtx )

   IF lHit

      HIX_Metric( HIXM_VCACHE_HITS )
   ELSE
      HIX_Metric( HIXM_VCACHE_MISSES )

   ENDIF

   HIX_MetricSet( HIXM_VCACHE_ENTRIES, nEntries )
   HIX_MetricSet( HIXM_VCACHE_BYTES,   nBytes   )

RETURN oHrb

STATIC FUNCTION _ViewCachePut( cKey, oHrb, cFile )

   LOCAL nEntries, nBytes

   IF s_hViewMtx == NIL ; RETURN NIL ; ENDIF

   hb_mutexLock( s_hViewMtx )
   s_hViewCache[ cKey ] := { "hrb" => oHrb, "mtime" => hb_vfTimeGet( cFile ) }
   s_nVCacheBytes       += Len( oHrb )
   nEntries := Len( s_hViewCache )
   nBytes   := s_nVCacheBytes
   hb_mutexUnlock( s_hViewMtx )
   HIX_MetricSet( HIXM_VCACHE_ENTRIES, nEntries )
   HIX_MetricSet( HIXM_VCACHE_BYTES,   nBytes   )

RETURN NIL

// ------------------------------------------------- //

FUNCTION UView( cView, ... )

   LOCAL cHtml  := ""
   LOCAL oError

   IF procname( 1 ) == "HIX_TEMPLATE"

      HIX_DoErrorView( NIL, 9009, "Sintax error: use @view directive inside a template", NIL, NIL, "hix_view" )
      RETURN NIL

   ENDIF

   TRY

      cHtml := UView_Exec( cView, ... )
   CATCH oError
      HIX_EchoClear()
      HIX_Throw( oError )

   END

RETURN cHtml

// ------------------------------------------------- //

FUNCTION UView_Exec( cView, ... )

   LOCAL cPathView, oView, oError, cHtml, lCache, lDebug, lHixStyle, lStyleCacheRam
   LOCAL oHrbCached, cPhysFile

   lHixStyle      := UConfig( "hixstyle", "enabled",    .F. )
   lCache         := UConfig( "hixstyle", "cache_disk", .T. )
   lDebug         := UConfig( "hixstyle", "trace",      .F. )
   lStyleCacheRam := UConfig( "hixstyle", "cache_ram",  .F. )

   IF lHixStyle

      cPathView := HIX_GetRootAbsolute() + "views/"
   ELSE
      cPathView := hb_dirBase() + HIX_GetRoot()

   ENDIF

   cPathView := hb_DirSepToOS( cPathView )

   IF Left( cView, 1 ) != "/" .AND. Left( cView, 1 ) != "\"

      cView := hb_ps() + cView

   ENDIF

   cView := hb_DirSepToOS( cView )

   TRY

      oView                  := HIX_View_Viewer():New()
      oView:lCache           := lCache
      oView:lDebug           := lDebug
      oView:lStrictMode      := .T.
      oView:llSaveTranspiled := .F.
      oView:SetPathView( cPathView )

      // Global in-memory cache (cache_view = true)

      IF lStyleCacheRam .AND. s_hViewMtx != NIL

         cPhysFile    := cPathView + cView
         oHrbCached   := _ViewCacheGet( cView, cPhysFile )

         IF oHrbCached != NIL

            oView:SetHrb( NIL, oHrbCached )
         ELSE
            oView:SetPrg( cView )

         ENDIF

      ELSE
         oView:SetPrg( cView )

      ENDIF

      cHtml := oView:Render( ... )

      IF lStyleCacheRam .AND. s_hViewMtx != NIL .AND. ! Empty( oView:oHrb ) .AND. oHrbCached == NIL

         _ViewCachePut( cView, oView:oHrb, cPhysFile )

      ENDIF

   CATCH oError
      break oError

   END

RETURN cHtml

FUNCTION HIX_PathViews()
RETURN "views"
