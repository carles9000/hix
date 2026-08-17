/*-----------------------------------------------------------
  File ......: hix_test_data_pool.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Version....: 1.0.0
  Description: Integrated test -- HIX_DataPool named in-memory
               pools (hix_data_pool.prg): create, atomic ops,
               batch lock/raw, multiple pools, concurrency.
 -----------------------------------------------------------*/

FUNCTION HIX_TestDataPool_Run()

   LOCAL hCtx := { "total" => 0, "passed" => 0, "failed" => 0, "results" => {} }

   _TestPoolBasic( hCtx )
   _TestPoolBatch( hCtx )
   _TestPoolMultiple( hCtx )
   _TestPoolConcurrent( hCtx )

RETURN hCtx


// ============================================================
// T-01..T-09 -- basic atomic operations
// ============================================================
STATIC PROCEDURE _TestPoolBasic( hCtx )

   LOCAL xVal, aKeys

   HIX_PoolCreate( "test_basic" )

   // T-01: get on empty pool returns default
   xVal := HIX_PoolGet( "test_basic", "missing", "default" )
   HixTU_Check( hCtx, xVal == "default", ;
      "DataPool T01: get missing key -> default", "default", xVal )

   // T-02: has on empty pool returns .F.
   HixTU_Check( hCtx, ! HIX_PoolHas( "test_basic", "k1" ), ;
      "DataPool T02: has missing -> .F.", ".F.", hb_CStr( HIX_PoolHas( "test_basic", "k1" ) ) )

   // T-03: set + get
   HIX_PoolSet( "test_basic", "k1", "hello" )
   xVal := HIX_PoolGet( "test_basic", "k1", "" )
   HixTU_Check( hCtx, xVal == "hello", ;
      "DataPool T03: set + get string", "hello", xVal )

   // T-04: has returns .T. after set
   HixTU_Check( hCtx, HIX_PoolHas( "test_basic", "k1" ), ;
      "DataPool T04: has after set -> .T.", ".T.", hb_CStr( HIX_PoolHas( "test_basic", "k1" ) ) )

   // T-05: set hash value
   HIX_PoolSet( "test_basic", "entry", { "user" => "admin", "exp" => 9999 } )
   xVal := HIX_PoolGet( "test_basic", "entry", NIL )
   HixTU_Check( hCtx, HB_ISHASH( xVal ) .AND. xVal[ "user" ] == "admin", ;
      "DataPool T05: set + get hash entry", "admin", hb_HGetDef( xVal, "user", "" ) )

   // T-06: size
   HixTU_Check( hCtx, HIX_PoolSize( "test_basic" ) == 2, ;
      "DataPool T06: size == 2", "2", hb_NToS( HIX_PoolSize( "test_basic" ) ) )

   // T-07: keys snapshot
   aKeys := HIX_PoolKeys( "test_basic" )
   HixTU_Check( hCtx, Len( aKeys ) == 2, ;
      "DataPool T07: keys snapshot len == 2", "2", hb_NToS( Len( aKeys ) ) )

   // T-08: del removes key
   HIX_PoolDel( "test_basic", "k1" )
   HixTU_Check( hCtx, ! HIX_PoolHas( "test_basic", "k1" ), ;
      "DataPool T08: del -> has returns .F.", ".F.", hb_CStr( HIX_PoolHas( "test_basic", "k1" ) ) )

   // T-09: size after del
   HixTU_Check( hCtx, HIX_PoolSize( "test_basic" ) == 1, ;
      "DataPool T09: size == 1 after del", "1", hb_NToS( HIX_PoolSize( "test_basic" ) ) )

   HIX_PoolDestroy( "test_basic" )

RETURN


