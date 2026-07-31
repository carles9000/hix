/*-----------------------------------------------------------
  File ......: hix_firewall.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-05-03
  Description: IP firewall — blacklist/whitelist with CIDR and range support.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

// Estado global (configurado antes de Start(), leido desde _AcceptLoop)
STATIC saFilter := NIL
STATIC scMode   := "blacklist"
STATIC slActive := .F.

// ============================================================
// API publica
// ============================================================

// Configura el firewall. Llamar antes de THixServer:Start().
// cFilter: IPs/CIDRs/rangos separados por espacio; prefijo ! para excluir
// cMode: "blacklist" (bloquea los listados) | "whitelist" (permite solo los listados)
FUNCTION HIX_FirewallSetup( cFilter, cMode )

   LOCAL aOut

   hb_default( @cMode, "blacklist" )
   cMode := Lower( cMode )

   IF cMode != "blacklist" .AND. cMode != "whitelist"

      cMode := "blacklist"

   ENDIF

   slActive := .F.

   IF Empty( cFilter )

      RETURN NIL

   ENDIF

   IF HIX_ParseFirewallFilter( cFilter, @aOut, .T. )

      saFilter := aOut
      scMode   := cMode
      slActive := .T.

   ENDIF

RETURN NIL

// Desactiva el firewall (permite toda IP).
FUNCTION HIX_FirewallClear()

   saFilter := NIL
   slActive := .F.

RETURN NIL

// Verifica si cIP puede conectar. .T. = permitir, .F. = denegar.
FUNCTION HIX_FirewallCheck( cIP )

   LOCAL lInRanges

   IF ! slActive

      RETURN .T.

   ENDIF

   lInRanges := HIX_IsIPInRanges( cIP, saFilter )

   IF scMode == "whitelist"

      RETURN lInRanges

   ENDIF

RETURN ! lInRanges

// ============================================================
// Motor de parsing (publico para tests)
// ============================================================

// Convierte IP string a array numerico.
// IPv4: { nIP32bit }   IPv6: { w0, w1, w2, w3 } (4 words de 32 bit)
FUNCTION HIX_IPAddr2Num( cIP )

   LOCAL aMatch, nI, nIp, aWords, nHext, nWordIdx
   LOCAL n1, n2, n3, n4, cFullHex
   LOCAL cRegexIPv4 := "^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$"

   aMatch := hb_regex( cRegexIPv4, cIP )

   IF Len( aMatch ) == 5

      n1 := Val( aMatch[ 2 ] )
      n2 := Val( aMatch[ 3 ] )
      n3 := Val( aMatch[ 4 ] )
      n4 := Val( aMatch[ 5 ] )

      IF n1 <= 255 .AND. n2 <= 255 .AND. n3 <= 255 .AND. n4 <= 255

         nIP := ( ( ( n1 * 256 ) + n2 ) * 256 + n3 ) * 256 + n4
         RETURN { nIP }

      ENDIF

   ENDIF

   IF "::" $ cIP .OR. ":" $ cIP

      cFullHex := _HixFwExpandIPv6( cIP )

      IF Len( cFullHex ) == 32

         aWords := Array( 4 )

         FOR nI := 1 TO 8

            nHext    := _HixFwHexToNum( SubStr( cFullHex, ( nI - 1 ) * 4 + 1, 4 ) )
            nWordIdx := Int( ( nI + 1 ) / 2 )

            IF nI % 2 == 1

               aWords[ nWordIdx ] := nHext * 65536
            ELSE
               aWords[ nWordIdx ] += nHext

            ENDIF

         NEXT

         RETURN aWords

      ENDIF

   ENDIF

RETURN {}

// Parsea un string de filtro en un array ordenado de intervalos.
// Formato: "1.2.3.0/24 10.0.0.0/8 !10.0.1.0/24 192.168.1.1-192.168.1.50"
// .T. si el parse es correcto, .F. si hay errores de formato.
FUNCTION HIX_ParseFirewallFilter( cFilter, aFilterOut, lSorted )

   LOCAL cExpr, lDeny, aDeny, aTemp, aAllow
   LOCAL nI, cI, nPrefix, aAddr, aStart, aEnd, lIPv6, aMaskIP, aInterval

   hb_default( @lSorted, .T. )
   aFilterOut := NIL
   aDeny      := {}
   aTemp      := {}

   cFilter := StrTran( cFilter, ",", " " )

   FOR EACH cExpr IN hb_ATokens( cFilter, " " )

      IF Empty( cExpr ) ; LOOP ; ENDIF

      lDeny := ( Left( cExpr, 1 ) == "!" )

      IF lDeny ; cExpr := SubStr( cExpr, 2 ) ; ENDIF

      IF ( nI := At( "/", cExpr ) ) > 0

         cI    := SubStr( cExpr, nI + 1 )
         cExpr := Left( cExpr, nI - 1 )
         aAddr := HIX_IPAddr2Num( cExpr )

         IF Empty( aAddr ) ; RETURN .F. ; ENDIF

         lIPv6 := ( Len( aAddr ) == 4 )

         IF "." $ cI

            aMaskIP := HIX_IPAddr2Num( cI )

            IF Empty( aMaskIP ) ; RETURN .F. ; ENDIF

            IF ! _HixFwIsValidNetmask( aMaskIP[ 1 ] ) ; RETURN .F. ; ENDIF

            nPrefix := _HixFwBitCount( aMaskIP[ 1 ] )
         ELSE
            nPrefix := Val( cI )

         ENDIF

         IF lIPv6 .AND. ( nPrefix < 0 .OR. nPrefix > 128 ) ; RETURN .F. ; ENDIF

         IF ! lIPv6 .AND. ( nPrefix < 0 .OR. nPrefix > 32  ) ; RETURN .F. ; ENDIF

         aStart := _HixFwApplyMask( aAddr, nPrefix, lIPv6 )
         aEnd   := _HixFwApplyInvMask( aAddr, nPrefix, lIPv6 )

      ELSEIF ( nI := At( "-", cExpr ) ) > 0
         aStart := HIX_IPAddr2Num( Left( cExpr, nI - 1 ) )
         aEnd   := HIX_IPAddr2Num( SubStr( cExpr, nI + 1 ) )

         IF Empty( aStart ) .OR. Empty( aEnd ) ; RETURN .F. ; ENDIF

         IF ! _HixFwCompareIPs( aStart, "<=", aEnd ) ; RETURN .F. ; ENDIF

      ELSE
         aStart := HIX_IPAddr2Num( cExpr )

         IF Empty( aStart ) ; RETURN .F. ; ENDIF

         aEnd := AClone( aStart )

      ENDIF

      IF lDeny

         AAdd( aDeny, { aStart, aEnd } )
      ELSE
         aInterval := { "type" => IIF( Len( aStart ) == 1, "v4", "v6" ), ;
            "start" => aStart, "end" => aEnd }
         AAdd( aTemp, aInterval )

      ENDIF

   NEXT

   ASort( aTemp, , , {| x, y | _HixFwCompareIPs( x[ "start" ], "<", y[ "start" ] ) } )
   aAllow     := _HixFwMergeIntervals( aTemp )
   aAllow     := _HixFwSubtractIntervals( aAllow, aDeny )
   aFilterOut := aAllow

RETURN .T.

// Verifica si cIP cae dentro de algun intervalo del filtro parseado.
FUNCTION HIX_IsIPInRanges( cIP, aFilter )

   LOCAL aIP, nI, x

   aIP := HIX_IPAddr2Num( cIP )

   IF Empty( aIP ) .OR. Empty( aFilter )

      RETURN .F.

   ENDIF

   FOR nI := 1 TO Len( aFilter )

      x := aFilter[ nI ]

      IF Len( aIP ) == Len( x[ "start" ] ) .AND. ;
            _HixFwCompareIPs( aIP, ">=", x[ "start" ] ) .AND. ;
            _HixFwCompareIPs( aIP, "<=", x[ "end" ] )

         RETURN .T.

      ENDIF

   NEXT

RETURN .F.

// ============================================================
// Funciones internas (STATIC)
// ============================================================

// Convierte string hex (sin "0x") a numero. Val() no soporta hex en Harbour.
STATIC FUNCTION _HixFwHexToNum( cHex )

   LOCAL nVal, nI, c, nDigit

   nVal := 0

   FOR nI := 1 TO Len( cHex )

      c := Upper( SubStr( cHex, nI, 1 ) )

      IF c >= "0" .AND. c <= "9"

         nDigit := Asc( c ) - Asc( "0" )
      ELSEIF c >= "A" .AND. c <= "F"
         nDigit := Asc( c ) - Asc( "A" ) + 10
      ELSE
         RETURN 0

      ENDIF

      nVal := nVal * 16 + nDigit

   NEXT

RETURN nVal

// Expande IPv6 comprimido a 32 chars hex (sin separadores)
STATIC FUNCTION _HixFwExpandIPv6( cIP )

   LOCAL aParts, aLeft, aRight, cFull, nI, nColonPos, nZerosNeeded, cPart

   aLeft  := {}
   aRight := {}
   cFull  := ""

   IF "::" $ cIP

      nColonPos := At( "::", cIP )

      IF nColonPos > 1

         aLeft := hb_ATokens( Left( cIP, nColonPos - 1 ), ":" )

      ENDIF

      IF nColonPos + 1 < Len( cIP )

         aRight := hb_ATokens( SubStr( cIP, nColonPos + 2 ), ":" )

      ENDIF

      nZerosNeeded := 8 - Len( aLeft ) - Len( aRight )

      IF nZerosNeeded < 0 ; RETURN "" ; ENDIF

      aParts := AClone( aLeft )

      FOR nI := 1 TO nZerosNeeded

         AAdd( aParts, "0" )

      NEXT

      AEval( aRight, {| x | AAdd( aParts, x ) } )
   ELSE
      aParts := hb_ATokens( cIP, ":" )

   ENDIF

   IF Len( aParts ) != 8 ; RETURN "" ; ENDIF

   FOR EACH cPart IN aParts

      cPart := Upper( AllTrim( cPart ) )

      IF Len( cPart ) > 4 ; RETURN "" ; ENDIF

      cFull += Right( "0000" + cPart, 4 )

   NEXT

RETURN cFull

// Aplica mascara de red: devuelve la network address del prefijo
STATIC FUNCTION _HixFwApplyMask( aIP, nPrefix, lIPv6 )

   LOCAL aMasked, nWords, nBitsInWord, nHostBits, nNetMask, nWord

   aMasked := AClone( aIP )
   nWords  := IIF( lIPv6, 4, 1 )

   FOR nWord := 1 TO nWords

      nBitsInWord := Max( 0, Min( nPrefix, 32 ) )

      IF nBitsInWord == 0

         aMasked[ nWord ] := 0
      ELSEIF nBitsInWord < 32
         nHostBits      := 32 - nBitsInWord
         nNetMask       := 0xFFFFFFFF - ( hb_bitShift( 1, nHostBits ) - 1 )
         aMasked[ nWord ] := hb_bitAnd( aIP[ nWord ], nNetMask )

      ENDIF

      nPrefix -= 32

   NEXT

RETURN aMasked

// Aplica mascara invertida: devuelve el broadcast/ultimo address del prefijo
STATIC FUNCTION _HixFwApplyInvMask( aIP, nPrefix, lIPv6 )

   LOCAL aEnd, nWords, nBitsOff, nFreeBits, nWord, nMask

   aEnd    := AClone( aIP )
   nWords  := IIF( lIPv6, 4, 1 )
   nBitsOff := IIF( lIPv6, 128 - nPrefix, 32 - nPrefix )

   FOR nWord := nWords TO 1 STEP -1

      nFreeBits := Max( 0, Min( nBitsOff, 32 ) )

      IF nFreeBits == 32

         aEnd[ nWord ] := 0xFFFFFFFF
      ELSEIF nFreeBits > 0
         nMask       := hb_bitShift( 1, nFreeBits ) - 1
         aEnd[ nWord ] := hb_bitOr( aEnd[ nWord ], nMask )

      ENDIF

      nBitsOff -= 32

   NEXT

RETURN aEnd

// Compara dos IPs multi-word. cOp: "==", "<", "<=", ">", ">=", "!="
STATIC FUNCTION _HixFwCompareIPs( aIP1, cOp, aIP2 )

   LOCAL i, nCmp

   nCmp := 0

   IF Len( aIP1 ) != Len( aIP2 ) ; RETURN .F. ; ENDIF

   FOR i := 1 TO Len( aIP1 )

      IF aIP1[ i ] < aIP2[ i ]

         nCmp := -1
         EXIT
      ELSEIF aIP1[ i ] > aIP2[ i ]
         nCmp := 1
         EXIT

      ENDIF

   NEXT

   DO CASE

      CASE cOp == "==" .OR. cOp == "="  ; RETURN nCmp == 0
      CASE cOp == "<"                    ; RETURN nCmp < 0
      CASE cOp == "<="                   ; RETURN nCmp <= 0
      CASE cOp == ">"                    ; RETURN nCmp > 0
      CASE cOp == ">="                   ; RETURN nCmp >= 0
      CASE cOp == "!=" .OR. cOp == "<>" ; RETURN nCmp != 0

   ENDCASE

RETURN .F.

// Merge de intervalos adyacentes o solapados (lista ya ordenada)
STATIC FUNCTION _HixFwMergeIntervals( aIntervals )

   LOCAL aMerged, nI, aCurrStart, aCurrEnd, cType, aInt

   aMerged := {}

   IF Empty( aIntervals ) ; RETURN aMerged ; ENDIF

   aCurrStart := aIntervals[ 1 ][ "start" ]
   aCurrEnd   := aIntervals[ 1 ][ "end" ]
   cType      := aIntervals[ 1 ][ "type" ]

   FOR nI := 2 TO Len( aIntervals )

      aInt := aIntervals[ nI ]

      IF _HixFwAdjacentOrOverlap( aCurrEnd, aInt[ "start" ] )

         aCurrEnd := _HixFwMaxEnd( aCurrEnd, aInt[ "end" ] )
      ELSE
         AAdd( aMerged, { "type" => cType, "start" => aCurrStart, "end" => aCurrEnd } )
         aCurrStart := aInt[ "start" ]
         aCurrEnd   := aInt[ "end" ]
         cType      := aInt[ "type" ]

      ENDIF

   NEXT

   AAdd( aMerged, { "type" => cType, "start" => aCurrStart, "end" => aCurrEnd } )

RETURN aMerged

// Substrae los rangos denegados (aDenies) de los permitidos (aAllows)
STATIC FUNCTION _HixFwSubtractIntervals( aAllows, aDenies )

   LOCAL aResult, aTempSubs, xAllow, xDeny
   LOCAL aSubEnd, aRemainingStart, aRemainingEnd

   aResult := {}

   IF Empty( aAllows ) .OR. Empty( aDenies ) ; RETURN aAllows ; ENDIF

   FOR EACH xAllow IN aAllows

      aTempSubs      := {}
      aRemainingStart := AClone( xAllow[ "start" ] )
      aRemainingEnd   := AClone( xAllow[ "end" ] )

      FOR EACH xDeny IN aDenies

         IF Empty( aRemainingStart ) ; EXIT ; ENDIF

         IF ! _HixFwOverlapsWith( aRemainingStart, aRemainingEnd, xDeny[ 1 ], xDeny[ 2 ] )

            LOOP

         ENDIF

         IF _HixFwCompareIPs( aRemainingStart, "<", xDeny[ 1 ] )

            aSubEnd := _HixFwSubOne( xDeny[ 1 ] )

            IF ! Empty( aSubEnd ) .AND. _HixFwCompareIPs( aRemainingStart, "<=", aSubEnd )

               AAdd( aTempSubs, { "type" => xAllow[ "type" ], ;
                  "start" => AClone( aRemainingStart ), "end" => aSubEnd } )

            ENDIF

         ENDIF

         aRemainingStart := _HixFwAddOne( xDeny[ 2 ] )

         IF Empty( aRemainingStart ) .OR. _HixFwCompareIPs( aRemainingStart, ">", aRemainingEnd )

            aRemainingStart := {}
            EXIT

         ENDIF

      NEXT

      IF ! Empty( aRemainingStart ) .AND. _HixFwCompareIPs( aRemainingStart, "<=", aRemainingEnd )

         AAdd( aTempSubs, { "type" => xAllow[ "type" ], ;
            "start" => aRemainingStart, "end" => aRemainingEnd } )

      ENDIF

      AEval( aTempSubs, {| x | AAdd( aResult, x ) } )

   NEXT

RETURN _HixFwMergeIntervals( aResult )

STATIC FUNCTION _HixFwOverlapsWith( aS1, aE1, aS2, aE2 )
RETURN !( _HixFwCompareIPs( aE1, "<", aS2 ) .OR. _HixFwCompareIPs( aE2, "<", aS1 ) )

STATIC FUNCTION _HixFwAdjacentOrOverlap( aEnd1, aStart2 )
RETURN _HixFwCompareIPs( aStart2, "<=", _HixFwAddOne( aEnd1 ) )

STATIC FUNCTION _HixFwMaxEnd( aEnd1, aEnd2 )
RETURN IIF( _HixFwCompareIPs( aEnd1, "<", aEnd2 ), aEnd2, aEnd1 )

// Suma 1 a una IP multi-word. Devuelve {} en overflow.
STATIC FUNCTION _HixFwAddOne( aIP )

   LOCAL aNew, i, nCarry

   aNew   := AClone( aIP )
   nCarry := 1

   FOR i := Len( aNew ) TO 1 STEP -1

      aNew[ i ] += nCarry

      IF aNew[ i ] <= 0xFFFFFFFF

         nCarry := 0
         EXIT

      ENDIF

      aNew[ i ] := 0

   NEXT

   IF nCarry > 0 ; RETURN {} ; ENDIF

RETURN aNew

// Resta 1 a una IP multi-word. Devuelve {} en underflow.
STATIC FUNCTION _HixFwSubOne( aIP )

   LOCAL aNew, i, nBorrow

   aNew    := AClone( aIP )
   nBorrow := 1

   FOR i := Len( aNew ) TO 1 STEP -1

      IF aNew[ i ] >= nBorrow

         aNew[ i ] -= nBorrow
         nBorrow  := 0
         EXIT

      ENDIF

      aNew[ i ] := 0xFFFFFFFF

   NEXT

   IF nBorrow > 0 ; RETURN {} ; ENDIF

RETURN aNew

// Cuenta bits a 1 en un numero (para dotted netmask)
STATIC FUNCTION _HixFwBitCount( nNum )

   LOCAL nCount, nTemp

   nCount := 0
   nTemp  := nNum

   DO WHILE nTemp > 0

      nCount += hb_bitAnd( nTemp, 1 )
      nTemp   := Int( nTemp / 2 )

   ENDDO

RETURN nCount

// Valida que la mascara sea contigua (ej: 255.255.240.0 valida)
STATIC FUNCTION _HixFwIsValidNetmask( nMask )

   LOCAL nInverted, nPlusOne

   nInverted := hb_bitXor( nMask, 0xFFFFFFFF )
   nPlusOne  := nInverted + 1

RETURN hb_bitAnd( nInverted, nPlusOne ) == 0
