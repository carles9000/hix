FUNCTION Main()

   LOCAL aRows := {}   

   USE 'data/customers.dbf' SHARED NEW 
   
   FOR n := 1 TO 10
      
      GoTo( hb_RandInt( 1, 1000 ) )
   
      hRow := { 'recno' => recno(), 'first' => field->first , 'last' => field->last, 'age' => field->age }
      
      Aadd( aRows, hRow )
      
   NEXT                
   
RETURN UView( 'users.html', aRows )

