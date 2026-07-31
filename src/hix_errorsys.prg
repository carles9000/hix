/*-----------------------------------------------------------
  File ......: hix_errorsys.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: View engine error renderer. Entry point ShowError(oError)
               is compatible with HIX_ErrorSysInit().
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#INCLUDE "hix_const.ch"

// ============================================================
// ShowError — Harbour VM fallback error block (last resort).
// If a request is active and not yet responded, delegate to
// HIX_ShowError so the client gets an HTTP response instead
// of hanging. Then return the rendered HTML for the VM.
// ============================================================
FUNCTION ShowError( oError )

   LOCAL oReq := HIX_GetRequest()

   IF oReq != NIL .AND. ! oReq:lResponded

      HIX_ShowError( oError, oReq )

   ENDIF

RETURN HIX_ErrorSys( oError )

// ============================================================
// HIX_ErrorSys — dispatcher: elige entre dev y prod segun env
// ============================================================
FUNCTION HIX_ErrorSys( oError )

   LOCAL lDev := UConfig( "app", "env", "dev" ) == "dev"

   IF ValType( oError ) != "O"

      IF lDev

         RETURN _HixErrHead( "HIX Error" ) + _HixErrLogo( "Error" ) + "</body></html>"

      ENDIF

      RETURN HIX_HttpErrorHtml( 500, HIX_StatusText( 500 ), "" )

   ENDIF

   IF lDev

      RETURN HIX_ErrorSysDev( oError )

   ENDIF

RETURN HIX_ErrorSysProd( oError )

// ============================================================
// HIX_ErrorSysDev — pagina detallada para entorno de desarrollo
// Lee campos estandar del ERROR + datos extra del cargo hash
// (system, module, process, line, line_code, aCode, ...).
// ============================================================
FUNCTION HIX_ErrorSysDev( oError )

   LOCAL cHtml
   LOCAL hExtra, cSystem, cProcess, nLine, cLineCode, aCode
   LOCAL nViewCode, cModule
   LOCAL nStart, nEnd, n, xLine, cLine, nIdx, nShow
   LOCAL cSrcFile, cSrc

   // Extraer datos extra de vista si cargo es hash

   IF ValType( oError:cargo ) == "H"

      hExtra := oError:cargo
   ELSE
      hExtra := { => }

   ENDIF

   cSystem   := HB_HGetDef( hExtra, "system",    "" )
   cModule   := HB_HGetDef( hExtra, "module",    "" )
   cProcess  := HB_HGetDef( hExtra, "process",   "" )
   nViewCode := HB_HGetDef( hExtra, "view_code", 0  )
   nLine     := HB_HGetDef( hExtra, "line",       0  )
   cLineCode := HB_HGetDef( hExtra, "line_code",  "" )
   aCode     := HB_HGetDef( hExtra, "aCode",      {} )
   // Fallback para errores no-vista: si el cargo no traia line, probamos
   // oError:ProcLine y oError:Line con TRY (algunas clases de error de
   // Harbour no exponen esos metodos).

   IF nLine == 0

      TRY

         IF ValType( oError:ProcLine ) == "N"

            nLine := oError:ProcLine

         ENDIF

      CATCH

      END

   ENDIF

   IF nLine == 0

      TRY

         IF ValType( oError:Line ) == "N"

            nLine := oError:Line

         ENDIF

      CATCH

      END

   ENDIF

   // line_index es el indice en aLineMap; si falta, cae en nLine
   nIdx      := HB_HGetDef( hExtra, "line_index", nLine )

   cHtml := _HixErrHead( "HIX Error" )
   cHtml += _HixErrLogo( "Application Error" )
   cHtml += "<table class='table table-bordered table-striped'>" + hb_eol()

   // cHtml += "<thead class='table-secondary'><tr><th>Field</th><th>Value</th></tr></thead>" + hb_eol()

   cHtml += _HixErrRow( "Time", DToC( Date() ) + " " + Time() )
   cHtml += _HixErrRow( "Mode", "Developer" )

   IF ! Empty( cSystem )

      cHtml += _HixErrRow( "System",  UHtmlEncode( cSystem ) )

   ENDIF

   IF ! Empty( cModule )

      cHtml += _HixErrRow( "Module",  UHtmlEncode( cModule ) )

   ENDIF

   IF ! Empty( cProcess )

      cHtml += _HixErrRow( "Process", UHtmlEncode( cProcess ) )

   ENDIF

   IF ! Empty( hb_CStr( oError:description ) )

      cHtml += _HixErrRow( "Description", UHtmlEncode( hb_CStr( oError:description ) ) )

   ENDIF

   IF nLine > 0

      cHtml += _HixErrRow( "Line", hb_NToS( nLine ) )

   ENDIF

   IF ! Empty( cLineCode )

      cHtml += _HixErrRow( "Code", "<code>" + UHtmlEncode( cLineCode ) + "</code>" )

   ENDIF

   IF ! Empty( hb_CStr( oError:subSystem ) )

      cHtml += _HixErrRow( "Subsystem", UHtmlEncode( hb_CStr( oError:subSystem ) ) )

   ENDIF

   IF ! Empty( hb_CStr( oError:operation ) )

      cHtml += _HixErrRow( "Operation", UHtmlEncode( hb_CStr( oError:operation ) ) )

   ENDIF

   IF ! Empty( hb_CStr( oError:filename ) )

      cHtml += _HixErrRow( "File", UHtmlEncode( hb_CStr( oError:filename ) ) )

   ENDIF

   IF nViewCode > 0

      cHtml += _HixErrRow( "View Code", hb_NToS( nViewCode ) )

   ENDIF

   IF oError:subCode > 0

      cHtml += _HixErrRow( "HTTP Code", hb_NToS( oError:subCode ) )

   ENDIF

   cHtml += "</table>" + hb_eol()

   // Fallback para errores no-vista (loaders PRG, controllers, ...):
   // si no hay aCode pero tenemos filename + ProcLine, leer el fichero
   // fuente y construir un snippet directo. Se salta si algo no cuadra
   // (fichero inexistente, linea fuera de rango) para no pintar codigo
   // engañoso.

   IF ( ValType( aCode ) != "A" .OR. Len( aCode ) == 0 ) .AND. nLine > 0

      cSrcFile := ""

      TRY

         cSrcFile := hb_CStr( oError:filename )
      CATCH

      END

      // Resolver a absoluta si viene relativa (drive letter / raiz => absoluta ya)

      IF ! Empty( cSrcFile ) .AND. ;
            !( SubStr( cSrcFile, 2, 1 ) == ":" .OR. ;
            Left( cSrcFile, 1 ) == "/" .OR. Left( cSrcFile, 1 ) == "\" )

         cSrcFile := hb_dirbase() + cSrcFile

      ENDIF

      IF ! Empty( cSrcFile ) .AND. hb_FileExists( cSrcFile )

         cSrc := hb_MemoRead( cSrcFile )
         aCode := hb_ATokens( StrTran( cSrc, Chr( 13 ), "" ), Chr( 10 ) )
         nIdx := nLine

         IF nIdx > Len( aCode )

            aCode := {}
            nIdx  := 0

         ENDIF

      ENDIF

   ENDIF

   // Bloque de codigo fuente con linea resaltada.
   // Iteramos por indice de aLineMap (nIdx) pero mostramos como numero visible
   // aCode[n][1] — la linea original en el template.

   IF ValType( aCode ) == "A" .AND. Len( aCode ) > 0 .AND. nIdx > 0

      nStart := Max( nIdx - 3, 1 )
      nEnd   := Min( nIdx + 3, Len( aCode ) )
      cHtml += "<h3>Code</h3><hr><div class='code'><pre>"

      FOR n := nStart TO nEnd

         xLine := aCode[ n ]

         IF ValType( xLine ) == "A"

            nShow := xLine[ 1 ]
            cLine := hb_CStr( xLine[ 2 ] )
         ELSE
            nShow := n
            cLine := hb_CStr( xLine )

         ENDIF

         IF n == nIdx

            cHtml += '<span class="line_error">=> ' + StrZero( nShow, 4 ) + " " + UHtmlEncode( cLine ) + "</span>"
         ELSE
            cHtml += "   " + StrZero( nShow, 4 ) + " " + UHtmlEncode( cLine )

         ENDIF

         cHtml += hb_eol()

      NEXT

      cHtml += "</pre></div><hr>" + hb_eol()

   ENDIF

   cHtml += "</body></html>"

RETURN cHtml

// ============================================================
// HIX_ErrorSysProd — pagina reducida para produccion.
// Muestra solo Time, Mode y HTTP Code. Nunca filtra File,
// Operation, SubSystem o Description (pueden contener rutas
// absolutas, nombres de subsistemas internos y detalles del
// stacktrace que no deben salir del servidor).
// ============================================================
FUNCTION HIX_ErrorSysProd( oError )

   LOCAL cHtml
   LOCAL nCode := 500

   IF ValType( oError ) == "O" .AND. ValType( oError:subCode ) == "N" .AND. ;
      oError:subCode >= 100 .AND. oError:subCode <= 599

      nCode := oError:subCode

   ENDIF

   cHtml := _HixErrHead( "HIX Error" )
   cHtml += _HixErrLogo( "Application Error" )
   cHtml += "<table class='table table-bordered table-striped'>" + hb_eol()

   cHtml += _HixErrRow( "Time", DToC( Date() ) + " " + Time() )
   cHtml += _HixErrRow( "Mode", "Production" )
   cHtml += _HixErrRow( "HTTP Code", hb_NToS( nCode ) )

   cHtml += "</table>" + hb_eol()
   cHtml += "</body></html>"

RETURN cHtml

// ============================================================
// HIX_ErrorSysFallback — minimal self-contained error page.
// Last-resort renderer when an external error view fails to
// load or render. No CDN, no external assets, no dependencies
// on the view engine. Shows HTTP code, description, operation
// and file when available.
// ============================================================
FUNCTION HIX_ErrorSysFallback( oError )

   LOCAL nCode := 500
   LOCAL cDesc := ""
   LOCAL cOper := ""
   LOCAL cFile := ""
   LOCAL cHtml

   IF ValType( oError ) == "O"

      IF ValType( oError:subCode ) == "N" .AND. oError:subCode >= 100 .AND. oError:subCode <= 599

         nCode := oError:subCode

      ENDIF

      cDesc := hb_CStr( oError:description )
      cOper := hb_CStr( oError:operation )
      cFile := hb_CStr( oError:filename )

   ENDIF
   
   BLOCK TO cHtml RAW PARAMS nCode
<!DOCTYPE html>
<html>
   <head>
      <meta charset='UTF-8'>
      <title><$ hb_NToS( nCode ) + ' ' + UHtmlEncode( HIX_StatusText( nCode ) ) $></title>   
      <style>
         body { 
            font-family:system-ui,sans-serif;
            padding:2em;color:#222;
            background:#f7f7f7;
         }
         h1 { 
            color:#c00;margin:0 0 .3em;
            font-size:2.2em;
         }
         h2 {
            color:#555;margin:0 0 1.2em;
            font-weight:normal;font-size:1.1em;
         }
         dl { 
            background:#fff;
            border:1px solid #ddd;
            padding:1em 1.5em;
            max-width:900px;
         }
         dt { 
            font-weight:bold;
            color:#666;
            margin-top:.6em;
         }
         dd { 
            margin:.2em 0 .6em 0;
            font-family:Consolas,monospace;
            word-break:break-word;
         }
         footer { 
            margin-top:1.5em;
            color:#999;
            font-size:.85em;
         }
      </style>
   </head>
<body>   
   ENDTEXT 

   cHtml += "<h1>" + hb_NToS( nCode ) + " " + UHtmlEncode( HIX_StatusText( nCode ) ) + "</h1>" + hb_eol()
   cHtml += "<h2>HIX internal error page</h2>" + hb_eol()
   cHtml += "<dl>" + hb_eol()

   IF ! Empty( cDesc )

      cHtml += "<dt>Description</dt><dd>" + UHtmlEncode( cDesc ) + "</dd>" + hb_eol()

   ENDIF

   IF ! Empty( cOper )

      cHtml += "<dt>Operation</dt><dd>" + UHtmlEncode( cOper ) + "</dd>" + hb_eol()

   ENDIF

   IF ! Empty( cFile )

      cHtml += "<dt>File</dt><dd>" + UHtmlEncode( cFile ) + "</dd>" + hb_eol()

   ENDIF

   cHtml += "<dt>Time</dt><dd>" + DToC( Date() ) + " " + Time() + "</dd>" + hb_eol()
   cHtml += "</dl>" + hb_eol()
   cHtml += "<footer>HIX Web Server</footer>" + hb_eol()
   cHtml += "</body></html>"

RETURN cHtml

// ============================================================
// Helpers de presentacion HTML
// ============================================================

STATIC FUNCTION _HixErrHead( cTitle )

   LOCAL cHtml := ''
   
   BLOCK TO cHtml RAW PARAMS cTitle 
 <!DOCTYPE html>
 <html>
   <head>
     <meta charset='UTF-8'>
     <title><$ UHtmlEncode( cTitle ) $></title>
     <link rel='icon' href='https://raw.githubusercontent.com/carles9000/hix/main/resources/images/hix.ico' type='image/x-icon'>
     <link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css' rel='stylesheet'>
     <style>
       body { padding: 10px; }
       pre { margin-top: 0; margin-bottom: 0; }
       tbody { font-family: Consolas, monospace; }
       .col { text-align: right; font-weight: bold; }
       .contenedor { display: flex; align-items: center; gap: 20px; }
       .contenedor img { height: 40px; width: auto; }
       .title { font-size: 40px; font-weight: bold; font-family: system-ui; }
       .line_error { border: 1px solid red; padding: 0; font-weight: bold; }
     </style>
   </head>
   <body>   
   ENDTEXT 
   
return cHtml 


STATIC FUNCTION _HixErrLogo( cSubtitle )

   LOCAL cHtml := ''
   
   BLOCK TO cHtml RAW PARAMS cSubTitle 
<div class='contenedor'>
   <img src='https://raw.githubusercontent.com/carles9000/hix/main/resources/images/hix.png' alt='Logo HIX'>
   <span class='title'><$ UHtmlEncode( cSubtitle ) $></span>
   </div><hr>
   ENDTEXT 
   
return cHtml 

STATIC FUNCTION _HixErrRow( cLabel, cValue )
RETURN "<tr><td class='col'>" + UHtmlEncode( cLabel ) + "</td><td>" + cValue + "</td></tr>" + hb_eol()
