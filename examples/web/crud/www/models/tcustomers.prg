function TCustomers() 

	local oCustomers 	:= UDbf()

	oCustomers:cPath 	:= hb_dirbase() + UConfig( "paths", "data", "data" )
	oCustomers:cDbf 	   := 'customers.dbf'
	oCustomers:cCdx	   := 'customers.cdx'	
	oCustomers:cTag	   := 'first'					
   
	oCustomers:Hide( 'salary' )
	
	oCustomers:Open()	
		
return oCustomers 

// -------------------------------------------------- //
