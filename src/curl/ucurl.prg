/*-----------------------------------------------------------
  File ......: ucurl.prg
  Author.....: Charly 9000
  Created....: 2026-05-12
  Modified...: 2026-08-31
  Version....: 1.1.0
  Description: HTTP client class wrapping hbcurl.
  Usage      : o := UCurl():New( cUrl, hFields, cMethod, hOptions )
               o:AddHeader( "Authorization: Bearer ..." )
               nRet := o:Run()
               IF o:GetHttpCode() == 200 ; xData := o:GetResponse() ; ENDIF
               o:End()
  Notes      : - AddHeader() calls stack for the NEXT Run(); each Run()
                 resets headers/response/error so instances are reusable.
               - hOptions is a pass-through hash of HB_CURLOPT_* to raw
                 curl_easy_setopt() calls (except URL / verb / body /
                 headers which are set explicitly).
               - Default SSL_VERIFYPEER/HOST is .F. for backward compat
                 with existing self-signed callers (connector.prg).
                 Override via hOptions[ HB_CURLOPT_SSL_VERIFYPEER ] := .T.
 -----------------------------------------------------------*/
#include "hbcurl.ch"
#include "hbclass.ch"
#include "hix_const.ch"

// Force the linker to pull CURL_VERSION even though nothing calls it
// directly. Without this REQUEST the boot banner in hix_server.prg
// falls back to "n/a (hbcurl not linked)" because hbcurl.hbx marks
// CURL_VERSION as DYNAMIC (soft reference) instead of REQUEST.
REQUEST CURL_VERSION


CLASS UCurl

    DATA hCurl
    DATA cUrl
    DATA cMethod                        INIT 'POST'
    DATA hFields                        INIT {=>}
    DATA aHeaders                       INIT {}
    DATA aInfo                          INIT {=>}
    DATA cResponse                      INIT ''
    DATA cError                         INIT ''
    DATA nHttpCode                      INIT 0
    DATA lInit                          INIT .F.
    DATA hOptions                       INIT {=>}

    METHOD New( cUrl, hFields, cMethod, hOptions )
    METHOD Run()
    METHOD End()

    METHOD SetMethod( cMethod )         INLINE ::cMethod := Upper( cMethod )
    METHOD GetResponse()                INLINE ::cResponse
    METHOD GetResponseHash( cKey )
    METHOD GetError()                   INLINE ::cError
    METHOD GetHttpCode()                INLINE ::nHttpCode
    METHOD HttpCode2Txt( nStatus )

    METHOD BuildPostFields( hFields )
    METHOD BuildQueryString( hFields )
    METHOD AddHeader( cHeader )         INLINE AAdd( ::aHeaders, cHeader ), Self
    METHOD AddHeaderHash( hHeaders )

    // Convenience wrappers
    METHOD Get( cUrl )
    METHOD Post( cUrl, hFields )
    METHOD PostJson( cUrl, xData )

    // File transfer — streaming, no full-buffer in memory
    METHOD Download( cUrl, cLocalPath )
    METHOD Upload( cUrl, cLocalPath, cMethod )

ENDCLASS

//  --------------------------------------------------------- //

METHOD New( cUrl, hFields, cMethod, hOptions ) CLASS UCurl

    hb_default( @cUrl, '' )
    hb_default( @hFields, {=>} )
    hb_default( @cMethod, 'POST' )
    hb_default( @hOptions, {=>} )

    ::cUrl      := cUrl
    ::hFields   := hFields
    ::cMethod   := Upper( cMethod )
    ::hOptions  := hOptions

    ::hCurl     := curl_easy_init()

    ::lInit     := .T.

    HB_HCaseMatch( ::hOptions, .F. )

RETURN Self

//  --------------------------------------------------------- //

METHOD End() CLASS UCurl

    IF ::lInit .AND. ::hCurl != NIL
        curl_easy_cleanup( ::hCurl )
    ENDIF

    ::hCurl := NIL
    ::lInit := .F.

RETURN NIL

//  --------------------------------------------------------- //

