/*-----------------------------------------------------------
  File ......: hix_error.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: Error types, worker protection block and HTTP error page
               renderer (HIX_ShowError).
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE HIX_LOG_MODULE HIX_MOD_ERROR

#INCLUDE "hix_logger.ch"
#INCLUDE "hbhrb.ch"
#INCLUDE "error.ch"

// Handler de aplicacion: {|oHarbourError, oReq| ...}
STATIC s_bOnError      := NIL

// Error sys: ruta relativa a www/ del template de vista personalizado
STATIC s_cErrorSysFile := ""

// Error log: fichero unico errors.log con append
STATIC s_cErrorLogPath := ""
STATIC s_hErrLog       := NIL
STATIC s_oErrMutex     := NIL
STATIC s_nErrLogSeq    := 0

CLASS THixError

   DATA nCode    INIT HIX_ERR_OK
   DATA cMessage INIT ""
   DATA cModule  INIT ""
   DATA tAt      INIT NIL

   METHOD New( nCode, cMessage, cModule )
   METHOD ToString()
   METHOD IsOk()

ENDCLASS

METHOD New( nCode, cMessage, cModule ) CLASS THixError

   hb_default( @nCode,    HIX_ERR_OK )
   hb_default( @cMessage, ""         )
   hb_default( @cModule,  ""         )
   
   ::nCode    := nCode
   ::cMessage := cMessage
   ::cModule  := cModule
   ::tAt      := hb_DateTime()

RETURN Self

METHOD ToString() CLASS THixError
RETURN "[" + HIX_ErrorName( ::nCode ) + "] " + ::cModule + ": " + ::cMessage

METHOD IsOk() CLASS THixError
RETURN ::nCode == HIX_ERR_OK

// ============================================================
// HIX_SetErrorHandler / HIX_GetErrorHandler
// ============================================================
FUNCTION HIX_SetErrorHandler( bBlock )

   s_bOnError := bBlock

RETURN NIL

FUNCTION HIX_GetErrorHandler()
RETURN s_bOnError

// ============================================================
// _HixResolveErrorSysPath — normaliza la ruta configurada en app.errorsys.
// Con hixstyle.enabled=.T., la carpeta "errors/" es fija en el layout
// (como controllers/, views/, models/) y siempre se prefija.
// Sin hixstyle, el valor se usa tal cual bajo <cRoot>.
// ============================================================
STATIC FUNCTION _HixResolveErrorSysPath( cFile )

   IF Empty( cFile )

      RETURN ""

   ENDIF

   IF UConfig( "hixstyle", "enabled", .F. )

      RETURN "errors" + hb_ps() + cFile

   ENDIF

RETURN cFile

// ============================================================
// HIX_ErrorSysInit — registra el template custom de errorsys.
// No carga nada: el template se ejecuta bajo demanda via UView.
// cFile es la ruta configurada en app.errorsys (ver reglas en
// _HixResolveErrorSysPath).
// ============================================================
FUNCTION HIX_ErrorSysInit( cFile )

   LOCAL cFullPath, cRoot

   s_cErrorSysFile := _HixResolveErrorSysPath( hb_defaultValue( cFile, "" ) )

   IF Empty( s_cErrorSysFile )

      RETURN NIL

   ENDIF

   cRoot := UConfig( "paths", "root", "www" )
   cFullPath := hb_dirbase() + cRoot + hb_ps() + s_cErrorSysFile

   IF hb_FileExists( cFullPath )

      l( "HIX_ErrorSysInit: errorsys configurado — " + s_cErrorSysFile )
   ELSE
      le( "HIX_ErrorSysInit: file_error configurado pero no existe — " + cFullPath )

   ENDIF

RETURN NIL

// ============================================================
// HIX_ErrorLogInit — establece el directorio de log de errores.
// Llamar desde THixServer._Init() con ::oConfig:cPathErrors.
// cPath vacio -> log desactivado.
// ============================================================
FUNCTION HIX_ErrorLogInit( cPath )

   LOCAL cFile

   s_cErrorLogPath := hb_defaultValue( cPath, "" )

   IF Empty( s_cErrorLogPath )

      RETURN NIL

   ENDIF

   IF ! hb_DirExists( s_cErrorLogPath )

      hb_DirCreate( s_cErrorLogPath )

   ENDIF

   cFile := s_cErrorLogPath + hb_ps() + "errors.log"
   s_oErrMutex := hb_mutexCreate()
   s_hErrLog := FOpen( cFile, FO_READWRITE + FO_SHARED )

   IF s_hErrLog == F_ERROR

      s_hErrLog := FCreate( cFile )

   ENDIF

   FSeek( s_hErrLog, 0, FS_END )

RETURN NIL

FUNCTION HIX_ErrorLogClose()

   IF s_hErrLog != NIL .AND. s_hErrLog != F_ERROR

      FClose( s_hErrLog )
      s_hErrLog := NIL

   ENDIF

   s_oErrMutex := NIL

RETURN NIL

// ============================================================
// HIX_ShowError — manejador principal de errores HTTP.
// 1. Escribe log en disco.
// 2. JSON → responde JSON directo.
// 3. HTML → intenta template errorsys via UView (si esta config).
// Si el template falla → pagina de "errorsys design error".
// Si no hay template → renderer interno HIX_ErrorSys.
// ============================================================
FUNCTION HIX_ShowError( oErr, oReq )

   LOCAL cHtml, nCode, cDesc, hErrData, oDesignErr

   _HixWriteErrorLog( oErr )

   IF HIX_WantsJson( oReq )

      IF ValType( oErr ) == "O"

         cDesc := hb_defaultValue( oErr:Description, "Internal Error" )
         IF ! Empty( oErr:Operation ) .AND. !( hb_ValToStr( oErr:Operation ) $ cDesc )
            cDesc += " (" + hb_ValToStr( oErr:Operation ) + ")"
         ENDIF
         nCode := hb_defaultValue( oErr:SubCode, 500 )
         
      ELSE
      
         cDesc := hb_CStr( oErr )
         nCode := 500

      ENDIF

      IF nCode < 400 .OR. nCode > 599 ; nCode := 500 ; ENDIF

      oReq:Respond( { "error" => cDesc, "code" => nCode }, nCode )
      RETURN NIL

   ENDIF

   IF ! Empty( s_cErrorSysFile ) .AND. ;
         hb_FileExists( hb_dirbase() + UConfig( "paths", "root", "www" ) + hb_ps() + s_cErrorSysFile )

      hErrData := _HixBuildErrorHash( oErr )
      HB_HCaseMatch( hErrData, .F. )

      TRY

         cHtml := _HixRenderErrorSys( s_cErrorSysFile, hErrData )
         
      CATCH oDesignErr
      
         cHtml := _HixErrorSysDesignError( oDesignErr, oErr )

      END

   ENDIF

   IF ValType( cHtml ) != "C" .OR. Empty( cHtml )

      cHtml := HIX_ErrorSys( oErr )

   ENDIF

   oReq:Respond( cHtml, 500, "html" )

RETURN NIL

// ============================================================
// _HixRenderErrorSys — ejecuta el template errorsys via HIX_View_Viewer.
// Separado para que el CATCH en HIX_ShowError lo envuelva limpio.
// ============================================================
STATIC FUNCTION _HixRenderErrorSys( cFile, hErrData )

   LOCAL oView, cHtml

   oView                  := HIX_View_Viewer():New()
   oView:lCache           := .T.
   oView:lDebug           := .F.
   oView:lStrictMode      := .T.
   
   // Poner .T. si necesitas analizar el fichero .prg transpilado en disco
   oView:llSaveTranspiled := .F.
   oView:SetPathView( hb_dirbase() + UConfig( "paths", "root", "www" ) + hb_ps() )
   oView:SetPrg( cFile )
   
   cHtml := oView:Render( hErrData )

RETURN cHtml

// ============================================================
// _HixBuildErrorHash — extrae campos del objeto error a un hash.
// El template errorsys recibe este hash como parametro @args hErr.
// Si oErr:cargo es un hash (error de vista), sus campos se fusionan.
// ============================================================
STATIC FUNCTION _HixBuildErrorHash( oErr )

   LOCAL hErr := { => }
   LOCAL hCargo


   IF ValType( oErr ) == "O"

      // hErr[ "args" ] := hb_defaultValue( oErr:args, "" )
      hErr[ "args" ] := oErr:args

      hErr[ "description" ] := hb_defaultValue( oErr:Description, "" )
      hErr[ "subsystem"   ] := hb_defaultValue( oErr:SubSystem,   "" )
      hErr[ "operation"   ] := hb_defaultValue( oErr:Operation,   "" )
      hErr[ "subCode"     ] := hb_defaultValue( oErr:SubCode,     0  )
      hErr[ "severity"    ] := hb_defaultValue( oErr:Severity,    0  )

      IF __objHasData( oErr, "FILENAME" )

         hErr[ "file" ] := hb_defaultValue( oErr:FileName, "" )
         
      ELSE
      
         hErr[ "file" ] := ""

      ENDIF

      IF __objHasData( oErr, "PROCLINE" )

         hErr[ "line" ] := hb_defaultValue( oErr:ProcLine, 0 )
         
      ELSE
      
         hErr[ "line" ] := 0

      ENDIF

      // Campos extra de vista (cargo hash)

      IF ValType( oErr:cargo ) == "H"

         hCargo := oErr:cargo
         hErr[ "system"    ] := hb_HGetDef( hCargo, "system",    "" )
         hErr[ "process"   ] := hb_HGetDef( hCargo, "process",   "" )
         hErr[ "lineCode"  ] := hb_HGetDef( hCargo, "line_code", "" )
         hErr[ "aCode"     ] := hb_HGetDef( hCargo, "aCode",     {} )
         hErr[ "viewCode"  ] := hb_HGetDef( hCargo, "view_code", 0  )
         hErr[ "module"    ] := hb_HGetDef( hCargo, "module",    "" )

         IF hErr[ "line" ] == 0

            hErr[ "line" ] := hb_HGetDef( hCargo, "line", 0 )

         ENDIF

      ELSE
         hErr[ "system"   ] := ""
         hErr[ "process"  ] := ""
         hErr[ "lineCode" ] := ""
         hErr[ "aCode"    ] := {}
         hErr[ "viewCode" ] := 0
         hErr[ "module"   ] := ""

      ENDIF

   ELSE
   
      hErr[ "description" ] := hb_CStr( oErr )
      hErr[ "subsystem"   ] := ""
      hErr[ "operation"   ] := ""
      hErr[ "subCode"     ] := 500
      hErr[ "severity"    ] := 0
      hErr[ "file"        ] := ""
      hErr[ "line"        ] := 0
      hErr[ "system"      ] := ""
      hErr[ "process"     ] := ""
      hErr[ "lineCode"    ] := ""
      hErr[ "aCode"       ] := {}

   ENDIF

   // Fallback: si aCode viene vacio pero tenemos file + line, leer el
   // fichero fuente para que tanto renderer interno como template custom
   // dispongan del snippet.

   IF ( ValType( hErr[ "aCode" ] ) != "A" .OR. Len( hErr[ "aCode" ] ) == 0 ) ;
         .AND. hErr[ "line" ] > 0 .AND. ! Empty( hErr[ "file" ] )

      hErr[ "aCode" ] := _HixReadSourceLines( hErr[ "file" ] )

   ENDIF

RETURN hErr

// ============================================================
// _HixReadSourceLines — lee un .prg / .html y devuelve array de
// lineas. Resuelve relativo -> absoluto via hb_dirbase().
// Devuelve {} si el fichero no existe o no es legible.
// ============================================================
STATIC FUNCTION _HixReadSourceLines( cFile )

   LOCAL cAbs := cFile
   LOCAL cSrc

   IF Empty( cAbs )

      RETURN {}

   ENDIF

   IF !( SubStr( cAbs, 2, 1 ) == ":" .OR. ;
         Left( cAbs, 1 ) == "/" .OR. Left( cAbs, 1 ) == "\" )

      cAbs := hb_dirbase() + cAbs

   ENDIF

   IF ! hb_FileExists( cAbs )

      RETURN {}

   ENDIF

   cSrc := hb_MemoRead( cAbs )

RETURN hb_ATokens( StrTran( cSrc, Chr( 13 ), "" ), Chr( 10 ) )

// ============================================================
// _HixErrorSysDesignError — pagina de error cuando el template
// errorsys personalizado falla. Muestra el error original + el
// error de diseno, sin usar el motor de views (para no volver a fallar).
// ============================================================
STATIC FUNCTION _HixErrorSysDesignError( oDesign, oOrig )

   LOCAL cOrig, cDesign, cStyle, cHtml          
   /*
   LOCAL cStyle := "body{font-family:monospace;padding:1.5em;background:#1a0000;color:#eee}" + ;
      "h1{color:#f88;margin:0}h2{color:#fc8;font-size:.9em;margin:.5em 0}" + ;
      "table{border-collapse:collapse;margin:.5em 0}td{padding:.15em .6em}" + ;
      "td:first-child{color:#aaa;text-align:right}hr{border-color:#444}" + ;
      ".box{background:#111;border:1px solid #444;padding:.8em;margin:.5em 0}"
   */
   
   BLOCK TO cStyle RAW    
