/*-----------------------------------------------------------
  File ......: customer/delete.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 1.0.0
  Description: DELETE /customer/:id -- logical delete toggle.
               If active -> marks as deleted.
               If already deleted -> recalls (undeletes).
               Requires MyWsGuardScope + scope customers:delete.
  Usage      : DELETE /customer/42
               Authorization: Bearer <token>
 -----------------------------------------------------------*/

FUNCTION Main()

   LOCAL oVal, oCust, hRow, lIsDeleted, nId, cAction

   oVal := UValidateParams( { "id" => { "required|number|min:1", "Id" } } )

   IF ! oVal:Make()
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

   IF ! oCust:Delete( nId, .T., @lIsDeleted )
      oCust:Close()
      USendApiError( "DB_DELETE_FAILED", "Could not toggle delete on id=" + hb_NToS( nId ), 500 )
      RETURN NIL
   ENDIF

   oCust:Close()

   cAction := iif( lIsDeleted, "deleted", "recalled" )

   USendApi( { "id" => nId, "deleted" => lIsDeleted, "action" => cAction } )

RETURN NIL

#include '/models/tcustomers.prg'
