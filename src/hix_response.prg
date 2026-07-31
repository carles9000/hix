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

            cRaw += cKey + ": " + cVal + HIX_CRLF

         NEXT

      ELSE
         cRaw += cKey + ": " + hExtra[ cKey ] + HIX_CRLF

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

            cRaw += cKey + ": " + cVal + HIX_CRLF

         NEXT

      ELSE

         cRaw += cKey + ": " + hExtra[ cKey ] + HIX_CRLF

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
