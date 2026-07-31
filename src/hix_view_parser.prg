/*-----------------------------------------------------------
  File ......: hix_view_parser.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: HIX view template parser — tokenizes source into directives,
               blocks and HTML.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#INCLUDE "hbclass.ch"
#INCLUDE "common.ch"
#INCLUDE "error.ch"

#INCLUDE "hix_const.ch"
#INCLUDE "hix_hrb.ch"

#DEFINE TYPE_HRB           "HRB"
#DEFINE TYPE_HRB_CMT       "HRB_CMT"
#DEFINE TYPE_HTML          "HTML"
#DEFINE TYPE_HTML_CMT      "HTML_CMT"
#DEFINE TYPE_TEXT          "TEXT"

#DEFINE ST_NORMAL          0
#DEFINE ST_PRG_BLOCK       3
#DEFINE ST_CMT_PRG         1
#DEFINE ST_CMT_HTML        2

#DEFINE PARSER_ERROR_LINE    1
#DEFINE PARSER_ERROR_TYPE     2
#DEFINE PARSER_ERROR_DESCRIPTION  3
#DEFINE PARSER_ERROR_CODE     4

// ------------------------------------------------------------
// SECCION 1: CLASE — DECLARACION Y CICLO DE VIDA
// ------------------------------------------------------------

CLASS HIX_Parser

   DATA aResult       // { nLinea, cTipo, cContenido }
   DATA aBlocks       // bloques @prg: { nLineaInicio, cContenido }
   DATA aPrgBlocks    // alias/acceso externo a bloques @prg
   DATA aSymbols      // { cNombre, cTipo, nLinea }  cTipo=ARG|GLOBAL
   DATA aErrors       // { nLinea, cNivel, cMensaje } cNivel=ERROR|WARN|INFO

   DATA nLineNum      // contador de linea actual durante Parse()
   DATA nState        // estado actual del parser (ST_*)
   DATA nPrgStartLine // linea donde se abrio el @prg actual
   DATA cPrgAccum     // acumulador de contenido del bloque @prg actual
   DATA cAccum        // acumulador para comentarios multilinea
   DATA nAccumLine    // linea de inicio del acumulador de comentarios

   DATA aDirectiveStack  // stack de directivas abiertas { cDir, nLinea }
   DATA cAccumType       // tipo de acumulador activo (TYPE_HRB o TYPE_HTML)
   DATA aDirectives      // lista de directivas HIX reconocidas

   DATA aSourceLines  // lineas raw del fuente (para aCode en errorsys)

   DATA lDebug        // .T. activa Trace*() — default .F.
   DATA lStrictMode   // .T. lanza excepcion en primer error — default .T.

   DATA aTraceTimes     // { { cNombre, nStart, nEnd, nMs, nCalls } }
   DATA hTraceTimes     // hash para acceso rápido por nombre

   METHOD New()
   METHOD Reset()
   METHOD End()

   METHOD Parse( cCode )

   // --- Metodos de procesamiento linea a linea ---
   METHOD ProcessLine( cLine )
   METHOD DetectLineType( cTrim )
   METHOD IsHarbourDirective( cLine )
   METHOD FlushAccum()
   METHOD StripTrailingComment( cLine )

   // --- Validaciones semanticas ---
   METHOD CheckSymbols()
   METHOD CheckBlockStack()
   METHOD CheckMacros()
   METHOD CheckExprSyntax()

   // --- Helpers de validacion ---
   METHOD ValidateMacroExpr( cExpr, nLine, aErrors )
   METHOD ValidateCondExpr( cExpr, cDir, nLine, aErrors )
   METHOD ValidateForExpr( cExpr, nLine, aErrors )
   METHOD ValidateForeachExpr( cExpr, nLine, aErrors )


   // --- Helpers de simbolos ---
   METHOD ExtractVarName( cVar )
   METHOD SplitArgs( cText )
   METHOD SplitOnAssign( cText )

   METHOD IsSymbolDeclared( cVar )
   METHOD HasSymbolType( cTipo )
   METHOD IsValidIdentifier( cName )
   METHOD IsSimpleVar( cExpr )

   // --- Helpers de estructura ---
   METHOD FindKeyword( cUpper, cKw )
   METHOD CloserOf( cDirectiva )
   METHOD PopDirective( cTag, nLine, cLine )

   METHOD IsPureHtml( cCode )

   METHOD InitTraceTime( cName )
   METHOD EndTraceTime( cName )

   // --- Debug / Trace ---
   METHOD TraceResult()
   METHOD TraceErrors()
   METHOD TraceSymbols()
   METHOD TraceTimes()

ENDCLASS


// ============================================================
// New()
// Constructor de la clase HIX_Parser. Inicializa el estado por
// defecto, define las directivas soportadas y configuración inicial.
//
// Ejemplo:
// oParser := HIX_Parser():New()
// ============================================================
METHOD New() CLASS HIX_Parser

   ::aDirectives := { ;
      "@IF", "@ELSE", "@ELSEIF", "@ENDIF", ;
      "@FOREACH", "@ENDFOREACH", ;
      "@FOR", "@NEXT", ;
      "@WHILE", "@ENDWHILE", ;
      "@PRG", "@ENDPRG", ;
      "@ARGS", "@GLOBAL", ;
      "@VIEW", "@CSS", "@JS", ;
      "@CSRF", "@RESOURCE" }

   ::Reset()
   ::lDebug      := .F.
   ::lStrictMode := .T.

RETURN Self


// ============================================================
// Reset()
// Limpia y restablece los contenedores internos y acumuladores
// para procesar un nuevo archivo desde cero, sin recrear clase.
//
// Ejemplo:
// oParser:Reset()
// ============================================================
METHOD Reset() CLASS HIX_Parser

   ::aResult          := {}
   ::aBlocks          := {}
   ::aPrgBlocks       := {}
   ::aSymbols         := {}
   ::aErrors          := {}
   ::aSourceLines     := {}
   ::aDirectiveStack := {}
   ::cAccumType       := ""
   ::nLineNum         := 0
   ::nState           := ST_NORMAL
   ::nPrgStartLine   := 0
   ::cPrgAccum        := ""
   ::cAccum           := ""
   ::nAccumLine       := 0
   ::aTraceTimes      := {}
   ::hTraceTimes      := { => }

RETURN NIL


// ============================================================
// End()
// Destructor parcial y liberación de memoria de las propiedades
// internas. Debe invocarse al desechar la instancia.
//
// Ejemplo:
// oParser:End()
// ============================================================
METHOD End() CLASS HIX_Parser

   ::aResult          := {}
   ::aBlocks          := {}
   ::aPrgBlocks       := {}
   ::aSymbols         := {}
   ::aErrors          := {}
   ::aDirectiveStack := {}
   ::cPrgAccum        := ""
   ::cAccum           := ""

RETURN NIL


// ============================================================
// Parse( cCode )
// Punto de entrada principal para el análisis léxico y sintáctico.
// Recibe el código fuente HIX/HTML y construye internamente los
// bloques, símbolos detectados y errores.
//
// Parámetros:
// cCode - Código fuente a analizar (String).
//
// Ejemplo:
// oParser:Parse( Memoread( "vista.prg" ) )
// ============================================================
METHOD Parse( cCode ) CLASS HIX_Parser

   LOCAL aLines, cLine, cNext
   LOCAL cTrimLine, oErrPrg
   LOCAL nIdx, nTotal
   LOCAL oErr, oErrView

   ::Reset()

   // Normalizar: quitar CR, convertir tabs en espacios
   ::InitTraceTime( 'PARSE_NORMALIZE' )
   cCode  := StrTran( cCode, Chr( 13 ), "" )
   cCode  := StrTran( cCode, Chr( 9 ),  " " )
   aLines           := hb_ATokens( cCode, Chr( 10 ) )
   ::aSourceLines  := aLines
   nTotal          := Len( aLines )
   ::EndTraceTime( 'PARSE_NORMALIZE' )

   // Indice numerico en lugar de FOR EACH
   // permite avanzar nIdx manualmente para multilinea con ";"
   ::InitTraceTime( 'PARSE_LOOP' )
   nIdx := 0

   WHILE nIdx < nTotal

      nIdx++
      cLine := aLines[ nIdx ]
      ::nLineNum++

      DO CASE

            // --- Bloque @prg: acumular hasta @endprg ---
            // El UNICO criterio de cierre es @endprg.
            // FUNCTION/RETURN internos son codigo valido dentro del bloque.
         CASE ::nState == ST_PRG_BLOCK

         IF Upper( AllTrim( cLine ) ) == "@ENDPRG"

            AAdd( ::aBlocks, { ::nPrgStartLine, ::cPrgAccum } )
            AAdd( ::aResult, { ::nPrgStartLine, TYPE_HRB, "@PRG BLOCK" + AllTrim( Str( Len( ::aBlocks ) ) ) } )
            ::PopDirective( "@PRG", ::nLineNum, cLine )
            ::nState    := ST_NORMAL
            ::cPrgAccum := ""
         ELSE
            cTrimLine := AllTrim( cLine )

            // Directivas HIX no permitidas dentro de @prg

            IF Left( Upper( cTrimLine ), 1 ) == "@" .AND. ::IsHarbourDirective( cTrimLine )

               AAdd( ::aErrors, { ::nLineNum, "ERROR", ;
                  "Directive '" + Upper( cTrimLine ) + "' not allowed inside @PRG " + ;
                  "(line " + AllTrim( Str( ::nLineNum ) ) + ", @PRG opened at line " + ;
                  AllTrim( Str( ::nPrgStartLine ) ) + ")", cTrimLine } )

               // Macros {{ }} y {!! !!} no permitidas dentro de @prg
            ELSEIF "{{" $ cTrimLine .OR. "{!!" $ cTrimLine
               AAdd( ::aErrors, { ::nLineNum, "ERROR", ;
                  "Macro not allowed inside @PRG " + ;
                  "(line " + AllTrim( Str( ::nLineNum ) ) + ", @PRG opened at line " + ;
                  AllTrim( Str( ::nPrgStartLine ) ) + ")", cTrimLine } )

            ENDIF

            ::cPrgAccum += cLine + Chr( 10 )

            ENDIF

            // --- Comentario Harbour multilinea: acumular hasta */ ---
         CASE ::nState == ST_CMT_PRG

            ::cAccum += Chr( 10 ) + cLine

         IF "*/" $ cLine

            ::nState := ST_NORMAL
            AAdd( ::aResult, { ::nAccumLine, TYPE_HRB_CMT, AllTrim( ::cAccum ), cLine } )
            ::cAccum := ""

            ENDIF

            // --- Comentario HTML multilinea: acumular hasta --> ---
         CASE ::nState == ST_CMT_HTML

            ::cAccum += Chr( 10 ) + cLine

         IF "-->" $ cLine

            ::nState := ST_NORMAL
            AAdd( ::aResult, { ::nAccumLine, TYPE_HTML_CMT, AllTrim( ::cAccum ), cLine } )
            ::cAccum := ""

            ENDIF

            // --- Estado normal ---
         OTHERWISE

            // Acumulacion de lineas con continuacion ";"
            // Solo aplica a directivas @ para soportar @if con condicion multilinea:
            // @if year(date()) > 2000 .and. ;
            // year(date()) > 1990
            cTrimLine := AllTrim( cLine )

         IF Left( cTrimLine, 1 ) == "@" .AND. Right( cTrimLine, 1 ) == ";"

            cLine := Left( cTrimLine, Len( cTrimLine ) - 1 )

            WHILE nIdx < nTotal

               nIdx++
               ::nLineNum++
               cNext := AllTrim( aLines[ nIdx ] )

               IF Right( cNext, 1 ) == ";"

                  cLine += " " + Left( cNext, Len( cNext ) - 1 )
               ELSE
                  cLine += " " + cNext
                  EXIT

               ENDIF

            ENDDO

         ELSEIF Left( cTrimLine, 1 ) == "@" .AND. Right( cTrimLine, 1 ) == "\"
            cLine := Left( cTrimLine, Len( cTrimLine ) - 1 )

            WHILE nIdx < nTotal

               nIdx++
               ::nLineNum++
               cNext := AllTrim( aLines[ nIdx ] )

               IF Right( cNext, 1 ) == "\"

                  cLine += " " + Left( cNext, Len( cNext ) - 1 )
               ELSE
                  cLine += " " + cNext
                  EXIT

               ENDIF

            ENDDO

            ENDIF

            ::ProcessLine( cLine )

      ENDCASE

   ENDDO

   ::EndTraceTime( 'PARSE_LOOP' )

   // Flush de HRB acumulado pendiente
   ::InitTraceTime( 'PARSE_FLUSHACCUM' )
   ::FlushAccum()
   ::EndTraceTime( 'PARSE_FLUSHACCUM' )

   // Validar si quedo un bloque @prg abierto al finalizar el fichero

   IF ::nState == ST_PRG_BLOCK

      AAdd( ::aErrors, { ::nPrgStartLine, "ERROR", ;
         "@PRG opened at line " + AllTrim( Str( ::nPrgStartLine ) ) + " was never closed (missing @ENDPRG)", "" } )

   ENDIF

   // Validaciones semanticas en orden de dependencia
   ::InitTraceTime( 'CHECK_SYMBOLS' )
   ::CheckSymbols()       // 1. construye ::aSymbols desde @args/@global
   ::EndTraceTime( 'CHECK_SYMBOLS' )

   ::InitTraceTime( 'CHECK_BLOCKSTACK' )
   ::CheckBlockStack()    // 2. verifica anidamiento de bloques
   ::EndTraceTime( 'CHECK_BLOCKSTACK' )

   ::InitTraceTime( 'CHECK_MACROS' )
   ::CheckMacros()        // 3. valida {{ }} usando ::aSymbols
   ::EndTraceTime( 'CHECK_MACROS' )

   ::InitTraceTime( 'CHECK_EXPRSYNTAX' )
   ::CheckExprSyntax()    // 4. valida condiciones de directivas
   ::EndTraceTime( 'CHECK_EXPRSYNTAX' )

   // Podemos tener varios errores. Si es lStrictMode == .T. generamos error
   // usando el primer registros de ::aErrors si existe

   IF ::lStrictMode .AND. Len( ::aErrors ) > 0

      oErrView := HIX_ErrorView( NIL, 9001, ::aErrors[ 1 ][ PARSER_ERROR_DESCRIPTION ], ;
         ::aErrors[ 1 ][ PARSER_ERROR_LINE ], ;
         ::aErrors[ 1 ][ PARSER_ERROR_CODE ], "hix_view_parser" )
      oErrView:cargo[ "aCode" ] := ::aSourceLines
      HIX_Throw( oErrView )

   ENDIF

   // En modo estricto: lanzar excepcion con el primer error
   // (desactivado: se usan aErrors para reportar sin lanzar)
   // IF ::lStrictMode .AND. Len( ::aErrors ) > 0 ...

