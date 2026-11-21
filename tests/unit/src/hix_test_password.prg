/*-----------------------------------------------------------
  File ......: hix_test_password.prg
  Author.....: Charly 9000
  Created....: 2026-11-09
  Description: Integrated test — HIX_Password core primitive
                (hix_password.prg): Hash / Verify / NeedsRehash
                over PBKDF2-HMAC-SHA256 via libcrypto.
 -----------------------------------------------------------*/

#define HIX_PASSWORD_MIN_ROUNDS   600000

FUNCTION HIX_TestPassword_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _TestPasswordHash( hCtx )
   _TestPasswordVerify( hCtx )
   _TestPasswordNeedsRehash( hCtx )
   _TestPasswordInputValidation( hCtx )

RETURN hCtx

// ============================================================
// Hash shape: algorithm, iterations, salt and hash fields
// are produced with the documented sizes.
// ============================================================
STATIC PROCEDURE _TestPasswordHash( hCtx )

   LOCAL hRec, hRec2

   hRec := HIX_PasswordHash( "correct horse battery staple" )

   HixTU_Check( hCtx, HB_ISHASH( hRec ), ;
      "Password T01: Hash returns hash", ".T.", hb_CStr( HB_ISHASH( hRec ) ) )

   HixTU_Check( hCtx, hb_HGetDef( hRec, "PASSALG", "" ) == "PBKDF2-SHA256", ;
      "Password T02: PASSALG tag",      "PBKDF2-SHA256", hb_HGetDef( hRec, "PASSALG", "" ) )

   HixTU_Check( hCtx, hb_HGetDef( hRec, "PASSITER", 0 ) == HIX_PASSWORD_MIN_ROUNDS, ;
      "Password T03: default iterations = 600000", ;
      hb_NToS( HIX_PASSWORD_MIN_ROUNDS ), hb_NToS( hb_HGetDef( hRec, "PASSITER", 0 ) ) )

   HixTU_Check( hCtx, Len( hb_HGetDef( hRec, "SALT", "" ) ) == 32, ;
      "Password T04: SALT is 32 hex chars (16 bytes)", ;
      "32", hb_NToS( Len( hb_HGetDef( hRec, "SALT", "" ) ) ) )

   HixTU_Check( hCtx, Len( hb_HGetDef( hRec, "PASSHASH", "" ) ) == 64, ;
      "Password T05: PASSHASH is 64 hex chars (32 bytes)", ;
      "64", hb_NToS( Len( hb_HGetDef( hRec, "PASSHASH", "" ) ) ) )

   // Two hashes of the same password must differ (unique salt).
   hRec2 := HIX_PasswordHash( "correct horse battery staple" )
   HixTU_Check( hCtx, ! ( hRec[ "PASSHASH" ] == hRec2[ "PASSHASH" ] ), ;
      "Password T06: unique salt -> different hashes", ".T.", ;
      hb_CStr( ! ( hRec[ "PASSHASH" ] == hRec2[ "PASSHASH" ] ) ) )

RETURN

// ============================================================
// Verify: correct password -> .T.; wrong -> .F.; corrupt record -> .F.
// ============================================================
STATIC PROCEDURE _TestPasswordVerify( hCtx )

   LOCAL hRec, hBad

   hRec := HIX_PasswordHash( "s3cret-value" )

   HixTU_Check( hCtx, HIX_PasswordVerify( "s3cret-value", hRec ), ;
      "Password T07: verify correct password", ".T.", ".F." )

   HixTU_Check( hCtx, ! HIX_PasswordVerify( "wrong-value", hRec ), ;
      "Password T08: verify wrong password",   ".F.", ".T." )

   // Corrupt PASSHASH -> .F.
   hBad := hb_HClone( hRec )
   hBad[ "PASSHASH" ] := Replicate( "0", 64 )
   HixTU_Check( hCtx, ! HIX_PasswordVerify( "s3cret-value", hBad ), ;
      "Password T09: tampered PASSHASH -> fail", ".F.", ".T." )

   // Unknown algorithm -> .F.
   hBad := hb_HClone( hRec )
   hBad[ "PASSALG" ] := "md5"
   HixTU_Check( hCtx, ! HIX_PasswordVerify( "s3cret-value", hBad ), ;
      "Password T10: unknown algorithm -> fail", ".F.", ".T." )

   // Non-hex salt -> .F.
   hBad := hb_HClone( hRec )
   hBad[ "SALT" ] := Replicate( "z", 32 )
   HixTU_Check( hCtx, ! HIX_PasswordVerify( "s3cret-value", hBad ), ;
      "Password T11: non-hex salt -> fail", ".F.", ".T." )

   // Not a hash -> .F.
   HixTU_Check( hCtx, ! HIX_PasswordVerify( "s3cret-value", "not a hash" ), ;
      "Password T12: record not a hash -> fail", ".F.", ".T." )

RETURN

// ============================================================
// NeedsRehash: .T. when record is missing, obsolete, or below the
// current public minimum of iterations.
// ============================================================
STATIC PROCEDURE _TestPasswordNeedsRehash( hCtx )

   LOCAL hRec, hLow

   hRec := HIX_PasswordHash( "abc123" )

   HixTU_Check( hCtx, ! HIX_PasswordNeedsRehash( hRec ), ;
      "Password T13: fresh record does not need rehash", ".F.", ".T." )

   HixTU_Check( hCtx, HIX_PasswordNeedsRehash( NIL ), ;
      "Password T14: NIL record needs rehash", ".T.", ".F." )

   // Below minimum -> rehash.
   hLow := hb_HClone( hRec )
   hLow[ "PASSITER" ] := HIX_PASSWORD_MIN_ROUNDS - 1
   HixTU_Check( hCtx, HIX_PasswordNeedsRehash( hLow ), ;
      "Password T15: below-min rounds -> rehash", ".T.", ".F." )

   // Obsolete algorithm -> rehash.
   hLow := hb_HClone( hRec )
   hLow[ "PASSALG" ] := "pbkdf2-sha1"
   HixTU_Check( hCtx, HIX_PasswordNeedsRehash( hLow ), ;
      "Password T16: obsolete algorithm -> rehash", ".T.", ".F." )

   // Bad salt length -> rehash.
   hLow := hb_HClone( hRec )
   hLow[ "SALT" ] := "short"
   HixTU_Check( hCtx, HIX_PasswordNeedsRehash( hLow ), ;
      "Password T17: bad salt length -> rehash", ".T.", ".F." )

RETURN

// ============================================================
// Input validation: public API never returns a value for
// out-of-range passwords or iteration counts.
// ============================================================
STATIC PROCEDURE _TestPasswordInputValidation( hCtx )

   HixTU_Check( hCtx, HIX_PasswordHash( "" ) == NIL, ;
      "Password T18: empty password -> NIL", "NIL", hb_CStr( HIX_PasswordHash( "" ) ) )

   HixTU_Check( hCtx, HIX_PasswordHash( NIL ) == NIL, ;
      "Password T19: NIL password -> NIL", "NIL", hb_CStr( HIX_PasswordHash( NIL ) ) )

   // Below minimum -> NIL (public API never accepts weaker cost).
   HixTU_Check( hCtx, HIX_PasswordHash( "ok", HIX_PASSWORD_MIN_ROUNDS - 1 ) == NIL, ;
      "Password T20: rounds below minimum -> NIL", "NIL", ;
      hb_CStr( HIX_PasswordHash( "ok", HIX_PASSWORD_MIN_ROUNDS - 1 ) ) )

RETURN
