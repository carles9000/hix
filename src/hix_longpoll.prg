/*-----------------------------------------------------------
  File ......: hix_longpoll.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-01
  Description: Pub/sub bus for Long Polling — HIX_LongPollPush /
               HIX_LongPollWait.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_WORKER_OTROS
#INCLUDE "hix_logger.ch"

STATIC s_nDefaultTimeout := 30
STATIC s_hBusMutex       := NIL
STATIC s_hBus            := NIL   // hash: cChannel -> array de hMx

// ------------------------------------------------------------
FUNCTION HIX_LongPollSetup( nTimeoutSec )

   hb_default( @nTimeoutSec, 30 )
   s_nDefaultTimeout := nTimeoutSec
   _HixLpInit()

RETURN NIL

// ------------------------------------------------------------
// HIX_LongPollPush — publica xData a todos los waiters de cChannel
// xData: string JSON ya formateado, o valor que se serializa
// Retorna numero de clientes notificados
// ------------------------------------------------------------
FUNCTION HIX_LongPollPush( cChannel, xData )

   LOCAL aMxList, i, nCount, cJson

   _HixLpInit()

   IF ValType( xData ) == "C"

      cJson := xData
   ELSE
      cJson := hb_jsonEncode( xData )

   ENDIF

   // Copiar lista de mutexes con el bus bloqueado (evita deadlock)
   hb_mutexLock( s_hBusMutex )

   IF hb_hHasKey( s_hBus, cChannel )

      aMxList := AClone( s_hBus[ cChannel ] )
   ELSE
      aMxList := {}

   ENDIF

   hb_mutexUnlock( s_hBusMutex )

   nCount := 0

   FOR i := 1 TO Len( aMxList )

      hb_mutexLock( aMxList[ i ] )
      hb_mutexNotify( aMxList[ i ], cJson )
      hb_mutexUnlock( aMxList[ i ] )
      nCount++

   NEXT

   ld( "LongPollPush channel=" + cChannel + " notified=" + hb_NToS( nCount ) )

RETURN nCount

// ------------------------------------------------------------
FUNCTION HIX_LongPollCount( cChannel )

   LOCAL nCount := 0

   _HixLpInit()
   hb_mutexLock( s_hBusMutex )

   IF hb_hHasKey( s_hBus, cChannel )

      nCount := Len( s_hBus[ cChannel ] )

   ENDIF

   hb_mutexUnlock( s_hBusMutex )

RETURN nCount

// ============================================================
// Funciones internas
// ============================================================

// ------------------------------------------------------------
// _HixLpWait — bloquea hasta datos o timeout
// Retorna { lGotData, cJsonData }
// El valor llega via hb_mutexSubscribe(@xVal) — sin array compartida
// ------------------------------------------------------------
FUNCTION _HixLpWait( cChannel, nTimeoutSec )

   LOCAL hMx := hb_mutexCreate()
   LOCAL lGot, xData

   _HixLpInit()
   hb_default( @nTimeoutSec, s_nDefaultTimeout )

   IF nTimeoutSec <= 0

      nTimeoutSec := s_nDefaultTimeout

   ENDIF

   hb_mutexLock( s_hBusMutex )

   IF ! hb_hHasKey( s_hBus, cChannel )

      s_hBus[ cChannel ] := {}

   ENDIF

   AAdd( s_hBus[ cChannel ], hMx )
   hb_mutexUnlock( s_hBusMutex )

   hb_mutexLock( hMx )
   lGot := hb_mutexSubscribe( hMx, nTimeoutSec, @xData )
   hb_mutexUnlock( hMx )

   hb_mutexLock( s_hBusMutex )
   _HixLpRemove( cChannel, hMx )
   hb_mutexUnlock( s_hBusMutex )

RETURN { lGot, xData }

// ------------------------------------------------------------
STATIC FUNCTION _HixLpInit()

   IF s_hBusMutex == NIL

      s_hBusMutex := hb_mutexCreate()
      s_hBus      := hb_Hash()

   ENDIF

RETURN NIL

// Eliminar hMx del array del canal (llamar con s_hBusMutex bloqueado)
STATIC FUNCTION _HixLpRemove( cChannel, hMx )

   LOCAL aList, i

   IF ! hb_hHasKey( s_hBus, cChannel ) ; RETURN NIL ; ENDIF

   aList := s_hBus[ cChannel ]

   FOR i := 1 TO Len( aList )

      IF aList[ i ] == hMx

         ADel( aList, i )
         ASize( aList, Len( aList ) - 1 )
         EXIT

      ENDIF

   NEXT

RETURN NIL