body { 
   font-family:monospace;
   padding:1.5em;
   background:#1a0000;color:#eee;
}
h1 { 
   color:#f88;
   margin:0
}
h2 {
   color:#fc8;
   font-size:.9em;
   margin:.5em 0
}
table { 
   border-collapse:collapse;
   margin:.5em 0
}
td { 
   padding:.15em .6em
}
td:first-child { 
   color:#aaa;
   text-align:right
}
hr { 
   border-color:#444
}
.box { 
   background:#111;
   border:1px solid #444;
   padding:.8em;
   margin:.5em 0
}   
   ENDTEXT

   IF ValType( oOrig ) == "O"

      cOrig := hb_defaultValue( oOrig:Description, "" ) + ;
         iif( !Empty( hb_defaultValue( oOrig:FileName, "" ) ), ;
         " (" + oOrig:FileName + ")", "" )
   ELSE
      cOrig := hb_CStr( oOrig )

   ENDIF

   IF ValType( oDesign ) == "O"

      // cDesign := hb_defaultValue( oDesign:Description, "" ) + ;
      // iif( !Empty(hb_defaultValue(oDesign:FileName,"")), ;
      // " (" + oDesign:FileName + ")", "" )
      cDesign := 'Description: ' + oDesign:description
      cDesign += '<br>Operation: ' + oDesign:operation
   ELSE
      cDesign := hb_CStr( oDesign )

   ENDIF
   
   BLOCK TO cHtml RAW PARAMS cStyle, cOrig, s_cErrorSysFile, cDesign
