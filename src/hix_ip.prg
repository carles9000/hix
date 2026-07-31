/*-----------------------------------------------------------
  File ......: hix_ip.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-28
  Description: Real client IP detection — supports reverse proxy,
               Cloudflare Tunnel, IPv4, IPv6.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
FUNCTION HIX_GetClientIP( oReq )

   LOCAL aHeaders := { ;
      "cf-connecting-ip", ;
      "x-forwarded-for", ;
      "x-real-ip", ;
      "client-ip" ;
      }
   LOCAL nI, cValue, aForward, cIp

   IF oReq:lProxied

      RETURN oReq:RealIP()

   ENDIF

   FOR nI := 1 TO Len( aHeaders )

      cValue := AllTrim( oReq:Header( aHeaders[ nI ], "" ) )

      IF Empty( cValue )

         LOOP

      ENDIF

      IF aHeaders[ nI ] == "x-forwarded-for"

         // Cadena de proxies: "client, proxy1, proxy2" — primera IP publica
         aForward := hb_ATokens( cValue, "," )

         FOR EACH cIp IN aForward

            cIp := AllTrim( cIp )

            IF HIX_ValidIP( cIp ) .AND. HIX_IsPublicIP( cIp )

               RETURN cIp

            ENDIF

         NEXT

         // Ninguna publica en la cadena — probar siguiente header
         LOOP

      ENDIF

      // Headers directos: un solo valor
      cIp := cValue

      IF HIX_ValidIP( cIp ) .AND. HIX_IsPublicIP( cIp )

         RETURN cIp

      ENDIF

   NEXT

   // Fallback: IP de conexion TCP (puede ser privada en entornos locales)

RETURN oReq:cIP

// ------------------------------------------------------------
// Valida formato: IPv4 o IPv6
// ------------------------------------------------------------
FUNCTION HIX_ValidIP( cIP )

   LOCAL lValid := .F.

   IF Empty( cIP )

      RETURN .F.

   ENDIF

   IF ":" $ cIP

      lValid := _HixValidIPv6( cIP )
   ELSE
      lValid := _HixValidIPv4( cIP )

   ENDIF

RETURN lValid

// ------------------------------------------------------------
// Comprueba si la IP es publica (no privada/local/reservada)
// ------------------------------------------------------------
FUNCTION HIX_IsPublicIP( cIP )

   LOCAL lPublic := .F.

   IF ! HIX_ValidIP( cIP )

      RETURN .F.

   ENDIF

   IF ":" $ cIP

      lPublic := _HixIsPublicIPv6( cIP )
   ELSE
      lPublic := _HixIsPublicIPv4( cIP )

   ENDIF

RETURN lPublic

// ============================================================
// Funciones internas
// ============================================================

STATIC FUNCTION _HixValidIPv4( cIP )

   LOCAL cPatron := "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"

   IF Empty( cIP )

      RETURN .F.

   ENDIF

RETURN hb_RegExMatch( cPatron, cIP )

STATIC FUNCTION _HixValidIPv6( cIP )

   LOCAL cFull, cComp, cMapped

   IF Empty( cIP )

      RETURN .F.

   ENDIF

   cFull   := "^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$"
   cComp   := "^(([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:))$"
   cMapped := "^::ffff:(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"

RETURN hb_RegExMatch( cFull, cIP ) .OR. ;
      hb_RegExMatch( cComp, cIP ) .OR. ;
      hb_RegExMatch( cMapped, Lower( cIP ) )

// ------------------------------------------------------------
// IPv4: excluye loopback, privadas RFC1918, CGNAT, link-local,
// benchmark, TEST-NET, multicast y reserved
// ------------------------------------------------------------
STATIC FUNCTION _HixIsPublicIPv4( cIP )

   LOCAL aParts, nOct1, nOct2, nOct3

   IF ! _HixValidIPv4( cIP )

      RETURN .F.

   ENDIF

   aParts := hb_ATokens( cIP, "." )

   IF Len( aParts ) != 4

      RETURN .F.

   ENDIF

   nOct1 := Val( aParts[ 1 ] )
   nOct2 := Val( aParts[ 2 ] )
   nOct3 := Val( aParts[ 3 ] )

   IF nOct1 == 0   ;  RETURN .F.  ; ENDIF   // 0.0.0.0/8

   IF nOct1 == 127 ;  RETURN .F.  ; ENDIF   // loopback

   IF nOct1 == 10  ;  RETURN .F.  ; ENDIF   // RFC1918 10/8

   // RFC1918 172.16-31/12

   IF nOct1 == 172 .AND. nOct2 >= 16 .AND. nOct2 <= 31

      RETURN .F.

   ENDIF

   // RFC1918 192.168/16

   IF nOct1 == 192 .AND. nOct2 == 168

      RETURN .F.

   ENDIF

   // Link-local 169.254/16

   IF nOct1 == 169 .AND. nOct2 == 254

      RETURN .F.

   ENDIF

   // CGNAT RFC6598 100.64-127/10

   IF nOct1 == 100 .AND. nOct2 >= 64 .AND. nOct2 <= 127

      RETURN .F.

   ENDIF

   // Benchmark RFC2544 198.18-19/15

   IF nOct1 == 198 .AND. ( nOct2 == 18 .OR. nOct2 == 19 )

      RETURN .F.

   ENDIF

   // TEST-NET (documentacion)

   IF ( nOct1 == 192 .AND. nOct2 == 0   .AND. nOct3 == 0   ) .OR. ;
         ( nOct1 == 198 .AND. nOct2 == 51  .AND. nOct3 == 100 ) .OR. ;
         ( nOct1 == 203 .AND. nOct2 == 0   .AND. nOct3 == 113 )

      RETURN .F.

   ENDIF

   // Multicast (224/4) y reserved (240/4)

   IF nOct1 >= 224

      RETURN .F.

   ENDIF

RETURN .T.

// ------------------------------------------------------------
// IPv6: excluye loopback, link-local, ULA, multicast,
// unspecified y mapped-IPv4 privadas
// ------------------------------------------------------------
STATIC FUNCTION _HixIsPublicIPv6( cIP )

   LOCAL cL, cIPv4Part

   IF ! _HixValidIPv6( cIP )

      RETURN .F.

   ENDIF

   cL := Lower( AllTrim( cIP ) )

   IF cL == "::1"             ;  RETURN .F.  ; ENDIF   // loopback

   IF cL == "::"              ;  RETURN .F.  ; ENDIF   // unspecified

   IF Left( cL, 4 ) == "fe80" ; RETURN .F.  ; ENDIF   // link-local fe80::/10

   IF Left( cL, 2 ) == "fc"   ; RETURN .F.  ; ENDIF   // ULA fc00::/7

   IF Left( cL, 2 ) == "fd"   ; RETURN .F.  ; ENDIF   // ULA fd00::/7

   IF Left( cL, 2 ) == "ff"   ; RETURN .F.  ; ENDIF   // multicast ff00::/8

   // IPv4-mapped ::ffff:x.x.x.x — verificar parte IPv4

   IF "::ffff:" $ cL

      cIPv4Part := SubStr( cL, At( "::ffff:", cL ) + 7 )

      IF ! _HixIsPublicIPv4( cIPv4Part )

         RETURN .F.

      ENDIF

   ENDIF

RETURN .T.