METHOD Run() CLASS UCurl

    LOCAL cUrl      := ::cUrl
    LOCAL cData     := ''
    LOCAL cQs
    LOCAL nRet
    LOCAL nTimeout
    LOCAL xKey, xVal

    // Reset per-request state (headers stay: user builds them before Run)
    ::cResponse := ''
    ::cError    := ''
    ::nHttpCode := 0
    ::aInfo     := {=>}

    // Timeout — respect hOptions if present, else default 2s
    nTimeout := hb_HGetDef( ::hOptions, 'HB_CURLOPT_TIMEOUT', 2 )
    ::hOptions[ 'HB_CURLOPT_TIMEOUT' ] := nTimeout

    // Verb + body
    DO CASE
    CASE ::cMethod == 'GET'
        curl_easy_setopt( ::hCurl, HB_CURLOPT_HTTPGET, 1 )
        IF ! Empty( ::hFields )
            cQs := ::BuildQueryString( ::hFields )
            IF ! Empty( cQs )
                cUrl += iif( "?" $ cUrl, "&", "?" ) + cQs
            ENDIF
        ENDIF

    CASE ::cMethod == 'POST'
        cData := ::BuildPostFields( ::hFields )
        curl_easy_setopt( ::hCurl, HB_CURLOPT_POST, 1 )
        curl_easy_setopt( ::hCurl, HB_CURLOPT_POSTFIELDS, cData )

    CASE ::cMethod == 'PUT' .OR. ::cMethod == 'DELETE' .OR. ::cMethod == 'PATCH'
        curl_easy_setopt( ::hCurl, HB_CURLOPT_CUSTOMREQUEST, ::cMethod )
        IF ! Empty( ::hFields )
            cData := ::BuildPostFields( ::hFields )
            curl_easy_setopt( ::hCurl, HB_CURLOPT_POSTFIELDS, cData )
        ENDIF

    OTHERWISE
        // Unknown verb -> treat as custom
        curl_easy_setopt( ::hCurl, HB_CURLOPT_CUSTOMREQUEST, ::cMethod )
    ENDCASE

    curl_easy_setopt( ::hCurl, HB_CURLOPT_URL, cUrl )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_TIMEOUT, nTimeout )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_HTTPHEADER, ::aHeaders )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_WRITEFUNCTION, NIL )

    // Defaults SSL (compat) — overridable by hOptions
    curl_easy_setopt( ::hCurl, HB_CURLOPT_SSL_VERIFYPEER, .F. )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_SSL_VERIFYHOST, .F. )

    // Pass-through: keys must be numeric HB_CURLOPT_* constants.
    // Legacy string keys are ignored (only 'HB_CURLOPT_TIMEOUT'
    // was ever wired up historically and is already applied above).
    FOR EACH xKey IN hb_HKeys( ::hOptions )
        IF ! HB_ISNUMERIC( xKey ) ; LOOP ; ENDIF
        DO CASE
        CASE xKey == HB_CURLOPT_URL
        CASE xKey == HB_CURLOPT_POSTFIELDS
        CASE xKey == HB_CURLOPT_HTTPHEADER
        CASE xKey == HB_CURLOPT_POST
        CASE xKey == HB_CURLOPT_HTTPGET
        CASE xKey == HB_CURLOPT_CUSTOMREQUEST
        CASE xKey == HB_CURLOPT_TIMEOUT
            // Already applied
        OTHERWISE
            xVal := ::hOptions[ xKey ]
            curl_easy_setopt( ::hCurl, xKey, xVal )
        ENDCASE
    NEXT

    curl_easy_setopt( ::hCurl, HB_CURLOPT_DL_BUFF_SETUP )

    nRet := curl_easy_perform( ::hCurl )

    IF nRet == HB_CURLE_OK

        ::aInfo[ 'response_code'  ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_RESPONSE_CODE )
        ::aInfo[ 'connect_code'   ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_HTTP_CONNECTCODE )
        ::aInfo[ 'connect_time'   ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_CONNECT_TIME )
        ::aInfo[ 'total_time'     ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_TOTAL_TIME )
        ::aInfo[ 'size_upload'    ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_SIZE_UPLOAD )
        ::aInfo[ 'size_download'  ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_SIZE_DOWNLOAD )
        ::aInfo[ 'speed_upload'   ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_SPEED_UPLOAD )
        ::aInfo[ 'speed_download' ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_SPEED_DOWNLOAD )
        ::aInfo[ 'content_type'   ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_CONTENT_TYPE )
        ::aInfo[ 'time'           ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_STARTTRANSFER_TIME )

        ::nHttpCode := ::aInfo[ 'response_code' ]

        // Always capture body (2xx, 3xx, 4xx, 5xx) — caller decides
        ::cResponse := curl_easy_dl_buff_get( ::hCurl )
        IF ::cResponse == NIL ; ::cResponse := '' ; ENDIF

        IF ::nHttpCode >= 400
            ::cError := ::HttpCode2Txt( ::nHttpCode )
        ENDIF

    ELSE
        ::cError := curl_easy_strerror( nRet )
    ENDIF

