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
   DATA oMutex  INIT NIL   // audit A2.03 — protege lClosed + oIO

   METHOD New( oIO, cIP )
   METHOD Send( cData )
   METHOD SendBinary( cData )
   METHOD Close()

ENDCLASS

METHOD New( oIO, cIP ) CLASS THixWsConn

   ::oIO    := oIO
   ::cIP    := cIP
   ::oMutex := hb_mutexCreate()

RETURN Self

// Audit A2.03 — lock-check-write bajo mutex evita race con Close.
METHOD Send( cData ) CLASS THixWsConn

   hb_mutexLock( ::oMutex )

   IF ! ::lClosed

      ::oIO:Write( _HixWSBuildFrame( WS_OP_TEXT, cData ) )

   ENDIF

   hb_mutexUnlock( ::oMutex )

RETURN Self

METHOD SendBinary( cData ) CLASS THixWsConn

   hb_mutexLock( ::oMutex )

   IF ! ::lClosed

      ::oIO:Write( _HixWSBuildFrame( WS_OP_BINARY, cData ) )

   ENDIF

   hb_mutexUnlock( ::oMutex )

RETURN Self

METHOD Close() CLASS THixWsConn

   hb_mutexLock( ::oMutex )

   IF ! ::lClosed

      ::lClosed := .T.
      ::oIO:Close()

   ENDIF

   hb_mutexUnlock( ::oMutex )

RETURN Self

// ============================================================
// Registro global de callbacks WS
// ============================================================

// Audit A2.05 — mutex creado eager al arranque del proceso via
// INIT PROCEDURE (main thread, antes de cualquier worker). Elimina el
// lazy init con doble-write race de las versiones anteriores.
INIT PROCEDURE _HixWsInit()

   shMutexCb := hb_mutexCreate()

RETURN

FUNCTION HIX_WsSetCallbacks( bConnect, bMessage, bClose )

   hb_mutexLock( shMutexCb )
   sbOnConnect := bConnect
   sbOnMessage := bMessage
   sbOnClose   := bClose
   hb_mutexUnlock( shMutexCb )

RETURN NIL

STATIC FUNCTION _HixWsCallbacks()

   LOCAL aR

   hb_mutexLock( shMutexCb )
   aR := { sbOnConnect, sbOnMessage, sbOnClose }
   hb_mutexUnlock( shMutexCb )

RETURN aR

