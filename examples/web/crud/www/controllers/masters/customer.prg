#include 'hbclass.ch'	

//#xtranslate Throw( <oErr> ) => ( Eval( ErrorBlock(), <oErr> ), Break( <oErr> ) )

CLASS Customer

	//DATA lAuthorization	 INIT .t.

	METHOD New()			 CONSTRUCTOR 
	METHOD End() 
			
	
	METHOD Search() 
	METHOD Show() 
   METHOD Edit()
   METHOD Update() 
   METHOD Create() 
   METHOD Delete() 
   METHOD Store()
   
   
	METHOD Destroy() 
	
ENDCLASS 

// -------------------------------------------------------------- //

METHOD New() CLASS Customer

	_d( 'NEW() -->> ' + Self:ClassName() )	
	
RETU SELF 

// -------------------------------------------------------------- //

METHOD End() CLASS Customer
	
RETU SELF 

// -------------------------------------------------------------- //

METHOD Search() CLASS Customer

RETU UView( 'masters/customer/search.html' )

// -------------------------------------------------------------- //

METHOD Show() CLASS Customer

   LOCAL cId, hProduct
   LOCAL hrow := {=>}
   LOCAL hMessage := {=>}
   LOCAL oVal, oCustomers, oStates


   oVal := UValidateParams( { ;
      "id" => { "required|number|min:0", "Id",        "" } ;
   } )
   
   IF ! oVal:Make() .or. oVal:Get( 'id' ) == 0

      UFlash( "customer" ):Set( { "errors" => oVal:GetErrors(), "message" => "Error validacion",  "input" => oVal:Resume(), "type" => 'danger' } )
      RETURN URedirect( URoute( 'customer.search' ) )      
   ENDIF

   oCustomers := TCustomers()   
   
   lFound := oCustomers:GetRecno( oVal:Get( 'id'), @hRow, NIL , .T. )  // .T. == to String Web            

   if lFound 
      oStates := TStates()
      oStates:Seek( hRow[ 'state' ], nil, 'code' )	
      
      hRow[ 'state_txt' ] := oStates:FieldGet( 'name' )
   
      oFlash   := UFlash( 'customer' )
      
      hMessage[ 'type' ]      := oFlash:Get( 'type' )
      hMessage[ 'message' ]   := oFlash:Get( 'message' )
      
   else 
      hRow := oCustomers:Blank( .t. )
      hRow[ 'state_txt' ] := ''   
   endif     

RETU UView( 'masters/customer/show.html', lFound, hRow, hMessage )

// -------------------------------------------------------------- //
// "url": "/customer/:id" -> we need chek if :id number & > 0  
// "url": "/customer/:id([0-9]+)" -> we have a expression ! only numbers

METHOD Edit() CLASS Customer

   LOCAL oVal, oCustomers, oStates, lFound, oFlash
   LOCAL aStates := {}
   LOCAL hMessage := {=>}
   LOCAL hRow := {=>}

   oVal := UValidateParams( { "id" => { "required|number|min:0", "Id" }  })   

   IF ! oVal:Make()     
      RETU URedirect( URoute( 'customer.search' ) )      
   ENDIF

   
   // Recover data flash if it exist
      oFlash := UFlash('customer')

      hMessage[ 'type' ]      := oFlash:Get('type')
      hMessage[ 'message' ]   := oFlash:Get('message')
      hInput                  := oFlash:Get('input')
      hErrors                 := oFlash:Get('errors', {=>})    
   
   
   // Load state
      oStates     := TStates()   
      aStates     := oStates:LoadAll()   

   // Si existeix Input es que viene de una EDIT

   if !empty( hInput )         
      RETU UView( 'masters/customer/edit.html', 'edit', .T., hInput, aStates, hMessage, hErrors )        
   endif 
   
   oCustomers  := TCustomers() 
   
   
   // Si no hay input, es una simple edicion para editar. Buscaremos registro   

   lFound := oCustomers:GetRecno( oVal:Get( 'id'), @hRow, NIL , .T. )  // .T. == to String Web 
   
   if !lFound 
      hRow := oCustomers:Blank( .t. )
   endif 

   if hb_IsHash( hInput )
      hRow := hInput
   endif

   if empty( hErrors )
      hErrors := {=>}
   endif 

