/*-----------------------------------------------------------
  File ......: hix_sse.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-01
  Description: Pub/sub bus for Server-Sent Events — HIX_SseBroadcast /
               HIX_SseCount.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_WORKER_OTROS
#INCLUDE "hix_logger.ch"

STATIC s_hSseMutex := NIL
STATIC s_hSseBus   := NIL   // hash: cChannel -> array de THixSseConn

CLASS THixSseConn

   DATA oIO
   DATA cChannel
   DATA nLastId  INIT 0
   DATA lActive  INIT .T.

ENDCLASS

// ------------------------------------------------------------
FUNCTION HIX_SseSetup()

   _HixSseInit()

RETURN NIL

// ------------------------------------------------------------
// HIX_SseBroadcast — emite un frame SSE a todos los clientes activos del canal
// Retorna numero de clientes notificados
// ------------------------------------------------------------
FUNCTION HIX_SseBroadcast( cChannel, cData, cEvent, nId )

   LOCAL aList, i, oConn, cFrame, nNotified

   hb_default( @cEvent, "" )
   hb_default( @nId, 0 )
   _HixSseInit()

   hb_mutexLock( s_hSseMutex )

   IF hb_hHasKey( s_hSseBus, cChannel )

      aList := AClone( s_hSseBus[ cChannel ] )
   ELSE
      aList := {}

   ENDIF

   hb_mutexUnlock( s_hSseMutex )

   cFrame := ""

   IF nId > 0

      cFrame += "id: " + hb_NToS( nId ) + Chr( 10 )

   ENDIF

   IF ! Empty( cEvent )

      cFrame += "event: " + cEvent + Chr( 10 )

   ENDIF

   cFrame += "data: " + cData + Chr( 10 ) + Chr( 10 )

   nNotified := 0

   FOR i := 1 TO Len( aList )

      oConn := aList[ i ]

      IF oConn:lActive

         IF oConn:oIO:Write( cFrame )

            IF nId > 0

               oConn:nLastId := nId

            ENDIF

            nNotified++
         ELSE
            oConn:lActive := .F.

         ENDIF

      ENDIF

   NEXT

   ld( "SseBroadcast channel=" + cChannel + " notified=" + hb_NToS( nNotified ) )

RETURN nNotified

// ------------------------------------------------------------
// HIX_SseCount — numero de conexiones activas en el canal
// ------------------------------------------------------------
FUNCTION HIX_SseCount( cChannel )

   LOCAL nCount, aList, i

   nCount := 0
   _HixSseInit()
   hb_mutexLock( s_hSseMutex )

   IF hb_hHasKey( s_hSseBus, cChannel )

      aList := s_hSseBus[ cChannel ]

      FOR i := 1 TO Len( aList )

         IF aList[ i ]:lActive

            nCount++

         ENDIF

      NEXT

   ENDIF

   hb_mutexUnlock( s_hSseMutex )

RETURN nCount

// ============================================================
// Funciones internas
// ============================================================

FUNCTION _HixSseRegister( oIO, cChannel, nLastId )

   LOCAL oConn

   _HixSseInit()
   hb_default( @nLastId, 0 )
   oConn          := THixSseConn():New()
   oConn:oIO      := oIO
   oConn:cChannel := cChannel
   oConn:nLastId  := nLastId
   hb_mutexLock( s_hSseMutex )

   IF ! hb_hHasKey( s_hSseBus, cChannel )

      s_hSseBus[ cChannel ] := {}

   ENDIF

   AAdd( s_hSseBus[ cChannel ], oConn )
   hb_mutexUnlock( s_hSseMutex )

RETURN oConn

FUNCTION _HixSseUnregister( oConn )

   LOCAL aList, i

   _HixSseInit()
   hb_mutexLock( s_hSseMutex )

   IF hb_hHasKey( s_hSseBus, oConn:cChannel )

      aList := s_hSseBus[ oConn:cChannel ]

      FOR i := 1 TO Len( aList )

         IF aList[ i ] == oConn

            ADel( aList, i )
            ASize( aList, Len( aList ) - 1 )
            EXIT

         ENDIF

      NEXT

   ENDIF

   hb_mutexUnlock( s_hSseMutex )

RETURN NIL

STATIC FUNCTION _HixSseInit()

   IF s_hSseMutex == NIL

      s_hSseMutex := hb_mutexCreate()
      s_hSseBus   := hb_Hash()

   ENDIF

RETURN NIL
