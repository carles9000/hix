/*-----------------------------------------------------------
  File ......: customer/list.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 1.0.0
  Description: GET /customers -- paginated list with optional
               full-text search on FIRST and LAST fields.
               Requires MyWsGuardScope + scope customers:read.
  Usage      : GET /customers
               GET /customers?page=2&limit=20
               GET /customers?q=john
               Authorization: Bearer <token>
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL oCust, aItems, aAll, nTotalPages, nTotal, cQUp, nFrom, nTo, nI
   LOCAL cQ     := AllTrim( UGet( "q", "" ) )
   LOCAL nPage  := Max( 1, Val( UGet( "page",  "1"  ) ) )
   LOCAL nLimit := Min( 100, Max( 1, Val( UGet( "limit", "20" ) ) ) )

   oCust := TCustomers()

   IF oCust == NIL
      USendApiError( "DB_UNAVAILABLE", "Customers database is not available", 500 )
      RETURN NIL
   ENDIF

   IF Empty( cQ )

      aItems      := oCust:Page( nPage, nLimit, NIL, @nTotalPages )
      nTotal      := oCust:Count()

   ELSE

      cQUp        := Upper( cQ )
      aAll        := oCust:LoadAll( NIL, NIL, NIL, ;
                        {|a| Upper( AllTrim( (a)->( FieldGet( FieldPos("FIRST") ) ) ) ) $ cQUp .OR. ;
                             Upper( AllTrim( (a)->( FieldGet( FieldPos("LAST")  ) ) ) ) $ cQUp } )
      nTotal      := Len( aAll )
      nTotalPages := Int( ( nTotal + nLimit - 1 ) / nLimit )
      IF nTotalPages == 0
         nTotalPages := 1
      ENDIF
      nPage       := Min( nPage, nTotalPages )
      nFrom       := ( nPage - 1 ) * nLimit + 1
      nTo         := Min( nFrom + nLimit - 1, nTotal )
      aItems      := {}
      FOR nI := nFrom TO nTo
         AAdd( aItems, aAll[ nI ] )
      NEXT

   ENDIF

   oCust:Close()

   USendApi( { ;
      "items"  => aItems,      ;
      "page"   => nPage,       ;
      "limit"  => nLimit,      ;
      "total"  => nTotal,      ;
      "pages"  => nTotalPages  ;
   } )

RETURN NIL

#include '/models/tcustomers.prg'
