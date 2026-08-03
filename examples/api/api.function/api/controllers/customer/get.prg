/*-----------------------------------------------------------
  File ......: customer/get.prg
  Author.....: Charly 9000
  Created....: 2026-07-19
  Modified...: 2026-07-23
  Version....: 1.1.0
  Description: GET /customer/:id -- lookup by numeric ID.
               Requires MyWsGuardScope + scope customers:read.
  Usage      : GET /customer/1
               Authorization: Bearer <token>
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL nId, oCust, hRow, oVal

   oVal := UValidateParams( { ;
      "id" => { "required|number|min:1", "Id" } ;
   } )

   IF ! oVal:Make() .OR. oVal:Get( "id" ) == 0
      USendApiError( "INVALID_ID", oVal:GetErrorsTxt(), 400 )
      RETURN NIL
   ENDIF

   nId   := oVal:Get( "id" )
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

   oCust:Close()
   USendApi( hRow )

RETURN NIL

#include '/models/tcustomers.prg'
