/*-----------------------------------------------------------
  File ......: hix_request.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-23
  Description: THixRequest — HTTP request parser (headers, body, multipart,
               query string, cookies).
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_REQUEST

#INCLUDE "hix_logger.ch"

// Request activo en el hilo actual (accesible desde PRG/HRB via HIX_GetRequest)
THREAD STATIC s_oCurrentReq := NIL

CLASS THixRequest

   // Canal de IO (lectura y escritura)
   DATA oIO
   DATA cIP

   // Request line
   DATA cMethod    INIT ""
   DATA cPath      INIT ""
   DATA cQuery     INIT ""
   DATA cProtocol  INIT ""

   // Headers y body
   DATA hParam        INIT { => }  // route params (:id, :id!)
   DATA hHeaders      INIT { => }
   DATA cBody         INIT NIL    // NIL = no leído aún
   DATA cBodyPre      INIT ""     // bytes del body pre-leídos con los headers
   DATA xJsonBody     INIT NIL    // NIL = no parseado aún
   DATA hFormBody     INIT NIL    // NIL = no parseado aún
   DATA hQueryParams  INIT NIL    // NIL = no parseado aún
   DATA hCookies      INIT NIL    // NIL = no parseado aún
   DATA aMultipart    INIT NIL    // NIL = no parseado aún

   // Keep-alive derivado de los headers
   DATA lKeepAlive    INIT .F.

   // Modo streaming chunked activo
   DATA lStreaming     INIT .F.

   // Modo proxied: resolver cIP desde X-Forwarded-For / X-Real-IP
   DATA lProxied      INIT .F.

   // Marca que la respuesta ya fue enviada (evita doble Respond desde PRG dinámico)
   DATA lResponded    INIT .F.

   // Buffer de salida acumulado por U*/HIX_Echo* (estado compartido entre hilos via referencia)
   DATA cEchoBuffer     INIT ""
   DATA cResponseMime   INIT "html"
   DATA nResponseStatus INIT 200

   // Datos resueltos del proxy inverso (sólo si lProxied y proxy de confianza)
   DATA cRealClientIP  INIT ""   // IP real del cliente
   DATA cProtoScheme   INIT ""   // "http" | "https"
   DATA cFwdHost       INIT ""   // Host original
   DATA cFwdPort       INIT ""   // Puerto original

   // Cabeceras extra para fusionar en cada Respond() — usado por MW (ej. CORS, Session)
   DATA hExtraHeaders INIT { => }

   // Datos de middleware accesibles desde controladores .prg (cross-thread via oReq)
   DATA hData         INIT { => }

   // Error de lectura: HIX_REQ_ERR_NONE | HIX_REQ_ERR_CLOSED | HIX_REQ_ERR_BADREQ
   DATA nReadError    INIT HIX_REQ_ERR_NONE

   METHOD New( oIO, cIP )
   METHOD Read()                              // Paso 1: leer oIO → parsea request line + headers
   METHOD ReadBody()                          // Paso 2: leer body raw (lazy, según Content-Length)
   METHOD JsonBody()                          // Body parseado como JSON → hash/array (lazy)
   METHOD FormBody()                          // Body parseado como form-urlencoded → hash (lazy)
   METHOD ContentType()                       // Valor del header Content-Type (lowercase)
   METHOD IsJson()                            // Content-Type es application/json
   METHOD IsForm()                            // Content-Type es application/x-www-form-urlencoded
   METHOD IsMultipart()                       // Content-Type es multipart/form-data
   METHOD MultipartBoundary()                 // Extrae boundary del Content-Type
   METHOD MultipartFiles()                    // Array de partes multipart (lazy, cacheado)
   METHOD Respond( xData, nStatus, cMime, hExtra )    // Atajo: envía respuesta HTTP
   METHOD Redirect( cUrl, nStatus )                   // Redirección HTTP 301/302 (AJAX-aware)
   METHOD IsAjax()                                    // .T. si X-Requested-With: XMLHttpRequest
   METHOD RespondStart( cMime, nStatus, hExtra )      // Inicia streaming chunked (envía headers)
   METHOD RespondChunk( cData )                       // Envía un trozo de datos
   METHOD RespondEnd()                                // Finaliza streaming (chunk 0\r\n\r\n)
   METHOD RespondStream( cMime, bBlock, nStatus, hExtra ) // RespondStart + bBlock(Self) + RespondEnd
   METHOD Header( cKey, xDef )                // Acceso normalizado a headers
   METHOD QueryParam( cKey, xDef )            // Acceso lazy a query string (URL-decoded)
   METHOD QueryParamsAll()                    // Hash completo de query params (lazy parse)
   METHOD Cookie( cName, xDef )               // Acceso lazy a cookies (Cookie: header)
   METHOD ContentLength()
   METHOD Scheme()      // "https" | "http" — desde Forwarded / X-Forwarded-Proto
   METHOD IsHttps()     // .T. si Scheme() == "https"
   METHOD RealHost()    // Host original — Forwarded host= / X-Forwarded-Host / Host:
   METHOD RealPort()    // Puerto original — Forwarded port= / X-Forwarded-Port
   METHOD RealIP()      // IP real respetando trusted proxy (vs cIP que es siempre TCP)