<!DOCTYPE html>
<html>
   <head>
      <title>Errorsys Design Error</title>
      <style><$ cStyle $></style>
   </head>
   <body>
      <h1>Errorsys Design Error</h1><hr>
      <h2>El template errorsys personalizado ha fallado</h2>
      <div class='box'>
         <b>Error original de la aplicacion:</b><br><$ UHtmlEncode( cOrig ) $>
         </div>
         <div class='box'>
            <b>Error template errorsys ( <$ UHtmlEncode( s_cErrorSysFile ) $>):</b><br>
            <$ cDesign $>
         </div>
         
         <hr>
         <small>HIX Web Server — revisar el template errorsys</small>
   </body>
</html>
   ENDTEXT
   
RETURN cHtml 
/*
RETURN "<!DOCTYPE html><html><head><title>Errorsys Design Error</title>" + ;
      "<style>" + cStyle + "</style></head><body>" + ;
      "<h1>Errorsys Design Error</h1><hr>" + ;
      "<h2>El template errorsys personalizado ha fallado.</h2>" + ;
      "<div class='box'>" + ;
      "<b>Error original de la aplicacion:</b><br>" + UHtmlEncode( cOrig ) + ;
      "</div>" + ;
      "<div class='box'>" + ;
      "<b>Error template errorsys (" + UHtmlEncode( s_cErrorSysFile ) + "):</b><br>" + ;
      cDesign + ;  // UHtmlEncode( cDesign ) + ;
      "</div>" + ;
      "<hr><small>HIX Web Server — revisar el template errorsys</small>" + ;
      "</body></html>"
*/

