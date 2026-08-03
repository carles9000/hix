/*-----------------------------------------------------------
  File ......: customer/store.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 1.0.0
  Description: POST /customer -- create a new customer record.
               Requires MyWsGuardScope + scope customers:write.
  Usage      : POST /customer
               Authorization: Bearer <token>
               Content-Type: application/json
               { "first":"john","last":"doe",... }
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL oVal, oCust, hRow, cError, nRecno, hFields

   oVal := UValidateOrFail( { ;
      "first"    => "required|string|maxlen:20|field", ;
      "last"     => "required|string|maxlen:20|field", ;
      "street"   => "required|string|maxlen:30|field", ;
      "city"     => "required|string|maxlen:30|field", ;
      "state"    => "required|string|maxlen:2|field",  ;
      "zip"      => "required|string|maxlen:10|field", ;
      "hiredate" => "required|string|maxlen:10|field", ;
      "married"  => "boolean|field",                   ;
      "age"      => "required|integer|min:0|max:120|field", ;
      "notes"    => "string|field"                     ;
   }, { "first" => "lower|trim", "last" => "lower|trim" } )

   IF oVal == NIL
      RETURN NIL
   ENDIF

   hFields := oVal:DataFields()

   IF HB_HHasKey( hFields, "hiredate" )
      hFields[ "hiredate" ] := hb_SToD( StrTran( hFields[ "hiredate" ], "-", "" ) )
   ENDIF

   oCust := TCustomers()

   IF oCust == NIL
      USendApiError( "DB_UNAVAILABLE", "Customers database is not available", 500 )
      RETURN NIL
   ENDIF

   IF ! oCust:Insert( hFields, @cError, @nRecno )
      oCust:Close()
      USendApiError( "DB_INSERT_FAILED", cError, 500 )
      RETURN NIL
   ENDIF

   oCust:GetRecno( nRecno, @hRow )
   hRow[ "recno" ] := nRecno
   oCust:Close()

   USendApi( hRow, 201 )

RETURN NIL

#include '/models/tcustomers.prg'
