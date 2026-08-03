/*-----------------------------------------------------------
  File ......: customer.prg
  Author.....: Charly 9000
  Created....: 2026-07-23
  Modified...: 2026-07-23
  Version....: 1.0.0
  Description: Customer resource controller. Consolidates all
               CRUD operations into a single class.

               List   GET    /customers              -- paginated list
               Get    GET    /customer/:id           -- single record
               Store  POST   /customer               -- create
               Update PUT    /customer/:id           -- full update
               Delete DELETE /customer/:id           -- toggle delete

  Usage      : Route actions:
                 controllers/list@customer.prg
                 controllers/get@customer.prg
                 controllers/store@customer.prg
                 controllers/update@customer.prg
                 controllers/delete@customer.prg
 -----------------------------------------------------------*/

#include "hbclass.ch"

CLASS CustomerController

   METHOD New()    CONSTRUCTOR
   METHOD End()
   METHOD List()
   METHOD Get()
   METHOD Store()
   METHOD Update()
   METHOD Delete()
   
   METHOD Destroy()

ENDCLASS


METHOD New() CLASS CustomerController
RETURN SELF


METHOD End() CLASS CustomerController
RETURN SELF


// ============================================================
// GET /customers
// ============================================================
METHOD List() CLASS CustomerController

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

   USendApi( { ;
      "items"  => aItems,     ;
      "page"   => nPage,      ;
      "limit"  => nLimit,     ;
      "total"  => nTotal,     ;
      "pages"  => nTotalPages ;
   } )

RETURN NIL


// ============================================================
// GET /customer/:id
// ============================================================
METHOD Get() CLASS CustomerController

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
      USendApiError( "CUSTOMER_NOT_FOUND", "No customer with id=" + hb_NToS( nId ), 404 )
      RETURN NIL
   ENDIF
   
   USendApi( hRow )

RETURN NIL


// ============================================================
// POST /customer
// ============================================================
METHOD Store() CLASS CustomerController

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
      USendApiError( "DB_INSERT_FAILED", cError, 500 )
      RETURN NIL
   ENDIF

   oCust:GetRecno( nRecno, @hRow )
   hRow[ "recno" ] := nRecno
   

   USendApi( hRow, 201 )

RETURN NIL


// ============================================================
// PUT /customer/:id
// ============================================================
METHOD Update() CLASS CustomerController

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
      USendApiError( "CUSTOMER_NOT_FOUND", "No customer with id=" + hb_NToS( nId ), 404 )
      RETURN NIL
   ENDIF

   IF ! oCust:Update( nId, hFields, @cError )      
      USendApiError( "DB_UPDATE_FAILED", cError, 500 )
      RETURN NIL
   ENDIF

   oCust:GetRecno( nId, @hRow )
   
   USendApi( hRow )

RETURN NIL


// ============================================================
// DELETE /customer/:id
// ============================================================
METHOD Delete() CLASS CustomerController

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
      USendApiError( "CUSTOMER_NOT_FOUND", "No customer with id=" + hb_NToS( nId ), 404 )
      RETURN NIL
   ENDIF

   IF ! oCust:Delete( nId, .T., @lIsDeleted )
      oCust:Close()
      USendApiError( "DB_DELETE_FAILED", "Could not toggle delete on id=" + hb_NToS( nId ), 500 )
      RETURN NIL
   ENDIF  

   cAction := iif( lIsDeleted, "deleted", "recalled" )

   USendApi( { "id" => nId, "deleted" => lIsDeleted, "action" => cAction } )

RETURN NIL

METHOD Destroy() CLASS CustomerController
   
   DbCloseAll()
   
RETURN NIL 

#include '/models/tcustomers.prg'