RETURN ::aResult


// ------------------------------------------------------------
// SECCION 2b: PROCESAMIENTO DE LINEA
// ------------------------------------------------------------

// ============================================================
// ProcessLine( cLine )
// Clasifica y emite una línea del código fuente en estado normal.
// Gestiona el vaciado (flush) de lineas acumuladas dependiendo
// del bloque anterior (ej. comentarios multilinea).
//
// Parámetros:
// cLine - Línea a procesar (String)
//
// Ejemplo:
// ::ProcessLine( "<div>Texto</div>" )
// ============================================================
METHOD ProcessLine( cLine ) CLASS HIX_Parser

   LOCAL cTrim      := AllTrim( cLine )
   LOCAL cCleanLine
   LOCAL cType

   // Linea vacia: solo flush si hay HTML acumulado

   IF Empty( cTrim )

      IF ! Empty( ::cAccum ) .AND. ::cAccumType == TYPE_HTML

         ::FlushAccum()

      ENDIF

      RETURN Self

   ENDIF

   // Linea limpia (sin comentario trailing) — usada solo si se emite contenido
   cCleanLine := AllTrim( ::StripTrailingComment( cTrim ) )

   // Detectamos el tipo sobre la linea original para que // al inicio
   // sea reconocido como HRBCMT aunque StripTrailingComment la vacie
   cType := ::DetectLineType( cTrim )

   // DetectLineType retorna "" si ya gestiono la emision (ej: @prg)

   IF Empty( cType )

      RETURN Self

   ENDIF

   // Emitir directamente — el stack semantico lo verifica CheckBlockStack()

   IF cType == TYPE_HRB

      AAdd( ::aResult, { ::nLineNum, TYPE_HRB, cCleanLine } )
   ELSE
      AAdd( ::aResult, { ::nLineNum, cType, RTrim( cLine ) } )

   ENDIF

RETURN Self


// ============================================================
// DetectLineType( cTrim )
// Detecta el tipo semántico subyacente de la línea (HTML, Directiva, Comentario).
// Si identifica un bloque complejo (como @prg o comentarios multilinea),
// altera el estado de análisis global (::nState) de la clase HIX_Parser.
//
// Parámetros:
// cTrim - Línea despuntada sin espacios (String).
//
// Retorna:
// cType - Una constante identificadora (ej: TYPE_HRB, TYPE_HTML), o
// string vacío ("") si la emision es contenida internamente.
//
// Ejemplo:
// cType := oParser:DetectLineType( "@if a == b" )  // devuelve TYPE_HRB
// ============================================================
METHOD DetectLineType( cTrim ) CLASS HIX_Parser

   LOCAL cUp  := Upper( cTrim )
   LOCAL cType

   DO CASE

         // --- Apertura de bloque @prg ---
      CASE Left( cUp, 4 ) == "@PRG" .AND. ( Len( cUp ) == 4 .OR. !IsAlpha( SubStr( cUp, 5, 1 ) ) )
         ::nState        := ST_PRG_BLOCK
         ::nPrgStartLine := ::nLineNum
         ::cPrgAccum     := ""
         AAdd( ::aDirectiveStack, { "@PRG", ::nLineNum } )
         RETURN ""   // lo emitimos al cerrar con el indice del bloque

         // --- Directiva HIX ---
      CASE Left( cUp, 1 ) == "@" .AND. ::IsHarbourDirective( cTrim )
         cType := TYPE_HRB

         // --- Comentario Harbour inline: // ---
      CASE Left( cUp, 2 ) == "//"
         cType := TYPE_HRB_CMT

         // --- Comentario Harbour multilinea: /* ... */ ---
      CASE Left( cUp, 2 ) == "/*"
         cType := TYPE_HRB_CMT

      IF !( "*/" $ SubStr( cTrim, 3 ) )

         ::nState     := ST_CMT_PRG
         ::nAccumLine := ::nLineNum
         ::cAccum     := cTrim
         RETURN ""

         ENDIF

         // --- Comentario HTML: <!-- ... --> ---
      CASE Left( cUp, 4 ) == "<!--"
         cType := TYPE_HTML_CMT

      IF !( "-->" $ SubStr( cTrim, 5 ) )

         ::nState     := ST_CMT_HTML
         ::nAccumLine := ::nLineNum
         ::cAccum     := cTrim
         RETURN ""

         ENDIF

         // --- Por defecto: HTML/TEXT ---
      OTHERWISE

         cType := TYPE_HTML

   ENDCASE