RETU UView( 'masters/customer/edit.html', 'edit', lFound, hRow, aStates, hMessage, hErrors )

// -------------------------------------------------------------- //

METHOD Create() CLASS Customer

   LOCAL oCustomers, oStates, oFlash, aStates, hRow
   LOCAL hMessage 	:= {=>}   
   LOCAL hErrors 	:= {=>}   

   // Load state
	oCustomers  := TCustomers() 
   oStates     := TStates()   
   aStates     := oStates:LoadAll()         

   oFlash := UFlash('customer')

   hMessage[ 'type' ]      := oFlash:Get('type')
   hMessage[ 'message' ]   := oFlash:Get('message')
   hInput                  := oFlash:Get('input')	
	hErrors                 := oFlash:Get('errors', {=>} ) 
	

	if ! empty( hInput )	
		hRow := hInput 		
	else		

		UFlash("customer"):Set( { "type" => 'primary', "message" => 'New customer...' }) 		
		hRow := oCustomers:Blank( .t. )	// .t. == to web string
	endif 


RETU UView( 'masters/customer/edit.html', 'create', .F., hRow, aStates, hMessage, hErrors )


// -------------------------------------------------------------- //

METHOD Update() CLASS Customer

   LOCAL cId   := UGetResource() // == _recno
   LOCAL oVal, nId, cError, lSuccess
   LOCAL o
   LOCAL hMessage := {=>}
   LOCAL oError
   LOCAL hResume
   LOCAL oCustomers, oStates
 
   // Validamos RESOURCE !
   
      // Hack Resource > Go to main !
         if empty( cId )
            retu URedirect( URoute( 'main' ) )                  
         endif 
      
      // Recover cResource       
         oVal  := UValidatorOne( 'Id', cId , "required|number|min:0" )
         
         IF oVal:Fails()
            retu URedirect( URoute( 'customer.search' ) ) 
         ENDIF   
      
         nId := oVal:Get() 

  
   // Validamos campos (Update).
   //
   // NOTA H8: _deleted NO va en las reglas — es un flag interno del DBF.
   // Se preserva del form via UPost para re-mostrar el estado en la vista
   // tras un fallo de validación, pero nunca se copia a DataFields().

      oVal  := UValidatePost( { ;
               "first"    	=> "required|string|max:20|field", ;
               "last"     	=> "required|string|max:20|field", ;
               "street"   	=> "required|string|max:30|field", ;
               "city"   	=> "required|string|max:30|field", ;
               "state"   	=> "required|string|max:2|field",;
               "zip"   	   => "required|string|max:10|field", ;
               "hiredate" 	=> "required|date|field", ;
               "married" 	=> "logic|field", ;
               "age" 		=> "required|numeric|max:70|field",;
               "notes"     => "string|field";
            }, { 'dummy' => 'upper|trim', 'first' => 'lower' } )


     if ! oVal:Make()

         hResume := oVal:Resume()
         hResume[ '_deleted' ] := UPost( '_deleted', .F. )

         UFlash("customer"):Set( { ;
            "type"   => 'danger',          ;
            "message" => 'Error validacion',;
            "errors" => oVal:GetErrors(),  ;
            "input"  => hResume            ;
         })

         retu URedirect( URoute( 'customer.edit', nId ) )

      endif

 
   // Open DataSource 
      oCustomers  := TCustomers() 
      oStates     := TStates()              
   
      lSuccess := oCustomers:Update( nId, oVal:DataFields(), @cError )

      if lSuccess

         UFlash("customer"):Set( { ;
            "type"    => 'success',          ;
            "message" => 'Customer ' + ltrim(str(nId)) + ' was updated!' ;
         })

         retu URedirect( URoute( 'customer.show', nId ) )

      else

         hResume := oVal:Resume()
         hResume[ '_deleted' ] := UPost( '_deleted', .F. )

         UFlash("customer"):Set( { ;
            "type"    => 'danger',         ;
            "message" => cError,           ;
            "errors"  => {=>},             ;
            "input"   => hResume           ;
         })

         retu URedirect( URoute('customer.edit', nId) )

      endif

