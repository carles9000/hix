/*-----------------------------------------------------------
  File ......: hix_prepro.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-10
  Description: Template preprocessor — converts HIX view syntax to executable
               Harbour PRG. Based on mod_harbour.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
/*
**  Original code from modHarbour
**
** Developed by Antonio Linares & Carles Aubia
** MIT license https://github.com/FiveTechSoft/mod_harbour/blob/master/LICENSE
*/


#DEFINE HIX_LOG_MODULE HIX_MOD_DISPATCHER

#INCLUDE "common.ch"
#INCLUDE "hix_logger.ch"
#INCLUDE "hbhrb.ch"


// ------------------------------------------------------------- //

#XCOMMAND VIEW <into:TO,INTO> <o> => #pragma __cstream|<o> += %s

#XCOMMAND VIEW <into:TO,INTO> <o> [ PARAMS [<v1>] [,<vn>] ] ;
      => ;
      #pragma __cstream | < o > += UInlinePRG( UReplaceBlocks( % s, '<$', "$>"[, < ( v1 ) > ][ + "," + < ( vn ) > ][, @ < v1 > ][, @ < vn > ] ), NIL[, @ < v1 > ][, @ < vn > ]  )


#XCOMMAND TRY  => BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }
#XCOMMAND CATCH [<!oErr!>] => RECOVER [USING <oErr>] <-oErr->
#XCOMMAND FINALLY => ALWAYS

// ------------------------------------------------------------- //
/*
| Función                   | ¿Cuándo?                   | ¿Cuántas veces?      |
| ------------------------- | -------------------------- | -------------------- |
| __pp_Init()               | Al arrancar la aplicación  | 1 sola vez           |
| __pp_AddRule()            | Justo después del Init     | 1 sola vez por regla |
| __pp_Reset()              | Antes de cada __pp_Process | Cada vez             |
| __pp_AddRule() (re-apply) | Justo después del Reset    | Cada vez             |
| __pp_Process()            | En tu función de negocio   | Cada vez             |
*/

/*
Causas probables del degradado de rendimiento
1. Acumulación de #define dinámicos en pState
Cada vez que el texto preprocesado contiene directivas #define, #translate o #command
implícitas, estas se añaden a las tablas internas del estado. Con cada llamada,
el motor del preprocesador tiene que recorrer una lista de reglas que crece
progresivamente para encontrar coincidencias. El costo es O(n × reglas) donde n
aumenta con cada iteración.
​

2. Buffer interno que crece sin liberarse
hb_pp_parseLine trabaja sobre buffers internos del pState. Si el estado guarda
historial de líneas procesadas, buffers de expansión de macros o tokens intermedios,
la memoria consumida crece y provoca más presión sobre el heap y posibles fallos
de caché de CPU.

La solución: usar __pp_Reset

Siempre hemos de hacer esta secuencia:

FUNCTION MiFuncion( cCode )
   LOCAL cResult

   // Reset: vuelve a std.ch limpio, descarta acumulados anteriores
   __pp_Reset( s_hPP )

   // Re-aplicar tus reglas (son pocas, es rápido)
   __pp_AddRule( s_hPP, "#define MAX 100" )
   __pp_AddRule( s_hPP, "#translate DOBLE( <n> ) => ( <n> * 2 )" )

   // Procesar
   cResult := __pp_Process( s_hPP, cCode )

RETURN cResult

Podriamos hacer cada vez un __pp_Init() + aplicar reglas, però teoricament
__pp_init() te un cost de inicialitacio (es my parecido una mmanera que otra)

*/

THREAD STATIC __hPP

// ------------------------------------------------------------- //

FUNCTION UGetPPRules()

   LOCAL cOs := OS()

   IF __hPP  == nil

      __hPP  = __pp_Init()

   ENDIF

   __PP_Reset( __hPP )

   DO CASE

      CASE "Windows" $ cOs   ; __pp_Path( __hPP, "c:\harbour\include" )
      CASE "Linux" $ cOs    ; __pp_Path( __hPP, "~/harbour/include" )

   ENDCASE

   IF ! Empty( hb_GetEnv( "HB_INCLUDE" ) )

      __pp_Path( __hPP, hb_GetEnv( "HB_INCLUDE" ) )

   ENDIF

   __pp_AddRule( __hPP, "#xcommand ? [<explist,...>] => UWrite( '<br>' [,<explist>] )" )
   __pp_AddRule( __hPP, "#xcommand ?? [<explist,...>] => UWrite( [<explist>] )" )

   __pp_AddRule( __hPP, "#xcommand TRY  => BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }" )
   __pp_AddRule( __hPP, "#xcommand CATCH [<!oErr!>] => RECOVER [USING <oErr>] <-oErr->" )
   __pp_AddRule( __hPP, "#xcommand FINALLY => ALWAYS" )
   __pp_AddRule( __hPP, "#xtranslate Throw( <oErr> ) => ( Eval( ErrorBlock(), <oErr> ), Break( <oErr> )" )

   // [RAW]: optional marker for hbformat, invisible at runtime (consumed but not referenced)
   __pp_AddRule( __hPP, "#xcommand BLOCK <into:TO,INTO> <o> [RAW] [ PARAMS [<v1>] [,<vn>] ] " + ;
      "=> #pragma __cstream|<o>+= " + ;
      "HIX_Block( %s [,<(v1)>][+','+<(vn)>] [, @<v1>][, @<vn>] )"  )

   __pp_AddRule( __hPP, "#xcommand BLOCK <into:TO,INTO> <o> [RAW] => #pragma __cstream|<o> += %s" )


   RETU __hPP