ENDCLASS

// ------------------------------------------------------------
METHOD New( oIO, cIP, lProxied ) CLASS THixRequest

   hb_default( @lProxied, .F. )
   ::oIO      := oIO
   ::cIP      := cIP
   ::lProxied := lProxied
   HB_HCaseMatch( ::hParam,   .F. )
   HB_HCaseMatch( ::hHeaders, .F. )
   HB_HCaseMatch( ::hData, .F. )

RETURN Self

// ------------------------------------------------------------
// Read — lee del canal IO y parsea request line + headers.
// Devuelve .F. si el canal falla o la request line es inválida.
// ------------------------------------------------------------
METHOD Read() CLASS THixRequest

   LOCAL cRaw, nEnd, cFirstLine, aParts, nQ, nCRLF2
   LOCAL aLines, cLine, nPos, nStart, cConn
   LOCAL cFwd, cReal, cFwdHeader, hFwd, aFwd, cCandidate

   cRaw := ::oIO:ReadHeaders()

   IF cRaw == NIL

      ::nReadError := HIX_REQ_ERR_CLOSED
      RETURN .F.

   ENDIF

   HIX_Metric( HIXM_BYTES_IN, Len( cRaw ) )

   // ---- Request line ----
   nEnd := At( HIX_CRLF, cRaw )

   IF nEnd == 0 ; nEnd := At( Chr( 10 ), cRaw ) ; ENDIF

   IF nEnd == 0 ; RETURN .F. ; ENDIF

   cFirstLine := Left( cRaw, nEnd - 1 )
   aParts     := hb_ATokens( AllTrim( cFirstLine ), " " )

   IF Len( aParts ) < 3

      ::nReadError := HIX_REQ_ERR_BADREQ
      RETURN .F.

   ENDIF

   ::cMethod   := Upper( AllTrim( aParts[ 1 ] ) )
   ::cPath     := AllTrim( aParts[ 2 ] )
   ::cProtocol := Upper( AllTrim( aParts[ 3 ] ) )

   nQ := At( "?", ::cPath )

   IF nQ > 0

      ::cQuery := SubStr( ::cPath, nQ + 1 )
      ::cPath  := Left( ::cPath, nQ - 1 )

   ENDIF

   // ---- Headers ----
   nStart := At( HIX_CRLF, cRaw )

   IF nStart > 0

      aLines := hb_ATokens( SubStr( cRaw, nStart + 2 ), Chr( 10 ) )

      FOR EACH cLine IN aLines

         cLine := StrTran( cLine, Chr( 13 ), "" )

         IF Empty( cLine )

            EXIT

         ENDIF

         nPos  := At( ":", cLine )

         IF nPos > 0

            ::hHeaders[ Lower( AllTrim( Left( cLine, nPos - 1 ) ) ) ] := ;
               AllTrim( SubStr( cLine, nPos + 1 ) )

         ENDIF

      NEXT

   ENDIF

   // ---- Keep-alive ----
   cConn := Lower( hb_HGetDef( ::hHeaders, "connection", "" ) )

   IF ::cProtocol == "HTTP/1.1"

      ::lKeepAlive := ( cConn != "close" )
   ELSE
      ::lKeepAlive := ( cConn == "keep-alive" )

   ENDIF

   IF ::lProxied .AND. HIX_IsTrustedProxy( ::cIP )

      // RFC 7239 Forwarded: tiene precedencia sobre X-Forwarded-*
      cFwdHeader := hb_HGetDef( ::hHeaders, "forwarded", "" )

      IF ! Empty( cFwdHeader )

         hFwd := HIX_ParseForwarded( cFwdHeader )

         IF hb_HHasKey( hFwd, "for"   ) ; ::cRealClientIP := hFwd[ "for"   ] ; ENDIF

         IF hb_HHasKey( hFwd, "proto" ) ; ::cProtoScheme  := hFwd[ "proto" ] ; ENDIF

         IF hb_HHasKey( hFwd, "host"  ) ; ::cFwdHost      := hFwd[ "host"  ] ; ENDIF

         IF hb_HHasKey( hFwd, "port"  ) ; ::cFwdPort      := hFwd[ "port"  ] ; ENDIF

      ELSE
         // Fallback: X-Forwarded-For — tomar primera IP no-proxy de la cadena
         cFwd := hb_HGetDef( ::hHeaders, "x-forwarded-for", "" )

         IF ! Empty( cFwd )

            aFwd := hb_ATokens( cFwd, "," )

            FOR EACH cCandidate IN aFwd

               cCandidate := AllTrim( cCandidate )

               IF ! HIX_IsTrustedProxy( cCandidate )

                  ::cRealClientIP := cCandidate
                  EXIT

               ENDIF

            NEXT

            IF Empty( ::cRealClientIP )

               ::cRealClientIP := AllTrim( aFwd[ 1 ] )

            ENDIF

         ELSE
            cReal := hb_HGetDef( ::hHeaders, "x-real-ip", "" )

            IF ! Empty( cReal ) ; ::cRealClientIP := AllTrim( cReal ) ; ENDIF

         ENDIF

         ::cProtoScheme := AllTrim( hb_HGetDef( ::hHeaders, "x-forwarded-proto", "" ) )
         ::cFwdHost     := AllTrim( hb_HGetDef( ::hHeaders, "x-forwarded-host",  "" ) )
         ::cFwdPort     := AllTrim( hb_HGetDef( ::hHeaders, "x-forwarded-port",  "" ) )

      ENDIF

   ENDIF

   // Extraer bytes del body que llegaron pegados a los headers (chunk unico)
   nCRLF2 := At( HIX_CRLF + HIX_CRLF, cRaw )

   IF nCRLF2 > 0

      ::cBodyPre := SubStr( cRaw, nCRLF2 + 4 )

   ENDIF

   ld( "REQ " + ::cMethod + " " + ::cPath + " [" + ::cIP + "]" )

