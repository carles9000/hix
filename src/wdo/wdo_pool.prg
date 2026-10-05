/*-----------------------------------------------------------
  File ......: wdo_pool.prg
  Author.....: Charly 9000
  Created....: 2026-09-27
  Modified...: 2026-09-27
  Version....: 1.0.0
  Description: Generic WDO connection pool + global registry.
               Drivers register their pool under a string key
               (e.g. "MYSQL"). Handlers acquire with WDO_Get(cKey)
               and release with oConn:Close() (transparent override
               on driver classes that set DATA oPool).
               Thread-local tracking (THREAD STATIC) enables safety
               net WDO_ReleaseAllThread(), called by the dispatcher
               after every request to reclaim any connection that
               a handler forgot to close or lost due to an exception.
  Usage      : WDO_RegisterPool( "MYSQL", oPool )
               oConn := WDO_Get( "MYSQL" )
               oConn:Close()                          // -> release
               WDO_ReleaseAllThread()                 // dispatcher hook
  Notes      : Fast-path via sl_HasPools makes the release hook
               ~1 ns when no pool is registered. THREAD STATIC
               eliminates mutex contention on the borrowed list.
 -----------------------------------------------------------*/

#include 'hix_const.ch'
#include 'hix_logger.ch'
#include 'hbclass.ch'
#include "wdo_metrics.ch"

#define WDO_POOL_VERSION           '1.0'
#define WDO_POOL_DEFAULT_TIMEOUT   5000     // ms
#define WDO_POOL_NOTIFY_TICK       50       // ms per wait slice

STATIC sh_Pools    := {=>}
STATIC sl_HasPools := .F.
STATIC so_Mutex                                     // guards sh_Pools registry

INIT PROCEDURE _WDO_PoolInit()
   so_Mutex := hb_mutexCreate()
RETURN


CLASS WDO_Pool

   DATA cDriver                                       // "MYSQL", "SQLITE", ...
   DATA nSize                                         // fixed pool size
   DATA nTimeoutMs                                    // acquire timeout
   DATA lPing                                         // health-check on Acquire
   DATA bFactory                                      // codeblock: creates a new connection
   DATA aItems                                        // array of { oConn, lBusy, tSince, nTid, bErrOrig }
   DATA hMutex                                        // guards aItems
   DATA hNotify                                       // notify mutex for waiters
   DATA lClosed                                       INIT .F.
   DATA nCreated                                      INIT 0

   METHOD New( cDriver, nSize, nTimeoutMs, lPing, bFactory ) CONSTRUCTOR
   METHOD Init()
   METHOD Acquire()
   METHOD Release( oConn )
   METHOD Close()
   METHOD Stats()
   METHOD Size()                       INLINE ::nSize
   METHOD Busy()
   METHOD Free()

ENDCLASS


METHOD New( cDriver, nSize, nTimeoutMs, lPing, bFactory ) CLASS WDO_Pool

   hb_default( @cDriver,    "GENERIC" )
   hb_default( @nSize,      5 )
   hb_default( @nTimeoutMs, WDO_POOL_DEFAULT_TIMEOUT )
   hb_default( @lPing,      .T. )

   ::cDriver    := Upper( cDriver )
   ::nSize      := Max( 1, nSize )
   ::nTimeoutMs := Max( 0, nTimeoutMs )
   ::lPing      := lPing
   ::bFactory   := bFactory
   ::aItems     := {}
   ::hMutex     := hb_mutexCreate()
   ::hNotify    := hb_mutexCreate()

RETU SELF