RETURN cType


// ============================================================
// IsHarbourDirective( cLine )
// Comprueba si la línea comienza con una directiva HIX reconocida.
// Valida que sea palabra completa (no prefijo de otra variable).
//
// Parámetros:
// cLine - Línea a evaluar (String).
//
// Retorna:
// lBool - .T. si es directiva reconocida, .F. en caso contrario.
//
// Ejemplo:
// lIsHrb := oParser:IsHarbourDirective( "@if a == b" )
// ============================================================
METHOD IsHarbourDirective( cLine ) CLASS HIX_Parser

   LOCAL cUp  := Upper( AllTrim( cLine ) )
   LOCAL cDir, nLen, i

   FOR i := 1 TO Len( ::aDirectives )

      cDir := ::aDirectives[ i ]
      nLen := Len( cDir )

      IF Left( cUp, nLen ) == cDir

         IF Len( cUp ) == nLen .OR. ! IsAlpha( SubStr( cUp, nLen + 1, 1 ) )

            RETURN .T.

         ENDIF

      ENDIF

   NEXT

RETURN .F.

// ============================================================
// FlushAccum()
// Emite cualquier acumulación pendiente de líneas (como strings
// HTML multilinea o bloques). Restablece los buffers.
//
// Ejemplo:
// oParser:FlushAccum()
// ============================================================
METHOD FlushAccum() CLASS HIX_Parser

   IF ! Empty( ::cAccum )

      AAdd( ::aResult, { ::nAccumLine, ::cAccumType, AllTrim( ::cAccum ) } )
      ::cAccum     := ""
      ::cAccumType := ""

   ENDIF

RETURN Self


// ============================================================
// StripTrailingComment( cLine )
// Quita el comentario Harbour `//` al final de una línea, pero
// respetando inteligentemente los strings y URLs.
//
// Parámetros:
// cLine - Línea a procesar (String).
//
// Retorna:
// cText - Línea sin el comentario al final.
//
// Ejemplo:
// cCode := oParser:StripTrailingComment( 'cUrl := "http://"' )
// ============================================================
METHOD StripTrailingComment( cLine ) CLASS HIX_Parser

   LOCAL lInStr   := .F.
   LOCAL cStrChar := ""
   LOCAL cChar, cNext, i

   FOR i := 1 TO Len( cLine )

      cChar := SubStr( cLine, i, 1 )
      cNext := iif( i < Len( cLine ), SubStr( cLine, i + 1, 1 ), "" )

      IF lInStr

         IF cChar == cStrChar

            lInStr := .F.

         ENDIF

      ELSE

         DO CASE

            CASE cChar == '"' .OR. cChar == "'"
               lInStr   := .T.
               cStrChar := cChar
            CASE cChar == "/" .AND. cNext == "/"
               RETURN Left( cLine, i - 1 )

         ENDCASE

      ENDIF

   NEXT

RETURN cLine


// ============================================================
// CheckSymbols()
// Analiza el código buscando directivas `@args` y `@global` para
// registrar las variables expuestas en el array ::aSymbols.
//
// Formato matriz ::aSymbols:
// { cNombre, cTipo, nLinea, cNombreOriginal, cDefault }
// El 5º elemento (cDefault) contiene el valor por defecto
// si el argumento fue declarado con '=' o ':=', o "" si no.
//
// Ejemplo:
// oParser:CheckSymbols()
// ============================================================
METHOD CheckSymbols() CLASS HIX_Parser

   LOCAL aRow, cToken
   LOCAL cArgs, aNames, cName
   LOCAL aLocalErrors := {}
   LOCAL nPosAssign, nPosIn
   LOCAL aPair, cVarName, cDefault, lAccept

   ::aSymbols := {}

   FOR EACH aRow IN ::aResult

      IF !( aRow[ 2 ] == TYPE_HRB )

         LOOP

      ENDIF

      cToken := AllTrim( aRow[ 3 ] )

      DO CASE

// --- @args aData, cUser, lActive ---
// Soporta inicializadores opcionales con '=' o ':='
// Ejemplo: @args par1, hora := time(), data = 'pepe'
// Los valores pueden contener comas internas (arrays, hashes, funciones)
         CASE Upper( Left( cToken, 5 ) ) == "@ARGS"

            cArgs := AllTrim( SubStr( cToken, 6 ) )

         IF Empty( cArgs )

            AAdd( aLocalErrors, { aRow[ 1 ], "WARN", ;
               "@ARGS without parameters in line " + AllTrim( Str( aRow[ 1 ] ) ), cToken } )
            LOOP

            ENDIF

// @args solo puede aparecer una vez
// Podriem mirar de tenir varies linees en un futur TO-DO

         IF ::HasSymbolType( "ARG" )

            AAdd( aLocalErrors, { aRow[ 1 ], "ERROR", ;
               "Duplicate @ARGS at line " + AllTrim( Str( aRow[ 1 ] ) ) + ;
               " (already declared previously)", cToken } )
            LOOP

            ENDIF

// SplitArgs respeta anidamiento de (), [], {} y strings
            aNames := ::SplitArgs( cArgs )

         FOR EACH cName IN aNames

            IF Empty( cName ) ; LOOP ; ENDIF

// SplitOnAssign separa nombre del valor por defecto
// respetando anidamiento y operadores '=' vs ':='
            aPair    := ::SplitOnAssign( cName )
            cVarName := aPair[ 1 ]
            cDefault := aPair[ 2 ]

            IF ! ::IsValidIdentifier( cVarName )

               AAdd( aLocalErrors, { aRow[ 1 ], "ERROR", ;
                  "Variable name wrong in @ARGS: '" + cVarName + ;
                  "' (line " + AllTrim( Str( aRow[ 1 ] ) ) + ")", cVarName } )
            ELSEIF ::IsSymbolDeclared( cVarName )
               AAdd( aLocalErrors, { aRow[ 1 ], "WARN", ;
                  "Parameter '" + cVarName + "' duplicate in @ARGS " + ;
                  "(line " + AllTrim( Str( aRow[ 1 ] ) ) + ")", cVarName } )
            ELSE

               lAccept := .T.

               IF !empty( cDefault )

                  lAccept := ::ValidateMacroExpr( cDefault,  aRow[ 1 ], aLocalErrors )

               ENDIF

               IF lAccept

// { cNombre, cTipo, nLinea, cNombreOriginal, cDefault }
                  AAdd( ::aSymbols, { Lower( cVarName ), "ARG", aRow[ 1 ], cVarName, cDefault } )

               ENDIF

            ENDIF

            NEXT

// --- @global dummy_var ---
// Admite una o varias variables separadas por coma
         CASE Upper( Left( cToken, 7 ) ) == "@GLOBAL"

            cArgs := AllTrim( SubStr( cToken, 8 ) )

         IF Empty( cArgs )

            AAdd( aLocalErrors, { aRow[ 1 ], "WARN", ;
               "@GLOBAL without name variable at line " + AllTrim( Str( aRow[ 1 ] ) ), cToken } )
            LOOP

            ENDIF

// SplitArgs respeta anidamiento de (), [], {} y strings
            aNames := ::SplitArgs( cArgs )

         FOR EACH cName IN aNames

            IF Empty( cName ) ; LOOP ; ENDIF

// SplitOnAssign separa nombre del valor por defecto
// respetando anidamiento y operadores '=' vs ':='
            aPair    := ::SplitOnAssign( cName )
            cVarName := aPair[ 1 ]
            cDefault := aPair[ 2 ]

            IF ! ::IsValidIdentifier( cVarName )

               AAdd( aLocalErrors, { aRow[ 1 ], "ERROR", ;
                  "Variable name wrong in @GLOBAL: '" + cVarName + ;
                  "' (line " + AllTrim( Str( aRow[ 1 ] ) ) + ")", cVarName } )
            ELSEIF ::IsSymbolDeclared( cVarName )
               AAdd( aLocalErrors, { aRow[ 1 ], "WARN", ;
                  "Parameter '" + cVarName + "' duplicate in @GLOBAL " + ;
                  "(line " + AllTrim( Str( aRow[ 1 ] ) ) + ")", cVarName } )
            ELSE
               lAccept := .T.

               IF !empty( cDefault )

                  lAccept := ::ValidateMacroExpr( cDefault,  aRow[ 1 ], aLocalErrors )

               ENDIF

               IF lAccept

// { cNombre, cTipo, nLinea, cNombreOriginal, cDefault }
                  AAdd( ::aSymbols, { Lower( cVarName ), "GLOBAL", aRow[ 1 ], cVarName, cDefault } )

               ENDIF

            ENDIF

            NEXT

