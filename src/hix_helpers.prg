/*-----------------------------------------------------------
  File ......: hix_helpers.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-11
  Description: Global U* convenience functions for routes and controllers
               (UGet, UPost, USendJson, etc.).
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_REQUEST
#INCLUDE "hix_logger.ch"

// ------------------------------------------------------------
// REQUEST — DATA READING
// ------------------------------------------------------------

FUNCTION UMethod()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:cMethod, "" )

FUNCTION UPath()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:cPath, "" )

FUNCTION UQuery()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:cQuery, "" )

FUNCTION UGet( cKey, xDef )

   LOCAL o := HIX_GetRequest()

   hb_default( @xDef, "" )

   IF PCount() == 0

      IF o == NIL

         RETURN { => }

      ENDIF

      RETURN o:QueryParamsAll()

   ENDIF

RETURN iif( o != NIL, o:QueryParam( cKey, xDef ), xDef )

FUNCTION UPost( cKey, xDef )

   LOCAL o := HIX_GetRequest()
   LOCAL h

   hb_default( @xDef, "" )

   IF o == NIL

      RETURN iif( PCount() == 0, { => }, xDef )

   ENDIF

   IF o:IsJson()

      h := o:JsonBody()

      IF ValType( h ) != "H"

         RETURN iif( PCount() == 0, { => }, xDef )

      ENDIF

      HB_HCaseMatch( h, .F. )

      IF PCount() == 0

         RETURN hb_HClone( h )

      ENDIF

      RETURN hb_HGetDef( h, cKey, xDef )

   ENDIF

   h := o:FormBody()
   HB_HCaseMatch( h, .F. )

   IF PCount() == 0

      RETURN hb_HClone( h )

   ENDIF

RETURN hb_HGetDef( h, cKey, xDef )

FUNCTION UParam( cKey, xDef )

   LOCAL o      := HIX_GetRequest()
   LOCAL lDef   := ( PCount() >= 2 )
   LOCAL cLabel, hCopy

   IF PCount() == 0

      IF o == NIL

         RETURN { => }

      ENDIF

      hCopy := hb_HClone( o:hParam )
      HB_HCaseMatch( hCopy, .F. )
      RETURN hCopy

   ENDIF

   cLabel := iif( ValType( cKey ) == "N", hb_NToS( cKey ), cKey )

   IF ValType( cKey ) == "N"

      cKey := "_" + hb_NToS( cKey )

   ENDIF

   IF o != NIL

      HB_HCaseMatch( o:hParam, .F. )

      IF hb_HHasKey( o:hParam, cKey )

         RETURN o:hParam[ cKey ]

      ENDIF

   ENDIF

   IF lDef

      RETURN xDef

   ENDIF

   HIX_Throw( HIX_NewError( _( 'ERR_PARAM_NOT_FOUND', cLabel ), "Request", 400, "UParam" ) )

RETURN ""

FUNCTION UHeader( cKey, xDef )

   LOCAL o := HIX_GetRequest()

   hb_default( @xDef, "" )

RETURN iif( o != NIL, o:Header( cKey, xDef ), xDef )

FUNCTION UCookie( cKey, xDef )

   LOCAL o := HIX_GetRequest()

   hb_default( @xDef, "" )

RETURN iif( o != NIL, o:Cookie( cKey, xDef ), xDef )

FUNCTION UBody()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:ReadBody(), "" )

FUNCTION UJson()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:JsonBody(), NIL )

FUNCTION UContentType()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:ContentType(), "" )

// ------------------------------------------------------------
// REQUEST — STATE AND NEGOTIATION
// ------------------------------------------------------------

FUNCTION UIsPost()
RETURN Upper( UMethod() ) == "POST"

FUNCTION UIsGet()
RETURN Upper( UMethod() ) == "GET"

FUNCTION UIsAjax()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:IsAjax(), .F. )

FUNCTION UIsHttps()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:IsHttps(), .F. )

FUNCTION UScheme()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:Scheme(), "http" )

FUNCTION UIsJson()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:IsJson(), .F. )

FUNCTION UWantsJson()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, HIX_WantsJson( o ), .F. )

FUNCTION UIP()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:RealIP(), "" )

FUNCTION UHost()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:RealHost(), "" )

FUNCTION UPort()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:RealPort(), 0 )

FUNCTION UIsForm()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:IsForm(), .F. )

FUNCTION UIsMultipart()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:IsMultipart(), .F. )

FUNCTION UFiles()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:MultipartFiles(), {} )

FUNCTION UContentLength()

   LOCAL o := HIX_GetRequest()

RETURN iif( o != NIL, o:ContentLength(), 0 )

FUNCTION URequest()
RETURN HIX_GetRequest()

// ------------------------------------------------------------
// RESPONSE — OUTPUTS (USend)
// ------------------------------------------------------------

// Base Response Function — acumula en buffer (no envia directamente)
FUNCTION USend( xData, nStatus, cMime, hExtra )

   LOCAL o    := HIX_GetRequest()
   LOCAL cOut

   hb_default( @nStatus, 200 )

   IF o == NIL

      RETURN NIL

   ENDIF

   IF cMime == NIL .OR. cMime == "html"

      IF ValType( xData ) == "H" .OR. ValType( xData ) == "A"

         cMime := "json"
      ELSEIF HIX_WantsJson( o )
         cMime := "json"
      ELSE
         hb_default( @cMime, "html" )

      ENDIF

   ENDIF

   cOut := iif( ValType( xData ) == "H" .OR. ValType( xData ) == "A", ;
      hb_jsonEncode( xData ), UStr( xData ) )
   HIX_SetStatus( nStatus )
   HIX_SetMime( cMime )

   IF ! Empty( hExtra )

      hb_HMerge( o:hExtraHeaders, hExtra )

   ENDIF

   HIX_Echo( cOut )

RETURN NIL

// Flush buffer — envia lo acumulado y resetea.
// Primer flush: inicia chunked stream (RespondStart + RespondChunk).
// Flushes posteriores: solo RespondChunk.
// El dispatcher llama RespondEnd() al terminar la ejecucion.
FUNCTION UFlush()

   LOCAL o := HIX_GetRequest()

   IF o == NIL .OR. o:lResponded .OR. Empty( o:cEchoBuffer )

      RETURN NIL

   ENDIF

   IF o:lStreaming

      o:RespondChunk( o:cEchoBuffer )
   ELSE
      o:RespondStart( o:cResponseMime, o:nResponseStatus )
      o:RespondChunk( o:cEchoBuffer )

   ENDIF

   o:cEchoBuffer := ""

RETURN NIL

// Send View response — must echo so the router sends a response
FUNCTION USendView( cView, ... )

   LOCAL cHtml := UView( cView, ... )

   IF ! Empty( cHtml )

      HIX_SetMime( "html" )
      HIX_Echo( cHtml )

   ENDIF

RETURN cHtml

// Send HTML Response
FUNCTION USendHtml( cHtml, nStatus )

   hb_default( @nStatus, 200 )
   USend( cHtml, nStatus, "html" )

RETURN NIL

// Send Plain Text Response
FUNCTION USendText( cText, nStatus )

   hb_default( @nStatus, 200 )
   USend( cText, nStatus, "text" )

RETURN NIL

// Send JSON Response
FUNCTION USendJson( xData, nStatus )

   hb_default( @nStatus, 200 )
   USend( xData, nStatus, "json" )

RETURN NIL

// Send 204 No Content Response
FUNCTION USendEmpty()

   LOCAL o := HIX_GetRequest()

   IF o != NIL

      o:Respond( "", 204, "html" )

   ENDIF

RETURN NIL

// Send Redirect Response
FUNCTION URedirect( cUrl, nStatus )

   LOCAL o := HIX_GetRequest()

   hb_default( @nStatus, 302 )

   IF o != NIL

      o:Redirect( cUrl, nStatus )

   ENDIF

RETURN NIL

// Send HTTP Error Response
FUNCTION USendError( nStatus, cDetail )

   LOCAL o := HIX_GetRequest()

   hb_default( @nStatus, 500 )
   hb_default( @cDetail, "" )

   IF o != NIL

      HIX_HttpError( o, nStatus, cDetail )

   ENDIF

RETURN NIL

// ------------------------------------------------------------
// RESPONSE — MODIFIERS
// ------------------------------------------------------------

// Set a Custom Response Header
FUNCTION USetHeader( cKey, cVal )

   LOCAL o := HIX_GetRequest()

   IF o != NIL

      o:hExtraHeaders[ cKey ] := cVal

   ENDIF

RETURN NIL

// Set a Response Cookie
FUNCTION USetCookie( cName, cVal, nMaxAge )

   LOCAL o := HIX_GetRequest()

   hb_default( @nMaxAge, 0 )

   IF o != NIL

      HIX_SetCookie( o, cName, cVal, nMaxAge )

   ENDIF

RETURN NIL

// ------------------------------------------------------------
// STREAMING (USendStream)
// ------------------------------------------------------------

// Start a Chunked Stream Response
FUNCTION USendStreamStart( cMime, nStatus, hExtra )

   LOCAL o := HIX_GetRequest()

   hb_default( @cMime,   "html" )
   hb_default( @nStatus, 200 )
   hb_default( @hExtra,  { => } )

   IF o != NIL

      o:RespondStart( cMime, nStatus, hExtra )

   ENDIF

RETURN NIL

// Send a Single Chunk of Data
FUNCTION USendChunk( cData )

   LOCAL o := HIX_GetRequest()

   IF o != NIL

      o:RespondChunk( cData )

   ENDIF

RETURN NIL

// End the Stream Response
FUNCTION USendStreamEnd()

   LOCAL o := HIX_GetRequest()

   IF o != NIL

      o:RespondEnd()

   ENDIF

RETURN NIL

// ------------------------------------------------------------
// UTILITIES AND ENVIRONMENT
// ------------------------------------------------------------

// Get full config hash / section / scalar (thin wrapper over HIX_GetConfig).
FUNCTION UGetConfig( cSection, cKey )

   LOCAL nArgs := PCount()

   IF nArgs == 0 ; RETURN HIX_GetConfig() ; ENDIF

   IF nArgs == 1 ; RETURN HIX_GetConfig( cSection ) ; ENDIF

RETURN HIX_GetConfig( cSection, cKey )

// Get Current Environment (dev/prod)
FUNCTION UEnv()  ; RETURN UConfig( "app", "env", "dev" )
FUNCTION UProd() ; RETURN UConfig( "app", "env", "prod" )

// Check if Environment is Development
FUNCTION UIsDev()  ; RETURN UEnv() == "dev"
FUNCTION UIsProd() ; RETURN UEnv() == "prod"

// Get Configuration Value — defensive (returns xDef if section/key missing).
FUNCTION UConfig( cSection, cKey, xDef )

   LOCAL hCfg := HIX_GetConfig()

   IF ! hb_IsHash( hCfg ) .OR. ! hb_HHasKey( hCfg, cSection )

      RETURN xDef

   ENDIF

   IF ! hb_HHasKey( hCfg[ cSection ], cKey )

      RETURN xDef

   ENDIF

RETURN hCfg[ cSection ][ cKey ]

// Read a value from the middleware setup config (www/middlewares/config.json "setup" section).
// UMwConfig( "auth", "session_user_key" )  -> "_auth_user"
FUNCTION UMwConfig( cSection, cKey, xDef )
RETURN HIX_MwConfig( cSection, cKey, xDef )

// Get Current Timestamp in String Format
FUNCTION UNow()
RETURN hb_TToS( hb_DateTime() )

// Direct Echo to Buffer
FUNCTION UEcho( ... )  ; RETURN HIX_Echo( ... )
FUNCTION UWrite( ... ) ; RETURN HIX_Echo( ... )

// Set MIME for buffer output — alias (json, html, text...) or full MIME type
FUNCTION USetMime( cMime )

   hb_default( @cMime, "html" )
   HIX_SetMime( cMime )

RETURN NIL

// Get current buffer MIME
FUNCTION UGetMime()
RETURN HIX_GetMime()

// Set HTTP status for buffer output
FUNCTION USetStatus( nStatus )

   hb_default( @nStatus, 200 )
   HIX_SetStatus( nStatus )

RETURN NIL


// ------------------------------------------------------------
// CONTEXT — SESSION AND JWT (via HIX_GetContext)
// ------------------------------------------------------------

// USession()        -> THixSessionProxy (Set/Get/Save/Destroy) — works in .prg sub-threads
// USession(cKey)    -> value for key, NIL if not found
// USession(cKey, x) -> value for key, x as default
FUNCTION USession( cKey, xDef )

   IF PCount() == 0

      RETURN THixSessionProxy():New( UContext() )

   ENDIF

RETURN HIX_Session( cKey, xDef )

// UJwt()        -> full JWT payload hash
// UJwt(cKey)    -> claim value, NIL if not found
// UJwt(cKey, x) -> claim value, x as default
FUNCTION UJwt( cKey, xDef )
RETURN HIX_JwtPayload( cKey, xDef )

// UAuthUser()         -> full authenticated user hash (set by auth middleware), or NIL
// UAuthUser( cKey )   -> single field value, NIL if not found
// UAuthUser( cKey, x) -> single field value, x as default
FUNCTION UAuthUser( cKey, xDef )

   LOCAL oReq  := URequest()
   LOCAL hUser := iif( oReq != NIL, hb_HGetDef( oReq:hData, "user", NIL ), NIL )

   IF PCount() == 0

      RETURN hUser

   ENDIF

RETURN hb_HGetDef( iif( ValType( hUser ) == "H", hUser, { => } ), cKey, xDef )


// UHasScope( cScope ) -> .T. if the current JWT carries the given scope token.
// cScope is a single space-separated token, e.g. "read:products".
// Returns .F. if no JWT is present.
FUNCTION UHasScope( cScope )

   LOCAL hJwt, cGranted, aGranted

   hJwt := HIX_JwtPayload()

   IF ValType( hJwt ) != "H"

      RETURN .F.

   ENDIF

   cGranted := AllTrim( hb_HGetDef( hJwt, "scope", "" ) )

   IF Empty( cGranted )

      RETURN .F.

   ENDIF

   aGranted := hb_ATokens( cGranted, " " )

RETURN AScan( aGranted, {| s | s == AllTrim( cScope ) } ) > 0

// ------------------------------------------------------------
// VIEW / PATH UTILITIES
// ------------------------------------------------------------

// URoot() -> configured web root folder name (e.g. "www")
FUNCTION URoot()
RETURN HIX_GetRoot()

// URootPath() -> absolute filesystem path to web root, with trailing separator
FUNCTION URootPath()
RETURN HIX_GetRootAbsolute()

// UErrorPage(oError) -> renders oError as HTML page and sends it as response
FUNCTION UErrorPage( oError )

   LOCAL cHtml := HIX_ErrorSys( oError )
   LOCAL o     := HIX_GetRequest()

   IF o != NIL

      o:Respond( cHtml, 500, "html" )

   ENDIF

RETURN NIL

// -----------------------------------------------------------
// HIX_CloseDbfAreas( [lForce] )
// Cierra todas las areas DBF abiertas en el hilo actual si la
// configuracion [app] auto_close_dbf esta activa (o si lForce=.T.).
// Si [app] auto_close_dbf_log esta activo, escribe en log la
// lista de aliases que quedaron abiertos antes del cierre.
// Uso interno: llamado por el router/dispatcher al terminar la
// ejecucion de una request. Uso publico: se puede invocar desde
// controllers para liberar antes del cierre automatico.
// -----------------------------------------------------------
FUNCTION HIX_CloseDbfAreas( lForce )

   LOCAL lEnabled, lLog, oError
   LOCAL nSaved, nSel, cAlias, cList

   hb_default( @lForce, .F. )

   lEnabled := lForce .OR. UConfig( 'app', 'auto_close_dbf', .F. )

   IF ! lEnabled

      RETURN .F.

   ENDIF

   lLog  := UConfig( 'app', 'auto_close_dbf_log', .F. )
   cList := ''

   TRY

      IF lLog

         nSaved := Select()

         FOR nSel := 1 TO 65535

            cAlias := Alias( nSel )

            IF Empty( cAlias )

               EXIT

            ENDIF

            cList += iif( Empty( cList ), '', ',' ) + cAlias

         NEXT

         IF nSaved > 0

            dbSelectArea( nSaved )

         ENDIF

         IF ! Empty( cList )

            lw( 'auto-close dbf aliases: ' + cList )

         ENDIF

      ENDIF

      dbCloseAll()
   CATCH oError
      le( 'HIX_CloseDbfAreas error: ' + oError:description )
      RETURN .F.

   END

RETURN .T.

FUNCTION HIX_NetName()

   LOCAL cHost := hb_GetEnv( "HOSTNAME", hb_GetEnv( "COMPUTERNAME", "" ) )

   IF Empty( cHost )
      TRY
         cHost := hb_socketGetHostName( hb_socketResolveAddr( "127.0.0.1" ) )
      CATCH
      END
   ENDIF

   IF Empty( cHost )
      cHost := "localhost"
   ENDIF

RETURN cHost

FUNCTION NetName()
RETURN HIX_NetName()