RETU nil

// -------------------------------------------------------------- //

METHOD Delete() CLASS Customer

   LOCAL cId   := UGetResource() // == _recno
   LOCAL oVal, nId, cError, lSuccess
   LOCAL o
   LOCAL hMessage := {=>}
   LOCAL oError, lIsDeleted, cMessage
   LOCAL oCustomers
   LOCAL hRow := {=>}

   // Validamos RESOURCE !

      // Hack Resource > Go to main !
         if empty( cId )
            retu URedirect( URoute( 'main' ) )
         endif

      // Recover cResource
         oVal  := UValidatorOne( 'Id', cId , "required|number|min:0" )

         IF oVal:Fails()
            retu URedirect( URoute( 'customer.search' ) )
         ENDIF

         nId := oVal:Get()

   // Open DataSource
      oCustomers  := TCustomers()

      if ! oCustomers:GetRecno( nId, @hRow )

         UFlash("customer"):Set( { ;
            "type"    => 'warning',                                 ;
            "message" => 'Customer ' + ltrim(str(nId)) + ' not found' ;
         })

         retu URedirect( URoute( 'customer.search' ) )

      endif

      if oCustomers:Delete( nId, .T., @lIsDeleted  )

         if lIsDeleted
            cMessage := 'Recno was deleted'
         else
            cMessage := 'Recno was recall'
         endif

         UFlash("customer"):Set( { "type" => 'success', "message" => cMessage })

         retu URedirect(URoute('customer.edit', nId) )

      endif

RETU nil


// -------------------------------------------------------------- //

METHOD Store() CLASS Customer

   
   LOCAL oVal, nId, cError, lSuccess, nRecno
   LOCAL o 
   LOCAL hMessage := {=>}
   LOCAL oError
  
   // Validamos campos (Store).

      oVal  := UValidatePost( { ;
               "first"    	=> "required|string|max:20|field", ;
               "last"     	=> "required|string|max:20|field", ;
               "street"   	=> "required|string|max:30|field", ;
               "city"   	=> "required|string|max:30|field", ;
               "state"   	=> "required|string|max:2|field",;
               "zip"   	    => "required|string|max:10|field", ;
               "hiredate" 	=> "required|date|field", ;
               "married" 	=> "logic|field", ;
               "age" 		=> "required|numeric|max:70|field",;
               "notes"      => "string|field";
            }, { 'dummy' => 'upper|trim', 'first' => 'lower' } )


     if ! oVal:Make() 

         UFlash("customer"):Set( { ;
            "type"   => 'danger',          ;
            "message" => 'Error validacion',; 
            "errors" => oVal:GetErrors(),  ;
            "input"  => oVal:Resume()      ;
         })
   
         retu URedirect( URoute( 'customer.create' ) )

      endif 

 
   // Open DataSource 
      oCustomers  := TCustomers() 
      oStates     := TStates()              
   
      lSuccess := oCustomers:Insert( oVal:DataFields(), @cError, @nRecno )

      if lSuccess      
      
         UFlash("customer"):Set( { ;
            "type"   => 'success',          ;
            "message" => 'Customer ' + ltrim(str(nRecno)) + ' was created!';
         })    
         
         retu URedirect( URoute( 'customer.show', nRecno ) )    
         
      else 

         UFlash("customer"):Set( { ;
            "type"    => 'danger',         ;
            "message" => cError,           ;
            "errors"  => {=>},  ;
            "input"   => oVal:Resume()     ;
         })
         
         retu URedirect( URoute('customer.create' ) )     
         
      endif 

RETU nil 

// -------------------------------------------------------------- //

METHOD Destroy() CLASS Customer

   dbcloseall()

RETU nil 

// -------------------------------------------------------------- //

#include 'models/tcustomers.prg'
#include 'models/tstates.prg'