// --- @for nI := 1 TO ... ---
         CASE Upper( Left( cToken, 4 ) ) == "@FOR" .AND. Upper( Left( cToken, 8 ) ) != "@FOREACH"

            cArgs := AllTrim( SubStr( cToken, 5 ) )
            nPosAssign := At( ":=", cArgs )

         IF nPosAssign > 0

            cName := AllTrim( Left( cArgs, nPosAssign - 1 ) )

            IF ::IsValidIdentifier( cName ) .AND. !::IsSymbolDeclared( cName )

               AAdd( ::aSymbols, { Lower( cName ), "LOOP", aRow[ 1 ], cName } )

            ENDIF

            ENDIF

// --- @foreach oItem IN aData ---
         CASE Upper( Left( cToken, 8 ) ) == "@FOREACH"

            cArgs := AllTrim( SubStr( cToken, 9 ) )
            nPosIn := ::FindKeyword( Upper( cArgs ), "IN" )

         IF nPosIn > 0

            cName := AllTrim( Left( cArgs, nPosIn - 1 ) )

            IF ::IsValidIdentifier( cName ) .AND. !::IsSymbolDeclared( cName )

               AAdd( ::aSymbols, { Lower( cName ), "LOOP", aRow[ 1 ], cName } )

            ENDIF

            ENDIF

      ENDCASE

   NEXT

   IF Len( aLocalErrors ) > 0

      AEval( aLocalErrors, {| e | AAdd( ::aErrors, e ) } )

   ENDIF

RETURN ::aSymbols

// ------------------------------------------------------------
// Extreu nom de var si es inicialitzada. Ex: aData := {}
// NOTA: Este método queda por compatibilidad. Para el parseo
// de @args se recomienda usar SplitOnAssign() directamente.

METHOD ExtractVarName( cVar ) CLASS HIX_Parser

   LOCAL nPos

   cVar := alltrim( cVar )

   IF ( nPos := AT( ":=", cVar ) ) > 0

      cVar := Alltrim( Substr( cVar, 1, nPos - 1 ) )

   ELSEIF ( nPos := AT( "=", cVar ) ) > 0

      cVar := Alltrim( Substr( cVar, 1, nPos - 1 ) )

   ENDIF

   RETU cVar


// ============================================================
// SplitArgs( cText )
// Divide una lista de argumentos separados por coma, respetando
// el anidamiento de (), [], {} y los strings con ' y ".
// A diferencia de hb_ATokens(), no parte por comas internas
// en expresiones como MyFunc('a',1) o { 'k'=>'v', 'x'=>1 }.
//
// Parámetros:
// cText - Texto con la lista de args (String).
//
// Retorna:
// Array - Cada elemento es un token sin comas de separación.
//
// Ejemplo:
// SplitArgs( "par1, par2 := MyFunc('a',1), par3" )
// => { "par1", "par2 := MyFunc('a',1)", "par3" }
// ============================================================

METHOD SplitArgs( cText ) CLASS HIX_Parser

   LOCAL aResult  := {}
   LOCAL cCurrent := ""
   LOCAL nDepth   := 0
   LOCAL lInStr   := .F.
   LOCAL cStrChar := ""
   LOCAL cChar, i

   FOR i := 1 TO Len( cText )

      cChar := SubStr( cText, i, 1 )

      DO CASE

            // --- Dentro de string: solo vigilar el cierre ---
         CASE lInStr
            cCurrent += cChar

         IF cChar == cStrChar

            lInStr := .F.

            ENDIF

            // --- Apertura de string ---
         CASE cChar == '"' .OR. cChar == "'"
            lInStr   := .T.
            cStrChar := cChar
            cCurrent += cChar

            // --- Apertura de nivel: (, [, { ---
         CASE cChar == "(" .OR. cChar == "[" .OR. cChar == "{"
            nDepth++
            cCurrent += cChar

            // --- Cierre de nivel: ), ], } ---
         CASE cChar == ")" .OR. cChar == "]" .OR. cChar == "}"
            nDepth--
            cCurrent += cChar

            // --- Coma separadora solo en nivel raiz ---
         CASE cChar == "," .AND. nDepth == 0
            AAdd( aResult, AllTrim( cCurrent ) )
            cCurrent := ""

         OTHERWISE
            cCurrent += cChar

      ENDCASE

   NEXT

   // Ultimo elemento (sin coma final)

   IF ! Empty( AllTrim( cCurrent ) )

      AAdd( aResult, AllTrim( cCurrent ) )

   ENDIF

RETURN aResult


// ============================================================
// SplitOnAssign( cText )
// Busca el primer operador de asignacion ':=' o '=' en nivel 0
// (fuera de strings, parentesis, corchetes y llaves) y divide
// el texto en { cNombre, cValorDefault }.
//
// Reglas de deteccion del '=' simple:
// - Descarta '=>'  (hash rocket)
// - Descarta '=='  (comparacion)
// - Descarta '<=', '>=' , '!=' (comparaciones compuestas)
//
// Parámetros:
// cText - Expresión a analizar (String).
//
// Retorna:
// Array de 2 elementos: { cNombreVar, cDefault }
// Si no hay asignacion: { cText, "" }
//
// Ejemplos:
// SplitOnAssign( "hora := time()" )        => { "hora", "time()" }
// SplitOnAssign( "data = 'pepe'" )         => { "data", "'pepe'" }
// SplitOnAssign( "f = MyF('a',1,.t.)" )    => { "f", "MyF('a',1,.t.)" }
// SplitOnAssign( "h = { 'k'=>'v' }" )      => { "h", "{ 'k'=>'v' }" }
// SplitOnAssign( "par1" )                  => { "par1", "" }
// ============================================================
METHOD SplitOnAssign( cText ) CLASS HIX_Parser

   LOCAL nDepth   := 0
   LOCAL lInStr   := .F.
   LOCAL cStrChar := ""
   LOCAL cChar, cNext, cPrev, i
   LOCAL nLen     := Len( cText )

   FOR i := 1 TO nLen

      cChar := SubStr( cText, i, 1 )
      cNext := iif( i < nLen,  SubStr( cText, i + 1, 1 ), "" )
      cPrev := iif( i > 1,     SubStr( cText, i - 1, 1 ), "" )

      DO CASE

            // --- Dentro de string ---
         CASE lInStr

         IF cChar == cStrChar

            lInStr := .F.

            ENDIF

            // --- Apertura de string ---
         CASE cChar == '"' .OR. cChar == "'"
            lInStr   := .T.
            cStrChar := cChar

            // --- Apertura de nivel ---
         CASE cChar == "(" .OR. cChar == "[" .OR. cChar == "{"
            nDepth++

            // --- Cierre de nivel ---
         CASE cChar == ")" .OR. cChar == "]" .OR. cChar == "}"
            nDepth--

            // --- ':=' en nivel 0: asignacion Harbour ---
         CASE cChar == ":" .AND. cNext == "=" .AND. nDepth == 0
            RETURN { AllTrim( Left( cText, i - 1 ) ), ;
            AllTrim( SubStr( cText, i + 2 ) ) }

            // --- '=' simple en nivel 0 ---
         CASE cChar == "=" .AND. nDepth == 0
            // Descartar '=>' (hash rocket)

         IF cNext == ">"

            LOOP

            ENDIF

            // Descartar '==' (comparacion)

         IF cNext == "="

            LOOP

            ENDIF

            // Descartar '<=', '>=', '!=' (el '=' es el segundo caracter)

         IF cPrev $ "<!>="

            LOOP

            ENDIF

            // Es un '=' de asignacion valido
            RETURN { AllTrim( Left( cText, i - 1 ) ), ;
            AllTrim( SubStr( cText, i + 1 ) ) }

      ENDCASE

   NEXT

   // Sin asignacion encontrada: el texto completo es el nombre

RETURN { AllTrim( cText ), "" }


