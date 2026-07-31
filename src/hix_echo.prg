/*-----------------------------------------------------------
  File ......: hix_echo.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-02
  Description: Output buffer (UWrite/USetMime/USetStatus) linked to the
               active request. Falls back to thread-static when no HTTP
               request is active.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

THREAD STATIC s_cBuffer
THREAD STATIC s_cMime
THREAD STATIC s_cStatus

// ------------------------------------------------------------
// HIX_Echo — acumula valores en el buffer del request activo.
// ------------------------------------------------------------
FUNCTION HIX_Echo( ... )

   LOCAL aP, i, oReq

   oReq := HIX_GetRequest()
   aP   := hb_AParams()

   IF oReq != NIL

      FOR i := 1 TO Len( aP )

         oReq:cEchoBuffer += UStr( aP[ i ] )

      NEXT

   ELSE
   
      hb_default( @s_cBuffer, "" )

      FOR i := 1 TO Len( aP )

         s_cBuffer += UStr( aP[ i ] )

      NEXT

   ENDIF

RETURN NIL

// ------------------------------------------------------------
// HIX_SetMime / HIX_GetMime
// ------------------------------------------------------------
FUNCTION HIX_SetMime( cMime )

   LOCAL oReq

   hb_default( @cMime, "html" )
   oReq := HIX_GetRequest()

   IF oReq != NIL

      oReq:cResponseMime := cMime
      
   ELSE
   
      s_cMime := cMime

   ENDIF

RETURN NIL

FUNCTION HIX_GetMime()

   LOCAL oReq

   oReq := HIX_GetRequest()

   IF oReq != NIL

      RETURN oReq:cResponseMime

   ENDIF

   hb_default( @s_cMime, "html" )

RETURN s_cMime

// ------------------------------------------------------------
// HIX_SetStatus / HIX_GetStatus
// ------------------------------------------------------------
FUNCTION HIX_SetStatus( nStatus )

   LOCAL oReq

   hb_default( @nStatus, 200 )
   oReq := HIX_GetRequest()

   IF oReq != NIL

      oReq:nResponseStatus := nStatus
      
   ELSE
   
      s_cStatus := nStatus

   ENDIF

RETURN NIL

FUNCTION HIX_GetStatus()

   LOCAL oReq

   oReq := HIX_GetRequest()

   IF oReq != NIL

      RETURN oReq:nResponseStatus

   ENDIF

   hb_default( @s_cStatus, 200 )

RETURN s_cStatus

// ------------------------------------------------------------
// HIX_EchoFlush — envia el buffer acumulado via oReq:Respond()
// y limpia el buffer.
// ------------------------------------------------------------
FUNCTION HIX_EchoFlush( oReq )

   LOCAL cOut, oR

   oR := iif( oReq != NIL, oReq, HIX_GetRequest() )

   IF oR != NIL

      cOut         := oR:cEchoBuffer
      oR:cEchoBuffer := ""      
      
   ELSE
   
      hb_default( @s_cBuffer, "" )
      cOut      := s_cBuffer
      s_cBuffer := ""

   ENDIF

   IF ! Empty( cOut ) .AND. oR != NIL

      oR:Respond( cOut, 200, "html" )

   ENDIF

RETURN cOut

// ------------------------------------------------------------
// HIX_EchoGet — retorna el contenido actual del buffer.
// ------------------------------------------------------------
FUNCTION HIX_EchoGet()

   LOCAL oReq

   oReq := HIX_GetRequest()

   IF oReq != NIL

      RETURN oReq:cEchoBuffer

   ENDIF

   hb_default( @s_cBuffer, "" )

RETURN s_cBuffer

// ------------------------------------------------------------
// HIX_EchoClear — limpia buffer, mime y status.
// Llamado por el dispatcher antes y despues de ejecutar cada .prg/.hrb.
// ------------------------------------------------------------
FUNCTION HIX_EchoClear()

   LOCAL oReq

   oReq := HIX_GetRequest()

   IF oReq != NIL

      oReq:cEchoBuffer     := ""
      oReq:cResponseMime   := "html"
      // No pisar nResponseStatus: el worker HTTP lo lee tras el dispatch
      // (HIX_AnomalyRecord). Cada peticion arranca con INIT 200 en el
      // nuevo THixRequest, y el status real se ajusta via HIX_SetStatus /
      // Respond antes de emitir la respuesta.

   ELSE
   
      s_cBuffer := ""
      s_cMime   := "html"
      s_cStatus := 200

   ENDIF

RETURN NIL

// ------------------------------------------------------------