RETURN .T.

// ------------------------------------------------------------
// ReadBody — lee el body del canal según Content-Length.
// Idempotente: si ya se leyó, devuelve el valor cacheado.
// ------------------------------------------------------------
METHOD ReadBody() CLASS THixRequest

   LOCAL nLen, cData, nRemain, cMore

   IF ::cBody != NIL

      RETURN ::cBody

   ENDIF

   nLen := ::ContentLength()

   IF nLen <= 0

      ::cBody := ""
      RETURN ::cBody

   ENDIF

   IF nLen > HIX_MAX_BODY_SIZE

      lw( _( "REQ_BODY_TOO_LARGE", hb_ntos( nLen ) ) )
      ::cBody := ""
      RETURN ::cBody

   ENDIF

   // Usar bytes pre-leídos junto con los headers (requests pequeños en un solo recv)
   cData   := ::cBodyPre
   nRemain := nLen - Len( cData )

   IF nRemain > 0

      cMore := ::oIO:Read( nRemain )
      cData += iif( cMore == NIL, "", cMore )
   ELSEIF nRemain < 0
      cData := Left( cData, nLen )

   ENDIF

   ::cBody := cData

   IF ! Empty( ::cBody )

      HIX_Metric( HIXM_BYTES_IN, Len( ::cBody ) )

   ENDIF

RETURN ::cBody