//  Populates the pool with nSize connections. Returns count actually opened.
//  Init errors are logged (WARN) but don't abort — better a small pool than none.
METHOD Init() CLASS WDO_Pool

   LOCAL i, oConn, oErr, nOk := 0

   IF ::bFactory == NIL
      HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Init: bFactory==NIL, aborting" )
      RETU 0
   ENDIF

   HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Init: opening " + hb_NToS( ::nSize ) + ;
            " connections (ping=" + iif( ::lPing, "T", "F" ) + ;
            " timeout=" + hb_NToS( ::nTimeoutMs ) + "ms)" )

   FOR i := 1 TO ::nSize
      //  Contain any Break() thrown by the factory (typical when the
      //  driver class has lShowError=.T. and the DLL fails to load).
      //  Without this the exception unwinds past Init(), past InitPoolEx,
      //  and past Main() into the runtime error handler which pops a
      //  modal dialog and hangs the process.
      oConn := NIL
      TRY
         oConn := Eval( ::bFactory, i )
      CATCH oErr
         HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Init:   slot #" + hb_NToS( i ) + ;
                  " factory threw: " + oErr:description )
         oConn := NIL
      END
      IF oConn != NIL .AND. oConn:lConnect
         oConn:oPool := SELF
         hb_mutexLock( ::hMutex )
         //  Snapshot bError post-factory so Release can restore it after
         //  a handler override, preventing per-request overrides from
         //  leaking across acquisitions of the same slot.
         AAdd( ::aItems, { oConn, .F., hb_DateTime(), 0, oConn:bError } )
         ::nCreated++
         hb_mutexUnlock( ::hMutex )
         nOk++
         HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Init:   slot #" + hb_NToS( i ) + " OPENED" )
      ELSE
         lw( _( 'WDO_LOG_POOL_INIT_FAIL', ::cDriver, i, ;
                iif( oConn != NIL, ": " + oConn:cError, "" ) ) )
         HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Init:   slot #" + hb_NToS( i ) + " FAILED" + ;
                  iif( oConn != NIL, ": " + oConn:cError, "" ) )
      ENDIF
   NEXT

   HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Init: done, opened " + hb_NToS( nOk ) + ;
            "/" + hb_NToS( ::nSize ) )

RETU nOk