// Public wrapper para tests A2.05 — snapshot atomico del estado de
// callbacks WS. Aisla la STATIC _HixWsCallbacks para pruebas unitarias.
FUNCTION HIX_WsGetCallbacks()
RETURN _HixWsCallbacks()

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

   LOCAL oConn, aCb, oError

   HIX_Metric( HIXM_ACTIVE_WS )

   IF ! _HixWSHandshake( oReq )

      oReq:oIO:Close()
      HIX_MetricDec( HIXM_ACTIVE_WS )
      RETURN NIL

   ENDIF

   oConn := THixWsConn():New( oReq:oIO, cIP )
   aCb   := _HixWsCallbacks()

   l( _( "WS_CONNECTED", cIP ) )

   // Audit A2.04 — HIX_WsSafeEval envuelve cada callback en TRY/CATCH:
   // un throw del handler de usuario NO debe abortar el cleanup
   // (Close + MetricDec). Sin esto, un fallo en bOnConnect deja el
   // socket colgado y active_ws envenenado.
   HIX_WsSafeEval( aCb[ 1 ], { oConn }, "bOnConnect", cIP )

   // [B1.W3] TRY/CATCH garantiza bOnClose + MetricDec incluso si
   // hb_socketGetFD(NIL) u otra excepción aborta el frame loop.
   TRY
      _HixWSFrameLoop( oConn, aCb[ 2 ] )
   CATCH oError
      le( "WS frame loop exception [" + cIP + "]: " + oError:description )
   END

   l( _( "WS_DISCONNECTED", cIP ) )

   HIX_WsSafeEval( aCb[ 3 ], { oConn }, "bOnClose", cIP )

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
   LOCAL lActive      := .T.
   LOCAL oIO          := oConn:oIO
   LOCAL cIP          := oConn:cIP
   LOCAL nIdle        := 0
   LOCAL lPingSent    := .F.
   LOCAL tFrame
   // [B1.W6.2] estado de fragmentación — RFC 6455 §5.4
   LOCAL nFragOpcode := 0     // 0 = no fragmentando; WS_OP_TEXT/BINARY si activo
   LOCAL cFragBuffer := ""
   // [B1.W6.3] leer ping_interval_s / ping_timeout_s de pool_ws en config
   LOCAL hPoolWs      := HIX_GetConfig( "pool_ws" )
   LOCAL nPingInterval := hb_HGetDef( hPoolWs, "ping_interval_s", 30 )
   LOCAL nPingTimeout  := hb_HGetDef( hPoolWs, "ping_timeout_s",  10 )

   ld( "[WS] CONNECT fd=" + hb_NToS( iif( oIO:hSocket != NIL, hb_socketGetFD( oIO:hSocket ), -1 ) ) + " ip=" + cIP )

   DO WHILE lActive

      cFrame := oIO:Read( 2, 1000 )

      IF cFrame == NIL

         IF oIO:lConnClosed

            ld( "[WS] EXIT lConnClosed fd=" + hb_NToS( iif( oIO:hSocket != NIL, hb_socketGetFD( oIO:hSocket ), -1 ) ) + " nIdle=" + hb_NToS( nIdle ) )
            EXIT

         ENDIF

         nIdle++

         IF lPingSent

            IF nIdle > nPingTimeout

               ld( "WS: ping timeout - " + cIP )
               EXIT

            ENDIF

         ELSEIF nIdle >= nPingInterval
            ld( "[WS] SEND PING fd=" + hb_NToS( iif( oIO:hSocket != NIL, hb_socketGetFD( oIO:hSocket ), -1 ) ) + " nIdle=" + hb_NToS( nIdle ) )

            IF ! _HixWSSendPing( oConn )

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
            // [B1.W6.2] frames de control NO pueden fragmentarse (FIN debe ser 1)
            IF ! lFin
               ld( "WS: fragmented control frame (CLOSE) — protocol error" )
               _HixWSSendClose( oConn )
               lActive := .F.
               LOOP
            ENDIF
            ld( "[WS] RECV CLOSE fd=" + hb_NToS( iif( oIO:hSocket != NIL, hb_socketGetFD( oIO:hSocket ), -1 ) ) )
            _HixWSSendClose( oConn )
            ld( "[WS] SEND CLOSE fd=" + hb_NToS( iif( oIO:hSocket != NIL, hb_socketGetFD( oIO:hSocket ), -1 ) ) )
            lActive := .F.
         CASE nOpcode == WS_OP_PING
            IF ! lFin
               ld( "WS: fragmented control frame (PING) — protocol error" )
               _HixWSSendClose( oConn )
               lActive := .F.
               LOOP
            ENDIF
            _HixWSSendPong( oConn, cPayload )
         CASE nOpcode == WS_OP_PONG
            IF ! lFin
               ld( "WS: fragmented control frame (PONG) — protocol error" )
               _HixWSSendClose( oConn )
               lActive := .F.
               LOOP
            ENDIF
            ld( "WS: pong from " + cIP )
         CASE nOpcode == WS_OP_TEXT .OR. nOpcode == WS_OP_BINARY
            // [B1.W6.2] nuevo mensaje: no puede llegar mientras hay fragmentación abierta
            IF nFragOpcode != 0
               ld( "WS: new data frame while fragmenting — protocol error" )
               _HixWSSendClose( oConn )
               lActive := .F.
               LOOP
            ENDIF
            IF lFin
               ld( "WS: data " + hb_NToS( Len( cPayload ) ) + "B from " + cIP )
               HIX_Metric( HIXM_BYTES_IN, Len( cPayload ) )
               tFrame := hb_DateTime()
               HIX_WsSafeEval( bOnMessage, { oConn, cPayload, nOpcode }, "bOnMessage", cIP )
               HIX_MetricWsTiming( Int( ( hb_DateTime() - tFrame ) * 86400000 ) )
            ELSE
               // primer fragmento — abrir buffer
               nFragOpcode := nOpcode
               cFragBuffer := cPayload
               HIX_Metric( HIXM_BYTES_IN, Len( cPayload ) )
            ENDIF
         CASE nOpcode == WS_OP_CONTINUATION
            // [B1.W6.2] continuación sólo válida tras un data frame FIN=0
            IF nFragOpcode == 0
               ld( "WS: continuation without initial frame — protocol error" )
               _HixWSSendClose( oConn )
               lActive := .F.
               LOOP
            ENDIF
            IF Len( cFragBuffer ) + Len( cPayload ) > HIX_WS_MAX_FRAME_SIZE
               ld( "WS: fragmented message exceeds max size — rechazado" )
               _HixWSSendClose( oConn )
               lActive := .F.
               LOOP
            ENDIF
            cFragBuffer += cPayload
            HIX_Metric( HIXM_BYTES_IN, Len( cPayload ) )
            IF lFin
               ld( "WS: reassembled " + hb_NToS( Len( cFragBuffer ) ) + "B from " + cIP )
               tFrame := hb_DateTime()
               HIX_WsSafeEval( bOnMessage, { oConn, cFragBuffer, nFragOpcode }, "bOnMessage", cIP )
               HIX_MetricWsTiming( Int( ( hb_DateTime() - tFrame ) * 86400000 ) )
               nFragOpcode := 0
               cFragBuffer := ""
            ENDIF
         OTHERWISE
            ld( "WS: unknown opcode " + hb_NToS( nOpcode ) )
            _HixWSSendClose( oConn )
            lActive := .F.

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
      // [B1.W6.1] leer los 8 bytes de longitud extendida — RFC 6455 §5.2
      cExtLen := oIO:Read( 8, 5000 )
      IF cExtLen == NIL ; RETURN .F. ; ENDIF
      // Soportamos hasta 2^32-1 (4 GB); los 4 bytes altos deben ser 0
      IF Asc( SubStr( cExtLen, 1, 1 ) ) != 0 .OR. ;
         Asc( SubStr( cExtLen, 2, 1 ) ) != 0 .OR. ;
         Asc( SubStr( cExtLen, 3, 1 ) ) != 0 .OR. ;
         Asc( SubStr( cExtLen, 4, 1 ) ) != 0
         ld( "WS: frame length > 4 GB — rechazado" )
         RETURN .F.
      ENDIF
      nPayloadLen := Asc( SubStr( cExtLen, 5, 1 ) ) * 16777216 + ;
                     Asc( SubStr( cExtLen, 6, 1 ) ) * 65536    + ;
                     Asc( SubStr( cExtLen, 7, 1 ) ) * 256      + ;
                     Asc( SubStr( cExtLen, 8, 1 ) )

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

