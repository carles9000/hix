/*-----------------------------------------------------------
  File ......: hix_worker_otros.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: SSE and LongPoll worker — holds connection open and streams
               events to client.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_WORKER_OTROS

#INCLUDE "hix_logger.ch"

FUNCTION HIX_WorkerRest( aJob )

   LOCAL oIO   := aJob[ 1 ]
   LOCAL cIP   := aJob[ 2 ]
   LOCAL cTipo := aJob[ 3 ]
   LOCAL oReq

   HIX_Metric( HIXM_ACTIVE_OTROS )

   oReq := THixRequest():New( oIO, cIP, HIX_IsProxied() )

   IF ! oReq:Read()

      IF oReq:nReadError == HIX_REQ_ERR_BADREQ

         HIX_ResponseRaw( oIO, hb_jsonEncode( { "error" => _( 'ERR_BAD_REQUEST' ) } ), "json", 400, .F. )

      ENDIF

      oIO:Close()
      HIX_MetricDec( HIXM_ACTIVE_OTROS )
      RETURN NIL

   ENDIF

   DO CASE

      CASE cTipo == HIX_CONN_SSE
         _HixWorkerSSE( oReq )
      CASE cTipo == HIX_CONN_LONGPOLL
         _HixWorkerLongPoll( oReq )
      OTHERWISE
         HIX_ResponseRaw( oIO, hb_jsonEncode( { "error" => _( 'ERR_BAD_REQUEST' ) } ), "json", 400, .F. )

   ENDCASE

   oIO:Close()
   HIX_MetricDec( HIXM_ACTIVE_OTROS )

RETURN NIL

// ============================================================
STATIC FUNCTION _HixWorkerSSE( oReq )

   LOCAL cResp, tLast, cChannel, cLastIdHdr, nLastId, oConn, nTick
   LOCAL lActive := .T.

   cResp := "HTTP/1.1 200 OK"                + Chr( 13 ) + Chr( 10 ) + ;
      "Content-Type: text/event-stream" + Chr( 13 ) + Chr( 10 ) + ;
      "Cache-Control: no-cache"         + Chr( 13 ) + Chr( 10 ) + ;
      "Connection: keep-alive"          + Chr( 13 ) + Chr( 10 ) + ;
      "X-Accel-Buffering: no"           + Chr( 13 ) + Chr( 10 ) + ;
      Chr( 13 ) + Chr( 10 )

   IF ! oReq:oIO:Write( cResp ) ; RETURN NIL ; ENDIF

   cChannel   := oReq:QueryParam( "channel" )

   IF Empty( cChannel ) ; cChannel := "default" ; ENDIF

   cLastIdHdr := oReq:Header( "last-event-id" )
   nLastId    := iif( Empty( cLastIdHdr ), 0, Val( cLastIdHdr ) )

   oConn := _HixSseRegister( oReq:oIO, cChannel, nLastId )
   l( _( "SSE_OPENED", oReq:cIP, cChannel ) )

   nTick := 0
   tLast := hb_DateTime()

   DO WHILE lActive .AND. oConn:lActive .AND. HIX_ServerIsRunning()

      hb_idleSleep( 1 )
      nTick++

      IF nTick < 15 ; LOOP ; ENDIF

      nTick := 0

      IF ! oReq:oIO:Write( ": keep-alive" + Chr( 10 ) + Chr( 10 ) )

         lActive := .F.

      ENDIF

      IF ( hb_DateTime() - tLast ) * 86400 > 3600

         lActive := .F.

      ENDIF

   ENDDO

   _HixSseUnregister( oConn )
   l( _( "SSE_CLOSED", oReq:cIP ) )

RETURN NIL

// ============================================================
STATIC FUNCTION _HixWorkerLongPoll( oReq )

   LOCAL cChannel, nTimeout, aResult, cTimeoutHdr

   // Canal: query param > header > "default"
   cChannel := oReq:QueryParam( "channel" )

   IF Empty( cChannel )

      cChannel := oReq:Header( "x-hix-channel" )

   ENDIF

   IF Empty( cChannel )

      cChannel := "default"

   ENDIF

   // Timeout: header X-Hix-Timeout (segundos) > default del bus
   cTimeoutHdr := oReq:Header( "x-hix-timeout" )
   nTimeout    := iif( Empty( cTimeoutHdr ), 0, Val( cTimeoutHdr ) )

   ld( "LongPoll wait channel=" + cChannel + " ip=" + oReq:cIP )

   aResult := _HixLpWait( cChannel, nTimeout )

   IF aResult[ 1 ] .AND. aResult[ 2 ] != NIL

      oReq:Respond( '{"data":' + aResult[ 2 ] + '}', 200, "json" )
   ELSE
      oReq:Respond( '{"timeout":true}', 200, "json" )

   ENDIF

RETURN NIL
