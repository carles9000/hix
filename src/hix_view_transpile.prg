/*-----------------------------------------------------------
  File ......: hix_view_transpile.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: HIX view transpiler — converts parser AST to executable
               Harbour PRG source.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#INCLUDE "hix_const.ch"
#INCLUDE "hix_hrb.ch"

#INCLUDE "hbclass.ch"
#INCLUDE "common.ch"
#INCLUDE "error.ch"

#XTRANSLATE Throw( <o> ) => ( Eval( ErrorBlock(), <o> ), Break( <o> ) )

#DEFINE PARSER_LINE 1
#DEFINE PARSER_TYPE 2
#DEFINE PARSER_CODE 3

CLASS Hix_Transpile

   DATA aLines            // Array de { linea, tipo, codigo } recibidos del parser
   DATA aPrgBlocks        // Bloques @prg raw
   DATA aParams           // Parametros dinámicos pasados a Render()
   DATA aArgs             // Lista de nombres @args
   DATA aGlobal           // Lista de nombres @global
   DATA hExpression_Cached // Caché de validaciones precompiladas

   DATA cTranspiledPRG    // PRG generado resultante
   DATA aLineMap          // Mapa de trazabilidad para seguimiento de errores
   DATA aRawSource        // Lineas raw del template (para aCode en errores 9002)

   DATA lDebug            // .T. para imprimir mensajes de traza

   METHOD New( aLines, aParams, aPrgBlocks ) CONSTRUCTOR

   METHOD Run()
   METHOD ExtractDirectives()
   METHOD TranspileValidExpression( cExpr, aLine )
   METHOD ReplaceVars( cExpr, lIsHrb )
   METHOD BuildPRG()
   METHOD Array2String( aData )
   METHOD Array2StringNames( aArgs )
   METHOD SplitArgs( cText )
   METHOD SplitOnAssign( cText )

   METHOD ProcHrb( aLine, aBodyParts )
   METHOD ProcHtml( aLine, aBodyParts )

   METHOD TraceLineMap()
   METHOD GetLineLineMap( nLine )
   METHOD GetCodeLineMap( nLine )
   METHOD GetAllCodeLineMap()

   METHOD toMap( nLine, cargo )
   METHOD InfoLineMap( nLine_Search )

// METHOD ParseArgs( cLine )

   METHOD _t( ... )

ENDCLASS

// -------------------------------------------------------------
// New( aLines, aParams, aPrgBlocks )
// Constructor de la clase Hix_Transpile. Inicializa el estado por
// defecto y carga las estructuras resultantes del parser.
//
// Parámetros:
// aLines     - Matriz con las líneas parseadas.
// aParams    - Parámetros adicionales a inyectar al template.
// aPrgBlocks - Matriz de bloques @prg.
//
// Retorna:
// Self - La instancia creada.
//
// Ejemplo:
// oTranspile := Hix_Transpile():New( aResult, aParams, aBlocks )
// -------------------------------------------------------------
METHOD New( aLines, aParams, aPrgBlocks ) CLASS Hix_Transpile

   hb_Default( @aLines, {} )
   hb_Default( @aParams, {} )
   hb_Default( @aPrgBlocks, {} )

   ::aLines         := aLines
   ::aParams        := aParams
   ::aPrgBlocks     := aPrgBlocks

   ::aArgs          := {}
   ::aGlobal        := {}
   ::hExpression_Cached  := { => }

   ::cTranspiledPRG   := ""
   ::aLineMap         := {}
   ::aRawSource       := {}
   ::lDebug    := .F.

RETURN Self

// -------------------------------------------------------------
// InfoLineMap( nLine_Search )
// Obtiene el registro completo de aLineMap correspondiente
// a una línea específica del código fuente original.
//
// Parámetros:
// nLine_Search - Número de línea original a buscar.
//
// Retorna:
// Array - { nLineOriginal, cCodigo Generado } o 0 si no se encuentra.
//
// Ejemplo:
// aInfo := oTranspile:InfoLineMap( 15 )
// -------------------------------------------------------------
METHOD InfoLineMap( nLine_Search ) CLASS Hix_Transpile

   LOCAL n
   LOCAL nLen

   hb_default( @nLine_Search, 0 )

   IF nLine_Search > 0

      nLen := len( ::aLineMap )

      FOR n := 1 TO nLen

         IF ::aLineMap[ n ][ 1 ] == nLine_Search

            RETURN ::aLineMap[ n ]

         ENDIF

      NEXT

   ENDIF

RETURN 0

// -------------------------------------------------------------
// GetCodeLineMap( nLine )
// Obtiene el código Harbour transpiled de una línea específica
// (índice del array aLineMap, no la línea del fuente).
//
// Parámetros:
// nLine - Índice interno dentro del array aLineMap.
//
// Retorna:
// String - El código generado.
//
// Ejemplo:
// cCode := oTranspile:GetCodeLineMap( 5 )
// -------------------------------------------------------------
METHOD GetCodeLineMap( nLine ) CLASS Hix_Transpile

   hb_default( @nLine, 0 )

   IF nLine > 0 .AND. nLine <= len( ::aLineMap )

      RETURN ::aLineMap[ nLine ][ 2 ]

   ENDIF

RETURN ''

// -------------------------------------------------------------
// GetLineLineMap( nLine )
// Obtiene el número de línea original correspondiente al índice
// interno transpiled.
//
// Parámetros:
// nLine - Índice interno del array aLineMap.
//
// Retorna:
// Numeric - La línea del código fuente original.
//
// Ejemplo:
// nOrigLine := oTranspile:GetLineLineMap( 5 )
// -------------------------------------------------------------
METHOD GetLineLineMap( nLine ) CLASS Hix_Transpile

   hb_default( @nLine, 0 )

   IF nLine > 0 .AND. nLine <= len( ::aLineMap )

      RETURN ::aLineMap[ nLine ][ 1 ]

   ENDIF

RETURN 0

// -------------------------------------------------------------
// GetAllCodeLineMap()
// Devuelve un mapa completo de todas las líneas con su código
// original convertido a HTML seguro (UHtmlEncode).
// Útil para visualizar o rastrear el código generado en la web.
//
// Retorna:
// Array - Matriz de { nLineOriginal, cHTML_Escapado }.
//
// Ejemplo:
// aTraceMap := oTranspile:GetAllCodeLineMap()
// -------------------------------------------------------------
METHOD GetAllCodeLineMap() CLASS Hix_Transpile

   LOCAL n
   LOCAL aCode := {}
   LOCAL nLen  := len( ::aLineMap )

   FOR n := 1 TO nLen

      IF ::aLineMap[ n ][ 1 ] > 0

         Aadd( aCode, { ::aLineMap[ n ][ 1 ], UHtmlEncode( ::aLineMap[ n ][ 2 ] )  } )

      ENDIF

   NEXT

RETURN aCode

// -------------------------------------------------------------
// TraceLineMap()
// Imprime en consola (QOut) el contenido completo de aLineMap
// para fines de depuración visual de la trazabilidad.
//
// Ejemplo:
// oTranspile:TraceLineMap()
// -------------------------------------------------------------
METHOD TraceLineMap() CLASS Hix_Transpile

   LOCAL aRow

   FOR EACH aRow IN ::aLineMap

      ? StrZero( aRow[ 1 ], 4 ) + " " + UHtmlEncode( aRow[ 2 ] )

   NEXT

RETURN NIL

// -------------------------------------------------------------
// Run()

// Ejecuta el flujo principal del transpilador: extracción de
// directivas iniciales y construcción del PRG dinámico.
//
// Retorna:
// Pointer - Puntero opaco al HRB compilado.
//
// Ejemplo:
// oHrb := oTranspile:Run()
// -------------------------------------------------------------
METHOD Run() CLASS Hix_Transpile

   LOCAL oHrb

   ::ExtractDirectives()
   oHrb := ::BuildPRG()

RETURN oHrb

// -------------------------------------------------------------
// ExtractDirectives()
// Pre-procesa las líneas iniciales (aLines) del parser para
// extraer directivas configurativas como @args y @global, las
// cuales inyectan dependencias globales al template.
//
// Para @args, cada parametro puede tener un valor por defecto
// opcional declarado con '=' o ':='. Los valores pueden contener
// expresiones complejas (funciones, arrays, hashes) con comas
// internas. SplitArgs() y SplitOnAssign() gestionan este parseo.
//
// Ejemplo:
// oTranspile:ExtractDirectives()
// -------------------------------------------------------------
METHOD ExtractDirectives() CLASS Hix_Transpile

   LOCAL aLine, cFirst, cRest, nPos, cCode
   LOCAL aParts, cPart, aPair

   FOR EACH aLine IN ::aLines

      IF aLine[ PARSER_TYPE ] == 'HRB'

         cCode := AllTrim( aLine[ PARSER_CODE ] )
         nPos  := At( " ", cCode )

         IF nPos > 0

            cFirst := Lower( Left( cCode, nPos - 1 ) )
            cRest  := AllTrim( SubStr( cCode, nPos + 1 ) )
         ELSE
            cFirst := Lower( cCode )
            cRest  := ""

         ENDIF

         IF cFirst == "@args"

// Usar SplitArgs para respetar comas internas en valores
// (funciones, arrays, hashes). Cada elemento queda como
// { cNombre, cDefault } tras SplitOnAssign().
            aParts  := ::SplitArgs( cRest )
            ::aArgs := {}

            FOR EACH cPart IN aParts

               cPart := AllTrim( cPart )

               IF Empty( cPart ) ; LOOP ; ENDIF

               aPair := ::SplitOnAssign( cPart )
               AAdd( ::aArgs, { AllTrim( aPair[ 1 ] ), AllTrim( aPair[ 2 ] ) } )

            NEXT

         ELSEIF cFirst == "@global"
// ::aGlobal := hb_ATokens( cRest, "," )
// AEval( ::aGlobal, {|x, j| ::aGlobal[j] := AllTrim(x) } )

// Usar SplitArgs para respetar comas internas en valores
// (funciones, arrays, hashes). Cada elemento queda como
// { cNombre, cDefault } tras SplitOnAssign().
            aParts  := ::SplitArgs( cRest )
            ::aGlobal := {}

            FOR EACH cPart IN aParts

               cPart := AllTrim( cPart )

               IF Empty( cPart ) ; LOOP ; ENDIF

               aPair := ::SplitOnAssign( cPart )
               AAdd( ::aGlobal, { AllTrim( aPair[ 1 ] ), AllTrim( aPair[ 2 ] ) } )

            NEXT

         ENDIF

      ENDIF

   NEXT

RETURN NIL


// -------------------------------------------------------------
// ReplaceVars( cExpr, lIsHrb )
// Sustituye las variables declaradas en @args y @global por sus
// accesos equivalentes "__oPar:Variable".
//
// aArgs tiene ahora formato { { cNombre, cDefault }, ... }
// por lo que se accede al nombre via cKey[1].
//
// Parámetros:
// cExpr  - Expresión donde inyectar el reemplazo (String).
// lIsHrb - Mantenido para compatibilidad API.
//
// Retorna:
// String - Expresión modificada lista para transpilar.
//
// Ejemplo:
// cNew := oTranspile:ReplaceVars( "name + 1", .T. )
// -------------------------------------------------------------
METHOD ReplaceVars( cExpr, lIsHrb ) CLASS Hix_Transpile

   LOCAL cKey, cLower, cVarName

   IF Empty( ::aArgs ) .AND. Empty( ::aGlobal )

      RETURN cExpr

   ENDIF

   cLower := Lower( cExpr )

// aArgs = { { cNombre, cDefault }, ... }

   FOR EACH cKey IN ::aArgs

      cVarName := cKey[ 1 ]

      IF hb_At( Lower( cVarName ), cLower ) > 0

         cExpr := hb_RegExReplace( "(?i)\b" + cVarName + "\b", cExpr, '__oPar:' + cVarName )

      ENDIF

   NEXT

// aGlobal = { { cNombre, cDefault }, ... } — igual que aArgs

   FOR EACH cKey IN ::aGlobal

      cVarName := cKey[ 1 ]

      IF hb_At( Lower( cVarName ), cLower ) > 0

         cExpr := hb_RegExReplace( "(?i)\b" + cVarName + "\b", cExpr, '__oPar:' + cVarName )

      ENDIF

   NEXT

RETURN cExpr

// -------------------------------------------------------------
// TranspileValidExpression( cExpr, aLine )
// Evalúa la sintaxis de una expresión sin correrla, con caché
// para repeticiones idénticas. Muestra un error si es inválida.
//
// Parámetros:
// cExpr  - Expresión a validar (String).
// aLine  - Fila del parser { nLine, cType, cCode }.
//
// Retorna:
// Logic - .T. si la sintaxis es válida.
//
// Ejemplo:
// lOk := oTranspile:TranspileValidExpression( "1 + 1", aLine )
// -------------------------------------------------------------
METHOD TranspileValidExpression( cExpr, aLine ) CLASS Hix_Transpile

   LOCAL bCode, oErr, oErrView
   LOCAL lValid := .F.
   LOCAL nLine  := aLine[ PARSER_LINE ]

   IF hb_HHasKey( ::hExpression_Cached, cExpr )

      RETURN .T.

   ENDIF

   TRY

// Valida sintaxis, no chequea existencia en runtime
      bCode  := &( '{|| ' + cExpr + '}' )
      lValid := .T.
      ::hExpression_Cached[ cExpr ] := .T.

   CATCH oErr
      oErrView := HIX_ErrorView( oErr, 9002, "Sintax error: " + oErr:description, nLine, UHtmlEncode( cExpr ), "hix_view_transpile" )
      oErrView:cargo[ "aCode" ] := ::aRawSource
      HIX_Throw( oErrView )

   END

   bCode := NIL

RETURN lValid

// -------------------------------------------------------------

// -------------------------------------------------------------
// BuildPRG()
// El motor principal del generador de código. Procesa secuencialemente
// aLines y aPrgBlocks iterando las lógicas condicionales transformadas
// (ProcHrb) y las secciones DOM (ProcHtml). Compila y vincula.
//
// Retorna:
// Pointer - Retorna el Handler de PCode HRB compilado dinámicamente.
// Un fracaso en compilación dispara una excepción.
//
// Ejemplo:
// oTranspile:BuildPRG()
// -------------------------------------------------------------
METHOD BuildPRG() CLASS Hix_Transpile

   LOCAL aBodyParts := {}
   LOCAL aLine, i, aCode, n, cCodeTrace
   LOCAL oTest, oError, cBlock, aLines, oHrb
   LOCAL oErrorView, nLine
   LOCAL z, nStartLineBlock
   LOCAL aPair

   aLines := {}


   AAdd( aBodyParts, "FUNCTION Hix_Template( oPar )" + hb_eol() )
   ::ToMap( 0, "FUNCTION Hix_Template" )

   AAdd( aBodyParts, "   LOCAL __cOut := ''" + hb_eol() )
   ::ToMap( 0 )

   AAdd( aBodyParts, "   PRIVATE __oPar := oPar" + hb_eol() )
   ::ToMap( 0 )


// Pasar solo los nombres al objeto par (Array2StringNames extrae [1] de cada par)
   AAdd( aBodyParts, "   __oPar:aArgs := " + ::Array2StringNames( ::aArgs ) + hb_eol() )
   ::ToMap( 0 )

   AAdd( aBodyParts, "   __oPar:aGlobal := " + ::Array2StringNames( ::aGlobal ) + hb_eol() )
   ::ToMap( 0 )

   AAdd( aBodyParts, "   __oPar:Init()" +  hb_eol() )
   ::ToMap( 0 )

// Inyectar valores por defecto para @args que los tengan declarados.
// Se aplican DESPUES de Init() para que los parametros pasados tengan
// prioridad: si __oPar:var es NIL (no fue pasado), se asigna el default.

   FOR EACH aPair IN ::aArgs

      IF ! Empty( aPair[ 2 ] )

         AAdd( aBodyParts, "   IF HB_IsNil( __oPar:" + aPair[ 1 ] + " ) ; " + ;
            "__oPar:" + aPair[ 1 ] + " := " + aPair[ 2 ] + " ; ENDIF" + hb_eol() )
         ::ToMap( 0 )

      ENDIF

   NEXT

// Fer el  mateix per @global

   FOR EACH aPair IN ::aGlobal

      IF ! Empty( aPair[ 2 ] )

         AAdd( aBodyParts, "   IF HB_IsNil( __oPar:" + aPair[ 1 ] + " ) ; " + ;
            "__oPar:" + aPair[ 1 ] + " := " + aPair[ 2 ] + " ; ENDIF" + hb_eol() )
         ::ToMap( 0 )

      ENDIF

   NEXT

// Volcar el cuerpo linea a linea

   FOR EACH aLine IN ::aLines

      DO CASE

         CASE aLine[ PARSER_TYPE ] == 'HRB' ; ::ProcHrb( aLine, aBodyParts )
         CASE aLine[ PARSER_TYPE ] == 'HTML'; ::ProcHtml( aLine, aBodyParts )

      ENDCASE

   NEXT

// Cierre de funcion
   AAdd( aBodyParts, "   __oPar:End()" + hb_eol() )
   ::ToMap( 0 )

   AAdd( aBodyParts, "   __oPar := nil " + hb_eol() )
   ::ToMap( 0 )

   AAdd( aBodyParts, "RETURN __cOut" + hb_eol() )
   ::ToMap( 0 )

   ::_t( '>> Transpile:BuildPrg' )

// Volcar funciones externas estáticas (bloques @prg)

   IF Len( ::aPrgBlocks ) > 0

      ::_t( '>> Need compile blocks' )

   ENDIF

   FOR i := 1 TO Len( ::aPrgBlocks )

      ::_t( '>> Compile block @prg ' + ltrim( str( i ) ) )

      cBlock := "static function __block" + AllTrim( Str( i ) ) + "( __oPar )" + chr( 10 )
      cBlock += ::ReplaceVars( ::aPrgBlocks[ i ][ 2 ], .T. )

      TRY

         oTest := hb_CompileFromBuf( cBlock, .T., "-n", "-q2" )
      CATCH oError

         IF !empty( oError:cargo )

            _t( 'Trenco!' )

            IF !empty( oError:operation )

               IF substr( oError:operation, 1, 5 ) == 'line:'

                  nLine := Val( substr( oError:operation, 6 ) )
                  oError:procline := nLine

               ENDIF

            ENDIF

            break oError

         ENDIF

         ::_t( '>> Transpile:BuildPrg() Error 9005' )
         ::_t( '>> Description: ' + oError:description )
         ::_t( '>> Operation: ' + oError:operation )

         aLines := hb_atokens( cBlock, Chr( 10 ) )

// Primera linea eliminarem: "static function __blockxxx"
         aLines[ 1 ] := ''


         oErrorView := HIX_ErrorView( oError, 9005, NIL, NIL, NIL, "hix_view_transpile" )
         oErrorView:cargo[ "aCode" ] := aLines

         IF ! Empty( oError:operation )

            IF SubStr( oError:operation, 1, 5 ) == 'line:'

               nLine := Val( SubStr( oError:operation, 6 ) )

               IF Len( aLines ) > 0 .AND. nLine <= Len( aLines )

                  oErrorView:cargo[ "line"      ] := nLine
                  oErrorView:cargo[ "line_code" ] := aLines[ nLine ]

               ENDIF

            ENDIF

         ENDIF

         break oErrorView

         RETURN NIL

      END

   NEXT


// Ya validamos pre-compilación, ahora volcamos los bloques a la rutina

   ::ToMap( 0, '<END OF PROGRAM>' )

   FOR i := 1 TO Len( ::aPrgBlocks )

      AAdd( aBodyParts, hb_eol() + "static function __block" + AllTrim( Str( i ) ) + "()" + chr( 10 ) )

      nStartLineBlock := ::aPrgBlocks[ i ][ 1 ]


      ::ToMap( nStartLineBlock, "function __block" + AllTrim( Str( i ) ) + "()" )

      nStartLineBlock++

      aCode := hb_atokens( ::ReplaceVars( ::aPrgBlocks[ i ][ 2 ], .T. ), Chr( 10 ) )

      FOR n := 1 TO Len( aCode )

         AAdd( aBodyParts, aCode[ n ] + hb_eol() )
         ::ToMap( nStartLineBlock, aCode[ n ] )

         nStartLineBlock++

      NEXT

   NEXT

   cCodeTrace := hb_jsonencode( ::aLineMap )
   AAdd( aBodyParts, "function __trace() ; RETURN '" + hb_base64Encode( cCodeTrace ) + "'" + chr( 10 ) )

   ::cTranspiledPRG := ""

   FOR i := 1 TO Len( aBodyParts )

      ::cTranspiledPRG += aBodyParts[ i ]

   NEXT

   ::_t( '>> Compiling Transpile...' )

   TRY

      oHrb := hb_CompileFromBuf( ::cTranspiledPRG, .T., "-n", "-q2" )
   CATCH oError

      IF !empty( oError:cargo )

         IF !empty( oError:operation )

            IF substr( oError:operation, 1, 5 ) == 'line:'

               nLine := Val( substr( oError:operation, 6 ) )
               oError:procline := nLine

            ENDIF

         ENDIF

         break oError

      ENDIF

      ::_t( '>> Transpile:BuildPrg() Error 9006' )

      ::_t( ::cTranspiledPRG )

      oErrorView := HIX_ErrorView( oError, 9006, NIL, NIL, NIL, "hix_view_transpile" )

      IF ! Empty( oError:operation )

         IF SubStr( oError:operation, 1, 5 ) == 'line:'

            nLine := Val( SubStr( oError:operation, 6 ) )

            IF nLine > 0 .AND. nLine <= Len( ::aLineMap )

               oErrorView:cargo[ "line"       ] := ::aLineMap[ nLine ][ 1 ]
               oErrorView:cargo[ "line_code"  ] := ::aLineMap[ nLine ][ 2 ]
               oErrorView:cargo[ "line_index" ] := nLine
               oErrorView:cargo[ "aCode"      ] := ::aLineMap

            ENDIF

         ENDIF

      ENDIF

      break oErrorView

      RETURN NIL

   END

   ::_t( 'Transpiled file compiled Ok ' )

RETURN oHrb

// -------------------------------------------------------------
// ProcHrb( aLine, aBodyParts )
// Procesa una línea de directiva Harbour reconocida y traduce su
// lógica HIX a sentencias Harbour PRG equivalentes.
//
// Parámetros:
// aLine      - Matriz origen desde el parser con el código.
// aBodyParts - Matriz referencia donde se acumulan las líneas PRG.
//
// Ejemplo:
// oTranspile:ProcHrb( aRow, aBodyParts )
// -------------------------------------------------------------
METHOD ProcHrb( aLine, aBodyParts ) CLASS Hix_Transpile

   LOCAL cTrimLine, cFirst, cRest, nPos, nPosSpace, nPosParen

   cTrimLine := AllTrim( aLine[ PARSER_CODE ] )
   nPosSpace := At( " ", cTrimLine )
   nPosParen := At( "(", cTrimLine )

   IF nPosSpace > 0 .AND. nPosParen > 0

      nPos := Min( nPosSpace, nPosParen )
   ELSEIF nPosSpace > 0
      nPos := nPosSpace
   ELSEIF nPosParen > 0
      nPos := nPosParen
   ELSE
      nPos := 0

   ENDIF

   IF nPos > 0

      cFirst := Lower( Left( cTrimLine, nPos - 1 ) )

      IF nPos == nPosParen

         cRest  := AllTrim( SubStr( cTrimLine, nPos ) )
      ELSE
         cRest  := AllTrim( SubStr( cTrimLine, nPos + 1 ) )

      ENDIF

   ELSE
      cFirst := Lower( cTrimLine )
      cRest  := ""

   ENDIF

// Las directivas de variables ya fueron procesadas en ExtractDirectives()

   IF cFirst == "@args" .OR. cFirst == "@global"

      RETURN NIL

   ENDIF

   AADD( ::aLineMap, { aLine[ PARSER_LINE ], aLine[ PARSER_CODE ] }  )

   DO CASE

      CASE cFirst == "@if"
         ::TranspileValidExpression( cRest, aLine )
         AAdd( aBodyParts, "   IF ( " + ::ReplaceVars( cRest, .T. ) + " )" + hb_eol() )

      CASE cFirst == "@else"
         AAdd( aBodyParts, "   ELSE" + hb_eol() )

      CASE cFirst == "@elseif"
         ::TranspileValidExpression( cRest, aLine )
         AAdd( aBodyParts, "   ELSEIF ( " + ::ReplaceVars( cRest, .T. ) + " )" + hb_eol() )

      CASE cFirst == "@endif"
         AAdd( aBodyParts, "   ENDIF" + hb_eol() )

      CASE cFirst == "@foreach"
// Extraer variable indexadora del foreach "oItem IN aData"
         nPos := At( " IN ", Upper( cRest ) )

      IF nPos > 0

         ::TranspileValidExpression( AllTrim( Left( cRest, nPos - 1 ) ), aLine )
         AAdd( aBodyParts, "   PRIVATE " + AllTrim( Left( cRest, nPos - 1 ) ) + hb_eol() )

         ENDIF

         AAdd( aBodyParts, "   FOR EACH " + ::ReplaceVars( cRest, .T. ) + hb_eol() )

      CASE cFirst == "@endforeach"
         AAdd( aBodyParts, "   NEXT" + hb_eol() )

      CASE cFirst == "@for"
// Extraer variable indexadora del for "nI := 1 to 10"
         nPos := At( ":=", cRest )

      IF nPos > 0

         ::TranspileValidExpression( AllTrim( Left( cRest, nPos - 1 ) ), aLine )
         AAdd( aBodyParts, "   PRIVATE " + AllTrim( Left( cRest, nPos - 1 ) ) + hb_eol() )

         ENDIF

// NOTA: No podemos hacer TranspileValidExpression( cRest ) porque contiene 'TO'
         AAdd( aBodyParts, "   FOR " + ::ReplaceVars( cRest, .T. ) + hb_eol() )

      CASE cFirst == "@next"
         AAdd( aBodyParts, "   NEXT" + hb_eol() )

      CASE cFirst == "@prg"
         AAdd( aBodyParts, "   __cOut += UStr( __" + cRest + "() )" + hb_eol() )

      CASE cFirst == "@view"

         AAdd( aBodyParts, "   __cOut += UStr( UView_Exec( " + ::ReplaceVars( cRest, .T. ) + " ) )" + hb_eol() )

      CASE cFirst == "@css"

         AAdd( aBodyParts, "   __cOut += UView_Css( " + cRest + " ) " + hb_eol() )

      CASE cFirst == "@js"

         AAdd( aBodyParts, "   __cOut += UView_JS( " + cRest + " ) " + hb_eol() )

      CASE cFirst == "@csrf"

         AAdd( aBodyParts, "   __cOut += UCsrfToHtml() " + hb_eol() )

      CASE cFirst == "@resource"

         ::TranspileValidExpression( cRest, aLine )

         AAdd( aBodyParts, "   __cOut += UResourceToHtml( " + ::ReplaceVars( cRest, .T. ) + " ) " + hb_eol() )

   ENDCASE

RETURN NIL

// -------------------------------------------------------------
// ProcHtml( aLine, aBodyParts )
// Transforma un bloque de texto libre/HTML puro que puede
// contener macros intercaladas {{ }} o {!! !!}. Escapa las
// comillas y envuelve la salida en operaciones de concatenación.
//
// Parámetros:
// aLine      - Matriz origen con el código HTML crudo.
// aBodyParts - Matriz referencia donde amontonar código generado.
//
// Ejemplo:
// oTranspile:ProcHtml( aRow, aBodyParts )
// -------------------------------------------------------------
METHOD ProcHtml( aLine, aBodyParts ) CLASS Hix_Transpile

   LOCAL cHtml := aLine[ PARSER_CODE ]
   LOCAL cOut  := ""
   LOCAL nLen  := Len( cHtml )
   LOCAL nI    := 1
   LOCAL nPosL, nPosR, cText, cMacro, cSafeMacro
   LOCAL nOpenEsc, nOpenUnesc, cTagType, nTagLen, cCloseTag

   WHILE nI <= nLen

      nOpenEsc   := hb_At( "{{", cHtml, nI )
      nOpenUnesc := hb_At( "{!!", cHtml, nI )

// Determinar cual macro aparece primero

      IF nOpenEsc == 0 .AND. nOpenUnesc == 0

         nPosL := 0
      ELSEIF nOpenUnesc > 0 .AND. ( nOpenEsc == 0 .OR. nOpenUnesc < nOpenEsc )
         nPosL := nOpenUnesc
         cTagType := "{!!"
         nTagLen  := 3
      ELSE
         nPosL := nOpenEsc
         cTagType := "{{"
         nTagLen  := 2

      ENDIF

// 1. Text plain final sin macros

      IF nPosL == 0

         cText := SubStr( cHtml, nI )

         IF !Empty( cOut )

            cOut += " + "

         ENDIF

// Se encapsula evitar colisión de array y comillas dobles
         cOut += "'" + StrTran( cText, "'", "' + Chr(39) + '" ) + "'"
         EXIT

      ENDIF

// 2. Text plain antes de un chunk macro

      IF nPosL > nI

         cText := SubStr( cHtml, nI, nPosL - nI )

         IF !Empty( cOut )

            cOut += " + "

         ENDIF

         cOut += "'" + StrTran( cText, "'", "' + Chr(39) + '" ) + "'"

      ENDIF

// 3. Extraccion y chequeo macro
      cCloseTag := iif( cTagType == "{{", "}}", "!!}" )
      nPosR := hb_At( cCloseTag, cHtml, nPosL + nTagLen )

      IF nPosR > 0

         cMacro := SubStr( cHtml, nPosL + nTagLen, nPosR - nPosL - nTagLen )

// Validar macro original sintácticamente
         ::TranspileValidExpression( AllTrim( cMacro ), aLine )

// Variables => __oPar:var
         cSafeMacro := ::ReplaceVars( cMacro, .F. )

         IF !Empty( cOut )

            cOut += " + "

         ENDIF

         IF cTagType == "{{"

            cOut += "UHtmlEncode( UStr( " + cSafeMacro + " ) )"
         ELSE
            cOut += "UStr( " + cSafeMacro + " )"

         ENDIF

         nI := nPosR + Len( cCloseTag )

      ELSE

// Tag corrupto, cerramos el resto
         cText := SubStr( cHtml, nPosL )

         IF !Empty( cOut )

            cOut += " + "

         ENDIF

         cOut += "'" + StrTran( cText, "'", "' + Chr(39) + '" ) + "'"
         EXIT

      ENDIF

   ENDDO

   IF !Empty( cOut )

      AAdd( aBodyParts, "   __cOut += " + cOut + " + Chr(10)" + hb_eol() )
   ELSE
      AAdd( aBodyParts, "   __cOut += Chr(10)" + hb_eol() )

   ENDIF

   ::ToMap( aLine[ PARSER_LINE ], aLine[ PARSER_CODE ] )

RETURN NIL

// -------------------------------------------------------------
// Array2String( aData )
// Convierte un array unidimensional Harbour de cadenas en su
// representación literal de inicialización en tiempo de ejecución.
//
// Parámetros:
// aData - Matriz de textos a serializar.
//
// Retorna:
// String - Array transformado, ej. "{'a', 'b'}"
// -------------------------------------------------------------
METHOD Array2String( aData ) CLASS Hix_Transpile

   LOCAL cArray := '{'
   LOCAL n, nLen

   IF ValType( aData ) == 'A' .AND. Len( aData ) > 0

      nLen := Len( aData )

      FOR n := 1 TO ( nLen - 1 )

         cArray += "'" + AllTrim( aData[ n ] ) + "', "

      NEXT

      cArray += "'" + AllTrim( aData[ nLen ] )  + "'"

   ENDIF

   cArray += '}'

RETURN cArray


// -------------------------------------------------------------
// Array2StringNames( aArgs )
// Extrae solo los nombres (elemento [1]) del array de @args con
// formato { { cNombre, cDefault }, ... } y genera la representacion
// literal equivalente para inicializar __oPar:aArgs en el PRG.
//
// Parámetros:
// aArgs - Array de pares { { cNombre, cDefault }, ... }
//
// Retorna:
// String - Literal array Harbour con los nombres, ej. "{'par1','hora'}"
//
// Ejemplo:
// Array2StringNames( { {"par1",""}, {"hora","time()"} } )
// => "{'par1', 'hora'}"
// -------------------------------------------------------------
METHOD Array2StringNames( aArgs ) CLASS Hix_Transpile

   LOCAL cArray := '{'
   LOCAL n, nLen

   IF ValType( aArgs ) == 'A' .AND. Len( aArgs ) > 0

      nLen := Len( aArgs )

      FOR n := 1 TO ( nLen - 1 )

         cArray += "'" + AllTrim( aArgs[ n ][ 1 ] ) + "', "

      NEXT

      cArray += "'" + AllTrim( aArgs[ nLen ][ 1 ] ) + "'"

   ENDIF

   cArray += '}'

RETURN cArray


// -------------------------------------------------------------
// SplitArgs( cText )
// Divide una lista de argumentos separados por coma, respetando
// el anidamiento de (), [], {} y los strings con ' y ".
// Replica la logica del parser para usarse en el transpilador.
//
// Ejemplo:
// SplitArgs( "par1, par2 := MyFunc('a',1), par3" )
// => { "par1", "par2 := MyFunc('a',1)", "par3" }
// -------------------------------------------------------------
METHOD SplitArgs( cText ) CLASS Hix_Transpile

   LOCAL aResult  := {}
   LOCAL cCurrent := ""
   LOCAL nDepth   := 0
   LOCAL lInStr   := .F.
   LOCAL cStrChar := ""
   LOCAL cChar, i

   FOR i := 1 TO Len( cText )

      cChar := SubStr( cText, i, 1 )

      DO CASE

         CASE lInStr
            cCurrent += cChar

         IF cChar == cStrChar

            lInStr := .F.

            ENDIF

         CASE cChar == '"' .OR. cChar == "'"
            lInStr   := .T.
            cStrChar := cChar
            cCurrent += cChar

         CASE cChar == "(" .OR. cChar == "[" .OR. cChar == "{"
            nDepth++
            cCurrent += cChar

         CASE cChar == ")" .OR. cChar == "]" .OR. cChar == "}"
            nDepth--
            cCurrent += cChar

         CASE cChar == "," .AND. nDepth == 0
            AAdd( aResult, AllTrim( cCurrent ) )
            cCurrent := ""

         OTHERWISE
            cCurrent += cChar

      ENDCASE

   NEXT

   IF ! Empty( AllTrim( cCurrent ) )

      AAdd( aResult, AllTrim( cCurrent ) )

   ENDIF

RETURN aResult


// -------------------------------------------------------------
// SplitOnAssign( cText )
// Busca el primer ':=' o '=' en nivel 0 y divide en
// { cNombre, cValorDefault }. Si no hay asignacion: { cText, "" }
// Replica la logica del parser para usarse en el transpilador.
//
// Ejemplos:
// SplitOnAssign( "hora := time()" )     => { "hora", "time()" }
// SplitOnAssign( "h = { 'k'=>'v' }" )   => { "h", "{ 'k'=>'v' }" }
// SplitOnAssign( "par1" )               => { "par1", "" }
// -------------------------------------------------------------
METHOD SplitOnAssign( cText ) CLASS Hix_Transpile

   LOCAL nDepth   := 0
   LOCAL lInStr   := .F.
   LOCAL cStrChar := ""
   LOCAL cChar, cNext, cPrev, i
   LOCAL nLen     := Len( cText )

   FOR i := 1 TO nLen

      cChar := SubStr( cText, i, 1 )
      cNext := iif( i < nLen, SubStr( cText, i + 1, 1 ), "" )
      cPrev := iif( i > 1,   SubStr( cText, i - 1, 1 ), "" )

      DO CASE

         CASE lInStr

         IF cChar == cStrChar

            lInStr := .F.

            ENDIF

         CASE cChar == '"' .OR. cChar == "'"
            lInStr   := .T.
            cStrChar := cChar

         CASE cChar == "(" .OR. cChar == "[" .OR. cChar == "{"
            nDepth++

         CASE cChar == ")" .OR. cChar == "]" .OR. cChar == "}"
            nDepth--

         CASE cChar == ":" .AND. cNext == "=" .AND. nDepth == 0
            RETURN { AllTrim( Left( cText, i - 1 ) ), ;
            AllTrim( SubStr( cText, i + 2 ) ) }

         CASE cChar == "=" .AND. nDepth == 0

         IF cNext == ">" .OR. cNext == "="

            LOOP

            ENDIF

         IF cPrev $ "<!>="

            LOOP

            ENDIF

            RETURN { AllTrim( Left( cText, i - 1 ) ), ;
            AllTrim( SubStr( cText, i + 1 ) ) }

      ENDCASE

   NEXT

RETURN { AllTrim( cText ), "" }


METHOD toMap( nLine, cargo ) CLASS Hix_Transpile

   hb_default( @nLine, 0 )
   hb_default( @cargo, '' )

   AADD( ::aLineMap, { nLine, cargo }  )

   RETU NIL

// -------------------------------------------------------------
// _t( ... )
// Utilidad interna para volcar trazas de depuración estándar,
// condicionadas por la propiedad `::lDebug`.
// -------------------------------------------------------------

METHOD _t( ... ) CLASS Hix_Transpile

   IF ::lDebug

      _t( ... )

   ENDIF

RETURN NIL

// -------------------------------------------------------------

