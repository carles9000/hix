/*-----------------------------------------------------------
  File ......: hix_gzip.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-15
  Description: Gzip compression helpers for HTTP responses.
               Converts hb_Compress() zlib output (RFC 1950) to gzip (RFC 1952)
               by replacing the zlib header with the gzip header + crc32/isize.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_RESPONSE
#INCLUDE "hix_logger.ch"

// Compresses cData to RFC 1952 gzip binary string.
// Returns NIL on failure or empty input.
FUNCTION HIX_GzipCompress( cData )

   LOCAL cZlib, cDeflate, nCrc
   LOCAL oError

   IF Empty( cData )

      RETURN NIL

   ENDIF

   TRY

      cZlib := hb_Compress( cData )
   CATCH oError
      ld( "HIX_GzipCompress: " + oError:description )
      RETURN NIL

   END

   // hb_Compress output: [2-byte zlib header][deflate data][4-byte adler32]
   // Minimum valid zlib stream is 8 bytes (2 header + 2 deflate + 4 adler32)

   IF Empty( cZlib ) .OR. Len( cZlib ) < 8

      RETURN NIL

   ENDIF

   // Extract raw DEFLATE: strip 2-byte zlib header and 4-byte adler32 trailer
   cDeflate := SubStr( cZlib, 3, Len( cZlib ) - 6 )
   nCrc     := hb_CRC32( cData, 0 )

   // RFC 1952 gzip: [10-byte header][deflate][4-byte crc32 LE][4-byte isize LE]

RETURN _HixGzipHeader() + cDeflate + _HixU32LE( nCrc ) + _HixU32LE( Len( cData ) )

// Returns .T. if cMimeFull is a compressible text-based content type.
// Strips charset/boundary params before matching (e.g. "text/html; charset=utf-8").
FUNCTION HIX_GzipShouldCompress( cMimeFull )

   LOCAL cM

   cM := Lower( AllTrim( cMimeFull ) )

   IF ";" $ cM

      cM := AllTrim( hb_ATokens( cM, ";" )[ 1 ] )

   ENDIF

RETURN cM == "text/html"              .OR. ;
      cM == "text/plain"             .OR. ;
      cM == "text/css"               .OR. ;
      cM == "text/javascript"        .OR. ;
      cM == "text/xml"               .OR. ;
      cM == "application/json"       .OR. ;
      cM == "application/javascript" .OR. ;
      cM == "application/xml"        .OR. ;
      cM == "image/svg+xml"

// 10-byte RFC 1952 gzip member header.
// Fields: ID1=0x1f ID2=0x8b CM=8(DEFLATE) FLG=0 MTIME=0 XFL=0 OS=0xff(unknown)
STATIC FUNCTION _HixGzipHeader()
RETURN Chr( 31 ) + Chr( 139 ) + Chr( 8 ) + Chr( 0 ) + ;
      Chr( 0 )  + Chr( 0 )   + Chr( 0 ) + Chr( 0 ) + ;
      Chr( 0 )  + Chr( 255 )

// Encode n as a 4-byte little-endian unsigned 32-bit integer.
STATIC FUNCTION _HixU32LE( n )

   n := Int( n ) % 4294967296

   IF n < 0

      n += 4294967296

   ENDIF

RETURN hb_BChar(  n                   % 256 ) + ;
      hb_BChar( Int( n / 256 )        % 256 ) + ;
      hb_BChar( Int( n / 65536 )      % 256 ) + ;
      hb_BChar( Int( n / 16777216 )   % 256 )