//  Acquire: block until a free connection appears or timeout expires.
//  On success: marks busy, tracks in thread-local list, returns oConn.
//  On timeout: SetError EG_LIMIT, returns NIL.
METHOD Acquire() CLASS WDO_Pool

   LOCAL i, nSlot := 0, oConn := NIL
   LOCAL nWaited := 0
   LOCAL nTid    := hb_threadId( hb_threadSelf() )
   LOCAL nT0     := hb_MilliSeconds()
   LOCAL lPingOk, nPos, oErr

   IF ::lClosed
      HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Acquire (tid=" + hb_NToS( nTid ) + ;
               "): pool CLOSED, returning NIL" )
      RETU NIL
   ENDIF

   HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Acquire : looking for free slot" )

   DO WHILE oConn == NIL

      hb_mutexLock( ::hMutex )
      FOR i := 1 TO Len( ::aItems )
         IF ! ::aItems[ i ][ 2 ]     // not busy
            ::aItems[ i ][ 2 ] := .T.
            ::aItems[ i ][ 3 ] := hb_DateTime()
            ::aItems[ i ][ 4 ] := nTid
            oConn              := ::aItems[ i ][ 1 ]
            nSlot              := i
            EXIT
         ENDIF
      NEXT
      hb_mutexUnlock( ::hMutex )

      IF oConn != NIL
         HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Acquire (tid=" + hb_NToS( nTid ) + ;
                  "): got slot #" + hb_NToS( nSlot ) + " after " + hb_NToS( nWaited ) + "ms" )
         EXIT
      ENDIF

      IF ::nTimeoutMs > 0 .AND. nWaited >= ::nTimeoutMs
         lw( _( 'WDO_LOG_ACQUIRE_TIMEOUT', ::cDriver, ::nTimeoutMs ) )
         HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Acquire (tid=" + hb_NToS( nTid ) + ;
                  "): TIMEOUT after " + hb_NToS( ::nTimeoutMs ) + "ms" )
         WDO_Metric( WDOM_ACQUIRES_TIMEOUT )
         RETU NIL
      ENDIF

      //  Wait for a Release() to notify. Slice sleeps so a closed pool
      //  or timeout is honored quickly.
      hb_mutexSubscribe( ::hNotify, WDO_POOL_NOTIFY_TICK / 1000.0 )
      nWaited += WDO_POOL_NOTIFY_TICK

      IF ::lClosed
         HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Acquire (tid=" + hb_NToS( nTid ) + ;
                  "): pool CLOSED while waiting" )
         RETU NIL
      ENDIF

   ENDDO

   //  Track in thread-local list BEFORE Ping so that if Ping hangs or
   //  throws, WDO_ReleaseAllThread() can still reclaim this connection.
   AAdd( _Borrowed(), oConn )

   //  Health check — wrapped in TRY/CATCH so a Ping exception doesn't
   //  bypass the fail-path (which would leave the slot busy forever).
   IF ::lPing
      TRY
         lPingOk := oConn:Ping()
      CATCH oErr
         HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Acquire (tid=" + hb_NToS( nTid ) + ;
                  "): ping THREW on slot #" + hb_NToS( nSlot ) + ": " + oErr:description )
         lPingOk := .F.
      END
      IF ! lPingOk
         lw( _( 'WDO_LOG_PING_RECONNECT', ::cDriver ) )
         HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Acquire (tid=" + hb_NToS( nTid ) + ;
                  "): ping FAILED on slot #" + hb_NToS( nSlot ) + ", reconnecting" )
         oConn:oPool := NIL          // avoid recursive Close-as-release
         oConn:Close()
         oConn:Open()
         oConn:oPool := SELF
         //  Reconnect wipes bError; re-inject the snapshot to keep the
         //  invariant "acquired conn always has pool-wide handler".
         oConn:bError := ::aItems[ nSlot ][ 5 ]
         IF ! oConn:lConnect
            HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Acquire (tid=" + hb_NToS( nTid ) + ;
                     "): reconnect FAILED on slot #" + hb_NToS( nSlot ) )
            //  Reconnect failed: untrack from _Borrowed (we added it above),
            //  mark busy=.F. and return NIL
            nPos := AScan( _Borrowed(), {| x | x == oConn } )
            IF nPos > 0
               hb_ADel( _Borrowed(), nPos, .T. )
            ENDIF
            hb_mutexLock( ::hMutex )
            FOR i := 1 TO Len( ::aItems )
               IF ::aItems[ i ][ 1 ] == oConn
                  ::aItems[ i ][ 2 ] := .F.
                  EXIT
               ENDIF
            NEXT
            hb_mutexUnlock( ::hMutex )
            hb_mutexNotify( ::hNotify )
            RETU NIL
         ENDIF
         HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Acquire (tid=" + hb_NToS( nTid ) + ;
                  "): reconnect OK on slot #" + hb_NToS( nSlot ) )
      ENDIF
   ENDIF

   WDO_Metric( WDOM_ACQUIRES_TOTAL )
   WDO_Metric( WDOM_ACTIVE_CONN )
   WDO_MetricAcquire( hb_MilliSeconds() - nT0 )

RETU oConn


//  Release: rollback if in-tx, mark free, notify one waiter, untrack.
METHOD Release( oConn ) CLASS WDO_Pool

   LOCAL i, nPos, nSlot := 0
   LOCAL nTid := hb_threadId( hb_threadSelf() )

   IF oConn == NIL
      HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Release : oConn==NIL, no-op" )
      RETU NIL
   ENDIF

   //  Defensive rollback: never return a dirty connection to the pool
   IF oConn:lInTrans
      HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Release (tid=" + hb_NToS( nTid ) + ;
               "): AUTO-ROLLBACK (conn was in transaction)" )
      oConn:Rollback()
   ENDIF

   //  Untrack from thread-local list
   nPos := AScan( _Borrowed(), {| x | x == oConn } )
   IF nPos > 0
      hb_ADel( _Borrowed(), nPos, .T. )
   ENDIF

   hb_mutexLock( ::hMutex )
   FOR i := 1 TO Len( ::aItems )
      IF ::aItems[ i ][ 1 ] == oConn
         //  Restore factory-injected bError: a per-request override
         //  must not survive the release, or the next Acquire on this
         //  slot would inherit it (silently disabling the pool-wide handler).
         oConn:bError       := ::aItems[ i ][ 5 ]
         ::aItems[ i ][ 2 ] := .F.
         ::aItems[ i ][ 4 ] := 0
         nSlot              := i
         EXIT
      ENDIF
   NEXT
   hb_mutexUnlock( ::hMutex )

   HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Release (tid=" + hb_NToS( nTid ) + ;
            "): slot #" + hb_NToS( nSlot ) + " freed, notify one waiter" )

   hb_mutexNotify( ::hNotify )

   WDO_Metric( WDOM_RELEASES_TOTAL )
   WDO_MetricDec( WDOM_ACTIVE_CONN )