// [B1.W6.2] wrappers públicos para tests: permiten alimentar frames simulados
// al bucle real sin abrir socket. También expone build de frame client-side
// (con máscara) para que los tests puedan generar tráfico de entrada válido.
FUNCTION HIX_WSTestRunFrameLoop( oConn, bOnMessage )
RETURN _HixWSFrameLoop( oConn, bOnMessage )

FUNCTION HIX_WSTestBuildClientFrame( nOpcode, lFin, cPayload )
   LOCAL cFrame, nLen, b1, cMask, i, c
   hb_default( @cPayload, "" )
   hb_default( @lFin, .T. )
   nLen := Len( cPayload )
   b1   := iif( lFin, 0x80, 0x00 ) + hb_bitAnd( nOpcode, 0x0F )
   cFrame := Chr( b1 )
   // MASK bit + length (cliente SIEMPRE enmascara — RFC 6455 §5.3)
   IF nLen < 126
      cFrame += Chr( 0x80 + nLen )
   ELSEIF nLen < 65536
      cFrame += Chr( 0x80 + 126 ) + Chr( Int( nLen / 256 ) ) + Chr( nLen % 256 )
   ELSE
      cFrame += Chr( 0x80 + 127 ) + ;
         Chr(0) + Chr(0) + Chr(0) + Chr(0) + ;
         Chr( Int( nLen / 16777216 ) % 256 ) + ;
         Chr( Int( nLen / 65536    ) % 256 ) + ;
         Chr( Int( nLen / 256      ) % 256 ) + ;
         Chr(       nLen              % 256 )
   ENDIF
   // máscara determinista (test-only) para poder reproducir bit a bit
   cMask := Chr( 0xA1 ) + Chr( 0xB2 ) + Chr( 0xC3 ) + Chr( 0xD4 )
   cFrame += cMask
   FOR i := 1 TO nLen
      c := hb_bitXor( Asc( SubStr( cPayload, i, 1 ) ), Asc( SubStr( cMask, ( ( i - 1 ) % 4 ) + 1, 1 ) ) )
      cFrame += Chr( c )
   NEXT