// ============================================================
// _HixWriteErrorLog — append al fichero errors.log unico.
// Sin efecto si HIX_ErrorLogInit no fue llamado.
// ============================================================
STATIC FUNCTION _HixWriteErrorLog( oErr )

   LOCAL dNow, cDesc, cFileName, cLine, cSub, cOp, nSub, nSev, cEntry

   IF s_hErrLog == NIL .OR. s_hErrLog == F_ERROR

      RETURN NIL

   ENDIF

   IF ValType( oErr ) == "O"

      cDesc     := hb_defaultValue( oErr:Description, "" )

      IF __objHasData( oErr, "FILENAME" )

         cFileName := hb_defaultValue( oErr:FileName, "" )
      ELSE
         cFileName := ""

      ENDIF

      IF __objHasData( oErr, "PROCLINE" )

         cLine := hb_NToS( hb_defaultValue( oErr:ProcLine, 0 ) )
      ELSE
         cLine := "0"

      ENDIF

      cSub := hb_defaultValue( oErr:SubSystem, "" )
      cOp  := hb_defaultValue( oErr:Operation, "" )
      nSub := hb_defaultValue( oErr:SubCode,   0  )
      nSev := hb_defaultValue( oErr:Severity,  0  )
   ELSE
      cDesc := hb_CStr( oErr )
      cFileName := "" ; cLine := "0" ; cSub := "" ; cOp := "" ; nSub := 0 ; nSev := 0

   ENDIF

   dNow := hb_DateTime()
   s_nErrLogSeq++

   cEntry := "=== Error #" + hb_NToS( s_nErrLogSeq ) + " — " + dtoc( date() ) + ' ' + time() + " ===" + hb_eol() + ;
      "Subsystem  : " + cSub              + hb_eol() + ;
      "SubCode    : " + hb_NToS( nSub )   + hb_eol() + ;
      "Severity   : " + hb_NToS( nSev )   + hb_eol() + ;
      "Description: " + cDesc             + hb_eol() + ;
      "Operation  : " + cOp               + hb_eol() + ;
      "File       : " + cFileName + ":" + cLine + hb_eol() + ;
      hb_eol()

   hb_mutexLock( s_oErrMutex )
   FWrite( s_hErrLog, cEntry )
   hb_mutexUnlock( s_oErrMutex )