RETU NIL


//  Close pool: mark closed, tear down all connections. Wakes waiters.
METHOD Close() CLASS WDO_Pool

   LOCAL i, oConn, nTotal, nBusy := 0

   HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Close: BEGIN (tid=" + ;
            hb_NToS( hb_threadId( hb_threadSelf() ) ) + ")" )

   ::lClosed := .T.
   hb_mutexNotifyAll( ::hNotify )
   HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Close: notified all waiters" )

   hb_mutexLock( ::hMutex )
   nTotal := Len( ::aItems )

   //  Contar busy antes de teardown para diagnóstico de leaks
   FOR i := 1 TO nTotal
      IF ::aItems[ i ][ 2 ]
         nBusy++
      ENDIF
   NEXT

   IF nBusy > 0
      HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Close: WARNING " + hb_NToS( nBusy ) + ;
               "/" + hb_NToS( nTotal ) + " slots still busy at shutdown" )
   ENDIF

   FOR i := 1 TO nTotal
      oConn := ::aItems[ i ][ 1 ]
      IF oConn != NIL
         HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Close:   tearing down slot #" + ;
                  hb_NToS( i ) + iif( ::aItems[ i ][ 2 ], " (was busy)", "" ) )
         oConn:oPool := NIL     // now Close() really tears down TCP
         oConn:Close()
      ELSE
         HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Close:   slot #" + hb_NToS( i ) + " already NIL" )
      ENDIF
   NEXT
   ::aItems := {}
   hb_mutexUnlock( ::hMutex )

   HIX_Dbg( "[WDO_Pool:" + ::cDriver + "] Close: END (torn down " + hb_NToS( nTotal ) + " slots)" )

RETU NIL


METHOD Busy() CLASS WDO_Pool

   LOCAL i, n := 0

   hb_mutexLock( ::hMutex )
   FOR i := 1 TO Len( ::aItems )
      IF ::aItems[ i ][ 2 ]
         n++
      ENDIF
   NEXT
   hb_mutexUnlock( ::hMutex )

RETU n


METHOD Free() CLASS WDO_Pool

RETU ::Size() - ::Busy()


METHOD Stats() CLASS WDO_Pool

   LOCAL nBusy := ::Busy()

RETU { ;
   "driver" => ::cDriver, ;
   "size"   => ::nSize,   ;
   "busy"   => nBusy,     ;
   "free"   => ::nSize - nBusy, ;
   "closed" => ::lClosed }


//	=======================================================  //
//  Registro global + helpers públicos
//	=======================================================  //

//  Register a pool under a driver key. Called by driver-specific
//  helpers (WDO_InitPoolMySql, ...). Sets sl_HasPools flag.
FUNCTION WDO_RegisterPool( cDriver, oPool )

   LOCAL cKey := Upper( cDriver )

   hb_mutexLock( so_Mutex )
   sh_Pools[ cKey ] := oPool
   sl_HasPools      := .T.
   hb_mutexUnlock( so_Mutex )

   HIX_Dbg( "[WDO_Pool] RegisterPool: '" + cKey + "' registered (sl_HasPools=T)" )

RETU NIL


//  Unregister and close. Recomputes sl_HasPools.
FUNCTION WDO_UnregisterPool( cDriver )

   LOCAL cKey := Upper( cDriver )
   LOCAL oPool

   HIX_Dbg( "[WDO_Pool] UnregisterPool: '" + cKey + "' BEGIN" )

   hb_mutexLock( so_Mutex )
   IF hb_HHasKey( sh_Pools, cKey )
      oPool := sh_Pools[ cKey ]
      hb_HDel( sh_Pools, cKey )
   ENDIF
   sl_HasPools := ! Empty( sh_Pools )
   hb_mutexUnlock( so_Mutex )

   IF oPool != NIL
      oPool:Close()
   ELSE
      HIX_Dbg( "[WDO_Pool] UnregisterPool: '" + cKey + "' NOT FOUND in registry" )
   ENDIF

   HIX_Dbg( "[WDO_Pool] UnregisterPool: '" + cKey + "' END (sl_HasPools=" + ;
            iif( sl_HasPools, "T", "F" ) + ")" )

