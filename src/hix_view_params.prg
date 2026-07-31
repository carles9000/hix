/*-----------------------------------------------------------
  File ......: hix_view_params.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: THixViewParams — parameter container passed to compiled
               view HRB modules.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#INCLUDE "hbclass.ch"
#INCLUDE "error.ch"
#INCLUDE "hix_const.ch"
#INCLUDE "hix_hrb.ch"


CLASS Hix_View_Params

   DATA aParams
   DATA aArgs
   DATA aGlobal
   DATA hVars   INIT { => }
   DATA cTime     INIT time()

   METHOD New( aParams ) CONSTRUCTOR
   METHOD End()

// METHOD InitArgs( aArgs )
// METHOD ValidateExpr( cExpr )

// METHOD ParseArgs( cLine )

   METHOD Init()

   ERROR HANDLER OnError

ENDCLASS

// -------------------------------------------------------------

METHOD New( aParams ) CLASS Hix_View_Params

   ::aParams  := aParams
   ::hVars  := { => }

RETURN Self

// -------------------------------------------------------------

METHOD Init() CLASS Hix_View_Params

   LOCAL i, cKey, nParams

// Numero de parametros realmente pasados a Render()
   nParams := Len( ::aParams )

// Las claves de hVars se guardan en MAYUSCULAS porque Harbour convierte
// internamente los nombres de mensaje a mayusculas antes de llamar a OnError.
// Por tanto __oPar:test y __oPar:TEST producen el mismo mensaje "TEST".
// Guardando en Upper() la busqueda en OnError siempre coincide.

   ::hVars := { => }

// --- Inicializar @args ---
// Regla posicional:
// - Si se paso el parametro i => hVars[Upper(aArgs[i])] := aParams[i]
// - Si NO se paso            => hVars[Upper(aArgs[i])] := NIL
// (el transpilado aplicara el default con IF HB_IsNil(...))
// - Se permiten mas @args que parametros (defaults cubren el resto)
// - Parametros sobrantes respecto a @args se ignoran

   FOR i := 1 TO Len( ::aArgs )

      cKey := Upper( ::aArgs[ i ] )

      IF i <= nParams

         ::hVars[ cKey ] := ::aParams[ i ]
      ELSE
         ::hVars[ cKey ] := NIL

      ENDIF

   NEXT

// --- Inicializar @global ---
// En runtime, ::aGlobal es un array plano de strings { "test", "otra", ... }
// porque Array2StringNames serializa solo los nombres al PRG transpilado.
//
// Se inicializan a NIL (igual que @args sin parametro) para que el transpilado
// pueda aplicar el valor por defecto con IF HB_IsNil(...).
// Si no hay default declarado, quedara NIL y el template lo mostrara como ''.

   FOR i := 1 TO Len( ::aGlobal )

      cKey := Upper( ::aGlobal[ i ] )

      IF HB_HHasKey( ::hVars, cKey )

         HIX_DoErrorView( NIL, 9004, "@global variable '" + cKey + "' already declared in @args", NIL, NIL, "hix_view_params" )
      ELSE
         ::hVars[ cKey ] := NIL

      ENDIF

   NEXT

   RETU NIL


// --------------------------------------------------- //

STATIC FUNCTION SplitArgTokens( cArgs )

   LOCAL aTokens    := {}
   LOCAL cToken     := ""
   LOCAL nParen     := 0
   LOCAL nBrace     := 0
   LOCAL nBracket   := 0
   LOCAL lInSingle  := .F.    // dentro de '...'
   LOCAL lInDouble  := .F.    // dentro de "..."
   LOCAL i, c, cPrev, oError

// BEGIN SEQUENCE WITH { | oErr | SplitArgTokens_Error( oErr, @aTokens, @cToken ) }

   TRY

      FOR i := 1 TO LEN( cArgs )

         c      := SUBSTR( cArgs, i, 1 )
         cPrev  := IF( i > 1, SUBSTR( cArgs, i - 1, 1 ), "" )

         DO CASE

// -- Gestión de strings con comillas simples
            CASE c == "'" .AND. !lInDouble
               lInSingle := !lInSingle
               cToken += c

// -- Gestión de strings con comillas dobles
            CASE c == '"' .AND. !lInSingle
               lInDouble := !lInDouble
               cToken += c

// -- Si estamos dentro de un string, acumular sin interpretar
            CASE lInSingle .OR. lInDouble
               cToken += c

// -- Paréntesis
            CASE c == "("  ;  nParen++;  cToken += c
            CASE c == ")"  ;  nParen--;  cToken += c

// -- Llaves
            CASE c == "{"  ;  nBrace++;  cToken += c
            CASE c == "}"  ;  nBrace--;  cToken += c

// -- Corchetes
            CASE c == "["  ;  nBracket++;  cToken += c
            CASE c == "]"  ;  nBracket--;  cToken += c

// -- Coma separadora solo si estamos al nivel raíz
            CASE c == "," .AND. nParen == 0 .AND. nBrace == 0 .AND. nBracket == 0
               AADD( aTokens, ALLTRIM( cToken ) )
               cToken := ""

            OTHERWISE
               cToken += c

         ENDCASE

      NEXT

      IF !EMPTY( ALLTRIM( cToken ) )

         AADD( aTokens, ALLTRIM( cToken ) )

      ENDIF

   CATCH oError

      HIX_DoErrorView( oError, 9002, "Sintax error: " + oError:description, 0, '@args => ' + cArgs, "hix_view_params" )

   END

RETURN aTokens


// -------------------------------------------------------------

METHOD OnError() CLASS Hix_View_Params

   LOCAL cMsg := __GetMessage()
   LOCAL lAssign  := Left( cMsg, 1 ) == '_'

   IF lAssign

      cMsg := SubStr( cMsg, 2 )

   ENDIF

   IF lAssign

      ::hVars[ cMsg ] := HB_AParams()[ 1 ]
   ELSE

      IF hb_HHasKey( ::hVars, cMsg )

         RETURN ::hVars[ cMsg ]

      ENDIF

      RETU  '*** ERROR -->>' + cMsg

   ENDIF

RETURN NIL

// -------------------------------------------------------------

METHOD End() CLASS Hix_View_Params

   ::aParams  := nil
   ::aArgs  := nil
   ::aGlobal := nil

   RETU NIL


// ============================================================
// HIX_DoErrorView — crea error de vista y hace break
// ============================================================

FUNCTION HIX_DoErrorView( oError, nCode, cDescription, nLine, cLine_Code, cModule )

   LOCAL o

   o := HIX_ErrorView( oError, nCode, cDescription, nLine, cLine_Code, cModule )
   HIX_Throw( o )

RETURN NIL

// ============================================================
// HIX_ErrorView — fabrica un ERROR estandar con cargo hash
// cargo = { "system", "module", "process", "view_code", "line", "line_code", "aCode" }
// subCode = HTTP status (404, 500...) — nunca el 900x view code
// ============================================================
FUNCTION HIX_ErrorView( oError, nCode, cDescription, nLine, cLine_Code, cModule )

   LOCAL oErr, cSubsystem, hExtra, nHttpCode

   hb_default( @nCode,        9000 )
   hb_default( @cDescription, ""   )
   hb_default( @nLine,        0    )
   hb_default( @cLine_Code,   ""   )
   hb_default( @cModule,      ""   )

   DO CASE

      CASE nCode == 9001 ; cSubsystem := "Parser"
      CASE nCode == 9002 ; cSubsystem := "Transpile"
      CASE nCode == 9004 ; cSubsystem := "Execute"
      CASE nCode == 9005 ; cSubsystem := "Prg block"
      CASE nCode == 9006 ; cSubsystem := "Prg transpiled"
      CASE nCode == 9009 ; cSubsystem := "View recursion"
      CASE nCode == 9010 ; cSubsystem := "Load"
      CASE nCode == 9011 ; cSubsystem := "Load"
      OTHERWISE          ; cSubsystem := "View"

   ENDCASE

   nHttpCode := iif( nCode == 9010, 404, 500 )

   oErr            := ErrorNew()
   oErr:subSystem  := cSubsystem
   oErr:subCode    := nHttpCode
   oErr:genCode    := EG_ARG
   oErr:severity   := ES_ERROR
   oErr:description := iif( ! Empty( cDescription ), cDescription, ;
      iif( ValType( oError ) == "O", ;
      hb_defaultValue( oError:description, "" ), "" ) )
   oErr:operation   := iif( nLine > 0, "line:" + hb_NToS( nLine ), ;
      iif( ValType( oError ) == "O", ;
      hb_defaultValue( oError:operation, "" ), "" ) )
   oErr:filename    := iif( ValType( oError ) == "O", ;
      hb_defaultValue( oError:filename, "" ), "" )

   hExtra := { => }
   hExtra[ "system"    ] := "View"
   hExtra[ "module"    ] := cModule
   hExtra[ "process"   ] := cSubsystem
   hExtra[ "view_code" ] := nCode
   hExtra[ "line"      ] := nLine
   hExtra[ "line_code" ] := cLine_Code
   hExtra[ "aCode"     ] := {}
   oErr:cargo := hExtra

RETURN oErr