RETURN NIL

// ============================================================
// _HixDefaultErrorHtml — pagina de error interna (ASCII-only)
// ============================================================
STATIC FUNCTION _HixDefaultErrorHtml( oErr )

   LOCAL cDesc, cFile, cLine, cSub, cOp

   IF ValType( oErr ) == "O"

      cDesc := hb_defaultValue( oErr:Description, "" )
      cFile := hb_defaultValue( oErr:FileName,    "" )

      IF __objHasData( oErr, "PROCLINE" )

         cLine := hb_NToS( hb_defaultValue( oErr:ProcLine, 0 ) )
      ELSE
         cLine := '0'

      ENDIF

      cSub  := hb_defaultValue( oErr:SubSystem,   "" )
      cOp   := hb_defaultValue( oErr:Operation,   "" )
   ELSE
      cDesc := hb_CStr( oErr )
      cFile := ""
      cLine := ""
      cSub  := ""
      cOp   := ""

   ENDIF

   // _d( '_HixDefaultErrorHtml===>>', oErr )

RETURN _w( oErr )
/*
RETURN ;
   "<!DOCTYPE html><html><head>" + ;
   "<title>Error " + ltrim(str( oErr:subcode ))  + "</title>" + ;
   "<style>body{font-family:monospace;padding:2em;background:#111;color:#eee}" + ;
   "h1{color:#f66}table{border-collapse:collapse;margin-top:1em}" + ;
   "th{text-align:left;padding:.3em 1em .3em 0;color:#aaa}" + ;
   "td{padding:.3em 0;word-break:break-all}" + ;
   "hr{border-color:#333}</style></head><body>" + ;
   "<h1>HIX Error: " + ltrim(str( oErr:subcode ))  + "</h1><hr>" + ;
   "<table>" + ;
   "<tr><th>Time</th><td>" + dtoc(date()) + ' ' + time() + "</td></tr>" + ;
   "<tr><th>Error</th><td>" + UHtmlEncode( cDesc ) + "</td></tr>" + ;
   "<tr><th>File</th><td>"  + UHtmlEncode( cFile ) + "</td></tr>" + ;
   if ( ! empty( cLine ) .and. cLine <> '0' , ;
  "<tr><th>File</th><td>"  + cLine + "</td></tr>", '' ) + ;
   "<tr><th>Subsystem</th><td>" + UHtmlEncode( cSub ) + "</td></tr>" + ;
   "<tr><th>Operation</th><td>" + UHtmlEncode( cOp  ) + "</td></tr>" + ;
   "</table><hr><small>HIX Web Server</small>" + ;
   "</body></html>"
*/
// ============================================================
// HIX_NewError — fabrica un objeto Error de Harbour estandar.
//
// oErr := HIX_NewError( "Token inesperado", "Parser", 9002, "Parse" )
// HIX_Throw( oErr )
//
// Parametros opcionales: cSubSystem, nSubCode, cOperation.
// FileName/Line se rellenan automaticamente con el llamador (nivel 1).
// ============================================================
FUNCTION HIX_NewError( cDescription, cSubSystem, nSubCode, cOperation, cFile )

   LOCAL oErr

   hb_default( @cDescription, "" )
   hb_default( @cSubSystem,   "HIX" )
   hb_default( @nSubCode,     0 )
   hb_default( @cOperation,   "" )
   hb_default( @cFile,   ProcFile( 1 ) )

   oErr              := ErrorNew()
   oErr:SubSystem    := cSubSystem
   oErr:SubCode      := nSubCode
   oErr:GenCode      := EG_ARG
   oErr:Severity     := ES_ERROR
   oErr:Description  := cDescription
   oErr:Operation    := cOperation
   oErr:FileName     := cFile
   // oErr:Line         := ProcLine( 1 )

