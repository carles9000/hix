PROCEDURE Main(...)

   LOCAL oReq  := URequest()
   LOCAL hUser := hb_HGetDef( oReq:hData, "user", { "name" => "Unknown", "roles" => {=>} } )
   LOCAL cName := hUser['name']
   LOCAL cKey, cRoles := '' 
   
   FOR EACH cKey IN hUser["roles"]
      cRoles += cKey:__enumKey() + " "
   NEXT
   
   IF Empty( cRoles ) ; cRoles := "(none)" ; ENDIF  
   
RETURN UView( 'main.html', cName, hUser, cRoles )

