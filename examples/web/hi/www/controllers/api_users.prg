/*-----------------------------------------------------------
  File ......: api_users.prg
  Author.....: Charly 9000
  Created....: 2026-08-18
  Modified...: 2026-08-18
  Version....: 1.0.0
  Description: JSON feed for the /users screen. Returns the same
               10 random rows that users.prg renders server side,
               so the table can be reloaded without a full page
               request.
  Usage      : GET /api/users
  Notes      : The work area is closed by the server when
               app.auto_close_dbf is on (hix.json).
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL aRows := {}
   LOCAL n

   USE 'data\customers.dbf' SHARED NEW

   FOR n := 1 TO 10

      GoTo( hb_RandInt( 1, 1000 ) )

      AAdd( aRows, { 'recno' => RecNo(),        ;
                     'first' => field->first,   ;
                     'last'  => field->last,    ;
                     'age'   => field->age      } )

   NEXT

RETURN USendJson( { 'ok'   => .T.,    ;
                    'rows' => aRows,  ;
                    'time' => Time()  } )