// ============================================================
// CheckBlockStack()
// Verifica el anidamiento correcto de directivas de bloque (@if,
// @for, @prg, etc.) a lo largo de todo el código analizado.
// Utiliza una pila (stack) para detectar aperturas sin cierre,
// cierres huérfanos, cruzamiento de bloques o anidamientos ilegales.
//
// Retorna:
// aErrors - Matriz de errores detectados durante la validación.
//
// Ejemplo:
// oParser:CheckBlockStack()
// ============================================================
METHOD CheckBlockStack() CLASS HIX_Parser

   LOCAL aErrors  := {}
   LOCAL aStack   := {}
   LOCAL aRow, cType, cToken
   LOCAL oTop, cExpected

   FOR EACH aRow IN ::aResult

      cType  := aRow[ 2 ]
      cToken := Upper( AllTrim( aRow[ 3 ] ) )

      IF !( cType == TYPE_HRB )

         LOOP

      ENDIF

      DO CASE

            // --- Aperturas: push al stack ---
         CASE Left( cToken, 3 ) == "@IF"
            AAdd( aStack, { "@IF", aRow[ 1 ] } )

         CASE Left( cToken, 8 ) == "@FOREACH"
            AAdd( aStack, { "@FOREACH", aRow[ 1 ] } )

         CASE Left( cToken, 4 ) == "@FOR" .AND. Left( cToken, 8 ) != "@FOREACH"
            AAdd( aStack, { "@FOR", aRow[ 1 ] } )

         CASE Left( cToken, 4 ) == "@PRG" .AND. cToken != "@ENDPRG" .AND. ;
            !( "@PRG BLOCK" $ cToken )
            oTop := iif( Len( aStack ) > 0, ATail( aStack ), NIL )

         IF oTop != NIL .AND. oTop[ 1 ] == "@PRG"

            AAdd( aErrors, { aRow[ 1 ], "ERROR", ;
               "@PRG nesting not allowed (open in line " + ;
               AllTrim( Str( oTop[ 2 ] ) ) + ")", cToken } )
         ELSE

            IF  Empty( Substr( cToken, 5 ) )

               AAdd( aStack, { "@PRG", aRow[ 1 ] } )
            ELSE
               AAdd( aErrors, { aRow[ 1 ], "ERROR", ;
                  "The @PRG directive has to be empty in the first line", cToken } )

            ENDIF

            ENDIF

            // --- @else/@elseif: deben estar dentro de @if ---
         CASE Left( cToken, 7 ) == "@ELSEIF" .OR. cToken == "@ELSE"

            oTop := iif( Len( aStack ) > 0, ATail( aStack ), NIL )

         IF oTop == NIL .OR. ( oTop[ 1 ] != "@IF" .AND. oTop[ 1 ] != "@IF_ELSE" )

            AAdd( aErrors, { aRow[ 1 ], "ERROR", ;
               cToken + " without corresponding @IF", cToken } )
         ELSEIF cToken == "@ELSE"

            IF ATail( aStack )[ 1 ] == "@IF_ELSE"

               // Segundo @else en el mismo @if
               AAdd( aErrors, { aRow[ 1 ], "ERROR", ;
                  "Double @ELSE in the same @IF (open in line " + ;
                  AllTrim( Str( ATail( aStack )[ 2 ] ) ) + ")", cToken } )
            ELSE
               // Marcar que este @if ya tiene @else
               ATail( aStack )[ 1 ] := "@IF_ELSE"

            ENDIF

            ENDIF

            // --- Cierres: pop del stack y validar pareja ---
         CASE cToken == "@ENDIF"

         IF Len( aStack ) == 0

            AAdd( aErrors, { aRow[ 1 ], "ERROR", "@ENDIF without corresponding @IF", cToken } )
         ELSE
            oTop := ATail( aStack )

            IF oTop[ 1 ] != "@IF" .AND. oTop[ 1 ] != "@IF_ELSE"

               cExpected := ::CloserOf( oTop[ 1 ] )
               AAdd( aErrors, { aRow[ 1 ], "ERROR", ;
                  "@ENDIF unexpected — it was expected " + cExpected + ;
                  " to close " + oTop[ 1 ] + " open in line " + AllTrim( Str( oTop[ 2 ] ) ), cToken } )
            ELSE
               ASize( aStack, Len( aStack ) - 1 )

            ENDIF

            ENDIF

         CASE cToken == "@ENDFOREACH"

         IF Len( aStack ) == 0

            AAdd( aErrors, { aRow[ 1 ], "ERROR", "@ENDFOREACH sin @FOREACH correspondiente" } )
         ELSE
            oTop := ATail( aStack )

            IF oTop[ 1 ] != "@FOREACH"

               cExpected := ::CloserOf( oTop[ 1 ] )
               AAdd( aErrors, { aRow[ 1 ], "ERROR", ;
                  "@ENDFOREACH without corresponding @FOREACH " + cExpected + ;
                  " to close " + oTop[ 1 ] + " open in line " + AllTrim( Str( oTop[ 2 ] ) ), cToken } )
            ELSE
               ASize( aStack, Len( aStack ) - 1 )

            ENDIF

            ENDIF

         CASE cToken == "@NEXT"

         IF Len( aStack ) == 0

            AAdd( aErrors, { aRow[ 1 ], "ERROR", "@NEXT without corresponding @FOR", cToken } )
         ELSE
            oTop := ATail( aStack )

            IF oTop[ 1 ] != "@FOR"

               cExpected := ::CloserOf( oTop[ 1 ] )
               AAdd( aErrors, { aRow[ 1 ], "ERROR", ;
                  "@NEXT unexpected — expected " + cExpected + ;
                  " to close " + oTop[ 1 ] + " open in line " + AllTrim( Str( oTop[ 2 ] ) ), cToken } )
            ELSE
               ASize( aStack, Len( aStack ) - 1 )

            ENDIF

            ENDIF

         CASE cToken == "@ENDPRG"

         IF Len( aStack ) == 0

            AAdd( aErrors, { aRow[ 1 ], "ERROR", "@ENDPRG without corresponding @PRG", cToken } )
         ELSE
            oTop := ATail( aStack )

            IF oTop[ 1 ] != "@PRG"

               cExpected := ::CloserOf( oTop[ 1 ] )
               AAdd( aErrors, { aRow[ 1 ], "ERROR", ;
                  "@ENDPRG unexpected — it was expected " + cExpected + ;
                  " to close " + oTop[ 1 ] + " open in line " + AllTrim( Str( oTop[ 2 ] ) ), cToken } )
            ELSE
               ASize( aStack, Len( aStack ) - 1 )

            ENDIF

            ENDIF

      ENDCASE

   NEXT

   // Bloques que quedaron abiertos sin cerrar

   IF Len( aStack ) > 0

      FOR EACH oTop IN aStack

         AAdd( aErrors, { oTop[ 2 ], "ERROR", ;
            oTop[ 1 ] + " open in line " + AllTrim( Str( oTop[ 2 ] ) ) + ;
            " was never closed (missing " + ::CloserOf( oTop[ 1 ] ) + ")", '' } )

      NEXT

   ENDIF

   IF Len( aErrors ) > 0

      AEval( aErrors, {| e | AAdd( ::aErrors, e ) } )

   ENDIF

RETURN aErrors


// ============================================================
// CheckMacros()
// Valida semánticamente todas las macros `{{ }}` y `{!! !!}`
// integrando verificaciones previas.
//
// Reglas:
// - Alerta si falta llave de cierre.
// - Alerta macros vacías o anidadas.
// - Valida la sintaxis de Harbour dentro de la expresión.
// - Advierte si una variable macro no se ha declarado globalmente.
//
// Retorna:
// aLocalErrors - Matriz de errores detectados.
//
// Ejemplo:
// oParser:CheckMacros()
// ============================================================
METHOD CheckMacros() CLASS HIX_Parser

   LOCAL aRow, cRaw, cContent
   LOCAL nOpen, nClose, nPos, nLen
   LOCAL cExpr, cVar
   LOCAL aLocalErrors := {}
   LOCAL nOpenEsc, nOpenUnesc, nOpenTagLen, nCloseTagLen, cCloseTag, cTagType

   FOR EACH aRow IN ::aResult

      // Solo procesamos tokens HTML/TEXT que pueden contener macros

      IF !( aRow[ 2 ] == TYPE_HTML .OR. aRow[ 2 ] == TYPE_TEXT )

         LOOP

      ENDIF

      cRaw := aRow[ 3 ]
      nLen := Len( cRaw )
      nPos := 1

      WHILE nPos <= nLen

         // Buscar ambos tipos de macro ("{{" o "{!!")
         nOpenEsc   := hb_At( "{{", cRaw, nPos )
         nOpenUnesc := hb_At( "{!!", cRaw, nPos )

         // Determinar cual va primero

         IF nOpenEsc == 0 .AND. nOpenUnesc == 0

            EXIT

         ENDIF

         IF nOpenUnesc > 0 .AND. ( nOpenEsc == 0 .OR. nOpenUnesc < nOpenEsc )

            nOpen       := nOpenUnesc
            nOpenTagLen := 3
            cTagType    := "{!!"
            cCloseTag   := "!!}"
         ELSE
            nOpen       := nOpenEsc
            nOpenTagLen := 2
            cTagType    := "{{"
            cCloseTag   := "}}"

         ENDIF

         nClose := hb_At( cCloseTag, cRaw, nOpen + nOpenTagLen )

         IF nClose == 0

            // Macro sin cierre
            AAdd( aLocalErrors, { aRow[ 1 ], "ERROR", ;
               "Macro without closing '" + cTagType + "' in line " + AllTrim( Str( aRow[ 1 ] ) ) + ;
               ": " + AllTrim( SubStr( cRaw, nOpen, 20 ) ) + "...", cRaw } )
            EXIT

         ENDIF

         nCloseTagLen := Len( cCloseTag )
         cContent := SubStr( cRaw, nOpen + nOpenTagLen, nClose - nOpen - nOpenTagLen )
         cExpr    := AllTrim( cContent )

         // Macro vacia

         IF Empty( cExpr )

            AAdd( aLocalErrors, { aRow[ 1 ], "WARN", ;
               "Empty macro '" + cTagType + "  " + cCloseTag + "' in line " + AllTrim( Str( aRow[ 1 ] ) ), cRaw } )
            nPos := nClose + nCloseTagLen
            LOOP

         ENDIF

         // Macro anidada (verifica ambos tipos dentro del contenido)

         IF "{{" $ cExpr .OR. "{!!" $ cExpr

            AAdd( aLocalErrors, { aRow[ 1 ], "ERROR", ;
               "Nested macro not allowed in line " + AllTrim( Str( aRow[ 1 ] ) ) + ;
               ": " + cTagType + " " + cExpr + " " + cCloseTag, cRaw } )
            nPos := nClose + nCloseTagLen
            LOOP

         ENDIF

         // Sintaxis Harbour
         ::ValidateMacroExpr( cExpr, aRow[ 1 ], @aLocalErrors )

         // Variable simple no declarada en @args/@global

         IF ::IsSimpleVar( cExpr ) .AND. ! ::IsSymbolDeclared( cExpr )

            AAdd( aLocalErrors, { aRow[ 1 ], "WARN", ;
               "Variable '" + cExpr + "' in macro (line " + AllTrim( Str( aRow[ 1 ] ) ) + ;
               ") not declared in @args/@global", "" } )

         ENDIF

         nPos := nClose + nCloseTagLen

      ENDDO

   NEXT

   IF Len( aLocalErrors ) > 0

      AEval( aLocalErrors, {| e | AAdd( ::aErrors, e ) } )

   ENDIF

