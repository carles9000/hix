function TStates() 

	local oStates 	:= UDbf()

	oStates:cPath 	:= hb_dirbase() + UConfig( "paths", "data", "data" )
	oStates:cDbf 	   := 'states.dbf'
	oStates:cCdx	   := 'states.cdx'	
	oStates:cTag	   := 'name'					   	
	
	oStates:Open()	
		
return oStates 

// -------------------------------------------------- //
