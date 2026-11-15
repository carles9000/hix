/*-----------------------------------------------------------
  File ......: hix_response.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: HIX_ResponseRaw — low-level HTTP response writer
               (status, headers, body, keep-alive).
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_RESPONSE

#INCLUDE "hix_logger.ch"

// hExtra — hash opcional de cabeceras adicionales (e.g. {"ETag"=>"...", "Cache-Control"=>"..."})
FUNCTION HIX_ResponseRaw( oIO, xData, cMime, nStatus, lKeepAlive, hExtra )

   LOCAL cBody, cMimeFull, cRaw, cKey, cVal
   LOCAL oReq, cCompressed, cServerName

   hb_default( @cMime,      "json" )
   hb_default( @nStatus,    200    )
   hb_default( @lKeepAlive, .F.    )
   hb_default( @hExtra,     { => }   )

   nStatus := _HixHdrStatusClamp( nStatus )   // [A1.06]

   cMimeFull  := HIX_MimeExpand( cMime )

   cBody      := _HIXSerialize( xData, cMimeFull )

   // Gzip compression — only for non-empty compressible responses above the threshold
   oReq := HIX_GetRequest()

   IF UConfig( "server", "gzip", .F. ) .AND. ;
         nStatus != 204 .AND. nStatus != 304 .AND. ! Empty( cBody ) .AND. ;
         Len( cBody ) >= UConfig( "server", "gzip_min_size", 2048 ) .AND. ;
         HIX_GzipShouldCompress( cMimeFull ) .AND. ;
         oReq != NIL .AND. "gzip" $ Lower( oReq:Header( "accept-encoding", "" ) )

      cCompressed := HIX_GzipCompress( cBody )

      IF cCompressed != NIL

         cBody                        := cCompressed
         hExtra[ "Content-Encoding" ] := "gzip"
         hExtra[ "Vary" ]             := "Accept-Encoding"

      ENDIF

   ENDIF

   cRaw := "HTTP/1.1 " + hb_NToS( nStatus ) + " " + HIX_StatusText( nStatus )  + HIX_CRLF + ;
      "Content-Type: "   + cMimeFull                                      + HIX_CRLF + ;
      "Content-Length: " + hb_NToS( Len( cBody ) )                        + HIX_CRLF + ;
      "Connection: "     + iif( lKeepAlive, "keep-alive", "close" )       + HIX_CRLF

   cServerName := AllTrim( UConfig( "server", "name", "HIX" ) )
   IF ! Empty( cServerName )
      cRaw += "Server: " + cServerName + HIX_CRLF
   ENDIF

   FOR EACH cKey IN hb_HKeys( hExtra )

      IF ValType( hExtra[ cKey ] ) == "A"

         FOR EACH cVal IN hExtra[ cKey ]

            IF _HixHdrSanitize( cKey, cVal )       // [A1.05]
               cRaw += cKey + ": " + cVal + HIX_CRLF
            ENDIF

         NEXT

      ELSE
         IF _HixHdrSanitize( cKey, hExtra[ cKey ] )   // [A1.05]
            cRaw += cKey + ": " + hExtra[ cKey ] + HIX_CRLF
         ENDIF

      ENDIF

   NEXT

   cRaw += HIX_CRLF + cBody

   HIX_Metric( HIXM_REQUESTS )

   IF nStatus >= 400

      HIX_Metric( HIXM_ERRORS )

   ENDIF

RETURN oIO:Write( cRaw )

// ============================================================
// HIX_ResponseStreamStart — envía solo cabeceras para chunked streaming.
// No incluye Content-Length. El body lo envía el caller en trozos.
// ============================================================
FUNCTION HIX_ResponseStreamStart( oIO, cMime, nStatus, lKeepAlive, hExtra )

   LOCAL cRaw, cKey, cVal, cServerName

   hb_default( @cMime,      "html" )
   hb_default( @nStatus,    200    )
   hb_default( @lKeepAlive, .F.    )
   hb_default( @hExtra,     { => }   )

   nStatus := _HixHdrStatusClamp( nStatus )   // [A1.06]

   cRaw := "HTTP/1.1 " + hb_NToS( nStatus ) + " " + HIX_StatusText( nStatus )  + HIX_CRLF + ;
      "Content-Type: "       + HIX_MimeExpand( cMime )                     + HIX_CRLF + ;
      "Transfer-Encoding: chunked"                                          + HIX_CRLF + ;
      "Connection: "         + iif( lKeepAlive, "keep-alive", "close" )   + HIX_CRLF

   cServerName := AllTrim( UConfig( "server", "name", "HIX" ) )
   IF ! Empty( cServerName )
      cRaw += "Server: " + cServerName + HIX_CRLF
   ENDIF

   FOR EACH cKey IN hb_HKeys( hExtra )

      IF ValType( hExtra[ cKey ] ) == "A"

         FOR EACH cVal IN hExtra[ cKey ]

            IF _HixHdrSanitize( cKey, cVal )         // [A1.05]
               cRaw += cKey + ": " + cVal + HIX_CRLF
            ENDIF

         NEXT

      ELSE

         IF _HixHdrSanitize( cKey, hExtra[ cKey ] )   // [A1.05]
            cRaw += cKey + ": " + hExtra[ cKey ] + HIX_CRLF
         ENDIF

      ENDIF

   NEXT

   cRaw += HIX_CRLF

   HIX_Metric( HIXM_REQUESTS )

RETURN oIO:Write( cRaw )

// ============================================================

STATIC FUNCTION _HIXSerialize( xData, cMime )  // UStr() ???

   DO CASE

      CASE ValType( xData ) == "C" ; RETURN xData
      CASE ValType( xData ) == "N" ; RETURN hb_NToS( xData )
      CASE ValType( xData ) == "L" ; RETURN iif( xData, "true", "false" )
      CASE ValType( xData ) == "H" ; RETURN hb_jsonEncode( xData )
      CASE ValType( xData ) == "A" ; RETURN hb_jsonEncode( xData )
      CASE ValType( xData ) == "D" ; RETURN DToC( xData )
      CASE ValType( xData ) == "M" ; RETURN xData
      CASE ValType( xData ) == "U"
         RETURN iif( "json" $ cMime, "{}", "" )

   ENDCASE

RETURN ""

FUNCTION HIX_MimeExpand( cShort )

   DO CASE

// Most common - Web & API formats
      CASE cShort == "html" ; RETURN "text/html; charset=utf-8"
      CASE cShort == "css"  ; RETURN "text/css"
      CASE cShort == "js"   ; RETURN "application/javascript"
      CASE cShort == "json" ; RETURN "application/json"
      CASE cShort == "txt"  ; RETURN "text/plain; charset=utf-8"
      CASE cShort == "xml"  ; RETURN "application/xml"

// Images (very frequent)
      CASE cShort == "jpg"  ; RETURN "image/jpeg"
      CASE cShort == "jpeg" ; RETURN "image/jpeg"
      CASE cShort == "png"  ; RETURN "image/png"
      CASE cShort == "gif"  ; RETURN "image/gif"
      CASE cShort == "svg"  ; RETURN "image/svg+xml"
      CASE cShort == "webp" ; RETURN "image/webp"
      CASE cShort == "ico"  ; RETURN "image/x-icon"

// Fonts
      CASE cShort == "woff" ; RETURN "font/woff"
      CASE cShort == "woff2"; RETURN "font/woff2"
      CASE cShort == "ttf"  ; RETURN "font/ttf"
      CASE cShort == "otf"  ; RETURN "font/otf"

// Documents
      CASE cShort == "pdf"  ; RETURN "application/pdf"
      CASE cShort == "doc"  ; RETURN "application/msword"
      CASE cShort == "docx" ; RETURN "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      CASE cShort == "xls"  ; RETURN "application/vnd.ms-excel"
      CASE cShort == "xlsx" ; RETURN "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      CASE cShort == "ppt"  ; RETURN "application/vnd.ms-powerpoint"
      CASE cShort == "pptx" ; RETURN "application/vnd.openxmlformats-officedocument.presentationml.presentation"

// Audio/Video
      CASE cShort == "mp3"  ; RETURN "audio/mpeg"
      CASE cShort == "mp4"  ; RETURN "video/mp4"
      CASE cShort == "webm" ; RETURN "video/webm"
      CASE cShort == "ogg"  ; RETURN "audio/ogg"
      CASE cShort == "wav"  ; RETURN "audio/wav"

// Archives
      CASE cShort == "zip"  ; RETURN "application/zip"
      CASE cShort == "gz"   ; RETURN "application/gzip"
      CASE cShort == "tar"  ; RETURN "application/x-tar"
      CASE cShort == "7z"   ; RETURN "application/x-7z-compressed"

// Binary fallback
      CASE cShort == "bin"  ; RETURN "application/octet-stream"
      CASE cShort == "exe"  ; RETURN "application/vnd.microsoft.portable-executable"

// Legacy/Text formats
      CASE cShort == "text" ; RETURN "text/plain; charset=utf-8"
      CASE cShort == "csv"  ; RETURN "text/csv"
      CASE cShort == "rtf"  ; RETURN "application/rtf"

   ENDCASE

RETURN cShort

// ============================================================
// [A1.05] _HixHdrSanitize — filtra cabeceras HTTP contra CRLF
//   injection y nombres inválidos.
//
//   Retorna .T. si (cName, cVal) puede emitirse tal cual, .F.
//   si debe descartarse. En caso de rechazo emite un warn con
//   la clave y una versión escapada del valor para diagnóstico.
//
//   Reglas:
//     - Nombre: sólo `[A-Za-z0-9-]`. Cualquier otro carácter
//       (espacio, `:`, `\r`, `\n`) → skip.
//     - Nombre vacío → skip.
//     - Valor: NO contener `\r`, `\n`, `\0`. Cualquier presencia
//       → skip toda la cabecera (política defensiva: log +
//       descartar, no `StrTran` silencioso, para dejar rastro
//       del intento).
//     - Valor con tipo no-string → skip.
// ============================================================
STATIC FUNCTION _HixHdrSanitize( cName, cVal )

   LOCAL nI, cCh

   IF Empty( cName ) .OR. ValType( cName ) != "C"
      lw( "HDR_INJECT_NAME_INVALID: " + hb_ValToExp( cName ) )
      RETURN .F.
   ENDIF

   FOR nI := 1 TO Len( cName )
      cCh := SubStr( cName, nI, 1 )
      IF ! ( ( cCh >= "A" .AND. cCh <= "Z" ) .OR. ;
             ( cCh >= "a" .AND. cCh <= "z" ) .OR. ;
             ( cCh >= "0" .AND. cCh <= "9" ) .OR. ;
             cCh == "-" )
         lw( "HDR_INJECT_NAME_BADCHAR: " + cName )
         RETURN .F.
      ENDIF
   NEXT

   IF ValType( cVal ) != "C"
      lw( "HDR_INJECT_VAL_TYPE: " + cName + "=" + hb_ValToExp( cVal ) )
      RETURN .F.
   ENDIF

   IF Chr( 13 ) $ cVal .OR. Chr( 10 ) $ cVal .OR. Chr( 0 ) $ cVal
      lw( "HDR_INJECT_VAL_CRLF: " + cName + "=" + ;
          StrTran( StrTran( StrTran( cVal, Chr( 13 ), "\r" ), Chr( 10 ), "\n" ), Chr( 0 ), "\0" ) )
      RETURN .F.
   ENDIF

RETURN .T.

// Test hook: expone `_HixHdrSanitize` para tests unitarios.
FUNCTION HIX_HdrSanitize( cName, cVal )
RETURN _HixHdrSanitize( cName, cVal )

// ============================================================
// [A1.06] _HixHdrStatusClamp — normaliza el status code HTTP.
//
//   Rango válido RFC 7231: 100..599. Cualquier valor fuera de
//   rango, no-numérico o no-entero → 500 (con lw()).
//
//   `Int()` primero para tolerar decimales espurios (200.5 → 200
//   sigue siendo válido; 200.9 → 200, no 201, para no promocionar
//   accidentalmente el status).
// ============================================================
STATIC FUNCTION _HixHdrStatusClamp( nStatus )

   LOCAL nOrig

   IF ValType( nStatus ) != "N"
      lw( "HTTP_STATUS_TYPE: " + hb_ValToExp( nStatus ) + " -> 500" )
      RETURN 500
   ENDIF

   nOrig   := nStatus
   nStatus := Int( nStatus )

   IF nStatus < 100 .OR. nStatus > 599
      lw( "HTTP_STATUS_RANGE: " + hb_NToS( nOrig ) + " -> 500" )
      RETURN 500
   ENDIF

RETURN nStatus

// Test hook: expone `_HixHdrStatusClamp` para tests unitarios.
FUNCTION HIX_HdrStatusClamp( nStatus )
RETURN _HixHdrStatusClamp( nStatus )