RETURN aLocalErrors


// ============================================================
// CheckExprSyntax()
// Analiza y delega la validación sintáctica de las condiciones y
// asignaciones de todas las directivas de control de flujo en el
// archivo (@if, @elseif, @while, @for, @foreach).
//
// Retorna:
// aLocalErrors - Matriz de errores descubiertos.
//
// Ejemplo:
// oParser:CheckExprSyntax()
// ============================================================
METHOD CheckExprSyntax() CLASS HIX_Parser

   LOCAL aRow, cToken, cUpper, cExpr, cDirectiva
   LOCAL aLocalErrors := {}

   FOR EACH aRow IN ::aResult

      IF !( aRow[ 2 ] == TYPE_HRB )

         LOOP

      ENDIF

      cToken := AllTrim( aRow[ 3 ] )
      cUpper := Upper( cToken )

      DO CASE

         CASE Left( cUpper, 3 ) == "@IF" .AND. Left( cUpper, 7 ) != "@IFDEF"
            cExpr      := AllTrim( SubStr( cToken, 4 ) )
            cDirectiva := "@IF"
            ::ValidateCondExpr( cExpr, cDirectiva, aRow[ 1 ], @aLocalErrors )

         CASE Left( cUpper, 7 ) == "@ELSEIF"
            cExpr      := AllTrim( SubStr( cToken, 8 ) )
            cDirectiva := "@ELSEIF"
            ::ValidateCondExpr( cExpr, cDirectiva, aRow[ 1 ], @aLocalErrors )

         CASE Left( cUpper, 6 ) == "@WHILE"
            cExpr      := AllTrim( SubStr( cToken, 7 ) )
            cDirectiva := "@WHILE"
            ::ValidateCondExpr( cExpr, cDirectiva, aRow[ 1 ], @aLocalErrors )

         CASE Left( cUpper, 4 ) == "@FOR" .AND. Left( cUpper, 8 ) != "@FOREACH"
            cExpr := AllTrim( SubStr( cToken, 5 ) )
            ::ValidateForExpr( cExpr, aRow[ 1 ], @aLocalErrors )

         CASE Left( cUpper, 8 ) == "@FOREACH"
            cExpr := AllTrim( SubStr( cToken, 9 ) )
            ::ValidateForeachExpr( cExpr, aRow[ 1 ], @aLocalErrors )

      ENDCASE

   NEXT

   IF Len( aLocalErrors ) > 0

      AEval( aLocalErrors, {| e | AAdd( ::aErrors, e ) } )

   ENDIF

RETURN aLocalErrors


// ------------------------------------------------------------
// SECCION 4: HELPERS DE VALIDACION DE EXPRESIONES
// ------------------------------------------------------------

// ============================================================
// ValidateMacroExpr( cExpr, nLine, aErrors )
// Compila la expresión con código Harbour (`hb_compileExpr()`)
// puramente con propósitos de validación sintáctica (sin ejecutar).
// Envoltorio genérico en array prevé múltiples declaraciones.
//
// Parámetros:
// cExpr - Código Harbour a validar.
// aErrors - Referencia a matriz de errores acumulados.
//
// Ejemplo:
// oParser:ValidateMacroExpr( "Upper(cVar)", 10, @aErrors )
// ============================================================
METHOD ValidateMacroExpr( cExpr, nLine, aErrors ) CLASS HIX_Parser

   LOCAL bCode, oErr
   LOCAL lPass := .T.

   TRY

      bCode := &( '{|| (' + cExpr + ')}' )
   CATCH oErr
      lPass := .F.
      AAdd( aErrors, { nLine, "ERROR", oErr:Description + " (line " + AllTrim( Str( nLine ) ) + ")", cExpr } )

   END

   bCode := nil

RETURN lPass





// ============================================================
// ValidateCondExpr( cExpr, cDir, nLine, aErrors )
// Pre-valida expresiones condicionales exigidas por directivas
// lógicas (`@if`, `@elseif`, `@while`), garantizando que no
// sean nulas previo paso al compilador base.
//
// Ejemplo:
// oParser:ValidateCondExpr( "a == b", "@IF", 10, @aErr )
// ============================================================
METHOD ValidateCondExpr( cExpr, cDir, nLine, aErrors ) CLASS HIX_Parser

   IF Empty( cExpr )

      AAdd( aErrors, { nLine, "ERROR", ;
         cDir + " line without expresion: " + AllTrim( Str( nLine ) ), cExpr } )

      RETURN NIL

   ENDIF

   ::ValidateMacroExpr( cExpr, nLine, @aErrors )

RETURN NIL


// ============================================================
// ValidateForExpr( cExpr, nLine, aErrors )
// Valida estructuralmente el bloque de bucle Harbour clásico `FOR`.
// Garantiza la existencia de operando asignación y tope TO.
//
// Formato base: nVar := nInicio TO nFin [STEP n]
//
// Ejemplo:
// oParser:ValidateForExpr( "i:=1 TO 10", 10, @aErr )
// ============================================================
METHOD ValidateForExpr( cExpr, nLine, aErrors ) CLASS HIX_Parser

   LOCAL nPosAssign, nPosTo, nPosStep, oError
   LOCAL cVar, cFrom, cTo, cStep
   LOCAL cUpper := Upper( cExpr )

   nPosAssign := At( ":=", cExpr )

   IF nPosAssign == 0

      AAdd( aErrors, { nLine, "ERROR", ;
         "@FOR without assignment ':=' in line " + AllTrim( Str( nLine ) ) + ": " + cExpr, cExpr } )
      RETURN NIL

   ENDIF

   nPosTo := ::FindKeyword( cUpper, "TO" )

   IF nPosTo == 0

      AAdd( aErrors, { nLine, "ERROR", ;
         "@FOR without 'TO' in line " + AllTrim( Str( nLine ) ) + ": " + cExpr, cExpr } )
      RETURN NIL

   ENDIF

   cVar  := AllTrim( Left( cExpr, nPosAssign - 1 ) )
   cFrom := AllTrim( SubStr( cExpr, nPosAssign + 2, nPosTo - nPosAssign - 2 ) )
   nPosStep := ::FindKeyword( cUpper, "STEP" )

   IF nPosStep > 0

      cTo   := AllTrim( SubStr( cExpr, nPosTo + 2, nPosStep - nPosTo - 2 ) )
      cStep := AllTrim( SubStr( cExpr, nPosStep + 4 ) )
   ELSE
      cTo   := AllTrim( SubStr( cExpr, nPosTo + 2 ) )
      cStep := ""

   ENDIF

   IF ! ::IsValidIdentifier( cVar )

      AAdd( aErrors, { nLine, "ERROR", ;
         "@FOR initial empty value (line '" + cVar + ;
         "' (line " + AllTrim( Str( nLine ) ) + ")", cExpr } )

   ENDIF

   IF Empty( cFrom )

      AAdd( aErrors, { nLine, "ERROR", "@FOR initial empty value (line " + AllTrim( Str( nLine ) ) + ")", cExpr } )
   ELSE
      ::ValidateMacroExpr( cFrom, nLine, @aErrors )

   ENDIF

   IF Empty( cTo )

      AAdd( aErrors, { nLine, "ERROR", "@FOR empty final value (line " + AllTrim( Str( nLine ) ) + ")", cExpr } )
   ELSE
      ::ValidateMacroExpr( cTo, nLine, @aErrors )

   ENDIF

   IF ! Empty( cStep )

      ::ValidateMacroExpr( cStep, nLine, @aErrors )

   ENDIF

RETURN NIL