// ------------------------------------------------------------- //

// Preamble de reglas HIX que se anteponen al codigo del usuario.
// Unico paso de compilacion (.T.) — el compilador Harbour resuelve
// hbclass.ch y demas includes sin doble-preprocessing.

STATIC FUNCTION _HixPreamble()
RETURN ;
      "#xcommand TRY  => BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }" + hb_eol() + ;
      "#xcommand CATCH [<!oErr!>] => RECOVER [USING <oErr>] <-oErr->" + hb_eol() + ;
      "#xcommand FINALLY => ALWAYS" + hb_eol() + ;
      "#xtranslate Throw( <oErr> ) => ( Eval( ErrorBlock(), <oErr> ), Break( <oErr> ) )" + hb_eol() + ;
      "#xcommand BLOCK <into:TO,INTO> <o> [RAW] [ PARAMS [<v1>] [,<vn>] ] => " + ;
      "#pragma __cstream|<o>+= HIX_Block( %s [,<(v1)>][+','+<(vn)>] [, @<v1>][, @<vn>] )" + hb_eol() + ;
      "#xcommand BLOCK <into:TO,INTO> <o> [RAW] => #pragma __cstream|<o> += %s" + hb_eol() + ;
      "#xcommand ?  [<explist,...>] => UEcho( '<br>' [,<explist>] )" + hb_eol() + ;
      "#xcommand ?? [<explist,...>] => UEcho( [<explist>] )" + hb_eol()

// ------------------------------------------------------------- //
// Cuenta las lineas del preamble para compensar el offset de
// numero de linea que introduce en el codigo compilado.
FUNCTION HIX_PreambleLines()

   STATIC snLines := -1
   LOCAL cPre, i, n

   IF snLines == -1

      cPre := _HixPreamble()
      n := 0

      FOR i := 1 TO Len( cPre )

         IF SubStr( cPre, i, 1 ) == Chr( 10 )

            n++

         ENDIF

      NEXT

      snLines := n

   ENDIF

RETURN snLines

// ------------------------------------------------------------- //

FUNCTION HIX_CompileFile( cPath )

   LOCAL oHrb, oError, cCode, aArgs
   LOCAL cOs      := OS()
   LOCAL cHBHeader := ''
   LOCAL cHBInclude, cUserFlags

   l( "CompileFile: " + cPath )

   cCode := hb_MemoRead( cPath )

   IF Empty( cCode )

      lw( "CompileFile: fichero no existe o vacio - " + cPath )
      RETURN NIL

   ENDIF

   DO CASE

      CASE "Windows" $ cOs ; cHBHeader := "c:\harbour\include"
      CASE "Linux" $ cOs   ; cHBHeader := "~/harbour/include"

   ENDCASE

   cHBInclude := hb_GetEnv( "HB_INCLUDE" )
   cUserFlags := hb_GetEnv( "HB_USER_PRGFLAGS" )

   // Build arg list filtering empty strings — hb_CompileFromBuf treats ""
   // as an empty filename and throws "Invalid filename ''"
   aArgs := { _HixPreamble() + cCode, .T., "-n", "-q2" }
   IF ! Empty( cHBHeader )  ; AAdd( aArgs, "-I" + cHBHeader ) ; ENDIF
   AAdd( aArgs, "-I" + HIX_GetRootAbsolute() )
   IF ! Empty( cHBInclude ) ; AAdd( aArgs, "-I" + cHBInclude ) ; ENDIF
   IF ! Empty( cUserFlags ) ; AAdd( aArgs, cUserFlags ) ; ENDIF

   TRY

      // El preamble desplaza las lineas del .prg del usuario por
      // HIX_PreambleLines(). Harbour ignora las directivas #line de
      // entrada (ppcore.c:5407), por lo que la compensacion se hace en
      // runtime desde HIX_Trace_Out via HIX_LoaderIsUserFunc().
      oHrb := hb_ExecFromArray( "hb_CompileFromBuf", aArgs )

   CATCH oError
      oError:filename := cPath

   END

   IF Empty( oHrb )

      lw( "CompileFile: compilacion fallida - " + cPath )

      IF oError == NIL

         oError := HIX_NewError( "Compile error", "Dispatcher", 504, "CompileFile" )

      ENDIF

      HIX_Throw( oError )
      RETURN NIL

   ENDIF

RETURN oHrb
