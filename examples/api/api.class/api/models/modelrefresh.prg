/*-----------------------------------------------------------
  File ......: modelrefresh.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 2.0.0
  Description: Refresh token store -- backed by HIX_DataPool
               ("refresh" pool). No STATIC variables; no HRB
               isolation concerns. Safe to #include from any
               controller.

               Rotation: the old token is marked revoked and
               a new one is issued with rot_from = old token.
               If a revoked token is presented again, the whole
               forward chain is revoked (reuse detection) and
               the caller must respond 401 and force re-login.

               Cleanup: expired entries are pruned on every
               ModelRefreshIssue call (no background worker).

               TTL: UMwConfig( "refresh", "ttl_days", 1 )
  Usage      : ModelRefreshInit()   -- call once at startup
               hIssued  := ModelRefreshIssue( cUserId, cIp )
               hRotated := ModelRefreshRotate( cToken, cIp )
               ModelRefreshRevoke( cToken )
 -----------------------------------------------------------*/

#define POOL_REFRESH "refresh"


// ============================================================
// ModelRefreshInit -- create the pool at startup (single thread).
// Call from UserInit() before any worker starts.
// ============================================================
FUNCTION ModelRefreshInit()
   HIX_PoolCreate( POOL_REFRESH )
RETURN NIL


// ============================================================
// ModelRefreshIssue -- mint a new refresh token.
// Returns { token, exp } -- the only moment the plaintext is
// visible; the caller must return it to the client.
// ============================================================
FUNCTION ModelRefreshIssue( cUserId, cIp, cRotatedFrom )

   LOCAL cToken, nExp, nTtlDays

   hb_default( @cIp,          "" )
   hb_default( @cRotatedFrom, "" )

   nTtlDays := UMwConfig( "refresh", "ttl_days", 1 )
   IF ! HB_ISNUMERIC( nTtlDays ) .OR. nTtlDays <= 0
      nTtlDays := 1
   ENDIF
   nExp   := Int( hb_TToSec( hb_DateTime() ) ) + ( nTtlDays * 86400 )
   cToken := _RefreshRandomToken()

   HIX_PoolLock( POOL_REFRESH )
   _RefreshPurge()
   HIX_PoolSetRaw( POOL_REFRESH, cToken, { ;
      "user_id"  => cUserId,      ;
      "exp"      => nExp,         ;
      "revoked"  => .F.,          ;
      "rot_from" => cRotatedFrom  ;
   } )
   HIX_PoolUnlock( POOL_REFRESH )

RETURN { "token" => cToken, "exp" => nExp }


// ============================================================
// ModelRefreshRotate -- validate + revoke old, issue new.
// Returns { user_id, token, exp } or NIL on any failure.
// On reuse of a revoked token the whole forward chain is
// revoked -- caller must respond 401 and force re-login.
// ============================================================
FUNCTION ModelRefreshRotate( cToken, cIp )

   LOCAL hEntry, cUserId, hIssued, nNow

   IF Empty( cToken )
      RETURN NIL
   ENDIF

   hb_default( @cIp, "" )

   nNow := Int( hb_TToSec( hb_DateTime() ) )

   HIX_PoolLock( POOL_REFRESH )

   IF ! HIX_PoolHasRaw( POOL_REFRESH, cToken )
      HIX_PoolUnlock( POOL_REFRESH )
      RETURN NIL
   ENDIF

   hEntry := HIX_PoolGetRaw( POOL_REFRESH, cToken, NIL )

   IF hEntry[ "revoked" ]
      _RefreshRevokeChain( cToken )
      HIX_PoolUnlock( POOL_REFRESH )
      RETURN NIL
   ENDIF

   IF hEntry[ "exp" ] < nNow
      HIX_PoolDelRaw( POOL_REFRESH, cToken )
      HIX_PoolUnlock( POOL_REFRESH )
      RETURN NIL
   ENDIF

   cUserId             := hEntry[ "user_id" ]
   hEntry[ "revoked" ] := .T.
   HIX_PoolSetRaw( POOL_REFRESH, cToken, hEntry )

   HIX_PoolUnlock( POOL_REFRESH )

   hIssued              := ModelRefreshIssue( cUserId, cIp, cToken )
   hIssued[ "user_id" ] := cUserId

RETURN hIssued


// ============================================================
// ModelRefreshRevoke -- mark a token as revoked (logout).
// Silent success if token not found.
// ============================================================
FUNCTION ModelRefreshRevoke( cToken )

   LOCAL hEntry

   IF Empty( cToken )
      RETURN .F.
   ENDIF

   HIX_PoolLock( POOL_REFRESH )

   IF HIX_PoolHasRaw( POOL_REFRESH, cToken )
      hEntry              := HIX_PoolGetRaw( POOL_REFRESH, cToken, NIL )
      hEntry[ "revoked" ] := .T.
      HIX_PoolSetRaw( POOL_REFRESH, cToken, hEntry )
   ENDIF

   HIX_PoolUnlock( POOL_REFRESH )

RETURN .T.


// ---- private helpers (called under pool lock) ----

STATIC PROCEDURE _RefreshPurge()

   LOCAL aKeys, nNow, i, hEntry

   nNow  := Int( hb_TToSec( hb_DateTime() ) )
   aKeys := HIX_PoolKeysRaw( POOL_REFRESH )

   FOR i := 1 TO Len( aKeys )
      hEntry := HIX_PoolGetRaw( POOL_REFRESH, aKeys[ i ], NIL )
      IF HB_ISHASH( hEntry ) .AND. hEntry[ "exp" ] < nNow
         HIX_PoolDelRaw( POOL_REFRESH, aKeys[ i ] )
      ENDIF
   NEXT

RETURN


STATIC PROCEDURE _RefreshRevokeChain( cRoot )

   LOCAL aKeys, i, hEntry

   aKeys := HIX_PoolKeysRaw( POOL_REFRESH )

   FOR i := 1 TO Len( aKeys )
      hEntry := HIX_PoolGetRaw( POOL_REFRESH, aKeys[ i ], NIL )
      IF HB_ISHASH( hEntry )
         IF aKeys[ i ] == cRoot .OR. hEntry[ "rot_from" ] == cRoot
            hEntry[ "revoked" ]    := .T.
            HIX_PoolSetRaw( POOL_REFRESH, aKeys[ i ], hEntry )
         ENDIF
      ENDIF
   NEXT

RETURN


STATIC FUNCTION _RefreshRandomToken()

   LOCAL cChars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
   LOCAL cToken := ""
   LOCAL nI

   FOR nI := 1 TO 48
      cToken += SubStr( cChars, hb_RandomInt( 1, Len( cChars ) ), 1 )
   NEXT

RETURN cToken