// ------------------------------------------------------------
// Respond — envía una respuesta HTTP usando este canal.
// Elimina la necesidad de PRIVATE hHIXConn/lHIXKeepAlive.
// ------------------------------------------------------------
METHOD Respond( xData, nStatus, cMime, hExtra ) CLASS THixRequest

   LOCAL hMerged, cValType, xTmp

   hb_default( @nStatus, 200  )
   hb_default( @hExtra,  { => } )
   // hb_default( @cMime,  UGetMime() )  // Charly hem de implementar el mime

   IF cMime == NIL

      cValType := ValType( xData )

      IF cValType == "H" .OR. cValType == "A"

         cMime := "json"
      ELSEIF HIX_WantsJson( Self )
         cMime := "json"
      ELSE
         cMime := "html"

      ENDIF

   ENDIF

   IF ! Empty( ::hExtraHeaders )

      hMerged := hb_HClone( ::hExtraHeaders )
      hb_HMerge( hMerged, hExtra )
      hExtra := hMerged

   ENDIF

   ::lResponded       := .T.
   ::nResponseStatus  := nStatus

   HIX_AccessLog( ::cIP, ::cMethod, ::cPath, ::cProtocol, nStatus )

RETURN HIX_ResponseRaw( ::oIO, xData, cMime, nStatus, ::lKeepAlive, hExtra )

METHOD Redirect( cUrl, nStatus ) CLASS THixRequest

   hb_default( @nStatus, 302 )

   IF ::IsAjax()

      ::Respond( { "redirect" => cUrl } )
   ELSE
      ::Respond( "", nStatus, "html", { "Location" => cUrl } )

   ENDIF

RETURN Self

METHOD IsAjax() CLASS THixRequest
RETURN Lower( ::Header( "x-requested-with", "" ) ) == "xmlhttprequest"

// ------------------------------------------------------------
METHOD RespondStart( cMime, nStatus, hExtra ) CLASS THixRequest

   LOCAL hMerged

   hb_default( @cMime,   "html" )
   hb_default( @nStatus, 200    )
   hb_default( @hExtra,  { => }   )

   IF ! Empty( ::hExtraHeaders )

      hMerged := hb_HClone( ::hExtraHeaders )
      hb_HMerge( hMerged, hExtra )
      hExtra := hMerged

   ENDIF

   ::lStreaming := .T.
   HIX_AccessLog( ::cIP, ::cMethod, ::cPath, ::cProtocol, nStatus )

RETURN HIX_ResponseStreamStart( ::oIO, cMime, nStatus, ::lKeepAlive, hExtra )

METHOD RespondChunk( cData ) CLASS THixRequest

RETURN ::oIO:WriteChunk( cData )

METHOD RespondEnd() CLASS THixRequest

   ::lStreaming  := .F.
   ::lResponded  := .T.

RETURN ::oIO:WriteChunkEnd()

METHOD RespondStream( cMime, bBlock, nStatus, hExtra ) CLASS THixRequest

   hb_default( @cMime,   "html" )
   hb_default( @nStatus, 200    )
   hb_default( @hExtra,  { => }   )
   ::RespondStart( cMime, nStatus, hExtra )
   Eval( bBlock, Self )
   ::RespondEnd()

RETURN Self

// ------------------------------------------------------------
METHOD Header( cKey, xDef ) CLASS THixRequest

   hb_default( @xDef, "" )

RETURN hb_HGetDef( ::hHeaders, Lower( cKey ), xDef )

METHOD ContentLength() CLASS THixRequest
RETURN Val( ::Header( "content-length", "0" ) )

METHOD ContentType() CLASS THixRequest
RETURN Lower( ::Header( "content-type", "" ) )

METHOD IsJson() CLASS THixRequest
RETURN "application/json" $ ::ContentType()

METHOD IsForm() CLASS THixRequest
RETURN "application/x-www-form-urlencoded" $ ::ContentType()

