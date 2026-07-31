/*-----------------------------------------------------------
  File ......: hix_keys.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-29
  Modified...: 2026-07-14
  Description: In-memory named key store — single source for every
               HIX engine that needs a secret (JWT, session, token,
               CSRF, resource, future DB creds).

               Loads keys from config.json > "keys" section (hixstyle)
               or from user code via HIX_KeySet (standalone).
               Engines read via HIX_KeyGet — never care about origin.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_CONFIG

#INCLUDE "hix_logger.ch"

STATIC s_hKeys := { => }

// ============================================================
// HIX_KeySet — store or override a named key.
// Call from Main() before oSrv:Start() in standalone deployments.
// ============================================================
FUNCTION HIX_KeySet( cName, cVal )

   s_hKeys[ cName ] := cVal

RETURN NIL

// ============================================================
// HIX_KeyGet — read a named key. Returns cDefault when absent.
// ============================================================
FUNCTION HIX_KeyGet( cName, cDefault )

   hb_default( @cDefault, "" )

RETURN hb_HGetDef( s_hKeys, cName, cDefault )

// ============================================================
// HIX_KeyExists — .T. if a key is in the store.
// ============================================================
FUNCTION HIX_KeyExists( cName )
RETURN hb_HHasKey( s_hKeys, cName )

// ============================================================
// HIX_KeysLoadFromAppConfig — copy config.json > "keys" section
// into the store. Idempotent. Values already set by HIX_KeySet
// are overwritten — bootstrap runs before user code by design.
// Returns the number of keys copied.
// ============================================================
FUNCTION HIX_KeysLoadFromAppConfig()

   LOCAL hKeys, cName, nCount := 0

   hKeys := HIX_ConfigApp( "keys", NIL )

   IF ! HB_ISHASH( hKeys )

      RETURN 0

   ENDIF

   FOR EACH cName IN hb_HKeys( hKeys )

      s_hKeys[ cName ] := hKeys[ cName ]
      nCount++

   NEXT

   l( "HIX_Keys: " + hb_ntos( nCount ) + " key(s) loaded from config.json" )

RETURN nCount

// ============================================================
// HIX_KeysAsHash — returns a hash with the key NAMES only
// (values masked). Safe for logging / monitor endpoints.
// ============================================================
FUNCTION HIX_KeysAsHash()

   LOCAL hOut := { => }
   LOCAL cName, cVal

   FOR EACH cName IN hb_HKeys( s_hKeys )

      cVal := s_hKeys[ cName ]

      IF ValType( cVal ) == "C" .AND. Len( cVal ) > 4

         hOut[ cName ] := Left( cVal, 2 ) + "***" + Right( cVal, 2 )
      ELSE
         hOut[ cName ] := "***"

      ENDIF

   NEXT

RETURN hOut

// ============================================================
// HIX_KeysReset — clear the store. Test-only helper.
// ============================================================
FUNCTION HIX_KeysReset()

   s_hKeys := { => }

RETURN NIL
