/*-----------------------------------------------------------
  File ......: hix_config.prg
  Author.....: Carles Aubia (Charly 9000)
  Created....: 2026-06-30
  Modified...: 2026-06-30
  Version....: 1.0.0
  Description: HIX server configuration — JSON backed.
               Single source of truth: hix.json at hb_DirBase().
  Usage      : HIX_LoadConfig()                  -> read/seed file
               HIX_GetConfig()                   -> full hash
               HIX_GetConfig( cSection )         -> section hash
               HIX_GetConfig( cSection, cKey )   -> scalar (throws)
               HIX_SetConfig( hCfg )             -> replace in memory
               HIX_SaveConfig( [hCfg] )          -> persist to file
  Notes      : Defaults & validation live in hix_config_data.prg.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#INCLUDE 'error.ch'

STATIC s_hConfig := { => }

// ------------------------------------------------------------------ //
// HIX_FileConfig — absolute path of hix.json
// ------------------------------------------------------------------ //
FUNCTION HIX_FileConfig() ; RETURN hb_DirBase() + 'hix.json'

// ------------------------------------------------------------------ //
// HIX_GetConfig — polymorphic access
// ()                    -> whole hash
// ( cSection )          -> section hash (throws if missing)
// ( cSection, cKey )    -> scalar value (throws if missing)
// ------------------------------------------------------------------ //
FUNCTION HIX_GetConfig( cSection, cKey )

   LOCAL nArgs := PCount()

   IF nArgs == 0

      RETURN s_hConfig

   ENDIF

   IF ! hb_IsHash( s_hConfig ) .OR. ! hb_HHasKey( s_hConfig, cSection )

      _HixConfigCrash( 'section not found: [' + hb_CStr( cSection ) + ']' )

   ENDIF

   IF nArgs == 1

      RETURN s_hConfig[ cSection ]

   ENDIF

   IF ! hb_HHasKey( s_hConfig[ cSection ], cKey )

      _HixConfigCrash( 'key not found: [' + hb_CStr( cSection ) + '].' + hb_CStr( cKey ) )

   ENDIF

RETURN s_hConfig[ cSection ][ cKey ]

// ------------------------------------------------------------------ //
// HIX_SetConfig — replace the in-memory hash
// ------------------------------------------------------------------ //
FUNCTION HIX_SetConfig( hCfg )

   IF hb_IsHash( hCfg )

      s_hConfig := hCfg

   ENDIF

RETURN NIL

// ------------------------------------------------------------------ //
// HIX_LoadConfig — load hix.json into memory.
// If file missing -> seed from defaults and persist.
// If file present -> parse, validate, re-persist if validation
// added/changed any key (MD5 round-trip).
// ------------------------------------------------------------------ //
FUNCTION HIX_LoadConfig( cFile, lForce )

   LOCAL hCfg := { => }
   LOCAL cRaw, nHeader, cMacIni, cMacEnd
   LOCAL lExplicit := ( PCount() >= 1 .AND. cFile != NIL )

   hb_default( @cFile,  HIX_FileConfig() )
   hb_default( @lForce, .F. )

// Idempotente: si ya hay config cargada y no se pidio fichero
// explicito ni recarga forzada, devolver la actual sin tocar disco.

   IF ! lForce .AND. ! lExplicit .AND. hb_IsHash( s_hConfig ) .AND. Len( s_hConfig ) > 0

      RETURN s_hConfig

   ENDIF

   IF ! File( cFile )

      hCfg := HIX_InitDefault()
      HIX_SetConfig( hCfg )
      HIX_SaveConfig( hCfg, cFile )

      RETURN hCfg

   ENDIF

   cRaw := hb_MemoRead( cFile )

// Strip optional /* ... */ header
   nHeader := At( '*/' + Chr( 13 ) + Chr( 10 ), cRaw )

   IF nHeader == 0

      nHeader := At( '*/' + Chr( 10 ), cRaw )

      IF nHeader > 0

         cRaw := SubStr( cRaw, nHeader + Len( '*/' + Chr( 10 ) ) )

      ENDIF

   ELSE
      cRaw := SubStr( cRaw, nHeader + Len( '*/' + Chr( 13 ) + Chr( 10 ) ) )

   ENDIF

   hCfg := hb_jsonDecode( cRaw )

   IF ! hb_IsHash( hCfg )

// Corrupt JSON: rebuild from defaults so the server stays alive.
      hCfg := HIX_InitDefault()
      HIX_SetConfig( hCfg )
      HIX_SaveConfig( hCfg, cFile )

      RETURN hCfg

   ENDIF

// Merge user values over defaults & coerce types
   cMacIni := hb_MD5( hb_jsonEncode( hCfg ) )
   hCfg    := HIX_ValidConfig( hCfg )
   cMacEnd := hb_MD5( hb_jsonEncode( hCfg ) )

// Set first so SaveConfig can pull from memory if needed
   HIX_SetConfig( hCfg )

// Persist back if validation injected defaults

   IF cMacIni <> cMacEnd

      HIX_SaveConfig( hCfg, cFile )

   ENDIF

RETURN hCfg

// ------------------------------------------------------------------ //
// HIX_SaveConfig — write JSON with header.
// ------------------------------------------------------------------ //
FUNCTION HIX_SaveConfig( hCfg, cFile )

   LOCAL cOut
   LOCAL cEol := Chr( 13 ) + Chr( 10 )
   LOCAL cHeader := '/* ----------------------------------------------' + cEol + ;
                     ' | hix.json -- HIX Web Server Configuration' + cEol + ;
                     ' | Auto-generated. Edit values, keep structure.' + cEol + ;
                     ' * ---------------------------------------------- */' + cEol

   IF ! hb_IsHash( hCfg )

      hCfg := s_hConfig

   ENDIF

   cOut := cHeader + hb_jsonEncode( hCfg, .T. )

   hb_default( @cFile, HIX_FileConfig() )

RETURN hb_MemoWrit( cFile, cOut )

// ------------------------------------------------------------------ //
// _HixConfigCrash — hard error for missing section/key.
// Throwable, atrapable con TRY/CATCH.
// ------------------------------------------------------------------ //
STATIC PROCEDURE _HixConfigCrash( cMsg )

   LOCAL oErr := ErrorNew()

   oErr:severity    := ES_ERROR
   oErr:subSystem   := 'HIX_CONFIG'
   oErr:genCode     := EG_ARG
   oErr:description := 'HIX_GetConfig: ' + cMsg
   oErr:canRetry    := .F.
   oErr:canDefault  := .F.

   Eval( ErrorBlock(), oErr )

RETURN
