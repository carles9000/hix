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
// HIX_KeysLoadFromAppConfig — resolve the key store.
//
// v2.4.3 precedence (reversed from pre-v2.4.3):
//   1. HIX_KeySet()         -- call from Main() before Start()
//   2. config.json > "keys" -- loaded here, only when slot empty
//   3. generated in memory  -- last-resort for the core slots
//                              (csrf, jwt, session, token, resource)
//
// Returns the number of keys imported from config.json (not the
// total in the store — kept for backward compat with existing tests).
// ============================================================
FUNCTION HIX_KeysLoadFromAppConfig()

   LOCAL hKeys, cName, nCount := 0, nGen := 0
   LOCAL aSlots := { "csrf", "jwt", "session", "token", "resource" }

   hKeys := HIX_ConfigApp( "keys", NIL )

   IF HB_ISHASH( hKeys )

      FOR EACH cName IN hb_HKeys( hKeys )

         // v2.4.3 — never overwrite a key already set by HIX_KeySet.
         // Previously bootstrap pisaba el valor del usuario; eso convertía
         // config.json en autoridad (y arrastraba defaults publicados).
         IF hb_HHasKey( s_hKeys, cName ) .AND. ! Empty( s_hKeys[ cName ] )

            lw( "HIX_Keys: '" + cName + "' already set by HIX_KeySet — " + ;
                "config.json value ignored" )
            LOOP

         ENDIF

         s_hKeys[ cName ] := hKeys[ cName ]
         nCount++

         // Warn loudly when a key still carries the published default pattern.
         IF ValType( hKeys[ cName ] ) == "C" .AND. "H!x@" $ hKeys[ cName ]

            lw( "SECURITY: key '" + cName + "' uses a published default — " + ;
                "replace it in config.json > keys before deploying to production" )

         ENDIF

      NEXT

   ENDIF

   // v2.4.3 — last-resort generation for the core slots. Avoids a silent
   // "empty key" state that would make engines (JWT/CSRF/session) fall
   // back to builtin defaults. These generated keys do NOT persist: the
   // operator must call HIX_KeySet() (or populate config.json) to keep
   // tokens valid across restarts.
   FOR EACH cName IN aSlots

      IF Empty( hb_HGetDef( s_hKeys, cName, "" ) )

         s_hKeys[ cName ] := _HixGenKey()
         nGen++

      ENDIF

   NEXT

   IF nGen > 0

      lw( "HIX_Keys: " + hb_ntos( nGen ) + " key(s) generated in memory — " + ;
          "tokens/sessions die with the process. Use HIX_KeySet() or " + ;
          "config.json > keys to persist them" )

   ENDIF

   l( "HIX_Keys: " + hb_ntos( nCount ) + " from config.json, " + ;
      hb_ntos( nGen ) + " generated, " + hb_ntos( Len( s_hKeys ) ) + " in store" )

RETURN nCount

// ============================================================
// _HixGenKey — 64-char hex key from startup entropy. Mirrors
// hix_config_app.prg:_HixGenRandKey() so both paths produce
// equally unpredictable secrets.
// ============================================================
STATIC FUNCTION _HixGenKey()

   LOCAL cMsg := hb_NToS( Int( hb_TToSec( hb_DateTime() ) ) ) + ":" + ;
                 hb_NToS( hb_MilliSeconds()                  ) + ":" + ;
                 hb_NToS( hb_RandomInt( 0, 2147483647 )      )

RETURN hb_HMAC_SHA256( cMsg, "hix-key-init" )

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
