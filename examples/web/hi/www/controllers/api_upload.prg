/*-----------------------------------------------------------
  File ......: api_upload.prg
  Author.....: Charly 9000
  Created....: 2026-08-18
  Modified...: 2026-08-18
  Version....: 1.0.0
  Description: Upload sink for the /file-test screen. Accepts
               both a raw binary body and a multipart form, and
               answers how many bytes actually arrived so the
               client can measure upload throughput.
  Usage      : POST /api/upload
               Content-Type: application/octet-stream  -> raw body
               Content-Type: multipart/form-data       -> parsed parts
  Notes      : Nothing is written to disk — this only measures the
               transfer. THixRequest:ReadBody() drops any body over
               HIX_MAX_BODY_SIZE (10 MB), so in that case declared
               is the announced Content-Length and received is 0.
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL nDeclared := UContentLength()
   LOCAL nReceived := 0
   LOCAL cKind     := 'raw'
   LOCAL aNames    := {}
   LOCAL aFiles, hFile

   IF UIsMultipart()

      cKind  := 'multipart'
      aFiles := UFiles()

      FOR EACH hFile IN aFiles

         IF ! Empty( hFile[ 'filename' ] )

            nReceived += hFile[ 'size' ]
            AAdd( aNames, hFile[ 'filename' ] )

         ENDIF

      NEXT

   ELSE
      nReceived := Len( UBody() )

   ENDIF

RETURN USendJson( { 'ok'       => ( nReceived > 0 ),  ;
                    'kind'     => cKind,              ;
                    'declared' => nDeclared,          ;
                    'received' => nReceived,          ;
                    'files'    => aNames,             ;
                    'time'     => Time()              } )
