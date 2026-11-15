/*-----------------------------------------------------------
  File ......: mymsgthrottle.prg
  Author.....: Charly 9000
  Created....: 2026-08-20
  Modified...: 2026-08-20
  Version....: 1.0.0
  Description: Throttle middleware for the /message module. Allows
               one accepted POST per client IP within a sliding
               window (60 s by default). Extra requests inside the
               window are rejected with HTTP 429 and the number of
               seconds left before the next attempt is allowed.
  Usage      : "middleware": "MyMsgThrottle" in routes/web.json
               Window is read from middlewares/config.json:
               "setup": { "message": { "window_s": 60 } }
  Notes      : State lives in a STATIC hash shared by every worker
               thread and guarded by a mutex, so it is not persisted
               across restarts. Like any standard throttle, the window
               is consumed before the controller runs: an invalid
               payload also burns the slot.
 -----------------------------------------------------------*/

STATIC s_hLast   := { => }             // cIP => nUnixSeconds of last accepted POST
STATIC s_mtxLast := hb_mutexCreate()
STATIC s_nWindow := 0                  // 0 = not resolved yet, read from config.json

#define MSG_GC_LIMIT   500             // purge expired entries above this size

FUNCTION MyMsgThrottle( oCtx )

   LOCAL cIP, nNow, nWait, nWindow

   cIP     := oCtx:oReq:RealIP()
   nNow    := Int( hb_TToSec( hb_DateTime() ) )
   nWait   := 0
   nWindow := _Window()

   hb_mutexLock( s_mtxLast )

   IF hb_HHasKey( s_hLast, cIP ) .AND. ( nNow - s_hLast[ cIP ] ) < nWindow

      nWait := nWindow - ( nNow - s_hLast[ cIP ] )

   ELSE

      s_hLast[ cIP ] := nNow

      IF Len( s_hLast ) > MSG_GC_LIMIT
         _Purge( nNow, nWindow )
      ENDIF

   ENDIF

   hb_mutexUnlock( s_mtxLast )

   IF nWait > 0

      oCtx:lHandled := .T.
      oCtx:oReq:Respond( { 'ok'    => .F.,                                          ;
                           'wait'  => nWait,                                        ;
                           'error' => 'Only one message per minute. Try again in '  ;
                                      + hb_NToS( nWait ) + 's'                      }, 429, 'json' )
      RETURN .F.

   ENDIF

   oCtx:hData[ 'msg_window' ] := nWindow

RETURN .T.

/*-----------------------------------------------------------
  Window size in seconds, resolved once from middlewares/config.json
 -----------------------------------------------------------*/

STATIC FUNCTION _Window()

   IF s_nWindow == 0
      s_nWindow := HIX_MwConfig( 'message', 'window_s', 60 )
      IF ValType( s_nWindow ) != 'N' .OR. s_nWindow <= 0
         s_nWindow := 60
      ENDIF
   ENDIF

RETURN s_nWindow

/*-----------------------------------------------------------
  Drops entries already outside the window. Caller holds the mutex.
 -----------------------------------------------------------*/

STATIC FUNCTION _Purge( nNow, nWindow )

   LOCAL cKey

   FOR EACH cKey IN hb_HKeys( s_hLast )
      IF ( nNow - s_hLast[ cKey ] ) >= nWindow
         hb_HDel( s_hLast, cKey )
      ENDIF
   NEXT

RETURN NIL