RETURN nRet

//  --------------------------------------------------------- //

METHOD GetResponseHash( cKey ) CLASS UCurl

    LOCAL hValue

    hb_default( @cKey, '' )

    hValue := hb_jsondecode( ::cResponse )

    IF ! HB_ISHASH( hValue ) .AND. ! HB_ISARRAY( hValue )
        hValue := {=>}
    ENDIF

    IF ! Empty( ::cError ) .AND. HB_ISHASH( hValue )
        hValue[ 'success'  ] := .F.
        hValue[ 'msg'      ] := ::cError
        hValue[ 'httpcode' ] := ::nHttpCode
    ENDIF

    IF ! Empty( cKey ) .AND. HB_ISHASH( hValue )
        HB_HCaseMatch( hValue, .F. )
        IF HB_HHasKey( hValue, cKey )
            hValue := hValue[ cKey ]
        ENDIF
    ENDIF

RETURN hValue

//  --------------------------------------------------------- //

METHOD AddHeaderHash( hHeaders ) CLASS UCurl

    LOCAL cKey

    IF ! HB_ISHASH( hHeaders ) ; RETURN Self ; ENDIF

    FOR EACH cKey IN hb_HKeys( hHeaders )
        AAdd( ::aHeaders, cKey + ": " + hb_CStr( hHeaders[ cKey ] ) )
    NEXT

RETURN Self

//  --------------------------------------------------------- //

METHOD Get( cUrl ) CLASS UCurl

    IF cUrl != NIL ; ::cUrl := cUrl ; ENDIF
    ::cMethod := 'GET'

RETURN ::Run()

//  --------------------------------------------------------- //

METHOD Post( cUrl, hFields ) CLASS UCurl

    IF cUrl    != NIL ; ::cUrl    := cUrl    ; ENDIF
    IF hFields != NIL ; ::hFields := hFields ; ENDIF
    ::cMethod := 'POST'

RETURN ::Run()

//  --------------------------------------------------------- //

METHOD PostJson( cUrl, xData ) CLASS UCurl

    LOCAL cBody, lFound := .F., i

    IF cUrl != NIL ; ::cUrl := cUrl ; ENDIF
    ::cMethod := 'POST'

    cBody := iif( HB_ISSTRING( xData ), xData, hb_jsonEncode( xData ) )

    // Ensure Content-Type: application/json is present exactly once
    FOR i := 1 TO Len( ::aHeaders )
        IF Lower( Left( ::aHeaders[ i ], 13 ) ) == "content-type:"
            ::aHeaders[ i ] := "Content-Type: application/json"
            lFound := .T.
            EXIT
        ENDIF
    NEXT
    IF ! lFound
        AAdd( ::aHeaders, "Content-Type: application/json" )
    ENDIF

    // Bypass BuildPostFields: send raw JSON body
    ::cResponse := ''
    ::cError    := ''
    ::nHttpCode := 0
    ::aInfo     := {=>}

    curl_easy_setopt( ::hCurl, HB_CURLOPT_URL, ::cUrl )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_TIMEOUT, hb_HGetDef( ::hOptions, 'HB_CURLOPT_TIMEOUT', 2 ) )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_POST, 1 )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_POSTFIELDS, cBody )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_HTTPHEADER, ::aHeaders )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_SSL_VERIFYPEER, .F. )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_SSL_VERIFYHOST, .F. )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_DL_BUFF_SETUP )

    i := curl_easy_perform( ::hCurl )

    IF i == HB_CURLE_OK
        ::nHttpCode := curl_easy_getinfo( ::hCurl, HB_CURLINFO_RESPONSE_CODE )
        ::cResponse := curl_easy_dl_buff_get( ::hCurl )
        IF ::cResponse == NIL ; ::cResponse := '' ; ENDIF
        IF ::nHttpCode >= 400
            ::cError := ::HttpCode2Txt( ::nHttpCode )
        ENDIF
    ELSE
        ::cError := curl_easy_strerror( i )
    ENDIF