// ------------------------------------------------------------
// JsonBody — parsea el body como JSON. Lazy + cacheado.
// Devuelve hash, array, o hash vacío si el body es inválido.
// ------------------------------------------------------------
METHOD JsonBody() CLASS THixRequest

   LOCAL cRaw, xData

   IF ::xJsonBody != NIL

      RETURN ::xJsonBody

   ENDIF

   cRaw := ::ReadBody()

   IF Empty( cRaw )

      ::xJsonBody := { => }
      RETURN ::xJsonBody

   ENDIF

   xData := hb_jsonDecode( cRaw )

   IF xData == NIL

      lw( _( "REQ_JSON_INVALID", Left( cRaw, 80 ) ) )
      ::xJsonBody := { => }
   ELSE
      ::xJsonBody := xData

   ENDIF

RETURN ::xJsonBody

// ------------------------------------------------------------
// FormBody — parsea body application/x-www-form-urlencoded.
// Lazy + cacheado. Devuelve hash de pares key→value.
// ------------------------------------------------------------
METHOD FormBody() CLASS THixRequest

   LOCAL cRaw, aPairs, cPair, nEq

   IF ::hFormBody != NIL

      RETURN ::hFormBody

   ENDIF

   ::hFormBody := { => }

   cRaw := ::ReadBody()

   IF ! ::IsForm() .AND. ! ::IsMultipart()

      // Fallback: tolerate missing Content-Type when body has key=value pairs.
      // Skip if body is explicitly JSON (Content-Type: application/json).
      IF ::IsJson() .OR. At( "=", cRaw ) == 0

         RETURN ::hFormBody

      ENDIF

   ENDIF

   IF ! Empty( cRaw )

      aPairs := hb_ATokens( cRaw, "&" )

      FOR EACH cPair IN aPairs

         nEq := At( "=", cPair )

         IF nEq > 0

            ::hFormBody[ HIX_UrlDecode( AllTrim( Left( cPair, nEq - 1 ) ) ) ] := ;
               HIX_UrlDecode( AllTrim( SubStr( cPair, nEq + 1 ) ) )
         ELSEIF ! Empty( AllTrim( cPair ) )
            ::hFormBody[ HIX_UrlDecode( AllTrim( cPair ) ) ] := ""

         ENDIF

      NEXT

   ENDIF

RETURN ::hFormBody

// ------------------------------------------------------------
// QueryParam — parsea ::cQuery la primera vez (lazy, URL-decoded).
// ------------------------------------------------------------
METHOD QueryParam( cKey, xDef ) CLASS THixRequest

   LOCAL aPairs, cPair, nEq

   hb_default( @xDef, "" )

   IF ::hQueryParams == NIL

      ::hQueryParams := { => }

      IF ! Empty( ::cQuery )

         aPairs := hb_ATokens( ::cQuery, "&" )

         FOR EACH cPair IN aPairs

            nEq := At( "=", cPair )

            IF nEq > 0

               ::hQueryParams[ Lower( HIX_UrlDecode( AllTrim( Left( cPair, nEq - 1 ) ) ) ) ] := ;
                  HIX_UrlDecode( AllTrim( SubStr( cPair, nEq + 1 ) ) )

            ENDIF

         NEXT

      ENDIF

   ENDIF

RETURN hb_HGetDef( ::hQueryParams, Lower( cKey ), xDef )

METHOD QueryParamsAll() CLASS THixRequest

   ::QueryParam( "", "" )   // fuerza el parse lazy

RETURN hb_HClone( ::hQueryParams )

// ------------------------------------------------------------
// Cookie — parsea "Cookie: a=1; b=2" lazy. Devuelve xDef si no existe.
// ------------------------------------------------------------
METHOD Cookie( cName, xDef ) CLASS THixRequest

   LOCAL cRaw, aPairs, cPair, nEq

   hb_default( @xDef, "" )

   IF ::hCookies == NIL

      ::hCookies := { => }
      cRaw := ::Header( "cookie", "" )

      IF ! Empty( cRaw )

         aPairs := hb_ATokens( cRaw, ";" )

         FOR EACH cPair IN aPairs

            cPair := AllTrim( cPair )
            nEq   := At( "=", cPair )

            IF nEq > 0

               ::hCookies[ AllTrim( Left( cPair, nEq - 1 ) ) ] := AllTrim( SubStr( cPair, nEq + 1 ) )

            ENDIF

         NEXT

      ENDIF

   ENDIF

RETURN hb_HGetDef( ::hCookies, cName, xDef )

