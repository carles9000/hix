/*-----------------------------------------------------------
  File ......: hix_proxy.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-03
  Description: Reverse proxy support — trusted proxy detection (Apache,
               Nginx, Cloudflare), IP forwarding.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

STATIC saProxyFilter := NIL
STATIC slProxyActive := .F.

// Carga la lista de proxies de confianza (IPs/CIDRs separados por espacio).
// Llamar en _Init() antes de Start().
FUNCTION HIX_ProxyInit( cTrustedList )

   LOCAL aOut

   slProxyActive := .F.
   saProxyFilter := NIL

   IF Empty( cTrustedList )

      RETURN NIL

   ENDIF

   IF HIX_ParseFirewallFilter( cTrustedList, @aOut, .T. )

      saProxyFilter := aOut
      slProxyActive := .T.

   ENDIF

RETURN NIL

// .T. si cIP pertenece a la lista de proxies de confianza.
FUNCTION HIX_IsTrustedProxy( cIP )

   IF ! slProxyActive

      RETURN .F.

   ENDIF

RETURN HIX_IsIPInRanges( cIP, saProxyFilter )

// Parsea RFC 7239 Forwarded: header.
// Devuelve hash con keys "for", "proto", "host", "by", "port" (los presentes).
// Ejemplo: "for=192.168.1.1;proto=https;host=example.com"
FUNCTION HIX_ParseForwarded( cHeader )

   LOCAL hResult, cFirst, aParts, cPart, nEq, cKey, cVal
   LOCAL nClose, nColon, nColons, nI

   hResult := { => }

   IF Empty( cHeader )

      RETURN hResult

   ENDIF

   // Tomar el primer valor (izquierda = salto mas cercano al cliente)
   cFirst := AllTrim( hb_ATokens( cHeader, "," )[ 1 ] )

   FOR EACH cPart IN hb_ATokens( cFirst, ";" )

      cPart := AllTrim( cPart )
      nEq   := At( "=", cPart )

      IF nEq == 0

         LOOP

      ENDIF

      cKey := Lower( AllTrim( Left( cPart, nEq - 1 ) ) )
      cVal := AllTrim( SubStr( cPart, nEq + 1 ) )

      // Eliminar comillas externas

      IF Len( cVal ) >= 2 .AND. Left( cVal, 1 ) == '"' .AND. Right( cVal, 1 ) == '"'

         cVal := SubStr( cVal, 2, Len( cVal ) - 2 )

      ENDIF

      // Campo "for": limpiar brackets IPv6 y puerto opcional

      IF cKey == "for"

         IF Left( cVal, 1 ) == "["

            // IPv6: "[::1]" o "[::1]:port"
            nClose := At( "]", cVal )

            IF nClose > 0

               IF SubStr( cVal, nClose + 1, 1 ) == ":"

                  hResult[ "port" ] := SubStr( cVal, nClose + 2 )

               ENDIF

               cVal := SubStr( cVal, 2, nClose - 2 )

            ENDIF

         ELSEIF At( ":", cVal ) > 0
            // Contar dos puntos: si hay exactamente 1 es IPv4:puerto
            nColons := 0

            FOR nI := 1 TO Len( cVal )

               IF SubStr( cVal, nI, 1 ) == ":" ; nColons++; ENDIF

            NEXT

            IF nColons == 1

               nColon := At( ":", cVal )
               hResult[ "port" ] := SubStr( cVal, nColon + 1 )
               cVal := Left( cVal, nColon - 1 )

            ENDIF

         ENDIF

      ENDIF

      hResult[ cKey ] := cVal

   NEXT

RETURN hResult
