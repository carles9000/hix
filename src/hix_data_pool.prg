/*-----------------------------------------------------------
  File ......: hix_data_pool.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Version....: 1.0.0
  Description: Named in-memory data pools with per-pool mutex.
               Each pool is an independent thread-safe key-value
               store accessible from any HRB without STATIC
               isolation issues.

               Two operation layers:
                 - Atomic (locked internally): HIX_PoolSet/Get/Del/Has/Keys/Size
                 - Batch (manual lock):        HIX_PoolLock + HIX_Pool*Raw + HIX_PoolUnlock

               IMPORTANT: never call atomic ops while holding the
               pool lock -- use *Raw variants inside the batch block.

  Usage      : HIX_PoolCreate( "tokens" )
               HIX_PoolSet( "tokens", cKey, hEntry )
               hEntry := HIX_PoolGet( "tokens", cKey, NIL )
               HIX_PoolDel( "tokens", cKey )

               // Batch (atomic block):
               HIX_PoolLock( "tokens" )
               aKeys := HIX_PoolKeysRaw( "tokens" )
               FOR EACH cK IN aKeys
                  hEntry := HIX_PoolGetRaw( "tokens", cK )
                  // ... mutate ...
                  HIX_PoolSetRaw( "tokens", cK, hEntry )
               NEXT
               HIX_PoolUnlock( "tokens" )
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

STATIC s_hPools := NIL
STATIC s_mtxMgr := NIL


// ============================================================
// _PoolMgrInit -- lazy bootstrap of the pool manager.
// In practice HIX_PoolCreate is called from UserInit() before
// any worker thread starts, so this never races.
// ============================================================
STATIC PROCEDURE _PoolMgrInit()
   IF s_mtxMgr == NIL
      s_hPools := { => }
      s_mtxMgr := hb_mutexCreate()
   ENDIF
RETURN


// ============================================================
// HIX_PoolCreate -- create a named pool (idempotent).
// ============================================================
FUNCTION HIX_PoolCreate( cName )

   _PoolMgrInit()

   hb_mutexLock( s_mtxMgr )
   IF ! hb_HHasKey( s_hPools, cName )
      s_hPools[ cName ] := { "data" => { => }, "mtx" => hb_mutexCreate() }
   ENDIF
   hb_mutexUnlock( s_mtxMgr )

RETURN NIL


// ============================================================
// HIX_PoolDestroy -- remove a named pool and release resources.
// ============================================================
FUNCTION HIX_PoolDestroy( cName )

   _PoolMgrInit()

   hb_mutexLock( s_mtxMgr )
   IF hb_HHasKey( s_hPools, cName )
      hb_HDel( s_hPools, cName )
   ENDIF
   hb_mutexUnlock( s_mtxMgr )

RETURN NIL


// ============================================================
// HIX_PoolExists -- .T. if a pool with this name was created.
// ============================================================
FUNCTION HIX_PoolExists( cName )

   LOCAL lExists

   _PoolMgrInit()

   hb_mutexLock( s_mtxMgr )
   lExists := hb_HHasKey( s_hPools, cName )
   hb_mutexUnlock( s_mtxMgr )

RETURN lExists


// ============================================================
// Atomic ops -- each call acquires and releases the pool mutex.
// ============================================================
FUNCTION HIX_PoolSet( cName, cKey, xValue )

   LOCAL hPool := _PoolEntry( cName )

   hb_mutexLock( hPool[ "mtx" ] )
   hPool[ "data" ][ cKey ] := xValue
   hb_mutexUnlock( hPool[ "mtx" ] )

RETURN NIL


FUNCTION HIX_PoolGet( cName, cKey, xDef )

   LOCAL hPool := _PoolEntry( cName )
   LOCAL xVal

   hb_mutexLock( hPool[ "mtx" ] )
   xVal := hb_HGetDef( hPool[ "data" ], cKey, xDef )
   hb_mutexUnlock( hPool[ "mtx" ] )

RETURN xVal


FUNCTION HIX_PoolDel( cName, cKey )

   LOCAL hPool := _PoolEntry( cName )

   hb_mutexLock( hPool[ "mtx" ] )
   IF hb_HHasKey( hPool[ "data" ], cKey )
      hb_HDel( hPool[ "data" ], cKey )
   ENDIF
   hb_mutexUnlock( hPool[ "mtx" ] )

RETURN NIL


FUNCTION HIX_PoolHas( cName, cKey )

   LOCAL hPool := _PoolEntry( cName )
   LOCAL lHas

   hb_mutexLock( hPool[ "mtx" ] )
   lHas := hb_HHasKey( hPool[ "data" ], cKey )
   hb_mutexUnlock( hPool[ "mtx" ] )

RETURN lHas


FUNCTION HIX_PoolKeys( cName )

   LOCAL hPool := _PoolEntry( cName )
   LOCAL aKeys

   hb_mutexLock( hPool[ "mtx" ] )
   aKeys := hb_HKeys( hPool[ "data" ] )
   hb_mutexUnlock( hPool[ "mtx" ] )

RETURN aKeys


FUNCTION HIX_PoolSize( cName )

   LOCAL hPool := _PoolEntry( cName )
   LOCAL nSize

   hb_mutexLock( hPool[ "mtx" ] )
   nSize := Len( hPool[ "data" ] )
   hb_mutexUnlock( hPool[ "mtx" ] )

RETURN nSize


// ============================================================
// Manual lock -- for multi-step operations that must be atomic.
// Use HIX_Pool*Raw inside the locked block; NEVER atomic ops.
// ============================================================
FUNCTION HIX_PoolLock( cName )
   hb_mutexLock( _PoolEntry( cName )[ "mtx" ] )
RETURN NIL


FUNCTION HIX_PoolUnlock( cName )
   hb_mutexUnlock( _PoolEntry( cName )[ "mtx" ] )
RETURN NIL


// ============================================================
// Raw ops -- no locking; MUST be called under HIX_PoolLock.
// ============================================================
FUNCTION HIX_PoolSetRaw( cName, cKey, xValue )
   _PoolEntry( cName )[ "data" ][ cKey ] := xValue
RETURN NIL


FUNCTION HIX_PoolGetRaw( cName, cKey, xDef )
RETURN hb_HGetDef( _PoolEntry( cName )[ "data" ], cKey, xDef )


FUNCTION HIX_PoolDelRaw( cName, cKey )
   LOCAL hData := _PoolEntry( cName )[ "data" ]
   IF hb_HHasKey( hData, cKey )
      hb_HDel( hData, cKey )
   ENDIF
RETURN NIL


FUNCTION HIX_PoolHasRaw( cName, cKey )
RETURN hb_HHasKey( _PoolEntry( cName )[ "data" ], cKey )


FUNCTION HIX_PoolKeysRaw( cName )
RETURN hb_HKeys( _PoolEntry( cName )[ "data" ] )


// ============================================================
// _PoolEntry -- return pool hash; throws 500 if not created.
// ============================================================
STATIC FUNCTION _PoolEntry( cName )

   LOCAL hPool

   _PoolMgrInit()

   hb_mutexLock( s_mtxMgr )
   hPool := hb_HGetDef( s_hPools, cName, NIL )
   hb_mutexUnlock( s_mtxMgr )

   IF hPool == NIL
      HIX_Throw( HIX_NewError( "Pool '" + cName + "' not found. Call HIX_PoolCreate() first.", ;
         "DataPool", 500, "_PoolEntry" ) )
   ENDIF

RETURN hPool
