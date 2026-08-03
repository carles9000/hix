/*-----------------------------------------------------------
  File ......: modeltoken.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-24
  Version....: 2.0.0
  Description: Refresh token store -- backed by HIX_DataPool
               ("token" pool). No STATIC variables; no HRB
               isolation concerns. Safe to #include from any
               controller.

               Rotation: the old token is marked revoked and
               a new one is issued with rot_from = old token.
               If a revoked token is presented again, the whole
               forward chain is revoked (reuse detection) and
               the caller must respond 401 and force re-login.

               Cleanup: expired entries are pruned on every
               ModelTokenIssue call (no background worker).

               TTL: UMwConfig( "token", "ttl_days", 1 )
  Usage      : ModelTokenInit()   -- call once at startup
               hIssued  := ModelTokenIssue( cUserId, cIp )
               hRotated := ModelTokenRotate( cToken, cIp )
               ModelTokenRevoke( cToken )
 -----------------------------------------------------------*/

#define POOL_TOKEN "token"


// ============================================================
// ModelTokenInit -- create the pool at startup (single thread).
// Call from UserInit() before any worker starts.
// ============================================================
FUNCTION ModelTokenInit()
   HIX_PoolCreate( POOL_TOKEN )
RETURN NIL


// ============================================================
// ModelTokenIssue -- mint a new refresh token.
// Returns { token, exp } -- the only moment the plaintext is
// visible; the caller must return it to the client.
// ============================================================
FUNCTION ModelTokenIssue( cUserId, cIp, cRotatedFrom )

   LOCAL cToken, nExp, nTtlDays

   hb_default( @cIp,          "" )
   hb_default( @cRotatedFrom, "" )

   nTtlDays := UMwConfig( "token", "ttl_days", 1 )
   IF ! HB_ISNUMERIC( nTtlDays ) .OR. nTtlDays <= 0
      nTtlDays := 1
   ENDIF
   nExp   := Int( hb_TToSec( hb_DateTime() ) ) + ( nTtlDays * 86400 )
   cToken := _TokenRandomToken()

   HIX_PoolLock( POOL_TOKEN )
   _TokenPurge()
   HIX_PoolSetRaw( POOL_TOKEN, cToken, { ;
      "user_id"  => cUserId,      ;
      "exp"      => nExp,         ;
      "revoked"  => .F.,          ;
      "rot_from" => cRotatedFrom  ;
   } )
   HIX_PoolUnlock( POOL_TOKEN )

RETURN { "token" => cToken, "exp" => nExp }


// ============================================================
// ModelTokenRotate -- validate + revoke old, issue new.
// Returns { user_id, token, exp } or NIL on any failure.
// On reuse of a revoked token the whole forward chain is
// revoked -- caller must respond 401 and force re-login.
// ============================================================
FUNCTION ModelTokenRotate( cToken, cIp )

   LOCAL hEntry, cUserId, hIssued, nNow

   IF Empty( cToken )
      RETURN NIL
   ENDIF

   hb_default( @cIp, "" )

   nNow := Int( hb_TToSec( hb_DateTime() ) )

   HIX_PoolLock( POOL_TOKEN )

   IF ! HIX_PoolHasRaw( POOL_TOKEN, cToken )
      HIX_PoolUnlock( POOL_TOKEN )
      RETURN NIL
   ENDIF

   hEntry := HIX_PoolGetRaw( POOL_TOKEN, cToken, NIL )

   IF hEntry[ "revoked" ]
      _TokenRevokeChain( cToken )
      HIX_PoolUnlock( POOL_TOKEN )
      RETURN NIL
   ENDIF

   IF hEntry[ "exp" ] < nNow
      HIX_PoolDelRaw( POOL_TOKEN, cToken )
      HIX_PoolUnlock( POOL_TOKEN )
      RETURN NIL
   ENDIF

   cUserId             := hEntry[ "user_id" ]
   hEntry[ "revoked" ] := .T.
   HIX_PoolSetRaw( POOL_TOKEN, cToken, hEntry )

   HIX_PoolUnlock( POOL_TOKEN )

   hIssued              := ModelTokenIssue( cUserId, cIp, cToken )
   hIssued[ "user_id" ] := cUserId

RETURN hIssued


// ============================================================
// ModelTokenRevoke -- mark a token as revoked (logout).
// Silent success if token not found.
// ============================================================
FUNCTION ModelTokenRevoke( cToken )

   LOCAL hEntry

   IF Empty( cToken )
      RETURN .F.
   ENDIF

   HIX_PoolLock( POOL_TOKEN )

   IF HIX_PoolHasRaw( POOL_TOKEN, cToken )
      hEntry              := HIX_PoolGetRaw( POOL_TOKEN, cToken, NIL )
      hEntry[ "revoked" ] := .T.
      HIX_PoolSetRaw( POOL_TOKEN, cToken, hEntry )
   ENDIF

   HIX_PoolUnlock( POOL_TOKEN )

RETURN .T.


// ---- private helpers (called under pool lock) ----

STATIC PROCEDURE _TokenPurge()

   LOCAL aKeys, nNow, i, hEntry

   nNow  := Int( hb_TToSec( hb_DateTime() ) )
   aKeys := HIX_PoolKeysRaw( POOL_TOKEN )

   FOR i := 1 TO Len( aKeys )
      hEntry := HIX_PoolGetRaw( POOL_TOKEN, aKeys[ i ], NIL )
      IF HB_ISHASH( hEntry ) .AND. hEntry[ "exp" ] < nNow
         HIX_PoolDelRaw( POOL_TOKEN, aKeys[ i ] )
      ENDIF
   NEXT

RETURN


STATIC PROCEDURE _TokenRevokeChain( cRoot )

   LOCAL aKeys, i, hEntry

   aKeys := HIX_PoolKeysRaw( POOL_TOKEN )

   FOR i := 1 TO Len( aKeys )
      hEntry := HIX_PoolGetRaw( POOL_TOKEN, aKeys[ i ], NIL )
      IF HB_ISHASH( hEntry )
         IF aKeys[ i ] == cRoot .OR. hEntry[ "rot_from" ] == cRoot
            hEntry[ "revoked" ]    := .T.
            HIX_PoolSetRaw( POOL_TOKEN, aKeys[ i ], hEntry )
         ENDIF
      ENDIF
   NEXT

RETURN


STATIC FUNCTION _TokenRandomToken()

   LOCAL cChars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
   LOCAL cToken := ""
   LOCAL nI

   FOR nI := 1 TO 48
      cToken += SubStr( cChars, hb_RandomInt( 1, Len( cChars ) ), 1 )
   NEXT

RETURN cToken
