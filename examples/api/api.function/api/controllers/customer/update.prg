/*-----------------------------------------------------------
  File ......: customer/update.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 1.0.0
  Description: PUT /customer/:id -- update an existing customer.
               Requires MyWsGuardScope + scope customers:write.
  Usage      : PUT /customer/42
               Authorization: Bearer <token>
               Content-Type: application/json
               { "first":"john","last":"doe",... }
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL oVal, oCust, hRow, cError, nId, hFields

   oVal := UValidateParams( { "id" => { "required|number|min:1", "Id" } } )

   IF ! oVal:Make()
      USendApiError( "INVALID_ID", oVal:GetErrorsTxt(), 400 )
      RETURN NIL
   ENDIF

   nId := oVal:Get( "id" )

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

   IF ! oCust:GetRecno( nId, @hRow )
      oCust:Close()
      USendApiError( "CUSTOMER_NOT_FOUND", "No customer with id=" + hb_NToS( nId ), 404 )
      RETURN NIL
   ENDIF

   IF ! oCust:Update( nId, hFields, @cError )
      oCust:Close()
      USendApiError( "DB_UPDATE_FAILED", cError, 500 )
      RETURN NIL
   ENDIF

   oCust:GetRecno( nId, @hRow )
   oCust:Close()

   USendApi( hRow )

RETURN NIL

#include '/models/tcustomers.prg'
