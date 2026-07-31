/*-----------------------------------------------------------
  File ......: hix_block.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-07
  Description: Template block processor — evaluates <$ ... $> inline code blocks.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/
#INCLUDE 'hix_const.ch'

#DEFINE cStartBlock  '<$'
#DEFINE cEndBlock  '$>'

// ------------------------------------------------------------- //

FUNCTION HIX_Block( cCode, cParams, ... )

   LOCAL lReplaced := .F.
   LOCAL nStart, nEnd, cBlock, uValue, oError

   hb_default( @cParams, "" )

   TRY

      WHILE ( nStart := At( cStartBlock, cCode ) ) != 0 .AND. ;
            ( nEnd := At( cEndBlock, cCode ) ) != 0

         cBlock = SubStr( cCode, nStart + Len( cStartBlock ), nEnd - nStart - Len( cEndBlock ) )

         uValue := Eval( &( "{ |" + cParams + "| " + cBlock + " }" ), ... )

         cCode = SubStr( cCode, 1, nStart - 1 ) + ;
            UStr( uValue ) + ;
            SubStr( cCode, nEnd + Len( cEndBlock ) )

         lReplaced = .T.

      END

   CATCH oError

      HIX_Throw( oError )

   END

RETURN If( hb_PIsByRef( 1 ), lReplaced, cCode )

// ------------------------------------------------------------- //