RETU NIL


//  Acquire a connection from the named pool. Returns NIL on timeout
//  or if the driver is not registered.
FUNCTION WDO_Get( cDriver )

   LOCAL cKey := Upper( hb_defaultValue( cDriver, "" ) )
   LOCAL oPool

   hb_mutexLock( so_Mutex )
   IF hb_HHasKey( sh_Pools, cKey )
      oPool := sh_Pools[ cKey ]
   ENDIF
   hb_mutexUnlock( so_Mutex )

   IF oPool == NIL
      lw( _( 'WDO_LOG_GET_NO_POOL', cKey ) )
      RETU NIL
   ENDIF

RETU oPool:Acquire()


//  Fast-path flag reader. Dispatcher hook uses this to skip work
//  when no pool has been initialized (99% of projects without DB).
FUNCTION WDO_HasPools()
RETU sl_HasPools


//  Returns the list of registered pool keys (snapshot).
//  Consumed by HIX_EndPoolsFromConfig to iterate & unregister.
FUNCTION WDO_ListPools()

   LOCAL aKeys

   hb_mutexLock( so_Mutex )
   aKeys := hb_HKeys( sh_Pools )
   hb_mutexUnlock( so_Mutex )

RETU aKeys


//  Introspection: hash of pool metrics or NIL if not registered.
FUNCTION WDO_PoolStats( cDriver )

   LOCAL cKey := Upper( hb_defaultValue( cDriver, "" ) )
   LOCAL oPool, hRet := NIL

   hb_mutexLock( so_Mutex )
   IF hb_HHasKey( sh_Pools, cKey )
      oPool := sh_Pools[ cKey ]
   ENDIF
   hb_mutexUnlock( so_Mutex )

   IF oPool != NIL
      hRet := oPool:Stats()
   ENDIF

RETU hRet


//  Dispatcher hook: releases every connection borrowed by the current
//  thread. Called from _HixEvalAction after each request (success or
//  exception). Fast-path when no pools exist. Logs WARN if leaks found.
FUNCTION WDO_ReleaseAllThread()

   LOCAL aList, oConn, nCount

   IF ! sl_HasPools
      RETU NIL             // fast path: ~1 ns
   ENDIF

   aList  := _Borrowed()
   nCount := Len( aList )

   IF nCount == 0
      RETU NIL
   ENDIF

   lw( _( 'WDO_LOG_RELEASE_RECLAIM', nCount, hb_threadId( hb_threadSelf() ) ) )
   HIX_Dbg( "[WDO_Pool] ReleaseAllThread (tid=" + hb_NToS( hb_threadId( hb_threadSelf() ) ) + ;
            "): reclaiming " + hb_NToS( nCount ) + " leaked connection(s)" )

   WDO_Metric( WDOM_RELEASES_RECLAIMED, nCount )

   //  Iterate a copy — Release() mutates _Borrowed()
   FOR EACH oConn IN AClone( aList )
      IF oConn != NIL .AND. oConn:oPool != NIL
         oConn:oPool:Release( oConn )
      ENDIF
   NEXT

   //  Belt-and-braces: force clear even if a Release above failed
   ASize( _Borrowed(), 0 )

RETU NIL


//  Thread-local accessor. THREAD STATIC gives each thread its own slot,
//  so Get/Release track in a lock-free per-thread list. All access to
//  the borrowed list goes through this accessor to share the same slot
//  between functions in the same module.
STATIC FUNCTION _Borrowed()

   THREAD STATIC t_aList := NIL

   IF t_aList == NIL
      t_aList := {}
   ENDIF

RETU t_aList


//	-------------------------------------------------------  //

FUNCTION WDO_PoolVersion()
RETU WDO_POOL_VERSION