RETURN oErr

// ============================================================
// HIX_Throw — lanza un objeto Error a traves del mecanismo
// estandar de Harbour.
//
// HIX_Throw( HIX_NewError( "Acceso denegado", "Auth", 403 ) )
//
// Dentro de un TRY/CATCH el CATCH lo recoge normalmente.
// HIX_ShowError lo procesara si llega al worker HTTP.
// ============================================================
FUNCTION HIX_Throw( oErr )

   Break( oErr )

RETURN NIL

// ============================================================
// HIX_HttpError — responde con el error HTTP correcto segun
// el tipo de cliente: JSON para API/AJAX, HTML para navegador.
// nStatus : codigo HTTP (403, 404, 405, 429, 503...)
// cDetail : info extra opcional (ej. metodos permitidos en 405)
// ============================================================
FUNCTION HIX_HttpError( oReq, nStatus, cDetail )

   LOCAL cMsg := HIX_StatusText( nStatus )

   hb_default( @cDetail, "" )

   IF nStatus == 404 .AND. Empty( cDetail ) .AND. ValType( oReq ) == "O" .AND. ! Empty( oReq:cPath )

      cDetail := "Route: " + oReq:cPath

   ENDIF

   IF nStatus == 403 .AND. HIX_HixstyleDormant() .AND. ;
      UConfig( "app", "env", "prod" ) == "dev"

      IF ! Empty( cDetail ) ; cDetail += "  --  " ; ENDIF
      cDetail += _( "HIXSTYLE_DORMANT_HINT" )

   ENDIF

   IF HIX_WantsJson( oReq )

      IF Empty( cDetail )

         oReq:Respond( { "error" => cMsg }, nStatus )
      ELSE
         oReq:Respond( { "error" => cMsg, "detail" => cDetail }, nStatus )

      ENDIF

   ELSE
      oReq:Respond( HIX_HttpErrorHtml( nStatus, cMsg, cDetail ), nStatus, "html" )

   ENDIF