RETURN i

//  --------------------------------------------------------- //

METHOD BuildQueryString( hFields ) CLASS UCurl

    LOCAL aKeys := hb_HKeys( hFields )
    LOCAL cOut  := ''
    LOCAL cKey, xValue, cVal, i

    FOR i := 1 TO Len( aKeys )
        cKey   := aKeys[ i ]
        xValue := hFields[ cKey ]
        cVal   := _UCurlValToStr( xValue )
        IF i > 1 ; cOut += "&" ; ENDIF
        cOut += curl_easy_escape( ::hCurl, cKey ) + "=" + curl_easy_escape( ::hCurl, cVal )
    NEXT

RETURN cOut

//  --------------------------------------------------------- //

METHOD BuildPostFields( hFields ) CLASS UCurl

    LOCAL aKeys := hb_HKeys( hFields )
    LOCAL cOut  := ''
    LOCAL cKey, xValue, cVal, i

    FOR i := 1 TO Len( aKeys )
        cKey   := aKeys[ i ]
        xValue := hFields[ cKey ]
        cVal   := _UCurlValToStr( xValue )
        IF i > 1 ; cOut += "&" ; ENDIF
        cOut += curl_easy_escape( ::hCurl, cKey ) + "=" + curl_easy_escape( ::hCurl, cVal )
    NEXT

RETURN cOut

//  --------------------------------------------------------- //

METHOD HttpCode2Txt( nStatus ) CLASS UCurl

    LOCAL cStatus := ''

    hb_default( @nStatus, ::nHttpCode )

    DO CASE
    CASE nStatus == 100 ; cStatus := "100 Continue"
    CASE nStatus == 101 ; cStatus := "101 Switching Protocols"
    CASE nStatus == 200 ; cStatus := "200 OK"
    CASE nStatus == 201 ; cStatus := "201 Created"
    CASE nStatus == 202 ; cStatus := "202 Accepted"
    CASE nStatus == 203 ; cStatus := "203 Non-Authoritative Information"
    CASE nStatus == 204 ; cStatus := "204 No Content"
    CASE nStatus == 205 ; cStatus := "205 Reset Content"
    CASE nStatus == 206 ; cStatus := "206 Partial Content"
    CASE nStatus == 300 ; cStatus := "300 Multiple Choices"
    CASE nStatus == 301 ; cStatus := "301 Moved Permanently"
    CASE nStatus == 302 ; cStatus := "302 Found"
    CASE nStatus == 303 ; cStatus := "303 See Other"
    CASE nStatus == 304 ; cStatus := "304 Not Modified"
    CASE nStatus == 305 ; cStatus := "305 Use Proxy"
    CASE nStatus == 307 ; cStatus := "307 Temporary Redirect"
    CASE nStatus == 400 ; cStatus := "400 Bad Request"
    CASE nStatus == 401 ; cStatus := "401 Unauthorized"
    CASE nStatus == 402 ; cStatus := "402 Payment Required"
    CASE nStatus == 403 ; cStatus := "403 Forbidden"
    CASE nStatus == 404 ; cStatus := "404 Not Found"
    CASE nStatus == 405 ; cStatus := "405 Method Not Allowed"
    CASE nStatus == 406 ; cStatus := "406 Not Acceptable"
    CASE nStatus == 407 ; cStatus := "407 Proxy Authentication Required"
    CASE nStatus == 408 ; cStatus := "408 Request Timeout"
    CASE nStatus == 409 ; cStatus := "409 Conflict"
    CASE nStatus == 410 ; cStatus := "410 Gone"
    CASE nStatus == 411 ; cStatus := "411 Length Required"
    CASE nStatus == 412 ; cStatus := "412 Precondition Failed"
    CASE nStatus == 413 ; cStatus := "413 Request Entity Too Large"
    CASE nStatus == 414 ; cStatus := "414 Request-URI Too Long"
    CASE nStatus == 415 ; cStatus := "415 Unsupported Media Type"
    CASE nStatus == 416 ; cStatus := "416 Requested Range Not Satisfiable"
    CASE nStatus == 417 ; cStatus := "417 Expectation Failed"
    CASE nStatus == 500 ; cStatus := "500 Internal Server Error"
    CASE nStatus == 501 ; cStatus := "501 Not Implemented"
    CASE nStatus == 502 ; cStatus := "502 Bad Gateway"
    CASE nStatus == 503 ; cStatus := "503 Service Unavailable"
    CASE nStatus == 504 ; cStatus := "504 Gateway Timeout"
    CASE nStatus == 505 ; cStatus := "505 HTTP Version Not Supported"
    OTHERWISE
        cStatus := hb_NToS( nStatus ) + " Unknown Status"
    ENDCASE

