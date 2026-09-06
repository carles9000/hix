/*-----------------------------------------------------------
  File ......: hix_worker_http.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: HTTP worker — handles keep-alive loop, reads request,
               dispatches to router.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_WORKER_HTTP
#INCLUDE "hix_logger.ch"

FUNCTION HIX_WorkerHTTP( aJob )

   LOCAL oIO, cIP
   LOCAL nReqs      := 0
   LOCAL lKeepAlive := .T.

   // Path SSL: el accept loop pasó el socket raw; hacemos el handshake aquí
   // para no bloquear el accept loop durante el apretón de manos TLS.

   IF Len( aJob ) >= 3 .AND. HB_ISOBJECT( aJob[ 3 ] )

      cIP := aJob[ 2 ]
      oIO := aJob[ 3 ]:CreateIO( aJob[ 1 ] )

      IF oIO:hSSLSession == NIL

         ld( "SSL handshake failed from " + cIP )
         oIO:Close()
         RETURN NIL

      ENDIF

   ELSE
      oIO := aJob[ 1 ]
      cIP := aJob[ 2 ]

   ENDIF

   HIX_Metric( HIXM_ACTIVE_HTTP )

   DO WHILE lKeepAlive

      // Bail out immediately on shutdown so hb_threadJoin in
      // pool:Stop() can return. Without this, a keep-alive worker
      // keeps servicing polls from the client indefinitely and
      // never checks the pool's stop flag.

      IF ! HIX_ServerIsRunning()

         EXIT

      ENDIF

      nReqs++

      IF nReqs >= 100

         lKeepAlive := .F.

      ENDIF

      IF ! _HixHTTPProcessOne( oIO, cIP, @lKeepAlive )

         EXIT

      ENDIF

   ENDDO

   oIO:Close()
   HIX_MetricDec( HIXM_ACTIVE_HTTP )

RETURN NIL

// ============================================================
STATIC FUNCTION _HixHTTPProcessOne( oIO, cIP, lKeepAlive )

   LOCAL oReq, oError, bHandler
   LOCAL tBefore, nMs

   oReq := THixRequest():New( oIO, cIP, HIX_IsProxied() )

   IF ! oReq:Read()

      IF oReq:nReadError == HIX_REQ_ERR_BADREQ

         HIX_ResponseRaw( oIO, hb_jsonEncode( { "error" => _( 'ERR_BAD_REQUEST' ) } ), "json", 400, .F. )

      ENDIF

      RETURN .F.

   ENDIF

   lKeepAlive := oReq:lKeepAlive

   IF ! _HixHostAllowed( oReq:Header( "host", "" ) )

      HIX_ResponseRaw( oIO, hb_jsonEncode( { "error" => "Invalid Host" } ), "json", 400, .F. )
      lKeepAlive := .F.
      RETURN .F.

   ENDIF

   // WSS: WebSocket upgrade en conexión SSL (el peek no actuó)

   IF oIO:lUseSSL .AND. Lower( oReq:Header( "upgrade" ) ) == "websocket"

      lKeepAlive := .F.
      HIX_HandleWSUpgrade( oReq, cIP )
      RETURN .F.

   ENDIF

   tBefore := hb_DateTime()

   TRY

      HIX_RouteDispatch( oReq )
   CATCH oError
      le( "Handler error [" + oReq:cPath + "]: " + oError:Description + ' (' + oError:operation + ')'  )
      HIX_Metric( HIXM_ERRORS )
      bHandler := HIX_GetErrorHandler()

      TRY

         IF bHandler != NIL

            Eval( bHandler, oError, oReq )
         ELSE
            HIX_ShowError( oError, oReq )

         ENDIF

      CATCH
         oReq:Respond( { "error" => _( 'ERR_INTERNAL_SERVER_ERROR' ) }, 500 )

      END

   END

   // Drain any unread request body before recycling the keep-alive
   // connection. Handlers may skip UBody()/UJson() (e.g. they only
   // care about query params); those unread bytes would become garbage
   // at the front of the next request on the same socket → 400 Bad
   // Request from _HixHTTPProcessOne on the following iteration.
   // ReadBody is idempotent (cached in ::cBody), so this is a no-op if
   // the handler already consumed it.

   IF oReq:lKeepAlive .AND. ( oReq:cMethod $ "POST,PUT,PATCH" )

      oReq:ReadBody()

   ENDIF

   nMs := Int( ( hb_DateTime() - tBefore ) * 86400000 )
   HIX_MetricTiming( nMs, oReq:cPath )

   HIX_AnomalyRecord( cIP, oReq:nResponseStatus )

   lKeepAlive := oReq:lKeepAlive
   HIX_SetContext( NIL )

RETURN .T.

// ============================================================
// _HixHostAllowed — valida Host header contra server.allowed_hosts.
// Lista vacía o no configurada => acepta todo (backward compat).
// Formato de la lista: entradas separadas por coma o espacio.
// El puerto del Host header se descarta antes de comparar.
// Se admite "*" como comodín global y wildcards prefijo tipo
// "*.example.com".
// ============================================================
STATIC FUNCTION _HixHostAllowed( cHost )

   LOCAL cAllowed, aList, cItem, cHostLower, cItemLower, cSuffix

   cAllowed := AllTrim( UConfig( "server", "allowed_hosts", "" ) )

   IF Empty( cAllowed )

      RETURN .T.

   ENDIF

   cHostLower := Lower( AllTrim( hb_defaultValue( cHost, "" ) ) )

   IF ( "]" $ cHostLower ) .AND. Left( cHostLower, 1 ) == "["

      cHostLower := SubStr( cHostLower, 1, At( "]", cHostLower ) )
   ELSEIF ":" $ cHostLower

      cHostLower := SubStr( cHostLower, 1, At( ":", cHostLower ) - 1 )

   ENDIF

   aList := hb_ATokens( StrTran( cAllowed, ",", " " ), " " )

   FOR EACH cItem IN aList

      cItemLower := Lower( AllTrim( cItem ) )

      IF Empty( cItemLower )

         LOOP

      ENDIF

      IF cItemLower == "*" .OR. cItemLower == cHostLower

         RETURN .T.

      ENDIF

      IF Left( cItemLower, 2 ) == "*."

         cSuffix := SubStr( cItemLower, 2 )

         IF Right( cHostLower, Len( cSuffix ) ) == cSuffix

            RETURN .T.

         ENDIF

      ENDIF

   NEXT

RETURN .F.