// ============================================================
// ValidateForeachExpr( cExpr, nLine, aErrors )
// Valida estructuralmente el bloque iterador `FOREACH`.
// Asegura la existencia de la sintaxis Harbour `oVar IN aData`.
//
// Ejemplo:
// oParser:ValidateForeachExpr( "oItem IN aLista", 10, @aErr )
// ============================================================
METHOD ValidateForeachExpr( cExpr, nLine, aErrors ) CLASS HIX_Parser

   LOCAL nPosIn, cVar, cCol
   LOCAL cUpper := Upper( cExpr )

   nPosIn := ::FindKeyword( cUpper, "IN" )

   IF nPosIn == 0

      AAdd( aErrors, { nLine, "ERROR", ;
         "@FOREACH no 'IN' in line " + AllTrim( Str( nLine ) ) + ": " + cExpr, cExpr } )
      RETURN NIL

   ENDIF

   cVar := AllTrim( Left( cExpr, nPosIn - 1 ) )
   cCol := AllTrim( SubStr( cExpr, nPosIn + 2 ) )

   IF ! ::IsValidIdentifier( cVar )

      AAdd( aErrors, { nLine, "ERROR", ;
         "@FOREACH invalid iterator variable '" + cVar + ;
         "' (linea " + AllTrim( Str( nLine ) ) + ")", cExpr } )

   ENDIF

   IF Empty( cCol )

      AAdd( aErrors, { nLine, "ERROR", ;
         "@FOREACH empty collection (line " + AllTrim( Str( nLine ) ) + ")", cExpr } )
   ELSE
      ::ValidateMacroExpr( cCol, nLine, @aErrors )

   ENDIF

RETURN NIL


// ------------------------------------------------------------
// SECCION 5: HELPERS DE SIMBOLOS E IDENTIFICADORES
// ------------------------------------------------------------

// ============================================================
// IsSymbolDeclared( cVar )
// Verifica si una variable en particular ya está alojada
// y registrada en el entorno de símbolos de contexto. (Insensible a ctrl/mayusculas).
//
// Retorna:
// lBool - .T. si la variable está declarada.
//
// Ejemplo:
// lExists := oParser:IsSymbolDeclared( "aData" )
// ============================================================
METHOD IsSymbolDeclared( cVar ) CLASS HIX_Parser

   LOCAL aSym

   FOR EACH aSym IN ::aSymbols

      IF Lower( aSym[ 1 ] ) == Lower( cVar )

         RETURN .T.

      ENDIF

   NEXT

RETURN .F.


// ============================================================
// HasSymbolType( cTipo )
// Informa si ya existe en la caché de símbolos algún miembro
// bajo un tipo en particular (`ARG`, `GLOBAL`, etc).
//
// Retorna:
// lBool - .T. si el alcance se encuentra presente.
//
// Ejemplo:
// lArgsDeclarados := oParser:HasSymbolType( "ARG" )
// ============================================================
METHOD HasSymbolType( cTipo ) CLASS HIX_Parser

   LOCAL aSym

   FOR EACH aSym IN ::aSymbols

      IF aSym[ 2 ] == cTipo

         RETURN .T.

      ENDIF

   NEXT

RETURN .F.


// ============================================================
// IsValidIdentifier( cName )
// Evalúa un posible nombre de variable o función para asegurar
// que coincide con las reglas de identificadores en Harbour.
// 1. No puede empezar por número.
// 2. Caracteres alfanuméricos y guión bajo `_` exclusivamente.
// 3. No puede colisionar con palabras reservadas del core.
//
// Ejemplo:
// lValid := oParser:IsValidIdentifier( "nContador_1" )
// ============================================================
METHOD IsValidIdentifier( cName ) CLASS HIX_Parser

   LOCAL i, c
   LOCAL aReserved := { "if", "else", "endif", "for", "next", "while", "end",  ;
      "do", "case", "otherwise", "return", "function",      ;
      "FUNCTION", "local", "static", "public", "private"   }

   IF Empty( cName )

      RETURN .F.

   ENDIF

   c := Left( cName, 1 )

   IF !( IsAlpha( c ) .OR. c == "_" )

      RETURN .F.

   ENDIF

   FOR i := 2 TO Len( cName )

      c := SubStr( cName, i, 1 )

      IF !( IsAlpha( c ) .OR. IsDigit( c ) .OR. c == "_" )

         RETURN .F.

      ENDIF

   NEXT

   IF AScan( aReserved, {| r | r == Lower( cName ) } ) > 0

      RETURN .F.

   ENDIF

RETURN .T.


// ============================================================
// IsSimpleVar( cExpr )
// Distingue entre una expresión compleja (`a + b`, `Upper(c)`)
// y una variable estándar aislada. Útil para verificar si
// una variable fue expuesta globalmente (`@GLOBAL` o `@ARGS`).
//
// Ejemplo:
// lSimple := oParser:IsSimpleVar( "cMiVar" )  // .T.
// lSimple := oParser:IsSimpleVar( "cMiVar()" ) // .F.
// ============================================================
METHOD IsSimpleVar( cExpr ) CLASS HIX_Parser

   LOCAL i, c

   IF Len( cExpr ) == 0 .OR. !( IsAlpha( Left( cExpr, 1 ) ) .OR. Left( cExpr, 1 ) == "_" )

      RETURN .F.

   ENDIF

   FOR i := 1 TO Len( cExpr )

      c := SubStr( cExpr, i, 1 )

      IF !( IsAlpha( c ) .OR. IsDigit( c ) .OR. c == "_" )

         RETURN .F.

      ENDIF

   NEXT

RETURN .T.


// ------------------------------------------------------------
// SECCION 6: HELPERS DE ESTRUCTURA Y STACK
// ------------------------------------------------------------

// ============================================================
// CloserOf( cDirectiva )
// Retorna el token de cierre esperado (pareja) para una directiva
// de apertura. Usado en CheckBlockStack() para emitir mensajes
// de error precisos.
//
// Parámetros:
// cDirectiva - Nombre de la directiva de apertura ("@IF", etc).
//
// Retorna:
// String - La directiva de cierre ("@ENDIF", etc).
//
// Ejemplo:
// cExpected := oParser:CloserOf( "@IF" ) // Retorna "@ENDIF"
// ============================================================
METHOD CloserOf( cDirectiva ) CLASS HIX_Parser

   DO CASE

      CASE cDirectiva == "@IF"      .OR. cDirectiva == "@IF_ELSE" ; RETURN "@ENDIF"
      CASE cDirectiva == "@FOREACH"                                ; RETURN "@ENDFOREACH"
      CASE cDirectiva == "@FOR"                                    ; RETURN "@NEXT"
      CASE cDirectiva == "@PRG"                                    ; RETURN "@ENDPRG"

   ENDCASE

RETURN "???"


// ============================================================
// FindKeyword( cUpper, cKw )
// Busca una palabra clave como token completo en un string en
// mayúsculas. Evita falsos positivos: "STOCK" contiene "TO"
// pero no se considera la palabra reservada "TO".
//
// Retorna:
// nPos - La posición de inicio o 0 si no se encuentra.
//
// Ejemplo:
// nPosTo := oParser:FindKeyword( Upper(cExpr), "TO" )
// ============================================================
METHOD FindKeyword( cUpper, cKw ) CLASS HIX_Parser

   LOCAL nPos := 1, nLen := Len( cKw )
   LOCAL cBefore, cAfter, nFound

   WHILE .T.

      nFound := hb_At( cKw, cUpper, nPos )

      IF nFound == 0

         RETURN 0

      ENDIF

      cBefore := iif( nFound > 1, SubStr( cUpper, nFound - 1, 1 ), " " )
      cAfter  := iif( nFound + nLen <= Len( cUpper ), SubStr( cUpper, nFound + nLen, 1 ), " " )

      IF !( IsAlpha( cBefore ) .OR. IsDigit( cBefore ) .OR. cBefore == "_" ) .AND. ;
            !( IsAlpha( cAfter )  .OR. IsDigit( cAfter )  .OR. cAfter  == "_" )

         RETURN nFound

      ENDIF

      nPos := nFound + 1

   ENDDO

RETURN 0


// ============================================================
// PopDirective( cTag, nLine, cLine )
// Hace pop del stack temporal de directivas anidadas,
// verificando que la etiqueta de cierre coincide con la cima.
// Se usa estrictamente para la verificación superficial durante
// el bucle principal de Parse(). (CheckBlockStack es más robusto).
//
// Ejemplo:
// oParser:PopDirective( "@PRG", 15, "@endprg" )
// ============================================================
METHOD PopDirective( cTag, nLine, cLine ) CLASS HIX_Parser

   LOCAL oTop

   IF Len( ::aDirectiveStack ) == 0

      RETURN NIL

   ENDIF

   oTop := ATail( ::aDirectiveStack )

   IF Upper( oTop[ 1 ] ) != Upper( cTag )

      // Mismatch de stack — se registra pero no se aborta
      AAdd( ::aErrors, { nLine, "WARN", ;
         "PopDirective: It was expected '" + oTop[ 1 ] + "' pero se recibio '" + cTag + "'", cLine } )

   ENDIF

   ASize( ::aDirectiveStack, Len( ::aDirectiveStack ) - 1 )

RETURN NIL


// ============================================================
// IsPureHtml( cCode )
// Retorna .T. si el fragmento no contiene macros {{ }}/{!! !!}
// ni directivas HIX (@if, @for, etc.).
// ============================================================
METHOD IsPureHtml( cCode ) CLASS HIX_Parser

   LOCAL aLines, cLine

   IF "{{" $ cCode .OR. "{!!" $ cCode

      RETURN .F.

   ENDIF

   IF "@" $ cCode

      aLines := hb_ATokens( StrTran( cCode, Chr( 13 ), "" ), Chr( 10 ) )

      FOR EACH cLine IN aLines

         IF Left( AllTrim( cLine ), 1 ) == "@" .AND. ::IsHarbourDirective( cLine )

            RETURN .F.

         ENDIF

      NEXT

   ENDIF

RETURN .T.


