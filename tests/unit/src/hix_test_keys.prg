/*-----------------------------------------------------------
  File ......: hix_test_keys.prg
  Author.....: Charly 9000
  Created....: 2026-07-14
  Description: Integrated test — HIX_Keys shared secret store
                (hix_keys.prg): Set/Get/Exists, LoadFromAppConfig,
                masked view via HIX_KeysAsHash and precedence.
 -----------------------------------------------------------*/

FUNCTION HIX_TestKeys_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _TestKeysBasic( hCtx )
   _TestKeysLoadFromConfig( hCtx )
   _TestKeysMasked( hCtx )
   _TestKeysEnginesConsume( hCtx )

RETURN hCtx

// ============================================================
// Basic Set/Get/Exists behaviour + default fallback.
// ============================================================
STATIC PROCEDURE _TestKeysBasic( hCtx )

   LOCAL cVal

   HIX_KeysReset()

   HixTU_Check( hCtx, ! HIX_KeyExists( "app_key" ), ;
      "Keys T01: reset -> no keys",     ".F.", hb_CStr( HIX_KeyExists( "app_key" ) ) )

   cVal := HIX_KeyGet( "missing", "fallback" )
   HixTU_Check( hCtx, cVal == "fallback", ;
      "Keys T02: default returned when absent", "fallback", cVal )

   HIX_KeySet( "app_key", "secret-A" )
   HixTU_Check( hCtx, HIX_KeyExists( "app_key" ), ;
      "Keys T03: exists after Set",     ".T.", hb_CStr( HIX_KeyExists( "app_key" ) ) )

   HixTU_Check( hCtx, HIX_KeyGet( "app_key" ) == "secret-A", ;
      "Keys T04: Get returns stored",   "secret-A", HIX_KeyGet( "app_key" ) )

   HIX_KeySet( "app_key", "secret-B" )
   HixTU_Check( hCtx, HIX_KeyGet( "app_key" ) == "secret-B", ;
      "Keys T05: Set overrides",        "secret-B", HIX_KeyGet( "app_key" ) )

   // Set con valor no string -> no debe romper (silencioso o admitirlo)
   HIX_KeySet( "num", 42 )
   HixTU_Check( hCtx, HIX_KeyGet( "num", 0 ) == 42, ;
      "Keys T06: numeric value supported", "42", hb_NToS( HIX_KeyGet( "num", 0 ) ) )

RETURN

// ============================================================
// LoadFromAppConfig copies "keys" hash from config.json store.
// ============================================================
STATIC PROCEDURE _TestKeysLoadFromConfig( hCtx )

   LOCAL nBefore, nAdded, hFake

   HIX_KeysReset()

   hFake := { ;
      "app_key" => "cfg-app",     ;
      "jwt"     => "cfg-jwt",     ;
      "session" => "cfg-sess",    ;
      "token"   => "cfg-tok",     ;
      "resource" => "cfg-res"     }

   HIX_ConfigAppSet( "keys", hFake )

   nBefore := 0
   nAdded  := HIX_KeysLoadFromAppConfig()

   HixTU_Check( hCtx, nAdded == 5, ;
      "Keys T07: LoadFromAppConfig -> 5 keys", "5", hb_NToS( nAdded ) )

   HixTU_Check( hCtx, HIX_KeyGet( "jwt" ) == "cfg-jwt", ;
      "Keys T08: jwt loaded from config", "cfg-jwt", HIX_KeyGet( "jwt" ) )

   HixTU_Check( hCtx, HIX_KeyGet( "resource" ) == "cfg-res", ;
      "Keys T09: resource loaded from config", "cfg-res", HIX_KeyGet( "resource" ) )

   // Section missing -> returns 0
   HIX_ConfigAppSet( "keys", NIL )
   HIX_KeysReset()
   nBefore := HIX_KeysLoadFromAppConfig()
   HixTU_Check( hCtx, nBefore == 0, ;
      "Keys T10: no keys section -> 0",  "0", hb_NToS( nBefore ) )

RETURN

// ============================================================
// HIX_KeysAsHash returns a masked snapshot (no raw secrets).
// ============================================================
STATIC PROCEDURE _TestKeysMasked( hCtx )

   LOCAL hSnap

   HIX_KeysReset()
   HIX_KeySet( "app_key", "topsecret" )
   HIX_KeySet( "jwt",     "jwtsecret" )

   hSnap := HIX_KeysAsHash()

   HixTU_Check( hCtx, HB_ISHASH( hSnap ), ;
      "Keys T11: AsHash returns hash", ".T.", hb_CStr( HB_ISHASH( hSnap ) ) )

   HixTU_Check( hCtx, hb_HHasKey( hSnap, "app_key" ), ;
      "Keys T12: snapshot has app_key", ".T.", hb_CStr( hb_HHasKey( hSnap, "app_key" ) ) )

   HixTU_Check( hCtx, !( hb_HGetDef( hSnap, "app_key", "" ) == "topsecret" ), ;
      "Keys T13: value is masked (not raw)", "masked", hb_HGetDef( hSnap, "app_key", "" ) )

RETURN

// ============================================================
// Engines (JWT/CSRF/Token) consume the shared store.
// ============================================================
STATIC PROCEDURE _TestKeysEnginesConsume( hCtx )

   LOCAL cToken, hPayload

   HIX_KeysReset()
   HIX_KeySet( "jwt", "shared-jwt-secret" )

   cToken   := HIX_JwtEncode( { "user" => "hix" } )
   hPayload := HIX_JwtValidate( cToken )

   HixTU_Check( hCtx, HB_ISHASH( hPayload ), ;
      "Keys T14: JWT encode/validate via store", ".T.", hb_CStr( HB_ISHASH( hPayload ) ) )

   // Rotar clave -> token anterior debe fallar
   HIX_KeySet( "jwt", "rotated-secret" )
   hPayload := HIX_JwtValidate( cToken )
   HixTU_Check( hCtx, hPayload == NIL, ;
      "Keys T15: rotating jwt key invalidates old token", "NIL", hb_CStr( hPayload ) )

   // Token module also uses the store
   HIX_KeysReset()
   HIX_KeySet( "token", "tok-shared" )
   cToken := HIX_TokenMake( "payload-x" )
   HixTU_Check( hCtx, HIX_TokenValid( cToken ), ;
      "Keys T16: TokenMake/Valid via store", ".T.", ".F." )

   // Rotar clave -> invalido
   HIX_KeySet( "token", "tok-rotated" )
   HixTU_Check( hCtx, ! HIX_TokenValid( cToken ), ;
      "Keys T17: rotating token key invalidates", ".F.", ".T." )

RETURN
