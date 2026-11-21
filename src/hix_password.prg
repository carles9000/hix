/*-----------------------------------------------------------
  File ......: hix_password.prg
  Author.....: Charly 9000
  Created....: 2026-11-08
  Modified...: 2026-11-09
  Version....: 1.1.0
  Description: Password hashing/verification core primitive.
               PBKDF2-HMAC-SHA256 via OpenSSL (libcrypto), no
               custom crypto loop. No DBF, request or session
               dependencies — pure crypto input/output.
  Usage      : HIX_PasswordHash( cPassword, nRounds ) -> hash record
               HIX_PasswordVerify( cPassword, hRecord ) -> .T./.F.
               HIX_PasswordNeedsRehash( hRecord ) -> .T. if obsolete
  Notes      : libcrypto resolved at RUNTIME from the same library HIX
               already loads for HMAC/session (libcrypto-4-x64.dll on
               Windows; libcrypto.so.* on Unix). HIX_ConstantEq lives
               in hix_helpers.prg. Minimum rounds locked at 600000 per
               OWASP 2026. Public API never accepts lower; internal C
               symbols accept 1..2000000 only for test vectors.
 -----------------------------------------------------------*/

#define HIX_PASSWORD_MIN_ROUNDS   600000
#define HIX_PASSWORD_MAX_ROUNDS  2000000

// ============================================================
// HIX_PasswordHash -- create a versioned, portable password record.
// cPassword: exact bytes, no trim, case folding or silent truncation.
// nRounds: default 600000, integer 600000..2000000. Never tuned down.
// Return: hash PASSALG/PASSITER/SALT/PASSHASH, or NIL on failure.
// The caller owns length policy; this module accepts 1..1024 bytes.
// Salt: 16 OS-seeded OpenSSL random bytes. Output: 32 bytes, hex stored.
// Never send the returned record to a view or browser.
// ============================================================
FUNCTION HIX_PasswordHash( cPassword, nRounds )

   LOCAL cSalt, cHash

   IF nRounds == NIL
      nRounds := HIX_PASSWORD_MIN_ROUNDS
   ENDIF

   IF ! _HixPasswordInput( cPassword ) .OR. ! _HixPasswordRounds( nRounds )
      RETURN NIL
   ENDIF

   cSalt := _HIX_PASSWORDSALT()
   IF ! HB_ISSTRING( cSalt ) .OR. Len( cSalt ) != 16
      RETURN NIL
   ENDIF

   cHash := _HIX_PASSWORDDERIVE( cPassword, cSalt, nRounds )
   IF ! HB_ISSTRING( cHash ) .OR. Len( cHash ) != 32
      RETURN NIL
   ENDIF

RETURN { "PASSALG"  => "PBKDF2-SHA256", ;
         "PASSITER" => nRounds, ;
         "SALT"     => Lower( hb_StrToHex( cSalt ) ), ;
         "PASSHASH" => Lower( hb_StrToHex( cHash ) ) }

// ============================================================
// HIX_PasswordVerify -- exact password match against stored record.
// Invalid algorithm, types, lengths, hex or cost fail closed.
// No fallback to a fast hash. No UI, logging or persistence effects.
// Rate limits/dummy checks for unknown users belong to the login layer.
// ============================================================
FUNCTION HIX_PasswordVerify( cPassword, hRecord )

   LOCAL cHash

   IF ! _HixPasswordInput( cPassword ) .OR. ! HB_ISHASH( hRecord )
      RETURN .F.
   ENDIF

   IF ! ( hb_HGetDef( hRecord, "PASSALG", "" ) == "PBKDF2-SHA256" ) .OR. ;
      ! _HixPasswordRounds( hb_HGetDef( hRecord, "PASSITER", NIL ) ) .OR. ;
      ! _HixPasswordHex( hb_HGetDef( hRecord, "SALT", NIL ), 32 ) .OR. ;
      ! _HixPasswordHex( hb_HGetDef( hRecord, "PASSHASH", NIL ), 64 )
      RETURN .F.
   ENDIF

   cHash := _HIX_PASSWORDDERIVE( cPassword, hb_HexToStr( hRecord[ "SALT" ] ), ;
                               hRecord[ "PASSITER" ] )
   IF ! HB_ISSTRING( cHash ) .OR. Len( cHash ) != 32
      RETURN .F.
   ENDIF

RETURN HIX_ConstantEq( cHash, hb_HexToStr( hRecord[ "PASSHASH" ] ) )

// ============================================================
// HIX_PasswordNeedsRehash -- .T. when the stored record uses an
// obsolete algorithm or a cost below the current public minimum.
// Call on successful login to re-derive and update in place; keeps
// the cost of fielded accounts up to date without forcing resets.
// A record that fails any structural check also needs rehash.
// ============================================================
FUNCTION HIX_PasswordNeedsRehash( hRecord )

   IF ! HB_ISHASH( hRecord )
      RETURN .T.
   ENDIF

   IF ! ( hb_HGetDef( hRecord, "PASSALG", "" ) == "PBKDF2-SHA256" )
      RETURN .T.
   ENDIF

   IF ! HB_ISNUMERIC( hb_HGetDef( hRecord, "PASSITER", NIL ) ) .OR. ;
      hRecord[ "PASSITER" ] < HIX_PASSWORD_MIN_ROUNDS
      RETURN .T.
   ENDIF

   IF ! _HixPasswordHex( hb_HGetDef( hRecord, "SALT", NIL ), 32 ) .OR. ;
      ! _HixPasswordHex( hb_HGetDef( hRecord, "PASSHASH", NIL ), 64 )
      RETURN .T.
   ENDIF