RETURN cStatus

//  --------------------------------------------------------- //
// Download — GET cUrl and stream the body to cLocalPath.
// Uses HB_CURLOPT_DL_FILE_SETUP so the file is written straight
// to disk (no full-body buffer in RAM). Suitable for large files.
// Returns HTTP status code (0 on transport error, cError filled).
//  --------------------------------------------------------- //

METHOD Download( cUrl, cLocalPath ) CLASS UCurl

    LOCAL nRet
    LOCAL nTimeout

    IF cUrl != NIL ; ::cUrl := cUrl ; ENDIF

    IF Empty( cLocalPath )
        ::cError := "Download: cLocalPath required"
        RETURN 0
    ENDIF

    ::cResponse := ''
    ::cError    := ''
    ::nHttpCode := 0
    ::aInfo     := {=>}

    nTimeout := hb_HGetDef( ::hOptions, 'HB_CURLOPT_TIMEOUT', 30 )

    curl_easy_setopt( ::hCurl, HB_CURLOPT_URL, ::cUrl )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_TIMEOUT, nTimeout )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_HTTPGET, 1 )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_HTTPHEADER, ::aHeaders )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_SSL_VERIFYPEER, .F. )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_SSL_VERIFYHOST, .F. )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_FOLLOWLOCATION, .T. )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_DL_FILE_SETUP, cLocalPath )

    nRet := curl_easy_perform( ::hCurl )

    // Close the download file handle immediately so caller can read it
    curl_easy_setopt( ::hCurl, HB_CURLOPT_DL_FILE_CLOSE )

    IF nRet == HB_CURLE_OK
        ::nHttpCode := curl_easy_getinfo( ::hCurl, HB_CURLINFO_RESPONSE_CODE )
        ::aInfo[ 'response_code'  ] := ::nHttpCode
        ::aInfo[ 'total_time'     ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_TOTAL_TIME )
        ::aInfo[ 'size_download'  ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_SIZE_DOWNLOAD )
        ::aInfo[ 'speed_download' ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_SPEED_DOWNLOAD )
        ::aInfo[ 'content_type'   ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_CONTENT_TYPE )
        IF ::nHttpCode >= 400
            ::cError := ::HttpCode2Txt( ::nHttpCode )
        ENDIF
    ELSE
        ::cError := curl_easy_strerror( nRet )
    ENDIF

RETURN ::nHttpCode

//  --------------------------------------------------------- //
// Upload — send cLocalPath as request body. Default verb is
// PUT (curl standard for HB_CURLOPT_UPLOAD). Pass "POST" to
// send as raw POST body instead. Uses HB_CURLOPT_UL_FILE_SETUP
// so hbcurl streams from disk (no full-body buffer in RAM).
// Response body (if any) is captured in ::cResponse via the
// download buffer. Returns HTTP status code.
//  --------------------------------------------------------- //

