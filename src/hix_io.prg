/*-----------------------------------------------------------
  File ......: hix_io.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-23
  Description: THixIO — per-connection read/write channel with optional
               SSL support.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_IO
#INCLUDE "hix_logger.ch"
#INCLUDE "hbssl.ch"

// ============================================================
// THixSocket — contexto SSL a nivel servidor
// ============================================================
CLASS THixSocket

   DATA lUseSSL    INIT .F.
   DATA cCertFile  INIT ""
   DATA cKeyFile   INIT ""
   DATA hSSLCtx    INIT NIL

   METHOD New()
   METHOD CreateIO( hSocket )

ENDCLASS

METHOD New() CLASS THixSocket

   LOCAL hSrv    := HIX_GetConfig( "server" )
   LOCAL cCerts  := hb_DirSepAdd( UConfig( "paths", "certs", "certs" ) )

   ::lUseSSL   := hSrv[ "ssl" ]
   ::cCertFile := cCerts + hSrv[ "cert_public" ]
   ::cKeyFile  := cCerts + hSrv[ "cert_private" ]

   IF ::lUseSSL

      ::hSSLCtx := _HixSSLCtxInit( ::cCertFile, ::cKeyFile )

   ENDIF

RETURN Self

METHOD CreateIO( hSocket ) CLASS THixSocket

   LOCAL oIO := THixIO():New( hSocket )

   oIO:lUseSSL := ::lUseSSL

   IF ::lUseSSL .AND. ::hSSLCtx != NIL

      oIO:hSSLSession := _HixSSLAccept( ::hSSLCtx, hSocket )

   ENDIF

RETURN oIO

// ============================================================
// THixIO — canal por conexión
// ============================================================
CLASS THixIO

   DATA hSocket
   DATA lUseSSL     INIT .F.
   DATA hSSLSession INIT NIL
   DATA lConnClosed INIT .F.

   METHOD New( hSocket )
   METHOD Read( nBytes, nTimeout )
   METHOD ReadHeaders( nTimeout )
   METHOD Write( cData, nTimeout )
   METHOD WriteChunk( cData )
   METHOD WriteChunkEnd()
   METHOD Close()

ENDCLASS

METHOD New( hSocket ) CLASS THixIO

   ::hSocket := hSocket

RETURN Self

// ------------------------------------------------------------
// Read — leer nBytes del socket o sesión SSL
// ------------------------------------------------------------
METHOD Read( nBytes, nTimeout ) CLASS THixIO

   LOCAL cBuf, nRead, lErr := .F.

   hb_default( @nTimeout, HIX_DEFAULT_READ_TIMEOUT )

   IF ::lUseSSL .AND. ::hSSLSession != NIL

      cBuf := _HixSSLRead( ::hSSLSession, ::hSocket, nBytes, nTimeout, @lErr )

      IF lErr

         ::lConnClosed := .T.

      ENDIF

      RETURN cBuf

   ENDIF

   cBuf  := Space( nBytes )
   nRead := hb_socketRecv( ::hSocket, @cBuf, nBytes, 0, nTimeout )

   IF nRead < 0

      ::lConnClosed := .T.
      RETURN NIL
   ELSEIF nRead == 0
      RETURN NIL

   ENDIF

RETURN Left( cBuf, nRead )

// ------------------------------------------------------------
// ReadHeaders — leer hasta CRLFCRLF (headers HTTP completos)
// ------------------------------------------------------------
METHOD ReadHeaders( nTimeout ) CLASS THixIO

   LOCAL cHeaders := ""
   LOCAL cBuf, nRead

   hb_default( @nTimeout, HIX_DEFAULT_READ_TIMEOUT )

   DO WHILE Len( cHeaders ) < HIX_MAX_HEADER_SIZE

      IF ::lUseSSL .AND. ::hSSLSession != NIL

         cBuf := _HixSSLRead( ::hSSLSession, ::hSocket, 1024, nTimeout )

         IF cBuf == NIL

            EXIT

         ENDIF

      ELSE
         cBuf  := Space( 1024 )
         nRead := hb_socketRecv( ::hSocket, @cBuf, 1024, 0, nTimeout )

         IF nRead <= 0

            EXIT

         ENDIF

         cBuf := Left( cBuf, nRead )

      ENDIF

      cHeaders += cBuf

      IF Chr( 13 ) + Chr( 10 ) + Chr( 13 ) + Chr( 10 ) $ cHeaders

         RETURN cHeaders

      ENDIF

   ENDDO

RETURN NIL

// ------------------------------------------------------------
// Write — enviar todos los bytes con reintento
// ------------------------------------------------------------
METHOD Write( cData, nTimeout ) CLASS THixIO

   LOCAL nTotal, nSent, nResult, nRetry

   hb_default( @nTimeout, HIX_DEFAULT_READ_TIMEOUT )

   IF Empty( cData )

      RETURN .T.

   ENDIF

   IF ::lUseSSL .AND. ::hSSLSession != NIL

      RETURN _HixSSLWrite( ::hSSLSession, ::hSocket, cData )

   ENDIF

   nTotal := Len( cData )
   nSent  := 0
   nRetry := 0

   DO WHILE nSent < nTotal .AND. nRetry < 5

      nResult := hb_socketSend( ::hSocket, SubStr( cData, nSent + 1 ), ;
         nTotal - nSent, 0, nTimeout )

      IF nResult <= 0

         nRetry++
         LOOP

      ENDIF

      nSent  += nResult
      nRetry := 0

   ENDDO

   IF nSent < nTotal

      RETURN .F.

   ENDIF

   HIX_Metric( HIXM_BYTES_OUT, nTotal )

RETURN .T.

// ------------------------------------------------------------
// WriteChunk — envía un trozo en formato chunked (RFC 7230)
// ------------------------------------------------------------
METHOD WriteChunk( cData ) CLASS THixIO

   IF Empty( cData ) ; RETURN .T. ; ENDIF

RETURN ::Write( hb_NumToHex( Len( cData ) ) + HIX_CRLF + cData + HIX_CRLF )

// ------------------------------------------------------------
// WriteChunkEnd — envía el chunk terminador 0\r\n\r\n
// ------------------------------------------------------------
METHOD WriteChunkEnd() CLASS THixIO
RETURN ::Write( "0" + HIX_CRLF + HIX_CRLF )

// ------------------------------------------------------------
// Close — drain + cierre limpio
// ------------------------------------------------------------
METHOD Close() CLASS THixIO

   LOCAL cDrain

   IF ::lUseSSL .AND. ::hSSLSession != NIL

      _HixSSLFree( ::hSSLSession )
      ::hSSLSession := NIL

   ENDIF

   IF ! Empty( ::hSocket )

      hb_socketShutdown( ::hSocket, HB_SOCKET_SHUT_WR )
      cDrain := Space( 256 )

      DO WHILE hb_socketRecv( ::hSocket, @cDrain, 256, 0, 100 ) > 0

      ENDDO

      hb_socketClose( ::hSocket )
      ::hSocket := NIL

   ENDIF

RETURN NIL


// ============================================================
// SSL — implementación real via hbssl
// ============================================================

// ------------------------------------------------------------
// _HixSSLCtxInit — crear contexto SSL servidor
// ------------------------------------------------------------
STATIC FUNCTION _HixSSLCtxInit( cCertFile, cKeyFile )

   LOCAL hCtx

   IF ! File( cKeyFile )

      le( "SSL: private key not found: " + cKeyFile )
      RETURN NIL

   ENDIF

   IF ! File( cCertFile )

      le( "SSL: certificate not found: " + cCertFile )
      RETURN NIL

   ENDIF

   SSL_INIT()

   DO WHILE RAND_STATUS() != 1

      RAND_add( Str( hb_Random(), 18, 15 ) + Str( hb_MilliSeconds(), 20 ), 1 )

   ENDDO

   hCtx := SSL_CTX_NEW( HB_SSL_CTX_NEW_METHOD_SSLV23_SERVER )
   SSL_CTX_SET_OPTIONS( hCtx, hb_bitOr( HB_SSL_OP_NO_TLSv1, HB_SSL_OP_NO_TLSv1_1 ) )

   IF SSL_CTX_USE_PRIVATEKEY_FILE( hCtx, cKeyFile, HB_SSL_FILETYPE_PEM ) != 1

      le( "SSL: invalid private key file" )
      RETURN NIL

   ENDIF

   IF SSL_CTX_USE_CERTIFICATE_FILE( hCtx, cCertFile, HB_SSL_FILETYPE_PEM ) != 1

      le( "SSL: invalid certificate file" )
      RETURN NIL

   ENDIF

RETURN hCtx

// ------------------------------------------------------------
// _HixSSLAccept — handshake TLS con timeout absoluto ~30s
// ------------------------------------------------------------
STATIC FUNCTION _HixSSLAccept( hCtx, hSocket )

   LOCAL hSSL, nErr, nStart

   hSSL := SSL_NEW( hCtx )
   SSL_SET_MODE( hSSL, hb_bitOr( SSL_GET_MODE( hSSL ), HB_SSL_MODE_ENABLE_PARTIAL_WRITE ) )
   hb_socketSetBlockingIO( hSocket, .F. )
   SSL_SET_FD( hSSL, hb_socketGetFD( hSocket ) )

   nStart := hb_MilliSeconds()

   DO WHILE .T.

      nErr := _MySslAccept( hSSL, hSocket, 1000 )

      IF nErr == 0

         EXIT
      ELSEIF nErr == HB_SOCKET_ERR_TIMEOUT

         IF hb_MilliSeconds() - nStart > 5000

            le( "SSL: handshake timeout" )
            RETURN NIL

         ENDIF

         LOOP
      ELSE
         le( "SSL: handshake error " + hb_ntos( nErr ) )
         RETURN NIL

      ENDIF

   ENDDO

RETURN hSSL

// ------------------------------------------------------------
// _HixSSLRead — leer nBytes con reintentos WANT_READ/WANT_WRITE
// ------------------------------------------------------------
STATIC FUNCTION _HixSSLRead( hSSL, hSocket, nBytes, nMaxMs, lConnError )

   LOCAL cBuf       := Space( nBytes )
   LOCAL nLen, nErr := 0, nStart, nIterStart, nFastLoops := 0

   hb_default( @nMaxMs,      5000 )
   hb_default( @lConnError, .F.  )
   nStart := hb_MilliSeconds()

   DO WHILE .T.

      nIterStart := hb_MilliSeconds()
      nLen := _MySslRead( hSSL, hSocket, @cBuf, 1000, @nErr )

      IF nLen > 0

         RETURN Left( cBuf, nLen )
      ELSEIF nErr == HB_SOCKET_ERR_TIMEOUT

         IF hb_MilliSeconds() - nStart > nMaxMs

            RETURN NIL

         ENDIF

         // Iteración rápida (<50ms) = selectRead retornó inmediatamente = socket cerrado

         IF hb_MilliSeconds() - nIterStart < 50

            nFastLoops++

            IF nFastLoops > 5

               lw( "[SSL] fast-loop fd=" + hb_NToS( hb_socketGetFD( hSocket ) ) + " lConnError" )
               lConnError := .T.
               RETURN NIL

            ENDIF

         ELSE
            nFastLoops := 0

         ENDIF

         LOOP
      ELSE
         lConnError := .T.
         RETURN NIL

      ENDIF

   ENDDO

RETURN NIL

// ------------------------------------------------------------
// _HixSSLWrite — escribir cData con reintentos WANT_READ/WANT_WRITE
// ------------------------------------------------------------
STATIC FUNCTION _HixSSLWrite( hSSL, hSocket, cData )

   LOCAL nTotal := Len( cData )
   LOCAL nSent  := 0
   LOCAL nLen, nErr := 0, cChunk, nStart

   nStart := hb_MilliSeconds()

   DO WHILE nSent < nTotal

      cChunk := SubStr( cData, nSent + 1 )
      nLen   := _MySslWrite( hSSL, hSocket, cChunk, 1000, @nErr )

      IF nLen > 0

         nSent += nLen
         nStart := hb_MilliSeconds()
      ELSEIF nLen == 0

         IF hb_MilliSeconds() - nStart > 10000

            RETURN .F.

         ENDIF

         LOOP
      ELSE
         RETURN .F.

      ENDIF

   ENDDO

RETURN .T.

// ------------------------------------------------------------
// _HixSSLFree — shutdown limpio
// ------------------------------------------------------------
STATIC FUNCTION _HixSSLFree( hSSL )

   SSL_SHUTDOWN( hSSL )
   HB_SYMBOL_UNUSED( hSSL )   // GC llama SSL_free al salir de scope

RETURN NIL

// ------------------------------------------------------------
// Auxiliares de bajo nivel (adaptadas de uhttpd2/umain.prg)
// ------------------------------------------------------------
STATIC FUNCTION _MySslRead( hSSL, hSocket, cBuf, nTimeout, nError )

   LOCAL nErr, nLen

   nLen := SSL_READ( hSSL, @cBuf )

   IF HB_ISNUMERIC( nLen ) .AND. nLen > 0

      RETURN nLen

   ENDIF

   nErr := SSL_GET_ERROR( hSSL, iif( HB_ISNUMERIC( nLen ), nLen, 0 ) )

   DO CASE

      CASE nErr == HB_SSL_ERROR_WANT_READ .OR. nErr == HB_SSL_ERROR_NONE
         nErr := hb_socketSelectRead( hSocket, nTimeout )

      IF nErr < 0

         nError := hb_socketGetError()
      ELSE
         nError := HB_SOCKET_ERR_TIMEOUT

         ENDIF

      CASE nErr == HB_SSL_ERROR_WANT_WRITE
         nErr := hb_socketSelectWrite( hSocket, nTimeout )

      IF nErr < 0

         nError := hb_socketGetError()
      ELSE
         nError := HB_SOCKET_ERR_TIMEOUT

         ENDIF

      OTHERWISE
         nError := 1000 + nErr

   ENDCASE

RETURN -1

STATIC FUNCTION _MySslWrite( hSSL, hSocket, cBuf, nTimeout, nError )

   LOCAL nErr, nLen

   nLen := SSL_WRITE( hSSL, cBuf )

   IF nLen <= 0

      nErr := SSL_GET_ERROR( hSSL, nLen )

      IF nErr == HB_SSL_ERROR_WANT_READ

         nErr := hb_socketSelectRead( hSocket, nTimeout )

         IF nErr < 0

            nError := hb_socketGetError()
            RETURN -1
         ELSE
            RETURN 0

         ENDIF

      ELSEIF nErr == HB_SSL_ERROR_WANT_WRITE
         nErr := hb_socketSelectWrite( hSocket, nTimeout )

         IF nErr < 0

            nError := hb_socketGetError()
            RETURN -1
         ELSE
            RETURN 0

         ENDIF

      ELSE
         nError := 1000 + nErr
         RETURN -1

      ENDIF

   ENDIF

RETURN nLen

STATIC FUNCTION _MySslAccept( hSSL, hSocket, nTimeout )

   LOCAL nErr

   nErr := SSL_ACCEPT( hSSL )

   IF nErr > 0

      RETURN 0
   ELSEIF nErr < 0
      nErr := SSL_GET_ERROR( hSSL, nErr )

      IF nErr == HB_SSL_ERROR_WANT_READ

         nErr := hb_socketSelectRead( hSocket, nTimeout )

         IF nErr < 0

            nErr := hb_socketGetError()
         ELSE
            nErr := HB_SOCKET_ERR_TIMEOUT

         ENDIF

      ELSEIF nErr == HB_SSL_ERROR_WANT_WRITE
         nErr := hb_socketSelectWrite( hSocket, nTimeout )

         IF nErr < 0

            nErr := hb_socketGetError()
         ELSE
            nErr := HB_SOCKET_ERR_TIMEOUT

         ENDIF

      ELSE
         nErr := 1000 + nErr

      ENDIF

   ELSE
      nErr := SSL_GET_ERROR( hSSL, nErr )
      nErr := 1000 + nErr

   ENDIF

RETURN nErr