// ------------------------------------------------------------
// SECCION 7: DEBUG / TRACE
// ------------------------------------------------------------

// ============================================================
// TraceResult()
// Vuelca por consola la matriz ::aResult (tokens clasificados).
// Solo actúa si ::lDebug = .T.
// ============================================================
METHOD TraceResult() CLASS HIX_Parser

   LOCAL aRow

   IF ! ::lDebug

      RETURN NIL

   ENDIF

   ? "=== PARSER RESULT ==="
   ? "Total tokens aResult : " + AllTrim( Str( Len( ::aResult ) ) )

   FOR EACH aRow IN ::aResult

      ? StrZero( aRow[ 1 ], 4 ) + " " + aRow[ 2 ] + " " + UHtmlEncode( aRow[ 3 ] )

   NEXT

   ? ""
   ? "Total blocks aBlocks: " + AllTrim( Str( Len( ::aBlocks ) ) )

   FOR EACH aRow IN ::aBlocks

      ? StrZero( aRow[ 1 ], 4 ) + " @PRG"

   NEXT

RETURN NIL


// ============================================================
// TraceErrors()
// Vuelca por consola la matriz ::aErrors (errores detectados).
// Solo actúa si ::lDebug = .T.
// ============================================================
METHOD TraceErrors() CLASS HIX_Parser

   LOCAL aErr

   IF ! ::lDebug

      RETURN NIL

   ENDIF

   IF Empty( ::aErrors )

      ? "=== NO ERRORS ==="
      RETURN NIL

   ENDIF

   ? "===PARSER ERRORS: " + AllTrim( Str( Len( ::aErrors ) ) ) + " ==="

   FOR EACH aErr IN ::aErrors

      ? "[" + aErr[ 2 ] + "] Line " + AllTrim( Str( aErr[ 1 ] ) ) + ": " + aErr[ 3 ]

   NEXT

RETURN NIL


// ============================================================
// TraceSymbols()
// Vuelca por consola la matriz ::aSymbols (símbolos expuestos).
// Solo actúa si ::lDebug = .T.
// ============================================================
METHOD TraceSymbols() CLASS HIX_Parser

   LOCAL aSym
   LOCAL cDefInfo := ""

   IF ! ::lDebug

      RETURN NIL

   ENDIF

   ? "=== DECLARED SYMBOLS: " + AllTrim( Str( Len( ::aSymbols ) ) ) + " ==="

   FOR EACH aSym IN ::aSymbols

      cDefInfo := ""

      IF Len( aSym ) >= 5 .AND. ! Empty( aSym[ 5 ] )

         cDefInfo := "  [default: " + aSym[ 5 ] + "]"

      ENDIF

      ? "  [" + aSym[ 2 ] + "] " + aSym[ 1 ] + "  (line " + AllTrim( Str( aSym[ 3 ] ) ) + ")" + cDefInfo

   NEXT

RETURN NIL

// ============================================================
// InitTraceTime()
// Marca el inicio de un bloque de medición.
// Solo actua si lDebug = .T.
// Si el nombre ya existe (llamadas multiples) acumula el tiempo
// y incrementa el contador de llamadas — util para MACRO_COMPILE.
//
// Uso:  ::InitTraceTime( 'CHECK_MACROS' )
// ============================================================
METHOD InitTraceTime( cName ) CLASS HIX_Parser

   LOCAL aSlot

   IF ! ::lDebug

      RETURN NIL

   ENDIF

   IF hb_HHasKey( ::hTraceTimes, cName )

      // Slot ya existe: actualizar nStart para esta llamada
      ::hTraceTimes[ cName ][ 2 ] := hb_MilliSeconds()
   ELSE
      // { cNombre, nStart, nEnd, nMsAcum, nCalls }
      aSlot := { cName, hb_MilliSeconds(), 0, 0, 0 }
      AAdd( ::aTraceTimes, aSlot )
      ::hTraceTimes[ cName ] := aSlot

   ENDIF

RETURN NIL


// ============================================================
// EndTraceTime()
// Marca el fin de un bloque de medición y acumula el tiempo.
// nMsAcum += ( ahora - nStart )
// nCalls++
//
// Uso:  ::EndTraceTime( 'CHECK_MACROS' )
// ============================================================
METHOD EndTraceTime( cName ) CLASS HIX_Parser

   LOCAL aSlot, nElapsed

   IF ! ::lDebug

      RETURN NIL

   ENDIF

   IF ! hb_HHasKey( ::hTraceTimes, cName )

      RETURN NIL   // InitTraceTime no fue llamado — ignorar silenciosamente

   ENDIF

   aSlot    := ::hTraceTimes[ cName ]
   nElapsed := hb_MilliSeconds() - aSlot[ 2 ]

   // Evitar negativo por overflow (raro pero posible en runs muy largos)

   IF nElapsed < 0

      nElapsed := 0

   ENDIF

   aSlot[ 3 ] := hb_MilliSeconds()  // nEnd = ahora
   aSlot[ 4 ] += nElapsed           // nMsAcum acumulado
   aSlot[ 5 ] += 1                  // nCalls++

   ::hTraceTimes[ cName ] := aSlot

RETURN NIL


// ============================================================
// TraceTimes()
// Muestra resumen de tiempos ordenado de mayor a menor (ms).
// Calcula el total global y el % de cada proceso.
// Muestra Top 5 cuellos de botella destacados.
// Solo actua si lDebug = .T.
// ============================================================
METHOD TraceTimes() CLASS HIX_Parser

   LOCAL aSlots, aSlot, aSorted
   LOCAL nTotal := 0, nMs, nPct
   LOCAL i, cBar, nBarLen
   LOCAL cMark
   LOCAL n, j, aTmp

   IF ! ::lDebug .OR. Empty( ::aTraceTimes )

      RETURN NIL

   ENDIF

   // Copiar y ordenar por nMsAcum descendente
   aSlots := AClone( ::aTraceTimes )
   // Bubble sort simple (array pequeño, max 10 entradas)
   n := Len( aSlots )

   FOR i := 1 TO n - 1

      FOR j := 1 TO n - i

         IF aSlots[ j ][ 4 ] < aSlots[ j + 1 ][ 4 ]

            aTmp        := aSlots[ j ]
            aSlots[ j ]   := aSlots[ j + 1 ]
            aSlots[ j + 1 ] := aTmp

         ENDIF

      NEXT

   NEXT

   // Calcular total

   FOR EACH aSlot IN aSlots

      nTotal += aSlot[ 4 ]

   NEXT

   ? ""
   ? "╔══════════════════════════════════════════════════════════════════╗"
   ? "║           HIX_Parser — Execution time trace                      ║"
   ? "╠══════════════════════════════════════════════════════════════════╣"
   ? "║  #   Process              ms total   calls   ms/call   %         ║"
   ? "╠══════════════════════════════════════════════════════════════════╣"

   FOR i := 1 TO Len( aSlots )

      aSlot  := aSlots[ i ]
      nMs    := aSlot[ 4 ]
      nPct   := iif( nTotal > 0, Round( nMs * 100 / nTotal, 1 ), 0 )

      // Barra visual proporcional (max 12 chars)
      nBarLen := Int( nPct / 100 * 12 )
      // cBar    := Replicate( "█", nBarLen ) + Replicate( "░", 12 - nBarLen )

      // Marca Top 5
      cMark := iif( i <= 5, iif( i == 1, " ◄TOP", "     " ), "     " )

      ? "║ " + StrZero( i, 2 ) + "  " + ;
         PadR( aSlot[ 1 ], 22 ) + ;
         PadL( AllTrim( Str( nMs ) ), 7 ) + " ms  " + ;
         PadL( AllTrim( Str( aSlot[ 5 ] ) ), 5 ) + "   " + ;
         PadL( iif( aSlot[ 5 ] > 0, AllTrim( Str( Round( nMs / aSlot[ 5 ], 1 ) ) ), "-" ), 7 ) + "  " + ;
         PadL( AllTrim( Str( nPct ) ), 5 ) + "%  " + ;
         "  ║"
      // cBar + cMark + " ║"

   NEXT

   ? "╠══════════════════════════════════════════════════════════════════╣"
   ? "║  TOTAL                    " + PadL( AllTrim( Str( nTotal ) ), 7 ) + " ms                             ║"
   ? "╚══════════════════════════════════════════════════════════════════╝"
   ? ""

   // Recomendacion automatica basada en el top 1

   IF Len( aSlots ) > 0 .AND. aSlots[ 1 ][ 4 ] > 0

      ? "  ► Main bottleneck: " + aSlots[ 1 ][ 1 ] + ;
         " (" + AllTrim( Str( aSlots[ 1 ][ 4 ] ) ) + " ms, " + ;
         AllTrim( Str( aSlots[ 1 ][ 5 ] ) ) + " llamadas)"

      IF aSlots[ 1 ][ 1 ] == "MACRO_COMPILE"

         ? "    Consider caching hb_compileExpr() for repeated expression."
      ELSEIF aSlots[ 1 ][ 1 ] == "CHECK_MACROS"
         ? "    Too many macros {{ }} in the template — consider reducing them."
      ELSEIF aSlots[ 1 ][ 1 ] == "PARSE_LOOP"
         ? "    Very large template — consider splitting into sub-templates."

      ENDIF

   ENDIF

   ? ""

RETURN NIL