RETURN .F.

STATIC FUNCTION _HixPasswordInput( cPassword )
RETURN HB_ISSTRING( cPassword ) .AND. Len( cPassword ) >= 1 .AND. Len( cPassword ) <= 1024

STATIC FUNCTION _HixPasswordRounds( nRounds )
RETURN HB_ISNUMERIC( nRounds ) .AND. nRounds >= HIX_PASSWORD_MIN_ROUNDS .AND. ;
       nRounds <= HIX_PASSWORD_MAX_ROUNDS .AND. nRounds == Int( nRounds )

STATIC FUNCTION _HixPasswordHex( cHex, nLen )

   LOCAL n

   IF ! HB_ISSTRING( cHex ) .OR. Len( cHex ) != nLen
      RETURN .F.
   ENDIF

   FOR n := 1 TO nLen
      IF ! ( SubStr( cHex, n, 1 ) $ "0123456789abcdef" )
         RETURN .F.
      ENDIF
   NEXT

RETURN .T.

// Thin native boundary, as in other HIX modules using BEGINDUMP.
// Internal symbols accept test-vector rounds 1..2000000; the PUBLIC
// API always enforces the stronger 600000 minimum. They are not APIs.
// libcrypto is resolved at runtime (the same library HIX already loads);
// NIL on any resolution failure, never a weak fallback.
#pragma BEGINDUMP
#include "hbapi.h"

#if defined( _WIN32 ) || defined( _WIN64 )
   #include <windows.h>
   typedef HMODULE uv2_lib;
   #define UV2_OPEN( name )      LoadLibraryA( name )
   #define UV2_SYM( lib, name )  ( void * ) GetProcAddress( lib, name )
   static const char * s_names[] = { "libcrypto-4-x64.dll", "libcrypto-3-x64.dll", "libcrypto.dll", 0 };
#else
   #include <dlfcn.h>
   typedef void * uv2_lib;
   #define UV2_OPEN( name )      dlopen( name, RTLD_NOW | RTLD_LOCAL )
   #define UV2_SYM( lib, name )  dlsym( lib, name )
   static const char * s_names[] = { "libcrypto.so.4", "libcrypto.so.3", "libcrypto.so.1.1", "libcrypto.so", 0 };
#endif

typedef int ( * uv2_pbkdf2_fn )( const char *, int, const unsigned char *, int, int, const void *, int, unsigned char * );
typedef int ( * uv2_rand_fn )( unsigned char *, int );
typedef const void * ( * uv2_evp_sha256_fn )( void );

static uv2_lib           s_lib    = ( uv2_lib ) 0;
static uv2_pbkdf2_fn     s_pbkdf2 = ( uv2_pbkdf2_fn ) 0;
static uv2_rand_fn       s_rand   = ( uv2_rand_fn ) 0;
static uv2_evp_sha256_fn s_sha256 = ( uv2_evp_sha256_fn ) 0;

static int uv2_crypto_ready( void )
{
   int i;

   if( s_pbkdf2 && s_rand && s_sha256 )
      return 1;
   if( ! s_lib )
      for( i = 0; s_names[ i ]; i++ )
         if( ( s_lib = UV2_OPEN( s_names[ i ] ) ) != ( uv2_lib ) 0 )
            break;
   if( ! s_lib )
      return 0;
   s_pbkdf2 = ( uv2_pbkdf2_fn ) UV2_SYM( s_lib, "PKCS5_PBKDF2_HMAC" );
   s_rand   = ( uv2_rand_fn ) UV2_SYM( s_lib, "RAND_bytes" );
   s_sha256 = ( uv2_evp_sha256_fn ) UV2_SYM( s_lib, "EVP_sha256" );

   return s_pbkdf2 && s_rand && s_sha256;
}

static void uv2_cleanse( void * p, unsigned int n )
{
   volatile unsigned char * v = ( volatile unsigned char * ) p;
   while( n-- )
      *v++ = 0;
}

HB_FUNC( _HIX_PASSWORDDERIVE )
{
   unsigned char key[32];
   double rounds = hb_parnd(3);
   if (!HB_ISCHAR(1) || !HB_ISCHAR(2) || !HB_ISNUM(3) ||
       hb_parclen(1)>1024 || hb_parclen(2)>1024 ||
       rounds<1 || rounds>2000000 || rounds!=(int)rounds ||
       !uv2_crypto_ready())
      return; /* NIL on bad input or missing libcrypto, never weak fallback */
   if (s_pbkdf2(hb_parc(1),(int)hb_parclen(1),
       (const unsigned char *)hb_parc(2),(int)hb_parclen(2),(int)rounds,
       s_sha256(),sizeof(key),key)==1)
      hb_retclen((const char *)key,sizeof(key));
   uv2_cleanse(key,sizeof(key));
}
HB_FUNC( _HIX_PASSWORDSALT )
{
   unsigned char salt[16];
   if (uv2_crypto_ready() && s_rand(salt,sizeof(salt))==1)
      hb_retclen((const char *)salt,sizeof(salt));
   uv2_cleanse(salt,sizeof(salt));
}
#pragma ENDDUMP
