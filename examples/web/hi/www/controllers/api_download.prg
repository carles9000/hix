/*-----------------------------------------------------------
  File ......: api_download.prg
  Author.....: Charly 9000
  Created....: 2026-08-18
  Modified...: 2026-08-18
  Version....: 1.0.0
  Description: Synthetic payload generator for the /file-test
               screen. Streams a body of the requested size so
               the client can measure download throughput.
  Usage      : GET /api/download?mb=<size>[&mime=bin|txt]
  Notes      : mime=bin -> application/octet-stream, never gzipped
                           (HIX_GzipShouldCompress rejects it), so
                           the measured rate is the real wire rate.
               mime=txt -> text/plain, compressed when the client
                           sends Accept-Encoding: gzip.
               Size is capped at 50 MB.
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL nMb   := Val( UGet( 'mb', '1' ) )
   LOCAL cKind := Lower( UGet( 'mime', 'bin' ) )
   LOCAL cData, cName

   IF nMb <= 0
      nMb := 1
   ENDIF

   nMb := Min( nMb, 50 )

   IF ! cKind == 'txt'
      cKind := 'bin'
   ENDIF

   cName := 'payload.' + cKind

   // 32-byte seed * 32 = 1 KB block, replicated to the requested size
   cData := Replicate( Replicate( 'HIX-PAYLOAD-0123456789ABCDEF-XYZ', 32 ), nMb * 1024 )

RETURN USend( cData, 200, cKind, ;
              { 'Content-Disposition' => 'attachment; filename="' + cName + '"', ;
                'Cache-Control'       => 'no-store' } )
