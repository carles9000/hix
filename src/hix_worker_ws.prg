/*-----------------------------------------------------------
  File ......: hix_worker_ws.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: WebSocket worker — handshake via THixRequest, frame loop
               via THixIO.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_WORKER_WS

#INCLUDE "hix_logger.ch"

#DEFINE WS_OP_CONTINUATION  0x00
#DEFINE WS_OP_TEXT          0x01
#DEFINE WS_OP_BINARY        0x02
#DEFINE WS_OP_CLOSE         0x08
#DEFINE WS_OP_PING          0x09
#DEFINE WS_OP_PONG          0x0A

// Callbacks globales — deben declararse antes de cualquier CLASS/METHOD
STATIC sbOnConnect := NIL
STATIC sbOnMessage := NIL
STATIC sbOnClose   := NIL
STATIC shMutexCb   := NIL

// ============================================================
// THixWsConn — conexión WebSocket activa, pasada a los callbacks
// ============================================================
CLASS THixWsConn

   DATA cIP    INIT ""
   DATA oIO    INIT NIL
   DATA lClosed INIT .F.

   METHOD New( oIO, cIP )
   METHOD Send( cData )
   METHOD SendBinary( cData )
   METHOD Close()

ENDCLASS

METHOD New( oIO, cIP ) CLASS THixWsConn

   ::oIO  := oIO
   ::cIP  := cIP

RETURN Self

METHOD Send( cData ) CLASS THixWsConn

   IF ! ::lClosed

      ::oIO:Write( _HixWSBuildFrame( WS_OP_TEXT, cData ) )

   ENDIF

RETURN Self

METHOD SendBinary( cData ) CLASS THixWsConn

   IF ! ::lClosed

      ::oIO:Write( _HixWSBuildFrame( WS_OP_BINARY, cData ) )

   ENDIF

RETURN Self

METHOD Close() CLASS THixWsConn

   IF ! ::lClosed

      ::lClosed := .T.
      ::oIO:Close()

   ENDIF

RETURN Self

// ============================================================
// Registro global de callbacks WS
// ============================================================
FUNCTION HIX_WsSetCallbacks( bConnect, bMessage, bClose )

   IF shMutexCb == NIL

      shMutexCb := hb_mutexCreate()

   ENDIF

   hb_mutexLock( shMutexCb )
   sbOnConnect := bConnect
   sbOnMessage := bMessage
   sbOnClose   := bClose
   hb_mutexUnlock( shMutexCb )

RETURN NIL

STATIC FUNCTION _HixWsCallbacks()

   LOCAL aR

   IF shMutexCb == NIL

      RETURN { NIL, NIL, NIL }

   ENDIF

   hb_mutexLock( shMutexCb )
   aR := { sbOnConnect, sbOnMessage, sbOnClose }
   hb_mutexUnlock( shMutexCb )

RETURN aR

// ============================================================
// HIX_WorkerWS — entry point desde pool WS (sin SSL / peek detectado)
// ============================================================
FUNCTION HIX_WorkerWS( aJob )

   LOCAL oIO  := aJob[ 1 ]
   LOCAL cIP  := aJob[ 2 ]
   LOCAL oReq

   oReq := THixRequest():New( oIO, cIP, HIX_IsProxied() )

   IF ! oReq:Read()

      IF oReq:nReadError == HIX_REQ_ERR_BADREQ

         ld( "WS: bad request from " + cIP )
         HIX_ResponseRaw( oIO, hb_jsonEncode( { "error" => _( 'ERR_BAD_REQUEST' ) } ), "json", 400, .F. )

      ENDIF

      oIO:Close()
      RETURN NIL

   ENDIF

   HIX_HandleWSUpgrade( oReq, cIP )

RETURN NIL

// ============================================================
// HIX_HandleWSUpgrade — handshake + frame loop con request ya leído.
// Usado por HIX_WorkerWS y por el worker HTTP en conexiones WSS (SSL).
// ============================================================
FUNCTION HIX_HandleWSUpgrade( oReq, cIP )

   LOCAL oConn, aCb

   HIX_Metric( HIXM_ACTIVE_WS )

   IF ! _HixWSHandshake( oReq )

      oReq:oIO:Close()
      HIX_MetricDec( HIXM_ACTIVE_WS )
      RETURN NIL

   ENDIF

   oConn := THixWsConn():New( oReq:oIO, cIP )
   aCb   := _HixWsCallbacks()

   l( _( "WS_CONNECTED", cIP ) )

   IF aCb[ 1 ] != NIL

      Eval( aCb[ 1 ], oConn )

   ENDIF

   _HixWSFrameLoop( oConn, aCb[ 2 ] )

   l( _( "WS_DISCONNECTED", cIP ) )

   IF aCb[ 3 ] != NIL

      Eval( aCb[ 3 ], oConn )

   ENDIF

   oConn:Close()
   HIX_MetricDec( HIXM_ACTIVE_WS )

RETURN NIL

// ============================================================
STATIC FUNCTION _HixWSHandshake( oReq )

   LOCAL cKey, cAccept, cResp
   LOCAL cGUID := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

   cKey := oReq:Header( "sec-websocket-key" )

   IF Empty( cKey )

      le( "WS: no Sec-WebSocket-Key from " + oReq:cIP )
      HIX_ResponseRaw( oReq:oIO, hb_jsonEncode( { "error" => _( 'ERR_BAD_REQUEST' ) } ), "json", 400, .F. )
      RETURN .F.

   ENDIF

   cAccept := hb_base64Encode( hb_SHA1( cKey + cGUID, .T. ) )
   cResp   := "HTTP/1.1 101 Switching Protocols" + Chr( 13 ) + Chr( 10 ) + ;
      "Upgrade: websocket"               + Chr( 13 ) + Chr( 10 ) + ;
      "Connection: Upgrade"              + Chr( 13 ) + Chr( 10 ) + ;
      "Sec-WebSocket-Accept: " + cAccept + Chr( 13 ) + Chr( 10 ) + ;
      Chr( 13 ) + Chr( 10 )

RETURN oReq:oIO:Write( cResp )

// ============================================================
STATIC FUNCTION _HixWSFrameLoop( oConn, bOnMessage )

   LOCAL cFrame, nOpcode, lFin, cPayload
   LOCAL lActive    := .T.
   LOCAL oIO        := oConn:oIO
   LOCAL cIP        := oConn:cIP
   LOCAL nIdle      := 0
   LOCAL lPingSent  := .F.

   ld( "[WS] CONNECT fd=" + hb_NToS( hb_socketGetFD( oIO:hSocket ) ) + " ip=" + cIP )

   DO WHILE lActive

      cFrame := oIO:Read( 2, 1000 )

      IF cFrame == NIL

         IF oIO:lConnClosed

            ld( "[WS] EXIT lConnClosed fd=" + hb_NToS( hb_socketGetFD( oIO:hSocket ) ) + " nIdle=" + hb_NToS( nIdle ) )
            EXIT

         ENDIF

         nIdle++

         IF lPingSent

            IF nIdle > 10

               ld( "WS: ping timeout - " + cIP )
               EXIT

            ENDIF

         ELSEIF nIdle >= 30
            ld( "[WS] SEND PING fd=" + hb_NToS( hb_socketGetFD( oIO:hSocket ) ) + " nIdle=" + hb_NToS( nIdle ) )

            IF ! _HixWSSendPing( oIO )

               EXIT

            ENDIF

            lPingSent := .T.
            nIdle     := 0

         ENDIF

         LOOP

      ENDIF

      nIdle    := 0
      lPingSent := .F.

      IF ! _HixWSDecodeFrame( oIO, cFrame, @nOpcode, @lFin, @cPayload )

         EXIT

      ENDIF

      DO CASE

         CASE nOpcode == WS_OP_CLOSE
            ld( "[WS] RECV CLOSE fd=" + hb_NToS( hb_socketGetFD( oIO:hSocket ) ) )
            _HixWSSendClose( oIO )
            ld( "[WS] SEND CLOSE fd=" + hb_NToS( hb_socketGetFD( oIO:hSocket ) ) )
            lActive := .F.
         CASE nOpcode == WS_OP_PING
            _HixWSSendPong( oIO, cPayload )
         CASE nOpcode == WS_OP_PONG
            ld( "WS: pong from " + cIP )
         CASE nOpcode == WS_OP_TEXT .OR. nOpcode == WS_OP_BINARY
            ld( "WS: data " + hb_NToS( Len( cPayload ) ) + "B from " + cIP )
            HIX_Metric( HIXM_BYTES_IN, Len( cPayload ) )

         IF bOnMessage != NIL

            Eval( bOnMessage, oConn, cPayload, nOpcode )

            ENDIF

         OTHERWISE
            ld( "WS: unknown opcode " + hb_NToS( nOpcode ) )

      ENDCASE

   ENDDO

RETURN NIL

// ============================================================
STATIC FUNCTION _HixWSDecodeFrame( oIO, cHeader2, nOpcode, lFin, cPayload )

   LOCAL b1, b2, nMaskBit, nPayloadLen, cExtLen, cMask, cRawPayload, i

   IF Len( cHeader2 ) < 2 ; RETURN .F. ; ENDIF

   b1 := Asc( SubStr( cHeader2, 1, 1 ) )
   b2 := Asc( SubStr( cHeader2, 2, 1 ) )

   lFin        := ( hb_bitAnd( b1, 0x80 ) != 0 )
   nOpcode     := hb_bitAnd( b1, 0x0F )
   nMaskBit    := hb_bitAnd( b2, 0x80 )
   nPayloadLen := hb_bitAnd( b2, 0x7F )

   IF nPayloadLen == 126

      cExtLen := oIO:Read( 2, 5000 )

      IF cExtLen == NIL ; RETURN .F. ; ENDIF

      nPayloadLen := Asc( SubStr( cExtLen, 1, 1 ) ) * 256 + Asc( SubStr( cExtLen, 2, 1 ) )
   ELSEIF nPayloadLen == 127
      ld( "WS: oversized frame" )
      RETURN .F.

   ENDIF

   IF nMaskBit != 0

      cMask := oIO:Read( 4, 5000 )

      IF cMask == NIL ; RETURN .F. ; ENDIF

   ENDIF

   IF nPayloadLen > 0

      IF nPayloadLen > HIX_WS_MAX_FRAME_SIZE

         ld( "WS: frame too large" )
         RETURN .F.

      ENDIF

      cRawPayload := oIO:Read( nPayloadLen, 10000 )

      IF cRawPayload == NIL ; RETURN .F. ; ENDIF

   ELSE
      cRawPayload := ""

   ENDIF

   cPayload := ""

   IF nMaskBit != 0 .AND. ! Empty( cRawPayload )

      FOR i := 1 TO Len( cRawPayload )

         cPayload += Chr( hb_bitXor( Asc( SubStr( cRawPayload, i, 1 ) ), ;
            Asc( SubStr( cMask, ( ( i - 1 ) % 4 ) + 1, 1 ) ) ) )

      NEXT

   ELSE
      cPayload := cRawPayload

   ENDIF

RETURN .T.

STATIC FUNCTION _HixWSBuildFrame( nOpcode, cPayload )

   LOCAL cFrame, nLen

   hb_default( @cPayload, "" )
   nLen   := Len( cPayload )
   cFrame := Chr( 0x80 + nOpcode )

   IF nLen < 126

      cFrame += Chr( nLen )
   ELSEIF nLen < 65536
      cFrame += Chr( 126 ) + Chr( Int( nLen / 256 ) ) + Chr( nLen % 256 )

   ENDIF

   cFrame += cPayload

RETURN cFrame

STATIC FUNCTION _HixWSSendPing( oIO )
RETURN oIO:Write( _HixWSBuildFrame( WS_OP_PING, "" ) )

STATIC FUNCTION _HixWSSendPong( oIO, cPayload )

   oIO:Write( _HixWSBuildFrame( WS_OP_PONG, cPayload ) )

RETURN NIL

STATIC FUNCTION _HixWSSendClose( oIO )

   oIO:Write( _HixWSBuildFrame( WS_OP_CLOSE, "" ) )

RETURN NIL

// Public wrapper so unit tests can verify frame byte encoding
FUNCTION HIX_WsBuildFrame( nOpcode, cPayload )
RETURN _HixWSBuildFrame( nOpcode, cPayload )
