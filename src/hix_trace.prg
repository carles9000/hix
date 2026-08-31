/*-----------------------------------------------------------
  File ......: hix_trace.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-04-21
  Description: Compile-time trace macros and TRY/CATCH/FINALLY preprocessor
               definitions.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#DEFINE CRLF             (CHR(13)+CHR(10))
#DEFINE DEPTH_LEVEL   10

#XCOMMAND DEFAULT <v1> TO <x1> [, <vn> TO <xn> ] ;
      => IF < v1 > == NIL ; < v1 > := < x1 > ; END[ ; IF < vn > == NIL ; < vn > := < xn > ; END ]

#XCOMMAND TRY  => BEGIN SEQUENCE WITH {| oErr | Break( oErr ) }
#XCOMMAND CATCH [<!oErr!>] => RECOVER [USING <oErr>] <-oErr->
#XCOMMAND FINALLY => ALWAYS


FUNCTION _d( ... )

#IFDEF __PLATFORM__WINDOWS
   RETU _HixTraceEmit( HIX_Trace_Out( 'dbg', ... ) )
#ELSE
   RETU TraceLog( HIX_Trace_Out( 'dbg', ... ) )
#ENDIF


// --------------------------------------------------------- //

FUNCTION _t( ... )

#IFDEF __PLATFORM__WINDOWS

   RETU _HixTraceEmit( HIX_Trace_Out( 'trace', ... ) )
#ELSE
   RETU TraceLog( HIX_Trace_Out( 'trace', ... ) )
#ENDIF

// --------------------------------------------------------- //
// WAPI_OutputDebugString on Windows silently drops messages
// larger than ~4KB. Split on CRLF and emit chunk by chunk so
// dumping a full boot log hash / large structure works.
STATIC FUNCTION _HixTraceEmit( cText )

   LOCAL cLine

   IF Empty( cText )
      RETURN NIL
   ENDIF

#IFDEF __PLATFORM__WINDOWS
   FOR EACH cLine IN hb_ATokens( cText, CRLF )
      IF ! Empty( cLine )
         WAPI_OutputDebugString( cLine + CRLF )
      ENDIF
   NEXT
#ELSE
   FOR EACH cLine IN hb_ATokens( cText, CRLF )
      IF ! Empty( cLine )
         TraceLog( cLine )
      ENDIF
   NEXT
#ENDIF

RETURN NIL


// --------------------------------------------------------- //

FUNCTION _w( ... )

   RETU HIX_Trace_Out( 'web', ... )

// --------------------------------------------------------- //

FUNCTION _c( ... )   // Console

   RETU HIX_Trace_Out( 'dbg', ... )

// --------------------------------------------------------- //

STATIC FUNCTION HIX_Trace_Out( cOut, ... )

   LOCAL cLine  := ''
   LOCAL nParam  := PCount()
   LOCAL nI, cCaller, nLine

   FOR nI := 2 TO nParam

      DO CASE

         CASE cOut == 'dbg'

         IF alltrim( procname( 2 ) ) == '(b)UHTTPD2'
            cCaller := procname( 4 )
            nLine   := procline( 4 )
         ELSE
            cCaller := procname( 2 )
            nLine   := procline( 2 )
         ENDIF

         // Compensacion del offset del preamble para funciones cargadas
         // via hb_hrbLoad (loaders/*.prg). Harbour ignora #line, asi que
         // restamos aqui las lineas que _HixPreamble antepone al codigo.
         IF HIX_LoaderIsUserFunc( cCaller )
            nLine := Max( nLine - HIX_PreambleLines(), 1 )
         ENDIF

         cLine += cCaller + ' (' + ltrim( str( nLine ) ) + ') '
         cLine += 'Type (' + valtype( pValue( nI ) ) + ') ' + HIX_Trace_ValTo( pValue( nI ), NIL, NIL, cOut ) + CRLF

         CASE cOut == 'trace'
            cLine += HIX_Trace_ValTo( pValue( nI ), NIL, NIL, cOut ) + CRLF

         CASE cOut == 'web'
            cLine += HIX_Trace_ValTo( pValue( nI ), NIL, NIL, cOut ) + '<br>'



      ENDCASE

   NEXT

   RETU cLine

// --------------------------------------------------------- //

STATIC FUNCTION HIX_Trace_ValTo( u, nTab, nDeep, cOut )

   STATIC _i   := 0

   LOCAL cType  := ValType( u )
   LOCAL cResult  := ""
   LOCAL hValue

   DEFAULT nTab TO  0
   DEFAULT nDeep TO  0
   DEFAULT cOut TO  'dbg'

   nTab++



   DO CASE

      CASE cType == "C" .OR. cType == "M"
         cResult := u

      CASE cType == "D"  ; cResult := DToC( u )
      CASE cType == "L"   ; cResult := If( u, ".T.", ".F." )
      CASE cType == "N"  ; cResult := AllTrim( Str( u ) )
      CASE cType == "A"  ; cResult := HIX_Trace_ArrayTo( @nTab, u, @nDeep, cOut )
      CASE cType == "O"

         hValue  := HIX_Trace_ObjToHash( u )

         cResult  := HIX_Trace_HashTo( @nTab, hValue, @nDeep, cOut )

// cResult  := MH_Valtochar( hValue )

      CASE cType == "P"    ; cResult := hb_NumToHex( u )
      CASE cType == "S"  ; cResult := "(Symbol)"
      CASE cType == "H"

         cResult := HIX_Trace_HashTo( @nTab, u, @nDeep, cOut )

      CASE cType == "T"  ; cResult := hb_tstostr( u )
      CASE cType == "U"  ; cResult := "nil"

      OTHERWISE
         cResult := "Type not supported: " + cType

   ENDCASE


   RETU cResult

// --------------------------------------------------------- //

STATIC FUNCTION HIX_Trace_HashTo( nTab, u, nDeep, cOut )

   LOCAL cResult  := ''
   LOCAL nLen  := len( u )
   LOCAL n, aPair
   LOCAL cSep, cJump

   DEFAULT cOut TO  'dbg'

   DO CASE

      CASE cOut == 'dbg'
         cSep := ' '
         cJump := CRLF
      CASE cOut == 'trace'
         cSep := ' '
         cJump := CRLF
      CASE cOut == 'web'
         cSep := '&nbsp;'
         cJump := '<br>'

   ENDCASE

   nDeep++

   IF nDeep > DEPTH_LEVEL

      RETU '<*** Too many levels ***>'

   ENDIF


   IF nLen > 0

      cResult := '{' + cJump

      FOR n := 1 TO nLen

         aPair := HB_HPairAt( u, n )


         cResult += Replicate( cSep, nTab * 3 ) + 'Key: ' + aPair[ 1 ]  + ' (' + valtype( aPair[ 2 ] ) + ') => ' + HIX_Trace_ValTo( aPair[ 2 ], nTab, @nDeep, cOut ) + cJump


      NEXT

      cResult += Replicate( cSep, --nTab * 3 ) + '}'

   ELSE

      cResult := '{=>}'

   ENDIF

   nDeep--

   RETU cResult

// --------------------------------------------------------- //

STATIC FUNCTION HIX_Trace_ArrayTo( nTab, u, nDeep, cOut )

   LOCAL cResult  := ''
   LOCAL nLen  := len( u )
   LOCAL n
   LOCAL cSep, cJump

   DEFAULT cOut TO  'dbg'

   DO CASE

      CASE cOut == 'dbg'
         cSep := ' '
         cJump := CRLF
      CASE cOut == 'trace'
         cSep := ' '
         cJump := CRLF
      CASE cOut == 'web'
         cSep := '&nbsp;'
         cJump := '<br>'

   ENDCASE

   nDeep++

   IF nDeep > DEPTH_LEVEL

      RETU '<*** Too many levels ***>'

   ENDIF


   IF nLen > 0

      cResult := '{' + cJump

      FOR n := 1 TO nLen

         cResult += Replicate( cSep, nTab * 3 ) + 'Type (' + valtype( u[ n ] ) + ') ' + HIX_Trace_ValTo( u[ n ], nTab, @nDeep, cOut ) + cJump

      NEXT

      cResult += Replicate( cSep, --nTab * 3 ) + '}'

   ELSE

      cResult := '{}'

   ENDIF

   nDeep--

   RETU cResult

// --------------------------------------------------------- //

STATIC FUNCTION HIX_Trace_ObjToHash( o )

   LOCAL hObj  := { => }
   LOCAL hPairs  := { => }

   LOCAL aDatas, aParents
   LOCAL oError

   oError := nil



   try

      aDatas   := __objGetMsgList( o, .T. )
      aParents  := __ClsGetAncestors( o:ClassH )

      AEval( aParents, {| h, n | aParents[ n ] := __ClassName( h ) } )

      hObj[ "CLASS" ] := o:ClassName()
      hObj[ "FROM" ]  := aParents

      AEval( aDatas, {| cData | hPairs[ cData ] := __ObjSendMsg( o, cData ) } )

      hObj[ "DATAs" ]   := hPairs
      hObj[ "METHODs" ] := __objGetMsgList( o, .F. )

   catch oError

      hObj[ 'error' ] := 'Error HIX_Trace_ObjToHash'

   END


   RETU hObj

// --------------------------------------------------------- //

FUNCTION _stack()

   LOCAL nI := 2

   DO WHILE ! EMPTY( PROCNAME( ++nI ) )

      _d( PROCNAME( nI ) + "(" + LTRIM( STR( PROCLINE( nI ) ) ) + ")"  )

   ENDDO

   RETU NIL

// --------------------------------------------------------- //
