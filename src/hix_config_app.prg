/*-----------------------------------------------------------
  File ......: hix_config_app.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-29
  Description: Application config — reads config.json from the
               project root and exposes get/set access to every key.
               Separate from hix_config.prg (server infrastructure).
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_CONFIG

#INCLUDE "hix_logger.ch"
#INCLUDE "set.ch"

// Force link of language + codepage modules used by HIX_HarbourConfigApply.
// Si queremos crear nuestro propio server con solo un codepage, eliminar los 
// otros, pero hoy en dia no tiene sentido valorar el tamaño que ocupa en el ex 

REQUEST HB_LANG_EN
REQUEST HB_LANG_ES, HB_CODEPAGE_ESWIN
REQUEST HB_LANG_PT, HB_CODEPAGE_PT850
REQUEST HB_LANG_IT, HB_CODEPAGE_ITWIN
REQUEST HB_LANG_DE, HB_CODEPAGE_DEWIN
REQUEST HB_LANG_FR, HB_CODEPAGE_FRWIN

// Force link of the CDX RDD so rddSetDefault("DBFCDX") from
// www/config.json actually switches the driver at runtime.
REQUEST DBFCDX

STATIC s_hConfig      := { => }

// ============================================================
// HIX_ConfigAppLoad -- reads config.json from project root.
// ============================================================
FUNCTION HIX_ConfigAppLoad( cFile )

   LOCAL cRaw, hJson

   hb_default( @cFile, "config.json" )

   IF ! File( cFile )

      lw( "HIX_ConfigApp: not found: " + cFile )
      RETURN .F.

   ENDIF

   cRaw := hb_MemoRead( cFile )

   IF Empty( cRaw )

      lw( "HIX_ConfigApp: empty file: " + cFile )
      RETURN .F.

   ENDIF

   IF hb_jsonDecode( cRaw, @hJson ) == 0 .OR. ! HB_ISHASH( hJson )

      lw( "HIX_ConfigApp: JSON parse error in: " + cFile )
      RETURN .F.

   ENDIF

   s_hConfig := hJson
   l( "HIX_ConfigApp: loaded " + hb_ntos( Len( hJson ) ) + " keys from " + cFile )

RETURN .T.

// ============================================================
// HIX_ConfigApp -- get a value from the app config.
// Returns xDefault ("" if omitted) when key is absent.
// ============================================================
FUNCTION HIX_ConfigApp( cKey, xDefault )

   hb_default( @xDefault, "" )

RETURN hb_HGetDef( s_hConfig, cKey, xDefault )

// ============================================================
// HIX_ConfigAppSet -- set or override a key at runtime.
// ============================================================
FUNCTION HIX_ConfigAppSet( cKey, xVal )

   s_hConfig[ cKey ] := xVal

RETURN NIL

// ============================================================
// HIX_ConfigAppDefaults -- returns the seed hash used to bootstrap
// config.json on first run. Contains only the sections HIX consumes
// today: "sets" (Harbour Set()) and "dbf" (RDD default).
// ============================================================
FUNCTION HIX_ConfigAppDefaults()

   LOCAL hDef := { => }

   hDef[ "sets" ] := { ;
      "language"   => "EN",       ;
      "dateformat" => "dd/mm/yy", ;
      "decimals"   => 2,          ;
      "deleted"    => .F.,        ;
      "epoch"      => 1900,       ;
      "exact"      => .F.,        ;
      "exclusive"  => .F.,        ;
      "fixed"      => .F.,        ;
      "softseek"   => .F.         }

   hDef[ "dbf" ]  := { "rddname" => "DBFCDX" }

   hDef[ "keys" ] := { ;
      "csrf"     => "H!x@CSRF@2026",    ;
      "jwt"      => "H!x@JWT@2026",     ;
      "session"  => "H!x@SESSION@2026", ;
      "token"    => "H!x@TOKEN@2026",   ;
      "resource" => "H!x@RES@2026"      }

RETURN hDef

// ============================================================
// HIX_ConfigAppReset -- overwrites the in-memory config with hDef.
// Used by the server bootstrap to seed defaults before saving.
// ============================================================
FUNCTION HIX_ConfigAppReset( hDef )

   IF ! HB_ISHASH( hDef ) ; RETURN .F. ; ENDIF

   s_hConfig := hDef

RETURN .T.

// ============================================================
// HIX_ConfigAppSave -- serializes the in-memory config as pretty JSON
// and writes it to cFile. Returns .T. on success.
// ============================================================
FUNCTION HIX_ConfigAppSave( cFile )

   LOCAL cJson

   hb_default( @cFile, "config.json" )

   cJson := hb_jsonEncode( s_hConfig, .T. )

   IF ! hb_MemoWrit( cFile, cJson )

      le( "HIX_ConfigApp: cannot write " + cFile )
      RETURN .F.

   ENDIF

   l( "HIX_ConfigApp: saved " + hb_ntos( Len( s_hConfig ) ) + " keys to " + cFile )

RETURN .T.

// ============================================================
// HIX_ConfigAppMerge -- non-destructive merge: adds keys from hDef
// that are missing in s_hConfig, recursing into nested hashes. Never
// overwrites user values. Returns number of keys added.
// Used on load to backfill new sections introduced in later versions.
// ============================================================
FUNCTION HIX_ConfigAppMerge( hDef )

   IF ! HB_ISHASH( hDef ) ; RETURN 0 ; ENDIF

RETURN _HixHashMergeInto( s_hConfig, hDef )

STATIC FUNCTION _HixHashMergeInto( hDst, hSrc )

   LOCAL cKey
   LOCAL nAdded := 0

   FOR EACH cKey IN hb_HKeys( hSrc )

      IF ! hb_HHasKey( hDst, cKey )

         hDst[ cKey ] := hSrc[ cKey ]
         nAdded++

      ELSEIF HB_ISHASH( hSrc[ cKey ] ) .AND. HB_ISHASH( hDst[ cKey ] )

         nAdded += _HixHashMergeInto( hDst[ cKey ], hSrc[ cKey ] )

      ENDIF

   NEXT

RETURN nAdded

// ============================================================
// HIX_HarbourConfigApply -- applies Harbour Set(...) values and RDD
// default from the "sets" and "dbf" sections of config.json. Missing
// sections/keys fall back to sensible defaults. Called on hixstyle
// startup so apps can tune Harbour from config without recompile.
// ============================================================
FUNCTION HIX_HarbourConfigApply()

   LOCAL hSets, hDbf
   LOCAL cDateFmt, cLang, cRdd
   LOCAL nDecimals, lDeleted, nEpoch, lExact, lExclusive, lFixed, lSoftseek

   hSets := HIX_ConfigApp( "sets", NIL )

   IF ! HB_ISHASH( hSets ) ; hSets := { => } ; ENDIF

   cLang := Upper( AllTrim( hb_HGetDef( hSets, "language", "EN" ) ) )

   DO CASE

      CASE cLang == "EN"
         hb_langSelect( "EN" )
      CASE cLang == "ES"
         hb_langSelect( "ES" )
         HB_SetCodePage( "ESWIN" )
         Set( _SET_DBCODEPAGE, "ESWIN" )
      CASE cLang == "PT"
         hb_langSelect( "PT" )
         HB_SetCodePage( "PT850" )
         Set( _SET_DBCODEPAGE, "PT850" )
      CASE cLang == "IT"
         hb_langSelect( "IT" )
         HB_SetCodePage( "ITWIN" )
      CASE cLang == "DE"
         hb_langSelect( "DE" )
         HB_SetCodePage( "DEWIN" )
         Set( _SET_DBCODEPAGE, "DEWIN" )
      CASE cLang == "FR"
         hb_langSelect( "FR" )
         HB_SetCodePage( "FRWIN" )
         Set( _SET_DBCODEPAGE, "FRWIN" )
      OTHERWISE
         cLang := "EN"
         hb_langSelect( "EN" )
         Set( _SET_DBCODEPAGE, "EN" )

   ENDCASE

   HIX_LangSelect( cLang )

   // Aplicar sets DESPUES de HB_LANGSELECT: cada modulo de idioma trae
   // su propio dateformat y podria sobreescribir la eleccion del usuario.
   cDateFmt   := hb_HGetDef( hSets, "dateformat", "dd/mm/yy" )
   nDecimals  := hb_HGetDef( hSets, "decimals",  2 )
   lDeleted   := hb_HGetDef( hSets, "deleted",   .F. )
   nEpoch     := hb_HGetDef( hSets, "epoch",     1900 )
   lExact     := hb_HGetDef( hSets, "exact",     .F. )
   lExclusive := hb_HGetDef( hSets, "exclusive", .F. )
   lFixed     := hb_HGetDef( hSets, "fixed",     .F. )
   lSoftseek  := hb_HGetDef( hSets, "softseek",  .F. )

   Set( _SET_DATEFORMAT, cDateFmt   )
   Set( _SET_DECIMALS,   nDecimals  )
   Set( _SET_DELETED,    lDeleted   )
   Set( _SET_EPOCH,      nEpoch     )
   Set( _SET_EXACT,      lExact     )
   Set( _SET_EXCLUSIVE,  lExclusive )
   Set( _SET_FIXED,      lFixed     )
   Set( _SET_SOFTSEEK,   lSoftseek  )

   hDbf := HIX_ConfigApp( "dbf", NIL )

   IF ! HB_ISHASH( hDbf ) ; hDbf := { => } ; ENDIF

   cRdd := hb_HGetDef( hDbf, "rddname", "DBFCDX" )
   rddSetDefault( cRdd )

   // Se llama una sola vez desde el hilo main, antes del spawn de pools.
   // Los workers heredan los sets via hb_setClone (vm/thread.c:1109).
   HIX_BootLogAdd( "config", "harbour", .T., ;
      "lang="       + cLang                    + ;
      " rdd="       + cRdd                     + ;
      " dateformat="+ cDateFmt                 + ;
      " decimals="  + hb_NToS( nDecimals )     + ;
      " deleted="   + iif( lDeleted,   "T","F" ) + ;
      " epoch="     + hb_NToS( nEpoch )        + ;
      " exact="     + iif( lExact,     "T","F" ) + ;
      " exclusive=" + iif( lExclusive, "T","F" ) + ;
      " fixed="     + iif( lFixed,     "T","F" ) + ;
      " softseek="  + iif( lSoftseek,  "T","F" ) )

RETURN NIL
