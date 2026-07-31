/*-----------------------------------------------------------
  File ......: hix_socket.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: Server-level socket utilities — protocol peek, connection
               setup, SSL context management.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_SOCKET
#INCLUDE "hix_logger.ch"

FUNCTION HIX_SocketInit()
RETURN NIL

// ============================================================
FUNCTION HIX_SocketConfigure( hConn )

   IF Empty( hConn )

      RETURN NIL

   ENDIF

   hb_socketSetNoDelay(   hConn, .T. )
   hb_socketSetKeepAlive( hConn, .T. )

RETURN NIL

// ============================================================
// Peek — leer sin consumir el buffer (MSG_PEEK)
// Necesario antes de crear THixIO para detectar el protocolo.
// ============================================================
FUNCTION HIX_SocketPeek( hConn, nBytes, nTimeoutMs )

   LOCAL cBuf, nRead

   hb_default( @nBytes,     HIX_DEFAULT_PEEK_BYTES   )
   hb_default( @nTimeoutMs, HIX_DEFAULT_PEEK_TIMEOUT )

   IF Empty( hConn )

      RETURN NIL

   ENDIF

   cBuf  := Space( nBytes )
   nRead := hb_socketRecv( hConn, @cBuf, nBytes, HB_SOCKET_MSG_PEEK, nTimeoutMs )

   IF nRead <= 0

      RETURN NIL

   ENDIF

RETURN Left( cBuf, nRead )

// ============================================================
// HIX_DetectProtocol — detectar tipo desde peek
// ============================================================
FUNCTION HIX_DetectProtocol( cPeek )

   LOCAL cLower

   IF Empty( cPeek )

      RETURN HIX_CONN_UNKNOWN

   ENDIF

   cLower := Lower( cPeek )

   IF HIX_TOKEN_WS_UPGRADE $ cLower  ; RETURN HIX_CONN_WS       ; ENDIF
   IF HIX_TOKEN_SSE_ACCEPT  $ cLower ; RETURN HIX_CONN_SSE      ; ENDIF
   IF HIX_TOKEN_LONGPOLL    $ cLower ; RETURN HIX_CONN_LONGPOLL ; ENDIF

   IF Upper( Left( cPeek, 3 ) ) $ HIX_HTTP_VERBS

      RETURN HIX_CONN_HTTP

   ENDIF

RETURN HIX_CONN_UNKNOWN