RETURN NIL

FUNCTION HIX_StatusText( nStatus )

   DO CASE

      CASE nStatus == 100 ; RETURN "Continue"
      CASE nStatus == 101 ; RETURN "Switching Protocols"
      CASE nStatus == 102 ; RETURN "Processing"
      CASE nStatus == 103 ; RETURN "Early Hints"
      CASE nStatus == 200 ; RETURN "OK"
      CASE nStatus == 201 ; RETURN "Created"
      CASE nStatus == 202 ; RETURN "Accepted"
      CASE nStatus == 203 ; RETURN "Non-Authoritative Information"
      CASE nStatus == 204 ; RETURN "No Content"
      CASE nStatus == 205 ; RETURN "Reset Content"
      CASE nStatus == 206 ; RETURN "Partial Content"
      CASE nStatus == 207 ; RETURN "Multi-Status"
      CASE nStatus == 208 ; RETURN "Already Reported"
      CASE nStatus == 226 ; RETURN "IM Used"
      CASE nStatus == 300 ; RETURN "Multiple Choices"
      CASE nStatus == 301 ; RETURN "Moved Permanently"
      CASE nStatus == 302 ; RETURN "Found"
      CASE nStatus == 303 ; RETURN "See Other"
      CASE nStatus == 304 ; RETURN "Not Modified"
      CASE nStatus == 307 ; RETURN "Temporary Redirect"
      CASE nStatus == 308 ; RETURN "Permanent Redirect"
      CASE nStatus == 400 ; RETURN "Bad Request"
      CASE nStatus == 401 ; RETURN "Unauthorized"
      CASE nStatus == 402 ; RETURN "Payment Required"
      CASE nStatus == 403 ; RETURN "Forbidden"
      CASE nStatus == 404 ; RETURN "Not Found"
      CASE nStatus == 405 ; RETURN "Method Not Allowed"
      CASE nStatus == 406 ; RETURN "Not Acceptable"
      CASE nStatus == 407 ; RETURN "Proxy Authentication Required"
      CASE nStatus == 408 ; RETURN "Request Timeout"
      CASE nStatus == 409 ; RETURN "Conflict"
      CASE nStatus == 410 ; RETURN "Gone"
      CASE nStatus == 411 ; RETURN "Length Required"
      CASE nStatus == 412 ; RETURN "Precondition Failed"
      CASE nStatus == 413 ; RETURN "Payload Too Large"
      CASE nStatus == 414 ; RETURN "URI Too Long"
      CASE nStatus == 415 ; RETURN "Unsupported Media Type"
      CASE nStatus == 416 ; RETURN "Range Not Satisfiable"
      CASE nStatus == 417 ; RETURN "Expectation Failed"
      CASE nStatus == 418 ; RETURN "I'm a teapot"
      CASE nStatus == 421 ; RETURN "Misdirected Request"
      CASE nStatus == 422 ; RETURN "Unprocessable Entity"
      CASE nStatus == 423 ; RETURN "Locked"
      CASE nStatus == 424 ; RETURN "Failed Dependency"
      CASE nStatus == 425 ; RETURN "Too Early"
      CASE nStatus == 426 ; RETURN "Upgrade Required"
      CASE nStatus == 428 ; RETURN "Precondition Required"
      CASE nStatus == 429 ; RETURN "Too Many Requests"
      CASE nStatus == 431 ; RETURN "Request Header Fields Too Large"
      CASE nStatus == 451 ; RETURN "Unavailable For Legal Reasons"
      CASE nStatus == 500 ; RETURN "Internal Server Error"
      CASE nStatus == 501 ; RETURN "Not Implemented"
      CASE nStatus == 502 ; RETURN "Bad Gateway"
      CASE nStatus == 503 ; RETURN "Service Unavailable"
      CASE nStatus == 504 ; RETURN "Gateway Timeout"
      CASE nStatus == 505 ; RETURN "HTTP Version Not Supported"
      CASE nStatus == 506 ; RETURN "Variant Also Negotiates"
      CASE nStatus == 507 ; RETURN "Insufficient Storage"
      CASE nStatus == 508 ; RETURN "Loop Detected"
      CASE nStatus == 510 ; RETURN "Not Extended"
      CASE nStatus == 511 ; RETURN "Network Authentication Required"

   ENDCASE