METHOD Upload( cUrl, cLocalPath, cMethod ) CLASS UCurl

    LOCAL nRet
    LOCAL nTimeout
    LOCAL nSize

    IF cUrl != NIL ; ::cUrl := cUrl ; ENDIF
    hb_default( @cMethod, "PUT" )
    cMethod := Upper( cMethod )

    IF Empty( cLocalPath ) .OR. ! hb_FileExists( cLocalPath )
        ::cError := "Upload: cLocalPath not found: " + hb_CStr( cLocalPath )
        RETURN 0
    ENDIF

    ::cResponse := ''
    ::cError    := ''
    ::nHttpCode := 0
    ::aInfo     := {=>}

    nTimeout := hb_HGetDef( ::hOptions, 'HB_CURLOPT_TIMEOUT', 60 )
    nSize    := hb_FSize( cLocalPath )

    curl_easy_setopt( ::hCurl, HB_CURLOPT_URL, ::cUrl )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_TIMEOUT, nTimeout )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_HTTPHEADER, ::aHeaders )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_SSL_VERIFYPEER, .F. )
    curl_easy_setopt( ::hCurl, HB_CURLOPT_SSL_VERIFYHOST, .F. )

    IF cMethod == "POST"
        // Raw POST body from file: read whole thing (hbcurl doesn't
        // expose a streaming callback for POST body, only for UPLOAD).
        curl_easy_setopt( ::hCurl, HB_CURLOPT_POST, 1 )
        curl_easy_setopt( ::hCurl, HB_CURLOPT_POSTFIELDS, hb_MemoRead( cLocalPath ) )
    ELSE
        // PUT (or custom): streaming upload via hbcurl helper
        curl_easy_setopt( ::hCurl, HB_CURLOPT_UPLOAD, 1 )
        curl_easy_setopt( ::hCurl, HB_CURLOPT_INFILESIZE_LARGE, nSize )
        curl_easy_setopt( ::hCurl, HB_CURLOPT_UL_FILE_SETUP, cLocalPath )
        IF cMethod != "PUT"
            curl_easy_setopt( ::hCurl, HB_CURLOPT_CUSTOMREQUEST, cMethod )
        ENDIF
    ENDIF

    curl_easy_setopt( ::hCurl, HB_CURLOPT_DL_BUFF_SETUP )

    nRet := curl_easy_perform( ::hCurl )

    // Close upload file handle if it was opened
    IF cMethod != "POST"
        curl_easy_setopt( ::hCurl, HB_CURLOPT_UL_FILE_CLOSE )
    ENDIF

    IF nRet == HB_CURLE_OK
        ::nHttpCode := curl_easy_getinfo( ::hCurl, HB_CURLINFO_RESPONSE_CODE )
        ::aInfo[ 'response_code' ] := ::nHttpCode
        ::aInfo[ 'total_time'    ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_TOTAL_TIME )
        ::aInfo[ 'size_upload'   ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_SIZE_UPLOAD )
        ::aInfo[ 'speed_upload'  ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_SPEED_UPLOAD )
        ::aInfo[ 'content_type'  ] := curl_easy_getinfo( ::hCurl, HB_CURLINFO_CONTENT_TYPE )
        ::cResponse := curl_easy_dl_buff_get( ::hCurl )
        IF ::cResponse == NIL ; ::cResponse := '' ; ENDIF
        IF ::nHttpCode >= 400
            ::cError := ::HttpCode2Txt( ::nHttpCode )
        ENDIF
    ELSE
        ::cError := curl_easy_strerror( nRet )
    ENDIF

RETURN ::nHttpCode

//  --------------------------------------------------------- //
// Typed value -> string conversion for x-www-form-urlencoded /
// query strings. Fixes hb_ValToStr() spitting Harbour reprs
// (.T., d"...", {...}) instead of the real value.
//  --------------------------------------------------------- //

STATIC FUNCTION _UCurlValToStr( xValue )

    LOCAL cType := ValType( xValue )
    LOCAL cRet

    DO CASE
    CASE cType == "C" ; cRet := xValue
    CASE cType == "M" ; cRet := xValue
    CASE cType == "N" ; cRet := hb_NToS( xValue )
    CASE cType == "L" ; cRet := iif( xValue, "true", "false" )
    CASE cType == "D" ; cRet := iif( Empty( xValue ), "", hb_DToC( xValue, "yyyy-mm-dd" ) )
    CASE cType == "T" ; cRet := iif( Empty( xValue ), "", hb_TToC( xValue, "yyyy-mm-dd", "hh:mm:ss" ) )
    CASE cType == "H" ; cRet := hb_jsonEncode( xValue )
    CASE cType == "A" ; cRet := hb_jsonEncode( xValue )
    CASE cType == "U" ; cRet := ""
    OTHERWISE          ; cRet := hb_CStr( xValue )
    ENDCASE

RETURN cRet
