/*-----------------------------------------------------------
  File ......: api_customers.prg
  Author.....: Charly 9000
  Created....: 2026-08-18
  Modified...: 2026-08-18
  Version....: 1.0.0
  Description: Returns random customer records from the DBF
               as a JSON payload. Used by the /ws-test screen.
  Usage      : GET /api/customers?limit=5
  Notes      : limit is clamped to the 1..100 range.
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL aRows  := {}
   LOCAL hRow
   LOCAL n
   LOCAL nLimit := Val( UGet( 'limit', '5' ) )

   IF nLimit < 1 .OR. nLimit > 100
      nLimit := 5
   ENDIF

   USE 'data\customers.dbf' SHARED NEW

   FOR n := 1 TO nLimit

      GoTo( hb_RandInt( 1, 1000 ) )

      hRow := { 'recno' => RecNo(), ;
                'first' => AllTrim( field->first ), ;
                'last'  => AllTrim( field->last ),  ;
                'age'   => field->age }

      AAdd( aRows, hRow )

   NEXT

RETURN USendJson( { 'ok' => .T., 'count' => Len( aRows ), 'rows' => aRows } )