RETURN cFrame

STATIC FUNCTION _HixWSBuildFrame( nOpcode, cPayload )

   LOCAL cFrame, nLen

   hb_default( @cPayload, "" )
   nLen   := Len( cPayload )
   cFrame := Chr( 0x80 + nOpcode )

   IF nLen < 126

      cFrame += Chr( nLen )
   ELSEIF nLen < 65536
      cFrame += Chr( 126 ) + Chr( Int( nLen / 256 ) ) + Chr( nLen % 256 )

   ELSE
      // [B1.W6.1] payload >= 65536 — código 127 + 8 bytes big-endian (RFC 6455 §5.2)
      cFrame += Chr( 127 ) + ;
         Chr(0) + Chr(0) + Chr(0) + Chr(0) + ;
         Chr( Int( nLen / 16777216 ) % 256 ) + ;
         Chr( Int( nLen / 65536    ) % 256 ) + ;
         Chr( Int( nLen / 256      ) % 256 ) + ;
         Chr(       nLen              % 256 )

   ENDIF

   cFrame += cPayload

RETURN cFrame

// [B1.W1] frames de control bajo oConn:oMutex — simétrico a Send/Close (A2.03)
STATIC FUNCTION _HixWSSendPing( oConn )
   LOCAL lOk := .F.
   hb_mutexLock( oConn:oMutex )
   IF ! oConn:lClosed
      lOk := oConn:oIO:Write( _HixWSBuildFrame( WS_OP_PING, "" ) )
   ENDIF
   hb_mutexUnlock( oConn:oMutex )
RETURN lOk

STATIC FUNCTION _HixWSSendPong( oConn, cPayload )
   hb_mutexLock( oConn:oMutex )
   IF ! oConn:lClosed
      oConn:oIO:Write( _HixWSBuildFrame( WS_OP_PONG, cPayload ) )
   ENDIF
   hb_mutexUnlock( oConn:oMutex )
RETURN NIL

STATIC FUNCTION _HixWSSendClose( oConn )
   hb_mutexLock( oConn:oMutex )
   IF ! oConn:lClosed
      oConn:oIO:Write( _HixWSBuildFrame( WS_OP_CLOSE, "" ) )
   ENDIF
   hb_mutexUnlock( oConn:oMutex )
RETURN NIL

// Public wrapper so unit tests can verify frame byte encoding
FUNCTION HIX_WsBuildFrame( nOpcode, cPayload )
RETURN _HixWSBuildFrame( nOpcode, cPayload )

// ============================================================
// Audit A2.04 — envuelve un callback WS en TRY/CATCH.
// Un throw del handler de usuario NO debe abortar el cleanup
// (Close + MetricDec) ni romper el frame loop.
//   bCb   : codeblock del handler (o NIL — no-op).
//   aArgs : array de argumentos a pasar al codeblock.
//   cKind : etiqueta para el log ("bOnConnect"/"bOnMessage"/"bOnClose").
//   cIP   : IP del peer, para el log.
// Retorna .T. si el eval terminó limpio; .F. si CATCH atrapó excepción.
// ============================================================
FUNCTION HIX_WsSafeEval( bCb, aArgs, cKind, cIP )

   LOCAL oError

   IF bCb == NIL

      RETURN .T.

   ENDIF

   TRY

      DO CASE
      CASE Len( aArgs ) == 1
         Eval( bCb, aArgs[ 1 ] )
      CASE Len( aArgs ) == 2
         Eval( bCb, aArgs[ 1 ], aArgs[ 2 ] )
      CASE Len( aArgs ) == 3
         Eval( bCb, aArgs[ 1 ], aArgs[ 2 ], aArgs[ 3 ] )
      OTHERWISE
         Eval( bCb )
      ENDCASE

   CATCH oError

      le( "WS " + cKind + " error [" + cIP + "]: " + oError:description )
      HIX_Metric( HIXM_WS_CB_ERRORS )
      RETURN .F.

   END

RETURN .T.