RETURN "Unknown"

FUNCTION HIX_HttpErrorHtml( nStatus, cMsg, cDetail )

   LOCAL cHtml := ''
   LOCAL cCode := hb_NToS( nStatus )
   LOCAL cFile
   LOCAL cBody := "<h1>" + cCode + " " + UHtmlEncode( cMsg ) + "</h1>"

   cFile := UConfig( "paths", "root", "www" ) + "/errors/error_" + cCode + ".html"

   IF hb_vfExists( cFile )

      RETURN hb_MemoRead( cFile )

   ENDIF   

   IF ! Empty( cDetail )

      cBody += "<h2 style='color:#c00'><small>" + UHtmlEncode( cDetail ) + "</small></h2>"

   ENDIF

   BLOCK TO cHtml RAW PARAMS cCode, cMsg, cBody      
<!DOCTYPE html>
<html>
<head>
   <title><$ cCode + " " + cMsg $></title>
   <style>
      body { 
         font-family:sans-serif;
         padding:2em;
         color:#333 
         }
      h1 { color:#c00 }
   </style>
</head>
<body>
   <$ cBody $>
   <hr>
   <small>HIX Web Server</small>
</body>
</html>      
   ENDTEXT 
   
RETURN cHtml 
/*   
RETURN "<!DOCTYPE html><html><head><title>" + cCode + " " + cMsg + "</title>" + ;
      "<style>body{font-family:sans-serif;padding:2em;color:#333}h1{color:#c00}</style></head>" + ;
      "<body>" + cBody + "<hr><small>HIX Web Server</small></body></html>"
*/

// ============================================================
// UHtmlEncode — escapa caracteres HTML en una sola pasada.
// & se procesa primero para no doblar-escapar los siguientes.
// ============================================================
FUNCTION UHtmlEncode( cText )

   IF Empty( cText )

      RETURN ""

   ENDIF

RETURN hb_StrReplace( cText, { ;
      "&"  => "&amp;", ;
      "<"  => "&lt;", ;
      ">"  => "&gt;", ;
      '"'  => "&quot;", ;
      "'"  => "&#39;"     ;
      } )

// ============================================================
FUNCTION HIX_ErrorName( nCode )

   DO CASE

      CASE nCode == HIX_ERR_OK       ; RETURN "OK"
      CASE nCode == HIX_ERR_SOCKET   ; RETURN "ERR_SOCKET"
      CASE nCode == HIX_ERR_TIMEOUT  ; RETURN "ERR_TIMEOUT"
      CASE nCode == HIX_ERR_PROTOCOL ; RETURN "ERR_PROTOCOL"
      CASE nCode == HIX_ERR_POOL_FULL; RETURN "ERR_POOL_FULL"
      CASE nCode == HIX_ERR_CONFIG   ; RETURN "ERR_CONFIG"
      CASE nCode == HIX_ERR_SSL      ; RETURN "ERR_SSL"

   ENDCASE

RETURN "ERR_UNKNOWN"