// ============================================================
// T-10..T-14 -- HIX_PoolExists, idempotent create, destroy
// ============================================================
STATIC PROCEDURE _TestPoolBatch( hCtx )

   LOCAL aKeys, hEntry, hVal

   // T-10: PoolExists false before create
   HixTU_Check( hCtx, ! HIX_PoolExists( "test_batch" ), ;
      "DataPool T10: PoolExists false before create", ".F.", ".T." )

   HIX_PoolCreate( "test_batch" )

   // T-11: PoolExists true after create
   HixTU_Check( hCtx, HIX_PoolExists( "test_batch" ), ;
      "DataPool T11: PoolExists true after create", ".T.", ".F." )

   // T-12: create is idempotent (second call does not wipe data)
   HIX_PoolSet( "test_batch", "saved", "data" )
   HIX_PoolCreate( "test_batch" )
   HixTU_Check( hCtx, HIX_PoolGet( "test_batch", "saved", "" ) == "data", ;
      "DataPool T12: create idempotent keeps existing data", "data", ;
      HIX_PoolGet( "test_batch", "saved", "" ) )

   // T-13: batch lock + raw ops
   HIX_PoolSet( "test_batch", "a", { "v" => 1 } )
   HIX_PoolSet( "test_batch", "b", { "v" => 2 } )

   HIX_PoolLock( "test_batch" )
   aKeys := HIX_PoolKeysRaw( "test_batch" )
   FOR EACH hEntry IN aKeys
      hVal := HIX_PoolGetRaw( "test_batch", hEntry, NIL )
      IF HB_ISHASH( hVal )
         hVal[ "v" ] += 10
         HIX_PoolSetRaw( "test_batch", hEntry, hVal )
      ENDIF
   NEXT
   HIX_PoolUnlock( "test_batch" )

   HixTU_Check( hCtx, HIX_PoolGet( "test_batch", "a", NIL )[ "v" ] == 11, ;
      "DataPool T13: batch raw update -> a.v == 11", "11", ;
      hb_NToS( HIX_PoolGet( "test_batch", "a", { "v" => 0 } )[ "v" ] ) )

   // T-14: PoolExists false after destroy
   HIX_PoolDestroy( "test_batch" )
   HixTU_Check( hCtx, ! HIX_PoolExists( "test_batch" ), ;
      "DataPool T14: PoolExists false after destroy", ".F.", ".T." )

RETURN


// ============================================================
// T-15..T-16 -- two pools do not interfere
// ============================================================
STATIC PROCEDURE _TestPoolMultiple( hCtx )

   LOCAL xA, xB

   HIX_PoolCreate( "pool_a" )
   HIX_PoolCreate( "pool_b" )

   HIX_PoolSet( "pool_a", "key", "value-A" )
   HIX_PoolSet( "pool_b", "key", "value-B" )

   xA := HIX_PoolGet( "pool_a", "key", "" )
   xB := HIX_PoolGet( "pool_b", "key", "" )

   // T-15: pools are independent
   HixTU_Check( hCtx, xA == "value-A" .AND. xB == "value-B", ;
      "DataPool T15: two pools independent", "A+B", xA + "+" + xB )

   // T-16: del in one pool does not affect the other
   HIX_PoolDel( "pool_a", "key" )
   HixTU_Check( hCtx, ! HIX_PoolHas( "pool_a", "key" ) .AND. HIX_PoolHas( "pool_b", "key" ), ;
      "DataPool T16: del in pool_a does not affect pool_b", ".T.", ;
      iif( ! HIX_PoolHas( "pool_a", "key" ) .AND. HIX_PoolHas( "pool_b", "key" ), ".T.", ".F." ) )

   HIX_PoolDestroy( "pool_a" )
   HIX_PoolDestroy( "pool_b" )

RETURN


// ============================================================
// T-17 -- concurrent writes from two threads do not corrupt
// ============================================================
STATIC PROCEDURE _TestPoolConcurrent( hCtx )

   LOCAL hThread1, hThread2, nSize, N := 200

   HIX_PoolCreate( "test_conc" )

   hThread1 := hb_threadStart( {|| _ConcWriter( "test_conc", "t1", N ) } )
   hThread2 := hb_threadStart( {|| _ConcWriter( "test_conc", "t2", N ) } )

   hb_threadJoin( hThread1 )
   hb_threadJoin( hThread2 )

   nSize := HIX_PoolSize( "test_conc" )

   HixTU_Check( hCtx, nSize == N * 2, ;
      "DataPool T17: concurrent writes -> " + hb_NToS( N * 2 ) + " entries", ;
      hb_NToS( N * 2 ), hb_NToS( nSize ) )

   HIX_PoolDestroy( "test_conc" )

RETURN


STATIC PROCEDURE _ConcWriter( cPool, cPrefix, nCount )

   LOCAL i

   FOR i := 1 TO nCount
      HIX_PoolSet( cPool, cPrefix + hb_NToS( i ), i )
   NEXT

RETURN