// ------------------------------------------------------------
// IsMultipart / MultipartBoundary / MultipartFiles
// ------------------------------------------------------------
METHOD IsMultipart() CLASS THixRequest
RETURN "multipart/form-data" $ ::ContentType()

METHOD MultipartBoundary() CLASS THixRequest

   LOCAL cCT, nPos

   cCT  := ::Header( "content-type", "" )       // raw — sin Lower() para preservar case
   nPos := At( "boundary=", Lower( cCT ) )       // buscar case-insensitive

   IF nPos == 0

      RETURN ""

   ENDIF

RETURN AllTrim( SubStr( cCT, nPos + 9 ) )

METHOD MultipartFiles() CLASS THixRequest

   LOCAL cBoundary, cRaw, hPart

   IF ::aMultipart != NIL

      RETURN ::aMultipart

   ENDIF

   cBoundary := ::MultipartBoundary()

   IF Empty( cBoundary )

      ::aMultipart := {}
      RETURN ::aMultipart

   ENDIF

   cRaw         := ::ReadBody()
   ::aMultipart := HIX_ParseMultipart( cRaw, cBoundary )

   // Rellenar hFormBody con los campos de texto (sin filename)

   IF ::hFormBody == NIL

      ::hFormBody := { => }

   ENDIF

   FOR EACH hPart IN ::aMultipart

      IF Empty( hPart[ "filename" ] )

         ::hFormBody[ hPart[ "name" ] ] := hPart[ "data" ]

      ENDIF

   NEXT

RETURN ::aMultipart

// ------------------------------------------------------------
// Métodos proxy inverso
// ------------------------------------------------------------
METHOD Scheme() CLASS THixRequest
RETURN iif( Empty( ::cProtoScheme ), "http", Lower( ::cProtoScheme ) )

METHOD IsHttps() CLASS THixRequest
RETURN ::Scheme() == "https"

METHOD RealHost() CLASS THixRequest
RETURN iif( Empty( ::cFwdHost ), ::Header( "host", "" ), ::cFwdHost )

METHOD RealPort() CLASS THixRequest
RETURN ::cFwdPort

METHOD RealIP() CLASS THixRequest
RETURN iif( Empty( ::cRealClientIP ), ::cIP, ::cRealClientIP )

// ============================================================
// HIX_WantsJson — .T. si el cliente prefiere JSON como respuesta.
// Prioridad: 1) Accept: application/json  2) X-Requested-With: XMLHttpRequest
// 3) ruta /api/
// ============================================================
FUNCTION HIX_WantsJson( oReq )

   LOCAL cAccept

   cAccept := oReq:Header( "accept", "" )

   IF "application/json" $ cAccept

      RETURN .T.

   ENDIF

   IF Lower( oReq:Header( "x-requested-with", "" ) ) == "xmlhttprequest"

      RETURN .T.

   ENDIF

   IF __objHasData( oReq, "CPATH" ) .AND. Left( oReq:cPath, 5 ) == "/api/"

      RETURN .T.

   ENDIF

RETURN .F.

// ============================================================
// HIX_UrlDecode — decodifica URL-encoding (%XX y + → espacio).
// ============================================================
FUNCTION HIX_UrlDecode( cStr )

   LOCAL cResult := "", i, c, cHex, nHi, nLo

   cStr := StrTran( cStr, "+", " " )
   i := 1

   DO WHILE i <= Len( cStr )

      c := SubStr( cStr, i, 1 )

      IF c == "%" .AND. i + 2 <= Len( cStr )

         cHex := Upper( SubStr( cStr, i + 1, 2 ) )
         nHi  := _HixHexVal( SubStr( cHex, 1, 1 ) )
         nLo  := _HixHexVal( SubStr( cHex, 2, 1 ) )

         IF nHi >= 0 .AND. nLo >= 0

            cResult += Chr( nHi * 16 + nLo )
            i += 3
         ELSE
            cResult += c
            i++

         ENDIF

      ELSE
         cResult += c
         i++

      ENDIF

   ENDDO

RETURN cResult

