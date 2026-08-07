/*-----------------------------------------------------------
  File ......: {{ENTITY_LOWER}}.prg
  Author.....: {{AUTHOR}}
  Created....: {{DATE}}
  Version....: 1.0.0
  Description: {{ENTITY}} controller class. Methods correspond
               to CRUD actions and are wired to routes via
               "method@{{ENTITY_LOWER}}.prg" action strings.
 -----------------------------------------------------------*/

#include "hbclass.ch"

CLASS {{ENTITY}}

   METHOD New()   CONSTRUCTOR
   METHOD End()

   METHOD List()
   METHOD Show()
   METHOD Create()
   METHOD Store()
   METHOD Edit()
   METHOD Update()
   METHOD Delete()

ENDCLASS

METHOD New() CLASS {{ENTITY}}
RETURN Self

METHOD End() CLASS {{ENTITY}}
RETURN Self

METHOD List() CLASS {{ENTITY}}
   LOCAL aRows := {{ENTITY}}ModelList()
   LOCAL cRows := ""
   LOCAL hRow

   FOR EACH hRow IN aRows
      cRows += "<tr><td>" + hb_NToS( hRow[ "id" ] ) + "</td>" + ;
               "<td>" + hRow[ "name" ] + "</td>" + ;
               "<td><a href='/{{ENTITY_PLURAL_LOWER}}/" + hb_NToS( hRow[ "id" ] ) + "'>view</a></td></tr>"
   NEXT

RETURN USendView( "{{ENTITY_LOWER}}/list.view.html", cRows )

METHOD Show() CLASS {{ENTITY}}
   LOCAL nId  := Val( UParam( "id", "0" ) )
   LOCAL hRow := {{ENTITY}}ModelGet( nId )

   IF Empty( hRow )
      RETURN USendError( 404, "{{ENTITY}} not found" )
   ENDIF

RETURN USendView( "{{ENTITY_LOWER}}/show.view.html", hRow )

METHOD Create() CLASS {{ENTITY}}
RETURN USendView( "{{ENTITY_LOWER}}/edit.view.html", ;
   "create", ;
   { "id" => 0, "name" => "", "notes" => "" }, ;
   { => } )

METHOD Store() CLASS {{ENTITY}}
   LOCAL oVal := UValidatePost( { ;
      "name"  => "required|trim|string|max:100", ;
      "notes" => "trim|string|max:200"           ;
   } )
   LOCAL nId

   IF ! oVal:Make()
      RETURN USendView( "{{ENTITY_LOWER}}/edit.view.html", ;
         "create", ;
         { "id" => 0, "name" => oVal:Get("name"), "notes" => oVal:Get("notes") }, ;
         oVal:GetErrorsJson() )
   ENDIF

   nId := {{ENTITY}}ModelCreate( oVal:Get("name"), oVal:Get("notes") )
RETURN URedirect( "/{{ENTITY_PLURAL_LOWER}}/" + hb_NToS( nId ) )

METHOD Edit() CLASS {{ENTITY}}
   LOCAL nId  := Val( UParam( "id", "0" ) )
   LOCAL hRow := {{ENTITY}}ModelGet( nId )

   IF Empty( hRow )
      RETURN USendError( 404, "{{ENTITY}} not found" )
   ENDIF

RETURN USendView( "{{ENTITY_LOWER}}/edit.view.html", "edit", hRow, { => } )

METHOD Update() CLASS {{ENTITY}}
   LOCAL nId  := Val( UParam( "id", "0" ) )
   LOCAL hRow := {{ENTITY}}ModelGet( nId )
   LOCAL oVal

   IF Empty( hRow )
      RETURN USendError( 404, "{{ENTITY}} not found" )
   ENDIF

   oVal := UValidatePost( { ;
      "name"  => "required|trim|string|max:100", ;
      "notes" => "trim|string|max:200"           ;
   } )

   IF ! oVal:Make()
      hRow[ "name"  ] := oVal:Get( "name" )
      hRow[ "notes" ] := oVal:Get( "notes" )
      RETURN USendView( "{{ENTITY_LOWER}}/edit.view.html", ;
         "edit", hRow, oVal:GetErrorsJson() )
   ENDIF

   {{ENTITY}}ModelUpdate( nId, { "name" => oVal:Get("name"), "notes" => oVal:Get("notes") } )
RETURN URedirect( "/{{ENTITY_PLURAL_LOWER}}/" + hb_NToS( nId ) )

METHOD Delete() CLASS {{ENTITY}}
   LOCAL nId := Val( UParam( "id", "0" ) )

   IF nId > 0
      {{ENTITY}}ModelDelete( nId )
   ENDIF

RETURN URedirect( "/{{ENTITY_PLURAL_LOWER}}" )