STATIC FUNCTION _HixHexVal( c )

   LOCAL n := Asc( c )

   IF n >= 48 .AND. n <= 57  ; RETURN n - 48 ; ENDIF  // '0'-'9'

   IF n >= 65 .AND. n <= 70  ; RETURN n - 55 ; ENDIF  // 'A'-'F'

RETURN -1

// ============================================================
// HIX_SetCookie — añade Set-Cookie a hExtraHeaders del request.
// nMaxAge == 0  → cookie de sesión (sin Max-Age)
// nMaxAge == -1 → expirar inmediatamente (Max-Age=0)
// nMaxAge  > 0  → duración en segundos
// ============================================================
FUNCTION HIX_SetCookie( oReq, cName, cVal, nMaxAge )

   LOCAL cLine, xExisting, cPrefix, i

   hb_default( @nMaxAge, 0 )

   cLine   := cName + "=" + cVal + "; Path=/; HttpOnly; SameSite=Lax"
   cPrefix := cName + "="

   DO CASE

      CASE nMaxAge > 0
         cLine += "; Max-Age=" + hb_NToS( nMaxAge )
      CASE nMaxAge < 0
         cLine += "; Max-Age=0"

   ENDCASE

   IF hb_HHasKey( oReq:hExtraHeaders, "Set-Cookie" )

      xExisting := oReq:hExtraHeaders[ "Set-Cookie" ]

      IF ValType( xExisting ) == "A"

         FOR i := 1 TO Len( xExisting )

            IF Left( xExisting[ i ], Len( cPrefix ) ) == cPrefix

               xExisting[ i ] := cLine
               RETURN NIL

            ENDIF

         NEXT

         AAdd( xExisting, cLine )
      ELSE

         IF Left( xExisting, Len( cPrefix ) ) == cPrefix

            oReq:hExtraHeaders[ "Set-Cookie" ] := cLine
         ELSE
            oReq:hExtraHeaders[ "Set-Cookie" ] := { xExisting, cLine }

         ENDIF

      ENDIF

   ELSE
      oReq:hExtraHeaders[ "Set-Cookie" ] := cLine

   ENDIF

RETURN NIL

// ============================================================
// HIX_SetRequest / HIX_GetRequest — request thread-local
// Permite a PRG/HRB acceder al THixRequest activo via HIX_GetRequest()
// ============================================================
FUNCTION HIX_SetRequest( oReq )

   s_oCurrentReq := oReq

RETURN NIL

FUNCTION HIX_GetRequest()
RETURN s_oCurrentReq

// UContext — returns the middleware context from any .prg controller.
// Works across thread boundaries: the context is stored in oReq:hData["_ctx"]
// by _HixEvalAction before dispatching to the execution sub-thread.
FUNCTION UContext()
RETURN hb_HGetDef( s_oCurrentReq:hData, "_ctx", NIL )

// ============================================================
// THixSessionProxy — thin wrapper so USession() returns an
// object with a clean Set/Get/Save/Destroy API.
// ============================================================
CLASS THixSessionProxy

   DATA oCtx
   DATA lLoaded INIT .F.

   METHOD New( oCtx )
   METHOD _EnsureLoaded()
   METHOD Set( cKey, uVal )
   METHOD Get( cKey, uDef )
   METHOD Save()
   METHOD Destroy()

ENDCLASS

METHOD New( oCtx ) CLASS THixSessionProxy

   ::oCtx := oCtx

RETURN Self

METHOD _EnsureLoaded() CLASS THixSessionProxy

   IF ! ::lLoaded

      HIX_MwSession( ::oCtx )
      ::lLoaded := .T.

   ENDIF

RETURN NIL

METHOD Set( cKey, uVal ) CLASS THixSessionProxy

   ::_EnsureLoaded()
   HIX_SessionSet( ::oCtx, cKey, uVal )

RETURN NIL

METHOD Get( cKey, uDef ) CLASS THixSessionProxy

   ::_EnsureLoaded()

RETURN HIX_SessionGet( ::oCtx, cKey, uDef )

METHOD Save() CLASS THixSessionProxy

   ::_EnsureLoaded()
   HIX_SessionSave( ::oCtx )

RETURN NIL

METHOD Destroy() CLASS THixSessionProxy

   ::_EnsureLoaded()
   HIX_SessionDestroy( ::oCtx )

RETURN NIL
